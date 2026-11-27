import Foundation
import CoreBluetooth
import UIKit

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

struct LogLine: Identifiable {
    let id = UUID()
    let time: String
    let tag: String
    let text: String
}

/// 最近一次完整的命令交换，用来一眼看出「发的是什么、泵回了什么、错在哪」。
struct LastExchange {
    let cmd: Int
    let name: String
    let requestHex: String
    let cipherHex: String
    let responseHex: String
    let code: Int?
    let note: String
    let ms: Int
    let at: String
}

/// BLE 客户端 —— 对应 Android 的 IpeleBleClient。
///
/// 与原版一致：单条命令串行、800ms 最小间隔、6s 响应超时、
/// 超时不自动重发（输注命令重发等于重复给药）。
final class PumpClient: NSObject, ObservableObject {

    @Published var devices: [DiscoveredDevice] = []
    @Published var scanning = false
    @Published var connected = false
    @Published var connecting = false
    @Published var currentName = ""
    @Published var bluetoothState = "未初始化"
    @Published var remainingU: Double? = nil
    @Published var switchOn: Bool? = nil
    @Published var lastAck = "—"
    @Published var modelInfo = "—"
    @Published var snHint = "未设置（明文通信）"
    @Published var busy = false
    @Published var lastParsed: ParsedResponse? = nil
    @Published var logs: [LogLine] = []
    @Published var waterTest = false
    @Published var selfCheckText = ""
    @Published var verifyText = ""
    @Published var basalRateNow: Double? = nil
    @Published var basalText = "未读取"
    @Published var lastExchange: LastExchange? = nil
    @Published var lastNotifyRaw = ""

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var key: [UInt8]?
    private var sn: String = ""
    private var paddedEmpty = true

    private let assembler = FrameAssembler()
    private var seq: UInt8 = 0

    private var pendingCmd = 0
    private var pendingCB: ((Frame?) -> Void)?
    private var timeoutItem: DispatchWorkItem?
    private var txChunks: [Data] = []
    private var txIndex = 0
    private var lastSendAt = Date.distantPast
    private struct DoseEntry: Codable { let at: Date; let units: Double }
    private var doses: [DoseEntry] = []
    private let doseKey = "ipele.doses"
    private let lastDeviceKey = "ipele.lastPeripheral"
    private var connectTimer: DispatchWorkItem?

    // 超时计时改为「最后一包写完后」才开始；这之前用写通道看门狗兜底
    private var pendingRaw = 0
    private var pendingSeq = 0
    private var pendingTxHex = ""
    private var pendingCipherHex = ""
    private var pendingStartAt = Date()
    private var pendingFramesHex = ""
    private let logIO = DispatchQueue(label: "ipele.log.io", qos: .utility)
    private var pendingPayload: [UInt8] = []
    private var pendingPadded = true
    private var pendingAllow = true
    private var pendingCompletion: ((Frame?) -> Void)?
    private var timeoutArmed = false
    private var writeWatchdog: DispatchWorkItem?

    override init() {
        super.init()
        if let d = UserDefaults.standard.data(forKey: doseKey),
           let list = try? JSONDecoder().decode([DoseEntry].self, from: d) {
            doses = list
        }
        pruneDoses()
    }

    // ------------------------------------------------------------ 配置

    func configure(sn: String, paddedEmpty: Bool) {
        self.sn = sn.trimmingCharacters(in: .whitespacesAndNewlines)
        self.paddedEmpty = paddedEmpty
        if self.sn.isEmpty {
            key = nil
            snHint = "未设置（明文通信）"
            log("CFG", "未填序列号，按明文收发")
            return
        }
        do {
            key = try Crypto.keyFromSN(self.sn)
            let tail = String(self.sn.uppercased().suffix(8))
            snHint = "AES-128，密钥来自 SN 末 8 位 \(tail)"
            log("CFG", "已启用加密，密钥 = SN 末 8 位 \(tail)")
        } catch {
            key = nil
            snHint = "序列号无效：\(error.localizedDescription)"
            log("CFG", "序列号无效：\(error.localizedDescription)")
        }
    }

    var encrypted: Bool { key != nil }

    // ------------------------------------------------------------ 扫描 / 连接

    func startScan() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        }
        devices.removeAll()
        scanning = true
        if central?.state == .poweredOn {
            central?.scanForPeripherals(withServices: nil,
                                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        log("SYS", "开始扫描（不过滤 Service UUID，请从列表里选泵）")
    }

    func stopScan() {
        central?.stopScan()
        scanning = false
    }

    func connect(_ d: DiscoveredDevice) {
        guard let c = central else { return }
        stopScan()
        connecting = true
        currentName = d.name
        peripheral = d.peripheral
        d.peripheral.delegate = self
        c.connect(d.peripheral, options: nil)
        startConnectTimer()
        log("SYS", "连接 \(d.name) …（命令间隔 \(Proto.queueIntervalMs)ms，响应超时 \(Proto.responseTimeoutMs)ms）")
    }

    func disconnect() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        basalRateNow = nil
        basalText = "未读取"
        cleanup(reason: "主动断开")
    }

    private func startConnectTimer() {
        connectTimer?.cancel()
        let t = DispatchWorkItem { [weak self] in
            guard let self = self, self.connecting else { return }
            self.log("ERR", "连接 10s 未完成，已取消（泵可能被其他设备占用或已休眠）")
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
            self.cleanup(reason: "连接超时")
        }
        connectTimer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: t)
    }

    private func cleanup(reason: String) {
        connectTimer?.cancel()
        connectTimer = nil
        connected = false
        connecting = false
        writeChar = nil
        notifyChar = nil
        assembler.reset()
        finishPending(nil)
        log("SYS", reason)
    }

    // ------------------------------------------------------------ 收发

    func send(cmd: Int, payload: [UInt8] = [], padded: Bool? = nil,
              allowNegotiate: Bool = true,
              completion: ((Frame?) -> Void)? = nil) {
        guard connected, let wc = writeChar, let p = peripheral else {
            completion?(nil)
            log("ERR", "未连接，无法发送 0x\(String(format: "%04X", cmd))")
            return
        }
        guard pendingCB == nil else {
            completion?(nil)
            log("ERR", "上一条命令仍在等待应答，拒绝并发发送")
            return
        }

        let usePadded = padded ?? (payload.isEmpty && paddedEmpty)
        seq = seq &+ 1
        let raw = Proto.build(cmd: cmd, data: payload, seq: Int(seq), padded: usePadded)
        let tx: [UInt8]
        if let k = key {
            do {
                tx = try Crypto.encrypt(key: k, plain: raw)
            } catch {
                completion?(nil)
                log("ERR", "加密失败：\(error.localizedDescription)")
                return
            }
        } else {
            tx = raw
        }

        pendingCmd = cmd | 0x8000
        pendingCB = completion ?? { _ in }
        lastAck = "等待 0x\(String(format: "%04X", cmd)) 应答…"
        log("TX", "0x\(String(format: "%04X", cmd)) \(Cmd.name(cmd))  seq=\(seq) LEN=\(raw[2]) 载荷\(payload.count)B  明文 \(raw.hex)" + (key != nil ? "  密文 \(tx.count)B \(tx.hex)" : ""))

        pendingRaw = cmd
        pendingSeq = Int(seq)
        pendingTxHex = raw.hex
        pendingCipherHex = tx.hex
        pendingStartAt = Date()
        pendingFramesHex = ""
        pendingPayload = payload
        pendingPadded = usePadded
        pendingAllow = allowNegotiate
        pendingCompletion = completion
        timeoutArmed = false

        let wd = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingCB != nil, !self.timeoutArmed else { return }
            self.log("ERR", "写通道 5s 内没有完成回调，按失败处理")
            self.lastAck = "写入失败"
            self.finishPending(nil)
        }
        writeWatchdog?.cancel()
        writeWatchdog = wd
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: wd)

        sendNextChunk(tx, peripheral: p, characteristic: wc)
    }

    private func sendNextChunk(_ bytes: [UInt8], peripheral p: CBPeripheral, characteristic c: CBCharacteristic) {
        if txIndex == 0 { txChunks = [] }
        if txChunks.isEmpty {
            let limit = max(20, p.maximumWriteValueLength(for: .withResponse))
            var rest = bytes
            while !rest.isEmpty {
                let n = min(limit, rest.count)
                txChunks.append(Data(rest[0..<n]))
                rest.removeFirst(n)
            }
            txIndex = 0
            let gap = Date().timeIntervalSince(lastSendAt)
            if gap < Double(Proto.queueIntervalMs) / 1000.0 {
                let wait = Double(Proto.queueIntervalMs) / 1000.0 - gap
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    self.writeChunk(p, c)
                }
                return
            }
        }
        writeChunk(p, c)
    }

    private func writeChunk(_ p: CBPeripheral, _ c: CBCharacteristic) {
        guard txIndex < txChunks.count else { return }
        lastSendAt = Date()
        p.writeValue(txChunks[txIndex], for: c, type: .withResponse)
        // 最后一包已交给蓝牙栈，此时才开始算应答超时（避免还在分包写就重发）
        if txIndex == txChunks.count - 1 { armResponseTimeout() }
    }

    private func armResponseTimeout() {
        guard !timeoutArmed, pendingCB != nil else { return }
        timeoutArmed = true
        writeWatchdog?.cancel()
        let cmd = pendingRaw
        let payload = pendingPayload
        let usePadded = pendingPadded
        let allow = pendingAllow
        let completion = pendingCompletion
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingCB != nil else { return }
            if payload.isEmpty && allow {
                self.log("SYS", "0x\(String(format: "%04X", cmd)) 超时，改用 LEN=\(usePadded ? 6 : 7) 再试一次")
                self.clearPending()
                self.send(cmd: cmd, payload: payload, padded: !usePadded,
                          allowNegotiate: false, completion: completion)
                return
            }
            self.log("RSP", "0x\(String(format: "%04X", cmd)) 超时 \(Proto.responseTimeoutMs)ms，未自动重发")
            self.lastAck = "超时"
            self.recordExchange(cmd: cmd, request: self.pendingTxHex, cipher: self.pendingCipherHex,
                                response: "", code: nil, note: "超时 \(Proto.responseTimeoutMs)ms 无应答")
            self.finishPending(nil)
        }
        timeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Proto.responseTimeoutMs), execute: item)
    }

    private func clearPending() {
        timeoutItem?.cancel()
        timeoutItem = nil
        writeWatchdog?.cancel()
        writeWatchdog = nil
        pendingCB = nil
        pendingCmd = 0
        pendingCompletion = nil
        timeoutArmed = false
        txChunks = []
        txIndex = 0
    }

    private func finishPending(_ f: Frame?) {
        let cb = pendingCB
        clearPending()
        busy = false
        cb?(f)
    }

    // ------------------------------------------------------------ 通知处理

    private func handleNotify(_ data: Data) {
        let bytes = [UInt8](data)
        if Responses.isRetryNotify(bytes) {
            log("RSP", "泵发来单字节 0x80：原厂语义「Command Invoke 80 error, try again!」")
            return
        }

        lastNotifyRaw = bytes.hex
        log("RX", "原始 \(bytes.count)B \(bytes.hex)")

        var plain = bytes
        if let k = key {
            do {
                plain = Crypto.trimToFrame(try Crypto.decrypt(key: k, cipher: bytes))
                log("RX", "[密文 \(bytes.count)B] → 明文 \(plain.hex)")
            } catch {
                log("ERR", "解密失败：\(error.localizedDescription)  原始 \(bytes.hex)")
                return
            }
        } else {
            log("RX", plain.hex)
        }

        let frames = assembler.feed(plain)
        for f in frames {
            log("RX", "帧 cmd=0x\(String(format: "%04X", f.cmd)) seq=\(f.seq) LEN=\(f.data.count + Proto.headerLen) data=\(f.data.hex)")
            pendingFramesHex += (pendingFramesHex.isEmpty ? "" : " | ") + "0x\(String(format: "%04X", f.cmd))/seq\(f.seq)/\(f.data.hex)"
            if Responses.isErrorFrame(len: f.data.count + Proto.headerLen, f.data) {
                let code = f.data.first.map { Int($0) } ?? -1
                let meaning = Responses.RSP_CODES[code] ?? "未定义的返回码"
                log("RSP", "0x\(String(format: "%04X", f.cmd)) 返回码 \(code)：\(meaning)")
                lastAck = "返回码 \(code) · \(meaning)"
            } else {
                let parsed = Responses.decode(cmd: f.cmd, data: f.data)
                lastAck = "0x\(String(format: "%04X", f.cmd)) 数据"
                log("DEC", "\(parsed.name)：\(parsed.summary)")
            }
            // 厂商固件有的回 cmd|0x8000，有的原样回 cmd；两种都认，seq 不一致只记日志不丢弃。
            if f.cmd == pendingCmd || (pendingRaw != 0 && f.cmd == pendingRaw) {
                if f.seq != pendingSeq && f.seq != 0 {
                    log("RSP", "seq 不一致（泵 \(f.seq) / 本机 \(pendingSeq)），仍按 cmd 匹配接受")
                }
                let code = Responses.isErrorFrame(len: f.data.count + Proto.headerLen, f.data)
                    ? (f.data.first.map { Int($0) } ?? -1) : nil
                recordExchange(cmd: pendingRaw, request: pendingTxHex, cipher: pendingCipherHex,
                               response: pendingFramesHex, code: code, note: code == nil ? "收到应答" : "错误应答")
                finishPending(f)
            }
        }
    }

    /// 通用命令执行：跑任意一条命令，并把结果解析后挂在 lastParsed 上。
    /// 错误应答帧（LEN=7 且 data[0]<=9）会转成「返回码」结果，不当作业务数据。
    func runCommand(_ code: Int, payload: [UInt8] = [], padded: Bool? = nil,
                    verify: Bool = false,
                    completion: @escaping (ParsedResponse?) -> Void = { _ in }) {
        busy = true
        let isWrite = (0x00A0...0x00A6).contains(code)
        send(cmd: code, payload: payload, padded: padded, allowNegotiate: !isWrite) { [weak self] f in
            guard let self = self else { return }
            guard let f = f else {
                self.lastParsed = nil
                completion(nil)
                return
            }
            if Responses.isErrorFrame(len: f.data.count + Proto.headerLen, f.data) {
                let rc = f.data.first.map { Int($0) } ?? -1
                let meaning = Responses.RSP_CODES[rc] ?? "未定义的返回码"
                let p = ParsedResponse(cmd: f.cmd,
                                       name: "RSP " + Cmd.name(f.cmd),
                                       fields: ["返回码": rc, "含义": meaning],
                                       raw: f.data, note: "错误应答帧")
                self.lastParsed = p
                self.lastAck = "返回码 \(rc) · \(meaning)"
                completion(p)
                return
            }
            let p = Responses.decode(cmd: f.cmd, data: f.data)
            self.lastParsed = p
            self.lastAck = p.name
            completion(p)
            if verify { self.verifyAfterWrite(code) }
        }
    }

    // ------------------------------------------------------------ 会话剂量 / 自检 / 回读

    func sessionTotal() -> Double {
        pruneDoses()
        return doses.reduce(0) { $0 + $1.units }
    }

    private func pruneDoses() {
        let cutoff = Date().addingTimeInterval(-3600)
        doses = doses.filter { $0.at > cutoff }
    }

    private func persistDoses() {
        if let d = try? JSONEncoder().encode(doses) {
            UserDefaults.standard.set(d, forKey: doseKey)
        }
    }

    private func recordDose(_ u: Double) {
        guard u > 0 else { return }
        pruneDoses()
        doses.append(DoseEntry(at: Date(), units: u))
        persistDoses()
    }

    /// 只有泵明确应答、且不是错误码时才算「这次写入可能生效」。
    /// 超时/被拒都等于泵可能没执行，计进 1 小时窗口会误拦后续合法剂量。
    private func ackAccepted(_ f: Frame?) -> Bool {
        guard let f = f else { return false }
        if Responses.isErrorFrame(len: f.data.count + Proto.headerLen, f.data) {
            return (f.data.first.map { Int($0) } ?? -1) == 0
        }
        return true
    }

    /// 两段式自检：先读版本，再读状态，把结论直接写出来，省得翻日志。
    func selfCheck() {
        guard connected else {
            selfCheckText = "未连接：先扫描并连接泵，再自检"
            return
        }
        selfCheckText = "① 读版本 0x00E9 …"
        send(cmd: Cmd.GET_VERSION) { [weak self] f1 in
            guard let self = self else { return }
            if f1 == nil {
                self.send(cmd: Cmd.GET_REMAINMED_AND_ISWITCH) { f2 in
                    let text: String
                    if f2 == nil {
                        text = "失败：0x00E9 与 0x00F0 都无回包。\n→ 先核对 SN 末 8 位是否纯 0-9/A-F；再看泵是否已被别的手机占用；最后确认蓝牙权限。"
                    } else {
                        text = "基本通过：0x00F0 有回包，说明帧格式与加密都对；该固件只是不支持版本命令。"
                    }
                    DispatchQueue.main.async { self.selfCheckText = text }
                }
                return
            }
            self.send(cmd: Cmd.GET_REMAINMED_AND_ISWITCH) { f2 in
                let text: String
                if f2 == nil {
                    text = "半通过：版本有回包、状态无回包。\n→ 多为泵忙或输注开关未开，隔 2 秒再自检一次。"
                } else {
                    let p = Responses.decode(cmd: 0x80F0, data: f2!.data)
                    let rem = p.dbl("remaining_dosage").map { String(format: "%.2fU", $0) } ?? "?"
                    let sw = p.int("infusion_switch") == 1 ? "开" : "关"
                    text = "通过：加密与帧格式正常。\n剩余药量 \(rem)，输注开关 \(sw)。"
                }
                DispatchQueue.main.async { self.selfCheckText = text }
            }
        }
    }

    /// 写入后回读校验：把「发出去的」和「泵上报的」并排看。
    func verifyAfterWrite(_ written: Int, expected: [String: String] = [:]) {
        var readCmd = Cmd.GET_REMAINMED_AND_ISWITCH
        switch written {
        case Cmd.SET_INFUSION_PARAMETERS:
            readCmd = Cmd.GET_ALL_INFUSION_SETTING_INFORMATION
        case Cmd.SET_BASIC_VOLUME_INFUSION_PARAMETERS:
            readCmd = Cmd.GET_BASIC_QUANTITY_PLAN
        case Cmd.TRIGGER_TEMPORARY_BASIC_VOLUME_INFUSION:
            readCmd = Cmd.GET_TEMPORARY_BASIC_QUANTITY_PLAN
        default:
            readCmd = Cmd.GET_REMAINMED_AND_ISWITCH
        }
        DispatchQueue.main.async {
            self.verifyText = "回读 0x\(String(format: "%04X", readCmd)) 中…"
        }
        send(cmd: readCmd) { [weak self] f in
            guard let self = self else { return }
            guard let f = f else {
                DispatchQueue.main.async {
                    self.verifyText = "回读失败：0x\(String(format: "%04X", readCmd)) 无应答 → 写入是否生效未知，请人工看泵屏幕"
                }
                return
            }
            let p = Responses.decode(cmd: f.cmd, data: f.data)
            var lines: [String] = ["回读 \(p.name)"]
            var mismatch = false
            for (k, v) in expected.sorted(by: { $0.key < $1.key }) {
                let got = p.fields[k].map { "\($0)" } ?? "—"
                let same = self.matchValue(got, v)
                if !same { mismatch = true }
                lines.append("\(k)：写入 \(v) / 泵上报 \(got) \(same ? "✓" : "✗")")
            }
            if expected.isEmpty { lines.append(p.summary) }
            lines.append(mismatch ? "结论：不一致，写入可能未被泵接受" : "结论：一致")
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async { self.verifyText = text }
        }
    }

    private func matchValue(_ got: String, _ want: String) -> Bool {
        if let g = Double(got), let w = Double(want) { return abs(g - w) < 0.011 }
        return got == want
    }

    // ------------------------------------------------------------ 重连

    var hasLastDevice: Bool {
        UserDefaults.standard.string(forKey: lastDeviceKey) != nil
    }

    func reconnectLast() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        }
        guard let c = central else { return }
        guard let s = UserDefaults.standard.string(forKey: lastDeviceKey), let uuid = UUID(uuidString: s) else {
            log("SYS", "没有上次连接的记录，请先扫描")
            return
        }
        let found = c.retrievePeripherals(withIdentifiers: [uuid])
        guard let p = found.first else {
            log("ERR", "系统里找不到上次的设备（可能已关机或蓝牙重置），请重新扫描")
            return
        }
        connecting = true
        currentName = p.name ?? "上次的设备"
        peripheral = p
        p.delegate = self
        c.connect(p, options: nil)
        startConnectTimer()
        log("SYS", "重连上次设备 \(currentName)")
    }

    // ------------------------------------------------------------ 便捷动作

    /// 读基础量方案（0x00F2），取当前小时的基础率。
    /// 百分比 TBR 必须先有它，否则算不出绝对剂量。
    func readBasalPlan() {
        // 厂商 BasicQuantityPlanParameter.toByteArray() 是 3B：[mode][startTimePoint][endTimePoint]
        // 之前发空载荷，泵直接回 code 3（参数错误），所以一直读不到点表。
        runCommand(Cmd.GET_BASIC_QUANTITY_PLAN, payload: [0x00, 0x00, 0x17]) { [weak self] p in
            guard let self = self else { return }
            guard let p = p, let raw = p.fields["point_list"] as? [String: Double] else {
                self.basalText = "读取失败：0x00F2 无有效点表"
                return
            }
            var map: [Int: Double] = [:]
            for (k, v) in raw { if let h = Int(k) { map[h] = v } }
            let hour = Calendar.current.component(.hour, from: Date())
            let rate = self.rateForHour(hour, map)
            self.basalRateNow = rate
            if let r = rate {
                self.basalText = String(format: "%02d:00 起 %.2f U/h（%d 个时段）", self.hourKey(hour, map), r, map.count)
            } else {
                self.basalText = "点表为空"
            }
            self.log("OK", "基础率 \(self.basalText)")
        }
    }

    /// 一键采集：把排查大剂量失败最需要的 5 条读取串起来跑，日志里会有完整收发。
    func collectDiagnostics() {
        guard connected else {
            log("SYS", "未连接泵，无法采集诊断")
            return
        }
        let steps: [(Int, [UInt8])] = [
            (Cmd.GET_REMAINMED_AND_ISWITCH, []),
            (Cmd.GET_VERSION, []),
            (Cmd.GET_PARAMETER_SETTINGS, []),
            (Cmd.GET_BASIC_QUANTITY_PLAN, [0x00, 0x00, 0x17]),
            (Cmd.GET_ALL_INFUSION_SETTING_INFORMATION, [])
        ]
        log("SYS", "开始一键采集诊断，共 \(steps.count) 条读取")
        func next(_ i: Int) {
            guard i < steps.count else {
                log("SYS", "诊断采集完成：去「通信日志」右上角导出 txt 发我")
                lastAck = "诊断采集完成"
                return
            }
            let (cmd, payload) = steps[i]
            runCommand(cmd, payload: payload) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { next(i + 1) }
            }
        }
        next(0)
    }

    private func rateForHour(_ h: Int, _ map: [Int: Double]) -> Double? {
        if let v = map[h] { return v }
        let lower = map.keys.filter { $0 <= h }.max()
        if let k = lower { return map[k] }
        return map.keys.min().flatMap { map[$0] }
    }

    private func hourKey(_ h: Int, _ map: [Int: Double]) -> Int {
        if map[h] != nil { return h }
        return map.keys.filter { $0 <= h }.max() ?? (map.keys.min() ?? 0)
    }

    func refreshStatus() {
        busy = true
        send(cmd: Cmd.GET_REMAINMED_AND_ISWITCH) { [weak self] f in
            guard let self = self else { return }
            guard let f = f else { self.lastAck = "超时"; return }
            let p = Responses.decode(cmd: f.cmd, data: f.data)
            if let r = p.dbl("remaining_dosage") { self.remainingU = r }
            self.switchOn = p.int("infusion_switch").map { $0 != 0 }
            self.log("OK", "剩余药量 \(self.remainingU.map { String(format: "%.2fU", $0) } ?? "?")，输注开关 \(self.switchOn == true ? "开" : self.switchOn == false ? "关" : "?")")
        }
    }

    func readModel() {
        send(cmd: Cmd.GET_VERSION) { [weak self] f in
            guard let self = self, let f = f else { return }
            let p = Responses.decode(cmd: f.cmd, data: f.data)
            self.modelInfo = p.summary
        }
    }

    func sendBolus(units: Double, minutes: Int = 0, waveform: Int = 0) -> Guard.Result {
        let g = Guard.checkBolus(units: units, remaining: remainingU, switchOn: switchOn,
                                 sessionUnits: sessionTotal(), waterTest: waterTest)
        guard g.ok else {
            log("GUARD", "拒绝大剂量 \(units)U：\(g.msg)")
            return g
        }
        var b = Params.Bolus(unitsValue: units)
        b.minutes = minutes
        b.waveform = waveform
        let payload: [UInt8]
        do { payload = try b.bytes() } catch {
            return Guard.Result(ok: false, msg: error.localizedDescription)
        }
        busy = true
        send(cmd: Cmd.TRIGGER_PREPRANDIAL_DOSE_INFUSION, payload: payload, allowNegotiate: false) { [weak self] f in
            guard let self = self else { return }
            self.summariseWrite(cmd: Cmd.TRIGGER_PREPRANDIAL_DOSE_INFUSION, frame: f)
            if self.ackAccepted(f) { self.recordDose(units) }
            self.verifyAfterWrite(Cmd.TRIGGER_PREPRANDIAL_DOSE_INFUSION)
        }
        return g
    }

    func sendTBR(rate: Double?, percent: Int?, minutes: Int) -> Guard.Result {
        let g = Guard.checkTbr(rate: rate, percent: percent, minutes: minutes,
                               remaining: remainingU, switchOn: switchOn,
                               sessionUnits: sessionTotal(), waterTest: waterTest,
                               basalRate: basalRateNow)
        guard g.ok else {
            let what: String
            if let r = rate { what = String(format: "%.2fU/h", r) }
            else { what = "百分比" + String(percent ?? 0) + "%" }
            log("GUARD", "拒绝临时基础率 \(what)：\(g.msg)")
            return g
        }
        do {
            let payload = try Params.TempBasal(rateUPerHour: rate, percent: percent, minutes: minutes).bytes()
            busy = true
            var expected: [String: String] = ["duration": "\(minutes)"]
            if let r = rate {
                expected["speed"] = String(format: "%.2f", r)
                expected["percentage_switch"] = "0"
            } else {
                expected["percentage"] = "\(percent ?? 0)"
                expected["percentage_switch"] = "1"
            }
            send(cmd: Cmd.TRIGGER_TEMPORARY_BASIC_VOLUME_INFUSION, payload: payload, allowNegotiate: false) { [weak self] f in
                guard let self = self else { return }
                self.summariseWrite(cmd: Cmd.TRIGGER_TEMPORARY_BASIC_VOLUME_INFUSION, frame: f)
                if let r = rate, self.ackAccepted(f) {
                    self.recordDose(r * Double(minutes) / 60.0)
                }
                self.verifyAfterWrite(Cmd.TRIGGER_TEMPORARY_BASIC_VOLUME_INFUSION, expected: expected)
            }
            return g
        } catch {
            return Guard.Result(ok: false, msg: error.localizedDescription)
        }
    }

    func cancelTBR() {
        busy = true
        send(cmd: Cmd.CANCEL_TEMPORARY_BASIC_VOLUME_INFUSION, allowNegotiate: false) { [weak self] f in
            self?.summariseWrite(cmd: Cmd.CANCEL_TEMPORARY_BASIC_VOLUME_INFUSION, frame: f)
        }
    }

    func cancelBolus() {
        busy = true
        send(cmd: Cmd.CANCEL_PRE_MEAL_VOLUME_INFUSION, allowNegotiate: false) { [weak self] f in
            self?.summariseWrite(cmd: Cmd.CANCEL_PRE_MEAL_VOLUME_INFUSION, frame: f)
        }
    }

    private func summariseWrite(cmd: Int, frame: Frame?) {
        guard let f = frame else {
            lastAck = "超时（未自动重发）"
            log("ERR", "0x\(String(format: "%04X", cmd)) 写入无应答，已放弃，请人工核对泵屏幕")
            return
        }
        if Responses.isErrorFrame(len: f.data.count + Proto.headerLen, f.data) {
            let code = f.data.first.map { Int($0) } ?? -1
            let meaning = Responses.RSP_CODES[code] ?? "未知"
            lastAck = "返回码 \(code) · \(meaning)"
            log("RSP", "0x\(String(format: "%04X", cmd)) 写入返回码 \(code)：\(meaning)")
        } else {
            lastAck = "已发送 · 无错误码"
            log("OK", "0x\(String(format: "%04X", cmd)) 写入已发送，请核对泵屏幕与出水")
        }
    }

    // ------------------------------------------------------------ 日志

    func log(_ tag: String, _ text: String) {
        let t = DateFormatter()
        t.dateFormat = "HH:mm:ss.SSS"
        let full = DateFormatter()
        full.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let now = Date()
        let line = LogLine(time: t.string(from: now), tag: tag, text: text)
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > 2000 { self.logs.removeFirst(self.logs.count - 2000) }
        }
        let disk = "\(full.string(from: now)) [\(tag)] \(text)\n"
        logIO.async { [weak self] in
            guard let self = self else { return }
            let url = self.logFileURL
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                if let d = disk.data(using: .utf8) { try? h.write(contentsOf: d) }
            } else {
                try? disk.data(using: .utf8)?.write(to: url, options: .atomic)
            }
        }
    }

    private var logFileURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IpeleLinkLogs", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return base.appendingPathComponent("log-\(df.string(from: Date())).txt")
    }

    private func recordExchange(cmd: Int, request: String, cipher: String,
                                response: String, code: Int?, note: String) {
        let ms = Int(Date().timeIntervalSince(pendingStartAt) * 1000)
        let t = DateFormatter()
        t.dateFormat = "HH:mm:ss"
        let e = LastExchange(cmd: cmd, name: Cmd.name(cmd), requestHex: request, cipherHex: cipher,
                             responseHex: response.isEmpty ? "（无应答）" : response,
                             code: code, note: note, ms: ms, at: t.string(from: Date()))
        DispatchQueue.main.async {
            self.lastExchange = e
        }
        let codeText = code.map { "code=\($0) \(Responses.RSP_CODES[$0] ?? "未知")" } ?? "code=—"
        log("DX", "\(String(format: "0x%04X", cmd)) \(Cmd.name(cmd)) \(codeText) \(ms)ms \(note)")
    }

    /// 生成可直接发给开发分析的诊断文本：环境、配置、最近一次交换、状态快照、全量日志。
    func diagnosticReport() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = ""
        out += "IpeleLink 诊断报告\n"
        out += "生成时间：\(df.string(from: Date()))\n"
        out += "App：\(AppInfo.versionText)  iOS：\(UIDevice.current.systemVersion)  机型：\(UIDevice.current.model)\n"
        out += "泵：\(currentName.isEmpty ? "未连接" : currentName)  蓝牙：\(bluetoothState)  状态：\(connected ? "已连接" : "未连接")\n"
        out += "加密：\(encrypted ? "AES-128" : "明文")  \(snHint)\n"
        out += "空载补 FF：\(paddedEmpty ? "是" : "否")\n"
        if let p = peripheral {
            out += "写入包长上限：\(p.maximumWriteValueLength(for: .withResponse))B\n"
        }
        out += "剩余药量：\(remainingU.map { String(format: "%.2fU", $0) } ?? "—")  开关：\(switchOn == nil ? "—" : (switchOn! ? "开" : "关"))\n"
        out += "当前基础率：\(basalRateNow.map { String(format: "%.2fU/h", $0) } ?? "—")  \(basalText)\n"
        out += "1 小时累计：\(String(format: "%.2fU", sessionTotal()))\n"
        out += "自检：\(selfCheckText.isEmpty ? "—" : selfCheckText)\n"
        out += "回读校验：\(verifyText.isEmpty ? "—" : verifyText)\n"
        if let e = lastExchange {
            out += "\n最近一次交换（\(e.at)）：0x\(String(format: "%04X", e.cmd)) \(e.name)\n"
            out += "  请求明文：\(e.requestHex)\n"
            out += "  请求密文：\(e.cipherHex)\n"
            out += "  应答：\(e.responseHex)\n"
            out += "  返回码：\(e.code.map { "\($0)（\(Responses.RSP_CODES[$0] ?? "未知")）" } ?? "无")\n"
            out += "  耗时：\(e.ms)ms  \(e.note)\n"
        }
        out += "\n—— 全量日志（\(logs.count) 条）——\n"
        out += logs.map { "\($0.time) [\($0.tag)] \($0.text)" }.joined(separator: "\n")
        out += "\n"
        return out
    }

    func clearLogs() { logs.removeAll() }

    func logText() -> String {
        logs.map { "\($0.time) [\($0.tag)] \($0.text)" }.joined(separator: "\n")
    }
}

extension PumpClient: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothState = "蓝牙可用"
            log("SYS", "蓝牙已就绪")
            if scanning {
                central.scanForPeripherals(withServices: nil, options: nil)
            }
        case .poweredOff:
            bluetoothState = "蓝牙已关闭"
            log("SYS", "请在系统设置里打开蓝牙")
        case .unauthorized:
            bluetoothState = "未授权"
            log("SYS", "蓝牙权限被拒绝，请到 设置 → 隐私 → 蓝牙 打开")
        case .unsupported:
            bluetoothState = "不支持 BLE"
        default:
            bluetoothState = "状态 \(central.state.rawValue)"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "未命名设备"
        let r = RSSI.intValue
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[i] = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: r, peripheral: peripheral)
        } else {
            devices.append(DiscoveredDevice(id: peripheral.identifier, name: name, rssi: r, peripheral: peripheral))
            log("SYS", "发现 \(name)  RSSI \(r)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimer?.cancel()
        connectTimer = nil
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastDeviceKey)
        log("SYS", "已连接，发现服务 \(Proto.serviceUUID)")
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: Proto.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimer?.cancel()
        connectTimer = nil
        connecting = false
        log("ERR", "连接失败：\(error?.localizedDescription ?? "未知")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cleanup(reason: "连接已断开 \(error?.localizedDescription ?? "")")
    }
}

extension PumpClient: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == CBUUID(string: Proto.serviceUUID) }) else {
            log("ERR", "没有找到 FFF0 服务：\(error?.localizedDescription ?? "")")
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: Proto.notifyUUID),
                                            CBUUID(string: Proto.writeUUID)], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == CBUUID(string: Proto.notifyUUID) {
                notifyChar = c
                peripheral.setNotifyValue(true, for: c)
                log("SYS", "已订阅 FFF1 通知")
            } else if c.uuid == CBUUID(string: Proto.writeUUID) {
                writeChar = c
                log("SYS", "找到 FFF2 写通道，最大写入 \(peripheral.maximumWriteValueLength(for: .withResponse))B")
            }
        }
        if writeChar != nil {
            connected = true
            connecting = false
            log("SYS", "链路就绪")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.readBasalPlan()
            }
        } else {
            log("ERR", "没找到 FFF2 写通道，无法下发命令")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            log("ERR", "写入失败：\(e.localizedDescription)")
            finishPending(nil)
            return
        }
        txIndex += 1
        if txIndex < txChunks.count {
            let gap = Date().timeIntervalSince(lastSendAt)
            let wait = max(0, Double(Proto.queueIntervalMs) / 1000.0 - gap)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                self.writeChunk(peripheral, characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let d = characteristic.value else { return }
        handleNotify(d)
    }
}

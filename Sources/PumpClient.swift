import Foundation
import CoreBluetooth

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
    @Published var logs: [LogLine] = []

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
        log("SYS", "连接 \(d.name) …（命令间隔 \(Proto.queueIntervalMs)ms，响应超时 \(Proto.responseTimeoutMs)ms）")
    }

    func disconnect() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        cleanup(reason: "主动断开")
    }

    private func cleanup(reason: String) {
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

        seq = seq &+ 1
        let raw = Proto.build(cmd: cmd, data: payload, seq: Int(seq),
                              padded: padded ?? (payload.isEmpty && paddedEmpty))
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
        log("TX", "0x\(String(format: "%04X", cmd)) \(Cmd.name(cmd))  明文 \(raw.hex)\(key != nil ? "  → 密文 \(tx.count)B" : "")")

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.log("RSP", "0x\(String(format: "%04X", cmd)) 超时 \(Proto.responseTimeoutMs)ms，未自动重发")
            self.lastAck = "超时"
            self.finishPending(nil)
        }
        timeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Proto.responseTimeoutMs), execute: item)

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
    }

    private func finishPending(_ f: Frame?) {
        timeoutItem?.cancel()
        timeoutItem = nil
        let cb = pendingCB
        pendingCB = nil
        txChunks = []
        txIndex = 0
        cb?(f)
        busy = false
    }

    // ------------------------------------------------------------ 通知处理

    private func handleNotify(_ data: Data) {
        let bytes = [UInt8](data)
        if Responses.isRetryNotify(bytes) {
            log("RSP", "泵发来单字节 0x80：原厂语义「Command Invoke 80 error, try again!」")
            return
        }

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
            log("RX", "0x\(String(format: "%04X", f.cmd)) \(Cmd.name(f.cmd))  \(f.data.hex)")
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
            if f.cmd == pendingCmd {
                finishPending(f)
            }
        }
    }

    // ------------------------------------------------------------ 便捷动作

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
        let g = Guard.checkBolus(units: units, remaining: remainingU, switchOn: switchOn)
        guard g.ok else { return g }
        var b = Params.Bolus(unitsValue: units)
        b.minutes = minutes
        b.waveform = waveform
        let payload = b.bytes()
        busy = true
        send(cmd: Cmd.TRIGGER_PREPRANDIAL_DOSE_INFUSION, payload: payload) { [weak self] f in
            self?.summariseWrite(cmd: Cmd.TRIGGER_PREPRANDIAL_DOSE_INFUSION, frame: f)
        }
        return g
    }

    func sendTBR(rate: Double?, percent: Int?, minutes: Int) -> Guard.Result {
        let g = Guard.checkTbr(rate: rate, percent: percent, minutes: minutes,
                               remaining: remainingU, switchOn: switchOn)
        guard g.ok else { return g }
        do {
            let payload = try Params.TempBasal(rateUPerHour: rate, percent: percent, minutes: minutes).bytes()
            busy = true
            send(cmd: Cmd.TRIGGER_TEMPORARY_BASIC_VOLUME_INFUSION, payload: payload) { [weak self] f in
                self?.summariseWrite(cmd: Cmd.TRIGGER_TEMPORARY_BASIC_VOLUME_INFUSION, frame: f)
            }
            return g
        } catch {
            return Guard.Result(ok: false, msg: error.localizedDescription)
        }
    }

    func cancelTBR() {
        busy = true
        send(cmd: Cmd.CANCEL_TEMPORARY_BASIC_VOLUME_INFUSION) { [weak self] f in
            self?.summariseWrite(cmd: Cmd.CANCEL_TEMPORARY_BASIC_VOLUME_INFUSION, frame: f)
        }
    }

    func cancelBolus() {
        busy = true
        send(cmd: Cmd.CANCEL_PRE_MEAL_VOLUME_INFUSION) { [weak self] f in
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
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = LogLine(time: f.string(from: Date()), tag: tag, text: text)
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > 600 { self.logs.removeFirst(self.logs.count - 600) }
        }
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
        log("SYS", "已连接，发现服务 \(Proto.serviceUUID)")
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: Proto.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
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

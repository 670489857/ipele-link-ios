import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var pump: PumpClient

    @AppStorage("ipele.sn") private var sn: String = ""
    @AppStorage("ipele.padded") private var paddedEmpty: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showInfusion = false
    @State private var showLog = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 8) {
                        if let hero = HeroImage.image {
                            Image(uiImage: hero)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 132)
                                .frame(maxWidth: .infinity)
                        }
                        Text(AppInfo.versionText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("连接")) {
                    HStack {
                        Text("蓝牙")
                        Spacer()
                        Text(pump.bluetoothState).foregroundColor(.secondary)
                    }
                    if pump.connected {
                        HStack {
                            Text("已连接")
                            Spacer()
                            Text(pump.currentName).foregroundColor(.secondary)
                        }
                        Button("断开连接") { pump.disconnect() }.foregroundColor(.red)
                    } else {
                        Button(pump.scanning ? "停止扫描" : "扫描附近的泵") {
                            if pump.scanning { pump.stopScan() } else { pump.startScan() }
                        }
                        if pump.hasLastDevice {
                            Button("重连上次设备") { pump.reconnectLast() }
                        }
                    }
                    HStack {
                        Text("加密")
                        Spacer()
                        Text(pump.snHint).foregroundColor(pump.encrypted ? .green : .orange)
                            .font(.caption)
                    }
                }

                if pump.scanning && pump.devices.isEmpty {
                    Section {
                        Text("正在查找 EV 开头的泵…").font(.caption).foregroundColor(.secondary)
                    }
                }

                if !pump.connected && !pump.devices.isEmpty {
                    Section(header: Text("发现的泵（EV/EI，\(pump.devices.count)）")) {
                        ForEach(pump.devices.sorted { $0.rssi > $1.rssi }) { d in
                            Button {
                                pump.connect(d)
                            } label: {
                                HStack {
                                    Text(d.name)
                                    Spacer()
                                    Text("\(d.rssi) dBm").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                if pump.connected {
                    Section(header: Text("泵状态")) {
                        HStack {
                            Text("剩余药量")
                            Spacer()
                            Text(pump.remainingU.map { String(format: "%.2f U", $0) } ?? "—")
                        }
                        HStack {
                            Text("当前基础率")
                            Spacer()
                            Text(pump.basalRateNow.map { String(format: "%.2f U/h", $0) } ?? "—")
                                .foregroundColor(pump.basalRateNow == nil ? .secondary : .primary)
                        }
                        HStack {
                            Text("1 小时写入累计")
                            Spacer()
                            Text(String(format: "%.2f U", pump.sessionTotal()))
                        }
                        HStack {
                            Text("输注开关")
                            Spacer()
                            Text(pump.switchOn == nil ? "—" : (pump.switchOn! ? "开" : "关"))
                                .foregroundColor(pump.switchOn == false ? .red : .primary)
                        }
                        HStack {
                            Text("应答")
                            Spacer()
                            Text(pump.lastAck).font(.caption).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("版本")
                            Spacer()
                            Text(pump.modelInfo).font(.caption2).foregroundColor(.secondary)
                        }
                        Button("刷新状态（0x00F0）") { pump.refreshStatus() }
                        Button("读基础率（0x00F2）") { pump.readBasalPlan() }
                        Button("读版本（0x00E9）") { pump.readModel() }
                        if pump.basalRateNow == nil {
                            Text(pump.basalText).font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("工程模式 · 输注写入")) {
                        Text("仅用于水测试。所有写入都会二次确认，超时不会自动重发。")
                            .font(.caption).foregroundColor(.secondary)
                        Button {
                            showInfusion = true
                        } label: {
                            Label("打开输注面板", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                        Button("取消临时基础率（0x00A5）") { pump.cancelTBR() }
                        Button("取消大剂量（0x00A6）") { pump.cancelBolus() }
                        Toggle("水测试模式（≤0.5U / ≤1.0U·h⁻¹）", isOn: $pump.waterTest)
                        if !pump.verifyText.isEmpty {
                            Text(pump.verifyText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("自检")) {
                    Button("运行自检（0x00E9 → 0x00F0）") { pump.selfCheck() }
                    if !pump.selfCheckText.isEmpty {
                        Text(pump.selfCheckText).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("功能（不用连泵也能进）")) {
                    NavigationLink(destination: ReadGroupView(pump: pump, group: "状态与设置")) {
                        entry("状态与设置", "14 条只读：药量、报警、IOB、每小时量…")
                    }
                    NavigationLink(destination: ReadGroupView(pump: pump, group: "记录")) {
                        entry("记录", "9 条：四组记录、单条记录、条数统计")
                    }
                    NavigationLink(destination: ReadGroupView(pump: pump, group: "系统与工厂")) {
                        entry("系统与工厂", "3 条：系统设置、工厂模式、版本")
                    }
                    NavigationLink(destination: WritesView(pump: pump)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写入（危险）").foregroundColor(.red)
                            Text("7 类：输注、取消、泵限值、基础率、时间")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("诊断")) {
                    NavigationLink(destination: LogView(pump: pump), isActive: $showLog) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("通信日志（\(pump.logs.count)）")
                            Text("含原始收发包、解密后字节、返回码、耗时；可导出")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Button("一键采集诊断（5 条读取）") { pump.collectDiagnostics() }
                    if let e = pump.lastExchange {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(format: "最近：0x%04X %@", e.cmd, e.name))
                                .font(.caption).bold()
                            Text("\(e.code.map { "返回码 \($0) · \(Responses.RSP_CODES[$0] ?? "未知")" } ?? e.note)  \(e.ms)ms")
                                .font(.caption2).foregroundColor(e.code != nil && e.code != 0 ? .red : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("IpeleLink")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("设置") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(pump: pump)
            }
            .sheet(isPresented: $showInfusion) {
                InfusionSheet(pump: pump)
            }
            .onAppear {
                pump.configure(sn: sn, paddedEmpty: paddedEmpty)
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active && !pump.connected && pump.hasLastDevice {
                    pump.reconnectLast()
                }
            }
        }
    }

    private func entry(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(sub).font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ipele.sn") private var sn: String = ""
    @AppStorage("ipele.padded") private var paddedEmpty: Bool = true
    @State private var draftSn: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("泵序列号"), footer: Text("一般不用手填：扫描到 EV 开头的泵并连接后，会自动取设备名末 8 位填入。也可手动改。留空则按明文收发。")) {
                    TextField("例如 E5F60718", text: $draftSn)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }
                Section(header: Text("空载命令")) {
                    Toggle("LEN=7 补 0xFF（原厂写法）", isOn: $paddedEmpty)
                }
                Section {
                    Button("保存并应用") {
                        sn = draftSn.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        pump.configure(sn: sn, paddedEmpty: paddedEmpty)
                        dismiss()
                    }
                }
                Section(header: Text("关于"), footer: Text("IpeleLink for iOS · \(AppInfo.versionText)（未签名自签构建）")) {
                    HStack {
                        Text("通信协议")
                        Spacer()
                        Text("Ipele / Elfin 2.0 · 55AA 帧").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { draftSn = sn }
        }
    }
}

struct InfusionSheet: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0
    @State private var amount = ""
    @State private var duration = "60"
    @State private var percent = "100"
    @State private var waveform = 0
    @State private var showConfirm = false
    @State private var summary = ""
    @State private var errorText = ""

    private var modes: [String] { ["大剂量", "TBR 速率", "TBR 百分比"] }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("风险提示：这是改变胰岛素输注的写入操作。首次必须在纯水管路做水测试，并在泵旁守候。")
                        .font(.caption).foregroundColor(.red)
                }
                Section(header: Text("模式")) {
                    Picker("模式", selection: $mode) {
                        ForEach(0..<modes.count, id: \.self) { i in Text(modes[i]).tag(i) }
                    }.pickerStyle(.segmented)
                }
                Section(header: Text("参数")) {
                    if mode == 0 {
                        HStack { Text("剂量 (U)"); TextField("0.10", text: $amount).keyboardType(.decimalPad) }
                        HStack { Text("时长 (min，0=即刻)"); TextField("0", text: $duration).keyboardType(.numberPad) }
                        Picker("波形", selection: $waveform) {
                            Text("自动").tag(0)
                            Text("3").tag(3)
                            Text("4").tag(4)
                        }.pickerStyle(.segmented)
                    } else if mode == 1 {
                        HStack { Text("速率 (U/h)"); TextField("0.50", text: $amount).keyboardType(.decimalPad) }
                        HStack { Text("时长 (min)"); TextField("60", text: $duration).keyboardType(.numberPad) }
                    } else {
                        HStack { Text("百分比 (%)"); TextField("100", text: $percent).keyboardType(.numberPad) }
                        HStack { Text("时长 (min)"); TextField("60", text: $duration).keyboardType(.numberPad) }
                    }
                }
                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundColor(.red).font(.caption) }
                }
                Section {
                    Button("校验并继续") { validate() }
                        .foregroundColor(.red)
                }
                Section(header: Text("当前状态参照")) {
                    Text("剩余药量 " + (pump.remainingU.map { String(format: "%.2f U", $0) } ?? "未知")
                         + "，开关 " + (pump.switchOn == nil ? "未知" : (pump.switchOn! ? "开" : "关")))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("输注面板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .sheet(isPresented: $showConfirm) {
                ConfirmView(summary: summary) {
                    execute()
                }
            }
        }
    }

    private func validate() {
        errorText = ""
        let minutes = Int(duration.trimmingCharacters(in: .whitespaces)) ?? 0
        switch mode {
        case 0:
            guard let u = Guard.parseUnits(amount) else { errorText = "剂量必须是大于 0、最多两位小数的数字"; return }
            let r = Guard.checkBolus(units: u, remaining: pump.remainingU, switchOn: pump.switchOn,
                                     sessionUnits: pump.sessionTotal(), waterTest: pump.waterTest)
            guard r.ok else { errorText = r.msg; return }
            let waveText = waveform == 0 ? "自动" : "波形 \(waveform)"
            summary = "大剂量 \(String(format: "%.2f", u)) U，\(waveText)" + (minutes > 0 ? "，时长 \(minutes) min" : "")
        case 1:
            guard let rate = Guard.parseUnits(amount) else { errorText = "速率必须是大于 0 的数字"; return }
            let r = Guard.checkTbr(rate: rate, percent: nil, minutes: minutes,
                                   remaining: pump.remainingU, switchOn: pump.switchOn,
                                   sessionUnits: pump.sessionTotal(), waterTest: pump.waterTest)
            guard r.ok else { errorText = r.msg; return }
            summary = String(format: "临时基础率 %.2f U/h × %d min", rate, minutes)
        default:
            guard let p = Int(percent.trimmingCharacters(in: .whitespaces)) else { errorText = "百分比必须是整数"; return }
            guard let basal = pump.basalRateNow else {
                errorText = "百分比模式要先读基础率：先点「读基础率（0x00F2）」，读到当前时段基础率再用百分比；或改用速率模式"
                return
            }
            let r = Guard.checkTbr(rate: nil, percent: p, minutes: minutes,
                                   remaining: pump.remainingU, switchOn: pump.switchOn,
                                   sessionUnits: pump.sessionTotal(), waterTest: pump.waterTest,
                                   basalRate: basal)
            guard r.ok else { errorText = r.msg; return }
            let implied = basal * Double(p) / 100
            summary = String(format: "临时基础率 %d%% ≈ %.2f U/h（按当前基础率 %.2f）× %d min", p, implied, basal, minutes)
        }
        showConfirm = true
    }

    private func execute() {
        let minutes = Int(duration.trimmingCharacters(in: .whitespaces)) ?? 0
        switch mode {
        case 0:
            if let u = Guard.parseUnits(amount) {
                let r = pump.sendBolus(units: u, minutes: minutes,
                                       waveform: waveform == 0 ? nil : waveform)
                errorText = r.ok ? "" : r.msg
            }
        case 1:
            if let rate = Guard.parseUnits(amount) {
                let r = pump.sendTBR(rate: rate, percent: nil, minutes: minutes)
                errorText = r.ok ? "" : r.msg
            }
        default:
            if let p = Int(percent.trimmingCharacters(in: .whitespaces)) {
                let r = pump.sendTBR(rate: nil, percent: p, minutes: minutes)
                errorText = r.ok ? "" : r.msg
            }
        }
        showConfirm = false
    }
}

struct ConfirmView: View {
    let summary: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var left = 3
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44)).foregroundColor(.red)
            Text("再次确认").font(.title2).bold()
            Text(summary).font(.title3)
            Text("确认后将直接向泵下发写入命令，不做钳制、不自动重发。")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button {
                timer?.invalidate()
                onConfirm()
                dismiss()
            } label: {
                Text(left > 0 ? "确认下发（\(left)）" : "确认下发")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(left > 0 ? Color.gray : Color.red)
                    .foregroundColor(.white).cornerRadius(10)
            }
            .disabled(left > 0)
            Button("取消") { timer?.invalidate(); dismiss() }
                .foregroundColor(.secondary)
        }
        .padding(24)
        .onAppear {
            left = 3
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                if left > 0 { left -= 1 } else { t.invalidate() }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

struct LogView: View {
    @ObservedObject var pump: PumpClient
    @State private var filter = 0
    @State private var query = ""
    @State private var shareURL: URL? = nil
    @State private var showShare = false
    @State private var copied = false

    private let filters = ["全部", "发送", "接收", "异常", "解析"]

    private var filtered: [LogLine] {
        pump.logs.filter { l in
            let passTag: Bool
            switch filter {
            case 1: passTag = l.tag == "TX"
            case 2: passTag = l.tag == "RX"
            case 3: passTag = ["ERR", "RSP", "GUARD", "DX"].contains(l.tag)
            case 4: passTag = ["DEC", "OK", "CFG", "SYS"].contains(l.tag)
            default: passTag = true
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            let passQuery = q.isEmpty
                || l.text.localizedCaseInsensitiveContains(q)
                || l.tag.localizedCaseInsensitiveContains(q)
            return passTag && passQuery
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(0..<filters.count, id: \.self) { i in Text(filters[i]).tag(i) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.top, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜 0x00A3 / 返回码 / code / 超时", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !query.isEmpty { Button("清除") { query = "" }.font(.caption) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            if let e = pump.lastExchange {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(String(format: "最近一次 0x%04X %@", e.cmd, e.name)).font(.caption).bold()
                        Spacer()
                        Text("\(e.ms)ms").font(.caption2).foregroundColor(.secondary)
                    }
                    Text(e.code.map { "返回码 \($0) · \(Responses.RSP_CODES[$0] ?? "未知")" } ?? e.note)
                        .font(.caption2)
                        .foregroundColor(e.code != nil && e.code != 0 ? .red : .secondary)
                    Text("请求 " + e.requestHex).font(.system(.caption2, design: .monospaced))
                        .lineLimit(2).foregroundColor(.secondary)
                    Text("应答 " + e.responseHex).font(.system(.caption2, design: .monospaced))
                        .lineLimit(2).foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal, 12).padding(.bottom, 6)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if filtered.isEmpty {
                        Text("没有匹配的日志").font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 30)
                    }
                    ForEach(filtered) { l in
                        HStack(alignment: .top, spacing: 6) {
                            Text(l.time).font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary).frame(width: 66, alignment: .leading)
                            Text(l.tag).font(.system(.caption2, design: .monospaced)).bold()
                                .foregroundColor(color(l.tag)).frame(width: 34, alignment: .leading)
                            Text(l.text).font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 30)
            }
        }
        .navigationTitle("通信日志")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    export()
                } label: { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(copied ? "已复制" : "复制") {
                    UIPasteboard.general.string = pump.diagnosticReport()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }.font(.caption)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("清空") { pump.clearLogs() }
            }
        }
        .sheet(isPresented: $showShare) {
            if let u = shareURL { ShareSheet(items: [u]) }
        }
    }

    private func export() {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "IpeleLink-diagnostic-\(df.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? pump.diagnosticReport().data(using: .utf8)?.write(to: url, options: .atomic)
        shareURL = url
        showShare = true
    }

    private func color(_ tag: String) -> Color {
        switch tag {
        case "ERR": return .red
        case "RSP": return .orange
        case "GUARD": return .purple
        case "TX": return .blue
        case "RX": return .green
        case "DX": return .pink
        case "DEC": return .teal
        default: return .secondary
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum AppInfo {
    static var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) · build \(b)"
    }
}

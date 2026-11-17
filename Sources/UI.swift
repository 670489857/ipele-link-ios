import SwiftUI

struct ContentView: View {
    @ObservedObject var pump: PumpClient

    @AppStorage("ipele.sn") private var sn: String = ""
    @AppStorage("ipele.padded") private var paddedEmpty: Bool = true

    @State private var showSettings = false
    @State private var showInfusion = false
    @State private var showLog = false

    var body: some View {
        NavigationView {
            List {
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
                    }
                    HStack {
                        Text("加密")
                        Spacer()
                        Text(pump.snHint).foregroundColor(pump.encrypted ? .green : .orange)
                            .font(.caption)
                    }
                }

                if !pump.connected && !pump.devices.isEmpty {
                    Section(header: Text("发现的设备（\(pump.devices.count)）")) {
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
                        Button("读版本（0x00E9）") { pump.readModel() }
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
                    }
                }

                Section(header: Text("诊断")) {
                    NavigationLink(destination: LogView(pump: pump), isActive: $showLog) {
                        Text("通信日志（\(pump.logs.count)）")
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
                Section(header: Text("泵序列号"), footer: Text("填序列号后 8 位（十六进制 0-9/A-F）。留空则按明文收发，泵一般会拒绝。")) {
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
            let r = Guard.checkBolus(units: u, remaining: pump.remainingU, switchOn: pump.switchOn)
            guard r.ok else { errorText = r.msg; return }
            summary = "大剂量 \(String(format: "%.2f", u)) U" + (minutes > 0 ? "，波形时长 \(minutes) min" : "")
        case 1:
            guard let rate = Guard.parseUnits(amount) else { errorText = "速率必须是大于 0 的数字"; return }
            let r = Guard.checkTbr(rate: rate, percent: nil, minutes: minutes,
                                   remaining: pump.remainingU, switchOn: pump.switchOn)
            guard r.ok else { errorText = r.msg; return }
            summary = String(format: "临时基础率 %.2f U/h × %d min", rate, minutes)
        default:
            guard let p = Int(percent.trimmingCharacters(in: .whitespaces)) else { errorText = "百分比必须是整数"; return }
            let r = Guard.checkTbr(rate: nil, percent: p, minutes: minutes,
                                   remaining: pump.remainingU, switchOn: pump.switchOn)
            guard r.ok else { errorText = r.msg; return }
            summary = "临时基础率 \(p)% × \(minutes) min"
        }
        showConfirm = true
    }

    private func execute() {
        let minutes = Int(duration.trimmingCharacters(in: .whitespaces)) ?? 0
        switch mode {
        case 0:
            if let u = Guard.parseUnits(amount) {
                let r = pump.sendBolus(units: u, minutes: minutes)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(pump.logs) { l in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.time).font(.caption2).foregroundColor(.secondary)
                        Text(l.tag).font(.caption2).bold()
                            .foregroundColor(color(l.tag))
                    }
                    Text(l.text).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle("通信日志")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("复制") { UIPasteboard.general.string = pump.logText() }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("清空") { pump.clearLogs() }
            }
        }
    }

    private func color(_ tag: String) -> Color {
        switch tag {
        case "ERR": return .red
        case "TX": return .blue
        case "RX": return .green
        case "OK": return .green
        default: return .secondary
        }
    }
}

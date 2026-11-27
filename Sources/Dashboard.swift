import SwiftUI

// 主界面：按“泵设置”卡片式布局重排。视觉层级参考用户给的截图：
// 泵图 + 电量胶囊 → 两个关键指标 → 操作列表 → 状态 → 设备 → 删除泵。

struct ContentView: View {
    @ObservedObject var pump: PumpClient

    @AppStorage("ipele.sn") private var sn: String = ""
    @AppStorage("ipele.padded") private var paddedEmpty: Bool = true
    @Environment(\.scenePhase) private var scenePhase

    @State private var showConnect = false
    @State private var showTBR = false
    @State private var showBolus = false
    @State private var showSquare = false
    @State private var showBasal = false
    @State private var showStop = false
    @State private var showEngineering = false
    @State private var showDelete = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    heroCard
                    metricsCard
                    operationsCard
                    statusCard
                    deviceCard
                    deleteCard
                    Text(AppInfo.versionText)
                        .font(.caption2).foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("艾派乐泵设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("工程") { showEngineering = true }
                }
            }
            .sheet(isPresented: $showConnect) { ConnectSheet(pump: pump) }
            .sheet(isPresented: $showTBR) { InfusionSheet(pump: pump, initialMode: 1) }
            .sheet(isPresented: $showBolus) { InfusionSheet(pump: pump, initialMode: 0, initialBolusKind: 0) }
            .sheet(isPresented: $showSquare) { InfusionSheet(pump: pump, initialMode: 0, initialBolusKind: 1) }
            .sheet(isPresented: $showBasal) { BasalSheet(pump: pump) }
            .sheet(isPresented: $showStop) { StopInfusionSheet(pump: pump) }
            .sheet(isPresented: $showEngineering) { EngineeringView(pump: pump) }
            .alert(isPresented: $showDelete) {
                Alert(title: Text("删除泵？"),
                      message: Text("会断开连接，并清除已保存的泵 UUID 和序列号；下次需要重新扫描。"),
                      primaryButton: .destructive(Text("删除")) { pump.forgetDevice() },
                      secondaryButton: .cancel(Text("取消")))
            }
            .onAppear {
                pump.configure(sn: sn, paddedEmpty: paddedEmpty)
                if !pump.connected && pump.hasLastDevice { pump.reconnectLast() }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active && !pump.connected && pump.hasLastDevice { pump.reconnectLast() }
            }
            .onChange(of: pump.connected) { connected in
                if connected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pump.readTodayTotal() }
                }
            }
        }
    }

    // ------------------------------------------------------------ 顶部泵图 + 电量

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                if let hero = HeroImage.image {
                    Image(uiImage: hero)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .frame(maxWidth: .infinity)
                } else {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 56)).foregroundColor(.teal)
                        .frame(height: 130)
                }
                Text(pump.connected ? "已连接 · \(pump.currentName)" : "未连接")
                    .font(.caption)
                    .foregroundColor(pump.connected ? .secondary : .orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)

            HStack(spacing: 4) {
                Image(systemName: batterySymbol)
                Text(batteryText)
            }
            .font(.caption).bold()
            .foregroundColor(batteryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(batteryColor.opacity(0.13)))
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground)))
    }

    private var metricsCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("基础率").font(.caption).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(rateText).font(.system(size: 32, weight: .semibold))
                    Text("单位/小时").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("剩余胰岛素").font(.caption).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(remainingText).font(.system(size: 32, weight: .semibold))
                    Text("U").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground)))
    }

    // ------------------------------------------------------------ 操作

    private var operationsCard: some View {
        VStack(spacing: 0) {
            sectionTitle("操作")

            if !pump.connected {
                Button { showConnect = true } label: {
                    row("连接泵", "扫描 EV / EL / EI 泵并建立加密连接")
                }.buttonStyle(PlainButtonStyle())
                divider
            }

            Button { showStop = true } label: {
                row("暂停输注", "取消正在进行的临时基础率和大剂量")
            }.buttonStyle(PlainButtonStyle())
            divider

            Button { pump.refreshStatus() } label: {
                row("同步状态", "刷新电量、剩余药量、今日总量与泵时间")
            }.buttonStyle(PlainButtonStyle())
            divider

            infoCell("上次同步", lastSyncText)
            divider

            Button { showTBR = true } label: {
                row("设置临时基础率", "按 10%～250% 调整，默认 30 分钟")
            }.buttonStyle(PlainButtonStyle())
            divider

            Button { showBolus = true } label: {
                row("常规大剂量", "立即输注，时长默认 0")
            }.buttonStyle(PlainButtonStyle())
            divider

            Button { showSquare = true } label: {
                row("方波大剂量", "总量铺在 15～480 分钟内，每 60 分钟输注")
            }.buttonStyle(PlainButtonStyle())
            divider

            Button { showBasal = true } label: {
                row("基础率时段管理 (48 段)", "一个默认值铺满 48 个半小时点，或查看当前方案")
            }.buttonStyle(PlainButtonStyle())
            divider

            NavigationLink(destination: ReadGroupView(pump: pump, group: "记录")) {
                row("历史记录查询", "读取泵内大剂量、日总量、关机与操作记录")
            }.buttonStyle(PlainButtonStyle())
            divider

            Button { pump.syncPumpTime() } label: {
                row("同步泵时间", "泵时间：\(pump.pumpTimeText)")
            }.buttonStyle(PlainButtonStyle())
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // ------------------------------------------------------------ 状态

    private var statusCard: some View {
        VStack(spacing: 0) {
            sectionTitle("状态")
            infoCell("蓝牙连接状态", connectionText, color: pump.connected ? .green : .orange)
            divider
            infoCell("电池电量", batteryText, color: batteryColor)
            divider
            infoCell("运行与输注状态", runStateText, color: runStateColor)
            divider
            infoCell("剩余药量与今日已输注", remainAndTodayText)
            divider
            infoCell("基础率与输注上限", basalAndLimitText)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // ------------------------------------------------------------ 设备

    private var deviceCard: some View {
        VStack(spacing: 0) {
            sectionTitle("设备")
            infoCell("泵名称", pump.connected ? "艾派乐 Elfin 2.0（\(pump.currentName)）" : "艾派乐 Elfin 2.0")
            divider
            infoCell("型号与序列号", "MTI-P IV · SN \(serialTail)")
            divider
            NavigationLink(destination: LogView(pump: pump)) {
                row("通信日志与连接诊断", "查看或导出收发原文，排查蓝牙连接与配对状态")
            }.buttonStyle(PlainButtonStyle())
            divider
            Button { showEngineering = true } label: {
                row("工程与诊断", "只读命令、写入面板、自检与参数设置")
            }.buttonStyle(PlainButtonStyle())
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var deleteCard: some View {
        Button { showDelete = true } label: {
            Text("删除泵")
                .font(.body)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(PlainButtonStyle())
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground)))
    }

    // ------------------------------------------------------------ 行 / 卡片零件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundColor(.primary)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption).foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func infoCell(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body).foregroundColor(.primary)
            Text(value).font(.subheadline).foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Divider().padding(.leading, 16)
    }

    // ------------------------------------------------------------ 文案

    private var rateText: String {
        (pump.basalDisplayRate ?? pump.basalRateNow).map { String(format: "%.2f", $0) } ?? "—"
    }

    private var remainingText: String {
        pump.remainingU.map { String(format: "%.1f", $0) } ?? "—"
    }

    private var batteryText: String {
        pump.batteryPct.map { "\($0)%" } ?? "—"
    }

    private var batteryColor: Color {
        guard let b = pump.batteryPct else { return .secondary }
        return b <= 20 ? .red : (b <= 40 ? .orange : .green)
    }

    private var batterySymbol: String {
        guard let b = pump.batteryPct else { return "battery.0" }
        if b > 75 { return "battery.100" }
        if b > 50 { return "battery.75" }
        if b > 25 { return "battery.50" }
        if b > 10 { return "battery.25" }
        return "battery.0"
    }

    private var connectionText: String {
        if pump.connected { return serialTail == "—" ? "已连接" : "已连接（\(serialTail)）" }
        return pump.connecting ? "连接中…" : "未连接"
    }

    private var runStateText: String {
        guard let on = pump.switchOn else { return "未知（先点同步状态）" }
        return on ? "正常输注中" : "已暂停"
    }

    private var runStateColor: Color {
        guard let on = pump.switchOn else { return .secondary }
        return on ? .green : .red
    }

    private var remainAndTodayText: String {
        let r = pump.remainingU.map { String(format: "%.1f U", $0) } ?? "—"
        let t = pump.todayTotalU.map { String(format: "今日累计 %.1f U", $0) } ?? "今日累计 —"
        return "剩余 \(r) · \(t)"
    }

    private var basalAndLimitText: String {
        let basal = pump.basalDisplayRate ?? pump.basalRateNow
        let regular = basal.map { String(format: "常规基础率 %.2f U/h", $0) } ?? "常规基础率 —"
        return regular + "\n" + "临时基础率：\(pump.tempBasalText)"
    }

    private var serialTail: String {
        let t = pump.currentName.uppercased()
        guard t.count >= 8 else { return "—" }
        return String(t.suffix(8))
    }

    private var lastSyncText: String {
        guard let d = pump.lastSyncAt else { return "尚未同步" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return f.string(from: d)
    }
}

// ---------------------------------------------------------------- 连接面板

struct ConnectSheet: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("蓝牙")) {
                    HStack {
                        Text("状态")
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
                        Text(pump.snHint).font(.caption)
                            .foregroundColor(pump.encrypted ? .green : .orange)
                    }
                }

                if pump.scanning && pump.devices.isEmpty {
                    Section { Text("正在查找 EV / EL / EI 开头的泵…").font(.caption).foregroundColor(.secondary) }
                }

                if !pump.connected && !pump.devices.isEmpty {
                    Section(header: Text("发现的泵（\(pump.devices.count)）")) {
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
            }
            .navigationTitle("连接泵")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .onAppear {
                if !pump.connected && pump.devices.isEmpty { pump.startScan() }
            }
            .onChange(of: pump.connected) { connected in
                if connected { dismiss() }
            }
        }
    }
}

// ---------------------------------------------------------------- 取消输注

struct StopInfusionSheet: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("只取消临时基础率和大剂量；常规基础率不会停，泵会继续按当前方案输注。")) {
                    Button("取消临时基础率（0x00A5）") { pump.cancelTBR() }
                    Button("取消大剂量（0x00A6）") { pump.cancelBolus() }
                }
                Section(header: Text("当前状态")) {
                    Text("剩余药量 " + (pump.remainingU.map { String(format: "%.2f U", $0) } ?? "—"))
                    Text("输注开关 " + (pump.switchOn == nil ? "未知" : (pump.switchOn! ? "开" : "关")))
                    if !pump.lastAck.isEmpty { Text("应答：\(pump.lastAck)").font(.caption).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("暂停/取消输注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }
}

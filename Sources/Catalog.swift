import SwiftUI

struct CommandDef: Identifiable {
    let id: Int
    let title: String
    let group: String
    let indexBytes: Int   // 0=无入参，1=1B 起始索引，2=2B 起始索引
    let note: String
}

enum Catalog {
    static let all: [CommandDef] = [
        // ---- 状态与设置
        CommandDef(id: Cmd.GET_REMAINMED_AND_ISWITCH, title: "剩余药量与输注开关", group: "状态与设置", indexBytes: 0, note: "2 字段"),
        CommandDef(id: Cmd.GET_PRE_MEAL_QUANTITY_PLAN, title: "餐前剂量方案", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_BASIC_QUANTITY_PLAN, title: "基础量方案", group: "状态与设置", indexBytes: 0, note: "3B 头 + 每点 3B"),
        CommandDef(id: Cmd.GET_TEMPORARY_BASIC_QUANTITY_PLAN, title: "临时基础量方案", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_PARAMETER_SETTINGS, title: "参数设置", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_SYSTEM_CONFIG, title: "系统配置", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_ALARM_INFORMATION, title: "报警信息", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_PRE_MEAL_QUANTITY_SETTINGS, title: "餐前剂量设置", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_ACTIVE_INSULIN, title: "活性胰岛素 IOB", group: "状态与设置", indexBytes: 0, note: "厂商为空实现，只能看原始字节"),
        CommandDef(id: Cmd.GET_THE_AMOUNT_OF_INPUT_PER_HOUR, title: "每小时输注量", group: "状态与设置", indexBytes: 0, note: "24×2B/100"),
        CommandDef(id: Cmd.GET_THE_TOTAL_DAYS, title: "使用总天数", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_THE_TOTAL_AMOUNT_OF_DAY, title: "当日总量", group: "状态与设置", indexBytes: 0, note: "4B 头 + 24×2B/100"),
        CommandDef(id: Cmd.GET_ALL_INFUSION_SETTING_INFORMATION, title: "全部输注设置", group: "状态与设置", indexBytes: 0, note: "19 字段"),
        CommandDef(id: Cmd.GET_ALL_STATUS_INFORMATION, title: "全部状态", group: "状态与设置", indexBytes: 0, note: "17 字段"),

        // ---- 记录
        CommandDef(id: Cmd.GET_THE_NUMBER_OF_RECORDS, title: "记录条数", group: "记录", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_ALL_RECORD_QUANTITIES, title: "各类记录条数", group: "记录", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_FOUR_PRE_MEAL_INFUSION_RECORDS, title: "四组餐前输注记录", group: "记录", indexBytes: 1, note: "4 条 ×16B"),
        CommandDef(id: Cmd.GET_FOUR_DAILY_TOTAL_QUANTITY_RECORDS, title: "四组当日总量记录", group: "记录", indexBytes: 1, note: "key = start+i"),
        CommandDef(id: Cmd.GET_FOUR_SHUTDOWN_RECORDS, title: "四组关机记录", group: "记录", indexBytes: 1, note: "key = start+i"),
        CommandDef(id: Cmd.GET_FOUR_OPERATION_RECORDS, title: "四组操作记录", group: "记录", indexBytes: 2, note: "索引 2B 大端"),
        CommandDef(id: Cmd.GET_PRE_MEAL_INFUSION_RECORDS, title: "单条餐前记录", group: "记录", indexBytes: 1, note: "分帧规则未确证"),
        CommandDef(id: Cmd.GET_DAILY_TOTAL_QUANTITY_RECORDS, title: "单条当日总量记录", group: "记录", indexBytes: 1, note: "分帧规则未确证"),
        CommandDef(id: Cmd.GET_SHUTDOWN_RECORDS, title: "单条关机记录", group: "记录", indexBytes: 1, note: "分帧规则未确证"),

        // ---- 系统与工厂
        CommandDef(id: Cmd.GET_SYSTEM_SETTINGS_INFORMATION, title: "系统设置信息", group: "系统与工厂", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_FACTORY_MODE_DATA, title: "工厂模式数据", group: "系统与工厂", indexBytes: 0, note: "只读，危险区"),
        CommandDef(id: Cmd.GET_VERSION, title: "泵版本", group: "系统与工厂", indexBytes: 0, note: "主/从版本各 4 段"),
    ]

    static let groups = ["状态与设置", "记录", "系统与工厂"]

    static func grouped(_ g: String) -> [CommandDef] {
        all.filter { $0.group == g }
    }
}

// ---------------------------------------------------------------- 结果展示

func prettyPairs(_ v: Any, prefix: String = "", into out: inout [(String, String)]) {
    if let d = v as? [String: Any] {
        for k in sortedKeys(Array(d.keys)) {
            prettyPairs(d[k]!, prefix: prefix.isEmpty ? k : "\(prefix).\(k)", into: &out)
        }
    } else if let d = v as? [String: Double] {
        for k in sortedKeys(Array(d.keys)) {
            out.append((prefix.isEmpty ? k : "\(prefix).\(k)", String(format: "%.2f", d[k]!)))
        }
    } else if let d = v as? [String: Int] {
        for k in sortedKeys(Array(d.keys)) {
            out.append((prefix.isEmpty ? k : "\(prefix).\(k)", String(d[k]!)))
        }
    } else if let b = v as? Bool {
        out.append((prefix, b ? "是" : "否"))
    } else if let i = v as? Int {
        out.append((prefix, String(i)))
    } else if let d = v as? Double {
        out.append((prefix, String(format: "%.2f", d)))
    } else {
        out.append((prefix, "\(v)"))
    }
}

private func sortedKeys(_ keys: [String]) -> [String] {
    return keys.sorted { a, b in
        if let x = Int(a), let y = Int(b) { return x < y }
        return a < b
    }
}

struct ResultSection: View {
    let result: ParsedResponse

    var body: some View {
        Section(header: Text("结果 · \(result.name)")
            .textCase(nil)
            .font(.subheadline)) {
            let pairs = makePairs()
            if pairs.isEmpty {
                Text("（无字段）").font(.caption).foregroundColor(.secondary)
            }
            ForEach(pairs.indices, id: \.self) { i in
                HStack(alignment: .top) {
                    Text(pairs[i].0).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(pairs[i].1).font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
            }
            if !result.raw.isEmpty && pairs.isEmpty {
                Text(result.raw.hex).font(.system(.caption2, design: .monospaced))
            }
            if !result.note.isEmpty {
                Text(result.note).font(.caption2).foregroundColor(.orange)
            }
        }
    }

    private func makePairs() -> [(String, String)] {
        var out: [(String, String)] = []
        prettyPairs(result.fields, into: &out)
        return out
    }
}

// ---------------------------------------------------------------- 全量命令面板

enum SheetKind: String, Identifiable {
    case infusion, limits, basal, confirm
    var id: String { rawValue }
}

struct AllCommandsView: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    @State private var indexText = "1"
    @State private var result: ParsedResponse? = nil
    @State private var sheet: SheetKind? = nil
    @State private var pendingSummary = ""
    @State private var pendingAction: (() -> Void)? = nil

    var body: some View {
        List {
            if let r = result { ResultSection(result: r) }

            Section(header: Text("索引（记录类命令用）")) {
                HStack {
                    Text("起始索引")
                    TextField("1", text: $indexText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }

            ForEach(Catalog.groups, id: \.self) { g in
                Section(header: Text(g)) {
                    ForEach(Catalog.grouped(g)) { d in
                        Button {
                            run(d)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title)
                                    Text(String(format: "0x%04X", d.id)).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                if d.indexBytes > 0 {
                                    Text("需索引").font(.caption2).foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            }

            Section(header: Text("写入（会改变泵）")) {
                Button {
                    sheet = .infusion
                } label: { Label("输注面板（0x00A2 / 0x00A3）", systemImage: "drop.fill") }
                    .foregroundColor(.red)
                Button {
                    sheet = .limits
                } label: { Label("泵限值（0x00A0）", systemImage: "gauge") }
                Button {
                    sheet = .basal
                } label: { Label("基础率方案（0x00A1）", systemImage: "chart.bar") }
                Button {
                    ask(summary: "把泵时钟同步为手机当前时间？") {
                        sendDateTime()
                    }
                } label: { Text("同步时间（0x00A4）") }
                Button {
                    ask(summary: "取消当前的临时基础率？") {
                        pump.runCommand(Cmd.CANCEL_TEMPORARY_BASIC_VOLUME_INFUSION)
                    }
                } label: { Text("取消临时基础率（0x00A5）") }
                Button {
                    ask(summary: "取消当前的大剂量输注？") {
                        pump.runCommand(Cmd.CANCEL_PRE_MEAL_VOLUME_INFUSION)
                    }
                } label: { Text("取消大剂量（0x00A6）") }
            }
        }
        .navigationTitle("全部功能")
        .toolbar {
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .infusion:
                InfusionSheet(pump: pump)
            case .limits:
                LimitsSheet(pump: pump)
            case .basal:
                BasalSheet(pump: pump)
            case .confirm:
                ConfirmView(summary: pendingSummary) {
                    pendingAction?()
                    pendingAction = nil
                    sheet = nil
                    pump.log("OK", "已下发：\(pendingSummary)")
                }
            }
        }
    }

    private func ask(summary: String, action: @escaping () -> Void) {
        pendingSummary = summary
        pendingAction = action
        sheet = .confirm
    }

    private func run(_ d: CommandDef) {
        var payload: [UInt8] = []
        if d.indexBytes > 0 {
            let idx = Int(indexText.trimmingCharacters(in: .whitespaces)) ?? 1
            if d.indexBytes == 1 {
                payload = [UInt8(max(0, min(255, idx)))]
            } else {
                payload = [UInt8((idx >> 8) & 0xFF), UInt8(idx & 0xFF)]
            }
        }
        pump.runCommand(d.id, payload: payload) { p in
            DispatchQueue.main.async { self.result = p }
        }
    }

    private func sendDateTime() {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        var dt = Params.SetDatetime(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1,
                                    hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0)
        dt.year = c.year ?? 2026
        guard let payload = try? dt.bytes() else { return }
        pump.runCommand(Cmd.SET_THE_CURRENT_DATETIME, payload: payload)
    }
}

// ---------------------------------------------------------------- 0x00A0 泵限值

struct LimitsSheet: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    @State private var concentration = "100"
    @State private var lowDosage = "1"
    @State private var maxBolus = "10"
    @State private var maxBasal = "3"
    @State private var limitQty = "50"
    @State private var showConfirm = false
    @State private var err = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("单位语义未在真机核对，先按保守值")) {
                    row("浓度", $concentration)
                    row("最低剂量", $lowDosage)
                    row("最大大剂量", $maxBolus)
                    row("最大基础率", $maxBasal)
                    row("限量", $limitQty)
                }
                if !err.isEmpty { Section { Text(err).foregroundColor(.red).font(.caption) } }
                Section {
                    Button("校验并下发") { check() }.foregroundColor(.red)
                }
            }
            .navigationTitle("泵限值 0x00A0")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showConfirm) {
                ConfirmView(summary: "写入泵限值：浓度 \(concentration) / 最低 \(lowDosage) / 最大大剂量 \(maxBolus) / 最大基础率 \(maxBasal) / 限量 \(limitQty)") {
                    send()
                }
            }
        }
    }

    private func row(_ t: String, _ b: Binding<String>) -> some View {
        HStack { Text(t); TextField("", text: b).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
    }

    private func check() {
        err = ""
        let vals = [concentration, lowDosage, maxBolus, maxBasal, limitQty].compactMap { Int($0) }
        guard vals.count == 5 else { err = "五个字段都必须是整数"; return }
        guard vals[0...3].allSatisfy({ $0 >= 0 && $0 <= 255 }) else { err = "前四个字段必须在 0..255"; return }
        guard vals[4] >= 0 && vals[4] <= 65535 else { err = "限量必须在 0..65535"; return }
        showConfirm = true
    }

    private func send() {
        var p = Params.PumpLimits()
        p.concentration = Int(concentration) ?? 100
        p.lowDosage = Int(lowDosage) ?? 1
        p.maxBolus = Int(maxBolus) ?? 10
        p.maxBasal = Int(maxBasal) ?? 3
        p.limitQuantity = Int(limitQty) ?? 50
        guard let payload = try? p.bytes() else { err = "参数越界"; showConfirm = false; return }
        pump.runCommand(Cmd.SET_INFUSION_PARAMETERS, payload: payload)
        showConfirm = false
    }
}

// ---------------------------------------------------------------- 0x00A1 基础率方案

struct BasalSheet: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    @State private var values = "0"
    @State private var showConfirm = false
    @State private var err = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("24 个整点基础率，逗号分隔（U/h）"),
                        footer: Text("例：0.5,0.5,0.6,0.6,0.6,0.7… 共 24 个值，对应 0:00–23:00。写入前先核对总日剂量。")) {
                    TextField("0.5,0.5,…", text: $values)
                        .font(.system(.caption, design: .monospaced))
                }
                if !err.isEmpty { Section { Text(err).foregroundColor(.red).font(.caption) } }
                Section {
                    Button("校验并下发") { check() }.foregroundColor(.red)
                }
            }
            .navigationTitle("基础率方案 0x00A1")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showConfirm) {
                ConfirmView(summary: "写入 24 段基础率：\(parsed().map { String(format: "%.2f", $0) }.joined(separator: "/")) U/h") {
                    send()
                }
            }
        }
    }

    private func parsed() -> [Double] {
        values.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .compactMap { Double(String($0)) }
    }

    private func check() {
        err = ""
        let v = parsed()
        guard v.count == 24 else { err = "必须正好 24 个值，当前 \(v.count) 个"; return }
        guard v.allSatisfy({ $0 >= 0 && $0 <= 20 }) else { err = "单个值应在 0..20 U/h"; return }
        let total = v.reduce(0, +)
        guard total <= 60 else { err = String(format: "日总量 %.2fU 过高，拒绝写入", total); return }
        showConfirm = true
    }

    private func send() {
        var p = Params.BasalProfile()
        p.start = 0
        p.end = 23
        p.points = parsed()
        guard let payload = try? p.bytes() else { err = "参数越界"; showConfirm = false; return }
        pump.runCommand(Cmd.SET_BASIC_VOLUME_INFUSION_PARAMETERS, payload: payload)
        showConfirm = false
    }
}

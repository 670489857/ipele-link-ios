import SwiftUI

struct CommandDef: Identifiable {
    let id: Int
    let title: String
    let group: String
    let indexBytes: Int   // 0=无入参，1=1B 起始索引，2=2B 起始索引
    let note: String
    var fixedPayload: [UInt8]? = nil   // 固定载荷（如 0x00F2 需要 [mode,start,end]）
}

enum Catalog {
    static let all: [CommandDef] = [
        // ---- 状态与设置
        CommandDef(id: Cmd.GET_REMAINMED_AND_ISWITCH, title: "剩余药量与输注开关", group: "状态与设置", indexBytes: 0, note: "2 字段"),
        CommandDef(id: Cmd.GET_PRE_MEAL_QUANTITY_PLAN, title: "餐前剂量方案", group: "状态与设置", indexBytes: 0, note: ""),
        CommandDef(id: Cmd.GET_BASIC_QUANTITY_PLAN, title: "基础量方案", group: "状态与设置", indexBytes: 0, note: "3B 头 + 每点 3B（48 个半小时点 0–47）", fixedPayload: [0x00, 0x00, 0x2F]),
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
    out.append(contentsOf: L.pairs(v, prefix: prefix))
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
        Section(header: Text("结果 · \(L.responseName(result.name))")
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
    case infusion, limits, basal
    var id: String { rawValue }
}

struct ReadGroupView: View {
    @ObservedObject var pump: PumpClient
    let group: String

    @State private var indexText = "1"
    @State private var result: ParsedResponse? = nil
    @State private var hint = ""

    private var defs: [CommandDef] { Catalog.grouped(group) }
    private var needsIndex: Bool { defs.contains { $0.indexBytes > 0 } }

    var body: some View {
        List {
            if !hint.isEmpty {
                Section { Text(hint).font(.caption).foregroundColor(.orange) }
            }
            if let r = result { ResultSection(result: r) }
            if needsIndex {
                Section(header: Text("起始索引"),
                        footer: Text("记录类命令的入参。0x00E0–E2 用 1 字节，0x00E3 用 2 字节；单条记录 0x00F8/9/A 的索引字节为推断值。")) {
                    HStack {
                        Text("起始索引")
                        TextField("1", text: $indexText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            Section(header: Text("\(group) · \(defs.count) 条")) {
                ForEach(defs) { d in
                    Button { run(d) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.title)
                                HStack(spacing: 8) {
                                    Text(String(format: "0x%04X", d.id))
                                    if !d.note.isEmpty { Text(d.note) }
                                }
                                .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            if d.indexBytes > 0 {
                                Text("索引").font(.caption2).foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(group)
    }

    private func run(_ d: CommandDef) {
        guard pump.connected else {
            hint = "未连接泵，命令发不出去。先回首页扫描并连接。"
            return
        }
        hint = ""
        var payload: [UInt8] = d.fixedPayload ?? []
        if d.indexBytes > 0 {
            let idx = Int(indexText.trimmingCharacters(in: .whitespaces)) ?? 1
            payload = d.indexBytes == 1
                ? [UInt8(max(0, min(255, idx)))]
                : [UInt8((idx >> 8) & 0xFF), UInt8(idx & 0xFF)]
        }
        pump.runCommand(d.id, payload: payload) { p in
            DispatchQueue.main.async { self.result = p }
        }
    }
}

struct WritesView: View {
    @ObservedObject var pump: PumpClient
    @State private var sheet: SheetKind? = nil
    @State private var hint = ""

    var body: some View {
        List {
            Section(footer: Text("未连接时只能浏览参数，下发会先被本地拒绝。")) {
                Text("点一下直接下发，不再二次确认；本地安全校验仍然生效，超时不会自动重发。")
                    .font(.caption).foregroundColor(.secondary)
            }
            if !hint.isEmpty {
                Section { Text(hint).font(.caption).foregroundColor(.orange) }
            }
            Section(header: Text("输注")) {
                Button { open(.infusion) } label: {
                    Label("输注面板（0x00A2 / 0x00A3）", systemImage: "drop.fill").foregroundColor(.red)
                }
                Button { ask("取消当前的临时基础率？") { pump.runCommand(Cmd.CANCEL_TEMPORARY_BASIC_VOLUME_INFUSION, payload: [0, 0, 0, 0]) } } label: {
                    Text("取消临时基础率（0x00A5）")
                }
                Button { ask("取消当前的大剂量输注？") { pump.runCommand(Cmd.CANCEL_PRE_MEAL_VOLUME_INFUSION, payload: [0, 0, 0, 0]) } } label: {
                    Text("取消大剂量（0x00A6）")
                }
            }
            Section(header: Text("泵配置")) {
                Button { open(.limits) } label: {
                    Label("泵限值（0x00A0）", systemImage: "gauge")
                }
                Button { open(.basal) } label: {
                    Label("基础率方案（0x00A1）", systemImage: "chart.bar")
                }
                Button { ask("把泵时钟同步为手机当前时间？") { sendDateTime() } } label: {
                    Text("同步时间（0x00A4）")
                }
            }
        }
        .navigationTitle("写入")
        .sheet(item: $sheet) { kind in
            switch kind {
            case .infusion: InfusionSheet(pump: pump)
            case .limits: LimitsSheet(pump: pump)
            case .basal: BasalSheet(pump: pump)
            }
        }
    }

    private func online() -> Bool {
        if !pump.connected {
            hint = "未连接泵：先在首页扫描并连接，再回来下发。"
            return false
        }
        hint = ""
        return true
    }

    private func open(_ k: SheetKind) {
        guard online() else { return }
        sheet = k
    }

    private func ask(_ summary: String, action: @escaping () -> Void) {
        guard online() else { return }
        _ = summary
        action()
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
    @State private var err = ""
    @State private var sent = false
    @State private var loaded = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("泵内整数原值"),
                        footer: Text("先点下面「读取泵内当前值（0x00E5）」，按泵实际值改，不要凭默认值硬发。")) {
                    row("浓度", $concentration)
                    row("最低剂量", $lowDosage)
                    row("最大大剂量", $maxBolus)
                    row("最大基础率", $maxBasal)
                    row("限量", $limitQty)
                }
                if !err.isEmpty { Section { Text(err).foregroundColor(.red).font(.caption) } }
                Section {
                    Button("读取泵内当前值（0x00E5）") { loadFromPump() }
                        .foregroundColor(.blue)
                    Button("直接下发泵限值（0x00A0）") { checkAndSend() }
                        .foregroundColor(.red)
                }
                if sent {
                    Section(header: Text("泵应答")) {
                        Text(pump.busy ? "下发中…" : pump.lastAck).font(.caption)
                        if !pump.verifyText.isEmpty {
                            Text(pump.verifyText).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("泵限值 0x00A0")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear { if !loaded { loadFromPump() } }
        }
    }

    private func row(_ t: String, _ b: Binding<String>) -> some View {
        HStack { Text(t); TextField("", text: b).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
    }

    private func loadFromPump() {
        guard pump.connected else { err = "未连接泵，读不到当前值"; return }
        err = ""
        pump.runCommand(Cmd.GET_ALL_INFUSION_SETTING_INFORMATION) { p in
            DispatchQueue.main.async {
                guard let p = p else { err = "0x00E5 无应答"; return }
                if let v = p.int("concentration") { concentration = String(v) }
                if let v = p.int("low_dosage_threshold") { lowDosage = String(v) }
                if let v = p.int("maximum_amount") { maxBolus = String(v) }
                if let v = p.int("maximum_basic_quantity") { maxBasal = String(v) }
                if let v = p.int("limit_quantity") { limitQty = String(v) }
                loaded = true
            }
        }
    }

    private func checkAndSend() {
        err = ""
        sent = false
        let vals = [concentration, lowDosage, maxBolus, maxBasal, limitQty].compactMap { Int($0) }
        guard vals.count == 5 else { err = "五个字段都必须是整数"; return }
        guard vals[0...3].allSatisfy({ $0 >= 0 && $0 <= 255 }) else { err = "前四个字段必须在 0..255"; return }
        guard vals[4] >= 0 && vals[4] <= 65535 else { err = "限量必须在 0..65535"; return }
        var p = Params.PumpLimits()
        p.concentration = vals[0]
        p.lowDosage = vals[1]
        p.maxBolus = vals[2]
        p.maxBasal = vals[3]
        p.limitQuantity = vals[4]
        guard let payload = try? p.bytes() else { err = "参数越界"; return }
        pump.runCommand(Cmd.SET_INFUSION_PARAMETERS, payload: payload, verify: true)
        sent = true
    }
}

struct BasalSheet: View {
    @ObservedObject var pump: PumpClient
    @Environment(\.dismiss) private var dismiss

    @State private var rate = "0.15"
    @State private var err = ""
    @State private var sent = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("默认基础率（U/h）"),
                        footer: Text("填一个值，自动铺满 48 个半小时点：0:00、0:30 … 23:30，每点相同。")) {
                    HStack {
                        Text("每小时")
                        TextField("0.15", text: $rate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if !err.isEmpty { Section { Text(err).foregroundColor(.red).font(.caption) } }
                Section {
                    Button("直接下发（48 个点）") { sendNow() }.foregroundColor(.red)
                }
                if sent {
                    Section(header: Text("泵应答")) {
                        Text(pump.busy ? "下发中…" : pump.lastAck)
                            .font(.caption)
                        if !pump.verifyText.isEmpty {
                            Text(pump.verifyText).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("基础率方案 0x00A1")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private func sendNow() {
        err = ""
        sent = false
        let text = rate.replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
        guard let v = Double(text), v >= 0, v <= 20 else {
            err = "基础率必须是 0–20 U/h 的数字"
            return
        }
        let total = v * 48
        guard total <= 60 else {
            err = String(format: "日总量 %.2fU 超过 60U，拒绝写入；请把每小时值降到 1.25 以下", total)
            return
        }
        var p = Params.BasalProfile()
        p.start = 0
        p.end = 47
        p.points = Array(repeating: v, count: 48)
        guard let payload = try? p.bytes() else { err = "参数越界"; return }
        pump.runCommand(Cmd.SET_BASIC_VOLUME_INFUSION_PARAMETERS, payload: payload, verify: true)
        sent = true
    }
}

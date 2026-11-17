import Foundation

/// 响应字段表 —— 与 Kotlin/Python SDK 同一份数据（由 v1.5 字段表生成）。
/// 偏移来自 classes6.dex 各 DataConvertToObject() 的字节码。

struct Field {
    let n: String
    let o: Int
    let k: String     // u8 | be | dec | le_be | le_dec | hex
    let s: Int
    let div: Double
    let sc: Int
}

enum Layout {
    case fields([Field], time: Bool)
    case ack
    case pointMap([Field])
    case hourMap(off: Int, count: Int, stride: Int, header: [Field])
    case factory([Field])
    case four(startOff: Int, startSize: Int, recOff: Int, stride: Int, count: Int, recordCmd: Int, keyAddI: Bool)
    case rawEmpty
}

struct LayoutSpec {
    let name: String
    let layout: Layout
    let note: String
}

enum Responses {

    static let RSP_CODES: [Int: String] = [
        0: "OK", 1: "NG 一般失败", 2: "UNKNOW 未知的消息ID",
        3: "ERROR 消息格式错误或参数错误", 4: "INVALID 请求的数据无效",
        5: "INHAND 泵忙正在处理其他任务中", 6: "DENIED 远程开关未开，请检查设置"
    ]

    static let OPERATION_RECORD: [Field] = [
        Field("year", 0, "u8", 1, 100.0, 2), Field("month", 1, "u8", 1, 100.0, 2),
        Field("day", 2, "u8", 1, 100.0, 2), Field("hour", 3, "u8", 1, 100.0, 2),
        Field("minute", 4, "u8", 1, 100.0, 2), Field("second", 5, "u8", 1, 100.0, 2),
        Field("operation_id", 6, "le_be", 4, 100.0, 2)
    ]

    static let LAYOUTS: [Int: LayoutSpec] = [
        0x80A0: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80A1: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80A2: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80A3: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80A4: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80A5: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80A6: LayoutSpec(name: "ReturnResponse", layout: .ack, note: "LEN=7 且 data[6]<=9 时为 RSP_* 错误码帧"),
        0x80E0: LayoutSpec(name: "FourPreMealInfusionRecords", layout: .four(startOff: 0, startSize: 1, recOff: 1, stride: 16, count: 4, recordCmd: 0x80F8, keyAddI: true), note: "startIndex 1B；4 条 16B 子记录；跳过 year==0；key = startIndex+i"),
        0x80E1: LayoutSpec(name: "FourDailyTotalQuantityRecords", layout: .four(startOff: 0, startSize: 1, recOff: 1, stride: 16, count: 4, recordCmd: 0x80F9, keyAddI: true), note: "startIndex 1B；4 条 16B 子记录；跳过 year==0；key = startIndex+i（与 0x80E0 同）"),
        0x80E2: LayoutSpec(name: "FourShutdownRecords", layout: .four(startOff: 0, startSize: 1, recOff: 1, stride: 16, count: 4, recordCmd: 0x80FA, keyAddI: true), note: "同 0x80E1：key = startIndex+i"),
        0x80E3: LayoutSpec(name: "FourOperationRecords", layout: .four(startOff: 0, startSize: 2, recOff: 2, stride: 16, count: 4, recordCmd: 0x80E3, keyAddI: true), note: "startIndex 是 2B 大端（与其他三个不同）；记录从 off=2 起"),
        0x80E4: LayoutSpec(name: "AllRecordQuantities", layout: .fields([Field("pre_meal_records", 0, "u8", 1, 100.0, 2), Field("daily_total_records", 1, "u8", 1, 100.0, 2), Field("shutdown_records", 2, "u8", 1, 100.0, 2), Field("operation_records", 3, "be", 2, 100.0, 2)], time: false), note: ""),
        0x80E5: LayoutSpec(name: "AllInfusionSettingInformation", layout: .fields([Field("preprandial_dose", 0, "dec", 2, 100.0, 2), Field("pre_meal_duration", 2, "be", 2, 100.0, 2), Field("long_meal_waveform", 4, "u8", 1, 100.0, 2), Field("dual_wave_mode_ratio", 5, "u8", 1, 100.0, 2), Field("infusion_interval", 6, "u8", 1, 100.0, 2), Field("meal_preset_switches", 7, "u8", 1, 100.0, 2), Field("pre_set_quantity1", 8, "dec", 2, 100.0, 2), Field("pre_set_quantity2", 10, "dec", 2, 100.0, 2), Field("pre_set_quantity3", 12, "dec", 2, 100.0, 2), Field("basic_quantity_mode", 14, "u8", 1, 100.0, 2), Field("proximity_percentage_switch", 15, "u8", 1, 100.0, 2), Field("base_velocity", 16, "dec", 2, 100.0, 2), Field("foundation_duration", 18, "be", 2, 100.0, 2), Field("base_percentage", 20, "be", 2, 100.0, 2), Field("concentration", 22, "u8", 1, 100.0, 2), Field("low_dosage_threshold", 23, "u8", 1, 100.0, 2), Field("maximum_amount", 24, "u8", 1, 100.0, 2), Field("maximum_basic_quantity", 25, "u8", 1, 100.0, 2), Field("limit_quantity", 26, "be", 2, 100.0, 2)], time: false), note: "28B；可反推 0x00A0/0x00A2/0x00A3 写入参数布局"),
        0x80E6: LayoutSpec(name: "AllStatusInformation", layout: .fields([Field("infusion_switch", 0, "u8", 1, 100.0, 2), Field("remaining_dosage", 1, "dec", 4, 100.0, 2), Field("pressure", 5, "be", 2, 100.0, 2), Field("encoder", 7, "be", 4, 100.0, 2), Field("battery", 11, "be", 2, 100.0, 2), Field("alarm_number", 13, "u8", 1, 100.0, 2)], time: false), note: "14B；编码器 4 字节，注意与 0x80F0 的 4B 剂量不同"),
        0x80E7: LayoutSpec(name: "SystemSettingsInformation", layout: .fields([Field("year", 0, "u8", 1, 100.0, 2), Field("month", 1, "u8", 1, 100.0, 2), Field("day", 2, "u8", 1, 100.0, 2), Field("hour", 3, "u8", 1, 100.0, 2), Field("minute", 4, "u8", 1, 100.0, 2), Field("second", 5, "u8", 1, 100.0, 2), Field("quiet_mode", 6, "u8", 1, 100.0, 2), Field("battery_percentage", 7, "u8", 1, 100.0, 2), Field("rest_day_mode_switch", 8, "u8", 1, 100.0, 2), Field("bt_switch", 9, "u8", 1, 100.0, 2), Field("screen_rest_time", 10, "be", 2, 100.0, 2), Field("alarm_level", 12, "u8", 1, 100.0, 2)], time: true), note: "13B；LocalDateTime.of(year+2000, ...)"),
        0x80E8: LayoutSpec(name: "FactoryModeData", layout: .factory([Field("calibration_data", 0, "be", 4, 100.0, 2), Field("block1", 4, "be", 2, 100.0, 2), Field("block2", 6, "be", 2, 100.0, 2), Field("block3", 8, "be", 2, 100.0, 2), Field("block4", 10, "be", 2, 100.0, 2), Field("block5", 12, "be", 2, 100.0, 2), Field("screen_brightness", 14, "u8", 1, 100.0, 2), Field("hardware_version_number", 15, "u8", 1, 100.0, 2), Field("serial_number", 16, "be", 4, 100.0, 2), Field("master_version1", 20, "be", 2, 100.0, 2), Field("master_version2", 22, "be", 2, 100.0, 2), Field("master_version3", 24, "be", 2, 100.0, 2), Field("master_version4", 26, "hex", 2, 100.0, 2), Field("slave_version1", 28, "be", 2, 100.0, 2), Field("slave_version2", 30, "be", 2, 100.0, 2), Field("slave_version3", 32, "be", 2, 100.0, 2), Field("slave_version4", 34, "hex", 2, 100.0, 2)]), note: "36B；版本号串 = v1.v2.v3.v4"),
        0x80E9: LayoutSpec(name: "Version", layout: .fields([Field("version1", 0, "u8", 1, 100.0, 2), Field("version2", 1, "u8", 1, 100.0, 2), Field("version3", 2, "u8", 1, 100.0, 2)], time: false), note: "3B；此前 v1.4 误当作 2B major/minor，已更正"),
        0x80F0: LayoutSpec(name: "RemainMedicalAndSwitch", layout: .fields([Field("infusion_switch", 0, "u8", 1, 100.0, 2), Field("remaining_dosage", 1, "dec", 4, 100.0, 2)], time: false), note: "剩余药量 BigDecimal(4B/100, 2位)"),
        0x80F1: LayoutSpec(name: "PreMealQuantityPlan", layout: .fields([Field("dose", 0, "dec", 2, 100.0, 2), Field("duration", 2, "be", 2, 100.0, 2), Field("wave_form", 4, "u8", 1, 100.0, 2)], time: false), note: ""),
        0x80F2: LayoutSpec(name: "BasicQuantityPlan", layout: .pointMap([Field("mode", 0, "u8", 1, 100.0, 2), Field("start_time_point", 1, "u8", 1, 100.0, 2), Field("end_time_point", 2, "u8", 1, 100.0, 2)]), note: "点表：每条 3B = [时间点u8][剂量2B/100]，条数 = end-start+1，从 off=3 起"),
        0x80F3: LayoutSpec(name: "TemporaryBasicQuantityPlan", layout: .fields([Field("speed", 0, "dec", 2, 100.0, 2), Field("duration", 2, "be", 2, 100.0, 2), Field("percentage", 4, "be", 2, 100.0, 2), Field("percentage_switch", 6, "u8", 1, 100.0, 2)], time: false), note: "getter 名原厂拼作 getErcentageSwitch"),
        0x80F4: LayoutSpec(name: "ParameterSettings", layout: .fields([Field("concentration", 0, "u8", 1, 100.0, 2), Field("low_dosage_threshold", 1, "u8", 1, 100.0, 2), Field("maximum_amount", 2, "u8", 1, 100.0, 2), Field("maximum_basic", 3, "u8", 1, 100.0, 2), Field("limit_quantity", 4, "be", 2, 100.0, 2)], time: false), note: "前 4 项各 1B，限量 2B 大端；与 SetInfusionParameter 布局一致"),
        0x80F5: LayoutSpec(name: "SystemConfig", layout: .fields([Field("year", 0, "u8", 1, 100.0, 2), Field("month", 1, "u8", 1, 100.0, 2), Field("day", 2, "u8", 1, 100.0, 2), Field("hour", 3, "u8", 1, 100.0, 2), Field("minute", 4, "u8", 1, 100.0, 2), Field("second", 5, "u8", 1, 100.0, 2), Field("quiet_mode", 6, "u8", 1, 100.0, 2), Field("battery_percentage", 7, "u8", 1, 100.0, 2), Field("rest_day_mode_switch", 8, "u8", 1, 100.0, 2)], time: true), note: "LocalDateTime.of(year+2000, ...)"),
        0x80F6: LayoutSpec(name: "AlarmInformation", layout: .fields([Field("alarm_number_present", 0, "u8", 1, 100.0, 2)], time: false), note: ""),
        0x80F7: LayoutSpec(name: "TheNumberOfRecords", layout: .fields([Field("pre_meal_records", 0, "u8", 1, 100.0, 2), Field("daily_total_records", 1, "u8", 1, 100.0, 2), Field("shutdown_records", 2, "u8", 1, 100.0, 2)], time: false), note: ""),
        0x80F8: LayoutSpec(name: "PreMealInfusionRecord", layout: .fields([Field("year", 0, "u8", 1, 100.0, 2), Field("month", 1, "u8", 1, 100.0, 2), Field("day", 2, "u8", 1, 100.0, 2), Field("hour", 3, "u8", 1, 100.0, 2), Field("minute", 4, "u8", 1, 100.0, 2), Field("second", 5, "u8", 1, 100.0, 2), Field("pre_meal_amount", 6, "le_dec", 4, 100.0, 2), Field("duration", 10, "le_be", 3, 100.0, 2), Field("wave", 13, "u8", 1, 100.0, 2)], time: false), note: "14B 有效 + 2B 保留 = 16B；小端 4B ÷1000"),
        0x80F9: LayoutSpec(name: "DailyTotalQuantityRecord", layout: .fields([Field("year", 0, "u8", 1, 100.0, 2), Field("month", 1, "u8", 1, 100.0, 2), Field("day", 2, "u8", 1, 100.0, 2), Field("hour", 3, "u8", 1, 100.0, 2), Field("minute", 4, "u8", 1, 100.0, 2), Field("second", 5, "u8", 1, 100.0, 2), Field("pre_meal_amount", 6, "le_dec", 4, 100.0, 2)], time: false), note: "10B 有效；小端 4B ÷1000"),
        0x80FA: LayoutSpec(name: "ShutdownRecord", layout: .fields([Field("year", 0, "u8", 1, 100.0, 2), Field("month", 1, "u8", 1, 100.0, 2), Field("day", 2, "u8", 1, 100.0, 2), Field("hour", 3, "u8", 1, 100.0, 2), Field("minute", 4, "u8", 1, 100.0, 2), Field("second", 5, "u8", 1, 100.0, 2), Field("shut_code", 6, "le_be", 4, 100.0, 2)], time: false), note: "10B 有效；小端 4B 整数"),
        0x80FB: LayoutSpec(name: "PreMealQuantitySettings", layout: .fields([Field("infusion_interval", 0, "be", 2, 100.0, 2), Field("pre_set_quantity1", 2, "dec", 2, 100.0, 2), Field("pre_set_quantity2", 4, "dec", 2, 100.0, 2), Field("pre_set_quantity3", 6, "dec", 2, 100.0, 2)], time: false), note: ""),
        0x80FC: LayoutSpec(name: "ActiveInsulin", layout: .rawEmpty, note: "IOB：厂商 DataConvertToObject() 为空实现，只保留原始 data；无数值可读"),
        0x80FD: LayoutSpec(name: "TheAmountOfInputPerHour", layout: .hourMap(off: 0, count: 24, stride: 2, header: []), note: "24 个小时量，每个 2B/100，key=0..23"),
        0x80FE: LayoutSpec(name: "TheTotalDays", layout: .fields([Field("total_days", 0, "u8", 1, 100.0, 2)], time: false), note: ""),
        0x80FF: LayoutSpec(name: "TheTotalAmountOfDay", layout: .hourMap(off: 4, count: 24, stride: 2, header: [Field("id", 0, "u8", 1, 100.0, 2), Field("year", 1, "u8", 1, 100.0, 2), Field("month", 2, "u8", 1, 100.0, 2), Field("day", 3, "u8", 1, 100.0, 2)]), note: "4B 头 + 24 个小时量(2B/100)"),
    ]


    static func u8(_ d: [UInt8], _ o: Int) -> Int { o < d.count ? Int(d[o]) : 0 }

    static func be(_ d: [UInt8], _ o: Int, _ n: Int) -> Int {
        var v = 0
        for i in 0..<n where o + i < d.count { v = (v << 8) | Int(d[o + i]) }
        return v
    }

    static func leBe(_ d: [UInt8], _ o: Int, _ n: Int) -> Int {
        var v = 0
        for i in (0..<n).reversed() where o + i < d.count { v = (v << 8) | Int(d[o + i]) }
        return v
    }

    static func dec(_ d: [UInt8], _ o: Int, _ n: Int, _ div: Double, _ sc: Int) -> Double {
        let raw = Double(be(d, o, n)) / div
        let f = pow(10.0, Double(sc))
        return (raw * f).rounded() / f
    }

    static func leDec(_ d: [UInt8], _ o: Int, _ n: Int, _ div: Double, _ sc: Int) -> Double {
        let raw = Double(leBe(d, o, n)) / div
        let f = pow(10.0, Double(sc))
        return (raw * f).rounded() / f
    }

    static func read(_ d: [UInt8], _ f: Field) -> Any {
        switch f.k {
        case "u8": return u8(d, f.o)
        case "be": return be(d, f.o, f.s)
        case "dec": return dec(d, f.o, f.s, f.div, f.sc)
        case "le_be": return leBe(d, f.o, f.s)
        case "le_dec": return leDec(d, f.o, f.s, f.div, f.sc)
        case "hex":
            let lo = min(f.o, d.count)
            let hi = min(f.o + f.s, d.count)
            return d[lo..<hi].map { String(format: "%02X", $0) }.joined()
        default: return 0
        }
    }

    static func readAll(_ d: [UInt8], _ fs: [Field]) -> [String: Any] {
        var m: [String: Any] = [:]
        for f in fs { m[f.n] = read(d, f) }
        return m
    }

    /// LEN==7 且 data[0]<=9 → RSP_* 错误应答帧
    static func isErrorFrame(len: Int, _ d: [UInt8]) -> Bool {
        return len == 7 && !d.isEmpty && d[0] <= 9
    }

    static func isRetryNotify(_ d: [UInt8]) -> Bool { d.count == 1 && d[0] == 0x80 }

    static func decode(cmd: Int, data: [UInt8]) -> ParsedResponse {
        guard let spec = LAYOUTS[cmd] else {
            return ParsedResponse(cmd: cmd, name: String(format: "UNKNOWN_%04X", cmd), fields: [:], raw: data, note: "")
        }
        var fields: [String: Any] = [:]
        switch spec.layout {
        case .rawEmpty:
            fields["raw_hex"] = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .ack:
            let c = data.isEmpty ? 0 : Int(data[0])
            fields["code"] = c
            fields["ok"] = (c == 0)
            fields["meaning"] = RSP_CODES[c] ?? "未定义的返回码"
        case .fields(let fs, let time):
            fields = readAll(data, fs)
            if time, let y = fields["year"] as? Int {
                let yy = y + 2000
                let mo = fields["month"] as? Int ?? 0
                let da = fields["day"] as? Int ?? 0
                let ho = fields["hour"] as? Int ?? 0
                let mi = fields["minute"] as? Int ?? 0
                let se = fields["second"] as? Int ?? 0
                fields["time"] = String(format: "%04d-%02d-%02d %02d:%02d:%02d", yy, mo, da, ho, mi, se)
            }
        case .pointMap(let fs):
            fields = readAll(data, fs)
            let start = fields["start_time_point"] as? Int ?? 0
            let end = fields["end_time_point"] as? Int ?? 0
            let n = max(0, end - start + 1)
            var pts: [String: Double] = [:]
            var o = 3
            for _ in 0..<n where o + 3 <= data.count {
                pts[String(u8(data, o))] = dec(data, o + 1, 2, 100.0, 2)
                o += 3
            }
            fields["point_list"] = pts
        case .hourMap(let off, let count, let stride, let header):
            fields = readAll(data, header)
            var hours: [String: Double] = [:]
            var o = off
            for i in 0..<count where o + stride <= data.count {
                hours[String(i)] = dec(data, o, stride, 100.0, 2)
                o += stride
            }
            fields["map_amount"] = hours
        case .factory(let fs):
            fields = readAll(data, fs)
            func ver(_ p: String) -> String {
                return (1...4).map { String(describing: fields[p + String($0)] ?? "") }.joined(separator: ".")
            }
            fields["master_version"] = ver("master_version")
            fields["slave_version"] = ver("slave_version")
        case .four(let startOff, let startSize, let recOff, let stride, let count, let recordCmd, let keyAddI):
            let start = be(data, startOff, startSize)
            fields["start_index"] = start
            let child: [Field]
            if recordCmd == 0x80E3 { child = OPERATION_RECORD }
            else if case .fields(let fs, _)? = LAYOUTS[recordCmd]?.layout { child = fs }
            else { child = [] }
            var recs: [String: Any] = [:]
            var o = recOff
            for i in 0..<count where o + stride <= data.count {
                let sub = Array(data[o..<(o + stride)])
                let sf = readAll(sub, child)
                if (sf["year"] as? Int ?? 0) != 0 {
                    let key = keyAddI ? start + i : start
                    recs[String(key)] = sf
                }
                o += stride
            }
            fields["records"] = recs
        }
        return ParsedResponse(cmd: cmd, name: spec.name, fields: fields, raw: data, note: spec.note)
    }
}

struct ParsedResponse {
    let cmd: Int
    let name: String
    let fields: [String: Any]
    let raw: [UInt8]
    let note: String

    func int(_ k: String) -> Int? { fields[k] as? Int }
    func dbl(_ k: String) -> Double? { fields[k] as? Double }
    func str(_ k: String) -> String? { fields[k] as? String }
    func bool(_ k: String) -> Bool? { fields[k] as? Bool }

    var summary: String {
        fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: "  ")
    }
}

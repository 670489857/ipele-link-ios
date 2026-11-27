import Foundation

/// 把泵上报的英文字段名统一翻成中文，并把 records.N.xxx 折叠成一行可读记录。
enum L {
    static let fieldNames: [String: String] = [
        // 状态
        "alarm_number": "报警编号",
        "alarm_level": "报警等级",
        "alarm_number_present": "有报警",
        "battery": "电量原始值",
        "battery_percentage": "电量百分比",
        "encoder": "编码器",
        "infusion_switch": "输注开关",
        "pressure": "压力",
        "remaining_dosage": "剩余药量",

        // 输注参数 / 泵限值
        "concentration": "浓度",
        "low_dosage_threshold": "最小剂量",
        "maximum_amount": "最大大剂量",
        "maximum_basic": "最大基础率",
        "maximum_basic_quantity": "最大基础率",
        "limit_quantity": "限量",
        "preprandial_dose": "餐前剂量",
        "pre_meal_duration": "餐前时长",
        "pre_meal_amount": "餐前剂量",
        "long_meal_waveform": "大剂量波形",
        "dual_wave_mode_ratio": "双波比例",
        "infusion_interval": "输注间隔",
        "meal_preset_switches": "餐前预设开关",
        "pre_set_quantity1": "预设量 1",
        "pre_set_quantity2": "预设量 2",
        "pre_set_quantity3": "预设量 3",
        "basic_quantity_mode": "基础率模式",
        "proximity_percentage_switch": "接近百分比开关",
        "base_velocity": "基础速率",
        "foundation_duration": "基础时长",
        "base_percentage": "基础百分比",
        "dose": "剂量",
        "duration": "时长（分钟）",
        "percentage": "百分比",
        "percentage_switch": "百分比开关",
        "wave_form": "波形",
        "wave": "波形",
        "speed": "速率",
        "mode": "模式",
        "start_time_point": "起始时间点",
        "end_time_point": "结束时间点",
        "start_index": "起始索引",

        // 系统 / 工厂
        "year": "年",
        "month": "月",
        "day": "日",
        "hour": "时",
        "minute": "分",
        "second": "秒",
        "quiet_mode": "静音模式",
        "rest_day_mode_switch": "休息日模式",
        "bt_switch": "蓝牙开关",
        "screen_rest_time": "息屏时间",
        "screen_brightness": "屏幕亮度",
        "hardware_version_number": "硬件版本号",
        "serial_number": "序列号",
        "calibration_data": "校准数据",
        "block1": "数据块 1",
        "block2": "数据块 2",
        "block3": "数据块 3",
        "block4": "数据块 4",
        "block5": "数据块 5",
        "master_version1": "主版本 1",
        "master_version2": "主版本 2",
        "master_version3": "主版本 3",
        "master_version4": "主版本 4",
        "slave_version1": "从版本 1",
        "slave_version2": "从版本 2",
        "slave_version3": "从版本 3",
        "slave_version4": "从版本 4",
        "master_version": "主版本",
        "slave_version": "从版本",
        "version1": "协议版本 1",
        "version2": "协议版本 2",
        "version3": "协议版本 3",
        "shut_code": "关机代码",
        "total_days": "使用总天数",
        "operation_id": "操作编号",
        "id": "编号",
        "time": "时间",

        // 记录 / 表
        "records": "记录",
        "point_list": "基础率点表",
        "map_amount": "每小时量",
        "pre_meal_records": "餐前记录条数",
        "daily_total_records": "当日总量记录条数",
        "shutdown_records": "关机记录条数",
        "operation_records": "操作记录条数",
        "records_count": "记录条数"
    ]

    static let responseNames: [String: String] = [
        "AllStatusInformation": "全部状态",
        "AllInfusionSettingInformation": "全部输注设置",
        "AllRecordQuantities": "各类记录条数",
        "TheNumberOfRecords": "记录条数",
        "RemainingDosageAndInfusionSwitch": "剩余药量与输注开关",
        "BasicQuantityPlan": "基础率方案",
        "TemporaryBasicQuantityPlan": "临时基础率",
        "PreMealQuantityPlan": "餐前剂量方案",
        "ParameterSettings": "参数设置",
        "SystemConfig": "系统配置",
        "SystemSettingsInformation": "系统设置",
        "AlarmInformation": "报警信息",
        "FactoryModeData": "工厂数据",
        "VersionResponse": "通信协议版本",
        "FourPreMealInfusionRecords": "餐前输注记录",
        "FourDailyTotalQuantityRecords": "当日总量记录",
        "FourShutdownRecords": "关机记录",
        "FourOperationRecords": "操作记录",
        "PreMealInfusionRecords": "餐前记录",
        "DailyTotalQuantityRecords": "当日总量记录",
        "ShutdownRecords": "关机记录",
        "TheAmountOfInputPerHour": "每小时输注量",
        "TheTotalDays": "使用总天数",
        "TheTotalAmountOfDay": "当日总量",
        "ReturnResponse": "写入应答"
    ]

    static func responseName(_ raw: String) -> String {
        if let v = responseNames[raw] { return v }
        if raw.hasPrefix("RSP ") { return "错误应答 · " + responseName(String(raw.dropFirst(4))) }
        return raw
    }

    static func label(_ key: String) -> String {
        if key.hasPrefix("records.") {
            let parts = key.split(separator: ".")
            if parts.count == 2 { return "记录 \(parts[1])" }
            if parts.count >= 3 { return "记录 \(parts[1]) · \(label(parts.dropFirst(2).joined(separator: ".")))" }
        }
        if key.hasPrefix("point_list."), let idx = Int(key.dropFirst("point_list.".count)) {
            return String(format: "时段 %02d:%02d", idx / 2, (idx % 2) * 30)
        }
        if key.hasPrefix("map_amount."), let h = Int(key.dropFirst("map_amount.".count)) {
            return String(format: "%02d:00", h)
        }
        if key.hasPrefix("records_count."), let n = Int(key.dropFirst("records_count.".count)) {
            return "第 \(n) 条"
        }
        return fieldNames[key] ?? key
    }

    static func sortedKeys(_ keys: [String]) -> [String] {
        keys.sorted { a, b in
            if let x = Int(a), let y = Int(b) { return x < y }
            return a < b
        }
    }

    static func isRecord(_ d: [String: Any]) -> Bool {
        d["year"] != nil && d["month"] != nil && d["day"] != nil
    }

    static func recordText(_ d: [String: Any]) -> String {
        let y = int(d["year"]) ?? 0
        let year = y < 100 ? y + 2000 : y
        let date = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                          year, int(d["month"]) ?? 0, int(d["day"]) ?? 0,
                          int(d["hour"]) ?? 0, int(d["minute"]) ?? 0, int(d["second"]) ?? 0)
        let op = int(d["operation_id"]).map { " · 操作 \($0)" } ?? ""
        return date + op
    }

    private static func int(_ v: Any?) -> Int? {
        guard let v = v else { return nil }
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    static func valueText(_ v: Any) -> String {
        if let b = v as? Bool { return b ? "是" : "否" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(format: "%.2f", d) }
        return "\(v)"
    }

    static func pairs(_ v: Any, prefix: String = "") -> [(String, String)] {
        var out: [(String, String)] = []
        walk(v, prefix: prefix, into: &out)
        return out
    }

    private static func walk(_ v: Any, prefix: String, into out: inout [(String, String)]) {
        if let d = v as? [String: Any] {
            if !prefix.isEmpty && isRecord(d) {
                out.append((label(prefix), recordText(d)))
                return
            }
            for k in sortedKeys(Array(d.keys)) {
                walk(d[k]!, prefix: prefix.isEmpty ? k : "\(prefix).\(k)", into: &out)
            }
        } else if let d = v as? [String: Double] {
            for k in sortedKeys(Array(d.keys)) {
                out.append((label(prefix.isEmpty ? k : "\(prefix).\(k)"), String(format: "%.2f", d[k]!)))
            }
        } else if let d = v as? [String: Int] {
            for k in sortedKeys(Array(d.keys)) {
                out.append((label(prefix.isEmpty ? k : "\(prefix).\(k)"), String(d[k]!)))
            }
        } else {
            out.append((label(prefix), valueText(v)))
        }
    }

    static func flatSummary(_ fields: [String: Any]) -> String {
        pairs(fields).map { "\($0.0)=\($0.1)" }.joined(separator: "；")
    }
}

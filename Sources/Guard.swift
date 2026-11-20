import Foundation

/// 输注前置校验 —— 与 Android 版同一组硬上限，另加三条 iOS 侧增强：
/// 1. 未知开关状态一律拒绝（必须先读到 0x00F0）
/// 2. 水测试模式把上限压到 0.5U / 1.0U·h⁻¹
/// 3. 一小时内累计 >15U 直接拒绝
enum Guard {
    static let maxBolusU = 10.0
    static let maxTbrRate = 3.0
    static let minTbrMin = 15
    static let maxTbrMin = 240
    static let maxPercent = 200

    static let waterMaxBolus = 0.5
    static let waterMaxTbr = 1.0
    static let sessionMaxUnits = 15.0

    struct Result {
        let ok: Bool
        let msg: String
    }

    static func parseUnits(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let d = Double(t), d.isFinite, d > 0 else { return nil }
        let rounded = (d * 100).rounded() / 100
        guard rounded > 0 else { return nil }
        return rounded
    }

    static func checkBolus(units: Double, remaining: Double?, switchOn: Bool?,
                           sessionUnits: Double = 0, waterTest: Bool = false) -> Result {
        if units <= 0 { return Result(ok: false, msg: "剂量必须大于 0") }
        if switchOn == nil {
            return Result(ok: false, msg: "还没读到泵的输注开关状态，先读 0x00F0 再下发")
        }
        if switchOn == false { return Result(ok: false, msg: "泵的输注开关处于关闭状态，请先在泵上开启") }
        if units > maxBolusU {
            return Result(ok: false, msg: String(format: "剂量 %.2fU 超过本地硬上限 %.2fU", units, maxBolusU))
        }
        if waterTest && units > waterMaxBolus {
            return Result(ok: false, msg: String(format: "水测试模式单次上限 %.2fU，当前 %.2fU", waterMaxBolus, units))
        }
        if sessionUnits + units > sessionMaxUnits {
            return Result(ok: false, msg: String(format: "一小时内累计将达 %.2fU，超过会话上限 %.0fU", sessionUnits + units, sessionMaxUnits))
        }
        if let r = remaining, units > r {
            return Result(ok: false, msg: String(format: "剂量 %.2fU 超过剩余药量 %.2fU", units, r))
        }
        return Result(ok: true, msg: String(format: "大剂量 %.2fU 通过本地校验", units))
    }

    static func checkTbr(rate: Double?, percent: Int?, minutes: Int,
                         remaining: Double?, switchOn: Bool?,
                         sessionUnits: Double = 0, waterTest: Bool = false) -> Result {
        if rate != nil && percent != nil { return Result(ok: false, msg: "速率与百分比只能填一个") }
        if rate == nil && percent == nil { return Result(ok: false, msg: "请填写速率或百分比") }
        if minutes < minTbrMin || minutes > maxTbrMin {
            return Result(ok: false, msg: "时长必须在 \(minTbrMin)..\(maxTbrMin) 分钟")
        }
        if switchOn == nil {
            return Result(ok: false, msg: "还没读到泵的输注开关状态，先读 0x00F0 再下发")
        }
        if switchOn == false { return Result(ok: false, msg: "泵的输注开关处于关闭状态，请先在泵上开启") }

        if let r = rate {
            if r < 0 { return Result(ok: false, msg: "速率不能为负") }
            if r > maxTbrRate {
                return Result(ok: false, msg: String(format: "速率 %.2fU/h 超过本地硬上限 %.2fU/h", r, maxTbrRate))
            }
            if waterTest && r > waterMaxTbr {
                return Result(ok: false, msg: String(format: "水测试模式速率上限 %.2fU/h，当前 %.2fU/h", waterMaxTbr, r))
            }
            let total = r * Double(minutes) / 60.0
            if sessionUnits + total > sessionMaxUnits {
                return Result(ok: false, msg: String(format: "一小时内累计将达 %.2fU，超过会话上限 %.0fU", sessionUnits + total, sessionMaxUnits))
            }
            if let rem = remaining, total > rem {
                return Result(ok: false, msg: String(format: "本次共需 %.2fU，超过剩余药量 %.2fU", total, rem))
            }
            return Result(ok: true, msg: String(format: "临时基础率 %.2fU/h × %dmin 通过本地校验", r, minutes))
        }

        let p = percent ?? 0
        if p <= 0 || p > maxPercent {
            return Result(ok: false, msg: "百分比必须在 1..\(maxPercent)")
        }
        return Result(ok: true, msg: "临时基础率 \(p)% × \(minutes)min 通过本地校验")
    }
}

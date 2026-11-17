import Foundation

/// 写参数的报文布局 —— 逆向自 com.lifescimp.blesdk.cmd.parameter.*.toByteArray()。
/// 剂量字段一律 ×100 的大端整数。
///
/// ⚠️ 这些报文会改变人体胰岛素输注，必须经 Guard 校验后下发。
enum Params {

    static func units(_ v: Double) -> UInt16 {
        let raw = Int((v * 100).rounded())
        return UInt16(max(0, min(0xFFFF, raw)))
    }

    /// 0x00A2 临时基础率（11B）：[0]百分比开关 [1:3]速率 [3:5]时长 [5:7]百分比 [7:11]保留
    struct TempBasal {
        var rateUPerHour: Double? = nil
        var percent: Int? = nil
        var minutes: Int

        func bytes() throws -> [UInt8] {
            guard (rateUPerHour == nil) != (percent == nil) else {
                throw Crypto.CryptoError(msg: "速率与百分比必须且只能给一个")
            }
            var buf = [UInt8](repeating: 0, count: 11)
            if let p = percent {
                buf[0] = 1
                let u = UInt16(max(0, min(0xFFFF, p)))
                buf[5] = UInt8((u >> 8) & 0xFF)
                buf[6] = UInt8(u & 0xFF)
            } else {
                let u = units(rateUPerHour!)
                buf[1] = UInt8((u >> 8) & 0xFF)
                buf[2] = UInt8(u & 0xFF)
            }
            let d = UInt16(max(0, min(0xFFFF, minutes)))
            buf[3] = UInt8((d >> 8) & 0xFF)
            buf[4] = UInt8(d & 0xFF)
            return buf
        }
    }

    /// 0x00A3 大剂量（13B）：剂量2B 时长2B 波形1B 双波比1B 间隔2B 间隔开关1B + 4×0
    struct Bolus {
        var unitsValue: Double
        var minutes: Int = 0
        var waveform: Int = 0
        var dualRatio: Int = 0
        var intervalMinutes: Int = 0
        var intervalSwitch: Int = 0

        func bytes() -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: 13)
            let u = units(unitsValue)
            buf[0] = UInt8((u >> 8) & 0xFF)
            buf[1] = UInt8(u & 0xFF)
            let d = UInt16(max(0, min(0xFFFF, minutes)))
            buf[2] = UInt8((d >> 8) & 0xFF)
            buf[3] = UInt8(d & 0xFF)
            buf[4] = UInt8(max(0, min(255, waveform)))
            buf[5] = UInt8(max(0, min(255, dualRatio)))
            let iv = UInt16(max(0, min(0xFFFF, intervalMinutes)))
            buf[6] = UInt8((iv >> 8) & 0xFF)
            buf[7] = UInt8(iv & 0xFF)
            buf[8] = UInt8(max(0, min(255, intervalSwitch)))
            return buf
        }
    }

    /// 0x00A0 泵限值（10B）：浓度/最低剂量/最大大剂量/最大基础率 各1B + 限量2B + 4×0
    struct PumpLimits {
        var concentration: Int = 100
        var lowDosage: Int = 1
        var maxBolus: Int = 10
        var maxBasal: Int = 3
        var limitQuantity: Int = 50

        func bytes() throws -> [UInt8] {
            for v in [concentration, lowDosage, maxBolus, maxBasal] where v < 0 || v > 255 {
                throw Crypto.CryptoError(msg: "单个字节字段超出 0..255：\(v)")
            }
            var buf = [UInt8](repeating: 0, count: 10)
            buf[0] = UInt8(concentration)
            buf[1] = UInt8(lowDosage)
            buf[2] = UInt8(maxBolus)
            buf[3] = UInt8(maxBasal)
            let q = UInt16(max(0, min(0xFFFF, limitQuantity)))
            buf[4] = UInt8((q >> 8) & 0xFF)
            buf[5] = UInt8(q & 0xFF)
            return buf
        }
    }

    /// 0x00A4 设置时间（10B）：年(2位) 月 日 时 分 秒 + 4×0
    struct SetDatetime {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var second: Int

        func bytes() throws -> [UInt8] {
            guard (1...12).contains(month), (1...31).contains(day),
                  (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
                throw Crypto.CryptoError(msg: "时间字段越界")
            }
            var buf = [UInt8](repeating: 0, count: 10)
            buf[0] = UInt8(year % 100)
            buf[1] = UInt8(month)
            buf[2] = UInt8(day)
            buf[3] = UInt8(hour)
            buf[4] = UInt8(minute)
            buf[5] = UInt8(second)
            return buf
        }
    }

    /// 0x00A1 基础率方案：8 + n×2 字节
    struct BasalProfile {
        var mode: Int = 0
        var setupMode: Int = 0
        var autoBasal: Double = 0
        var start: Int = 0
        var end: Int = 23
        var points: [Double] = []

        func bytes() throws -> [UInt8] {
            let n = end - start + 1
            guard n > 0, points.count == n else {
                throw Crypto.CryptoError(msg: "基础率点数 \(points.count) 与区间 \(n) 不匹配")
            }
            var buf = [UInt8](repeating: 0, count: 8 + n * 2)
            buf[0] = UInt8(max(0, min(255, mode)))
            buf[1] = UInt8(max(0, min(255, setupMode)))
            let a = units(autoBasal)
            buf[2] = UInt8((a >> 8) & 0xFF)
            buf[3] = UInt8(a & 0xFF)
            buf[4] = 0
            buf[5] = 0
            buf[6] = UInt8(max(0, min(255, start)))
            buf[7] = UInt8(max(0, min(255, end)))
            var o = 8
            for p in points {
                let u = units(p)
                buf[o] = UInt8((u >> 8) & 0xFF)
                buf[o + 1] = UInt8(u & 0xFF)
                o += 2
            }
            return buf
        }
    }
}

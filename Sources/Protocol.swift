import Foundation

/// 帧格式与 CRC —— 与 Android/Python SDK 二进制一致。
///
/// 55 AA | LEN(1B) | SEQ(1B) | CMD(2B 大端) | DATA | CRC(2B 小端)
/// LEN = 6 + DATA.count（不含 CRC）；CRC-16/CCITT-FALSE 覆盖 START..DATA。
enum Proto {
    static let start1: UInt8 = 0x55
    static let start2: UInt8 = 0xAA
    static let headerLen = 6
    static let crcLen = 2

    static let queueIntervalMs = 800
    static let responseTimeoutMs = 6000

    static let serviceUUID = "0000FFF0-0000-1000-8000-00805F9B34FB"
    static let notifyUUID = "0000FFF1-0000-1000-8000-00805F9B34FB"
    static let writeUUID = "0000FFF2-0000-1000-8000-00805F9B34FB"

    static func crc16(_ bytes: [UInt8]) -> Int {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return Int(crc & 0xFFFF)
    }

    /// 组帧。payload 为空且 padded=true 时按原厂写法补单字节 0xFF（LEN=7）。
    static func build(cmd: Int, data: [UInt8], seq: Int, padded: Bool = false) -> [UInt8] {
        var body = data
        if body.isEmpty && padded { body = [0xFF] }
        let len = headerLen + body.count
        var frame: [UInt8] = [start1, start2, UInt8(len & 0xFF), UInt8(seq & 0xFF),
                              UInt8((cmd >> 8) & 0xFF), UInt8(cmd & 0xFF)]
        frame.append(contentsOf: body)
        let c = crc16(frame)
        frame.append(UInt8(c & 0xFF))
        frame.append(UInt8((c >> 8) & 0xFF))
        return frame
    }

    static func verify(_ frame: [UInt8]) -> Bool {
        guard frame.count >= headerLen + crcLen else { return false }
        let body = Array(frame[0..<(frame.count - crcLen)])
        let c = crc16(body)
        let lo = Int(frame[frame.count - crcLen])
        let hi = Int(frame[frame.count - crcLen + 1])
        return c == (lo | (hi << 8))
    }
}

struct Frame {
    let cmd: Int
    let data: [UInt8]
    let seq: Int
}

/// 分包重组：服务端可能把一帧拆成多次通知。
final class FrameAssembler {
    private var buf: [UInt8] = []

    func feed(_ bytes: [UInt8]) -> [Frame] {
        buf.append(contentsOf: bytes)
        var out: [Frame] = []
        while true {
            guard let idx = startIndex() else { buf.removeAll(); break }
            if idx > 0 { buf.removeFirst(idx) }
            if buf.count < 3 { break }
            let total = Int(buf[2]) + Proto.crcLen
            if buf.count < total { break }
            let piece = Array(buf[0..<total])
            buf.removeFirst(total)
            if Proto.verify(piece), piece.count >= Proto.headerLen {
                let cmd = (Int(piece[4]) << 8) | Int(piece[5])
                let seq = Int(piece[3])
                let data = Array(piece[Proto.headerLen..<(piece.count - Proto.crcLen)])
                out.append(Frame(cmd: cmd, data: data, seq: seq))
            }
        }
        return out
    }

    func reset() { buf.removeAll() }

    private func startIndex() -> Int? {
        guard buf.count >= 2 else { return nil }
        for i in 0..<(buf.count - 1) where buf[i] == Proto.start1 && buf[i + 1] == Proto.start2 {
            return i
        }
        return nil
    }
}

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

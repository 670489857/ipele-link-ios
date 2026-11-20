import Foundation
import CommonCrypto

/// 报文加解密 —— 与厂商 DataUtils 逐字节一致。
///
/// 1. 密钥 = SN 末 8 位，每个字符展开成 "0"+c+"00" → 32 位 hex → AES-128
/// 2. AES/ECB/**NoPadding**
/// 3. 按 16 字节分组，末组尾部补 0x00（已对齐则不补）；整帧（含 55 AA 与 CRC）一起加密
/// 4. 解密后按 LEN 截断，去掉尾部补零
enum Crypto {
    struct CryptoError: Error, LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    static func keyFromSN(_ sn: String) throws -> [UInt8] {
        let clean = sn.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 8 else {
            throw CryptoError(msg: "序列号至少需要 8 位，当前 \(clean.count) 位")
        }
        let tail = String(clean.suffix(8))
        for ch in tail where !ch.isHexDigit {
            throw CryptoError(msg: "序列号后 8 位必须是十六进制字符（0-9 / A-F），发现 '\(ch)'")
        }
        // 每个字符展开成 "0"+c+"00"，拼成 32 位 hex，再按 2 个字符一个字节解析
        let hex = tail.map { "0\($0)00" }.joined()
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            let pair = String(hex[i..<j])
            guard let v = UInt8(pair, radix: 16) else {
                throw CryptoError(msg: "密钥派生失败：\(pair)")
            }
            out.append(v)
            i = j
        }
        return out
    }

    static func encrypt(key: [UInt8], plain: [UInt8]) throws -> [UInt8] {
        guard plain.count > 0 else { return [] }
        var padded = plain
        if padded.count % 16 != 0 {
            padded.append(contentsOf: [UInt8](repeating: 0, count: 16 - padded.count % 16))
        }
        return try run(op: CCOperation(kCCEncrypt), key: key, data: padded)
    }

    static func decrypt(key: [UInt8], cipher: [UInt8]) throws -> [UInt8] {
        guard cipher.count > 0 else { return [] }
        guard cipher.count % 16 == 0 else {
            throw CryptoError(msg: "密文长度 \(cipher.count) 不是 16 的整数倍")
        }
        return try run(op: CCOperation(kCCDecrypt), key: key, data: cipher)
    }

    private static func run(op: CCOperation, key: [UInt8], data: [UInt8]) throws -> [UInt8] {
        guard key.count == 16 || key.count == 24 || key.count == 32 else {
            throw CryptoError(msg: "非法 AES 密钥长度: \(key.count) 字节")
        }
        var out = [UInt8](repeating: 0, count: data.count)
        let outLen = out.count
        let keyLen = key.count
        let inLen = data.count
        var moved = 0
        let status: Int32 = key.withUnsafeBytes { (kb: UnsafeRawBufferPointer) -> Int32 in
            data.withUnsafeBytes { (db: UnsafeRawBufferPointer) -> Int32 in
                out.withUnsafeMutableBytes { (ob: UnsafeMutableRawBufferPointer) -> Int32 in
                    CCCrypt(op, CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode),
                            kb.baseAddress, keyLen, nil,
                            db.baseAddress, inLen,
                            ob.baseAddress, outLen, &moved)
                }
            }
        }
        guard status == Int32(kCCSuccess) else {
            throw CryptoError(msg: "CCCrypt 失败，状态 \(status)")
        }
        return Array(out[0..<moved])
    }

    /// 解密后按帧头 LEN 截断；若 0 位置不是 55 AA，在前 16 字节内搜一次帧头。
    static func trimToFrame(_ decrypted: [UInt8]) -> [UInt8] {
        guard decrypted.count >= 3 else { return decrypted }
        var off = 0
        if decrypted[0] != Proto.start1 || decrypted[1] != Proto.start2 {
            let limit = min(16, decrypted.count - 1)
            var i = 1
            while i < limit {
                if decrypted[i] == Proto.start1 && decrypted[i + 1] == Proto.start2 {
                    off = i
                    break
                }
                i += 1
            }
            if off == 0 { return decrypted }
        }
        let total = Int(decrypted[off + 2]) + Proto.crcLen
        let end = off + total
        return end <= decrypted.count ? Array(decrypted[off..<end]) : Array(decrypted[off...])
    }
}

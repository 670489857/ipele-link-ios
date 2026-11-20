import Foundation
import Darwin

// 协议层自检向量：每次构建前跑，防止改动把帧格式、CRC、AES 改坏。

var failed = 0
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        print("PASS  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
    } else {
        print("FAIL  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
        failed += 1
    }
}

let crc = Proto.crc16(Array("123456789".utf8))
check("CRC-16/CCITT-FALSE 向量", crc == 0x29B1, String(format: "0x%04X", crc))

let short = Proto.build(cmd: 0x00F0, data: [], seq: 1)
check("空载帧 LEN=6", short[2] == 6, "LEN=\(short[2])")
check("空载帧 CRC 自校验", Proto.verify(short))

let padded = Proto.build(cmd: 0x00F0, data: [], seq: 1, padded: true)
check("原厂写法 LEN=7 且 DATA=FF", padded[2] == 7 && padded[6] == 0xFF)

let cmdBytes = [short[4], short[5]]
check("命令码大端 0x00F0", cmdBytes == [0x00, 0xF0])

let key = try! Crypto.keyFromSN("E5F60718")
check("SN 派生密钥长度 16", key.count == 16)
let expectKey: [UInt8] = [0x0E, 0x00, 0x05, 0x00, 0x0F, 0x00, 0x06, 0x00,
                          0x00, 0x00, 0x07, 0x00, 0x01, 0x00, 0x08, 0x00]
check("SN 派生密钥字节", key == expectKey, key.map { String(format: "%02X", $0) }.joined(separator: " "))

let ct = try! Crypto.encrypt(key: key, plain: padded)
check("密文按 16B 对齐", ct.count % 16 == 0, "\(ct.count)B")
let round = Crypto.trimToFrame(try! Crypto.decrypt(key: key, cipher: ct))
check("加解密往返一致", round == padded)

let longFrame = Proto.build(cmd: 0x00A0, data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], seq: 2)
check("非对齐长度补零到 32B", (try! Crypto.encrypt(key: key, plain: longFrame)).count == 32)
let back2 = Crypto.trimToFrame(try! Crypto.decrypt(key: key, cipher: try! Crypto.encrypt(key: key, plain: longFrame)))
check("补零后可还原原帧", back2 == longFrame, "\(longFrame.count)B")

var threw = false
do { _ = try Crypto.keyFromSN("ZZZZZZZZ") } catch { threw = true }
check("非法 SN 抛错", threw)

// 响应字段：0x80F0 两字段偏移
let f0 = Responses.decode(cmd: 0x80F0, data: [0x01, 0x00, 0x00, 0x13, 0x88])
check("0x80F0 开关解析", f0.int("infusion_switch") == 1)
check("0x80F0 剩余药量 50.00", f0.dbl("remaining_dosage") == 50.0, "\(f0.dbl("remaining_dosage") ?? -1)")

print(failed == 0 ? "ALL PASS" : "\(failed) FAILED")
exit(failed == 0 ? 0 : 1)

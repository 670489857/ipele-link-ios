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

// 通知按字节拆分：先来 0x55，再来 0xAA…，整帧不能被丢掉
let sample = Proto.build(cmd: 0x00F0, data: [], seq: 3, padded: true)
let asm1 = FrameAssembler()
let a1 = asm1.feed([sample[0]])
let a2 = asm1.feed(Array(sample[1...]))
check("单字节 0x55 保留", a1.isEmpty && a2.count == 1 && a2[0].cmd == 0x00F0, "frames=\(a2.count)")

let asm2 = FrameAssembler()
let b1 = asm2.feed(Array(sample[0..<3]))
let b2 = asm2.feed(Array(sample[3...]))
check("帧跨 3 段重组", b1.isEmpty && b2.count == 1)

// 帧与帧之间的垃圾字节要被丢掉，不能污染下一帧
let asm3 = FrameAssembler()
let c1 = asm3.feed(sample)
let junk = asm3.feed([0x12, 0x34])
let c2 = asm3.feed(sample)
check("帧间垃圾后能恢复", c1.count == 1 && c2.count == 1 && junk.isEmpty)

// 参数越界必须抛错，不能静默截断后下发
var threwRate = false
do { _ = try Params.TempBasal(rateUPerHour: 30, percent: nil, minutes: 60).bytes() } catch { threwRate = true }
check("速率 30U/h 抛错", threwRate)

var threwDose = false
do { _ = try Params.Bolus(unitsValue: 30).bytes() } catch { threwDose = true }
check("剂量 30U 抛错", threwDose)

// 普通大剂量必须带厂商的波形/比值/间隔：0.10U → 00 0A 00 00 04 0A 00 0A 00 + 4×0
let bolus01 = (try? Params.Bolus(unitsValue: 0.10).bytes()) ?? []
check("0.10U 大剂量字节=厂商布局",
      bolus01 == [0x00, 0x0A, 0, 0, 0x04, 0x0A, 0, 0x0A, 0, 0, 0, 0, 0],
      "got \(bolus01.hex)")

var threwMin = false
do { _ = try Params.TempBasal(rateUPerHour: 0.5, percent: nil, minutes: 0).bytes() } catch { threwMin = true }
check("时长 0 分钟抛错", threwMin)

// 百分比 TBR：没有基础率、换算超 3U/h、水测试上限
var g1 = Guard.checkTbr(rate: nil, percent: 100, minutes: 60, remaining: 50,
                        switchOn: true, sessionUnits: 0, waterTest: false, basalRate: nil)
check("百分比无基础率拒绝", !g1.ok, g1.msg)

var g2 = Guard.checkTbr(rate: nil, percent: 200, minutes: 60, remaining: 50,
                        switchOn: true, sessionUnits: 0, waterTest: false, basalRate: 3.0)
check("200%×3U/h=6U/h 拒绝", !g2.ok, g2.msg)

var g3 = Guard.checkTbr(rate: nil, percent: 100, minutes: 60, remaining: 50,
                        switchOn: true, sessionUnits: 0, waterTest: false, basalRate: 0.96)
check("100%×0.96U/h 放行", g3.ok, g3.msg)

var g4 = Guard.checkTbr(rate: nil, percent: 150, minutes: 60, remaining: 50,
                        switchOn: true, sessionUnits: 0, waterTest: true, basalRate: 0.5)
check("水测试 150%×0.5=0.75U/h 放行", g4.ok, g4.msg)

var g5 = Guard.checkTbr(rate: nil, percent: 200, minutes: 240, remaining: 50,
                        switchOn: true, sessionUnits: 12, waterTest: false, basalRate: 1.0)
check("换算后超 15U/h 预算拒绝", !g5.ok, g5.msg)

print(failed == 0 ? "ALL PASS" : "\(failed) FAILED")
exit(failed == 0 ? 0 : 1)

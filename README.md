# IpeleLink iOS（v1.6 工程版）

艾派乐（Ipele）胰岛素泵的 **独立 iOS 客户端**，不是 AAPS 插件。协议层与 Android 版 / Python SDK 二进制一致，
响应字段表由 Kotlin 版 `IpeleResponses.kt` 程序化生成，避免手抄偏移出错。

## 能力

- CoreBluetooth 扫描 / 连接（Service `FFF0`，Notify `FFF1`，Write `FFF2`）
- 帧组装 + CRC-16/CCITT-FALSE、AES-128-ECB 加解密（密钥＝SN 末 8 位）
- 33 条命令，26 条只读响应的字段解析
- 写入：`0x00A3` 大剂量、`0x00A2` 临时基础率、`0x00A5/0x00A6` 取消
- 本地护栏：大剂量 ≤10U、TBR ≤3U/h（或 ≤200%）、时长 15–240min、不得超剩余药量、泵侧开关关闭即拒
- 二次确认（3 秒倒计时）、超时**不自动重发**、全程通信日志

## 构建

仓库自带 GitHub Actions：推送到 `main` 即用 `macos-14` 编译并产出 `IpeleLink-unsigned.ipa`。
本地构建（需 macOS + Xcode）：

```bash
bash scripts/build_ipa.sh
```

产物是**未签名 IPA**，安装前需用 Sideloadly / AltStore / TrollStore 以你自己的证书重签。

## 首次使用

1. 设置 → 填泵序列号后 8 位（十六进制）
2. 扫描 → 选择设备 → 连接
3. 先读 `0x00F0`，能拿到剩余药量再往下走（读不到说明加密/帧未通，别试写入）
4. 水测试：输液器装纯水，从 0.10U 开始，核对泵屏幕与出水量

## 安全边界

工程模式写入未经真机验证。禁止人体首测。泵侧仍有 `maximum_amount` / `limit_quantity` 等硬限制作为最后防线，
但读数语义未在真机核对，App 侧的本地上限不能替代它们。

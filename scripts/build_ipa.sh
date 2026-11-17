#!/bin/bash
# 在 macOS runner 上把 Swift 源码直接编成 .app 再打包成 IPA。
# 不依赖 xcodeproj，避免手写 pbxproj 出错。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="IpeleLink"
OUT="build"
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

rm -rf "$OUT"
mkdir -p "$OUT/Payload/$APP_NAME.app"

echo "== SDK: $SDK_PATH"
xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios15.0 \
  -sdk "$SDK_PATH" \
  -O -parse-as-library \
  Sources/*.swift \
  -o "$OUT/Payload/$APP_NAME.app/$APP_NAME"

cp Resources/Info.plist "$OUT/Payload/$APP_NAME.app/Info.plist"
printf 'APPL????' > "$OUT/Payload/$APP_NAME.app/PkgInfo"

# ad-hoc 签名（真机安装前仍需 Sideloadly/AltStore/TrollStore 用你的证书重签）
codesign --force --sign - --timestamp=none "$OUT/Payload/$APP_NAME.app" || echo "ad-hoc 签名失败，保持未签名"

cd "$OUT"
zip -qry "$APP_NAME-unsigned.ipa" Payload
ls -lh "$APP_NAME-unsigned.ipa"
shasum -a 256 "$APP_NAME-unsigned.ipa"

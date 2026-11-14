#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RoseLink"
BUILD_CONFIG="release"
APP_BUNDLE="$APP_NAME.app"

echo "==> 编译 Swift 可执行文件"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "编译产物不存在：$BIN_PATH" >&2
    exit 1
fi

echo "==> 组装 app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> 临时签名（CoreBluetooth 权限需要已签名 bundle）"
codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null 2>&1 || \
    echo "签名失败，可忽略；首次运行请在系统设置中授予蓝牙权限"

echo "完成：$(pwd)/$APP_BUNDLE"

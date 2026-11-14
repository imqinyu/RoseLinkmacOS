#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RoseLink"
BUILD_CONFIG="release"
APP_BUNDLE="$APP_NAME.app"

# 始终构建通用二进制（arm64 + x86_64）。体积只有 1 MB 出头，
# 没必要分成两个包让用户挑架构——挑错了会直接打不开。
echo "==> 编译（通用二进制 arm64 + x86_64）"
swift build -c "$BUILD_CONFIG" --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
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
lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

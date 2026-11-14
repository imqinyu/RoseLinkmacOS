#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RoseLink"
BUILD_CONFIG="release"

# 用法：
#   ./build.sh              通用二进制（arm64 + x86_64），产物 RoseLink.app
#   ./build.sh arm64        仅 Apple Silicon，产物 RoseLink-arm64.app
#   ./build.sh x86_64       仅 Intel，产物 RoseLink-x86_64.app
ARCHS="${1:-universal}"

case "$ARCHS" in
    universal)
        SWIFT_ARCH_FLAGS=(--arch arm64 --arch x86_64)
        BUNDLE_NAME="$APP_NAME.app"
        ;;
    arm64)
        SWIFT_ARCH_FLAGS=(--arch arm64)
        BUNDLE_NAME="$APP_NAME-arm64.app"
        ;;
    x86_64)
        SWIFT_ARCH_FLAGS=(--arch x86_64)
        BUNDLE_NAME="$APP_NAME-x86_64.app"
        ;;
    *)
        echo "未知架构：$ARCHS（可选 universal / arm64 / x86_64）" >&2
        exit 1
        ;;
esac

echo "==> 编译（$ARCHS）"
swift build -c "$BUILD_CONFIG" "${SWIFT_ARCH_FLAGS[@]}"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" "${SWIFT_ARCH_FLAGS[@]}" --show-bin-path)/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "编译产物不存在：$BIN_PATH" >&2
    exit 1
fi

echo "==> 组装 app bundle"
rm -rf "$BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS" "$BUNDLE_NAME/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE_NAME/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$BUNDLE_NAME/Contents/PkgInfo"

echo "==> 临时签名（CoreBluetooth 权限需要已签名 bundle）"
codesign --force --sign - --timestamp=none "$BUNDLE_NAME" >/dev/null 2>&1 || \
    echo "签名失败，可忽略；首次运行请在系统设置中授予蓝牙权限"

echo "完成：$(pwd)/$BUNDLE_NAME"
lipo -archs "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"

#!/usr/bin/env bash
# 打包流程对齐 hotkey-macos/build.sh：
#   swift release → 组装 dist/*.app → codesign（ad-hoc）→ dmg_temp → Applications 链接 → hdiutil → 清理临时目录
#
# 可选：export CODESIGN_IDENTITY="Developer ID Application: …" 后执行本脚本，将用正式证书签名（仍需 notarytool 公证才能消除「已损坏」提示）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/mnote"
APP_NAME="mnote"

VERSION_FILE="$PKG_DIR/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
  VERSION="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$VERSION_FILE" | head -1)"
else
  VERSION="0.1.0"
fi

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
REL_BIN_DIR="$PKG_DIR/.build/release"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}.dmg"
TEMP_DIR="$DIST_DIR/dmg_temp"
DMG_VOLNAME="mnote v${VERSION}"
ICON_SOURCE="$PKG_DIR/Sources/mnote/Resources/assets/macdown-icon-1024.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"

echo "=== 构建 mnote v${VERSION} ==="
swift build -c release --package-path "$PKG_DIR"

echo "=== 组装 ${APP_NAME}.app ==="
rm -rf "$APP_DIR" "$TEMP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$REL_BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "=== 生成 AppIcon.icns ==="
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

# 笔记本文件夹自定义图标（NSWorkspace.setIcon）用位图；由 mnote-mark.svg 导出，见 .cursor/mac-build.mdc
MARK_SRC="$PKG_DIR/Sources/mnote/Resources/assets"
cp "$MARK_SRC/mnote-mark-folder.png" "$RESOURCES_DIR/"
cp "$MARK_SRC/mnote-mark.svg" "$RESOURCES_DIR/"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>mnote</string>
  <key>CFBundleIdentifier</key>
  <string>com.mnote.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>mnote</string>
  <key>CFBundleDisplayName</key>
  <string>mnote</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key>
    <true/>
  </dict>
</dict>
</plist>
EOF

echo "=== codesign（与 hotkey-macos/build.sh 一致）==="
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi

echo "=== 打包 DMG ==="
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
mkdir -p "$TEMP_DIR"
cp -R "$APP_DIR" "$TEMP_DIR/"
ln -sf /Applications "$TEMP_DIR/Applications"

cat > "$TEMP_DIR/使用说明.txt" <<EOF
mnote v${VERSION}

安装
1. 将 mnote.app 拖入「应用程序」文件夹
2. 首次若提示无法打开，可在终端执行：xattr -cr /Applications/mnote.app
   （从网络下载的应用可能被标记隔离；正式对外分发需 Apple 开发者证书 + 公证）

使用
在「设置」中选择笔记根目录与笔记本；编辑区为 Markdown，右侧为预览。

© mnote
EOF

hdiutil create \
  -volname "$DMG_VOLNAME" \
  -srcfolder "$TEMP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$TEMP_DIR"

echo ""
echo "✅ 版本: ${VERSION}"
echo "✅ APP:  $APP_DIR"
echo "✅ DMG:  $(du -h "$DMG_PATH" | cut -f1)  ->  $DMG_PATH"

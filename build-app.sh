#!/bin/bash
# 编译 WorkBuddy-Skin 原生 macOS 应用（并可选打包 DMG，含 Applications 拖入链接）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="WorkBuddy-Skin"
VERSION="1.0.1"
APP_DIR="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 编译 WorkBuddy-Skin v${VERSION}..."

# 清理旧的应用
rm -rf "$APP_DIR"

# 创建应用结构
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 编译 Swift 代码
swiftc -o "${MACOS_DIR}/${APP_NAME}" \
  -framework Cocoa \
  -framework Foundation \
  -framework AVFoundation \
  "$SCRIPT_DIR/WorkBuddySkin.swift"

# 项目本地图标
ICON_PATH="${SCRIPT_DIR}/assets/AppIcon.icns"

if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "${RESOURCES_DIR}/AppIcon.icns"
  ICON_KEY="true"
else
  ICON_KEY="false"
fi

# 创建 Info.plist
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>com.workbuddy.skin</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
</dict>
</plist>
EOF

# 添加执行权限
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ 编译完成: $APP_DIR"
[ "$ICON_KEY" = "true" ] && echo "🎨 图标已应用" || echo "⚠️  未找到图标文件"

# ─── DMG 打包（含 Applications 拖入快捷方式）───
DMG_PATH="${SCRIPT_DIR}/dist/${APP_NAME}-v${VERSION}.dmg"
echo "📦 打包 DMG: $DMG_PATH"
mkdir -p "${SCRIPT_DIR}/dist"
rm -f "$DMG_PATH"

STAGE_DIR="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGE_DIR/"
# 拖入即装：DMG 内放置 /Applications 符号链接
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_PATH" -quiet

rm -rf "$STAGE_DIR"
echo "✅ DMG 已生成: $DMG_PATH"

[ "$ICON_KEY" = "true" ] && killall Dock 2>/dev/null &
echo "🚀 可以双击运行了"

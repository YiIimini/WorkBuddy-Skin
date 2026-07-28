#!/bin/bash
# 编译 WorkBuddy-Skin 原生 macOS 应用

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="WorkBuddy-Skin"
APP_DIR="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 编译 WorkBuddy-Skin..."

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

# 复制图标（如果存在）
ICON_SRC="$HOME/Pictures/暴富喵 apng.png"
ICONSET_DIR="/tmp/AppIcon.iconset"
ICNS_FILE="/tmp/WorkBuddy-Skin.icns"

if [ -f "$ICON_SRC" ]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16   "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
  sips -z 32 32   "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
  sips -z 32 32   "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
  sips -z 64 64   "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
  sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE" > /dev/null 2>&1
  cp "$ICNS_FILE" "${RESOURCES_DIR}/AppIcon.icns"
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
	<string>2.3</string>
	<key>CFBundleVersion</key>
	<string>2.3</string>
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
echo "🚀 可以双击运行了"

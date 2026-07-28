#!/bin/bash
# 编译 WorkBuddy-Skin 原生 macOS 应用

set -e

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
  WorkBuddySkin.swift

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
	<string>2.0.1</string>
	<key>CFBundleVersion</key>
	<string>2.0.1</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# 添加执行权限
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ 编译完成: $APP_DIR"
echo "🚀 可以双击运行了"

# WorkBuddy-Skin

> 原生 macOS 桌面应用，为 WorkBuddy 注入自定义背景图片/视频。零侵入，不修改 WorkBuddy 本体。

## 特性

- **原生应用**：Swift + Cocoa，轻量高效
- **零侵入**：CDP 注入，不修改 WorkBuddy.app
- **流体玻璃**：侧边栏/面板/按钮/输入框统一毛玻璃效果
- **7 种主题**：暗紫/暗蓝/暗绿/暖橙/玫瑰/石板/午夜
- **自动取色**：根据背景亮度自动匹配对比文字色
- **实时调节**：不透明度/遮罩/模糊/填充/位置，即时生效
- **菜单栏**：图标 + 快捷操作菜单

## 安装

1. 下载 [WorkBuddy-Skin-v2.3.dmg](../../releases/download/v2.3/WorkBuddy-Skin-v2.3.dmg)
2. 拖入 Applications
3. 首次运行授权：系统设置 → 隐私与安全性

## 使用

1. 双击 WorkBuddy-Skin.app
2. 选择背景文件 → 调整效果
3. 点击 CDP 注入启动

## 项目结构

```
assets/AppIcon.icns         应用图标
WorkBuddySkin.swift         原生 macOS 应用 (Swift)
build-app.sh                编译脚本
daemon.js                   背景注入守护进程 (Node.js)
launcher.sh                 WorkBuddy 启动器 (CDP)
config.json                 背景配置
```

## 许可证

MIT

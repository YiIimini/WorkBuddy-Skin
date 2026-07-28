# WorkBuddy-Skin

> 原生 macOS 桌面应用，为 WorkBuddy 注入自定义背景图片/视频。零侵入，不修改 WorkBuddy 本体。

## 特性

- **原生应用**：Swift + Cocoa 开发，轻量高效
- **零侵入**：不修改 WorkBuddy.app 任何文件
- **视频/图片背景**：支持 MP4/MOV/JPG/PNG/GIF 等
- **实时预览**：选择文件后直接在窗口预览
- **实时调节**：不透明度、暗色遮罩、模糊、填充方式、位置
- **背景持久**：每 500ms 自动重建背景层，不被 WorkBuddy 覆盖
- **一键启动**：自动以 CDP 模式启动 WorkBuddy 并注入背景

## 下载安装

1. 下载 [WorkBuddy-Skin-v2.2.dmg](../../releases/download/v2.2/WorkBuddy-Skin-v2.2.dmg)
2. 打开 DMG，拖拽 `WorkBuddy-Skin.app` 到 `Applications`
3. 首次运行：系统设置 → 隐私与安全性 → 仍要打开

## 使用方法

1. 双击 `WorkBuddy-Skin.app`
2. 点击「📁 选择文件」选择背景图片或视频
3. 调整效果（不透明度、遮罩、模糊等）
4. 点击「🚀 启动 WorkBuddy」启动并注入背景

## 系统要求

- macOS 11.0+
- WorkBuddy 已安装

## 项目结构

```
WorkBuddy-Skin/
├── WorkBuddySkin.swift       # 原生 macOS 应用源码（Swift）
├── WorkBuddySkin.applescript # 启动辅助脚本
├── build-app.sh              # 编译脚本
├── daemon.js                 # 背景注入守护进程
├── launcher.sh               # WorkBuddy 启动器（带 CDP）
├── config.json               # 背景配置
├── LICENSE
└── README.md
```

## 技术栈

- **Swift + Cocoa** — 原生 macOS 应用
- **Chrome DevTools Protocol (CDP)** — 背景注入机制
- **Node.js** — 守护进程运行时
- **file:// 协议** — 绕过 URL 安全检查

## 许可证

MIT License

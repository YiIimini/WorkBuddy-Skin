# WorkBuddy-Skin

> 原生 macOS 桌面应用，为 WorkBuddy 注入自定义背景图片/视频。零侵入，不修改 WorkBuddy 本体。

## 特性

- **原生应用**：Swift + Cocoa 开发，轻量高效，非 Electron
- **零侵入**：不修改 WorkBuddy.app 任何文件
- **视频背景**：支持 MP4/MOV 视频循环播放
- **图片背景**：支持 JPG/PNG/GIF 等格式
- **实时调节**：不透明度、暗色遮罩、模糊、填充方式、位置
- **毛玻璃效果**：WorkBuddy 面板自动变半透明
- **一键启动**：自动以 CDP 模式启动 WorkBuddy 并注入背景

## 下载安装

### DMG 安装包（推荐）

1. 下载 [WorkBuddy-Skin-v2.1.dmg](../../releases/download/v2.1/WorkBuddy-Skin-v2.1.dmg)
2. 打开 DMG，将 `WorkBuddy-Skin.app` 拖拽到 `Applications`
3. 首次运行：系统设置 → 隐私与安全性 → 仍要打开

### 从源码编译

```bash
git clone https://github.com/YiIimini/WorkBuddy-Skin.git
cd WorkBuddy-Skin
bash build-app.sh
```

## 使用方法

1. 双击 `WorkBuddy-Skin.app`
2. 点击「📁 选择文件」选择背景图片或视频
3. 调整效果（不透明度、遮罩、模糊等）
4. 点击「🚀 启动」启动 WorkBuddy（自动注入背景）

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

## 工作原理

1. 通过 CDP 将背景脚本注入 WorkBuddy 渲染进程
2. 创建背景层 + 暗色遮罩层
3. 注入 CSS 让 WorkBuddy 面板变半透明
4. 守护进程每 5 秒推送配置，确保背景持续生效

## 许可证

MIT License

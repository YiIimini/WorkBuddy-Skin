# WorkBuddy-Skin v2.1 Release Notes

## 发布日期
2026-07-28

## 下载

**DMG 安装包：** [WorkBuddy-Skin-v2.1.dmg](../../releases/download/v2.1/WorkBuddy-Skin-v2.1.dmg) (86 KB)

## 安装

1. 下载并打开 DMG
2. 拖拽 `WorkBuddy-Skin.app` 到 `Applications`
3. 首次运行授权：系统设置 → 隐私与安全性 → 仍要打开

## v2.1 更新内容

### 全新原生桌面应用
- ✅ 用 Swift + Cocoa 重写，原生 macOS 应用
- ✅ 深色主题 UI，卡片式状态布局
- ✅ 集成所有功能于一体（无需 Web 界面）

### 功能改进
- ✅ 不自动打开浏览器，Web 面板改为手动点击
- ✅ 背景持久性修复（每 5 秒定时推送配置）
- ✅ 实时更新（滑块/文件变化立即生效）
- ✅ 一键启动 WorkBuddy（自动退出 → CDP 模式重启）

### 界面
- 四个状态卡片：WorkBuddy / CDP / 守护进程 / 背景
- 快速操作：启动 / 刷新 / Web 面板
- 背景设置：文件选择 / 透明度 / 遮罩 / 模糊 / 填充 / 位置

### 清理
- 移除 manager.html、settings.html（被原生应用替代）
- 移除 tray-daemon.js、start-tray.sh（不再需要）
- 移除 set-bg-app.applescript、set-background.sh（原生应用内置文件选择）

## 系统要求

- macOS 11.0+
- WorkBuddy 已安装

## 源代码

GitHub: https://github.com/YiIimini/WorkBuddy-Skin

## 许可证

MIT License

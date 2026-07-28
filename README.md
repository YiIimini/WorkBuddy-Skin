# WorkBuddy-Skin v1.0.0

> 原生 macOS 桌面应用，为 WorkBuddy 注入自定义背景。零侵入，不修改 WorkBuddy 本体。

## 预览

![应用预览](https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E5%BA%94%E7%94%A8%E9%A2%84%E8%A7%88.png)

![设置界面](https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E8%AE%BE%E7%BD%AE%E7%95%8C%E9%9D%A2.png)

## 安装

下载 [WorkBuddy-Skin-v1.0.0.dmg](https://github.com/YiIimini/WorkBuddy-Skin/releases/download/v1.0.0/WorkBuddy-Skin-v1.0.0.dmg)，拖入 Applications。首次运行需授权。

## 功能

- **背景注入**：CDP 注入图片/视频背景，RAF 持续渲染，页面导航自动恢复（localStorage 持久化）
- **流体玻璃 UI**：侧边栏/面板/按钮/输入框统一毛玻璃效果（backdrop-filter + 渐变 + 内发光）
- **7 种主题**：暗紫/暗蓝/暗绿/暖橙/玫瑰/石板/午夜（CSS 变量配色体系）
- **自动取色**：根据背景图片亮度自动匹配文字色 + 取色板手动选色
- **实时调节**：透明度/遮罩/模糊/填充/位置，即时热更新
- **菜单栏**：图标 + 快捷操作（注入/启用背景/状态/刷新/打开窗口 ⌘O）
- **纯原生**：Swift + Cocoa 开发，无需 Electron

## 技术架构

```
WorkBuddy-Skin.app (Swift/Cocoa)    ← 桌面窗口
        ↓ HTTP API
daemon.js (Node.js HTTP server)     ← 核心守护进程
        ↓ CDP (chrome-remote-interface)
WorkBuddy (Electron)                 ← 目标应用
        ↓ 注入 CSS + JS
背景层 (body::before / #wb-bg-layer)
```

## 系统要求

- macOS 11.0+
- WorkBuddy 已安装
- 首次运行需授予辅助功能权限

## 社交媒体

[![抖音](https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/xc/dy.png)](https://www.douyin.com/user/yiilimini)

抖音 · 开发者动态 & 更新预告

## 打赏支持

如果 WorkBuddy-Skin 让你的 WorkBuddy 更好看了，欢迎请开发者喝杯咖啡 ☕

[![微信赞赏](https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/ds/wechat-pay.jpg)](https://github.com/YiIimini/Mineradio-MacOS/blob/main/public/ds/wechat-pay.jpg)

微信赞赏

[![支付宝](https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/ds/alipay.png)](https://github.com/YiIimini/Mineradio-MacOS/blob/main/public/ds/alipay.png)

支付宝

## 项目

https://github.com/YiIimini/WorkBuddy-Skin

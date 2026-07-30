# WorkBuddy-Skin v1.0.0

> 原生 macOS 桌面应用，为 WorkBuddy 注入自定义背景。零侵入，不修改 WorkBuddy 本体。

## 预览

![应用预览](https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E5%BA%94%E7%94%A8%E9%A2%84%E8%A7%88.png)

![设置界面](https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E8%AE%BE%E7%BD%AE%E7%95%8C%E9%9D%A2.png)

## 安装

下载 [WorkBuddy-Skin-v1.0.0.dmg](https://github.com/YiIimini/WorkBuddy-Skin/releases/download/v1.0.0/WorkBuddy-Skin-v1.0.0.dmg)，拖入 Applications。首次运行需授权。

## 功能

- **背景注入**：CDP 注入图片/视频背景，RAF 持续渲染，页面导航自动恢复（localStorage 持久化）
- **GSAP 动效**：按钮磁吸悬浮 + 按压回弹、弹窗/菜单弹簧进场 + 子项级联、输入框焦点光晕呼吸（尊重系统"减少动态效果"设置）
- **流体玻璃 UI**：侧边栏/面板/按钮/输入框统一毛玻璃效果（backdrop-filter + 渐变 + 内发光）
- **7 种主题**：暗紫/暗蓝/暗绿/暖橙/玫瑰/石板/午夜（CSS 变量配色体系）
- **自动取色**：根据背景图片亮度自动匹配文字色 + 取色板手动选色
- **实时调节**：透明度/遮罩/模糊/填充/位置，即时热更新
- **菜单栏**：图标 + 快捷操作（注入/启用背景/状态/刷新/打开窗口 ⌘O）
- **纯原生**：Swift + Cocoa 开发，无需 Electron

## 当前版本修复

- **窗口关闭后无法重开**：实现 `applicationShouldHandleReopen` 处理 Dock 点击（原 `didBecomeActive` 方案在 app 已激活时不触发），并显式 `isReleasedWhenClosed = false`
- **菜单栏点击闪退**：`currentConfig`（Swift Dictionary）原在后台线程读取、主线程写入，数据竞争导致崩溃；改为主线程快照 → 后台端口探测 → 主线程更新 UI
- **菜单逻辑错误**：菜单栏"启用/停用背景"原错绑为切换文字自动配色，已修正

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

<p align="center">
  <a href="https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/xc/dy.png">
    <img src="https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/xc/dy.png" width="160" alt="抖音" />
  </a>
</p>
<p align="center">抖音 · 开发者动态 & 更新预告</p>

## 打赏支持

如果 WorkBuddy-Skin 让你的 WorkBuddy 更好看了，欢迎请开发者喝杯咖啡 ☕

<p align="center">
  <a href="https://github.com/YiIimini/Mineradio-MacOS/blob/main/public/ds/wechat-pay.jpg">
    <img src="https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/ds/wechat-pay.jpg" width="180" alt="微信赞赏" />
  </a>
  &nbsp;&nbsp;&nbsp;
  <a href="https://github.com/YiIimini/Mineradio-MacOS/blob/main/public/ds/alipay.png">
    <img src="https://github.com/YiIimini/Mineradio-MacOS/raw/main/public/ds/alipay.png" width="180" alt="支付宝" />
  </a>
</p>
<p align="center">微信赞赏 &nbsp;·&nbsp; 支付宝</p>

## 开源协议

本项目基于 [GPL-3.0](https://github.com/YiIimini/WorkBuddy-Skin/blob/main/LICENSE) 开源。欢迎 Star、Fork、PR。

<p align="center">
  <a href="https://github.com/YiIimini/WorkBuddy-Skin">
    <img src="https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E5%BA%94%E7%94%A8%E5%9B%BE%E6%A0%87.png" width="64" alt="WorkBuddy-Skin" />
  </a>
</p>
<p align="center">
  <a href="https://github.com/YiIimini/WorkBuddy-Skin">github.com/YiIimini/WorkBuddy-Skin</a>
</p>

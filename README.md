# WorkBuddy-Skin v1.1.0

> 跨平台桌面美化工具，为 WorkBuddy 注入自定义背景与动效。零侵入，不修改 WorkBuddy 本体。

## 预览

![应用预览](https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E5%BA%94%E7%94%A8%E9%A2%84%E8%A7%88.png)

![设置界面](https://raw.githubusercontent.com/YiIimini/WorkBuddy-Skin/main/assets/%E8%AE%BE%E7%BD%AE%E7%95%8C%E9%9D%A2.png)

## 安装

**macOS**：下载 [WorkBuddy-Skin-v1.1.0.dmg](https://github.com/YiIimini/WorkBuddy-Skin/releases/download/v1.1.0/WorkBuddy-Skin-v1.1.0.dmg)，将 WorkBuddy-Skin.app **拖入 DMG 窗口中的 Applications 文件夹**。首次运行需授权。

**Windows**：
1. 安装 [Node.js 18+](https://nodejs.org)，克隆本仓库
2. 在仓库目录执行：`npm install chrome-remote-interface gsap`
3. 运行启动器：`powershell -ExecutionPolicy Bypass -File launcher.ps1`
4. 打开设置面板 http://localhost:17890 进行配置（原生管理器窗口为 macOS 独占，Windows 使用网页面板）

## 功能

- **背景注入**：CDP 注入图片/视频背景，RAF 持续渲染，页面导航自动恢复（localStorage 持久化）
- **跨平台**：macOS 原生管理器 + Windows PowerShell 启动器（daemon.js 全平台通用）
- **GSAP 动效**：按钮磁吸悬浮 + 按压回弹、弹窗/菜单弹簧进场 + 子项级联、输入框焦点光晕呼吸 + 打字辉光、自定义高亮光标（尊重系统"减少动态效果"设置）
- **深度思考优化**：思维链内容去模糊（实底玻璃 + 无文字阴影 + 全不透明度）
- **流体玻璃 UI**：侧边栏/面板/按钮/输入框统一毛玻璃效果（backdrop-filter + 渐变 + 内发光）
- **7 种主题**：暗紫/暗蓝/暗绿/暖橙/玫瑰/石板/午夜（CSS 变量配色体系）
- **自动取色**：根据背景图片亮度自动匹配文字色 + 取色板手动选色
- **实时调节**：透明度/遮罩/模糊/填充/位置，即时热更新
- **菜单栏**：图标 + 快捷操作（注入/启用背景/状态/刷新/打开窗口 ⌘O）
- **系统监测**：状态监测下新增 CPU / GPU / RAM / SSD / NET 五合一实时监测面板，点击任意卡片基于应用窗口正中弹出悬浮详情面板
- **纯原生**：Swift + Cocoa 开发（macOS 管理器），无需 Electron

## 当前版本修复

- **窗口关闭后无法重开**：实现 `applicationShouldHandleReopen` 处理 Dock 点击（原 `didBecomeActive` 方案在 app 已激活时不触发），并显式 `isReleasedWhenClosed = false`
- **菜单栏点击闪退**：`currentConfig`（Swift Dictionary）原在后台线程读取、主线程写入，数据竞争导致崩溃；改为主线程快照 → 后台端口探测 → 主线程更新 UI
- **菜单逻辑错误**：菜单栏"启用/停用背景"原错绑为切换文字自动配色，已修正

## v1.1.0 更新

- **系统监测模块**：在「状态监测」下方新增「系统监测」面板，包含 CPU（占用率）、GPU（占用率）、RAM（占用率）、SSD（读取+写入吞吐）、NET（上下行流量）五张卡片，每 2 秒刷新一次
- **详情悬浮面板**：点击任意卡片，基于应用窗口正中弹出 `NSPanel` 子窗口，展示该指标的更详细数据（CPU 用户态/系统态/核心数/型号、内存已用/可用/线路内存/压缩、网络上下行/接口、磁盘吞吐、GPU 授权状态）
- **GPU 占用率（可选授权）**：Apple Silicon 未公开 GPU 占用率公共 API，点击 GPU 卡片的「授权 GPU 监测」后将以管理员权限运行 `powermetrics` 实时采集估算值（仅需授权一次，可随时停止）
- **指标来源**：CPU/RAM 通过 Mach 内核 API（`host_statistics64`）采集；SSD 吞吐来自 `iostat`；网络流量来自 `netstat`（主网络接口经 `route` 自动探测，本机为 `en5`）

## v1.0.1 更新

- **守护进程看门狗**：首次成功连接 CDP 后启用看门狗，检测到 WorkBuddy 进程持续退出超过宽限期（25s）则守护进程自动退出，修复"WorkBuddy 退出后注入进程卡死不退出"问题
- **一键停止注入**：管理器新增"停止CDP注入"按钮，点击弹出"WorkBuddy程序将退出"确认框，确认后停止注入并安全退出 WorkBuddy 与守护进程（底层 `POST /api/stop-injection`：移除注入脚本 + `Browser.close` 关闭 WorkBuddy + 优雅退出守护进程）
- **配置有效性修复**：背景暗色遮罩、图片填充/位置等设置此前不生效，现已通过容器透明度排除规则与 `--wb-bg-size/--wb-bg-pos` 变量修正，全部开关实时生效
- **深度思考区排版**：思维链区域最大高度由 200px 放宽至 `min(60vh, 720px)` 并支持双向滚动，长内容不再被截断

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

- macOS 11.0+（原生管理器）或 Windows 10/11（脚本模式）
- WorkBuddy 已安装
- macOS 首次运行需授予辅助功能权限

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

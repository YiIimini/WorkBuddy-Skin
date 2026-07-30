# WorkBuddy-Skin v1.0.0 Release Notes

## 发布日期
2026-07-30

## 下载
**DMG：** [WorkBuddy-Skin-v1.0.0.dmg](../../releases/download/v1.0.0/WorkBuddy-Skin-v1.0.0.dmg)

## v1.0.0 更新

### 本轮新增（2026-07-30 第二轮）
- **Windows 支持**：daemon.js 跨平台依赖解析（node_modules 多候选路径）+ `launcher.ps1` 启动器（自动定位 WorkBuddy.exe/Node、安装依赖、CDP 启动、守护进程管理）；文件选择器与启动接口按平台分流
- **DMG 安装体验**：内置 Applications 文件夹符号链接，拖入即装
- **深度思考去模糊**：思维链容器实底玻璃 + 无文字阴影 + 全不透明度，不再蒙毛玻璃
- **自定义高亮光标**：contenteditable 选区 rect 精确定位的发光光标层，GSAP 呼吸闪烁，随主题色
- **输入排版**：行高 1.7 / 字距 0.012em / 内边距优化 / 抗锯齿渲染
- **文字按钮美化**（WorkBuddy 注入侧）：窗口中的纯文字/链接按钮统一主题色 + 悬浮下划线
- **终端命令块修复**：`execute-command-compact` 组件实底代码风格（68% 底色 + 主题描边 + 等宽字体），长命令横向可滚动看全；组件内去文字阴影
- **语法高亮修复**：全局强制文字色改为排除 pre/code 子树（`:not(pre *)` 复杂选择器），并内置 VS Code Dark+ 调色板补全 hljs token 配色
- **注入代际守卫**：`__wbBgGen` 代际号，守护进程重启重复注入时旧 RAF 循环自毁，杜绝新旧样式互抢

### GSAP 动效美化（新增）
- **按钮**：磁吸悬浮（back.out 回弹上浮）+ 按压弹性回弹（elastic.out），事件委托兼容 React 动态 DOM
- **弹窗/菜单/对话框**：MutationObserver 捕获动态新增，弹簧进场动画 + 菜单项级联 stagger
- **输入框**：焦点光晕呼吸动画 + 主题色光标（caret-color）+ 文本选择高亮
- GSAP 3.15 经守护进程 `/vendor/gsap.min.js` 分发，加载失败静默降级为静态美化
- 尊重系统"减少动态效果"（prefers-reduced-motion）设置
- transform 动画由 GSAP 驱动，CSS 过渡只保留颜色/阴影，避免双重动画冲突

### 关键修复
- **窗口关闭后无法重开**：实现 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 处理 Dock 图标点击 —— 原方案监听 `didBecomeActive` 通知，但 app 已激活时点击 Dock 不触发该通知，导致窗口永远无法重开；同时显式 `isReleasedWhenClosed = false`
- **菜单栏点击闪退**：`updateMenuStatus()`/`refreshStatus()` 原在后台线程直接读取 `currentConfig`（Swift Dictionary 非线程安全），与主线程写入形成数据竞争 → EXC_BAD_ACCESS；改为主线程快照 → 后台端口探测 → 主线程更新 UI
- **菜单逻辑错误**：菜单栏"启用/停用背景"原错绑 `autoTextToggled()`（切换文字自动配色），已修正为 `toggleBackground()`

### 原生 macOS 应用
- Swift + Cocoa 原生桌面窗口，轻量高效
- 深色主题 UI，SF Symbols 图标
- 菜单栏图标 + 快捷操作菜单（注入/启用/状态/刷新）

### 背景注入
- CDP 注入，零侵入不修改 WorkBuddy 本体
- `body::before` 伪元素图片背景 + div 视频背景
- RAF 持续渲染 + localStorage 配置持久化
- 页面导航自动恢复，不中断

### 流体玻璃 UI
- 侧边栏/面板/按钮/输入框统一毛玻璃效果
- 渐变遮罩提升文字可读性
- 7 种主题配色（暗紫/暗蓝/暗绿/暖橙/玫瑰/石板/午夜）

### 实时调节
- 不透明度 / 暗色遮罩 / 模糊 / 填充方式 / 位置
- 自动取色：根据背景亮度自动选择对比文字色
- NSColorWell 取色板手动选色
- 设置实时热更新

### 安装
1. 下载 DMG，拖入 Applications
2. 首次运行：系统设置 → 隐私与安全性 → 仍要打开

## 系统要求
- macOS 11.0+
- WorkBuddy 已安装

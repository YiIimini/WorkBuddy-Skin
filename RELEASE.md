# WorkBuddy-Skin v2.3 Release Notes

## 发布日期
2026-07-29

## 下载
**DMG：** [WorkBuddy-Skin-v2.3.dmg](../../releases/download/v2.3/WorkBuddy-Skin-v2.3.dmg)

## v2.3 更新

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

# WorkBuddy-Skin v2.2 Release Notes

## 发布日期
2026-07-28

## 下载

**DMG 安装包：** [WorkBuddy-Skin-v2.2.dmg](../../releases/download/v2.2/WorkBuddy-Skin-v2.2.dmg)

## 安装

1. 下载并打开 DMG
2. 拖拽 `WorkBuddy-Skin.app` 到 `Applications`
3. 首次运行授权：系统设置 → 隐私与安全性 → 仍要打开

## v2.2 更新内容

### 核心修复
- ✅ **修复背景不显示**：注入脚本语法错误（多余的 `})();`）
- ✅ **修复背景不持久**：每 500ms 轮询重建背景层，不再被 WorkBuddy DOM 重渲染覆盖
- ✅ **移除浏览器自动打开**：launcher.sh 不再自动打开 Web 面板

### UI 改进
- ✅ **配色重构**：使用系统自适应颜色（labelColor/secondaryLabelColor），强制深色外观
- ✅ **预览区**：顶部 180px 预览，图片直接显示，视频自动截取缩略帧
- ✅ **移除 Web 面板按钮**：纯桌面应用，不涉及浏览器

### 技术改进
- 注入脚本移除 guard clause，改用 `clearInterval` 防重复
- 守护进程每 5 秒定时推送配置
- `file://` 协议绕过 URL 安全检查

## 系统要求

- macOS 11.0+
- WorkBuddy 已安装

## 源代码

GitHub: https://github.com/YiIimini/WorkBuddy-Skin

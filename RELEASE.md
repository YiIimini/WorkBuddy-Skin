# WorkBuddy-Skin v2.0.1 Release Notes

## 发布日期
2026-07-28

## 下载

**DMG 安装包：** [WorkBuddy-Skin-v2.0.1.dmg](../../releases/download/v2.0.1/WorkBuddy-Skin-v2.0.1.dmg) (806 KB)

## 安装

1. 下载并打开 `WorkBuddy-Skin-v2.0.1.dmg`
2. 将 `WorkBuddy-Skin.app` 拖拽到 `Applications` 文件夹
3. 首次运行时，如果提示"未受信任的开发者"，前往 **系统设置 → 隐私与安全性 → 仍要打开**

## 更新内容

### v2.0.1 (2026-07-28)

**修复：**
- ✅ 修复 settings.html not found 问题（守护进程路径更新）
- ✅ 修复应用启动问题（AppleScript 文件名优化）
- ✅ 全面排查并更新所有文件路径
- ✅ 重新编译所有应用，确保路径正确

**改进：**
- ✅ 完整的应用程序排查和验证
- ✅ 所有脚本语法检查通过
- ✅ 清理旧日志和 PID 文件

### v2.0 (2026-07-28)

**核心功能：**
- ✅ 零侵入背景注入：不修改 WorkBuddy.app，通过 CDP 注入自定义背景
- ✅ 视频背景：支持 MP4/WebM/MOV 循环播放
- ✅ 图片背景：支持 JPG/PNG/GIF/WebP/AVIF
- ✅ 实时调节：不透明度、暗色遮罩、模糊、填充方式、位置
- ✅ 毛玻璃效果：WorkBuddy 面板自动变半透明

**用户体验：**
- ✅ 三步操作流程：打开 Web 管理 → 启动源程序并注入 → 退出
- ✅ Web 设置面板：实时预览，即时生效
- ✅ DMG 安装包：标准 macOS 安装方式
- ✅ 拖拽应用：拖文件到图标快速设置背景
- ✅ 持续监控：自动检测并恢复背景层

**技术改进：**
- ✅ file:// 协议：绕过 WorkBuddy 的 URL 安全检查
- ✅ CDP 推送配置：避免 fetch/XHR 被拦截
- ✅ MutationObserver：监控 DOM 变化，自动恢复背景层
- ✅ 托盘守护进程：常驻后台，自动监控 WorkBuddy

## 系统要求

- macOS 11.0 或更高版本（Apple Silicon / Intel）
- WorkBuddy 已安装在 `/Applications/WorkBuddy.app`

## 使用

1. 双击 `Applications/WorkBuddy-Skin.app`
2. 按三步流程操作：
   - **打开 Web 管理** — 选择背景文件
   - **启动源程序并注入** — 自动重启 WorkBuddy
   - **退出** — 完成

## 已知问题

- 首次运行需要授权「控制 Terminal」（用于启动脚本）
- 背景视频文件大小建议不超过 50MB（性能考虑）

## 技术栈

- **Node.js** — 守护进程运行时
- **Chrome DevTools Protocol (CDP)** — 注入机制
- **AppleScript** — macOS 应用包装
- **file:// 协议** — 媒体文件加载

## 源代码

GitHub: https://github.com/YiIimini/WorkBuddy-Skin

## 许可证

MIT License

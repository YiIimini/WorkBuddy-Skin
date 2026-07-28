# WorkBuddy+ 背景注入器

> 不修改 WorkBuddy 应用本体，通过 CDP（Chrome DevTools Protocol）外部注入自定义背景图片/视频。

## 特性

- **零侵入**：不修改 WorkBuddy.app 任何文件，升级不受影响
- **视频背景**：支持 MP4/WebM/MOV 视频循环播放
- **图片背景**：支持 JPG/PNG/GIF/WebP/AVIF 等格式
- **实时调节**：不透明度、暗色遮罩、模糊、填充方式、位置
- **设置面板**：Web 界面，实时预览，即时生效
- **毛玻璃效果**：WorkBuddy 面板自动变半透明，透出背景
- **托盘守护**：常驻后台，自动监控和注入，开机自启（可选）
- **独立应用**：WorkBuddy+.app 一键启动/设置，无需命令行
- **DMG 安装**：标准 macOS 安装包，拖拽安装

## 架构

```
┌─────────────────────────────────────────────┐
│  WorkBuddy.app（未修改）                     │
│  启动参数: --remote-debugging-port=9222      │
│  ┌───────────────────────────────────┐       │
│  │  Renderer (网页)                   │       │
│  │  ← CDP: Page.addScriptToEvaluate  │       │
│  │  ← 注入 #wb-bg-layer 背景层        │       │
│  └───────────────────────────────────┘       │
└─────────────────────────────────────────────┘
                 ↑ CDP ws://localhost:9222
                 │
┌─────────────────────────────────────────────┐
│  daemon.js（Node.js 守护进程）                │
│  • HTTP :17890  → 设置面板 + 文件服务         │
│  • CDP 连接     → 注入脚本 / 推送配置         │
│  • 配置监听     → config.json 变更即推送      │
└─────────────────────────────────────────────┘
                 ↑ 启动
┌─────────────────────────────────────────────┐
│  WorkBuddy+.app（启动器）                     │
│  双击 → 退出旧 WorkBuddy → 带 CDP 重启       │
│       → 启动守护进程 → 打开设置面板           │
└─────────────────────────────────────────────┘
```

## 快速开始

### 前置要求

- macOS 11.0 或更高版本（Apple Silicon / Intel）
- WorkBuddy 已安装在 `/Applications/WorkBuddy.app`

### 方式 1：DMG 安装包（推荐）

1. **下载 DMG**：
   - 从 [Releases](https://github.com/YiIimini/workbuddy-WorkBuddy+/releases) 下载 `WorkBuddy+-v2.0.1.dmg`

2. **安装**：
   - 双击打开 DMG 文件
   - 将 `WorkBuddy+.app` 拖拽到 `Applications` 文件夹
   - 弹出 DMG

3. **首次运行**：
   - 打开 `Applications/WorkBuddy+.app`
   - 如果提示"未受信任的开发者"，前往 **系统设置 → 隐私与安全性 → 仍要打开**

4. **使用**：
   - **第 1 步**：打开 Web 管理（选择背景图片/视频）
   - **第 2 步**：启动源程序并注入（自动重启 WorkBuddy）
   - **第 3 步**：退出

### 方式 2：从源码安装

```bash
# 1. 克隆仓库
git clone https://github.com/YiIimini/workbuddy-WorkBuddy+.git
cd workbuddy-WorkBuddy+

# 2. 安装依赖（chrome-remote-interface）
cd /Users/x/.workbuddy/binaries/node/workspace
npm install chrome-remote-interface

# 3. 启动
bash launcher.sh
```

### 使用

#### 方式 1：WorkBuddy+.app（推荐）

1. 双击 `Applications/WorkBuddy+.app`
2. 按三步流程操作：
   - **打开 Web 管理** — 选择背景文件，调整效果
   - **启动源程序并注入** — 自动重启 WorkBuddy 并应用背景
   - **退出** — 完成

#### 方式 2：Web 设置面板

1. **启动**：双击 `WorkBuddy+.app`，选择「打开 Web 管理」
2. **设置**：浏览器自动打开 `http://localhost:17890`
3. **选择背景**：点击「浏览…」选择图片或视频文件
4. **调节效果**：拖动滑块实时预览
5. **保存**：点击「保存并应用」，背景即时生效

#### 方式 3：拖拽应用

拖拽图片/视频文件到 `~/Applications/设为 WorkBuddy 背景.app` 图标上。

#### 方式 4：命令行脚本

```bash
# 设置背景
bash set-background.sh /path/to/image.jpg
bash set-background.sh /path/to/video.mp4

# 查看当前配置
cat config.json
```

#### 方式 5：直接编辑配置文件

编辑 `config.json`，保存后自动生效（无需重启）。

**开机自启（可选）：**
```bash
# 加载 LaunchAgent
launchctl load ~/Library/LaunchAgents/com.workbuddy.plus.tray.plist

# 卸载
launchctl unload ~/Library/LaunchAgents/com.workbuddy.plus.tray.plist
```

### 启动器命令

```bash
bash launcher.sh          # 正常启动
bash launcher.sh --status # 查看状态
bash launcher.sh --stop   # 停止守护进程
bash launcher.sh --help   # 显示帮助
```

## 配置说明

配置文件 `config.json`：

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | `true` | 是否启用背景 |
| `type` | string | `"none"` | 背景类型：`video` / `image` / `none` |
| `source` | string | `""` | 背景文件完整路径 |
| `opacity` | number | `1.0` | 背景不透明度（0.1-1.0） |
| `overlay` | number | `0.25` | 暗色遮罩强度（0-0.8） |
| `blur` | string | `"0px"` | 背景模糊（如 `"5px"`） |
| `scale` | string | `"cover"` | 填充方式：`cover` / `contain` / `fill` |
| `position` | string | `"center"` | 位置：`center` / `top` / `bottom` / `left` / `right` |

## API 端点

守护进程提供以下 HTTP 端点（`http://localhost:17890`）：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/` | GET | 设置面板页面 |
| `/api/health` | GET | 健康检查（uptime、CDP 状态、重连次数） |
| `/api/config` | GET | 获取当前配置 |
| `/api/config` | POST | 更新配置 |
| `/api/status` | GET | 守护进程状态 |
| `/api/file?path=...` | GET | 提供本地文件（支持 HTTP Range） |
| `/api/pick` | GET | 弹出 macOS 原生文件选择器 |

## 文件结构

```
WorkBuddy+/
├── daemon.js                # CDP 注入守护进程（核心）
├── tray-daemon.js           # 托盘守护进程（常驻后台，自动监控）
├── settings.html            # 设置面板（Web UI）
├── launcher.sh              # 启动脚本（启动 WorkBuddy + 守护进程）
├── start-tray.sh            # 启动托盘守护进程
├── set-background.sh        # 快速设置背景脚本
├── config.json              # 背景配置
├── daemon.log               # 守护进程日志（自动生成）
├── tray.log                 # 托盘守护进程日志（自动生成）
├── daemon.pid               # 守护进程 PID（自动生成）
├── tray.pid                 # 托盘守护进程 PID（自动生成）
└── README.md                # 本文件
```

**系统级集成：**
```
/Applications/
└── WorkBuddy+.app                   # 主应用（DMG 安装，三步流程操作）

~/Applications/
└── 设为 WorkBuddy 背景.app           # 拖拽应用（拖文件到图标设置背景）

~/Library/LaunchAgents/
└── com.workbuddy.plus.tray.plist    # 开机自启配置（可选）
```

**DMG 安装包：**
```
WorkBuddy+-v2.0.1.dmg                  # macOS 安装包（拖拽安装）
├── WorkBuddy+.app                   # 主应用
├── Applications -> /Applications    # 快捷方式
└── README.txt                       # 安装说明
```

## 工作原理

1. **CDP 注入**：通过 `Page.addScriptToEvaluateOnNewDocument` 将背景脚本注入 WorkBuddy 渲染进程，跨页面导航持久生效
2. **背景层**：注入脚本创建 `#wb-bg-layer`（video/img 元素）+ `#wb-bg-overlay`（暗色遮罩）
3. **透明化 CSS**：注入样式让 WorkBuddy 面板变半透明（毛玻璃效果），透出背景层
4. **配置同步**：注入脚本每 2 秒轮询守护进程的 `/api/config`，配置变更即时生效
5. **文件服务**：视频/图片通过 `/api/file` 端点流式提供（支持 HTTP Range，视频可拖动进度条）

## 安全说明

- 文件路径安全校验：拒绝包含 `..` 的路径，防止目录遍历攻击
- 配置验证：类型检查、范围检查、枚举检查，拒绝非法值
- 仅监听 `127.0.0.1`，不对外暴露
- 不修改 WorkBuddy.app 任何文件

## 故障排查

### 背景不显示

1. 确认 WorkBuddy 是通过 WorkBuddy+ 启动的（带 `--remote-debugging-port=9222`）
2. 检查守护进程状态：`bash launcher.sh --status`
3. 查看日志：`cat daemon.log`
4. 确认 CDP 连接：`curl http://localhost:17890/api/health`

### 设置面板打不开

1. 确认守护进程在运行：`bash launcher.sh --status`
2. 检查端口占用：`lsof -i :17890`
3. 重启守护进程：`bash launcher.sh --stop && bash launcher.sh`

### 视频不播放

1. 确认视频格式支持（MP4/WebM/MOV）
2. 检查文件路径是否正确
3. 确认文件服务正常：`curl -I "http://localhost:17890/api/file?path=/path/to/video.mp4"`

### WorkBuddy 升级后

无需任何操作。本方案不修改 WorkBuddy.app，升级不受影响。

## 技术栈

- **Node.js**：守护进程运行环境
- **chrome-remote-interface**：CDP 客户端库
- **原生 HTTP 模块**：设置面板 + 文件服务
- **AppleScript**：.app 启动器（osacompile 编译）
- **Bash**：启动脚本

## License

MIT

#!/bin/bash
#############################################################################
# WorkBuddy+ 启动器 v2.0
#
# 功能：
#   1. 退出正在运行的 WorkBuddy（如有）
#   2. 以 --remote-debugging-port=9222 参数重新启动 WorkBuddy
#   3. 启动背景注入守护进程 (daemon.js)
#   4. 在浏览器中打开设置面板
#
# 本启动器不修改 WorkBuddy.app 本体，仅以额外参数启动 Electron 二进制。
#
# 用法：
#   bash launcher.sh          # 正常启动
#   bash launcher.sh --help   # 显示帮助
#   bash launcher.sh --stop   # 仅停止守护进程
#   bash launcher.sh --status # 查看状态
#############################################################################
set -euo pipefail

# ─── 路径配置 ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WB_APP="/Applications/WorkBuddy.app"
WB_BIN="$WB_APP/Contents/MacOS/Electron"
CDP_PORT=9222
DAEMON_PORT=17890
DAEMON="$SCRIPT_DIR/daemon.js"
NODE="/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node"
LOG_FILE="$SCRIPT_DIR/daemon.log"
PID_FILE="$SCRIPT_DIR/daemon.pid"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# ─── 颜色输出 ────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log(){ printf "${MAGENTA}[WorkBuddy+]${NC} %s\n" "$*"; }
ok(){ printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err(){ printf "${RED}[✗]${NC} %s\n" "$*" >&2; }

# ─── 帮助信息 ────────────────────────────────────────────
show_help() {
  cat << 'EOF'
WorkBuddy+ 启动器 v2.0

用法：
  bash launcher.sh          正常启动 WorkBuddy + 背景注入
  bash launcher.sh --help   显示此帮助
  bash launcher.sh --stop   仅停止背景注入守护进程
  bash launcher.sh --status 查看当前状态

文件位置：
  项目目录:  ~/.workbuddy/WorkBuddy+/ → /Users/x/Documents/WorkBuddy/WorkBuddy+/
  配置文件:  config.json
  日志文件:  daemon.log
  PID 文件:  daemon.pid

设置面板：
  http://localhost:17890

注意：
  本启动器不修改 WorkBuddy.app 本体，仅以 --remote-debugging-port=9222
  参数启动 Electron 二进制。WorkBuddy 升级不受影响。
EOF
}

# ─── 状态检查 ────────────────────────────────────────────
show_status() {
  echo "=== WorkBuddy+ 状态 ==="
  echo ""

  # WorkBuddy 进程
  if pgrep -f "WorkBuddy.app/Contents/MacOS" >/dev/null 2>&1; then
    ok "WorkBuddy 正在运行"
    # 检查是否带 CDP 参数
    if pgrep -f "remote-debugging-port=$CDP_PORT" >/dev/null 2>&1; then
      ok "CDP 端口 $CDP_PORT 已开放"
    else
      warn "CDP 端口未开放（需通过 WorkBuddy+ 启动）"
    fi
  else
    warn "WorkBuddy 未运行"
  fi

  # 守护进程
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      ok "守护进程运行中 (PID: $pid)"
    else
      warn "守护进程 PID 文件存在但进程已退出"
    fi
  else
    warn "守护进程未运行"
  fi

  # HTTP 服务
  if curl -s "http://localhost:$DAEMON_PORT/api/health" >/dev/null 2>&1; then
    ok "设置面板可访问: http://localhost:$DAEMON_PORT"
  else
    warn "设置面板不可访问"
  fi

  # 配置
  if [ -f "$CONFIG_FILE" ]; then
    local source
    source=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('source','(无)'))" 2>/dev/null || echo "(解析失败)")
    log "当前背景: $source"
  fi
  echo ""
}

# ─── 停止守护进程 ────────────────────────────────────────
stop_daemon() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log "停止守护进程 (PID: $pid)..."
      kill "$pid" 2>/dev/null || true
      sleep 1
      if kill -0 "$pid" 2>/dev/null; then
        warn "进程未响应，强制终止..."
        kill -9 "$pid" 2>/dev/null || true
      fi
      ok "守护进程已停止"
    else
      warn "守护进程未在运行"
    fi
    rm -f "$PID_FILE"
  else
    warn "未找到 PID 文件"
  fi
}

# ─── 参数解析 ────────────────────────────────────────────
case "${1:-}" in
  --help|-h)
    show_help
    exit 0
    ;;
  --stop)
    stop_daemon
    exit 0
    ;;
  --status)
    show_status
    exit 0
    ;;
esac

# ─── 依赖检查 ────────────────────────────────────────────
log "检查依赖..."

[ -d "$WB_APP" ] || { err "未找到 WorkBuddy: $WB_APP"; exit 1; }
[ -x "$WB_BIN" ] || { err "WorkBuddy 二进制不可执行: $WB_BIN"; exit 1; }
ok "WorkBuddy.app"

[ -x "$NODE" ] || { err "未找到 Node.js: $NODE"; exit 1; }
ok "Node.js ($("$NODE" --version))"

[ -f "$DAEMON" ] || { err "未找到守护进程: $DAEMON"; exit 1; }
ok "守护进程脚本"

# 检查 chrome-remote-interface 依赖
if ! "$NODE" -e "require('/Users/x/.workbuddy/binaries/node/workspace/node_modules/chrome-remote-interface')" 2>/dev/null; then
  err "缺少依赖: chrome-remote-interface"
  err "请运行: cd /Users/x/.workbuddy/binaries/node/workspace && npm install chrome-remote-interface"
  exit 1
fi
ok "chrome-remote-interface"

# ── 1. 退出 WorkBuddy ──
if pgrep -f "WorkBuddy.app/Contents/MacOS" >/dev/null 2>&1; then
  log "退出当前 WorkBuddy..."
  osascript -e 'tell application "WorkBuddy" to quit' 2>/dev/null || true
  for i in $(seq 1 10); do
    pgrep -f "WorkBuddy.app/Contents/MacOS" >/dev/null 2>&1 || break
    sleep 1
  done
  pkill -f "WorkBuddy.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  ok "WorkBuddy 已退出"
fi

# ── 2. 启动 WorkBuddy（带 CDP 参数） ──
log "启动 WorkBuddy（CDP 端口 $CDP_PORT）..."
"$WB_BIN" --remote-debugging-port=$CDP_PORT &
WB_PID=$!
log "WorkBuddy PID: $WB_PID"

# ── 3. 启动守护进程 ──
# 先杀掉旧实例
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "停止旧守护进程 (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi
fi

log "启动背景注入守护进程..."
nohup "$NODE" "$DAEMON" > "$LOG_FILE" 2>&1 &
DAEMON_PID=$!
echo "$DAEMON_PID" > "$PID_FILE"
log "守护进程 PID: $DAEMON_PID (日志: $LOG_FILE)"

# ── 4. 等待 WorkBuddy 就绪 ──
log "等待 WorkBuddy 就绪..."
CDP_READY=false
for i in $(seq 1 20); do
  if curl -s "http://localhost:$CDP_PORT/json/version" >/dev/null 2>&1; then
    CDP_READY=true
    ok "WorkBuddy CDP 已就绪"
    break
  fi
  sleep 1
done

if [ "$CDP_READY" = false ]; then
  warn "WorkBuddy CDP 未在 20 秒内就绪，守护进程将持续重试"
fi

# ── 5. 等待守护进程就绪 ──
log "等待守护进程就绪..."
DAEMON_READY=false
for i in $(seq 1 10); do
  if curl -s "http://localhost:$DAEMON_PORT/api/health" >/dev/null 2>&1; then
    DAEMON_READY=true
    ok "守护进程已就绪"
    break
  fi
  sleep 1
done

if [ "$DAEMON_READY" = false ]; then
  warn "守护进程未在 10 秒内就绪，请检查日志: $LOG_FILE"
fi

# ── 6. 打开设置面板 ──
sleep 1
log "打开设置面板: http://localhost:$DAEMON_PORT"
open "http://localhost:$DAEMON_PORT"

echo ""
log "════════════════════════════════════════════"
log "  WorkBuddy+ 已启动"
log "  • 设置面板: http://localhost:$DAEMON_PORT"
log "  • 守护进程日志: $LOG_FILE"
log "  • 查看状态: bash $0 --status"
log "  • 停止守护: bash $0 --stop"
log "════════════════════════════════════════════"

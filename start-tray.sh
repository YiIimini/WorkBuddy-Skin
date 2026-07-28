#!/bin/bash
# 启动 WorkBuddy+ 托盘守护进程

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node"
TRAY_DAEMON="$SCRIPT_DIR/tray-daemon.js"
PID_FILE="$SCRIPT_DIR/tray.pid"

# 检查是否已运行
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "托盘守护进程已在运行 (PID: $PID)"
    exit 0
  fi
fi

# 启动
echo "启动 WorkBuddy+ 托盘守护进程..."
nohup "$NODE" "$TRAY_DAEMON" > /dev/null 2>&1 &
echo $! > "$PID_FILE"
echo "托盘守护进程已启动 (PID: $!)"
echo "HTTP API: http://localhost:17891"

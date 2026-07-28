#!/bin/bash
#############################################################################
# WorkBuddy+ 快速设置背景脚本
#
# 用法：
#   bash set-background.sh <文件路径>
#
# 功能：
#   - 自动检测文件类型（图片/视频）
#   - 更新 config.json
#   - 如果守护进程运行中，自动应用新背景
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
DAEMON_PORT=17890

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok(){ printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err(){ printf "${RED}[✗]${NC} %s\n" "$*" >&2; }

# 检查参数
if [ $# -eq 0 ]; then
  err "用法: bash $0 <文件路径>"
  exit 1
fi

FILE_PATH="$1"

# 检查文件是否存在
if [ ! -f "$FILE_PATH" ]; then
  err "文件不存在: $FILE_PATH"
  exit 1
fi

# 获取文件扩展名（小写）
EXT="${FILE_PATH##*.}"
EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

# 判断文件类型
TYPE=""
case "$EXT" in
  jpg|jpeg|png|gif|webp|bmp|svg|avif)
    TYPE="image"
    ;;
  mp4|webm|mov|avi|mkv|m4v)
    TYPE="video"
    ;;
  *)
    err "不支持的文件类型: .$EXT"
    err "支持的图片格式: jpg, jpeg, png, gif, webp, bmp, svg, avif"
    err "支持的视频格式: mp4, webm, mov, avi, mkv, m4v"
    exit 1
    ;;
esac

# 读取当前配置（如果存在）
CURRENT_CONFIG="{}"
if [ -f "$CONFIG_FILE" ]; then
  CURRENT_CONFIG=$(cat "$CONFIG_FILE")
fi

# 更新配置（保留其他设置，只更新 type, source, enabled）
NEW_CONFIG=$(echo "$CURRENT_CONFIG" | python3 -c "
import json, sys
config = json.load(sys.stdin)
config['type'] = '$TYPE'
config['source'] = '$FILE_PATH'
config['enabled'] = True
print(json.dumps(config, indent=2, ensure_ascii=False))
")

# 写入配置文件
echo "$NEW_CONFIG" > "$CONFIG_FILE"
ok "已设置背景: $(basename "$FILE_PATH")"
ok "类型: $TYPE"

# 检查守护进程是否运行
if curl -s "http://localhost:$DAEMON_PORT/api/health" >/dev/null 2>&1; then
  ok "守护进程运行中，背景已自动应用"
else
  warn "守护进程未运行，下次启动 WorkBuddy+ 时生效"
fi

# 显示通知（macOS）
osascript -e "display notification \"已设置背景: $(basename "$FILE_PATH")\" with title \"WorkBuddy+\" sound name \"Glass\"" 2>/dev/null || true

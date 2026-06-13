#!/bin/bash
# all-restart.command — 一键重启全套 (2 bot + 5 bot = 9 个 plist)
# 2026-06-13: all-stop + sleep 2 + all-start, 一气呵成
# 调试时 (改了 server 代码) 用这个最快

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  ══ Agent Chat 全套一键重启 ══"
echo ""
echo "  (这会停掉所有 bot 一会, 大约 8-10 秒)"
echo ""

# 1. stop
bash "$SCRIPT_DIR/all-stop.command" </dev/null

# 2. 等 2 秒
echo ""
echo "  [中间] 等 2 秒..."
sleep 2

# 3. start
bash "$SCRIPT_DIR/2人+多人一起启动.command" </dev/null

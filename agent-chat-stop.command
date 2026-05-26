#!/bin/bash
# agent-chat 一键停止 for Mac

echo ""
echo "  ══ Agent Chat 一键停止 (Mac) ══"
echo ""

# 停 cron jobs
echo "  [1/2] 停止轮询..."
openclaw cron list 2>/dev/null | grep "agent-chat" | awk '{print $2}' | while read id; do
    [ -n "$id" ] && openclaw cron rm "$id" 2>/dev/null && echo "  ✅ 停止轮询: $id"
done

# 停 screen
echo "  [2/2] 停止服务..."
for s in agent-chat cloudflared tunnel-watch; do
    screen -S "$s" -X quit 2>/dev/null && echo "  ✅ 停止 $s"
done

# 停 node
PID=$(lsof -ti:3000 2>/dev/null)
[ -n "$PID" ] && kill "$PID" 2>/dev/null && echo "  ✅ 停止 node (端口 3000)"

pkill -f "cloudflared tunnel" 2>/dev/null && echo "  ✅ 停止 cloudflared"

echo ""
echo "  全部已停止"
echo ""
echo "  按 Enter 关闭..."
read -r

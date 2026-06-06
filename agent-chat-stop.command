#!/bin/bash
# agent-chat 一键停止 for Mac

echo ""
echo "  ══ Agent Chat 一键停止 (Mac) ══"
echo ""

# 停 cron jobs（agent 消息轮询，不影响隧道）
echo "  [1/3] 停止 agent 轮询..."
openclaw cron list 2>/dev/null | grep "agent-chat" | awk '{print $2}' | while read id; do
    [ -n "$id" ] && openclaw cron rm "$id" 2>/dev/null && echo "  ✅ 停止轮询: $id"
done

# 停 cloudflared（用户级和 root 级都试）
echo "  [2/3] 停止 cloudflared..."
pkill -f "cloudflared tunnel" 2>/dev/null && echo "  ✅ 停止用户级 cloudflared" || echo "  （无用户级 cloudflared）"
sudo -n launchctl bootout system/com.cloudflare.cloudflared 2>/dev/null && echo "  ✅ 停止系统级 cloudflared" || true

# 停 Node
echo "  [3/3] 停止 Node 服务器..."
for s in agent-chat; do
    screen -S "$s" -X quit 2>/dev/null && echo "  ✅ 停止 $s"
done
PID=$(lsof -ti:3000 2>/dev/null)
[ -n "$PID" ] && kill "$PID" 2>/dev/null && echo "  ✅ 停止 node (端口 3000)"

echo ""
echo "  全部已停止"
echo ""
echo "  按 Enter 关闭..."
read -r

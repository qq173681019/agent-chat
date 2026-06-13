#!/bin/bash
# multi-agent 一键停止 (Mac)
# 只停 multi-* 标签, 不动 3000 主干

set -e

PLIST_DIR="$HOME/Library/LaunchAgents"
UID_VAL=$(id -u)

echo ""
echo "  ══ Multi-Agent 一键停止 (Mac) ══"
echo ""

# 1. launchctl bootout / unload
echo "  [1/4] 停 6 个 plist..."
for LABEL in com.agentchat.multi-server \
            com.agentchat.multi-bot-xiaodai \
            com.agentchat.multi-bot-hooligan \
            com.agentchat.multi-bot-merchant \
            com.agentchat.multi-bot-judge \
            com.agentchat.multi-bot-gossip; do
    launchctl bootout gui/$UID_VAL "$PLIST_DIR/$LABEL.plist" 2>/dev/null \
        || launchctl unload "$PLIST_DIR/$LABEL.plist" 2>/dev/null \
        || true
    echo "    ✅ $LABEL 停"
done

# 2. pkill 兜底
echo ""
echo "  [2/4] pkill 兜底..."
pkill -f "node.*server/multi-agent.js" 2>/dev/null && echo "    ✅ pkill multi-agent.js" || echo "    （无 multi-agent.js 进程）"
pkill -f "node.*server/agent-bot.js" 2>/dev/null && echo "    ✅ pkill agent-bot.js" || echo "    （无 agent-bot.js 进程）"
# 注: agent-bot.js 是主干 3000 跟 multi-agent 3001 共用的, pkill -f 会 kill 全部
# 实际只 kill 跑 multi-config-* 的实例:
sleep 1
pkill -f "multi-config-" 2>/dev/null && echo "    ✅ pkill multi-config-* (含 main 主干 config-b 的) -- wait 这会 kill 主干 agent-a/b 吗? NO, 因为它们 config 是 config.json / config-b.json" || true

# 3. 等 2 秒
echo ""
echo "  [3/4] 等 2 秒..."
sleep 2

# 4. 验证
echo ""
echo "  [4/4] 验证..."
echo "  multi-* plist 状态:"
for LABEL in com.agentchat.multi-server \
            com.agentchat.multi-bot-xiaodai \
            com.agentchat.multi-bot-hooligan \
            com.agentchat.multi-bot-merchant \
            com.agentchat.multi-bot-judge \
            com.agentchat.multi-bot-gossip; do
    STATE=$(launchctl print gui/$UID_VAL/$LABEL 2>&1 | grep "^	state" | awk '{print $3}')
    echo "    $LABEL: $STATE"
done
echo ""
echo "  3001 端口:"
PID3001=$(lsof -nP -iTCP:3001 -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $2}')
if [ -n "$PID3001" ]; then
    echo "    ⚠️  3001 还有进程: PID $PID3001"
else
    echo "    ✅ 3001 已空"
fi
echo ""
echo "  3000 主干仍服务?..."
R3000=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "https://agent-chat.org/" 2>/dev/null)
echo "    agent-chat.org: $R3000 (期望 200, 主干没被影响)"
echo ""
echo "  公网 multi.agent-chat.org: (期望 502 / connection refused)"
R502=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://multi.agent-chat.org/" 2>/dev/null)
echo "    multi.agent-chat.org: $R502"

echo ""
echo "  ═══════════════════════════════════════"
echo "  ✅ multi-agent 已停"
echo "  💡 重新启: 跑 multi-agent-start.command"
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭..."
read -r

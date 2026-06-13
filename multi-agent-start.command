#!/bin/bash
# multi-agent 一键启动 (Mac)
# 跑 install 已经装好 plist 的话, 这里只是重新 load 一下
# 跟 install 的区别: install 期望 plist 在 $PLIST_DIR; start 期望 plist 已装
# 两者是 idempotent — install 反复跑不会出问题

set -e

PLIST_DIR="$HOME/Library/LaunchAgents"
UID_VAL=$(id -u)

echo ""
echo "  ══ Multi-Agent 一键启动 (Mac) ══"
echo ""

# 1. launchctl bootstrap / load
echo "  [1/4] 启动 6 个 plist..."
for LABEL in com.agentchat.multi-server \
            com.agentchat.multi-bot-xiaodai \
            com.agentchat.multi-bot-hooligan \
            com.agentchat.multi-bot-merchant \
            com.agentchat.multi-bot-judge \
            com.agentchat.multi-bot-gossip; do
    STATE=$(launchctl print gui/$UID_VAL/$LABEL 2>&1 | grep "^	state" | awk '{print $3}')
    if [ "$STATE" = "running" ]; then
        echo "    ⏭  $LABEL 已在跑"
    else
        launchctl bootstrap gui/$UID_VAL "$PLIST_DIR/$LABEL.plist" 2>/dev/null \
            || launchctl load -w "$PLIST_DIR/$LABEL.plist" 2>&1
        echo "    ✅ $LABEL 启动"
    fi
done

# 2. 等 3 秒 launchd 拉起
echo ""
echo "  [2/4] 等 3 秒让 launchd 拉起..."
sleep 3

# 3. 验证
echo ""
echo "  [3/4] 验证..."
echo "  进程状态:"
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
echo "  3001 端口 (multi-server):"
R=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:3001/api/health" 2>/dev/null)
if [ "$R" = "200" ]; then
    echo "    ✅ 3001 /api/health: 200"
else
    echo "    ⚠️  3001 /api/health: $R (server 可能没启)"
fi
echo ""
echo "  5 bot 在线状态:"
for ROLE in xiaodai hooligan merchant judge gossip; do
    ON=$(curl -s --max-time 3 "http://localhost:3001/api/agents" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for a in d.get('agents', []):
        if a['id'] == '$ROLE':
            print('🟢 online' if a.get('online') else '⚪ offline')
            sys.exit(0)
except: pass
print('?')
" 2>/dev/null)
    echo "    $ROLE: $ON"
done
echo ""
echo "  公网 (multi.agent-chat.org):"
for i in $(seq 1 10); do
    R=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://multi.agent-chat.org/" 2>/dev/null)
    if [ "$R" = "200" ]; then
        echo "    ✅ multi.agent-chat.org: 200"
        break
    fi
    sleep 1
done
[ "$R" != "200" ] && echo "    ⚠️  multi.agent-chat.org: $R"

# 4. 主干是否仍 200
echo ""
echo "  [4/4] 主干 (3000) 仍服务?..."
R3000=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "https://agent-chat.org/" 2>/dev/null)
echo "    agent-chat.org: $R3000 (期望 200)"

echo ""
echo "  ═══════════════════════════════════════"
echo "  ✅ multi-agent 启动完成"
echo "  🌐 https://multi.agent-chat.org/  浏览器可访问"
echo "  🌐 https://agent-chat.org/         主干不动"
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭..."
read -r

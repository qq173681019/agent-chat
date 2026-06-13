#!/bin/bash
# all-stop.command — 一键停全套 (2 bot + 5 bot = 9 个 plist)
# 2026-06-13: 不动 cloudflared / tunnel; 只停 9 个 launchd 服务
#   launchctl bootout 优先, fallback 到 unload
#   跟 multi-agent-stop 一样, 但包含 2 bot 端 (server/agent-a/agent-b)

set -e

PLIST_DIR="$HOME/Library/LaunchAgents"
UID_VAL=$(id -u)

LABELS=(
  com.agentchat.server
  com.agentchat.agent-a
  com.agentchat.agent-b
  com.agentchat.multi-server
  com.agentchat.multi-bot-xiaodai
  com.agentchat.multi-bot-hooligan
  com.agentchat.multi-bot-merchant
  com.agentchat.multi-bot-judge
  com.agentchat.multi-bot-gossip
)

echo ""
echo "  ══ Agent Chat 全套一键停止 ══"
echo ""

# 1. 停 9 个 plist
echo "  [1/3] 停 9 个 plist..."

STOPPED=0
ALREADY_STOPPED=0
for L in "${LABELS[@]}"; do
    STATE=$(launchctl print gui/$UID_VAL/$L 2>&1 | grep "^	state" | awk '{print $3}')
    if [ "$STATE" != "running" ] && [ "$STATE" != "spawn" ]; then
        echo "    ⏭  $L ($STATE, skip)"
        ALREADY_STOPPED=$((ALREADY_STOPPED + 1))
    else
        if launchctl bootout gui/$UID_VAL "$PLIST_DIR/$L.plist" 2>/dev/null; then
            echo "    ✅ $L 停 (bootout)"
            STOPPED=$((STOPPED + 1))
        elif launchctl unload "$PLIST_DIR/$L.plist" 2>/dev/null; then
            echo "    ✅ $L 停 (unload)"
            STOPPED=$((STOPPED + 1))
        else
            echo "    ⚠️  $L 停失败 (强制 kill?)"
        fi
    fi
done

echo "  → 停 $STOPPED 个, 跳过 $ALREADY_STOPPED 个"

# 2. 等 2 秒 + pkill 兜底
echo ""
echo "  [2/3] 等 2 秒 + pkill 兜底..."
sleep 2
pkill -f "node.*server/index.js" 2>/dev/null && echo "    ✅ pkill index.js" || true
pkill -f "node.*server/multi-agent.js" 2>/dev/null && echo "    ✅ pkill multi-agent.js" || true
pkill -f "node.*server/agent-bot.js" 2>/dev/null && echo "    ✅ pkill agent-bot.js" || true

# 3. 验证全停
echo ""
echo "  [3/3] 验证全停..."

STILL_RUNNING=""
DOWN=0
for L in "${LABELS[@]}"; do
    STATE=$(launchctl print gui/$UID_VAL/$L 2>&1 | grep "^	state" | awk '{print $3}')
    if [ "$STATE" = "running" ] || [ "$STATE" = "spawn" ]; then
        STILL_RUNNING="$STILL_RUNNING $L"
        echo "    ❌ $L: $STATE (没停)"
    else
        DOWN=$((DOWN + 1))
        echo "    ✅ $L: $STATE"
    fi
done

echo ""
echo "  ═══════════════════════════════════════"
if [ "$DOWN" = "9" ]; then
    echo "  ✅ 9/9 全停"
else
    echo "  ⚠️  $DOWN/9 停, 没停的:$STILL_RUNNING"
    echo "  试手动: launchctl kill SIGTERM gui/$(id -u)/<label>"
fi
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭..."
read -r

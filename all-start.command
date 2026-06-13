#!/bin/bash
# all-start.command — 一键启动全套 (2 bot + 5 bot = 9 个 plist)
# 2026-06-13: 不动 cloudflared / tunnel; plist 在 ~/Library/LaunchAgents/ 装好后
#   这里只做 launchctl bootstrap / load, idempotent (已在跑就 skip)

set -e

PLIST_DIR="$HOME/Library/LaunchAgents"
UID_VAL=$(id -u)
REPO="/Users/gongruolan/Documents/GitHub/agent-chat"

# 9 个 label 顺序: server → 2 bot (main), 5 bot server → 5 bot
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
echo "  ══ Agent Chat 全套一键启动 ══"
echo ""

# 0. 必备检查
echo "  [0/4] 环境检查..."

if [ ! -d "$PLIST_DIR" ]; then
    echo "  ❌ $PLIST_DIR 不存在, 请先跑 multi-agent-install.command"
    exit 1
fi

MISSING=0
for L in "${LABELS[@]}"; do
    if [ ! -f "$PLIST_DIR/$L.plist" ]; then
        echo "  ❌ 缺 plist: $PLIST_DIR/$L.plist"
        MISSING=1
    fi
done
if [ "$MISSING" = "1" ]; then
    echo ""
    echo "  提示: 跑 multi-agent-install.command 装 5 bot 的 plist"
    exit 1
fi

# 关键文件 (server / multi-server / agents.json) 都在
for F in "$REPO/server/index.js" "$REPO/server/multi-agent.js" "$REPO/agents.json"; do
    if [ ! -f "$F" ]; then
        echo "  ❌ 关键文件不在: $F"
        exit 1
    fi
done

echo "  ✅ 9 个 plist + 关键文件都齐"

# 1. 启动每个 plist (idempotent)
echo ""
echo "  [1/4] 启动 9 个 plist (idempotent)..."

STARTED=0
SKIPPED=0
for L in "${LABELS[@]}"; do
    STATE=$(launchctl print gui/$UID_VAL/$L 2>&1 | grep "^	state" | awk '{print $3}')
    if [ "$STATE" = "running" ] || [ "$STATE" = "spawn" ]; then
        echo "    ⏭  $L ($STATE, skip)"
        SKIPPED=$((SKIPPED + 1))
    else
        if launchctl bootstrap gui/$UID_VAL "$PLIST_DIR/$L.plist" 2>/dev/null; then
            echo "    ✅ $L 启动 (bootstrap)"
            STARTED=$((STARTED + 1))
        elif launchctl load -w "$PLIST_DIR/$L.plist" 2>/dev/null; then
            echo "    ✅ $L 启动 (load)"
            STARTED=$((STARTED + 1))
        else
            echo "    ❌ $L 启动失败"
        fi
    fi
done

echo "  → 启动 $STARTED 个, 跳过 $SKIPPED 个"

# 2. 等 4 秒让 launchd 拉起
echo ""
echo "  [2/4] 等 4 秒让 launchd 拉起..."
sleep 4

# 3. 验证 9 个服务状态
echo ""
echo "  [3/4] 验证 9 个服务状态..."

RUNNING=0
NOT_RUNNING=""
for L in "${LABELS[@]}"; do
    STATE=$(launchctl print gui/$UID_VAL/$L 2>&1 | grep "^	state" | awk '{print $3}')
    if [ "$STATE" = "running" ] || [ "$STATE" = "spawn" ]; then
        RUNNING=$((RUNNING + 1))
        echo "    ✅ $L: $STATE"
    else
        NOT_RUNNING="$NOT_RUNNING $L"
        echo "    ❌ $L: $STATE"
    fi
done

echo ""
echo "  → $RUNNING / 9 running"

# 4. 端到端验证 (端口 + 域名)
echo ""
echo "  [4/4] 端到端验证..."

if curl -s --max-time 3 http://localhost:3000/api/config > /dev/null 2>&1; then
    echo "    ✅ 3000 (双人 server) 响应"
else
    echo "    ❌ 3000 没响应"
fi

if curl -s --max-time 3 http://localhost:3001/api/config > /dev/null 2>&1; then
    echo "    ✅ 3001 (五人 server) 响应"
else
    echo "    ❌ 3001 没响应"
fi

if curl -s --max-time 5 https://agent-chat.org/api/config > /dev/null 2>&1; then
    echo "    ✅ agent-chat.org (公网 2 bot) 200"
else
    echo "    ⚠️  agent-chat.org 没通 (公网/隧道问题, 不归 all-start 管)"
fi

if curl -s --max-time 5 https://multi.agent-chat.org/api/config > /dev/null 2>&1; then
    echo "    ✅ multi.agent-chat.org (公网 5 bot) 200"
else
    echo "    ⚠️  multi.agent-chat.org 没通 (公网/隧道问题, 不归 all-start 管)"
fi

echo ""
echo "  ═══════════════════════════════════════"
if [ "$RUNNING" = "9" ]; then
    echo "  ✅ 9/9 启动就绪"
    echo "  🌐 2 bot: http://localhost:3000  |  https://agent-chat.org"
    echo "  🌐 5 bot: http://localhost:3001  |  https://multi.agent-chat.org"
else
    echo "  ⚠️  $RUNNING/9 running, 没起来的: $NOT_RUNNING"
    echo "  看日志: ~/Library/Logs/com.agentchat.*.out.log"
fi
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭 (服务继续后台跑)..."
read -r

#!/bin/bash
# multi-agent 一键安装 (首次或 plist 改后)
# 把 6 个 plist 装到 ~/Library/LaunchAgents/，然后 launchctl load
# 不动 3000 主干

set -e

PLIST_DIR="$HOME/Library/LaunchAgents"
REPO="/Users/gongruolan/Documents/GitHub/agent-chat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  ══ Multi-Agent 一键安装 (Mac) ══"
echo ""

# 0. 环境
if ! command -v node &> /dev/null; then
    echo "❌ 请先安装 Node.js: https://nodejs.org"
    exit 1
fi
if [ ! -f "$REPO/server/multi-agent.js" ]; then
    echo "❌ $REPO/server/multi-agent.js 不在 (main 分支没 cherry-pick 这个文件?)"
    exit 1
fi
if [ ! -f "$REPO/agents.json" ]; then
    echo "❌ $REPO/agents.json 不在 (main 分支没 cherry-pick?)"
    exit 1
fi
for ROLE in xiaodai hooligan merchant judge gossip; do
    if [ ! -f "$REPO/multi-config-$ROLE.json" ]; then
        echo "❌ multi-config-$ROLE.json 不在"
        exit 1
    fi
done

# 1. 5 config 已就绪 (在仓库根)
echo "  [1/3] 检查 5 份 bot config..."
for ROLE in xiaodai hooligan merchant judge gossip; do
    echo "    ✅ multi-config-$ROLE.json"
done

# 2. 6 plist 已生成 (在 $PLIST_DIR)
echo ""
echo "  [2/3] 检查 6 份 plist..."
for LABEL in com.agentchat.multi-server \
            com.agentchat.multi-bot-xiaodai \
            com.agentchat.multi-bot-hooligan \
            com.agentchat.multi-bot-merchant \
            com.agentchat.multi-bot-judge \
            com.agentchat.multi-bot-gossip; do
    if [ -f "$PLIST_DIR/$LABEL.plist" ]; then
        echo "    ✅ $LABEL.plist"
    else
        echo "    ❌ $LABEL.plist 不在 $PLIST_DIR"
        echo "       (你应该跑 stage 2 step 5 先把 plist 生成好)"
        exit 1
    fi
done

# 3. launchctl load
echo ""
echo "  [3/3] launchctl load 全部 6 个..."
for LABEL in com.agentchat.multi-server \
            com.agentchat.multi-bot-xiaodai \
            com.agentchat.multi-bot-hooligan \
            com.agentchat.multi-bot-merchant \
            com.agentchat.multi-bot-judge \
            com.agentchat.multi-bot-gossip; do
    launchctl load -w "$PLIST_DIR/$LABEL.plist" 2>&1 && echo "    ✅ $LABEL loaded"
done

# 4. 验证
echo ""
echo "  ══ 验证 (3 秒后) ══"
sleep 3
echo "  进程状态:"
UID_VAL=$(id -u)
for LABEL in com.agentchat.multi-server \
            com.agentchat.multi-bot-xiaodai \
            com.agentchat.multi-bot-hooligan \
            com.agentchat.multi-bot-merchant \
            com.agentchat.multi-bot-judge \
            com.agentchat.multi-bot-gossip; do
    STATE=$(launchctl print gui/$UID_VAL/$LABEL 2>&1 | grep "^	state" | awk '{print $3}')
    PID=$(lsof -nP -iTCP:3001 -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $2}')
    echo "    $LABEL: $STATE"
done
echo ""
echo "  3001 端口:"
PID3001=$(lsof -nP -iTCP:3001 -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $2}')
if [ -n "$PID3001" ]; then
    echo "    ✅ 3001 端口在 PID $PID3001"
else
    echo "    ⚠️  3001 还没起 (server 可能还在加载)"
fi

echo ""
echo "  ═══════════════════════════════════════"
echo "  ✅ 安装完成"
echo "  💡 接下来跑 multi-agent-start.command"
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭..."
read -r

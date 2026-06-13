#!/bin/bash
# 2人启动.command — 一键启动 2 bot 端 (3 个 plist: server + agent-a + agent-b)
# 5 bot 不动. idempotent: 已在跑全 skip.
# 2026-06-13 创建: 跟 2人+多人一起启动.command 配套, 给只想跑 2 bot 的场景用.

cd "$(dirname "$0")"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLISTS=(
  "com.agentchat.server"
  "com.agentchat.agent-a"
  "com.agentchat.agent-b"
)

echo ""
echo "  ══ Agent Chat 2 人一键启动 ══"
echo ""
echo "  [1/3] 启动 3 个 plist (idempotent)..."

STARTED=0
SKIPPED=0
for L in "${PLISTS[@]}"; do
  P="$PLIST_DIR/$L.plist"
  if [ ! -f "$P" ]; then
    echo "    ⚠️  $L.plist 不存在 (skip)"
    SKIPPED=$((SKIPPED+1))
    continue
  fi
  # 检查是否已在跑
  if launchctl list 2>/dev/null | grep -q "$L"; then
    echo "    ⏭  $L 已在跑 (skip)"
    SKIPPED=$((SKIPPED+1))
  else
    launchctl bootstrap "gui/$(id -u)" "$P" 2>&1 | head -1
    echo "    ✅ $L 启动 (bootstrap)"
    STARTED=$((STARTED+1))
  fi
done
echo "  → 启动 $STARTED 个, 跳过 $SKIPPED 个"

echo ""
echo "  [2/3] 等 3 秒让 launchd 拉起..."
sleep 3

echo ""
echo "  [3/3] 验证 3 个服务状态..."
RUNNING=0
for L in "${PLISTS[@]}"; do
  STATE=$(launchctl list 2>/dev/null | grep "$L" | awk '{print $1}')
  if [ -n "$STATE" ]; then
    echo "    ✅ $L: $STATE"
    RUNNING=$((RUNNING+1))
  else
    echo "    ❌ $L: 没跑"
  fi
done
echo "  → $RUNNING / 3 in跑"

# 端口检测
echo ""
echo "  [端口检测]"
if curl -s --max-time 3 http://localhost:3000/api/config > /dev/null 2>&1; then
  echo "    ✅ 3000 (2 bot server) 响应"
else
  echo "    ❌ 3000 没响应"
fi

echo ""
echo "  ═══════════════════════════════════════"
echo "  🌐 2 bot: http://localhost:3000  |  https://agent-chat.org"
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭 (服务继续后台跑)..."
read _

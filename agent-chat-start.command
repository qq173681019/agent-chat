#!/bin/bash
# agent-chat 一键启动 for Mac
# 功能：启动服务器 → 启动隧道 → 推送地址 → 开启轮询

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
PROXY="http://127.0.0.1:7897"

echo ""
echo "  ══ Agent Chat 一键启动 (Mac) ══"
echo ""

# ── 0. 环境检查 ──
if ! command -v node &> /dev/null; then
    echo "❌ 请先安装 Node.js: https://nodejs.org"
    exit 1
fi
if ! command -v cloudflared &> /dev/null; then
    echo "❌ 请先安装 cloudflared"
    exit 1
fi

# ── 1. 清理旧进程 ──
echo "  [1/5] 清理旧进程..."

PID=$(lsof -ti:3000 2>/dev/null)
[ -n "$PID" ] && kill "$PID" 2>/dev/null

for s in agent-chat cloudflared tunnel-watch; do
    screen -S "$s" -X quit 2>/dev/null
done
pkill -f "cloudflared tunnel" 2>/dev/null

sleep 2
echo "  ✅ 清理完成"

# ── 2. 安装依赖 ──
echo "  [2/5] 检查依赖..."
if [ ! -d "server/node_modules" ]; then
    echo "  📦 首次安装依赖..."
    (cd server && npm install) || true
fi
echo "  ✅ 依赖就绪"

# ── 3. 启动 Node.js 服务器 ──
echo "  [3/5] 启动聊天服务器 (端口 3000)..."
screen -dmS agent-chat bash -c "cd '$BASEDIR/server' && node index.js; exec bash"
sleep 3

if ! curl -s --max-time 3 http://localhost:3000/api/config > /dev/null 2>&1; then
    echo "  ❌ 服务器启动失败！"
    exit 1
fi
echo "  ✅ 服务器已启动"

# ── 4. 启动 cloudflared 隧道 ──
echo "  [4/5] 启动 Cloudflare 隧道..."
screen -dmS cloudflared bash -c "cloudflared tunnel --url http://localhost:3000 > /tmp/cloudflared.log 2>&1"

TUNNEL_URL=""
for i in $(seq 1 20); do
    sleep 1
    TUNNEL_URL=$(strings /tmp/cloudflared.log 2>/dev/null | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
    [ -n "$TUNNEL_URL" ] && break
done

if [ -z "$TUNNEL_URL" ]; then
    echo "  ❌ 隧道超时！检查: screen -r cloudflared"
    exit 1
fi
echo "  ✅ 隧道: $TUNNEL_URL"

# ── 5. 更新 ws-url.json 并推送 ──
echo "  [5/5] 推送隧道地址到 GitHub..."
cd "$BASEDIR"
UPDATED=$(date +%s)000

echo "{\"url\":\"$TUNNEL_URL\",\"updated\":$UPDATED}" > ws-url.json

sed -i '' "s|url: 'https://[^']*'|url: '$TUNNEL_URL'|g; s|updated: [0-9]*|updated: $UPDATED|g" vercel/api/ws-url.js 2>/dev/null || true

git add ws-url.json vercel/api/ws-url.js
git commit -m "chore: update tunnel URL ($(date +%H:%M:%S))" 2>/dev/null
git push origin main 2>&1 | grep -E "To https|error|fatal" || echo "  ✅ 已推送"

echo ""
echo "  ═══════════════════════════════════════"
echo "  ✅ 全部就绪！"
echo "  🌐 本地:   http://localhost:3000"
echo "  🌐 隧道:   $TUNNEL_URL"
echo "  📡 前端:   https://agent-chat-d1m3.vercel.app/"
echo "  🌐 正在打开浏览器..."
open https://agent-chat-d1m3.vercel.app/echo "  🤖 轮询:   OpenClaw cron 自动运行"
echo "  ═══════════════════════════════════════"
echo ""
echo "  按 Enter 关闭（服务继续后台运行）..."
read -r

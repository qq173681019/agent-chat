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

# ── 4. 检查命名隧道（agent-chat.org → localhost:3000） ──
echo "  [4/5] 检查命名隧道..."

# 检查是否有 cloudflared 在跑
if ! pgrep -f "cloudflared tunnel" > /dev/null; then
    # 没有就启动一个（用命名隧道的 token + 用户级 config）
    TOKEN="eyJhIjoiYjkwMDhjMGFmZGE1MTc4ZGNlOWQyYjU0ODM4MzFlNTYiLCJ0IjoiMzAzNWQ0YzQtODJiMy00YmI5LWIzMGEtYjYwNWVjYzczNzU1IiwicyI6IlpUUXhaalV3TjJZdE9XSTFNaTAwWlRCbUxUaGxZVEl0Wmprek1ETXlPVGt5TW1NMyJ9"
    if [ -f "$HOME/.cloudflared/config.yml" ]; then
        nohup cloudflared tunnel run --token "$TOKEN" > "$HOME/.cloudflared/agent-chat.log" 2>&1 &
        echo "  ✅ 已启动命名隧道（PID $!）"
    else
        echo "  ❌ 找不到 ~/.cloudflared/config.yml，隧道不会工作"
        echo "     请先看 DNS-SETUP.md 把 ingress 规则写好"
        exit 1
    fi
else
    echo "  ✅ 命名隧道已在运行"
fi

# 验证域名能访问
echo "  验证 https://agent-chat.org ..."
VERIFY_OK=0
for i in $(seq 1 15); do
    if curl -s --max-time 5 "https://agent-chat.org/api/config" > /dev/null 2>&1; then
        VERIFY_OK=1
        break
    fi
    sleep 2
done

if [ "$VERIFY_OK" = "1" ]; then
    echo "  ✅ agent-chat.org 已就绪"
else
    echo "  ⚠️  隧道启动但域名还没通（检查 DNS 记录）"
fi

# ── 5. 完成 ──
echo "  [5/5] 完成"
echo ""
echo "  ═══════════════════════════════════════"
echo "  ✅ 全部就绪！"
echo "  🌐 域名:   https://agent-chat.org  (固定地址，不会变)"
echo "  🌐 本地:   http://localhost:3000"
echo "  ═══════════════════════════════════════"
echo ""
echo "  正在打开浏览器..."
open https://agent-chat.org/

echo "  ═══════════════════════════════════════"
echo "  ✅ 全部就绪！"
echo "  🌐 本地:   http://localhost:3000"

echo ""
echo "  按 Enter 关闭（服务继续后台运行）..."
read -r

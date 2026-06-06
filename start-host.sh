#!/bin/bash
# Agent Chat - One Key Start (macOS / Linux)
set -e
cd "$(dirname "$0")"

echo ""
echo "  Agent Chat - One Key Start"
echo "  =========================="
echo ""

if ! command -v node &> /dev/null; then
  echo "  [FAIL] Please install Node.js: https://nodejs.org"
  exit 1
fi

if [ ! -d "server/node_modules" ]; then
  echo "  Installing dependencies..."
  cd server && npm install && cd ..
fi

if [ ! -f "config.json" ]; then
  echo "  [WARN] config.json not found, creating from template..."
  cp config.example.json config.json
  echo "  Please edit config.json, then run again."
  exit 1
fi

PORT=$(node -e "const c=require('./config.json'); console.log(c.serverPort||3000)")

# Step 1: Kill old processes (wait until fully dead)
echo "  [1/4] Cleaning old processes..."
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
pkill -9 cloudflared 2>/dev/null || true

# Wait until port is free and cloudflared is gone
WAITED=0
while [ $WAITED -lt 15 ]; do
  LISTENING=$(lsof -ti:$PORT 2>/dev/null || true)
  CF_RUNNING=$(pgrep cloudflared 2>/dev/null || true)
  if [ -z "$LISTENING" ] && [ -z "$CF_RUNNING" ]; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
echo "  [OK] Cleaned"

# Step 2: Start server
echo "  [2/4] Starting server on port $PORT..."
node server/index.js &
sleep 3

if ! curl -s --max-time 3 "http://localhost:$PORT/api/poll?since=0" > /dev/null 2>&1; then
  echo "  [FAIL] Server not responding!"
  exit 1
fi
echo "  [OK] Server ready"

# Step 3: Start/check named tunnel (agent-chat.org → localhost:PORT)
echo "  [3/4] Checking named tunnel..."

CF_TOKEN_FILE="$HOME/.cloudflared/agent-chat-token"
if [ ! -f "$CF_TOKEN_FILE" ]; then
  echo "  [FAIL] No tunnel token found at $CF_TOKEN_FILE"
  echo "         See DNS-SETUP.md for one-time setup"
  exit 1
fi
CF_TOKEN=$(cat "$CF_TOKEN_FILE")

if ! pgrep -f "cloudflared tunnel run" > /dev/null; then
  nohup cloudflared tunnel run --token "$CF_TOKEN" > "$HOME/.cloudflared/agent-chat.log" 2>&1 &
  echo "  [OK] Started named tunnel (PID $!)"
else
  echo "  [OK] Named tunnel already running"
fi

# Verify domain works
echo "  Verifying https://agent-chat.org ..."
VERIFY_OK=0
for i in $(seq 1 15); do
  if curl -s --max-time 5 "https://agent-chat.org/api/config" > /dev/null 2>&1; then
    VERIFY_OK=1
    break
  fi
  sleep 2
done

if [ "$VERIFY_OK" = "1" ]; then
  echo "  [OK] https://agent-chat.org is live!"
else
  echo "  [WARN] Tunnel running but domain not yet reachable. Check DNS."
fi

# Step 4: Done
echo "  [4/4] Done"
echo ""
echo "  =========================="
echo "  All done!"
echo "  Domain: https://agent-chat.org  (permanent address)"
echo "  Local:  http://localhost:$PORT"
echo "  =========================="
echo ""

# Open browser
command -v open &> /dev/null && open 'https://agent-chat.org'
command -v xdg-open &> /dev/null && xdg-open 'https://agent-chat.org'

wait

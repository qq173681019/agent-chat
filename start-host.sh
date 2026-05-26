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

# Step 3: Start tunnel
echo "  [3/4] Starting tunnel..."
LOG_FILE="./cloudflared.log"
rm -f "$LOG_FILE"

if command -v cloudflared &> /dev/null; then
  cloudflared tunnel --url "http://localhost:$PORT" > /dev/null 2> "$LOG_FILE" &
  CF_PID=$!

  echo "  Waiting for tunnel URL..."
  TUNNEL_URL=""
  for i in $(seq 1 30); do
    sleep 2
    if [ -f "$LOG_FILE" ]; then
      TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_FILE" 2>/dev/null | tail -1 || true)
      if [ -n "$TUNNEL_URL" ]; then
        break
      fi
    fi
    echo "  ... waiting ($i)"
  done

  if [ -z "$TUNNEL_URL" ]; then
    echo "  [FAIL] Tunnel did not start! Check cloudflared.log"
    kill $CF_PID 2>/dev/null || true
    exit 1
  fi
  echo "  [OK] Tunnel: $TUNNEL_URL"

  # Verify tunnel works
  echo "  Verifying tunnel..."
  if curl -s --max-time 10 "$TUNNEL_URL/api/poll?since=0" > /dev/null 2>&1; then
    echo "  [OK] Tunnel is live!"
  else
    echo "  [WARN] Tunnel not yet reachable, may need a few seconds..."
  fi

else
  echo "  [FAIL] cloudflared not found! Install: https://github.com/cloudflare/cloudflared/releases"
  exit 1
fi

# Step 4: Push to GitHub
echo "  [4/4] Pushing tunnel URL to GitHub..."
TS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "$(date +%s)000")
cat > ws-url.json << EOF
{"url":"$TUNNEL_URL","updated":$TS}
EOF

git add ws-url.json
git commit -m "chore: update tunnel URL" --allow-empty 2>/dev/null || true
git push origin main

echo ""
echo "  =========================="
echo "  All done!"
echo "  Local:  http://localhost:$PORT"
echo "  Tunnel: $TUNNEL_URL"
echo "  =========================="
echo ""

# Open browser (fixed Vercel URL)
command -v open &> /dev/null && open 'https://agent-chat-d1m3.vercel.app'
command -v xdg-open &> /dev/null && xdg-open 'https://agent-chat-d1m3.vercel.app'

echo "  Press Ctrl+C to stop all services"
echo ""
wait

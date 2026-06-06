/**
 * agent-a-poll.js - 只负责轮询和判断
 * 输出 NO_REPLY 或 NEED_REPLY + JSON（包含 serverUrl 和消息）
 * AI 回复由 cron 里的模型生成
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

// 服务器地址：agent-chat.org（命名隧道 + Cloudflare DNS，固定）
const BOT_ROLE = 'agent-a';

function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http;
    const req = mod.get(url, { timeout: 15000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`JSON parse error: ${data.substring(0, 200)}`)); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function main() {
  // 1. Server URL（固定地址）
  const serverUrl = 'https://agent-chat.org';

  // 2. Poll all messages
  const pollData = await fetchJSON(`${serverUrl}/api/poll?since=0`);
  const messages = pollData.messages || [];
  if (messages.length === 0) { console.log('NO_REPLY'); process.exit(0); }

  // 3. Check last 5 messages
  const last5 = messages.slice(-5);
  const last = last5[last5.length - 1];

  let shouldReply = false;
  let targetMsg = null;

  if (last.role === 'user') {
    const replied = last5.some(m => m.role === BOT_ROLE && m.id > last.id);
    if (!replied) { shouldReply = true; targetMsg = last; }
  } else if (last.role === 'agent-b') {
    const replied = last5.some(m => m.role === BOT_ROLE && m.id > last.id);
    if (!replied) { shouldReply = true; targetMsg = last; }
  }

  if (!shouldReply) { console.log('NO_REPLY'); process.exit(0); }

  // 4. Output info for the cron model to generate reply
  console.log('NEED_REPLY');
  console.log(JSON.stringify({
    serverUrl,
    targetMessage: targetMsg,
    recentMessages: last5
  }));
}

main().catch(e => { console.error(`FAIL: ${e.message}`); process.exit(1); });

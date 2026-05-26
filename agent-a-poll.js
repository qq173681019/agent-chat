/**
 * agent-a-poll.js - Agent A 轮询脚本（小呆/顾小狼的小胡子）
 * 
 * 用法: node agent-a-poll.js
 * 
 * 输出:
 *   NO_REPLY       → 不需要回复
 *   NEED_REPLY     → 需要回复，后面跟 JSON 格式的消息
 * 
 * 判断逻辑:
 *   - 最后一条是 user → 需要回复
 *   - 最后一条是 agent-b 且 agent-a 还没回复 → 可以回应
 *   - 最后一条是 agent-a → 不回复
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const VERCEL_URL = 'https://agent-chat-d1m3.vercel.app';
const BOT_ROLE = 'agent-a';
const BOT_NAME = '顾小狼的小胡子';
const LAST_ID_FILE = path.join(__dirname, '.poller_xiaodai_lastid');

function fetch(url) {
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
  // 1. 获取服务器地址
  let wsData;
  try {
    wsData = await fetch(`${VERCEL_URL}/api/ws-url`);
  } catch (e) {
    console.error(`FAIL: Cannot reach Vercel API: ${e.message}`);
    process.exit(1);
  }
  
  const serverUrl = wsData.url;
  if (!serverUrl) {
    console.error('FAIL: No server URL in ws-url response');
    process.exit(1);
  }
  
  // 2. 获取上次处理的 lastId
  let since = 0;
  try {
    since = parseInt(fs.readFileSync(LAST_ID_FILE, 'utf8').trim()) || 0;
  } catch {}
  
  // 3. 轮询消息
  let pollData;
  try {
    pollData = await fetch(`${serverUrl}/api/poll?since=${since}`);
  } catch (e) {
    console.error(`FAIL: Cannot poll server: ${e.message}`);
    process.exit(1);
  }
  
  const messages = pollData.messages || [];
  const lastId = pollData.lastId || since;
  
  // 保存 lastId
  fs.writeFileSync(LAST_ID_FILE, String(lastId));
  
  if (messages.length === 0) {
    console.log('NO_REPLY');
    process.exit(0);
  }
  
  // 4. 只看最后5条，判断是否需要回复
  const last5 = messages.slice(-5);
  const last = last5[last5.length - 1];
  
  let shouldReply = false;
  let targetMsg = null;
  
  if (last.role === 'user') {
    // 人类发言，检查 agent-a 是否已回复
    const agentAReplied = last5.some(m => 
      m.role === BOT_ROLE && m.id > last.id
    );
    if (!agentAReplied) {
      shouldReply = true;
      targetMsg = last;
    }
  } else if (last.role === 'agent-b') {
    // Agent B 说了什么，检查 agent-a 是否已回应
    const agentAReplied = last5.some(m =>
      m.role === BOT_ROLE && m.id > last.id
    );
    if (!agentAReplied) {
      shouldReply = true;
      targetMsg = last;
    }
  }
  // agent-a 自己的消息或系统消息 → 不回复
  
  if (!shouldReply) {
    console.log('NO_REPLY');
    process.exit(0);
  }
  
  // 5. 输出需要回复的消息
  console.log('NEED_REPLY');
  console.log(JSON.stringify({
    serverUrl,
    targetMessage: targetMsg,
    recentMessages: last5
  }));
}

main().catch(e => {
  console.error(`FAIL: ${e.message}`);
  process.exit(1);
});

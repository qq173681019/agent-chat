const https = require('https');
const fs = require('fs');
const path = require('path');

const LOCAL_WS_URL = path.join(__dirname, 'ws-url.json');

// Get server URL
let serverUrl = null;
try {
  let raw = fs.readFileSync(LOCAL_WS_URL, 'utf8').trim();
  if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
  serverUrl = JSON.parse(raw).url;
} catch {}
console.log('Server:', serverUrl);

// Poll
https.get(`${serverUrl}/api/poll?since=0`, r => {
  let d = '';
  r.on('data', c => d += c);
  r.on('end', () => {
    const data = JSON.parse(d);
    const msgs = data.messages || [];
    const last5 = msgs.slice(-5);
    const last = last5[last5.length - 1];
    console.log('Last 5:');
    last5.forEach(m => console.log(`  [${m.id}] ${m.role} <${m.from}>`));
    console.log('Last:', last.role, last.from, last.id);
    
    // Check if agent-a replied after last
    const replied = last5.some(m => m.role === 'agent-a' && m.id > last.id);
    console.log('Agent-a replied after last?', replied);
    console.log('Should reply?', last.role === 'user' && !replied);
  });
});

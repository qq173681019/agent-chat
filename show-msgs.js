const https = require('https');
https.get('https://versions-stephen-mem-county.trycloudflare.com/api/poll?since=75', r => {
  let d = '';
  r.on('data', c => d += c);
  r.on('end', () => {
    const data = JSON.parse(d);
    data.messages.forEach(m => console.log(`[${m.id}] ${m.role} <${m.from}>: ${m.content.substring(0, 60)}`));
  });
});

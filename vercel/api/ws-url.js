// Vercel Serverless Function: 从 GitHub jsdelivr CDN 读取当前 WebSocket 地址
const GITHUB_RAW = 'https://raw.githubusercontent.com/qq173681019/agent-chat/main/ws-url.json';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    const resp = await fetch(GITHUB_RAW + '?t=' + Date.now(), {
      headers: { 'User-Agent': 'agent-chat-vercel' }
    });
    const data = await resp.json();
    return res.status(200).json(data);
  } catch (e) {
    return res.status(500).json({ error: 'Failed to fetch ws-url', url: '' });
  }
}

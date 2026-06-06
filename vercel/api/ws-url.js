// Vercel Serverless Function: 实时从 GitHub API 读取当前 WebSocket 地址
//
// 不用 raw.githubusercontent.com（因为 Fastly 边缘 cache 偶尔卡住，导致文件改了但
// 客户端一直拿到旧版本）
// 改用 api.github.com（直接调 GitHub API，cache-free）
//
// 注意：api.github.com 匿名调用有 60 req/hr rate limit。
// 如果前端调用频繁，需要在请求里加 Authorization header（用 GitHub PAT）。
// 简单起见：先匿名跑，真触限流再加 PAT。

const GITHUB_API = 'https://api.github.com/repos/qq173681019/agent-chat/contents/ws-url.json';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  // 1 秒缓存足够去重，10 秒陈旧足够防 429
  res.setHeader('Cache-Control', 'public, max-age=1, s-maxage=1, stale-while-revalidate=10');

  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    const resp = await fetch(GITHUB_API + '?ref=main&t=' + Date.now(), {
      headers: {
        'User-Agent': 'agent-chat-vercel',
        'Accept': 'application/vnd.github.v3.raw'
      }
    });

    if (!resp.ok) {
      const text = await resp.text();
      return res.status(502).json({
        error: `GitHub API ${resp.status}: ${text.slice(0, 200)}`,
        url: ''
      });
    }

    const text = await resp.text();
    let data;
    try { data = JSON.parse(text); }
    catch { return res.status(502).json({ error: 'Invalid JSON from GitHub', raw: text.slice(0, 200) }); }

    return res.status(200).json(data);
  } catch (e) {
    return res.status(500).json({ error: 'Failed to fetch ws-url: ' + String(e), url: '' });
  }
}

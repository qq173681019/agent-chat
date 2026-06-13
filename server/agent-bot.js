const WebSocket = require('ws');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const { URL } = require('url');

// 支持 env 指定不同 config (用于跑多个 agent 实例)
const configPath = process.env.AGENT_CONFIG_PATH || path.join(__dirname, '../config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

// ===== secrets 注入 (2026-06-07) =====
function loadSecrets() {
  const fs2 = require('fs'), path2 = require('path'), os = require('os');
  const candidates = [
    process.env.AGENT_CHAT_SECRETS,
    path2.join(os.homedir(), '.agent-chat-secrets.json'),
    path2.join(__dirname, '..', 'secrets.json'),
  ];
  for (const p of candidates) {
    if (!p) continue;
    try {
      if (fs2.existsSync(p)) {
        const s = JSON.parse(fs2.readFileSync(p, 'utf-8'));
        if (s.apiKey || s.minimaxApiKey) return s;
      }
    } catch (e) { /* 静默失败 */ }
  }
  return null;
}
const _secrets = loadSecrets();
if (_secrets) {
  if (!config.apiKey && _secrets.apiKey) config.apiKey = _secrets.apiKey;
  if (!config.apiBase && _secrets.apiBase) config.apiBase = _secrets.apiBase;
  if (!config.minimaxApiKey && _secrets.minimaxApiKey) config.minimaxApiKey = _secrets.minimaxApiKey;
  if (!config.minimaxBase && _secrets.minimaxBase) config.minimaxBase = _secrets.minimaxBase;
}
if (!config.apiKey && !config.minimaxApiKey) {
  console.error('[FATAL] 既无 zhipu apiKey 也无 minimax apiKey。放到 ~/.agent-chat-secrets.json');
  process.exit(1);
}
// ===== end secrets =====

const SERVER_URL = config.serverUrl || `ws://localhost:${config.serverPort || 3000}`;
const BOT_NAME = config.botName || '🤖 Agent';
const BOT_ROLE = config.botRole || 'agent-a';
const FALLBACK_PREFIX = config.fallbackPrefix || '傻傻的';  // 兜底模型回复时加在 from 前
// 模型链: 首选 + 兜底. 第一个调失败就试下一个.
const MODELS = [config.model, ...(config.fallbackModels || [])].filter(Boolean);
const PRIMARY_MODEL = MODELS[0];
const SYSTEM_PROMPT = (config.systemPrompt || '你是{botName}，一个有趣的AI助手。').replace('{botName}', BOT_NAME);
const MAX_TOKENS = config.maxTokens || 200;
const TEMPERATURE = config.temperature || 0.85;
const MAX_HISTORY = config.maxHistory || 10;

let ws;
let conversationHistory = [];
let currentTurnModel = PRIMARY_MODEL;  // 当前回复用的模型, 给 agent_query 的回复用
// 2026-06-13: 沉默模式 (server 推 pause/resume 控制)
let silentMode = false;

function connect() {
  console.log(`[Agent] ${BOT_NAME} (${BOT_ROLE}) models=${MODELS.join(' -> ')}`);
  console.log(`[Agent] 连接到 ${SERVER_URL} ...`);
  ws = new WebSocket(SERVER_URL);
  ws.on('open', () => {
    console.log(`[Agent] ✅ 连接成功`);
    // 2026-06-13: 兼容 2 套 server: index.js (认 role) / multi-agent.js (认 agentId)
    ws.send(JSON.stringify({ type: 'join', name: BOT_NAME, role: BOT_ROLE, agentId: BOT_ROLE }));
  });
  ws.on('message', async (raw) => {
    const data = JSON.parse(raw);
    // 2026-06-13: 沉默模式控制
    if (data.type === 'pause') {
      silentMode = true;
      console.log(`[Agent] 🔇 进入沉默模式 (user 停止指令)`);
      return;
    }
    if (data.type === 'resume') {
      silentMode = false;
      console.log(`[Agent] 🎙️ 退出沉默模式 (user 恢复指令)`);
      return;
    }
    if (silentMode) {
      // 沉默模式: agent_query 也忽略 (除非是 resume)
      if (data.type === 'agent_query') {
        console.log(`[Agent] 🔇 沉默模式, 忽略 agent_query`);
      }
      return;
    }
    if (data.type === 'agent_query') {
      const userMsg = data.message.content;
      const from = data.message.from;
      console.log(`[Agent] ${from}: ${userMsg}`);
      conversationHistory.push({ role: 'user', content: userMsg });
      if (conversationHistory.length > MAX_HISTORY) conversationHistory = conversationHistory.slice(-MAX_HISTORY);
      try {
        // 2026-06-13: 工具调用 (Anthropic 协议). OpenAI fmt 直答不加工具
        const _useTools = MODELS[0].toLowerCase().match(/(minimax|glm)/);
        const result = _useTools
          ? await callAnthropicWithTools(conversationHistory, MODELS[0])
              .then(text => ({ text, model: MODELS[0] }))
              .catch(async (e) => {
                // 工具调用失败: 退回普通 LLM
                console.error(`[Agent] tool 调用失败 (${e.message.substring(0,80)}), 退回普通 LLM`);
                return await callLLMWithFallback(conversationHistory);
              })
          : await callLLMWithFallback(conversationHistory);
        currentTurnModel = result.model;
        const isFallback = result.model !== PRIMARY_MODEL;
        const prefix = isFallback ? FALLBACK_PREFIX : '';
        const reply = {
          type: 'agent_reply',
          content: result.text,
          replyTo: data.message.id,
          fromPrefix: prefix || undefined  // undefined 让 server 端不处理
        };
        ws.send(JSON.stringify(reply));
        conversationHistory.push({ role: 'assistant', content: result.text });
        console.log(`[Agent] 回复 (${result.model}${isFallback ? ' ⚠️FALLBACK' : ''}): ${result.text.substring(0, 60)}`);
      } catch (e) {
        console.error('[Agent] 全部模型都失败:', e.message);
        currentTurnModel = PRIMARY_MODEL;
        // 全部失败: 不加前缀 (这不是 fallback, 是 catch-all 兜底句)
        ws.send(JSON.stringify({ type: 'agent_reply', content: '嗯...脑子卡了一下 🤔', replyTo: data.message.id }));
      }
    }
  });
  ws.on('close', () => { console.log('[Agent] 断开，3秒后重连...'); setTimeout(connect, 3000); });
  ws.on('error', (e) => console.error('[Agent] 连接错误:', e.message));
}

// 2026-06-13: 工具调用 (股票行情, 用东方财富免费接口)
const TOOLS = [{
  name: 'stock_price',
  description: '查询 A 股实时行情. 返回: 名称, 当前价, 涨跌幅%, 最高/最低, 昨收, 时间. symbol 格式: sh600519 (沪市) / sz000001 (深市). 例: 贵州茅台=sh600519, 平安银行=sz000001.',
  input_schema: {
    type: 'object',
    properties: {
      symbol: { type: 'string', description: '股票代码, 格式 sh600519 / sz000001 / bj830xxx (北交所)' }
    },
    required: ['symbol']
  }
}];
const STOCK_API = 'https://qt.gtimg.cn/q=';  // 腾讯财经, A 股稳定, GBK 编码
async function callStockPrice(symbol) {
  return new Promise((resolve) => {
    // symbol 标准化: sh600519 / sz000001 / 600519 / 000001
    let s = (symbol || '').toLowerCase();
    if (!s.startsWith('sh') && !s.startsWith('sz') && !s.startsWith('bj')) {
      if (/^6\d{5}$/.test(symbol)) s = 'sh' + symbol;
      else if (/^0\d{5}$/.test(symbol)) s = 'sz' + symbol;
      else if (/^8\d{5}$/.test(symbol)) s = 'bj' + symbol;
      else return resolve({ error: 'symbol 格式不对, 用 sh600519 / sz000001 / 600519' });
    }
    const url = STOCK_API + s;
    const req = https.get(url, { timeout: 5000 }, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        try {
          // 腾讯返回 GBK 编码 (iconv-lite 之类), 用 buffer + utf8 兜底
          const buf = Buffer.concat(chunks);
          let body = buf.toString('utf8');
          // 如果 utf8 解出乱码, 试 gb18030 (腾讯财经用的)
          if (body.includes('\ufffd')) {
            try { body = require('iconv-lite').decode(buf, 'gb18030'); } catch (e) { /* 用 utf8 兜底 */ }
          }
          // 解析 v_sh600519="1~名称~代码~当前价~昨收~今开~...~时间戳~涨跌额~涨跌幅%~最高~最低~..."
          // 2026-06-13 实测字段位置: [3]=当前价 [4]=昨收 [5]=今开 [6]=成交量(手) [30]=时间戳(20260612161418) [31]=涨跌额(元) [32]=涨跌幅(%) [33]=最高 [34]=最低
          const m = body.match(/="([^"]+)"/);
          if (!m) return resolve({ error: '接口返回格式不对' });
          const parts = m[1].split('~');
          if (parts.length < 35) return resolve({ error: '返回字段不够, 股票可能不存在' });
          const name = parts[1] || '未知';
          const code = parts[2] || symbol;
          const price = parseFloat(parts[3]).toFixed(2);
          const preClose = parseFloat(parts[4]).toFixed(2);
          const open = parseFloat(parts[5]).toFixed(2);
          const volume = parts[6] || '0';
          const change = parseFloat(parts[31] || '0').toFixed(2);
          const pct = parseFloat(parts[32] || '0').toFixed(2);
          const high = parseFloat(parts[33] || '0').toFixed(2);
          const low = parseFloat(parts[34] || '0').toFixed(2);
          const time = parts[30] && /^\d{14}$/.test(parts[30]) ? new Date(parts[30].replace(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/, '$1-$2-$3 $4:$5:$6')).toLocaleString('zh-CN') : '未知';
          resolve({ symbol, name, code, price, change, pct: pct + '%', high, low, open, preClose, volume: volume + ' 手', time });
        } catch (e) { resolve({ error: '解析失败: ' + e.message }); }
      });
    });
    req.on('error', (e) => resolve({ error: '请求失败: ' + e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ error: '请求超时' }); });
  });
}

async function runToolCall(name, input) {
  if (name === 'stock_price') return await callStockPrice(input.symbol);
  return { error: '未知工具: ' + name };
}

// 工具调用循环 (Anthropic 协议): LLM 说 tool_use → 调工具 → 把结果塞回去 → 再问, 最多 3 轮
async function callAnthropicWithTools(history, modelName) {
  const apiKey = config.minimaxApiKey;
  const apiBase = config.minimaxBase || 'https://api.minimaxi.com/anthropic';
  const url = new URL(`${apiBase}/v1/messages`);
  let msgs = history.map(h => ({ role: h.role, content: h.content }));
  const MAX_TOOL_ROUNDS = 3;
  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const body = JSON.stringify({
      model: modelName,
      max_tokens: MAX_TOKENS,
      temperature: TEMPERATURE,
      system: SYSTEM_PROMPT,
      messages: msgs,
      tools: TOOLS
    });
    const resp = await new Promise((resolve, reject) => {
      const req = https.request({
        method: 'POST', hostname: url.hostname, path: url.pathname,
        headers: {
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
          'x-api-key': apiKey,
          'Content-Length': Buffer.byteLength(body)
        }
      }, (res) => {
        let data = '';
        res.on('data', c => data += c);
        res.on('end', () => {
          try {
            const j = JSON.parse(data);
            if (j.error) return reject(new Error('Anthropic: ' + (j.error.message || JSON.stringify(j.error))));
            resolve(j);
          } catch (e) { reject(new Error('JSON parse: ' + e.message)); }
        });
      });
      req.on('error', reject);
      req.setTimeout(35000, () => req.destroy(new Error('timeout')));
      req.write(body);
      req.end();
    });
    if (resp.stop_reason !== 'tool_use') {
      // 正常: 取 text
      const text = (resp.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n').trim();
      if (text) return text;
      const think = (resp.content || []).filter(c => c.type === 'thinking').map(c => c.thinking).join('\n').trim();
      if (think) return think;
      throw new Error('Anthropic 无内容: ' + JSON.stringify(resp).substring(0, 200));
    }
    // 工具调用: 把 LLM 的 tool_use 加入 msgs, 然后调工具, 把 tool_result 也加入
    msgs.push({ role: 'assistant', content: resp.content });
    const toolBlocks = resp.content.filter(c => c.type === 'tool_use');
    const toolResults = [];
    for (const tb of toolBlocks) {
      console.log(`[Agent] 🔧 调工具 ${tb.name}(${JSON.stringify(tb.input)})`);
      const result = await runToolCall(tb.name, tb.input);
      console.log(`[Agent] 🔧 工具返回: ${JSON.stringify(result).substring(0, 200)}`);
      toolResults.push({ type: 'tool_result', tool_use_id: tb.id, content: JSON.stringify(result) });
    }
    msgs.push({ role: 'user', content: toolResults });
  }
  throw new Error('工具调用达到 ' + MAX_TOOL_ROUNDS + ' 轮上限, 停');
}

// 按顺序尝试 MODELS, 第一个成功的就返回
async function callLLMWithFallback(history) {
  let lastErr = null;
  for (let i = 0; i < MODELS.length; i++) {
    const m = MODELS[i];
    // 2026-06-13: zhipu anthropic endpoint 也用 'x-api-key' (跟 minimax 一致), model 包含 'glm' 也走 anthropic
    const ml = m.toLowerCase();
    const fmt = (ml.includes('minimax') || ml.includes('glm')) ? 'anthropic' : 'openai';
    try {
      const text = fmt === 'anthropic' ? await callAnthropic(history, m) : await callOpenAI(history, m);
      return { text, model: m };
    } catch (e) {
      console.error(`[Agent] ${m} (${fmt}) 失败: ${e.message.substring(0, 120)}`);
      lastErr = e;
      // 继续试下一个
    }
  }
  throw lastErr || new Error('no models configured');
}

async function callAnthropic(history, modelName) {
  const apiKey = config.minimaxApiKey;
  const apiBase = config.minimaxBase || 'https://api.minimaxi.com/anthropic';
  const url = new URL(`${apiBase}/v1/messages`);
  const msgs = history.map(h => ({ role: h.role, content: h.content }));
  const body = JSON.stringify({
    model: modelName,
    max_tokens: MAX_TOKENS,
    temperature: TEMPERATURE,
    system: SYSTEM_PROMPT,
    messages: msgs
  });
  return new Promise((resolve, reject) => {
    const req = https.request({
      method: 'POST',
      hostname: url.hostname,
      path: url.pathname,
      headers: {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        'x-api-key': apiKey,
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) return reject(new Error('Anthropic: ' + (parsed.error.message || JSON.stringify(parsed.error))));
          if (parsed.content && Array.isArray(parsed.content)) {
            const text = parsed.content.filter(c => c.type === 'text').map(c => c.text).join('\n').trim();
            if (text) return resolve(text);
            const think = parsed.content.filter(c => c.type === 'thinking').map(c => c.thinking).join('\n').trim();
            if (think) return resolve(think);
          }
          reject(new Error('Anthropic 解析失败: ' + JSON.stringify(parsed).substring(0, 200)));
        } catch (e) { reject(new Error('JSON parse: ' + e.message + ' | ' + data.substring(0, 200))); }
      });
    });
    req.on('error', reject);
    req.setTimeout(35000, () => req.destroy(new Error('timeout')));
    req.write(body);
    req.end();
  });
}

async function callOpenAI(history, modelName) {
  const msgs = [{ role: 'system', content: SYSTEM_PROMPT }, ...history];
  const body = JSON.stringify({ model: modelName, messages: msgs, max_tokens: MAX_TOKENS, temperature: TEMPERATURE });
  const apiKey = process.env.LLM_API_KEY || config.apiKey || '';
  const apiBase = config.apiBase || 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  const useProxy = config.useProxy !== false;
  const proxy = config.proxy || 'http://127.0.0.1:7897';
  const proxyArg = useProxy ? `--proxy ${proxy} ` : '';
  const cmd = `curl -s --max-time 30 ${proxyArg}${apiBase} -H "Content-Type: application/json" -H "Authorization: Bearer ${apiKey}" -d '${body.replace(/'/g, "'\\''")}'`;
  const result = execSync(cmd, { encoding: 'utf-8', timeout: 35000 });
  const data = JSON.parse(result);
  if (data.choices && data.choices[0]) return data.choices[0].message.content.trim();
  throw new Error('API异常: ' + JSON.stringify(data).substring(0, 100));
}

console.log(`[Agent] 🤖 ${BOT_NAME} / ${MODELS[0]} (fallback: ${MODELS.slice(1).join(',') || '无'})`);
connect();

# 🤖 Agent Chat

一个轻量的多人 + 多 AI Agent 实时聊天室。

## ✨ 特性

- 💬 多人实时聊天（WebSocket）
- 🤖 多个 AI Agent 同时在线，可互相讨论
- 🌐 Vercel 前端（固定地址）+ 本地 WebSocket 服务器
- 📱 手机端完美适配
- 💾 聊天记录导出/导入
- ⚙️ 可配置机器人名字、模型、提示词
- 🔧 支持 OpenClaw / Hermes 等 Agent 框架接入

## 🏗️ 架构

```
Vercel 前端（固定地址）  →  ws-url.json  →  本地 Node.js 服务器
                                                    ↑
                                          cloudflared 公网隧道
                                                    ↑
                                    Agent A (cron轮询) + Agent B (cron轮询)
```

- **前端**：部署在 Vercel，地址固定不变（`agent-chat-d1m3.vercel.app`）
- **WebSocket 服务器**：跑在本地，通过 cloudflared 隧道暴露到公网
- **Agent 接入**：通过 HTTP API 轮询，不需要 WebSocket 客户端

## 🚀 快速开始

### 前提条件

- Node.js >= 18
- cloudflared（`brew install cloudflared`）

### 1. 启动服务器

```bash
git clone https://github.com/qq173681019/agent-chat.git
cd agent-chat
cp config.example.json config.json
# 编辑 config.json

# 启动（macOS）
bash start-host.sh

# 或手动启动
screen -dmS agent-chat bash -c 'cd server && node index.js'
screen -dmS cloudflared bash -c 'cloudflared tunnel --url http://localhost:3000 > /tmp/cloudflared.log 2>&1'
```

### 2. 部署前端到 Vercel

1. Fork 本仓库
2. 在 Vercel 导入，Root Directory 设为 `vercel`
3. 部署后获得固定地址

### 3. 更新隧道地址

cloudflared 重启后地址会变，运行：

```bash
./update-tunnel-url.sh https://新地址.trycloudflare.com
```

### 4. 接入 AI Agent

详见 **[AGENT_INTEGRATION.md](./AGENT_INTEGRATION.md)** — 完整的 Agent 接入指南。

## 📖 文档

| 文档 | 说明 |
|------|------|
| [AGENT_INTEGRATION.md](./AGENT_INTEGRATION.md) | **Agent 接入完全指南**（OpenClaw / Hermes 等） |
| [config.example.json](./config.example.json) | 配置文件模板 |

## 🔑 关键配置

编辑 `config.json`：

```json
{
  "botName": "你的Agent名字",
  "model": "glm-5",
  "apiKey": "你的API Key",
  "apiBase": "https://open.bigmodel.cn/api/paas/v4/chat/completions",
  "systemPrompt": "你是一个有趣的聊天AI...",
  "useProxy": true,
  "proxy": "http://127.0.0.1:7897"
}
```

## 📁 项目结构

```
agent-chat/
├── server/index.js        # WebSocket + HTTP API 服务器
├── vercel/                # Vercel 前端（部署用）
├── public/index.html      # 本地前端（备用）
├── AGENT_INTEGRATION.md   # Agent 接入指南 ⭐
├── ws-url.json            # 当前隧道地址
├── update-tunnel-url.sh   # 隧道地址更新脚本
└── config.example.json    # 配置模板
```

## License

MIT

---

## 🔁 隧道地址维护规则

### 背景
每次重启 cloudflared 隧道都会生成**新地址**，必须同步到 GitHub 才能让 Vercel 前端拿到。

### 隧道守护脚本（必读）

项目里已有 `watch-tunnel.sh`，**在部署电脑上必须运行**：

```bash
screen -dmS tunnel-watch bash /Users/gongruolan/Documents/GitHub/agent-chat/watch-tunnel.sh
```

脚本每 60 秒检测隧道是否存活，断了自动重启并调用 `update-tunnel-url.sh` 推送新地址到 GitHub。

### 手动更新隧道地址（万不得已时）

如果在部署电脑上手动重启了 cloudflared，手动更新推送：

```bash
cd ~/Documents/GitHub/agent-chat

# 获取当前隧道地址（从 cloudflared 日志）
NEW_URL=$(strings /tmp/cloudflared.log | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)

# 更新 ws-url.json
echo "{\"url\":\"$NEW_URL\",\"updated\":$(date +%s)000}" > ws-url.json

# 更新 Vercel API 硬编码地址（防止 CDN 缓存问题）
sed -i '' "s|url: 'https://[^']*'|url: '$NEW_URL'|g; s|updated: [0-9]*|updated: $(date +%s)000|g" vercel/api/ws-url.js

# 推送
git add ws-url.json vercel/api/ws-url.js
git commit -m "chore: update tunnel URL ($(date +%H:%M:%S))"
git push
```

### 验证连接

```bash
# 测试隧道是否可达（从任意网络）
curl -s --max-time 5 "https://<隧道地址>/api/config"

# 测试 Vercel 前端是否正常
curl -s --max-time 5 "https://agent-chat-d1m3.vercel.app/"
```

### 常见问题

**Q: 前端一直显示"连接中"？**  
A: 执行 redeploy 让 Vercel API 读取最新隧道地址。

**Q: curl 隧道地址超时？**  
A: 部署电脑的 cloudflared 可能断了，检查 `screen -ls` 和 `ps aux | grep cloudflared`。

**Q: 两个 AI Agent 都不说话？**  
A: 检查 cron jobs 是否在跑：`openclaw cron list`


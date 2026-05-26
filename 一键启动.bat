@echo off
chcp 65001 >nul 2>&1
title Agent Chat - 一键启动

echo.
echo   🚀 Agent Chat - 一键启动
echo   ━━━━━━━━━━━━━━━━━━━━━━━━━━
echo.

set "BASEDIR=%~dp0"
set "CLOUDFLARED=%BASEDIR%cloudflared.exe"

:: ====== Step 1: 杀掉旧进程 ======
echo   [1/4] 清理旧进程...
taskkill /FI "WINDOWTITLE eq agent-chat-server*" /F >nul 2>&1
:: Kill any node process on port 3000
for /f "tokens=5" %%p in ('netstat -ano ^| findstr :3000 ^| findstr LISTENING') do (
    taskkill /PID %%p /F >nul 2>&1
)
:: Kill old cloudflared
taskkill /IM cloudflared.exe /F >nul 2>&1
timeout /t 2 /nobreak >nul

:: ====== Step 2: 启动 Node.js 服务器 ======
echo   [2/4] 启动聊天服务器 (端口 3000)...
start "agent-chat-server" /min cmd /c "cd /d "%BASEDIR%server" && node index.js"
timeout /t 3 /nobreak >nul

:: Verify server is running
curl -s http://localhost:3000/api/poll?since=0 >nul 2>&1
if %errorlevel% neq 0 (
    echo   ❌ 服务器启动失败！
    pause
    exit /b 1
)
echo   ✅ 服务器已启动

:: ====== Step 3: 启动 cloudflared 隧道 ======
echo   [3/4] 启动 Cloudflare 隧道...
start "agent-chat-tunnel" /min cmd /c ""%CLOUDFLARED%" tunnel --url http://localhost:3000 2> "%BASEDIR%cloudflared_err.log" > "%BASEDIR%cloudflared.log""

:: 等待隧道就绪，提取URL
set TUNNEL_URL=
for /L %%i in (1,1,20) do (
    if "%TUNNEL_URL%"=="" (
        timeout /t 1 /nobreak >nul
        for /f "delims=" %%u in ('powershell -Command "if (Test-Path '%BASEDIR%cloudflared.log') { Select-String -Path '%BASEDIR%cloudflared.log' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches | ForEach-Object { $_.Matches.Value } | Select-Object -Last 1 }" 2^>nul') do (
            set TUNNEL_URL=%%u
        )
    )
)

if "%TUNNEL_URL%"=="" (
    echo   ❌ 隧道启动超时！检查 cloudflared.log
    pause
    exit /b 1
)

echo   ✅ 隧道地址: %TUNNEL_URL%

:: ====== Step 4: 更新 ws-url.json 并推送到 GitHub ======
echo   [4/4] 推送隧道地址到 GitHub...
for /f %%t in ('powershell -Command "[int64]((Get-Date).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds"') do set TS=%%t

echo {"url":"%TUNNEL_URL%","updated":%TS%} > "%BASEDIR%ws-url.json"

cd /d "%BASEDIR%"
git add ws-url.json
git commit -m "chore: update tunnel URL" --allow-empty
git push origin main

echo.
echo   ═══════════════════════════════════════
echo   ✅ 全部完成！
echo   🌐 本地: http://localhost:3000
echo   🌐 隧道: %TUNNEL_URL%
echo   📡 Vercel: https://agent-chat-d1m3.vercel.app
echo   🤖 Cron 轮询: 已在 OpenClaw 中运行
echo   ═══════════════════════════════════════
echo.
echo   按任意键关闭此窗口（服务器和隧道继续在后台运行）...
pause >nul

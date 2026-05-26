# Agent Chat - One Key Start (Windows)
$ErrorActionPreference = 'Continue'
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host ''
Write-Host '  Agent Chat - One Key Start'
Write-Host '  ===================='
Write-Host ''

# Step 1: Kill old processes (wait until fully dead)
Write-Host '  [1/4] Cleaning old processes...'
$port3000 = netstat -ano 2>$null | Select-String ':3000.*LISTENING'
if ($port3000) {
    $pids = $port3000 | ForEach-Object { ($_ -split '\s+')[-1] } | Sort-Object -Unique
    foreach ($p in $pids) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
}
Stop-Process -Name cloudflared -Force -ErrorAction SilentlyContinue

# Wait until port 3000 is free and cloudflared is gone
$waited = 0
while ($waited -lt 15) {
    $stillListening = netstat -ano 2>$null | Select-String ':3000.*LISTENING'
    $stillCf = Get-Process -Name cloudflared -ErrorAction SilentlyContinue
    if (-not $stillListening -and -not $stillCf) { break }
    Start-Sleep -Seconds 1
    $waited++
}
Write-Host '  [OK] Cleaned'

# Step 2: Start server
Write-Host '  [2/4] Starting server on port 3000...'
Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "cd /d `"$baseDir\server`" & node index.js" -WindowStyle Minimized
Start-Sleep -Seconds 4

$test = try { Invoke-WebRequest -Uri 'http://localhost:3000/api/poll?since=0' -TimeoutSec 5 -UseBasicParsing } catch { $null }
if (-not $test) {
    Write-Host '  [FAIL] Server not responding!'
    Read-Host 'Press Enter to exit'
    exit 1
}
Write-Host '  [OK] Server ready'

# Step 3: Start tunnel
Write-Host '  [3/4] Starting tunnel...'
$logFile = Join-Path $baseDir 'cloudflared.log'
$errFile = Join-Path $baseDir 'cloudflared_err.log'
# Remove old logs so we don't match stale URL
if (Test-Path $logFile) { Remove-Item $logFile -Force }
if (Test-Path $errFile) { Remove-Item $errFile -Force }

# cloudflared outputs everything to stderr, use -RedirectStandardError to capture it
Start-Process -FilePath "$baseDir\cloudflared.exe" -ArgumentList 'tunnel','--url','http://localhost:3000' -WindowStyle Minimized -RedirectStandardOutput $logFile -RedirectStandardError $errFile

Write-Host '  Waiting for tunnel URL...'
$tunnelUrl = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    # Check stderr log (cloudflared writes to stderr)
    foreach ($f in @($errFile, $logFile)) {
        if (Test-Path $f) {
            $lines = Get-Content $f -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
                    $tunnelUrl = $Matches[0]
                    break
                }
            }
            if ($tunnelUrl) { break }
        }
    }
    if ($tunnelUrl) { break }
    Write-Host "  ... waiting ($($i+1))"
}

if (-not $tunnelUrl) {
    Write-Host '  [FAIL] Tunnel did not start! Check cloudflared.log'
    Read-Host 'Press Enter to exit'
    exit 1
}
Write-Host "  [OK] Tunnel: $tunnelUrl"

# Verify tunnel actually works
Write-Host '  Verifying tunnel...'
$check = try { Invoke-WebRequest -Uri "$tunnelUrl/api/poll?since=0" -TimeoutSec 10 -UseBasicParsing } catch { $null }
if (-not $check) {
    Write-Host '  [WARN] Tunnel URL fetched but not yet reachable, may need a few seconds...'
} else {
    Write-Host '  [OK] Tunnel is live!'
}

# Step 4: Push to GitHub
Write-Host '  [4/4] Pushing tunnel URL to GitHub...'
$ts = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
$wsJson = @{url=$tunnelUrl; updated=$ts} | ConvertTo-Json -Compress
Set-Content -Path (Join-Path $baseDir 'ws-url.json') -Value $wsJson -Encoding UTF8

Push-Location $baseDir
git add ws-url.json
git commit -m 'chore: update tunnel URL' --allow-empty 2>$null
git push origin main
Pop-Location

Write-Host ''
Write-Host '  ===================='
Write-Host '  All done!'
Write-Host "  Local:  http://localhost:3000"
Write-Host "  Tunnel: $tunnelUrl"
Write-Host '  ===================='
Write-Host ''

# Open browser
Start-Process $tunnelUrl

Write-Host '  Press Enter to close this window (servers keep running)...'
Read-Host

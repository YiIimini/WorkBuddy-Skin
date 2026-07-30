# WorkBuddy-Skin 启动器 (Windows)
# 用法: powershell -ExecutionPolicy Bypass -File launcher.ps1 [-Stop] [-Status]
param(
  [switch]$Stop,
  [switch]$Status
)

$ErrorActionPreference = 'SilentlyContinue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Daemon    = Join-Path $ScriptDir 'daemon.js'
$PidFile   = Join-Path $ScriptDir 'daemon.pid'
$LogFile   = Join-Path $ScriptDir 'daemon.log'
$CDP_PORT  = 9222

function Write-Step($msg) { Write-Host "[WorkBuddy-Skin] $msg" -ForegroundColor Magenta }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

# ─── 状态检查 ───
if ($Status) {
  Write-Host "=== WorkBuddy-Skin 状态 (Windows) ==="
  $wb = Get-Process | Where-Object { $_.Path -like '*WorkBuddy*' }
  if ($wb) { Write-Ok "WorkBuddy 正在运行" } else { Write-Warn "WorkBuddy 未运行" }
  if (Test-Path $PidFile) {
    $pid_ = Get-Content $PidFile
    if (Get-Process -Id $pid_ -ErrorAction SilentlyContinue) { Write-Ok "守护进程运行中 (PID: $pid_)" } else { Write-Warn "守护进程已退出" }
  } else { Write-Warn "守护进程未运行" }
  try { Invoke-RestMethod "http://localhost:17890/api/health" -TimeoutSec 2 | Out-Null; Write-Ok "设置面板: http://localhost:17890" } catch { Write-Warn "设置面板不可访问" }
  exit 0
}

# ─── 停止守护进程 ───
function Stop-Daemon {
  if (Test-Path $PidFile) {
    $pid_ = Get-Content $PidFile
    Stop-Process -Id $pid_ -Force -ErrorAction SilentlyContinue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    Write-Ok "守护进程已停止"
  }
}
if ($Stop) { Stop-Daemon; exit 0 }

# ─── 查找 WorkBuddy ───
$Candidates = @(
  "$env:LOCALAPPDATA\Programs\WorkBuddy\WorkBuddy.exe",
  "$env:LOCALAPPDATA\Programs\workbuddy\WorkBuddy.exe",
  "$env:ProgramFiles\WorkBuddy\WorkBuddy.exe",
  "${env:ProgramFiles(x86)}\WorkBuddy\WorkBuddy.exe"
)
$WB = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $WB) {
  Write-Host "[X] 未找到 WorkBuddy.exe，请确认已安装" -ForegroundColor Red
  exit 1
}
Write-Ok "WorkBuddy: $WB"

# ─── 查找 Node.js ───
$Node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $Node) {
  Write-Host "[X] 未找到 node，请先安装 Node.js 18+: https://nodejs.org" -ForegroundColor Red
  exit 1
}
Write-Ok "Node.js: $Node"

# ─── 检查依赖 ───
if (-not (Test-Path (Join-Path $ScriptDir 'node_modules\chrome-remote-interface'))) {
  Write-Step "安装依赖 (chrome-remote-interface, gsap)..."
  Push-Location $ScriptDir
  & $Node (Join-Path (Split-Path $Node) 'node_modules\npm\bin\npm-cli.js') install chrome-remote-interface gsap 2>$null
  if ($LASTEXITCODE -ne 0) { & npm install chrome-remote-interface gsap }
  Pop-Location
}

# ─── 1. 退出旧 WorkBuddy ───
$running = Get-Process | Where-Object { $_.Path -eq $WB }
if ($running) {
  Write-Step "退出当前 WorkBuddy..."
  $running | Stop-Process -Force
  Start-Sleep -Seconds 2
}

# ─── 2. 带 CDP 参数启动 WorkBuddy ───
Write-Step "启动 WorkBuddy（CDP 端口 $CDP_PORT）..."
Start-Process $WB -ArgumentList "--remote-debugging-port=$CDP_PORT"

# ─── 3. 启动守护进程 ───
Stop-Daemon
Write-Step "启动背景注入守护进程..."
$proc = Start-Process $Node -ArgumentList "`"$Daemon`"" -WorkingDirectory $ScriptDir -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput $LogFile -RedirectStandardError $LogFile
$proc.Id | Out-File $PidFile -Encoding ascii
Write-Step "守护进程 PID: $($proc.Id)"

# ─── 4. 等待就绪 ───
$ready = $false
for ($i = 0; $i -lt 15; $i++) {
  try { Invoke-RestMethod "http://localhost:17890/api/health" -TimeoutSec 1 | Out-Null; $ready = $true; break } catch { Start-Sleep 1 }
}
if ($ready) { Write-Ok "守护进程已就绪" } else { Write-Warn "守护进程未就绪，请查看日志: $LogFile" }

Write-Host ""
Write-Step "============================================"
Write-Step "  WorkBuddy-Skin 已启动 (Windows)"
Write-Step "  设置面板: http://localhost:17890"
Write-Step "  查看状态: launcher.ps1 -Status"
Write-Step "  停止守护: launcher.ps1 -Stop"
Write-Step "============================================"

# V380 Web Camera - easy installer (Windows PowerShell)
# irm https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.ps1 | iex
$ErrorActionPreference = "Stop"

$RepoUrl = if ($env:REPO_URL) { $env:REPO_URL } else { "https://github.com/LeeMcQ/v380-web-camera.git" }
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $env:USERPROFILE "v380-web-camera" }
$WebPort = if ($env:PORT) { $env:PORT } else { "8090" }
$DecoderHttpPort = if ($env:DECODER_HTTP_PORT) { $env:DECODER_HTTP_PORT } else { "18080" }
$DecoderRtspPort = if ($env:DECODER_RTSP_PORT) { $env:DECODER_RTSP_PORT } else { "18554" }
$DeviceIdDefault = "89370567"
$CameraUserDefault = "admin"
$SourceDefault = "cloud"
$PublicHost = if ($env:PUBLIC_HOST) { $env:PUBLIC_HOST } else { "41.74.144.221" }
$GrafanaPort = if ($env:GRAFANA_PORT) { $env:GRAFANA_PORT } else { "8081" }


function Write-Info([string]$Message) { Write-Host "> $Message" }
function Write-Warn([string]$Message) { Write-Warning $Message }
function Write-Die([string]$Message) { Write-Error $Message; exit 1 }

function Test-Command([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-EnvValue([string]$Key, [string]$Path = ".env") {
  if (-not (Test-Path $Path)) { return "" }
  $line = Get-Content $Path | Where-Object { $_ -match "^$Key=" } | Select-Object -Last 1
  if (-not $line) { return "" }
  return $line.Substring($Key.Length + 1)
}

function Set-EnvValue([string]$Key, [string]$Value, [string]$Path = ".env") {
  $lines = @()
  if (Test-Path $Path) { $lines = Get-Content $Path }
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match "^$Key=") {
      $found = $true
      "$Key=$Value"
    } else { $line }
  }
  if (-not $found) { $out = @($out) + "$Key=$Value" }
  Set-Content -Path $Path -Value $out -Encoding utf8
}

function Read-Secret([string]$VarName, [string]$Prompt, [string]$Current) {
  $envVal = [Environment]::GetEnvironmentVariable($VarName)
  if ($envVal) { return $envVal }
  if ($Current -and $Current -ne "change-me") { return $Current }
  try {
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  } catch {
    return $Current
  }
}


function Test-PortListening([int]$Port) {
  try {
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return [bool]$c
  } catch {
    try {
      $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
      $listener.Start(); $listener.Stop(); return $false
    } catch { return $true }
  }
}

function Find-NextFreePort([int]$Start) {
  for ($p = $Start; $p -le ($Start + 50); $p++) {
    if (-not (Test-PortListening $p)) { return $p }
  }
  return $null
}

function Invoke-HttpProbe([string]$Url) {
  try {
    if ($Url -like "https*") {
      try { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } } catch {}
    }
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 4
    return @{ Code = [int]$resp.StatusCode; Body = [string]$resp.Content }
  } catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    return @{ Code = $code; Body = "" }
  }
}

function Probe-Grafana {
  $urls = @(
    "https://127.0.0.1:$GrafanaPort/api/health",
    "http://127.0.0.1:$GrafanaPort/api/health",
    "https://${PublicHost}:$GrafanaPort/api/health",
    "http://${PublicHost}:$GrafanaPort/api/health"
  )
  foreach ($u in $urls) {
    $r = Invoke-HttpProbe $u
    if ($r.Code -eq 200) { return "OK|$u|$($r.Body.Substring(0, [Math]::Min(120, $r.Body.Length)))" }
  }
  return "DOWN|none|unreachable"
}

function Invoke-Preflight {
  Write-Host "Preflight safety checks (before starting anything)" -ForegroundColor Cyan
  Write-Info "Preferred ports - web $WebPort, decoder HTTP $DecoderHttpPort, RTSP $DecoderRtspPort"
  Write-Info "Grafana must stay on $GrafanaPort; same public IP $PublicHost"

  $busy = $false
  foreach ($p in @([int]$WebPort, [int]$DecoderHttpPort, [int]$DecoderRtspPort)) {
    if (Test-PortListening $p) {
      $sug = Find-NextFreePort $p
      Write-Warn "Port $p is already in use (suggested next free: $sug)"
      $busy = $true
    } else {
      Write-Host "OK Port $p is free" -ForegroundColor Green
    }
  }

  $script:GrafanaPre = Probe-Grafana
  if ($script:GrafanaPre -like "OK|*") {
    Write-Host "OK Grafana health - $($script:GrafanaPre)" -ForegroundColor Green
    Set-Content (Join-Path $env:USERPROFILE ".v380-web-camera\grafana-before.state") "up"
  } else {
    Write-Warn "Grafana /api/health not reachable on :$GrafanaPort (recorded; install continues)"
    Set-Content (Join-Path $env:USERPROFILE ".v380-web-camera\grafana-before.state") "down"
  }

  if ($busy) {
    Write-Die "Aborting: preferred camera ports are busy. Free them or set PORT / DECODER_HTTP_PORT / DECODER_RTSP_PORT (never $GrafanaPort)."
  }
  if ($WebPort -eq $GrafanaPort -or $DecoderHttpPort -eq $GrafanaPort -or $DecoderRtspPort -eq $GrafanaPort) {
    Write-Die "Refusing to use port $GrafanaPort (reserved for Grafana)."
  }
  Write-Host "OK Preflight passed" -ForegroundColor Green
}

function Invoke-Postflight {
  Write-Host "Post-install safety checks" -ForegroundColor Cyan
  $grafanaPost = Probe-Grafana
  $grafanaOk = $false
  if ($grafanaPost -like "OK|*") {
    Write-Host "OK Grafana still healthy - $grafanaPost" -ForegroundColor Green
    $grafanaOk = $true
  } else {
    Write-Warn "Grafana /api/health not OK after start"
  }

  $cameraOk = $false
  for ($i = 1; $i -le 30; $i++) {
    $r = Invoke-HttpProbe "http://127.0.0.1:$WebPort/health"
    if ($r.Code -eq 200) {
      Write-Host "OK Camera /health on :$WebPort" -ForegroundColor Green
      $cameraOk = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $cameraOk) { Write-Warn "Camera /health not ready on :$WebPort" }

  Write-Host ""
  Write-Host "Re-run checklist (anytime)" -ForegroundColor Cyan
  Write-Host "  1) powershell -File scripts/safety-check.ps1"
  Write-Host "  2) Get-NetTCPConnection -State Listen | ? LocalPort -in 8081,8090,18080,18554"
  Write-Host "  3) Probe Grafana http(s)://127.0.0.1:$GrafanaPort/api/health"
  Write-Host "  4) Invoke-WebRequest http://127.0.0.1:$WebPort/health"
  Write-Host "  5) Open http://${PublicHost}:$WebPort (Grafana stays on $GrafanaPort)"

  if (-not $cameraOk) { Write-Warn "Install finished but camera health failed" }
  if (-not $grafanaOk -and $script:GrafanaPre -like "OK|*") { Write-Warn "Grafana was OK before install but not after" }
}

# Prefer Docker Desktop; else Node
$UseDocker = $false
if (Test-Command "docker") {
  try {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      docker compose version 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $UseDocker = $true }
    }
  } catch { }
}


if (-not $UseDocker) {
  if (-not (Test-Command "node")) { Write-Die "Node.js >= 18 required." }
  if (-not (Test-Command "npm")) { Write-Die "npm is required." }
  $major = [int]((node -p "process.versions.node.split('.')[0]").Trim())
  if ($major -lt 18) { Write-Die "Node.js >= 18 required." }
  Write-Info "Using Node.js $(node -v)"
} else {
  Write-Info "Using Docker Compose"
}


# Persist Grafana snapshot for safety-check.ps1 -After
$stateDir = Join-Path $env:USERPROFILE ".v380-web-camera"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

Invoke-Preflight

# Repo sync
if (Test-Path (Join-Path $InstallDir ".git")) {
  Write-Info "Updating existing install at $InstallDir"
  Push-Location $InstallDir
  try {
    git fetch --quiet origin main 2>$null
    git pull --ff-only origin main 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warn "Could not fast-forward; continuing with local tree" }
  } finally { Pop-Location }
} else {
  if (Test-Path $InstallDir) { Write-Die "INSTALL_DIR exists but is not a git repo: $InstallDir" }
  Write-Info "Fetching project into $InstallDir"
  git clone --depth 1 $RepoUrl $InstallDir
}
Set-Location $InstallDir

if (-not (Test-Path ".env")) {
  Write-Info "Creating .env from .env.example"
  Copy-Item ".env.example" ".env"
}

Set-EnvValue "PORT" "$WebPort"
if (-not (Get-EnvValue "STREAM_TIMEOUT_SEC")) { Set-EnvValue "STREAM_TIMEOUT_SEC" "120" }
Set-EnvValue "MOCK_CAMERA" "0"
if (-not (Get-EnvValue "DEVICE_ID")) { Set-EnvValue "DEVICE_ID" $DeviceIdDefault }
if (-not (Get-EnvValue "CAMERA_USERNAME")) { Set-EnvValue "CAMERA_USERNAME" $CameraUserDefault }
if (-not (Get-EnvValue "SOURCE")) { Set-EnvValue "SOURCE" $SourceDefault }
Set-EnvValue "DECODER_HTTP_PORT" "$DecoderHttpPort"
Set-EnvValue "DECODER_RTSP_PORT" "$DecoderRtspPort"

if ($UseDocker) {
  Set-EnvValue "DECODER_URL" "http://v380decoder:8080"
} else {
  Set-EnvValue "DECODER_URL" "http://127.0.0.1:$DecoderHttpPort"
}

$curPass = Get-EnvValue "CAMERA_PASSWORD"
$tokenCur = Get-EnvValue "ACCESS_TOKEN"
$newPass = Read-Secret "CAMERA_PASSWORD" "Camera password (blank to skip)" $curPass
if ($newPass) { Set-EnvValue "CAMERA_PASSWORD" $newPass }
elseif (-not $curPass) { Write-Warn "CAMERA_PASSWORD empty - set it in $InstallDir\.env for a real stream" }

$newToken = Read-Secret "ACCESS_TOKEN" "Web ACCESS_TOKEN (Enter keeps existing)" $tokenCur
if ($newToken) { Set-EnvValue "ACCESS_TOKEN" $newToken }
elseif (-not $tokenCur) {
  Set-EnvValue "ACCESS_TOKEN" "change-me"
  Write-Warn "ACCESS_TOKEN left as change-me - set a strong token in .env"
}

$tokenNow = Get-EnvValue "ACCESS_TOKEN"
if ($tokenNow -and $tokenNow -ne "change-me") {
  Set-EnvValue "BIND_HOST" "0.0.0.0"
} else {
  Write-Warn "ACCESS_TOKEN is weak - Node mode may bind 127.0.0.1 only until you set a strong token"
  Set-EnvValue "BIND_HOST" "127.0.0.1"
}
if ($UseDocker) { Set-EnvValue "BIND_HOST" "0.0.0.0" }

$cameraPasswordVal = Get-EnvValue "CAMERA_PASSWORD"

Write-Host "Starting V380 Web Camera (ports $WebPort / $DecoderHttpPort / $DecoderRtspPort; Grafana $GrafanaPort untouched)" -ForegroundColor Cyan
Write-Info "Bind 0.0.0.0 - public URL http://$PublicHost:$WebPort"

$env:PORT = "$WebPort"
$env:DECODER_HTTP_PORT = "$DecoderHttpPort"
$env:DECODER_RTSP_PORT = "$DecoderRtspPort"

if ($UseDocker) {
  if ($cameraPasswordVal) {
    Set-EnvValue "MOCK_CAMERA" "0"
    docker compose --profile real up --build -d
  } else {
    Write-Warn "No CAMERA_PASSWORD - starting web only (mock)."
    $env:MOCK_CAMERA = "1"
    Set-EnvValue "MOCK_CAMERA" "1"
    docker compose up --build -d
  }
} else {
  $pidFile = ".easy-install.pid"
  npm install --omit=dev
  if (Test-Path $pidFile) {
    $old = Get-Content $pidFile | Select-Object -First 1
    if ($old) {
      try {
        Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue
        Write-Info "Stopped previous node process pid $old"
        Start-Sleep -Seconds 1
      } catch {}
    }
  }
  Get-Content .env | ForEach-Object {
    if ($_ -match "^\s*#" -or $_ -notmatch "=") { return }
    $k,$v = $_.Split("=",2)
    [Environment]::SetEnvironmentVariable($k.Trim(), $v, "Process")
  }
  $proc = Start-Process -FilePath "npm" -ArgumentList "start" -RedirectStandardOutput "v380-web-camera.log" -RedirectStandardError "v380-web-camera.err.log" -PassThru -WindowStyle Hidden
  Set-Content -Path $pidFile -Value $proc.Id
  Write-Info "Node gateway started (pid $($proc.Id)); logs in $InstallDir"
  Write-Warn "Node mode does not auto-start V380Decoder. Publish decoder HTTP on $DecoderHttpPort."
}


Invoke-Postflight

Write-Host ""
Write-Host "Done" -ForegroundColor Green
Write-Host "  Camera UI:  http://$PublicHost:$WebPort"
Write-Host "  Health:     http://$PublicHost:$WebPort/health"
Write-Host "  Grafana:    http(s)://$PublicHost:$GrafanaPort  (unchanged)"
Write-Info "Secrets live only in $InstallDir\.env - never commit that file"
Write-Info "Anytime: powershell -File $InstallDir\scripts\safety-check.ps1"


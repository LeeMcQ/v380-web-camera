# V380 Web Camera + Grafana coexistence safety check (Windows PowerShell)
# Usage:
#   .\scripts\safety-check.ps1
#   .\scripts\safety-check.ps1 -Before
#   .\scripts\safety-check.ps1 -After
# One-shot (no clone yet):
#   irm https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/safety-check.ps1 -OutFile $env:TEMP\v380-safety-check.ps1
#   powershell -ExecutionPolicy Bypass -File $env:TEMP\v380-safety-check.ps1 -Before
# Or:  $env:SAFETY_MODE='before'; irm .../safety-check.ps1 | iex
param(
  [switch]$Before,
  [switch]$After
)

$ErrorActionPreference = "Continue"

# Support remote one-shot via env when piped through iex (params are unavailable)
if (-not $Before -and -not $After) {
  if ($env:SAFETY_MODE -eq "before") { $Before = $true }
  elseif ($env:SAFETY_MODE -eq "after") { $After = $true }
}

$PublicHost = if ($env:PUBLIC_HOST) { $env:PUBLIC_HOST } else { "41.74.144.221" }
$WebPort = if ($env:PORT) { [int]$env:PORT } else { 8090 }
$GrafanaPort = if ($env:GRAFANA_PORT) { [int]$env:GRAFANA_PORT } else { 8081 }
$DecoderHttpPort = if ($env:DECODER_HTTP_PORT) { [int]$env:DECODER_HTTP_PORT } else { 18080 }
$DecoderRtspPort = if ($env:DECODER_RTSP_PORT) { [int]$env:DECODER_RTSP_PORT } else { 18554 }
$StateDir = Join-Path $env:USERPROFILE ".v380-web-camera"
$Mode = "full"
if ($Before) { $Mode = "before" }
if ($After) { $Mode = "after" }

function Get-PortListeners([int]$Port) {
  try {
    return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
  } catch {
    # Fallback when Get-NetTCPConnection is unavailable (older Windows / no admin)
    try {
      $hits = netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING"
      if ($hits) {
        return @([pscustomobject]@{ LocalAddress = "(netstat)"; OwningProcess = "?" })
      }
    } catch {}
    return @()
  }
}

function Test-PortListening([int]$Port) {
  return [bool](Get-PortListeners $Port)
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
    if ($_.Exception.Response) {
      try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 }
    }
    return @{ Code = $code; Body = "" }
  }
}

function Test-GrafanaHealth {
  foreach ($u in @(
    "https://127.0.0.1:$GrafanaPort/api/health",
    "http://127.0.0.1:$GrafanaPort/api/health",
    "https://${PublicHost}:$GrafanaPort/api/health",
    "http://${PublicHost}:$GrafanaPort/api/health"
  )) {
    $r = Invoke-HttpProbe $u
    if ($r.Code -eq 200) { return @{ Ok = $true; Url = $u; Body = $r.Body } }
  }
  return @{ Ok = $false; Url = $null; Body = "" }
}

function Test-CameraHealth {
  foreach ($u in @(
    "http://127.0.0.1:$WebPort/health",
    "http://${PublicHost}:$WebPort/health"
  )) {
    $r = Invoke-HttpProbe $u
    if ($r.Code -eq 200) { return @{ Ok = $true; Url = $u; Body = $r.Body } }
  }
  return @{ Ok = $false; Url = $null; Body = "" }
}

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

Write-Host "Port summary (8081 Grafana / 8090 camera / 18080 decoder HTTP / 18554 RTSP)" -ForegroundColor Cyan
Write-Host "Tip: Get-NetTCPConnection -LocalPort 8081,8090,18080,18554 -State Listen"
Write-Host "     netstat -ano | findstr `":8090 :8081 :18080 :18554`""
foreach ($p in @($GrafanaPort, $WebPort, $DecoderHttpPort, $DecoderRtspPort)) {
  Write-Host ""
  Write-Host "> Port $p"
  $rows = Get-PortListeners $p
  if (-not $rows -or $rows.Count -eq 0) {
    Write-Host "  (nothing listening)"
  } else {
    $rows | ForEach-Object {
      Write-Host ("  LocalAddress={0} OwningProcess={1}" -f $_.LocalAddress, $_.OwningProcess)
    }
  }
}

Write-Host ""
Write-Host "Grafana /api/health" -ForegroundColor Cyan
$gf = Test-GrafanaHealth
if ($gf.Ok) {
  Write-Host "OK $($gf.Url)" -ForegroundColor Green
} else {
  Write-Warning "Grafana health not OK on :$GrafanaPort"
}

if ($Mode -eq "before") {
  $statePath = Join-Path $StateDir "grafana-before.state"
  if ($gf.Ok) { "up" | Set-Content $statePath } else { "down" | Set-Content $statePath }
  Write-Host ""
  Write-Host "Preflight port availability (camera stack)" -ForegroundColor Cyan
  $busy = $false
  foreach ($p in @($WebPort, $DecoderHttpPort, $DecoderRtspPort)) {
    if (Test-PortListening $p) {
      Write-Warning "Port $p is already in use"
      $busy = $true
    } else {
      Write-Host "OK Port $p is free" -ForegroundColor Green
    }
  }
  if ($WebPort -eq $GrafanaPort -or $DecoderHttpPort -eq $GrafanaPort -or $DecoderRtspPort -eq $GrafanaPort) {
    Write-Warning "Refusing Grafana port $GrafanaPort for camera stack"
    $busy = $true
  }
  Write-Host ""
  Write-Host "Expected public URLs" -ForegroundColor Cyan
  Write-Host "  Camera UI:  http://${PublicHost}:$WebPort"
  Write-Host "  Grafana:    http(s)://${PublicHost}:$GrafanaPort  (must stay on $GrafanaPort)"
  if ($busy) {
    Write-Warning "Preflight failed - free camera ports (never $GrafanaPort)"
    exit 1
  }
  Write-Host "OK Preflight safety check passed" -ForegroundColor Green
  exit 0
}

Write-Host ""
Write-Host "Camera /health (:$WebPort)" -ForegroundColor Cyan
$cam = Test-CameraHealth
if ($cam.Ok) {
  $snippet = if ($cam.Body.Length -gt 120) { $cam.Body.Substring(0, 120) } else { $cam.Body }
  Write-Host "OK $($cam.Url) $snippet" -ForegroundColor Green
} else {
  Write-Warning "Camera /health not OK on :$WebPort"
}

Write-Host ""
Write-Host "Expected public URLs" -ForegroundColor Cyan
Write-Host "  Camera UI:  http://${PublicHost}:$WebPort"
Write-Host "  Grafana:    http(s)://${PublicHost}:$GrafanaPort  (must stay on $GrafanaPort)"

if ($Mode -eq "after") {
  $statePath = Join-Path $StateDir "grafana-before.state"
  $beforeState = if (Test-Path $statePath) { (Get-Content $statePath -Raw).Trim() } else { "unknown" }
  if (-not $cam.Ok) {
    Write-Warning "Postflight failed - camera /health not OK"
    exit 1
  }
  if ($beforeState -eq "up" -and -not $gf.Ok) {
    Write-Warning "Postflight failed - Grafana was up before and is down after"
    exit 1
  }
  Write-Host "OK Postflight safety check passed" -ForegroundColor Green
  exit 0
}

if ($gf.Ok -and $cam.Ok) {
  Write-Host "OK Safety check passed" -ForegroundColor Green
  exit 0
}
Write-Warning "Safety check incomplete - see warnings above"
exit 1

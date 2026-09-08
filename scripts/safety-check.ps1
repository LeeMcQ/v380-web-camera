# V380 Web Camera + Grafana coexistence safety check
# Usage: powershell -File scripts/safety-check.ps1
$ErrorActionPreference = "Continue"

$PublicHost = if ($env:PUBLIC_HOST) { $env:PUBLIC_HOST } else { "41.74.144.221" }
$WebPort = if ($env:PORT) { [int]$env:PORT } else { 8090 }
$GrafanaPort = if ($env:GRAFANA_PORT) { [int]$env:GRAFANA_PORT } else { 8081 }
$DecoderHttpPort = if ($env:DECODER_HTTP_PORT) { [int]$env:DECODER_HTTP_PORT } else { 18080 }
$DecoderRtspPort = if ($env:DECODER_RTSP_PORT) { [int]$env:DECODER_RTSP_PORT } else { 18554 }

function Get-PortListeners([int]$Port) {
  try {
    return Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  } catch { return @() }
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

Write-Host "Port summary (8081 Grafana / 8090 camera / 18080 decoder HTTP / 18554 RTSP)" -ForegroundColor Cyan
foreach ($p in @($GrafanaPort, $WebPort, $DecoderHttpPort, $DecoderRtspPort)) {
  Write-Host ""
  Write-Host "> Port $p"
  $rows = Get-PortListeners $p
  if (-not $rows) {
    Write-Host "  (nothing listening)"
  } else {
    $rows | ForEach-Object {
      Write-Host ("  LocalAddress={0} OwningProcess={1}" -f $_.LocalAddress, $_.OwningProcess)
    }
  }
}

Write-Host ""
Write-Host "Grafana /api/health" -ForegroundColor Cyan
$gfOk = $false
foreach ($u in @(
  "https://127.0.0.1:$GrafanaPort/api/health",
  "http://127.0.0.1:$GrafanaPort/api/health",
  "https://${PublicHost}:$GrafanaPort/api/health",
  "http://${PublicHost}:$GrafanaPort/api/health"
)) {
  $r = Invoke-HttpProbe $u
  if ($r.Code -eq 200) {
    Write-Host "OK $u -> $($r.Code)" -ForegroundColor Green
    $gfOk = $true
    break
  } else {
    Write-Host "> $u -> HTTP $($r.Code)"
  }
}
if (-not $gfOk) { Write-Warning "Grafana health not OK on :$GrafanaPort" }

Write-Host ""
Write-Host "Camera /health (:$WebPort)" -ForegroundColor Cyan
$camOk = $false
foreach ($u in @(
  "http://127.0.0.1:$WebPort/health",
  "http://${PublicHost}:$WebPort/health"
)) {
  $r = Invoke-HttpProbe $u
  if ($r.Code -eq 200) {
    Write-Host "OK $u -> $($r.Code) $($r.Body.Substring(0, [Math]::Min(120, $r.Body.Length)))" -ForegroundColor Green
    $camOk = $true
    break
  } else {
    Write-Host "> $u -> HTTP $($r.Code)"
  }
}
if (-not $camOk) { Write-Warning "Camera /health not OK on :$WebPort" }

Write-Host ""
Write-Host "Expected public URLs" -ForegroundColor Cyan
Write-Host "  Camera UI:  http://${PublicHost}:$WebPort"
Write-Host "  Grafana:    http(s)://${PublicHost}:$GrafanaPort  (must stay on $GrafanaPort)"

if ($gfOk -and $camOk) {
  Write-Host "OK Safety check passed" -ForegroundColor Green
  exit 0
}
Write-Warning "Safety check incomplete - see warnings above"
exit 1

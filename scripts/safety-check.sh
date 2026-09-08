#!/usr/bin/env bash
# V380 Web Camera + Grafana coexistence safety check
# Usage: bash scripts/safety-check.sh
# Same public IP: camera :8090, Grafana :8081
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-41.74.144.221}"
WEB_PORT="${PORT:-8090}"
GRAFANA_PORT="${GRAFANA_PORT:-8081}"
DECODER_HTTP_PORT="${DECODER_HTTP_PORT:-18080}"
DECODER_RTSP_PORT="${DECODER_RTSP_PORT:-18554}"

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf "→ %s\n" "$*"; }
ok()   { printf "✔ %s\n" "$*"; }
warn() { printf "⚠ %s\n" "$*" >&2; }
bold() { printf "\033[1m%s\033[0m\n" "$*"; }

port_listeners() {
  local port="$1"
  if have ss; then
    ss -ltnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true
  elif have lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  elif have netstat; then
    netstat -ltn 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true
  else
    echo "(no ss/lsof/netstat)"
  fi
}

curl_code() {
  local url="$1"
  if have curl; then
    curl -sk --max-time 4 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000"
  else
    echo "000"
  fi
}

curl_body() {
  local url="$1"
  if have curl; then
    curl -sk --max-time 4 "$url" 2>/dev/null || true
  fi
}

bold "Port summary (8081 Grafana / 8090 camera / 18080 decoder HTTP / 18554 RTSP)"
for p in "$GRAFANA_PORT" "$WEB_PORT" "$DECODER_HTTP_PORT" "$DECODER_RTSP_PORT"; do
  echo
  info "Port $p"
  out="$(port_listeners "$p")"
  if [[ -z "${out//[[:space:]]/}" ]]; then
    echo "  (nothing listening)"
  else
    echo "$out" | sed 's/^/  /'
  fi
done

echo
bold "Grafana /api/health"
gf_ok=0
for u in \
  "https://127.0.0.1:${GRAFANA_PORT}/api/health" \
  "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
  "https://${PUBLIC_HOST}:${GRAFANA_PORT}/api/health" \
  "http://${PUBLIC_HOST}:${GRAFANA_PORT}/api/health"
do
  code="$(curl_code "$u")"
  if [[ "$code" == "200" ]]; then
    ok "$u → $code $(curl_body "$u" | tr -d '\r' | head -c 120)"
    gf_ok=1
    break
  else
    info "$u → HTTP $code"
  fi
done
[[ "$gf_ok" -eq 1 ]] || warn "Grafana health not OK on :${GRAFANA_PORT}"

echo
bold "Camera /health (:${WEB_PORT})"
cam_ok=0
for u in \
  "http://127.0.0.1:${WEB_PORT}/health" \
  "http://${PUBLIC_HOST}:${WEB_PORT}/health"
do
  code="$(curl_code "$u")"
  if [[ "$code" == "200" ]]; then
    ok "$u → $code $(curl_body "$u" | tr -d '\r' | head -c 160)"
    cam_ok=1
    break
  else
    info "$u → HTTP $code"
  fi
done
[[ "$cam_ok" -eq 1 ]] || warn "Camera /health not OK on :${WEB_PORT}"

echo
bold "Expected public URLs"
echo "  Camera UI:  http://${PUBLIC_HOST}:${WEB_PORT}"
echo "  Grafana:    http(s)://${PUBLIC_HOST}:${GRAFANA_PORT}  (must stay on ${GRAFANA_PORT})"

if [[ "$gf_ok" -eq 1 && "$cam_ok" -eq 1 ]]; then
  ok "Safety check passed"
  exit 0
fi
warn "Safety check incomplete — see warnings above"
exit 1

#!/usr/bin/env bash
# V380 Web Camera + Grafana coexistence safety check
# Usage:
#   bash scripts/safety-check.sh            # full check
#   bash scripts/safety-check.sh --before   # preflight: Grafana + ports free
#   bash scripts/safety-check.sh --after    # postflight: Grafana + camera /health
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-41.74.144.221}"
WEB_PORT="${PORT:-8090}"
GRAFANA_PORT="${GRAFANA_PORT:-8081}"
DECODER_HTTP_PORT="${DECODER_HTTP_PORT:-18080}"
DECODER_RTSP_PORT="${DECODER_RTSP_PORT:-18554}"
STATE_DIR="${HOME}/.v380-web-camera"
MODE="full"

for arg in "$@"; do
  case "$arg" in
    --before|-Before) MODE="before" ;;
    --after|-After)   MODE="after" ;;
    --help|-h)
      echo "Usage: $0 [--before|--after]"
      exit 0
      ;;
  esac
done

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

port_listening() {
  local out
  out="$(port_listeners "$1")"
  [[ -n "${out//[[:space:]]/}" && "$out" != "(no ss/lsof/netstat)" ]]
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

probe_grafana() {
  local u code
  for u in \
    "https://127.0.0.1:${GRAFANA_PORT}/api/health" \
    "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
    "https://${PUBLIC_HOST}:${GRAFANA_PORT}/api/health" \
    "http://${PUBLIC_HOST}:${GRAFANA_PORT}/api/health"
  do
    code="$(curl_code "$u")"
    if [[ "$code" == "200" ]]; then
      echo "OK|$u|$(curl_body "$u" | tr -d '\r' | head -c 120)"
      return 0
    fi
  done
  return 1
}

probe_camera() {
  local u code
  for u in \
    "http://127.0.0.1:${WEB_PORT}/health" \
    "http://${PUBLIC_HOST}:${WEB_PORT}/health"
  do
    code="$(curl_code "$u")"
    if [[ "$code" == "200" ]]; then
      echo "OK|$u|$(curl_body "$u" | tr -d '\r' | head -c 160)"
      return 0
    fi
  done
  return 1
}

show_ports() {
  bold "Port summary (8081 Grafana / 8090 camera / 18080 decoder HTTP / 18554 RTSP)"
  local p out
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
}

mkdir -p "$STATE_DIR" 2>/dev/null || true

show_ports
echo

gf_ok=0
cam_ok=0
busy=0

bold "Grafana /api/health"
if gf_line="$(probe_grafana)"; then
  ok "${gf_line#OK|}"
  gf_ok=1
else
  warn "Grafana health not OK on :${GRAFANA_PORT}"
fi

if [[ "$MODE" == "before" ]]; then
  if [[ "$gf_ok" -eq 1 ]]; then echo up >"$STATE_DIR/grafana-before.state"; else echo down >"$STATE_DIR/grafana-before.state"; fi
  echo
  bold "Preflight port availability (camera stack)"
  for p in "$WEB_PORT" "$DECODER_HTTP_PORT" "$DECODER_RTSP_PORT"; do
    if port_listening "$p"; then
      warn "Port $p is already in use"
      busy=1
    else
      ok "Port $p is free"
    fi
  done
  if [[ "$WEB_PORT" == "$GRAFANA_PORT" ]] || [[ "$DECODER_HTTP_PORT" == "$GRAFANA_PORT" ]] || [[ "$DECODER_RTSP_PORT" == "$GRAFANA_PORT" ]]; then
    warn "Refusing Grafana port ${GRAFANA_PORT} for camera stack"
    busy=1
  fi
  echo
  bold "Expected public URLs"
  echo "  Camera UI:  http://${PUBLIC_HOST}:${WEB_PORT}"
  echo "  Grafana:    http(s)://${PUBLIC_HOST}:${GRAFANA_PORT}  (must stay on ${GRAFANA_PORT})"
  if [[ "$busy" -eq 1 ]]; then
    warn "Preflight failed — free camera ports (never ${GRAFANA_PORT})"
    exit 1
  fi
  ok "Preflight safety check passed"
  exit 0
fi

echo
bold "Camera /health (:${WEB_PORT})"
if cam_line="$(probe_camera)"; then
  ok "${cam_line#OK|}"
  cam_ok=1
else
  warn "Camera /health not OK on :${WEB_PORT}"
fi

echo
bold "Expected public URLs"
echo "  Camera UI:  http://${PUBLIC_HOST}:${WEB_PORT}"
echo "  Grafana:    http(s)://${PUBLIC_HOST}:${GRAFANA_PORT}  (must stay on ${GRAFANA_PORT})"

if [[ "$MODE" == "after" ]]; then
  before_state="$(cat "$STATE_DIR/grafana-before.state" 2>/dev/null || echo unknown)"
  if [[ "$cam_ok" -ne 1 ]]; then
    warn "Postflight failed — camera /health not OK"
    exit 1
  fi
  if [[ "$before_state" == "up" && "$gf_ok" -ne 1 ]]; then
    warn "Postflight failed — Grafana was up before and is down after"
    exit 1
  fi
  ok "Postflight safety check passed"
  exit 0
fi

if [[ "$gf_ok" -eq 1 && "$cam_ok" -eq 1 ]]; then
  ok "Safety check passed"
  exit 0
fi
warn "Safety check incomplete — see warnings above"
exit 1

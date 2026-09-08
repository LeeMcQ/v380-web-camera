#!/usr/bin/env bash
# V380 Web Camera easy installer (Linux/macOS)
# curl -fsSL https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.sh | bash
# Final URL: http://41.74.144.221:8090 — Grafana stays on 8081
set -euo pipefail
REPO_URL="${REPO_URL:-https://github.com/LeeMcQ/v380-web-camera.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/v380-web-camera}"
WEB_PORT="${PORT:-8090}"
DECODER_HTTP_PORT="${DECODER_HTTP_PORT:-18080}"
DECODER_RTSP_PORT="${DECODER_RTSP_PORT:-18554}"
PUBLIC_HOST="${PUBLIC_HOST:-41.74.144.221}"
GRAFANA_PORT="${GRAFANA_PORT:-8081}"
DEVICE_ID_DEFAULT="89370567"
CAMERA_USERNAME_DEFAULT="admin"
SOURCE_DEFAULT="cloud"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "→ %s\n" "$*"; }
warn() { printf "⚠ %s\n" "$*" >&2; }
ok()   { printf "✔ %s\n" "$*"; }
die()  { printf "✖ %s\n" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

port_listening() {
  local port="$1"
  if have ss; then
    ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]" && return 0
    return 1
  fi
  if have lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    return 1
  fi
  if have netstat; then
    netstat -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]" && return 0
    return 1
  fi
  if have python3; then
    python3 -c "import socket,sys;p=int(sys.argv[1]);s=socket.socket();s.settimeout(0.4);r=s.connect_ex(('127.0.0.1',p));s.close();raise SystemExit(0 if r==0 else 1)" "$port"
    return $?
  fi
  warn "No ss/lsof/netstat/python3 — cannot verify port $port"
  return 1
}

find_next_free() {
  local start="$1" p="$1" end=$((start + 50))
  while [[ "$p" -le "$end" ]]; do
    if ! port_listening "$p"; then
      echo "$p"
      return 0
    fi
    p=$((p + 1))
  done
  return 1
}

curl_code() {
  local url="$1"
  if have curl; then
    code=$(curl -sk --max-time 4 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true); echo "${code:-000}"
  elif have wget; then
    wget --no-check-certificate -q -O /dev/null --timeout=4 "$url" >/dev/null 2>&1 && echo "200" || echo "000"
  else
    echo "000"
  fi
}

curl_body() {
  local url="$1"
  if have curl; then
    curl -sk --max-time 4 "$url" 2>/dev/null || true
  elif have wget; then
    wget --no-check-certificate -q -O - --timeout=4 "$url" 2>/dev/null || true
  fi
}

probe_grafana() {
  local urls=(
    "https://127.0.0.1:${GRAFANA_PORT}/api/health"
    "http://127.0.0.1:${GRAFANA_PORT}/api/health"
    "https://${PUBLIC_HOST}:${GRAFANA_PORT}/api/health"
    "http://${PUBLIC_HOST}:${GRAFANA_PORT}/api/health"
  )
  local u code body
  for u in "${urls[@]}"; do
    code="$(curl_code "$u")"
    if [[ "$code" == "200" ]]; then
      body="$(curl_body "$u" | tr -d '\r' | head -c 200)"
      echo "OK|$u|$body"
      return 0
    fi
  done
  echo "DOWN|none|no /api/health response on :${GRAFANA_PORT}"
  return 1
}

preflight() {
  bold "Preflight safety checks (before starting anything)"
  info "Preferred ports — web ${WEB_PORT}, decoder HTTP ${DECODER_HTTP_PORT}, RTSP ${DECODER_RTSP_PORT}"
  info "Grafana must stay on ${GRAFANA_PORT} (never reclaim it)"
  info "Same public IP ${PUBLIC_HOST}: camera :${WEB_PORT}, Grafana :${GRAFANA_PORT}"

  local busy=0
  local p sug
  for p in "$WEB_PORT" "$DECODER_HTTP_PORT" "$DECODER_RTSP_PORT"; do
    if port_listening "$p"; then
      sug="$(find_next_free "$p" || echo "?")"
      warn "Port $p is already in use"
      info "  Suggested next free near $p: $sug"
      busy=1
    else
      ok "Port $p is free"
    fi
  done

  GRAFANA_PRE=""
  if GRAFANA_PRE="$(probe_grafana)"; then
    ok "Grafana health OK — ${GRAFANA_PRE#OK|}"
  else
    warn "Grafana /api/health not reachable on :${GRAFANA_PORT} (recorded; install continues)"
    GRAFANA_PRE="DOWN|none|unreachable"
  fi
  export GRAFANA_PRE
  mkdir -p "$HOME/.v380-web-camera" 2>/dev/null || true
  if [[ "$GRAFANA_PRE" == OK* ]]; then echo up >"$HOME/.v380-web-camera/grafana-before.state"; else echo down >"$HOME/.v380-web-camera/grafana-before.state"; fi
  if [[ "$busy" -eq 1 ]]; then
    die "Aborting: preferred camera ports are busy. Free them or re-run with PORT=… DECODER_HTTP_PORT=… DECODER_RTSP_PORT=… (never ${GRAFANA_PORT})."
  fi

  if [[ "$WEB_PORT" == "$GRAFANA_PORT" ]] || [[ "$DECODER_HTTP_PORT" == "$GRAFANA_PORT" ]] || [[ "$DECODER_RTSP_PORT" == "$GRAFANA_PORT" ]]; then
    die "Refusing to use port ${GRAFANA_PORT} (reserved for Grafana)."
  fi
  ok "Preflight passed"
}

wait_camera_health() {
  local url="http://127.0.0.1:${WEB_PORT}/health"
  local i code
  for i in $(seq 1 30); do
    code="$(curl_code "$url")"
    if [[ "$code" == "200" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

postflight() {
  bold "Post-install safety checks"
  local grafana_post camera_ok=0 grafana_ok=0

  if grafana_post="$(probe_grafana)"; then
    ok "Grafana still healthy — ${grafana_post#OK|}"
    grafana_ok=1
  else
    warn "Grafana /api/health not OK after start"
  fi

  if wait_camera_health; then
    ok "Camera /health OK on :${WEB_PORT}"
    camera_ok=1
  else
    warn "Camera /health not ready on :${WEB_PORT}"
  fi

  echo
  bold "Re-run checklist (anytime)"
  echo "  1) bash scripts/safety-check.sh"
  echo "  2) ss -ltn | grep -E ':(8081|8090|18080|18554)[[:space:]]'"
  echo "  3) curl -sk https://127.0.0.1:${GRAFANA_PORT}/api/health || curl -s http://127.0.0.1:${GRAFANA_PORT}/api/health"
  echo "  4) curl -s http://127.0.0.1:${WEB_PORT}/health"
  echo "  5) Open http://${PUBLIC_HOST}:${WEB_PORT}"

  if [[ "$camera_ok" -ne 1 ]]; then
    warn "Camera health check failed"
    return 1
  fi
  if [[ "$grafana_ok" -ne 1 ]] && [[ "${GRAFANA_PRE:-}" == OK* ]]; then
    warn "Grafana was OK before but not after"
    return 1
  fi
  return 0
}

preflight

USE_DOCKER=0
if have docker && docker info >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1 || have docker-compose; then
    USE_DOCKER=1
  fi
fi

if [[ "$USE_DOCKER" -eq 0 ]]; then
  have node || die "Need Docker (preferred) or Node.js >= 18 + npm."
  have npm  || die "Need npm when Docker is unavailable."
  NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
  [[ "$NODE_MAJOR" -ge 18 ]] || die "Node.js >= 18 required (found $(node -v))."
  info "Docker not available — using Node.js $(node -v)"
else
  info "Using Docker Compose"
fi

# --- repo sync ---
SCRIPT_SRC="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SRC" && -f "$SCRIPT_SRC" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SRC")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  SCRIPT_DIR=""
  REPO_ROOT=""
fi
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/package.json" && -d "$REPO_ROOT/.git" ]]; then
  INSTALL_DIR="$REPO_ROOT"
  info "Using existing checkout at $INSTALL_DIR"
elif [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Updating existing install at $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --quiet origin main 2>/dev/null || true
  git -C "$INSTALL_DIR" pull --ff-only origin main 2>/dev/null \
    || warn "Could not fast-forward; continuing with local tree"
else
  if [[ -e "$INSTALL_DIR" ]] && [[ ! -d "$INSTALL_DIR/.git" ]]; then
    die "INSTALL_DIR exists but is not a git repo: $INSTALL_DIR"
  fi
  info "Cloning into $INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# --- .env helpers ---
env_get() {
  local key="$1" file="${2:-.env}"
  [[ -f "$file" ]] || { echo ""; return 0; }
  local line
  line="$(grep -E "^${key}=" "$file" 2>/dev/null | tail -n1 || true)"
  echo "${line#*=}"
}

env_set() {
  local key="$1" val="$2" file="${3:-.env}"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]] && grep -qE "^${key}=" "$file"; then
    sed "s|^${key}=.*|${key}=${val}|" "$file" >"$tmp"
    mv "$tmp" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
    rm -f "$tmp"
  fi
}

prompt_secret() {
  local var_name="$1" prompt_text="$2" current="$3"
  if [[ -n "${!var_name:-}" ]]; then
    echo "${!var_name}"
    return 0
  fi
  if [[ -n "$current" && "$current" != "change-me" ]]; then
    echo "$current"
    return 0
  fi
  if [[ ! -t 0 ]] && [[ ! -r /dev/tty ]]; then
    echo "$current"
    return 0
  fi
  local entered=""
  printf '%s' "$prompt_text" >&2
  if [[ -r /dev/tty ]]; then
    read -r -s entered </dev/tty || entered=""
    printf '\n' >&2
  else
    read -r -s entered || entered=""
    printf '\n' >&2
  fi
  echo "$entered"
}

if [[ ! -f .env ]]; then
  info "Creating .env from .env.example"
  cp .env.example .env
fi

env_set PORT "$WEB_PORT"
if [[ -z "$(env_get STREAM_TIMEOUT_SEC)" ]]; then
  env_set STREAM_TIMEOUT_SEC "120"
fi
env_set MOCK_CAMERA "0"
if [[ -z "$(env_get DEVICE_ID)" ]]; then
  env_set DEVICE_ID "$DEVICE_ID_DEFAULT"
fi
if [[ -z "$(env_get CAMERA_USERNAME)" ]]; then
  env_set CAMERA_USERNAME "$CAMERA_USERNAME_DEFAULT"
fi
if [[ -z "$(env_get SOURCE)" ]]; then
  env_set SOURCE "$SOURCE_DEFAULT"
fi
env_set DECODER_HTTP_PORT "$DECODER_HTTP_PORT"
env_set DECODER_RTSP_PORT "$DECODER_RTSP_PORT"

if [[ "$USE_DOCKER" -eq 1 ]]; then
  env_set DECODER_URL "http://v380decoder:8080"
else
  env_set DECODER_URL "http://127.0.0.1:${DECODER_HTTP_PORT}"
fi

CUR_PASS="$(env_get CAMERA_PASSWORD)"
CUR_TOKEN="$(env_get ACCESS_TOKEN)"

NEW_PASS="$(prompt_secret CAMERA_PASSWORD "Camera password (CAMERA_PASSWORD, blank to skip): " "$CUR_PASS")"
if [[ -n "$NEW_PASS" ]]; then
  env_set CAMERA_PASSWORD "$NEW_PASS"
elif [[ -z "$CUR_PASS" ]]; then
  warn "CAMERA_PASSWORD is empty — set it in $INSTALL_DIR/.env for a real stream"
fi

NEW_TOKEN="$(prompt_secret ACCESS_TOKEN "Web ACCESS_TOKEN [Enter to keep existing / change-me]: " "$CUR_TOKEN")"
if [[ -n "$NEW_TOKEN" ]]; then
  env_set ACCESS_TOKEN "$NEW_TOKEN"
elif [[ -z "$CUR_TOKEN" ]]; then
  env_set ACCESS_TOKEN "change-me"
  warn "ACCESS_TOKEN left as change-me — set a strong token in $INSTALL_DIR/.env"
fi

CAMERA_PASSWORD_VAL="$(env_get CAMERA_PASSWORD)"

bold "Starting V380 Web Camera (ports ${WEB_PORT} / ${DECODER_HTTP_PORT} / ${DECODER_RTSP_PORT}; Grafana ${GRAFANA_PORT} untouched)"
info "Bind 0.0.0.0 — public URL http://${PUBLIC_HOST}:${WEB_PORT}"

if [[ "$USE_DOCKER" -eq 1 ]]; then
  COMPOSE=(docker compose)
  if ! docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  fi
  export PORT="$WEB_PORT"
  export DECODER_HTTP_PORT DECODER_RTSP_PORT
  if [[ -n "$CAMERA_PASSWORD_VAL" ]]; then
    env_set MOCK_CAMERA "0"
    "${COMPOSE[@]}" --profile real up --build -d
  else
    warn "No CAMERA_PASSWORD — starting web only (mock). Re-run after setting password for profile real."
    export MOCK_CAMERA=1
    env_set MOCK_CAMERA "1"
    "${COMPOSE[@]}" up --build -d
  fi
else
  npm install --omit=dev
  if [[ -f .easy-install.pid ]]; then
    oldpid="$(cat .easy-install.pid 2>/dev/null || true)"
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null ; then
      info "Stopping previous node process pid $oldpid"
      kill "$oldpid" 2>/dev/null || true
      sleep 1
    fi
  fi
  export PORT="$WEB_PORT"
  set -a
  source .env
  set +a
  (npm start >v380-web-camera.log 2>&1) &
  echo $! >.easy-install.pid
  info "Node gateway started (pid $(cat .easy-install.pid)); logs: $INSTALL_DIR/v380-web-camera.log"
  warn "Node mode does not auto-start V380Decoder. Publish decoder HTTP on ${DECODER_HTTP_PORT}."
fi


postflight || true

echo
bold "Done"
ok "Camera UI:  http://${PUBLIC_HOST}:${WEB_PORT}"
ok "Health:     http://${PUBLIC_HOST}:${WEB_PORT}/health"
ok "Grafana:    http(s)://${PUBLIC_HOST}:${GRAFANA_PORT}  (unchanged)"
info "Secrets live only in $INSTALL_DIR/.env — never commit that file"
info "Anytime: bash $INSTALL_DIR/scripts/safety-check.sh"

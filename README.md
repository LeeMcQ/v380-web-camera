# V380 Web Camera

> **GitHub Pages is documentation only.** Live UI is on the PC:
> **http://41.74.144.221:8090** — not this Pages site.
> Grafana stays at **https://41.74.144.221:8081** (untouched).

Self-hosted web UI for a V380 IP camera: live MJPEG, PTZ / light / IR / flip, token auth.
Camera credentials stay on the server. Clients use `ACCESS_TOKEN` only.

**Repo:** https://github.com/LeeMcQ/v380-web-camera  
**Docs (Pages):** https://leemcq.github.io/v380-web-camera/

## Ports (Grafana-safe)

| Service | Port | Notes |
|---------|------|-------|
| Grafana | `8081` | Do not touch |
| Camera web UI | `8090` | Live UI + `/health` |
| Decoder HTTP | `18080` | Compose `real` profile |
| Decoder RTSP | `18554` | Compose `real` profile |


## A. Before you start (from nothing)

**What you end up with:** UI on http://41.74.144.221:8090; optional decoder 18080/18554; Grafana untouched on https://41.74.144.221:8081.

**Have ready:** device ID `89370567`, username `admin`, camera password (terminal only), a strong `ACCESS_TOKEN` you invent (terminal only).

**PC:** Linux or Windows on `41.74.144.221`, internet, a terminal.

**Software if missing:** prefer Docker + Compose (`sudo apt update && sudo apt install -y docker.io docker-compose-v2` on Ubuntu/Debian), or Git + Node.js ≥ 18. Windows: Docker Desktop or Node LTS from nodejs.org.

## Port double-check (mandatory)

Do this **before** binding and again **after** install. Confirm **8090 is free** before the camera stack binds it, and confirm **8081 is still Grafana**. Live URL **http://41.74.144.221:8090** is valid **only after** install claims that free port.

Outside probe (verified recently): **8081 OPEN** (Grafana healthy); **8090 / 18080 / 3000 / 8080 / 8554** closed/filtered — **8090 is free to claim**.

### Before install
```bash
ss -ltn | grep -E ':(8081|8090|18080|18554)' || true
curl -sk https://127.0.0.1:8081/api/health || curl -s http://127.0.0.1:8081/api/health
bash scripts/safety-check.sh --before
```
Expect something on **8081**; expect **nothing** on **8090**.

### After install
```bash
ss -ltn | grep -E ':(8081|8090|18080|18554)' || true
curl -sk https://127.0.0.1:8081/api/health || curl -s http://127.0.0.1:8081/api/health
curl -s http://127.0.0.1:8090/health
bash scripts/safety-check.sh --after
```
Expect **8081** still Grafana + **8090** camera. Then open http://41.74.144.221:8090

## Install on PC `41.74.144.221`

### Step 0 — Grafana stays on 8081
Grafana on `https://41.74.144.221:8081` / port **8081** remains unchanged.

### Step 1 — Open a terminal on 41.74.144.221
SSH or open a local terminal on the machine with IP `41.74.144.221`.

### Step 2 — Preflight safety-check (--before)
```bash
curl -fsSL https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/safety-check.sh | bash -s -- --before
```
Or after clone: `bash scripts/safety-check.sh --before`  
Windows: `.\scripts\safety-check.ps1 -Before`

### Step 3 — Easy one-line install
Linux / macOS:
```bash
curl -fsSL https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.sh | bash
```
Windows PowerShell:
```powershell
irm https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.ps1 | iex
```

### Step 4 — Terminal prompts for CAMERA_PASSWORD + ACCESS_TOKEN
Enter **CAMERA_PASSWORD** and **ACCESS_TOKEN** in the **terminal** only (stored in `~/v380-web-camera/.env`).  
**Never paste passwords into the website / Pages docs.** Never commit `.env`.

### Step 5 — Optional manual path (if one-liner fails)
```bash
git clone https://github.com/LeeMcQ/v380-web-camera.git
cd v380-web-camera
cp .env.example .env
# edit .env in the terminal only — CAMERA_PASSWORD + strong ACCESS_TOKEN
docker compose --profile real up --build -d
# Or Node: npm install && npm start (decoder must run separately on :18080)
```

### Step 6 — Firewall TCP 8090
Allow inbound **TCP 8090** only as needed. Open **18080** only if decoder HTTP must be reached off-box. Do not alter Grafana `8081`.

### Step 7 — Open live UI and log in
http://41.74.144.221:8090 — log in with `ACCESS_TOKEN`. Then run **Installation and checks** below (includes `safety-check --after`).

## Installation and checks

Full verification checklist (pass/fail). Run on the PC after install:

1. **Ports listening:** `ss -ltn | grep -E ':(8081|8090|18080|18554)'` — expect 8081 + 8090 (and 18080 if real profile). Windows: `netstat -an | findstr "8081 8090 18080 18554"`
2. **Grafana health still OK:** `curl -sk https://127.0.0.1:8081/api/health || curl -s http://127.0.0.1:8081/api/health`
3. **Camera `GET /health`:** `curl -s http://127.0.0.1:8090/health` → ok / mode real or mock
4. **Unauthenticated stream → 401:** `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/stream.mjpg`
5. **Authenticated snapshot/session** with `Authorization: Bearer YOUR_TOKEN` only (never paste real tokens into docs)
6. **Browser:** login at http://41.74.144.221:8090 — live feed, PTZ, ~120s timeout + reconnect
7. **`bash scripts/safety-check.sh --after`** must pass (non-zero if Grafana died). Windows: `.\scripts\safety-check.ps1 -After`
8. **Done when:** Grafana healthy on :8081; UI on :8090; `/health` ok; stream 401 without auth; login/feed/PTZ work; safety-check --after exits 0; no secrets in Pages

Full copy-paste guide: GitHub Pages (`index.html`).

## Troubleshooting

- **Port busy** — do not steal 8081; change `PORT` / decoder ports
- **Weak token** — empty/`change-me` binds localhost only; set a strong `ACCESS_TOKEN`
- **No video** — decoder / `CAMERA_PASSWORD` / `MOCK_CAMERA`
- **Re-run installer** — easy-install is idempotent and safe

## Features

- Mobile-friendly SPA
- Auth: prefer HttpOnly cookie / Bearer; `?token=` supported but discourage long-lived shared links
- 120s hard stream timeout + reconnect (`STREAM_TIMEOUT_SEC`)
- Mock MJPEG (`MOCK_CAMERA=1`) or real decoder (`MOCK_CAMERA=0` + `DECODER_URL`)
- Docker Compose or Node >= 18
- Weak token (`empty` / `change-me`) → loud startup warning + localhost-only bind by default

## Manual setup

```bash
git clone https://github.com/LeeMcQ/v380-web-camera.git
cd v380-web-camera
cp .env.example .env
# set ACCESS_TOKEN + CAMERA_PASSWORD locally in .env; never commit .env
bash scripts/easy-install.sh
```

Compose profile `real` publishes web **8090**, decoder HTTP **18080**, RTSP **18554**.

## Env vars

See `.env.example` for `ACCESS_TOKEN` (replace `change-me` before exposing), `PORT` (8090), `STREAM_TIMEOUT_SEC`, `MOCK_CAMERA`, `DECODER_URL` (`http://127.0.0.1:18080`), `DECODER_HTTP_PORT`, `DECODER_RTSP_PORT`, `DEVICE_ID`, `CAMERA_USERNAME`, `CAMERA_PASSWORD` (empty placeholder — set locally), `SOURCE`, optional `BIND_HOST` / `ALLOW_INSECURE_BIND` / `TRUST_PROXY`.

## API

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| `GET` | `/health` | public | Liveness |
| `GET` | `/` | public | SPA UI |
| `POST` | `/api/login` | public | Sets HttpOnly cookie from token |
| `POST` | `/api/logout` | public | Clears cookie |
| `GET` | `/api/session` | auth | Session + control list |
| `GET` | `/stream.mjpg` | auth | Timed MJPEG |
| `GET` | `/api/snapshot` | auth | JPEG frame |
| `POST` | `/api/ptz/:dir` | auth | up / down / left / right / stop |
| `POST` | `/api/control/:action/:value?` | auth | light, ir, flip |

## Smoke test

```bash
ACCESS_TOKEN=change-me node scripts/smoke-test.js
```

## Security

- Never commit `.env` / passwords / real tokens
- Prefer HttpOnly cookie or Bearer over durable `?token=` query links
- Firewall **8090** only as needed; HTTPS if public
- Strong unique `ACCESS_TOKEN`; rotate if leaked
- Empty / `change-me` token → loud warning and bind `127.0.0.1` (override with `BIND_HOST` / `ALLOW_INSECURE_BIND` only when intentional)
- Live MJPEG hard-stops after **120s**

## License

MIT

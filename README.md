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

## Install on PC `41.74.144.221`

### Step 0 — What stays as-is
Grafana on `https://41.74.144.221:8081` / port **8081** remains unchanged.

### Step 1 — Terminal on that PC
SSH or open a local terminal on the machine with IP `41.74.144.221`.

### Step 2 — Safety check (before)
```bash
git clone https://github.com/LeeMcQ/v380-web-camera.git
cd v380-web-camera
bash scripts/safety-check.sh --before
```
Windows: `.\scripts\safety-check.ps1 -Before`

### Step 3 — Easy install (copy-paste)

Linux / macOS:
```bash
curl -fsSL https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.sh | bash
```

Windows PowerShell:
```powershell
irm https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.ps1 | iex
```

Or from a clone: `bash scripts/easy-install.sh` / `.\scripts\easy-install.ps1`

### Step 4 — Prompts
Enter **CAMERA_PASSWORD** and **ACCESS_TOKEN** when asked (stored only in `~/v380-web-camera/.env`).

### Step 5 — Open live UI
http://41.74.144.221:8090 — log in with `ACCESS_TOKEN`.

### Step 6 — Safety check (after)
```bash
bash scripts/safety-check.sh --after
curl -s http://127.0.0.1:8090/health
curl -sk https://127.0.0.1:8081/api/health || curl -s http://127.0.0.1:8081/api/health
```
Exits non-zero if Grafana was up before and is down after.

### Step 7 — Firewall
Allow inbound **TCP 8090**. Open **18080** only if decoder HTTP must be reached off-box. Do not alter Grafana `8081`.

## Features

- Mobile-friendly SPA
- Auth: Bearer, `?token=`, cookie
- 120s hard stream timeout + reconnect (`STREAM_TIMEOUT_SEC`)
- Mock MJPEG (`MOCK_CAMERA=1`) or real decoder (`MOCK_CAMERA=0` + `DECODER_URL`)
- Docker Compose or Node >= 18

## Manual setup

```bash
git clone https://github.com/LeeMcQ/v380-web-camera.git
cd v380-web-camera
cp .env.example .env
# set ACCESS_TOKEN + CAMERA_PASSWORD; never commit .env
bash scripts/easy-install.sh
```

Compose profile `real` publishes web **8090**, decoder HTTP **18080**, RTSP **18554**.
Prefer `scripts/easy-install.sh` / `.ps1` so Grafana **8081** is never claimed.

## Env vars

See `.env.example` for `ACCESS_TOKEN`, `PORT` (8090), `STREAM_TIMEOUT_SEC`, `MOCK_CAMERA`, `DECODER_URL`, `DECODER_HTTP_PORT`, `DECODER_RTSP_PORT`, `DEVICE_ID`, `CAMERA_USERNAME`, `CAMERA_PASSWORD`, `SOURCE`.

## API

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| `GET` | `/health` | public | Liveness |
| `GET` | `/` | public | SPA UI |
| `POST` | `/api/login` | public | Sets cookie from token |
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
- Prefer cookie/Bearer over durable query tokens
- Expose only on a trusted network or behind HTTPS / reverse proxy

## License

MIT

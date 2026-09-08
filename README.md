# V380 Web Camera

> **GitHub Pages is documentation only.** This site / Pages deploy is **not** the live camera.
> Install on your PC, then open `http://YOUR-PC:8090`.

Self-hosted web UI for a V380 IP camera: live MJPEG, PTZ / light / IR / flip, token auth.
Camera credentials stay on the server. Clients use `ACCESS_TOKEN` only.

**Repo:** https://github.com/LeeMcQ/v380-web-camera

**Default ports** (avoid Grafana on **8081** and common 8080/8554):
- Web UI: **8090**
- V380Decoder HTTP: **18080**
- V380Decoder RTSP: **18554**

## Easy install

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.sh | bash
```

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/LeeMcQ/v380-web-camera/main/scripts/easy-install.ps1 | iex
```

The installer clones/updates to `~/v380-web-camera` (or `$INSTALL_DIR`), creates `.env` from the example, prompts for `CAMERA_PASSWORD` / `ACCESS_TOKEN` if needed, and starts Docker Compose (preferred) or Node. Safe to re-run.

## Same IP as Grafana (do not clash)

On public IP **41.74.144.221**:

| Service | Port |
|---------|------|
| **Grafana** (existing) | **8081** — leave alone |
| V380 Web Camera UI | **8090** |
| V380Decoder HTTP | **18080** |
| V380Decoder RTSP | **18554** |

**Final URL:** http://41.74.144.221:8090

### Safety check (anytime)

```bash
bash scripts/safety-check.sh
```

```powershell
powershell -File scripts/safety-check.ps1
```

Manual checklist:

```bash
ss -ltn | grep -E ':(8081|8090|18080|18554)[[:space:]]'
curl -sk https://127.0.0.1:8081/api/health || curl -s http://127.0.0.1:8081/api/health
curl -s http://127.0.0.1:8090/health
```

The easy installer runs preflight (ports free + Grafana health) before start and postflight (Grafana still OK + camera /health) after start.


After install open `http://YOUR-PC:8090` (or `http://127.0.0.1:8090`). Live MJPEG hard-stops after 120s; the UI reconnects.

## Features

- Mobile-friendly SPA
- Auth: Bearer, `?token=`, cookie
- 120s hard stream timeout + reconnect (`STREAM_TIMEOUT_SEC`)
- Mock MJPEG (`MOCK_CAMERA=1`)
- Real decoder proxy path (`MOCK_CAMERA=0` + `DECODER_URL`)

## Manual setup

1. **Clone**
   ```bash
   git clone https://github.com/LeeMcQ/v380-web-camera.git
   cd v380-web-camera
   ```
2. **Copy env template**
   ```bash
   cp .env.example .env
   ```
3. **Edit secrets** — set a strong `ACCESS_TOKEN`. For a real camera, set `CAMERA_PASSWORD`, `DEVICE_ID`, and related fields. **Never commit `.env`.**
4. **Install and start**
   ```bash
   npm install && PORT=8090 npm start
   ```
   Open `http://YOUR-HOST:8090`.
5. **Real camera** — run [V380Decoder](https://github.com/PyanSofyan/V380Decoder), set `MOCK_CAMERA=0` and `DECODER_URL` (e.g. `http://127.0.0.1:18080`).

### Docker

Mock (no camera / decoder):

```bash
MOCK_CAMERA=1 ACCESS_TOKEN=change-me docker compose up --build
```

Real camera (compose profile `real` — publishes decoder on 18080 / 18554):

```bash
MOCK_CAMERA=0 CAMERA_PASSWORD=... docker compose --profile real up --build
```

## Env vars

See `.env.example` for `ACCESS_TOKEN`, `PORT` (default 8090), `STREAM_TIMEOUT_SEC`, `MOCK_CAMERA`, `DECODER_URL`, `DEVICE_ID`, `CAMERA_USERNAME` (default `admin`), `CAMERA_PASSWORD`, `SOURCE`, optional `DECODER_HTTP_PORT` / `DECODER_RTSP_PORT`.

Never commit `.env`.

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
| `POST` | `/api/ptz/:dir` | auth | `up` | `down` | `left` | `right` | `stop` |
| `POST` | `/api/control/:action/:value?` | auth | light, ir, flip, … |

Unauthenticated stream/control => `401`.

## Smoke test

With server running:

```bash
ACCESS_TOKEN=change-me node scripts/smoke-test.js
```

## Security

- Do not commit passwords or real tokens (`.env` is gitignored)
- Prefer cookie/Bearer over durable query tokens
- Expose only on a trusted network or behind HTTPS / reverse proxy
- Short live sessions reduce exposure

## License

MIT

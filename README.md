# V380 Web Camera

> **GitHub Pages is documentation only.** This site / Pages deploy is **not** the live camera.
> The interactive UI needs Node.js (and V380Decoder for a real camera) on a host you control,
> typically at `http://YOUR-HOST:3000`.

Self-hosted web UI for a V380 IP camera: live MJPEG, PTZ / light / IR / flip, token auth.
Camera credentials stay on the server. Clients use `ACCESS_TOKEN` only.

**Repo:** https://github.com/LeeMcQ/v380-web-camera

## Features

- Mobile-friendly SPA
- Auth: Bearer, `?token=`, cookie
- 120s hard stream timeout + reconnect (`STREAM_TIMEOUT_SEC`)
- Mock MJPEG (`MOCK_CAMERA=1`)
- Real decoder proxy path (`MOCK_CAMERA=0` + `DECODER_URL`)

## Setup

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
   npm install && npm start
   ```
   Open `http://YOUR-HOST:3000` (default port 3000).
5. **Real camera** — run [V380Decoder](https://github.com/PyanSofyan/V380Decoder), set `MOCK_CAMERA=0` and `DECODER_URL` (e.g. `http://127.0.0.1:8080`).

### Docker

Mock (no camera / decoder):

```bash
MOCK_CAMERA=1 ACCESS_TOKEN=change-me docker compose up --build
```

Real camera (compose profile `real`):

```bash
MOCK_CAMERA=0 CAMERA_PASSWORD=... docker compose --profile real up --build
```

## Env vars

See `.env.example` for `ACCESS_TOKEN`, `PORT`, `STREAM_TIMEOUT_SEC`, `MOCK_CAMERA`, `DECODER_URL`, `DEVICE_ID`, `CAMERA_USERNAME` (default `admin`), `CAMERA_PASSWORD`, `SOURCE`.

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

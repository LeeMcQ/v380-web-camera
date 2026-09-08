# V380 Web Camera

Self-hosted web UI for a V380 IP camera: live MJPEG, PTZ/light/IR/flip, token auth.
Camera credentials stay on the server. Clients use ACCESS_TOKEN only.

## Features

- Mobile-friendly SPA
- Auth: Bearer, ?token=, cookie
- 120s hard stream timeout + reconnect
- Mock MJPEG (MOCK_CAMERA=1)
- Real decoder proxy path

## Quick start

1. Copy .env.example to .env
2. Install Node deps
3. Start with: node src/server.js
4. Open http://localhost:3000

Container demo: use project compose with MOCK_CAMERA=1.

## Env vars

See .env.example for ACCESS_TOKEN, PORT, STREAM_TIMEOUT_SEC, MOCK_CAMERA, DECODER_URL, DEVICE_ID=89370567, CAMERA_USERNAME=5Hw51JLd27, CAMERA_PASSWORD, SOURCE=cloud.
Never commit .env.

## API

- GET /health (public)
- GET / (UI)
- POST /api/login, POST /api/logout
- GET /api/session (auth)
- GET /stream.mjpg (auth, timed)
- GET /api/snapshot (auth)
- POST /api/ptz/:dir (up|down|left|right|stop)
- POST /api/control/light|ir|flip...

Unauthenticated stream/control => 401.

## Real camera

Set MOCK_CAMERA=0 and CAMERA_PASSWORD. Enable compose profile real to run PyanSofyan/V380Decoder. Gateway proxies MJPEG+PTZ and still enforces 120s timeout.

## Smoke test

With server running: ACCESS_TOKEN=change-me node scripts/smoke-test.js

## GitHub

Target: https://github.com/LeeMcQ/v380-web-camera

Tree is ready for parent to commit and push. On a host: clone, copy env example, set secrets, start the compose stack.

## Security

- Do not commit passwords or real tokens
- Prefer cookie/Bearer over durable query tokens
- Short live sessions reduce exposure

## License

MIT

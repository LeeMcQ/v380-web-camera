'use strict';

const path = require('path');
const express = require('express');
const cookieParser = require('cookie-parser');
const config = require('./config');
const { requireAuth } = require('./auth');
const mock = require('./mockMjpeg');
const decoder = require('./decoderClient');

const app = express();
if (config.trustProxy) app.set('trust proxy', 1);

app.use(cookieParser());
app.use(express.json({ limit: '32kb' }));

// Public health (no auth) — useful for compose / k8s probes
app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    mode: config.useRealCamera ? 'real' : 'mock',
    mockCamera: config.mockCamera,
    streamTimeoutSec: config.streamTimeoutSec,
    deviceId: config.deviceId ? String(config.deviceId).replace(/.(?=.{4})/g, '*') : null,
    decoderUrl: config.useRealCamera ? config.decoderUrl : null,
  });
});

// Login helper: set cookie then redirect home (token never stored in JS if using cookie)
app.post('/api/login', express.urlencoded({ extended: false }), (req, res) => {
  const token =
    (req.body && req.body.token) ||
    (req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim() ||
    (req.query && req.query.token) ||
    '';
  if (!config.accessToken || token !== config.accessToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  res.cookie('access_token', token, {
    httpOnly: true,
    sameSite: 'lax',
    secure: req.secure || false,
    maxAge: 30 * 24 * 60 * 60 * 1000,
  });
  if (req.accepts('html') && !req.xhr) {
    return res.redirect('/');
  }
  return res.json({ ok: true });
});

app.post('/api/logout', (_req, res) => {
  res.clearCookie('access_token');
  res.json({ ok: true });
});

app.get('/api/session', requireAuth, (_req, res) => {
  res.json({
    ok: true,
    mode: config.useRealCamera ? 'real' : 'mock',
    streamTimeoutSec: config.streamTimeoutSec,
    controls: {
      ptz: ['up', 'down', 'left', 'right', 'stop'],
      light: true,
      ir: true,
      flip: true,
    },
  });
});

const timeoutMs = () => config.streamTimeoutSec * 1000;

app.get('/stream.mjpg', requireAuth, (req, res) => {
  if (config.useRealCamera) {
    return decoder.proxyMjpeg(res, { timeoutMs: timeoutMs() });
  }
  return mock.streamMjpeg(res, { timeoutMs: timeoutMs() });
});

app.get('/api/snapshot', requireAuth, async (_req, res) => {
  try {
    if (config.useRealCamera) {
      const r = await decoder.snapshot();
      if (r.status >= 400) {
        return res.status(502).json({ error: 'Snapshot failed', status: r.status });
      }
      res.set('Content-Type', r.headers['content-type'] || 'image/jpeg');
      res.set('Cache-Control', 'no-store');
      return res.send(r.body);
    }
    const buf = mock.snapshot();
    res.set('Content-Type', 'image/jpeg');
    res.set('Cache-Control', 'no-store');
    return res.send(buf);
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }
});

const PTZ_DIRS = new Set(['up', 'down', 'left', 'right', 'stop']);

app.post('/api/ptz/:dir', requireAuth, async (req, res) => {
  const dir = String(req.params.dir || '').toLowerCase();
  if (!PTZ_DIRS.has(dir)) {
    return res.status(400).json({ error: 'Invalid PTZ direction' });
  }

  if (!config.useRealCamera) {
    return res.json({ ok: true, mock: true, action: 'ptz', dir });
  }

  try {
    const r = await decoder.ptz(dir);
    return res.status(r.status >= 400 ? 502 : 200).json({
      ok: r.status < 400,
      status: r.status,
      body: r.body.toString('utf8').slice(0, 500),
    });
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }
});

app.post('/api/control/:action/:value?', requireAuth, async (req, res) => {
  const action = String(req.params.action || '').toLowerCase();
  const value = req.params.value ? String(req.params.value).toLowerCase() : '';
  const allowed = new Set(['light', 'ir', 'image', 'flip']);
  if (!allowed.has(action) && action !== 'flip') {
    return res.status(400).json({ error: 'Invalid control action' });
  }

  const normalized =
    action === 'flip' ? { action: 'image', value: 'flip' } : { action, value };

  if (!config.useRealCamera) {
    return res.json({
      ok: true,
      mock: true,
      action: normalized.action,
      value: normalized.value || null,
    });
  }

  try {
    const r = await decoder.control(normalized.action, normalized.value);
    return res.status(r.status >= 400 ? 502 : 200).json({
      ok: r.status < 400,
      status: r.status,
      body: r.body.toString('utf8').slice(0, 500),
    });
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }
});

// Static UI
app.use(express.static(path.join(__dirname, '..', 'public'), {
  etag: true,
  maxAge: 0,
}));

app.get('/', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

if (config.weakToken) {
  const reason = !config.accessToken
    ? 'ACCESS_TOKEN is empty'
    : 'ACCESS_TOKEN is still the default "change-me"';
  console.error('');
  console.error('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  console.error(`!!! SECURITY: ${reason}`);
  console.error('!!! Set a strong unique ACCESS_TOKEN in .env before exposing');
  console.error('!!! this UI. Prefer HttpOnly cookie (POST /api/login) or');
  console.error('!!! Authorization: Bearer — avoid long-lived ?token= links.');
  if (!config.accessToken) {
    console.error('!!! Authenticated routes will return 500 until a token is set.');
  }
  if (config.bindHost === '127.0.0.1') {
    console.error('!!! Refusing non-localhost bind; listening on 127.0.0.1 only.');
    console.error('!!! To override (not recommended): BIND_HOST=0.0.0.0 or');
    console.error('!!! ALLOW_INSECURE_BIND=1 after setting a real ACCESS_TOKEN.');
  }
  console.error('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  console.error('');
}

app.listen(config.port, config.bindHost, () => {
  console.log(
    `v380-web-camera listening on ${config.bindHost}:${config.port} mode=${
      config.useRealCamera ? 'real' : 'mock'
    } timeout=${config.streamTimeoutSec}s`
  );
});

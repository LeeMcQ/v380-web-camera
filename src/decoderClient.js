'use strict';

const http = require('http');
const https = require('https');
const { URL } = require('url');
const config = require('./config');

function request(method, path, { timeoutMs = 8000, body } = {}) {
  const target = new URL(path, config.decoderUrl);
  const lib = target.protocol === 'https:' ? https : http;
  const payload = body ? Buffer.from(JSON.stringify(body)) : null;

  return new Promise((resolve, reject) => {
    const req = lib.request(
      {
        protocol: target.protocol,
        hostname: target.hostname,
        port: target.port,
        path: target.pathname + target.search,
        method,
        headers: {
          Accept: '*/*',
          ...(payload
            ? {
                'Content-Type': 'application/json',
                'Content-Length': payload.length,
              }
            : {}),
        },
        timeout: timeoutMs,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks),
          });
        });
      }
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy(new Error('decoder request timeout'));
    });
    if (payload) req.write(payload);
    req.end();
  });
}

async function ptz(dir) {
  // V380Decoder: POST /api/ptz/{up|down|left|right|stop}
  return request('POST', `/api/ptz/${encodeURIComponent(dir)}`);
}

async function control(action, value) {
  // Common decoder paths: /api/light/{on|off|auto}, /api/image/{flip|...}
  const map = {
    'light/on': '/api/light/on',
    'light/off': '/api/light/off',
    'light/auto': '/api/light/auto',
    'ir/on': '/api/ir/on',
    'ir/off': '/api/ir/off',
    'image/flip': '/api/image/flip',
    'image/color': '/api/image/color',
    'image/bw': '/api/image/bw',
    'image/auto': '/api/image/auto',
  };
  const key = value ? `${action}/${value}` : action;
  const path = map[key] || `/api/${key}`;
  return request('POST', path);
}

async function snapshot() {
  // Prefer /snapshot, fall back to /api/snapshot
  try {
    const r = await request('GET', '/snapshot');
    if (r.status >= 200 && r.status < 300 && r.body.length > 100) return r;
  } catch (_) {
    /* fall through */
  }
  return request('GET', '/api/snapshot');
}

/**
 * Proxy an upstream MJPEG stream to the client, enforcing a hard timeout.
 */
function proxyMjpeg(clientRes, { timeoutMs }) {
  // V380Decoder serves MJPEG at /mjpeg (not /stream.mjpg)
  const target = new URL('/mjpeg', config.decoderUrl);
  const lib = target.protocol === 'https:' ? https : http;

  const upstream = lib.get(
    {
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port,
      path: target.pathname,
      headers: { Accept: '*/*', Connection: 'close' },
    },
    (up) => {
      if (up.statusCode && up.statusCode >= 400) {
        if (!clientRes.headersSent) {
          clientRes.status(502).json({
            error: 'Decoder stream unavailable',
            status: up.statusCode,
          });
        }
        up.resume();
        return;
      }

      const headers = {
        'Content-Type':
          up.headers['content-type'] ||
          'multipart/x-mixed-replace; boundary=frame',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        Pragma: 'no-cache',
        Connection: 'close',
        'X-Stream-Timeout-Sec': String(Math.round(timeoutMs / 1000)),
      };
      clientRes.writeHead(200, headers);

      let closed = false;
      const finish = () => {
        if (closed) return;
        closed = true;
        clearTimeout(timer);
        upstream.destroy();
        up.destroy();
        try {
          clientRes.end();
        } catch (_) {
          /* ignore */
        }
      };

      const timer = setTimeout(finish, timeoutMs);
      clientRes.on('close', finish);
      up.on('error', finish);
      up.pipe(clientRes);
    }
  );

  upstream.on('error', (err) => {
    if (!clientRes.headersSent) {
      clientRes.status(502).json({
        error: 'Failed to connect to V380 decoder',
        detail: err.message,
      });
    } else {
      try {
        clientRes.end();
      } catch (_) {
        /* ignore */
      }
    }
  });
}

module.exports = { ptz, control, snapshot, proxyMjpeg, request };

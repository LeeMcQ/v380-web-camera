'use strict';

const jpeg = require('jpeg-js');

const WIDTH = 640;
const HEIGHT = 360;

function makeFrame(frameIndex) {
  const data = Buffer.alloc(WIDTH * HEIGHT * 4);
  const t = frameIndex / 8;

  for (let y = 0; y < HEIGHT; y++) {
    for (let x = 0; x < WIDTH; x++) {
      const i = (y * WIDTH + x) * 4;
      const gx = x / WIDTH;
      const gy = y / HEIGHT;
      const bar = Math.abs(((x + frameIndex * 5) % WIDTH) - WIDTH / 2) < 10;
      const grid = x % 40 === 0 || y % 40 === 0;

      let r = Math.floor(30 + 200 * gx);
      let g = Math.floor(30 + 160 * gy);
      let b = Math.floor(60 + 120 * (0.5 + 0.5 * Math.sin(t + gx * 6)));

      if (y < 36) {
        r = 16;
        g = 22;
        b = 36;
      }
      if (bar) {
        r = 255;
        g = 196;
        b = 48;
      }
      if (grid && y >= 36) {
        r = Math.min(255, r + 35);
        g = Math.min(255, g + 35);
        b = Math.min(255, b + 35);
      }

      // Simple 5x7-ish “MOCK” dots in the header band
      if (y >= 8 && y < 28) {
        const cx = Math.floor((x - 20) / 6);
        const cy = Math.floor((y - 8) / 3);
        // decorative pulse
        if (cx >= 0 && cx < 80 && (cx + cy + frameIndex) % 17 === 0) {
          r = 80;
          g = 180;
          b = 255;
        }
      }

      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
      data[i + 3] = 255;
    }
  }

  return jpeg.encode({ data, width: WIDTH, height: HEIGHT }, 70).data;
}

/**
 * Stream multipart MJPEG until timeoutMs elapses or the client disconnects.
 */
function streamMjpeg(res, { timeoutMs, fps = 8 }) {
  const boundary = 'v380frame';
  res.writeHead(200, {
    'Content-Type': `multipart/x-mixed-replace; boundary=${boundary}`,
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    Pragma: 'no-cache',
    Connection: 'close',
    'X-Stream-Timeout-Sec': String(Math.round(timeoutMs / 1000)),
  });

  let frame = 0;
  let closed = false;
  const started = Date.now();

  const finish = (reason) => {
    if (closed) return;
    closed = true;
    clearTimeout(hardTimer);
    clearInterval(interval);
    try {
      if (reason === 'timeout') {
        res.write(
          `\r\n--${boundary}\r\nContent-Type: text/plain\r\n\r\nSTREAM_TIMEOUT\r\n`
        );
      }
      res.end();
    } catch (_) {
      /* ignore */
    }
  };

  const hardTimer = setTimeout(() => finish('timeout'), timeoutMs);
  res.on('close', () => finish('client'));

  const writeFrame = () => {
    if (closed) return;
    if (Date.now() - started >= timeoutMs) {
      finish('timeout');
      return;
    }
    try {
      const buf = makeFrame(frame++);
      res.write(
        `--${boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: ${buf.length}\r\n\r\n`
      );
      res.write(buf);
      res.write('\r\n');
    } catch (_) {
      finish('error');
    }
  };

  writeFrame();
  const interval = setInterval(writeFrame, Math.round(1000 / fps));
}

function snapshot() {
  return makeFrame(0);
}

module.exports = { streamMjpeg, snapshot, makeFrame };

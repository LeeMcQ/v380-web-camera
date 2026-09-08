'use strict';

function bool(v, fallback = false) {
  if (v === undefined || v === null || v === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase());
}

const config = {
  port: Number(process.env.PORT || 8090),
  accessToken: process.env.ACCESS_TOKEN || '',
  streamTimeoutSec: Number(process.env.STREAM_TIMEOUT_SEC || 120),
  mockCamera: bool(process.env.MOCK_CAMERA, true),
  decoderUrl: (process.env.DECODER_URL || 'http://v380decoder:8080').replace(/\/$/, ''),
  deviceId: process.env.DEVICE_ID || '',
  cameraUsername: process.env.CAMERA_USERNAME || '',
  cameraPassword: process.env.CAMERA_PASSWORD || '',
  source: process.env.SOURCE || 'cloud',
  cameraIp: process.env.CAMERA_IP || '',
  cameraPort: process.env.CAMERA_PORT || '8800',
  trustProxy: bool(process.env.TRUST_PROXY, false),
};

/** Real mode when not mocking and a camera password is present. */
config.useRealCamera = !config.mockCamera && Boolean(config.cameraPassword);

module.exports = config;

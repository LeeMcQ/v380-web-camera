'use strict';

const config = require('./config');

/**
 * Accept ACCESS_TOKEN via:
 *  - Authorization: Bearer <token>
 *  - ?token=<token> (useful for <img src="/stream.mjpg?token=...">)
 *  - Cookie: access_token=<token>
 */
function extractToken(req) {
  const auth = req.headers.authorization || '';
  if (auth.toLowerCase().startsWith('bearer ')) {
    return auth.slice(7).trim();
  }
  if (req.query && typeof req.query.token === 'string' && req.query.token) {
    return req.query.token;
  }
  if (req.cookies && req.cookies.access_token) {
    return req.cookies.access_token;
  }
  return null;
}

function requireAuth(req, res, next) {
  if (!config.accessToken) {
    return res.status(500).json({
      error: 'ACCESS_TOKEN is not configured on the server',
    });
  }
  const token = extractToken(req);
  if (!token || token !== config.accessToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  return next();
}

module.exports = { requireAuth, extractToken };

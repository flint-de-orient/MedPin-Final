const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const env = require('../config/env');

const hmac = (value) => crypto.createHmac('sha256', env.otpHashSecret).update(String(value)).digest('hex');
const sha256 = (value) => crypto.createHash('sha256').update(String(value)).digest('hex');
const randomDigits = (n) => Array.from({ length: n }, () => crypto.randomInt(0, 10)).join('');
const randomToken = (bytes = 48) => crypto.randomBytes(bytes).toString('base64url');
const safeEqual = (a, b) => {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

const signAccess = (user) =>
  jwt.sign({ sub: String(user._id), typ: 'access' }, env.jwt.accessSecret, { expiresIn: env.jwt.accessTtl });

const verifyAccess = (token) => {
  const payload = jwt.verify(token, env.jwt.accessSecret);
  if (payload.typ !== 'access') throw new Error('wrong token type');
  return payload;
};

/** "15m" / "30d" / "12h" → milliseconds. */
const ttlMs = (ttl) => {
  const m = /^(\d+)([smhd])$/.exec(String(ttl));
  if (!m) return Number(ttl) * 1000;
  return Number(m[1]) * { s: 1e3, m: 6e4, h: 36e5, d: 864e5 }[m[2]];
};

module.exports = { hmac, sha256, randomDigits, randomToken, safeEqual, signAccess, verifyAccess, ttlMs };

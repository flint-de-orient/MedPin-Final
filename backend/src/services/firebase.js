// Verifies Firebase Authentication ID tokens (phone sign-in) without a service
// account: RS256 signature against Google's public certificates, plus the
// audience / issuer checks Firebase documents.
const jwt = require('jsonwebtoken');
const env = require('../config/env');

const CERTS_URL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
let certs = { keys: null, exp: 0 };

async function publicCerts() {
  if (certs.keys && certs.exp > Date.now()) return certs.keys;
  const res = await fetch(CERTS_URL);
  if (!res.ok) throw new Error(`Firebase certificates: ${res.status}`);
  const maxAge = Number(/max-age=(\d+)/.exec(res.headers.get('cache-control') || '')?.[1] || 3600);
  certs = { keys: await res.json(), exp: Date.now() + maxAge * 1000 };
  return certs.keys;
}

/** Returns the verified token payload (with `phone_number`), or throws. */
async function verifyIdToken(idToken) {
  const projectId = env.firebase.projectId;
  if (!projectId) throw new Error('FIREBASE_PROJECT_ID is not set');
  const decoded = jwt.decode(idToken, { complete: true });
  if (!decoded?.header?.kid) throw new Error('Not a Firebase ID token');
  const cert = (await publicCerts())[decoded.header.kid];
  if (!cert) throw new Error('Unknown signing key');
  const payload = jwt.verify(idToken, cert, {
    algorithms: ['RS256'],
    audience: projectId,
    issuer: `https://securetoken.google.com/${projectId}`,
  });
  if (!payload.sub) throw new Error('Token has no subject');
  if (payload.auth_time && payload.auth_time * 1000 > Date.now() + 60_000) throw new Error('Token auth_time is in the future');
  return payload;
}

module.exports = { verifyIdToken };

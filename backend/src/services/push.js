// Push (FCM HTTP v1) and WhatsApp (Meta Cloud API). Both only log when unset.
const jwt = require('jsonwebtoken');
const env = require('../config/env');

let fcmToken = { value: null, exp: 0 };
async function fcmAccessToken() {
  if (fcmToken.value && fcmToken.exp > Date.now() + 60000) return fcmToken.value;
  const now = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign(
    {
      iss: env.fcm.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    env.fcm.privateKey,
    { algorithm: 'RS256' },
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`FCM auth: ${body.error_description || res.status}`);
  fcmToken = { value: body.access_token, exp: Date.now() + body.expires_in * 1000 };
  return fcmToken.value;
}

async function sendPush(tokens, { title, body, data }) {
  if (!tokens.length) return;
  if (!env.fcm.projectId || !env.fcm.privateKey) {
    console.log(`[push:dev] ${tokens.length} device(s): ${title}`);
    return;
  }
  const access = await fcmAccessToken();
  await Promise.allSettled(
    tokens.map((token) =>
      fetch(`https://fcm.googleapis.com/v1/projects/${env.fcm.projectId}/messages:send`, {
        method: 'POST',
        headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
        body: JSON.stringify({ message: { token, notification: { title, body }, data: data || {} } }),
      }),
    ),
  );
}

async function sendWhatsApp(phone, text) {
  if (!env.whatsapp.accessToken || !env.whatsapp.phoneNumberId) {
    console.log(`[whatsapp:dev] +91 ${phone}: ${text}`);
    return;
  }
  const res = await fetch(`https://graph.facebook.com/v21.0/${env.whatsapp.phoneNumberId}/messages`, {
    method: 'POST',
    headers: { authorization: `Bearer ${env.whatsapp.accessToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to: `91${phone}`, type: 'text', text: { body: text } }),
  });
  if (!res.ok) console.warn(`[whatsapp] send failed: ${res.status}`);
}

module.exports = { sendPush, sendWhatsApp };

// Email via SMTP. Without SMTP_HOST the message is only logged (dev).
const env = require('../config/env');

let transport;
async function sendEmail({ to, subject, text, attachments }) {
  if (!to) return { skipped: true };
  if (!env.smtp.host) {
    console.log(`[email:dev] to=${to} subject="${subject}" attachments=${(attachments || []).length}`);
    return { provider: 'dev' };
  }
  const make = () => require('nodemailer').createTransport({
    host: env.smtp.host,
    port: env.smtp.port,
    secure: env.smtp.port === 465,
    // Gmail app passwords are shown with spaces; the login needs them without.
    auth: env.smtp.user ? { user: env.smtp.user, pass: String(env.smtp.pass || '').replace(/\s+/g, '') } : undefined,
    connectionTimeout: 8000,
    greetingTimeout: 8000,
    socketTimeout: 12000,
  });
  const mail = { from: env.smtp.from || env.smtp.user, to, subject, text, attachments };
  // At most ~18 s in all, so the app (which waits 25 s) always gets an answer.
  const within = (p, ms) => Promise.race([p, new Promise((_, no) => setTimeout(() => no(Object.assign(new Error('Email took too long'), { code: 'ETIMEDOUT' })), ms))]);
  const started = Date.now();
  transport = transport || make();
  try {
    await within(transport.sendMail(mail), 12000);
  } catch (err) {
    // A dropped / stale connection: once more on a new one, in the time left.
    console.warn('[email] retrying after:', err.code || '', err.responseCode || '', err.message);
    transport = make();
    const left = 18000 - (Date.now() - started);
    if (left < 3000) throw err;
    await within(transport.sendMail(mail), left);
  }
  return { provider: 'smtp' };
}

module.exports = { sendEmail };

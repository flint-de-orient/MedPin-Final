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
    connectionTimeout: 15000,
    greetingTimeout: 15000,
  });
  const mail = { from: env.smtp.from || env.smtp.user, to, subject, text, attachments };
  transport = transport || make();
  try {
    await transport.sendMail(mail);
  } catch (err) {
    // A dropped / stale connection: once more on a new one.
    console.warn('[email] retrying after:', err.code || '', err.responseCode || '', err.message);
    transport = make();
    await transport.sendMail(mail);
  }
  return { provider: 'smtp' };
}

module.exports = { sendEmail };

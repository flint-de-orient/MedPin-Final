// Email via SMTP. Without SMTP_HOST the message is only logged (dev).
const env = require('../config/env');

let transport;
async function sendEmail({ to, subject, text, attachments }) {
  if (!to) return { skipped: true };
  if (!env.smtp.host) {
    console.log(`[email:dev] to=${to} subject="${subject}" attachments=${(attachments || []).length}`);
    return { provider: 'dev' };
  }
  if (!transport) {
    const nodemailer = require('nodemailer');
    transport = nodemailer.createTransport({
      host: env.smtp.host,
      port: env.smtp.port,
      secure: env.smtp.port === 465,
      auth: env.smtp.user ? { user: env.smtp.user, pass: env.smtp.pass } : undefined,
    });
  }
  await transport.sendMail({ from: env.smtp.from, to, subject, text, attachments });
  return { provider: 'smtp' };
}

module.exports = { sendEmail };

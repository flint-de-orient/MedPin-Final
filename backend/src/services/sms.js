// SMS one-time codes via MSG91's Flow API (the SMS product), with the two
// DLT-approved templates registered against the sender ID: MSG91_TEMPLATE_LOGIN
// (sign-in) and MSG91_TEMPLATE_REGISTER (verifying a new patient's or member's
// phone). The wording lives at MSG91; this only fills in the code.
//
// Not the OTP API (/api/v5/otp): that product has its own template list, and
// these templates aren't in it — every request there "succeeds" but MSG91
// drops it as "Template ID Missing or Invalid Template".
//
// Without MSG91_AUTH_KEY the code is only logged (development).
const env = require('../config/env');

const FLOW_URL = 'https://control.msg91.com/api/v5/flow/';

const mask = (phone) => `+91 ${String(phone).slice(0, 2)}••••${String(phone).slice(-2)}`;

/** MSG91 wants the number with 91 and no "+". */
function toMobiles(phone) {
  const digits = String(phone).replace(/\D/g, '');
  return digits.length === 10 ? `91${digits}` : digits;
}

async function sendOtp(phone, code, purpose = 'login') {
  if (!env.msg91.authKey) {
    console.log(`[sms:dev] OTP for +91 ${phone}: ${code}`);
    return { provider: 'dev' };
  }
  const templateId = purpose === 'login' ? env.msg91.loginTemplateId : env.msg91.registerTemplateId;
  if (!templateId) throw new Error('MSG91 template id is not set (MSG91_TEMPLATE_LOGIN / MSG91_TEMPLATE_REGISTER)');
  if (!env.msg91.senderId) throw new Error('MSG91 sender id is not set (MSG91_SENDER_ID)');

  // The approved templates spell their variable differently (##OTP## / ##otp##):
  // both keys go on every request; MSG91 ignores one a template doesn't use.
  const body = {
    template_id: templateId,
    sender: env.msg91.senderId,
    short_url: '0',
    recipients: [{ mobiles: toMobiles(phone), OTP: code, otp: code }],
  };

  // Someone waiting on the code screen is better told it failed than left spinning.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  let res;
  let payload;
  try {
    res = await fetch(FLOW_URL, {
      method: 'POST',
      headers: { authkey: env.msg91.authKey, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    payload = await res.json().catch(() => ({}));
  } catch (err) {
    console.warn(`[sms:msg91] ${mask(phone)} request failed: ${err.message}`);
    throw new Error("Couldn't send the SMS. Please try again.");
  } finally {
    clearTimeout(timer);
  }
  // MSG91 can answer 200 with { type: 'error' } (bad template, bad number), so the status alone isn't enough.
  console.log(`[sms:msg91] ${mask(phone)} ${purpose} → ${res.status} ${JSON.stringify(payload)}`);
  if (!res.ok || payload?.type === 'error') throw new Error(`MSG91: ${payload?.message || res.status}`);
  return { provider: 'msg91', requestId: payload?.message };
}

module.exports = { sendOtp, FLOW_URL };

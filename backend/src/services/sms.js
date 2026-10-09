// SMS OTP via MSG91. Without MSG91_AUTH_KEY the code is only logged (dev).
const env = require('../config/env');

// Sign-in codes use the login template; verifying a new patient's or member's
// phone uses the register template.
async function sendOtp(phone, code, purpose = 'login') {
  if (!env.msg91.authKey) {
    console.log(`[sms:dev] OTP for +91 ${phone}: ${code}`);
    return { provider: 'dev' };
  }
  const url = new URL('https://control.msg91.com/api/v5/otp');
  const templateId = purpose === 'login' ? env.msg91.loginTemplateId : env.msg91.registerTemplateId;
  if (!templateId) throw new Error('MSG91 template id is not set (MSG91_TEMPLATE_LOGIN / MSG91_TEMPLATE_REGISTER)');
  url.searchParams.set('template_id', templateId);
  url.searchParams.set('mobile', `91${phone}`);
  url.searchParams.set('otp', code);
  const res = await fetch(url, {
    method: 'POST',
    headers: { authkey: env.msg91.authKey, 'content-type': 'application/json' },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.type === 'error') throw new Error(`MSG91: ${body.message || res.status}`);
  return { provider: 'msg91' };
}

module.exports = { sendOtp };

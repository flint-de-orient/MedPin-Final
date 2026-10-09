const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env'), quiet: true });

// Empty values in .env fall back to local-development defaults, so the
// backend runs against a local MongoDB before any keys are added.
const v = (key, fallback = '') => {
  const value = process.env[key];
  return value === undefined || value === '' ? fallback : value;
};

const nodeEnv = v('NODE_ENV', 'development');
const isProd = nodeEnv === 'production';

// Secrets: required in production, a fixed dev value otherwise.
const secret = (key) => {
  const value = v(key);
  if (value) return value;
  if (isProd) throw new Error(`${key} must be set in production`);
  return `dev-only-${key.toLowerCase()}`;
};

const env = {
  nodeEnv,
  isProd,
  port: Number(v('PORT', '4000')),
  corsOrigins: v('CORS_ORIGINS')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  publicUrl: v('PUBLIC_URL', `http://localhost:${v('PORT', '4000')}`),
  mongo: {
    uri: v('MONGODB_URI', 'mongodb://127.0.0.1:27017'),
    dbName: v('MONGODB_DB_NAME', 'medpin'),
  },
  jwt: {
    accessSecret: secret('JWT_ACCESS_SECRET'),
    refreshSecret: secret('JWT_REFRESH_SECRET'),
    accessTtl: v('JWT_ACCESS_TTL', '15m'),
    refreshTtl: v('JWT_REFRESH_TTL', '30d'),
  },
  otpHashSecret: secret('OTP_HASH_SECRET'),
  msg91: {
    authKey: v('MSG91_AUTH_KEY'),
    senderId: v('MSG91_SENDER_ID'),
    loginTemplateId: v('MSG91_TEMPLATE_LOGIN', v('MSG91_OTP_TEMPLATE_ID')),
    registerTemplateId: v('MSG91_TEMPLATE_REGISTER', v('MSG91_TEMPLATE_LOGIN', v('MSG91_OTP_TEMPLATE_ID'))),
  },
  // How sign-in codes reach the phone: msg91 (SMS from this server) or
  // firebase (Firebase Phone Auth sends the SMS; the app sends us the ID token).
  // dev: no SMS, the code is returned to the app (refused in production).
  smsProvider: v('SMS_PROVIDER', 'msg91'),
  firebase: {
    projectId: v('FIREBASE_PROJECT_ID'),
  },
  whatsapp: {
    accessToken: v('WHATSAPP_ACCESS_TOKEN'),
    phoneNumberId: v('WHATSAPP_PHONE_NUMBER_ID'),
  },
  fcm: {
    projectId: v('FCM_PROJECT_ID'),
    clientEmail: v('FCM_CLIENT_EMAIL'),
    privateKey: v('FCM_PRIVATE_KEY').replace(/\\n/g, '\n'),
  },
  smtp: {
    host: v('SMTP_HOST'),
    port: Number(v('SMTP_PORT', '587')),
    user: v('SMTP_USER'),
    pass: v('SMTP_PASS'),
    from: v('EMAIL_FROM'),
  },
  s3: {
    endpoint: v('S3_ENDPOINT'),
    region: v('S3_REGION', 'auto'),
    bucket: v('S3_BUCKET'),
    accessKeyId: v('S3_ACCESS_KEY_ID'),
    secretAccessKey: v('S3_SECRET_ACCESS_KEY'),
  },
  uploadsDir: path.resolve(__dirname, '..', '..', v('UPLOADS_DIR', 'uploads')),
  ai: {
    // Claude (Anthropic)
    apiKey: v('ANTHROPIC_API_KEY'),
    model: v('AI_MODEL', 'claude-opus-5-5'),
    // Gemini (Google AI Studio)
    gemini: {
      apiKey: v('GEMINI_API_KEY'),
      chatModel: v('GEMINI_CHAT_MODEL', 'gemini-3.8-flash'),
      visionModel: v('GEMINI_VISION_MODEL', v('GEMINI_CHAT_MODEL', 'gemini-3.8-flash')),
      embedModel: v('GEMINI_EMBED_MODEL', 'gemini-embedding-2'),
    },
  },
  razorpay: {
    keyId: v('RAZORPAY_KEY_ID'),
    keySecret: v('RAZORPAY_KEY_SECRET'),
    webhookSecret: v('RAZORPAY_WEBHOOK_SECRET'),
  },
  googleMapsKey: v('GOOGLE_MAPS_API_KEY'),
  support: {
    email: v('SUPPORT_EMAIL'),
    phone: v('SUPPORT_PHONE'),
    whatsapp: v('SUPPORT_WHATSAPP'),
  },
  abdm: {
    clientId: v('ABDM_CLIENT_ID'),
    clientSecret: v('ABDM_CLIENT_SECRET'),
    baseUrl: v('ABDM_BASE_URL'),
  },
  v,
};

if (env.isProd && env.smsProvider === 'dev') throw new Error('SMS_PROVIDER=dev is not allowed in production');

// Which AI provider answers: AI_PROVIDER=gemini|anthropic, else whichever key is set.
env.ai.provider = v('AI_PROVIDER') || (env.ai.gemini.apiKey ? 'gemini' : env.ai.apiKey ? 'anthropic' : 'off');

// In development, OTP codes are returned in the API response when no SMS
// provider is configured, so the app can be tested without sending SMS.
env.exposeDevOtp = !env.isProd && !env.msg91.authKey;

// Test numbers (non-production only): their code is returned instead of sent by
// SMS. Defaults to the demo accounts from `npm run db:seed`.
env.devOtpPhones = env.isProd
  ? []
  : v('DEV_OTP_PHONES', '9876518210,9876543210').split(',').map((s) => s.replace(/\D/g, '')).filter(Boolean);

module.exports = env;

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const mongoose = require('mongoose');
const env = require('./config/env');
const { HttpError } = require('./lib/http');
const M = require('./models');
const ai = require('./services/ai');
const storage = require('./services/storage');

const auth = require('./routes/auth');
const { me, notifications, catalog, files } = require('./routes/me');
const { threads, inbox, ai: aiRoutes } = require('./routes/messaging');

function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors({
    origin: env.corsOrigins.length ? env.corsOrigins : !env.isProd, // dev: allow any origin (Flutter web on localhost)
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Practice-Id'],
  }));
  app.use(express.json({ limit: '2mb', verify: (req, _res, buf) => { req.rawBody = buf; } }));
  // Express 5 leaves req.body undefined for body-less requests; routes expect an object.
  app.use((req, _res, next) => {
    if (req.body === undefined) req.body = {};
    next();
  });

  // Small in-memory limiter for the sign-in endpoints (per IP).
  const hits = new Map();
  app.use('/api/auth/otp', (req, res, next) => {
    const now = Date.now();
    const list = (hits.get(req.ip) || []).filter((t) => now - t < 60_000);
    list.push(now);
    hits.set(req.ip, list);
    if (list.length > 20) return res.status(429).json({ error: { code: 'RATE_LIMIT', message: 'Too many requests. Try again in a minute.' } });
    return next();
  });

  app.get('/health', async (_req, res) => {
    const db = mongoose.connection.readyState === 1;
    if (env.isProd) return res.status(db ? 200 : 503).json({ ok: db });
    res.status(db ? 200 : 503).json({
      ok: db,
      db: db ? 'connected' : 'disconnected',
      services: {
        sms: env.smsProvider === 'dev' ? 'dev (code shown in the app, no SMS)' : env.smsProvider === 'firebase' ? `firebase (project ${env.firebase.projectId || 'not set'})` : env.msg91.authKey ? 'msg91' : 'dev (code shown in the API response)',
        storage: storage.useS3 ? 's3' : 'local ./uploads',
        ai: ai.enabled() ? `${ai.provider()} · ${ai.modelName()}` : 'off (set GEMINI_API_KEY or ANTHROPIC_API_KEY)',
        push: env.fcm.projectId ? 'fcm' : 'dev log',
        whatsapp: env.whatsapp.accessToken ? 'meta' : 'dev log',
        email: env.smtp.host ? 'smtp' : 'dev log',
        payments: env.razorpay.keyId ? 'razorpay' : 'dev links',
      },
    });
  });

  app.use('/files', files);
  app.use('/api/auth', auth.router);
  app.use('/api/me', me);
  app.use('/api/notifications', notifications);
  app.use('/api/catalog', catalog);
  app.use('/api/patient', require('./routes/patient'));
  app.use('/api/conversations', threads);
  app.use('/api/inbox', inbox);
  app.use('/api/ai', aiRoutes);
  app.use('/api', require('./routes/admin')); // webhook first, then staff-only billing/exports
  app.use('/api', require('./routes/practice'));
  app.use('/api', require('./routes/doctor'));
  app.use('/api', require('./routes/patients'));
  app.use('/api', require('./routes/appointments'));
  app.use('/api', require('./routes/consultations'));
  app.use('/api', require('./routes/care'));
  app.use('/api', require('./routes/knowledge'));
  app.use('/api', require('./routes/reports'));

  // Dev stand-in for a Razorpay payment link (only when Razorpay isn't configured).
  if (!env.isProd && !env.razorpay.keyId) {
    app.post('/dev/pay/:paymentId', async (req, res) => {
      const p = await M.Payment.findById(req.params.paymentId);
      if (!p) return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Payment not found' } });
      Object.assign(p, { status: 'paid', method: 'online', paidAt: new Date() });
      await p.save();
      if (p.appointmentId) await M.Appointment.updateOne({ _id: p.appointmentId }, { feeStatus: 'paid' });
      return res.json({ ok: true, payment: p });
    });
  }

  app.use((req, res) => res.status(404).json({ error: { code: 'NOT_FOUND', message: `No route for ${req.method} ${req.path}` } }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    if (err instanceof HttpError || (err.status && err.status < 500)) {
      return res.status(err.status).json({ error: { code: err.code || 'ERROR', message: err.message, ...(err.details ? { details: err.details } : {}) } });
    }
    if (err instanceof mongoose.Error.ValidationError) {
      const first = Object.values(err.errors)[0];
      return res.status(400).json({ error: { code: 'VALIDATION', message: first?.message || 'Invalid data', fields: Object.keys(err.errors) } });
    }
    if (err instanceof mongoose.Error.CastError) {
      return res.status(400).json({ error: { code: 'INVALID_VALUE', message: `Invalid ${err.path}` } });
    }
    if (err.code === 11000) {
      return res.status(409).json({ error: { code: 'DUPLICATE', message: 'This already exists', fields: Object.keys(err.keyPattern || {}) } });
    }
    if (err.type === 'entity.too.large' || err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: { code: 'TOO_LARGE', message: 'That file is too large' } });
    }
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: { code: 'BAD_JSON', message: 'Invalid JSON body' } });
    }
    console.error(`[${req.method} ${req.path}]`, err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Something went wrong. Please try again.' } });
  });
  return app;
}

module.exports = { createApp };

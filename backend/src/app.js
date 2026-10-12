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
  app.use(require('./lib/request-base').middleware);
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

  // Pharmacy order page (private link from the order WhatsApp / email; no account).
  app.use('/pharmacy', express.urlencoded({ extended: false, limit: '10kb' }));
  const pharmacyOrder = async (req) => {
    const { sha256, safeEqual } = require('./lib/security');
    const token = String(req.query.t || req.body?.t || '');
    if (!/^[0-9a-f]{24}$/.test(req.params.id) || !token) return null;
    const order = await M.Order.findById(req.params.id).select('+pharmacyTokenHash');
    return order && order.pharmacyTokenHash && safeEqual(order.pharmacyTokenHash, sha256(token)) ? { order, token } : null;
  };
  // Doctor proof review (private signed link sent to the MedPin team).
  app.get('/review/proofs/:userId/:qid', async (req, res) => {
    const html = await require('./services/verification').reviewPage(req.params.userId, req.params.qid, req.query.t);
    if (!html) return res.status(404).type('html').send('<p>Not found</p>');
    res.type('html').send(html);
  });
  app.post('/review/proofs/:userId/:qid', express.urlencoded({ extended: false, limit: '10kb' }), async (req, res) => {
    const q = await require('./services/verification').decide(req.params.userId, req.params.qid, req.body.t, req.body.decision, req.body.note);
    if (!q) return res.status(404).type('html').send('<p>Not found</p>');
    res.redirect(303, `/review/proofs/${req.params.userId}/${req.params.qid}?t=${encodeURIComponent(req.body.t)}`);
  });

  app.get('/pharmacy/orders/:id', async (req, res) => {
    const found = await pharmacyOrder(req);
    if (!found) return res.status(404).type('html').send('<p>This order link is not valid.</p>');
    res.set('Cache-Control', 'no-store').type('html').send(await require('./services/orders').pharmacyPage(found.order, found.token));
  });
  app.post('/pharmacy/orders/:id/status', async (req, res) => {
    const found = await pharmacyOrder(req);
    if (!found) return res.status(404).type('html').send('<p>This order link is not valid.</p>');
    try {
      await require('./services/orders').setStatus(found.order, String(req.body.status || ''), { by: 'pharmacy' });
    } catch (err) {
      return res.status(409).type('html').send(`<p>${String(err.message).replace(/[<>&]/g, '')}</p><p><a href="/pharmacy/orders/${found.order._id}?t=${found.token}">Back</a></p>`);
    }
    res.redirect(303, `/pharmacy/orders/${found.order._id}?t=${encodeURIComponent(found.token)}`);
  });
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
  app.use('/api', require('./routes/places'));
  app.use('/api', require('./routes/reports'));

  // Dev stand-in for a Razorpay payment link (never in production; only without Razorpay keys).
  if (!env.isProd && !require('./services/payments').configured()) {
    const pay = require('./services/payments');
    const page = (title, body) => `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<body style="font-family:system-ui,sans-serif;max-width:420px;margin:40px auto;padding:0 16px;color:#111827">
<p style="color:#B45309;font-weight:600">Test payment · no money moves</p>${body}</body>`;
    const button = (amount) => `<form method="post"><button style="width:100%;height:52px;border:0;border-radius:14px;background:#003399;color:#fff;font-size:17px;font-weight:600">Pay ₹${amount} (test)</button></form>`;
    app.get('/dev/pay/plan/:subId/:planKey', async (req, res) => {
      const plan = await M.Plan.findOne({ key: req.params.planKey });
      if (!plan || !(await M.Subscription.exists({ _id: req.params.subId }))) return res.status(404).send(page('Not found', '<h2>Payment not found</h2>'));
      res.send(page('Pay for plan', `<h2>MedPin ${plan.name || plan.key} plan</h2><p>1 month</p>${button(plan.priceMonthly)}`));
    });
    app.post('/dev/pay/plan/:subId/:planKey', async (req, res) => {
      const sub = await pay.planPaid(req.params.subId, req.params.planKey);
      if (!sub) return res.status(404).send(page('Not found', '<h2>Payment not found</h2>'));
      if (req.accepts(['html', 'json']) === 'json') return res.json({ ok: true, subscription: sub });
      res.send(page('Paid', '<h2>Paid ✓</h2><p>You can go back to the MedPin app.</p>'));
    });
    app.get('/dev/pay/:paymentId', async (req, res) => {
      const p = /^[a-f\d]{24}$/i.test(req.params.paymentId) ? await M.Payment.findById(req.params.paymentId).populate('locationId', 'name') : null;
      if (!p) return res.status(404).send(page('Not found', '<h2>Payment not found</h2>'));
      if (p.status !== 'pending') return res.send(page('Paid', '<h2>Already paid ✓</h2>'));
      res.send(page('Pay fee', `<h2>Consultation fee</h2><p>${p.locationId?.name || ''}</p>${button(p.amount)}`));
    });
    app.post('/dev/pay/:paymentId', async (req, res) => {
      const exists = /^[a-f\d]{24}$/i.test(req.params.paymentId) && (await M.Payment.exists({ _id: req.params.paymentId }));
      if (!exists) return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Payment not found' } });
      const p = (await pay.feePaid(req.params.paymentId)) || (await M.Payment.findById(req.params.paymentId));
      if (req.accepts(['html', 'json']) === 'json') return res.json({ ok: true, payment: p });
      res.send(page('Paid', '<h2>Paid ✓</h2><p>You can go back to the MedPin app.</p>'));
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

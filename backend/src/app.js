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
  app.locals.rateHits = hits; // tests clear it between checks
  // Also the consent-code link (a code that guesses could try).
  app.use(['/api/auth/otp', '/api/patients/link'], (req, res, next) => {
    const now = Date.now();
    // Counted per endpoint: a clinic's sign-ins don't use up its patient links (one IP, one office).
    const key = `${req.baseUrl}:${req.ip}`;
    const list = (hits.get(key) || []).filter((t) => now - t < 60_000);
    list.push(now);
    hits.set(key, list);
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
  // QR on every prescription PDF: anyone (a pharmacist) can check it is real.
  // Shows only what is needed to trust it; the patient appears as initials.
  app.get('/rx/:id/verify', async (req, res) => {
    const { verifyToken, rxNo, fmtDate } = require('./services/rxpdf');
    const { safeEqual } = require('./lib/security');
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const page = (title, body) => `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<body style="margin:0;background:#F7F9FC;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#111827">
<div style="max-width:440px;margin:0 auto;padding:32px 20px"><div style="font-weight:800;color:#003399;font-size:20px;margin-bottom:20px">MedPin</div>${body}</div></body>`;
    const ok = /^[a-f\d]{24}$/i.test(req.params.id) && safeEqual(String(req.query.t || ''), verifyToken(req.params.id));
    const rx = ok ? await M.Prescription.findById(req.params.id).populate('patientId', 'name') : null;
    if (!rx) {
      return res.status(404).send(page('Not verified', `<div style="background:#FDECEC;border:1px solid #F3C4C4;border-radius:16px;padding:20px"><h2 style="margin:0 0 6px;color:#B91C1C">Not verified</h2><p style="margin:0;color:#545E72">This QR code doesn't match a MedPin prescription. Ask the clinic to confirm it.</p></div>`));
    }
    const profile = await M.DoctorProfile.findOne({ userId: rx.doctorId }, 'registration displayName');
    const loc = rx.locationId ? await M.Location.findById(rx.locationId, 'name city') : null;
    const valid = !rx.validUntil || rx.validUntil >= new Date();
    const ini = String(rx.patientId?.name || '').split(/\s+/).filter(Boolean).map((w) => `${w[0].toUpperCase()}.`).join(' ');
    const reg = profile?.registration?.number ? `${profile.registration.number}${profile.registration.councilShort ? ` · ${profile.registration.councilShort}` : ''}` : '';
    const row = (k, v) => (v ? `<div style="display:flex;justify-content:space-between;gap:12px;padding:10px 0;border-top:1px solid #E5E9F0"><span style="color:#69738A">${k}</span><span style="font-weight:600;text-align:right">${esc(v)}</span></div>` : '');
    // Cancelled or replaced by a corrected one: genuine, but not to be dispensed.
    const stopped = rx.status === 'cancelled' || rx.status === 'amended';
    const badge = stopped
      ? `<span style="background:#FDECEC;color:#B91C1C;border-radius:999px;padding:4px 12px;font-weight:700;font-size:13px">${rx.status === 'cancelled' ? 'Cancelled by the doctor · do not dispense' : 'Replaced by a corrected prescription · do not dispense'}</span>`
      : valid
      ? '<span style="background:#E8F5EC;color:#15803D;border-radius:999px;padding:4px 12px;font-weight:700;font-size:13px">✓ Genuine · valid</span>'
      : '<span style="background:#FEF6E7;color:#B45309;border-radius:999px;padding:4px 12px;font-weight:700;font-size:13px">Genuine · expired</span>';
    res.set('Cache-Control', 'no-store').send(page('Prescription verified', `<div style="background:#fff;border:1px solid #E5E9F0;border-radius:24px;padding:20px">${badge}
<h2 style="margin:14px 0 4px">${esc(rxNo(rx))}</h2><p style="margin:0 0 12px;color:#545E72">Issued through MedPin</p>
${row('Doctor', rx.doctorName || profile?.displayName)}${row('Reg. No.', reg)}${row('Clinic', loc && [loc.name, loc.city].filter(Boolean).join(', '))}${row('Patient', ini)}${row('Date', fmtDate(rx.issuedAt))}${row('Valid till', rx.validUntil && fmtDate(rx.validUntil))}${row('Medicines', String(rx.items.length))}</div>`));
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
    app.get('/dev/pay/order/:orderId', async (req, res) => {
      const o = /^[a-f\d]{24}$/i.test(req.params.orderId) ? await M.Order.findById(req.params.orderId).populate('pharmacyId', 'name') : null;
      if (!o) return res.status(404).send(page('Not found', '<h2>Order not found</h2>'));
      if (o.pay?.status === 'paid') return res.send(page('Paid', '<h2>Already paid ✓</h2>'));
      res.send(page('Pay for medicines', `<h2>Medicines</h2><p>${o.pharmacyId?.name || ''}</p>${button(o.total)}`));
    });
    app.post('/dev/pay/order/:orderId', async (req, res) => {
      const o = /^[a-f\d]{24}$/i.test(req.params.orderId) && (await pay.orderPaid(req.params.orderId));
      if (!o) return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Order not found or already paid' } });
      if (req.accepts(['html', 'json']) === 'json') return res.json({ ok: true, order: o });
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

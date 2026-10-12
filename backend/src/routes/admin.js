// Billing, History-Download, Report-Download, Export, Razorpay webhook.
const { Router } = require('express');
const crypto = require('crypto');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit');
const { setupFonts, write } = require('../lib/pdftext');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const env = require('../config/env');
const { requireAuth, staff, ownerOnly, need } = require('../middleware/auth');
const { badRequest, conflict, notFound, list } = require('../lib/http');
const { safeEqual } = require('../lib/security');
const storage = require('../services/storage');
const { sendEmail } = require('../services/email');

const r = Router();

// ── Razorpay webhook (no auth; verified by signature) ──
r.post('/billing/webhook', async (req, res) => {
  if (!env.razorpay.webhookSecret) return res.status(503).json({ error: 'Webhook not configured' });
  const expected = crypto.createHmac('sha256', env.razorpay.webhookSecret).update(req.rawBody || '').digest('hex');
  if (!safeEqual(expected, req.headers['x-razorpay-signature'] || '')) return res.status(400).json({ error: 'Bad signature' });
  const { event, payload } = req.body;
  if (event === 'payment_link.paid') {
    const pay = require('../services/payments');
    const link = payload.payment_link?.entity || {};
    const notes = link.notes || {};
    const paymentId = payload.payment?.entity?.id;
    if (notes.kind === 'plan') await pay.planPaid(notes.subscriptionId, notes.planKey, paymentId);
    else if (notes.kind === 'order') await pay.orderPaid(notes.orderId, paymentId);
    else {
      // Fee links: notes.paymentId (older links: reference_id was the payment id).
      const ref = notes.paymentId || String(link.reference_id || '').split('.')[0];
      if (/^[a-f\d]{24}$/i.test(ref)) await pay.feePaid(ref, paymentId);
    }
  }
  if (String(event).startsWith('payout.')) await require('../services/payouts').onWebhook(event, payload.payout?.entity);
  if (event === 'invoice.paid') {
    await M.Invoice.updateOne({ razorpayInvoiceId: payload.invoice?.entity?.id }, { status: 'paid', paidAt: new Date(), razorpayPaymentId: payload.payment?.entity?.id });
  }
  if (event === 'subscription.charged') {
    const sub = await M.Subscription.findOne({ razorpaySubscriptionId: payload.subscription?.entity?.id });
    if (sub) {
      const start = sub.currentPeriodEnd || new Date();
      if (sub.pendingPlanKey) {
        const plan = await M.Plan.findOne({ key: sub.pendingPlanKey });
        Object.assign(sub, { planKey: sub.pendingPlanKey, price: plan.priceMonthly, pendingPlanKey: undefined, pendingFrom: undefined });
      }
      Object.assign(sub, { status: 'active', currentPeriodStart: start, currentPeriodEnd: T.addDays(start, 30) });
      await sub.save();
      await M.Invoice.create({ practiceId: sub.practiceId, issuedAt: new Date(), description: `${sub.planKey} plan · monthly`, amount: sub.price, status: 'paid', paidAt: new Date(), periodStart: start, periodEnd: sub.currentPeriodEnd, razorpayPaymentId: payload.payment?.entity?.id });
    }
  }
  return res.json({ ok: true });
});

r.use(requireAuth, staff());
r.use('/billing', need('billing'));
r.use('/exports', need('exports'));

// ── Billing ──
r.get('/billing', async (req, res) => {
  const sub = await M.Subscription.findOne({ practiceId: req.practiceId });
  const plans = await M.Plan.find({ active: true }).sort({ priceMonthly: 1 });
  const plan = sub && plans.find((p) => p.key === sub.planKey);
  const periodStart = sub?.currentPeriodStart || new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  const [seats, patients, usage, invoices] = await Promise.all([
    M.Member.countDocuments({ practiceId: req.practiceId, status: 'active' }),
    M.PatientEnrolment.countDocuments({ practiceId: req.practiceId, status: 'linked' }),
    M.UsageCounter.findOne({ practiceId: req.practiceId, periodStart }),
    M.Invoice.find({ practiceId: req.practiceId }).sort({ issuedAt: -1 }).limit(Number(req.query.invoices) || 3),
  ]);
  res.json({
    subscription: sub,
    plan,
    plans,
    usage: {
      resetsAt: sub?.currentPeriodEnd,
      seats: { used: seats, limit: plan?.seats },
      activePatients: { used: patients, limit: plan?.activePatients },
      aiChats: { used: usage?.aiChats || 0, limit: plan?.aiChatsPerMonth },
    },
    invoices: invoices.map((i) => ({ ...i.toJSON(), file: storage.withUrl(i.file) })),
    checkout: require('../services/payments').configured() ? 'razorpay' : env.isProd ? 'not_configured' : 'dev',
  });
});

// Changes apply from the next billing cycle.
r.post('/billing/switch', ownerOnly, async (req, res) => {
  const plan = await M.Plan.findOne({ key: req.body.planKey, active: true });
  if (!plan) throw badRequest('Choose a plan');
  const sub = await M.Subscription.findOne({ practiceId: req.practiceId });
  if (!sub) throw notFound('Subscription');
  if (sub.planKey === plan.key) throw conflict('You are already on this plan');
  const seats = await M.Member.countDocuments({ practiceId: req.practiceId, status: 'active' });
  if (seats > plan.seats) {
    throw conflict(`Your team has ${seats} people, so ${seats - plan.seats} would need to be removed first`, 'TOO_MANY_SEATS', { seats, limit: plan.seats });
  }
  const upgrade = (plan.priceMonthly || 0) > (sub.price || 0);
  const pay = require('../services/payments');
  if (upgrade && sub.status !== 'trialing' && !pay.configured() && env.isProd) {
    throw Object.assign(conflict('Online payment is not set up yet, so the plan cannot be upgraded. Contact MedPin support.', 'PAYMENTS_OFF'), { status: 503 });
  }
  // A paid upgrade starts once paid: the doctor gets a payment link to open.
  if (upgrade && sub.status !== 'trialing' && pay.configured()) {
    const checkoutUrl = await pay.planLink(sub, plan, req.user);
    return res.json({ ...sub.toJSON(), checkoutUrl, awaitingPayment: true });
  }
  sub.pendingPlanKey = plan.key;
  sub.pendingFrom = sub.currentPeriodEnd || new Date();
  // Trials (and practices without online billing yet) switch straight away.
  if (sub.status === 'trialing' || !pay.configured()) {
    Object.assign(sub, { planKey: plan.key, price: plan.priceMonthly, pendingPlanKey: undefined, pendingFrom: undefined });
  }
  await sub.save();
  res.json(sub);
});

r.get('/billing/invoices/:id/download', async (req, res) => {
  const inv = await M.Invoice.findOne({ _id: req.params.id, practiceId: req.practiceId });
  if (!inv) throw notFound('Invoice');
  if (!inv.file?.key) {
    const practice = await M.Practice.findById(req.practiceId, 'name');
    const pdf = await simplePdf(`Invoice ${inv.number || inv._id}`, [
      ['Billed to', practice.name], ['Date', T.dayKey(inv.issuedAt)], ['Description', inv.description || ''], ['Amount', `INR ${inv.amount}`], ['Status', inv.status],
    ]);
    inv.file = await storage.save(pdf, { folder: 'invoices', name: `invoice-${T.dayKey(inv.issuedAt)}.pdf`, mimeType: 'application/pdf' });
    await inv.save();
  }
  res.json({ url: storage.signedUrl(inv.file.key) });
});

// ── Exports ──
function simplePdf(title, rows, header) {
  return new Promise((resolve, reject) => {
    const doc = setupFonts(new PDFDocument({ size: 'A4', margin: 40, layout: header ? 'landscape' : 'portrait' }));
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    doc.fontSize(16);
    write(doc, title);
    doc.moveDown().fontSize(9);
    if (header) {
      write(doc, header.join('  |  '));
      doc.moveDown(0.3);
    }
    if (!rows.length) write(doc, 'Nothing in this period.');
    for (const row of rows) write(doc, row.map((c) => (c == null ? '' : String(c))).join('  |  '));
    doc.end();
  });
}

const safeCell = (v) => (typeof v === 'string' && /^[=+\-@\t\r]/.test(v) ? `'${v}` : v);
const csvCell = (v) => {
  const s = v == null ? '' : v instanceof Date ? v.toISOString() : String(safeCell(v));
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

async function buildRows(req, job) {
  const from = job.filters?.from ? T.parseDay(job.filters.from) : T.addDays(T.dayStart(), -30);
  const to = job.filters?.to ? T.addDays(T.parseDay(job.filters.to), 1) : T.addDays(T.dayStart(), 1);
  const mobile = (p) => (job.includeMobiles ? p?.phone : undefined);
  const sets = {};
  if (job.kind === 'appointment_history') {
    const q = { practiceId: req.practiceId, date: { $gte: from, $lt: to } };
    if (job.filters?.statuses?.length) q.status = { $in: job.filters.statuses };
    const appts = await M.Appointment.find(q).sort({ startAt: 1 }).populate('patientId', 'name phone').populate('doctorId', 'name').populate('locationId', 'name').lean();
    sets.appointments = {
      header: ['Date', 'Time', 'Token', 'Patient', ...(job.includeMobiles ? ['Mobile'] : []), 'Doctor', 'Location', 'Type', 'Mode', 'Status', 'Fee'],
      rows: appts.map((a) => [T.dayKey(a.startAt), T.fmtTime(T.minuteOfDay(a.startAt)), a.tokenNo, a.patientId?.name, ...(job.includeMobiles ? [mobile(a.patientId)] : []), a.doctorId?.name, a.locationId?.name, a.visitType, a.mode, a.status, a.fee]),
    };
  }
  if (job.kind === 'report') {
    const { filtersOf, visits } = require('./reports');
    const f = filtersOf(job.filters || {});
    const type = job.reportType || 'consultations';
    const mob = job.includeMobiles ? ['Mobile'] : [];
    const day = (d) => (d ? T.dayKey(d) : '');
    if (type === 'prescriptions') {
      const q = { practiceId: req.practiceId, issuedAt: { $gte: from, $lt: to } };
      if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
      if (f.locationIds.length || f.visitTypes.length || f.modes.length || f.ageGroups.length) {
        const appts = await visits(req, T.addDays(from, -1), to, f);
        q.consultationId = { $in: await M.Consultation.find({ appointmentId: { $in: appts.map((a) => a._id) } }).distinct('_id') };
      }
      const items = await M.Prescription.find(q).sort({ issuedAt: 1 }).populate('patientId', 'name phone').lean();
      sets.prescriptions = {
        header: ['Rx', 'Date', 'Patient', ...mob, 'Medicines', 'Tests'],
        rows: items.map((p) => [String(p.rxNumber || '').padStart(4, '0'), day(p.issuedAt), p.patientId?.name, ...(job.includeMobiles ? [mobile(p.patientId)] : []), p.items.map((i) => `${i.name} ${i.strength || ''}`.trim()).join('; '), p.tests.join('; ')]),
      };
    } else if (type === 'fees') {
      const appts = await visits(req, from, to, f, { status: { $in: ['completed', 'missed', 'cancelled', 'booked', 'confirmed', 'waiting', 'in_consultation'] } });
      const pays = await M.Payment.find({ practiceId: req.practiceId, appointmentId: { $in: appts.map((a) => a._id) } }).lean();
      const byAppt = new Map(pays.map((x) => [String(x.appointmentId), x]));
      sets.fees = {
        header: ['Date', 'Patient', ...mob, 'Location', 'Type', 'Fee', 'Status', 'Method', 'Paid on'],
        rows: appts.filter((a) => a.fee != null).sort((a, b) => a.date - b.date).map((a) => {
          const pay = byAppt.get(String(a._id));
          return [day(a.date), a.patientId?.name, ...(job.includeMobiles ? [mobile(a.patientId)] : []), a.locationId?.name, a.visitType, a.fee, pay?.status || a.feeStatus, pay?.method || '', day(pay?.paidAt)];
        }),
      };
    } else if (type === 'follow_ups') {
      const q = { practiceId: req.practiceId, dueDate: { $gte: from, $lt: to } };
      if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
      if (f.locationIds.length) q.locationId = { $in: f.locationIds };
      const items = await M.FollowUp.find(q).sort({ dueDate: 1 }).populate('patientId', 'name phone').lean();
      sets.follow_ups = {
        header: ['Due', 'Patient', ...mob, 'Advice', 'Status', 'Reminders sent', 'Last reminded'],
        rows: items.map((x) => [day(x.dueDate), x.patientId?.name, ...(job.includeMobiles ? [mobile(x.patientId)] : []), x.adviceText || '', x.status, x.remindersSent || 0, day(x.lastRemindedAt)]),
      };
    } else if (type === 'referrals') {
      const q = { practiceId: req.practiceId, referredAt: { $gte: from, $lt: to } };
      if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
      const items = await M.Referral.find(q).sort({ referredAt: 1 }).populate('patientId', 'name phone').lean();
      sets.referrals = {
        header: ['Date', 'Patient', ...mob, 'Direction', 'To / from', 'Specialty', 'Reason', 'Status'],
        rows: items.map((x) => [day(x.referredAt), x.patientId?.name, ...(job.includeMobiles ? [mobile(x.patientId)] : []), x.direction, x.counterpartName, x.specialty || '', x.reason || '', x.status]),
      };
    } else if (type === 'daily') {
      const appts = await visits(req, from, to, f, { status: { $in: ['completed', 'missed', 'cancelled', 'booked', 'confirmed', 'waiting', 'in_consultation', 'rescheduled'] } });
      sets.daily = {
        header: ['Date', 'Time', 'Token', 'Patient', ...mob, 'Location', 'Type', 'Mode', 'Status', 'Fee', 'Fee status'],
        rows: appts.sort((a, b) => a.startAt - b.startAt).map((a) => [day(a.date), T.fmtTime(T.minuteOfDay(a.startAt)), a.tokenNo, a.patientId?.name, ...(job.includeMobiles ? [mobile(a.patientId)] : []), a.locationId?.name, a.visitType, a.mode, a.status, a.fee, a.feeStatus]),
      };
    } else {
      const appts = await visits(req, from, to, f);
      const consults = await M.Consultation.find({ appointmentId: { $in: appts.map((a) => a._id) } }, 'appointmentId diagnoses').lean();
      const dx = new Map(consults.map((c) => [String(c.appointmentId), c.diagnoses.map((d) => d.name).join('; ')]));
      sets.consultations = {
        header: ['Date', 'Patient', ...mob, 'Age', 'Type', 'Mode', 'Location', 'Diagnosis', 'Fee', 'Fee status'],
        rows: appts.sort((a, b) => a.date - b.date).map((a) => [day(a.date), a.patientId?.name, ...(job.includeMobiles ? [mobile(a.patientId)] : []), a.age ?? '', a.visitType, a.mode, a.locationId?.name, dx.get(String(a._id)) || '', a.fee, a.feeStatus]),
      };
    }
  }
  if (job.kind === 'data_export') {
    const ids = await M.PatientEnrolment.find({ practiceId: req.practiceId, status: 'linked' }).distinct('patientId');
    const patients = await M.Patient.find({ _id: { $in: ids } }).lean();
    if (job.datasets.includes('patients')) {
      sets.patients = { header: ['Name', 'Mobile', 'Gender', 'Age', 'Blood group', 'Address'], rows: patients.map((p) => [p.name, p.phone, p.gender, T.ageFrom(p), p.bloodGroup, p.addresses?.[0]?.line]) };
    }
    if (job.datasets.includes('clinical_summary')) {
      const courses = await M.MedicationCourse.find({ patientId: { $in: ids }, status: 'active' }).lean();
      const latest = await M.Vitals.aggregate([{ $match: { patientId: { $in: ids } } }, { $sort: { recordedAt: -1 } }, { $group: { _id: '$patientId', v: { $first: '$$ROOT' } } }]);
      const lv = new Map(latest.map((x) => [String(x._id), x.v]));
      sets.clinical_summary = {
        header: ['Name', 'Conditions', 'Allergies', 'Medicines', 'Latest BP', 'Latest sugar', 'Latest weight'],
        rows: patients.map((p) => {
          const v = lv.get(String(p._id)) || {};
          return [p.name, p.conditions.map((c) => c.name).join('; '), p.allergies.map((a) => a.allergen).join('; '), courses.filter((c) => String(c.patientId) === String(p._id)).map((c) => `${c.name} ${c.strength || ''}`).join('; '), v.bpSystolic ? `${v.bpSystolic}/${v.bpDiastolic}` : '', v.bloodSugar || '', v.weightKg || ''];
        }),
      };
    }
    if (job.datasets.includes('alerts')) {
      const alerts = await M.Alert.find({ practiceId: req.practiceId, createdAt: { $gte: from, $lt: to } }).populate('patientId', 'name').lean();
      sets.alerts = { header: ['Raised', 'Patient', 'Severity', 'Kind', 'Status', 'Detail'], rows: alerts.map((a) => [a.createdAt, a.patientId?.name, a.severity, a.kind, a.status, a.detail]) };
    }
  }
  return sets;
}

async function render(sets, format, title) {
  if (format === 'json') {
    const obj = Object.fromEntries(Object.entries(sets).map(([k, s]) => [k, s.rows.map((row) => Object.fromEntries(s.header.map((h, i) => [h, row[i]])))]));
    return { buffer: Buffer.from(JSON.stringify(obj, null, 2)), mimeType: 'application/json', ext: 'json' };
  }
  if (format === 'csv') {
    const text = Object.entries(sets).map(([k, s]) => `${Object.keys(sets).length > 1 ? `# ${k}\n` : ''}${[s.header, ...s.rows].map((row) => row.map(csvCell).join(',')).join('\n')}`).join('\n\n');
    return { buffer: Buffer.from(`﻿${text}`), mimeType: 'text/csv', ext: 'csv' };
  }
  if (format === 'xlsx') {
    const wb = new ExcelJS.Workbook();
    for (const [k, s] of Object.entries(sets)) {
      const ws = wb.addWorksheet(k.slice(0, 31));
      ws.addRow(s.header).font = { bold: true };
      s.rows.forEach((row) => ws.addRow(row.map(safeCell)));
    }
    return { buffer: Buffer.from(await wb.xlsx.writeBuffer()), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', ext: 'xlsx' };
  }
  const [first] = Object.values(sets);
  return { buffer: await simplePdf(title, first?.rows || [], first?.header), mimeType: 'application/pdf', ext: 'pdf' };
}

r.post('/exports', async (req, res) => {
  const { kind, reportType, format, filters = {}, includeMobiles = false, emailCopy = false } = req.body;
  const datasets = list(req.body.datasets);
  if (!E.EXPORT_KINDS.includes(kind)) throw badRequest('Unknown export');
  if (!E.EXPORT_FORMATS.includes(format)) throw badRequest('Choose a format');
  if (kind === 'data_export') {
    if (!req.member.isOwner && req.member.role !== 'practice_manager') throw conflict('Only the practice owner can export patient data', 'OWNER_REQUIRED');
    if (!datasets.length) throw badRequest('Choose at least one dataset', 'DATASET_REQUIRED');
  }
  const job = await M.ExportJob.create({ practiceId: req.practiceId, requestedBy: req.user._id, kind, reportType, datasets, format, filters, includeMobiles, emailCopy, status: 'running' });
  try {
    const sets = await buildRows(req, job);
    const title = `MedPin ${kind.replace('_', ' ')}${reportType ? ` · ${reportType}` : ''} · ${T.dayKey(new Date())}`;
    const { buffer, mimeType, ext } = await render(sets, format, title);
    job.file = await storage.save(buffer, { folder: 'exports', name: `medpin-${reportType || kind}-${T.dayKey(new Date())}.${ext}`, mimeType });
    job.rowCount = Object.values(sets).reduce((n, s) => n + s.rows.length, 0);
    job.status = 'done';
    job.completedAt = new Date();
    await job.save();
    let emailed = false;
    if (emailCopy && req.user.email) {
      emailed = await sendEmail({ to: req.user.email, subject: title, text: 'Your MedPin export is attached.', attachments: [{ filename: job.file.name, content: buffer }] })
        .then((r) => r?.provider === 'smtp')
        .catch(() => false);
    }
    await M.AuditLog.create({ practiceId: req.practiceId, userId: req.user._id, action: 'export.create', entity: 'ExportJob', entityId: job._id, meta: { kind, format, includeMobiles, rows: job.rowCount }, ip: req.ip });
    res.status(201).json({ ...job.toJSON(), url: storage.signedUrl(job.file.key), emailed, emailMissing: Boolean(emailCopy && !req.user.email) });
  } catch (err) {
    job.status = 'failed';
    job.error = err.message;
    await job.save();
    throw err;
  }
});

r.get('/exports', async (req, res) => {
  const jobs = await M.ExportJob.find({ practiceId: req.practiceId, requestedBy: req.user._id }).sort({ createdAt: -1 }).limit(30);
  res.json(jobs.map((j) => ({ ...j.toJSON(), url: j.file?.key ? storage.signedUrl(j.file.key) : null })));
});

module.exports = r;

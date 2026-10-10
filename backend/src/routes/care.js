// Doctor-FollowUps, Report-Referrals, Alerts.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice, ownPractice } = require('../middleware/auth');
const { badRequest, notFound, conflict, list, escapeRegex, pick } = require('../lib/http');
const { notify } = require('../services/notify');
const { sendWhatsApp } = require('../services/push');

const r = Router();
r.use(requireAuth, staff());

// ── Follow-ups ──
r.get('/follow-ups', async (req, res) => {
  const today = T.dayStart();
  const q = { practiceId: req.practiceId, status: { $in: ['not_booked', 'no_reply', 'booked', 'reports_in'] } };
  if (req.query.tab === 'not_booked') q.status = { $in: ['not_booked', 'no_reply'] };
  if (req.query.tab === 'booked') q.status = { $in: ['booked', 'reports_in'] };
  if (req.query.locationId) q.locationId = req.query.locationId;
  if (req.query.doctorId) q.doctorId = req.query.doctorId === 'me' ? req.user._id : req.query.doctorId;
  q.dueDate = { $lte: T.addDays(today, Number(req.query.days) || 31) };
  let items = await M.FollowUp.find(q).sort({ dueDate: 1 })
    .populate('patientId', 'name gender ageYears ageRecordedAt phone conditions').populate('locationId', 'name shortName').populate('appointmentId', 'startAt locationId');
  if (req.query.condition) {
    const re = new RegExp(escapeRegex(req.query.condition), 'i');
    items = items.filter((f) => f.patientId?.conditions?.some((c) => re.test(c.name)));
  }
  const endOfWeek = T.addDays(today, 7);
  const rows = items.map((f) => ({
    ...f.toJSON(),
    patient: f.patientId && { id: f.patientId._id, name: f.patientId.name, age: T.ageFrom(f.patientId), gender: f.patientId.gender, phone: f.patientId.phone, conditions: f.patientId.conditions.map((c) => c.name) },
    overdueDays: f.dueDate < today ? Math.round((today - f.dueDate) / T.DAY_MS) : 0,
    group: f.dueDate < today ? 'overdue' : f.dueDate < endOfWeek ? 'this_week' : 'later',
  }));
  res.json({
    counts: { all: rows.length, notBooked: rows.filter((x) => ['not_booked', 'no_reply'].includes(x.status)).length, booked: rows.filter((x) => ['booked', 'reports_in'].includes(x.status)).length },
    items: rows,
  });
});

async function remind(fu, practiceName) {
  const patient = await M.Patient.findById(fu.patientId, 'name phone userId');
  const text = `${practiceName}: your follow-up is due on ${T.dayKey(fu.dueDate)}. Please book a visit in MedPin or reply to this message.`;
  if (patient.userId) await notify([patient.userId], { type: 'follow_up_reminder', practiceId: fu.practiceId, title: 'Follow-up due', body: text, screen: 'Patient-Doctors' });
  else await sendWhatsApp(patient.phone, text);
  fu.remindersSent += 1;
  fu.lastRemindedAt = new Date();
  if (fu.status === 'not_booked' && fu.remindersSent >= 2) fu.status = 'no_reply';
  await fu.save();
  return fu;
}

r.post('/follow-ups/:id/remind', async (req, res) => {
  const fu = ownPractice(req, await M.FollowUp.findById(req.params.id), 'Follow-up');
  const practice = await M.Practice.findById(req.practiceId, 'name');
  res.json(await remind(fu, practice.name));
});

// "Remind all" / "Remind 5"
r.post('/follow-ups/remind', async (req, res) => {
  const ids = list(req.body.ids);
  const q = { practiceId: req.practiceId, status: { $in: ['not_booked', 'no_reply'] }, ...(ids.length ? { _id: { $in: ids } } : { dueDate: { $lte: T.addDays(T.dayStart(), 7) } }) };
  const practice = await M.Practice.findById(req.practiceId, 'name');
  const items = await M.FollowUp.find(q);
  for (const fu of items) await remind(fu, practice.name);
  res.json({ reminded: items.length });
});

r.patch('/follow-ups/:id', async (req, res) => {
  const fu = ownPractice(req, await M.FollowUp.findById(req.params.id), 'Follow-up');
  const body = pick(req.body, ['dueDate', 'status', 'adviceText']);
  if (body.status && !E.FOLLOW_UP_STATUSES.includes(body.status)) throw badRequest('Unknown status');
  if (body.dueDate) body.dueDate = T.parseDay(body.dueDate);
  Object.assign(fu, body);
  await fu.save();
  res.json(fu);
});

// ── Referrals ──
r.get('/referrals', async (req, res) => {
  const direction = req.query.direction || 'sent';
  // Optional period (range=… or from/to, like the reports); default = all time.
  const period = {};
  if (req.query.range || req.query.from || req.query.to) {
    const { rangeOf } = require('./reports');
    const { from, to } = rangeOf(req.query);
    period.referredAt = { $gte: from, $lt: to };
  }
  const items = await M.Referral.find({ practiceId: req.practiceId, direction, ...period }).sort({ referredAt: -1 }).populate('patientId', 'name gender ageYears ageRecordedAt');
  const all = await M.Referral.aggregate([{ $match: { practiceId: req.practiceId, ...period } }, { $group: { _id: { d: '$direction', s: '$status' }, n: { $sum: 1 } } }]);
  const c = (d, s) => all.filter((x) => x._id.d === d && (!s || x._id.s === s)).reduce((n, x) => n + x.n, 0);
  const bySpecialty = await M.Referral.aggregate([{ $match: { practiceId: req.practiceId, direction, ...period } }, { $group: { _id: '$specialty', n: { $sum: 1 } } }, { $sort: { n: -1 } }]);
  res.json({
    counts: { sent: c('sent'), received: c('received'), sentSeen: c('sent', 'seen'), sentAwaiting: c('sent', 'awaiting'), receivedSeen: c('received', 'seen'), receivedAwaiting: c('received', 'awaiting') },
    bySpecialty: bySpecialty.map((b) => ({ specialty: b._id || 'Other', count: b.n })),
    items,
  });
});

r.post('/referrals', async (req, res) => {
  await patientInPractice(req, req.body.patientId);
  if (!E.REFERRAL_DIRECTIONS.includes(req.body.direction)) throw badRequest('Choose sent or received');
  if (!req.body.counterpartName) throw badRequest('Enter who it is to / from');
  const ref = await M.Referral.create({
    ...pick(req.body, ['patientId', 'direction', 'counterpartName', 'counterpartUserId', 'specialty', 'reason', 'consultationId']),
    practiceId: req.practiceId, doctorId: req.user._id,
  });
  res.status(201).json(ref);
});

r.post('/referrals/:id/seen', async (req, res) => {
  const ref = ownPractice(req, await M.Referral.findById(req.params.id), 'Referral');
  ref.status = 'seen';
  ref.seenAt = req.body.seenAt ? new Date(req.body.seenAt) : new Date();
  await ref.save();
  res.json(ref);
});

// ── Alerts ──
const SEVERITY_ORDER = { emergency: 0, urgent: 1, watch: 2 };
r.get('/alerts', need('alerts'), async (req, res) => {
  const q = { practiceId: req.practiceId };
  const status = req.query.status || 'open';
  if (status !== 'all') q.status = status;
  if (req.query.severity) q.severity = { $in: list(req.query.severity) };
  if (req.query.patientId) q.patientId = req.query.patientId;
  let items = await M.Alert.find(q).sort({ createdAt: -1 }).limit(300).populate('patientId', 'name gender ageYears ageRecordedAt conditions').populate('noteBy', 'name');
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    items = items.filter((a) => re.test(a.patientId?.name || ''));
  }
  items.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || ['open', 'acknowledged', 'resolved'].indexOf(a.status) - ['open', 'acknowledged', 'resolved'].indexOf(b.status) || b.createdAt - a.createdAt);
  const counts = await M.Alert.aggregate([{ $match: { practiceId: req.practiceId } }, { $group: { _id: '$status', n: { $sum: 1 } } }]);
  res.json({
    counts: Object.fromEntries(counts.map((c) => [c._id, c.n])),
    items: items.map((a) => ({
      ...a.toJSON(),
      patient: a.patientId && { id: a.patientId._id, name: a.patientId.name, age: T.ageFrom(a.patientId), gender: a.patientId.gender, conditions: a.patientId.conditions.map((c) => c.name) },
      acknowledgedToday: a.acknowledged?.at && T.dayKey(a.acknowledged.at) === T.dayKey(new Date()),
    })),
  });
});

const getAlert = async (req) => ownPractice(req, await M.Alert.findById(req.params.id), 'Alert');
const applyNote = (alert, req) => {
  if (req.body.note) Object.assign(alert, { note: req.body.note, noteBy: req.user._id, noteAt: new Date() });
};

r.post('/alerts/:id/acknowledge', need('manageAlerts'), async (req, res) => {
  const a = await getAlert(req);
  if (a.status !== 'open') throw conflict('Only open alerts can be acknowledged');
  a.status = 'acknowledged';
  a.acknowledged = { by: req.user._id, at: new Date() };
  applyNote(a, req);
  await a.save();
  res.json(a);
});

r.post('/alerts/:id/resolve', need('manageAlerts'), async (req, res) => {
  const a = await getAlert(req);
  if (a.status === 'resolved') throw conflict('This alert is already resolved');
  a.status = 'resolved';
  a.resolved = { by: req.user._id, at: new Date() };
  if (!a.acknowledged?.at) a.acknowledged = { by: req.user._id, at: new Date() };
  applyNote(a, req);
  await a.save();
  if (a.conversationId) await M.Conversation.updateOne({ _id: a.conversationId }, { isUrgent: false });
  res.json(a);
});

r.post('/alerts/:id/note', need('manageAlerts'), async (req, res) => {
  const a = await getAlert(req);
  if (!req.body.note) throw badRequest('Write a note');
  applyNote(a, req);
  await a.save();
  res.json(a);
});

r.post('/alerts', need('manageAlerts'), async (req, res) => {
  await patientInPractice(req, req.body.patientId);
  if (!E.ALERT_SEVERITIES.includes(req.body.severity) || !E.ALERT_KINDS.includes(req.body.kind)) throw badRequest('Choose a severity and kind');
  if (!req.body.detail) throw badRequest('Describe the alert');
  const { raiseAlert } = require('../services/care');
  res.status(201).json(await raiseAlert({ practiceId: req.practiceId, ...pick(req.body, ['patientId', 'severity', 'kind', 'title', 'detail']) }));
});

module.exports = r;

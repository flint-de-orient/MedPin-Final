// Doctor-FollowUps, Report-Referrals, Alerts.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice, ownPractice } = require('../middleware/auth');
const { badRequest, notFound, conflict, forbidden, list, escapeRegex, pick } = require('../lib/http');
const { notify, signal } = require('../services/notify');
const { sendWhatsApp } = require('../services/push');

const r = Router();
r.use(requireAuth, staff());

// ── Follow-ups ──
r.get('/follow-ups', async (req, res) => {
  const today = T.dayStart();
  const q = { practiceId: req.practiceId, status: { $in: ['not_booked', 'no_reply', 'booked', 'reports_in'] } };
  // "Reports in" is booked only once its report-review visit is; without one it still needs booking.
  if (req.query.tab === 'not_booked') Object.assign(q, { status: { $in: ['not_booked', 'no_reply', 'reports_in'] }, $or: [{ status: { $ne: 'reports_in' } }, { appointmentId: null }] });
  if (req.query.tab === 'booked') Object.assign(q, { status: { $in: ['booked', 'reports_in'] }, $or: [{ status: 'booked' }, { appointmentId: { $ne: null } }] });
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
    counts: (() => {
      const booked = (x) => x.status === 'booked' || (x.status === 'reports_in' && x.appointmentId);
      return { all: rows.length, notBooked: rows.filter((x) => !booked(x)).length, booked: rows.filter(booked).length };
    })(),
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
  const q = { practiceId: req.practiceId, status: { $in: ['not_booked', 'no_reply', 'reports_in'] }, appointmentId: null, ...(ids.length ? { _id: { $in: ids } } : { dueDate: { $lte: T.addDays(T.dayStart(), 7) } }) };
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
r.get('/referrals', need('clinical'), async (req, res) => {
  const direction = req.query.direction || 'sent';
  // Optional period (range=… or from/to, like the reports); default = all time.
  // Location / doctor filters from the Reports filter sheet.
  const period = {};
  if (req.query.range || req.query.from || req.query.to) {
    const { rangeOf } = require('./reports');
    const { from, to } = rangeOf(req.query);
    period.referredAt = { $gte: from, $lt: to };
  }
  const locs = list(req.query.locationIds).filter((x) => /^[0-9a-f]{24}$/i.test(x));
  if (locs.length) period.locationId = { $in: locs };
  if (req.query.doctorId) period.doctorId = req.query.doctorId === 'me' ? req.user._id : req.query.doctorId;
  await markReceivedSeen(req.practiceId);
  await fillLocations(req.practiceId);
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

/** Older referrals made before locations were kept: the patient's latest visit here. */
async function fillLocations(practiceId) {
  const missing = await M.Referral.find({ practiceId, locationId: null }, 'patientId').limit(200);
  for (const ref of missing) {
    const last = await M.Appointment.findOne({ practiceId, patientId: ref.patientId, locationId: { $ne: null } }, 'locationId').sort({ startAt: -1 });
    if (last) await M.Referral.updateOne({ _id: ref._id }, { locationId: last.locationId });
  }
}

/** Received and still awaiting, but the patient has since been seen here: seen, on that day. */
async function markReceivedSeen(practiceId) {
  const open = await M.Referral.find({ practiceId, direction: 'received', status: 'awaiting' }, 'patientId referredAt').limit(500);
  for (const ref of open) {
    const visit = await M.Appointment.findOne({ practiceId, patientId: ref.patientId, status: 'completed', completedAt: { $gte: ref.referredAt } }, 'completedAt').sort({ completedAt: 1 });
    if (visit) await M.Referral.updateOne({ _id: ref._id, status: 'awaiting' }, { status: 'seen', seenAt: visit.completedAt });
  }
}

r.post('/referrals', need('clinical'), async (req, res) => {
  await patientInPractice(req, req.body.patientId);
  if (!E.REFERRAL_DIRECTIONS.includes(req.body.direction)) throw badRequest('Choose sent or received');
  const name = String(req.body.counterpartName || '').trim();
  if (!name) throw badRequest('Enter who it is to / from');
  // Where the patient is seen: the location given, else their latest visit here.
  let locationId = /^[0-9a-f]{24}$/i.test(String(req.body.locationId || '')) ? req.body.locationId : null;
  if (!locationId) {
    const last = await M.Appointment.findOne({ practiceId: req.practiceId, patientId: req.body.patientId, locationId: { $ne: null } }, 'locationId').sort({ startAt: -1 });
    locationId = last?.locationId || null;
  }
  const clip = (s, n) => (s == null ? undefined : String(s).trim().slice(0, n) || undefined);
  const ref = await M.Referral.create({
    patientId: req.body.patientId, direction: req.body.direction, counterpartName: name.slice(0, 120),
    counterpartUserId: req.body.counterpartUserId || undefined, specialty: clip(req.body.specialty, 60), reason: clip(req.body.reason, 200),
    consultationId: req.body.consultationId || undefined,
    practiceId: req.practiceId, doctorId: req.user._id, locationId,
  });
  res.status(201).json(ref);
});

r.post('/referrals/:id/cancel', need('clinical'), async (req, res) => {
  const ref = ownPractice(req, await M.Referral.findById(req.params.id), 'Referral');
  if (ref.status !== 'awaiting') throw conflict('Only an awaiting referral can be cancelled');
  ref.status = 'cancelled';
  ref.cancelledAt = new Date();
  await ref.save();
  res.json(ref);
});

r.post('/referrals/:id/seen', need('clinical'), async (req, res) => {
  const ref = ownPractice(req, await M.Referral.findById(req.params.id), 'Referral');
  if (ref.status === 'cancelled') throw conflict('This referral was cancelled');
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
  let items = await M.Alert.find(q).sort({ createdAt: -1 }).limit(300).populate('patientId', 'name gender ageYears ageRecordedAt conditions userId').populate('noteBy', 'name').populate('deskNotes.by', 'name');
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    items = items.filter((a) => re.test(a.patientId?.name || ''));
  }
  items.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || ['open', 'acknowledged', 'resolved'].indexOf(a.status) - ['open', 'acknowledged', 'resolved'].indexOf(b.status) || b.createdAt - a.createdAt);
  const counts = await M.Alert.aggregate([{ $match: { practiceId: req.practiceId } }, { $group: { _id: '$status', n: { $sum: 1 } } }]);
  const photos = await require('../services/photos').photosFor(items.map((a) => a.patientId?.userId));
  res.json({
    counts: Object.fromEntries(counts.map((c) => [c._id, c.n])),
    items: items.map((a) => ({
      ...a.toJSON(),
      patient: a.patientId && {
        id: a.patientId._id, name: a.patientId.name, age: T.ageFrom(a.patientId), gender: a.patientId.gender, conditions: a.patientId.conditions.map((c) => c.name),
        photo: a.patientId.userId ? photos.get(String(a.patientId.userId)) || null : null,
      },
      acknowledgedToday: a.acknowledged?.at && T.dayKey(a.acknowledged.at) === T.dayKey(new Date()),
      // The front desk's notes ("Doctor informed · Tania, 9:20 AM").
      deskNotes: (a.deskNotes || []).map((n) => ({ text: n.text, at: n.at, by: n.by?.name || null })),
    })),
  });
});

/** Notifications about this alert (and, for an urgent chat, that chat's urgent messages). */
const alertNotes = (a) => {
  const ids = (x) => [x, String(x)];
  return {
    practiceId: a.practiceId,
    $or: [
      { 'params.alertId': { $in: ids(a._id) } },
      ...(a.conversationId ? [{ 'params.conversationId': { $in: ids(a.conversationId) }, type: /emergency|urgent/ }] : []),
    ],
  };
};

/** Marks those notifications read for [userIds] (everyone when null); their bells and lists update at once. */
async function clearAlertNotes(a, userIds = null) {
  const q = { ...alertNotes(a), readAt: null, ...(userIds ? { userId: { $in: userIds } } : {}) };
  const who = await M.Notification.distinct('userId', q);
  if (!who.length) return;
  await M.Notification.updateMany(q, { readAt: new Date() });
  await signal(who, { type: 'notifications_changed', practiceId: String(a.practiceId) });
}

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
  // Seen: off my bell. It stays red for the others until it's resolved.
  await clearAlertNotes(a, [req.user._id]);
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
  // Everyone told about it (doctors, assistants, the desk): read now, so every bell's red dot
  // clears at once. The desk who had it gets a quiet "Resolved by Dr. Sen" (no buzz).
  const told = (await M.Notification.distinct('userId', alertNotes(a))).map(String);
  await clearAlertNotes(a);
  const clinical = new Set((await M.Member.find({ practiceId: a.practiceId, userId: { $in: told }, status: 'active', role: { $in: ['doctor', 'doctor_assistant'] } }, 'userId')).map((m) => String(m.userId)));
  const desk = told.filter((id) => id !== String(req.user._id) && !clinical.has(id));
  if (desk.length) {
    const { shortName } = require('../services/care');
    const patient = await M.Patient.findById(a.patientId, 'name');
    await notify(desk, {
      type: 'alert_resolved', push: false, practiceId: a.practiceId, title: `Resolved by ${shortName(req.user.name) || 'the doctor'}`,
      body: `${patient?.name || 'Patient'}: ${a.detail}`.slice(0, 160), screen: 'Patient-Thread',
      params: { patientId: a.patientId, ...(a.conversationId ? { conversationId: a.conversationId } : {}) },
    });
  }
  if (a.conversationId) {
    const convo = await M.Conversation.findById(a.conversationId, 'participants');
    if (convo) await signal(convo.participants.filter((p) => p.role !== 'patient').map((p) => p.userId), { type: 'chat_changed', conversationId: a.conversationId });
  }
  res.json(a);
});

// The front desk on a patient's emergency: "Doctor informed" (or another short note). The doctor
// sees it on the alert; it never acknowledges or resolves it — only a clinician does that.
r.post('/alerts/:id/desk-note', need('chats'), async (req, res) => {
  const a = await getAlert(req);
  if (a.kind !== 'urgent_chat' && !a.escalatedAt) throw forbidden('Only the doctor handles this alert');
  if (a.status === 'resolved') throw conflict('This alert is already resolved', 'ALREADY_RESOLVED');
  const text = String(req.body.note || 'Doctor informed').trim().slice(0, 300) || 'Doctor informed';
  a.deskNotes.push({ text, by: req.user._id, at: new Date() });
  await a.save();
  // The doctors' Alerts screens and the thread refresh at once.
  const { clinicians, assistantsOf } = require('../services/notify');
  const doctors = await clinicians(a.practiceId, a.patientId, { doctorId: a.doctorId });
  await signal([...doctors, ...(await assistantsOf(a.practiceId, doctors))], { type: 'alerts_changed', alertId: String(a._id) });
  if (a.conversationId) await signal([req.user._id], { type: 'chat_changed', conversationId: String(a.conversationId) });
  res.json({ ok: true, deskNotes: a.deskNotes.map((n) => ({ text: n.text, at: n.at, by: String(n.by) === String(req.user._id) ? req.user.name : null })) });
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

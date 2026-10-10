// Doctor-Dashboard, Doctor-Home, Home-States, Cards-Clinical, Cards-Analytics,
// Doctor-Reports(+Filter), Report-Consultations/Prescriptions/Fees/FollowUps, Daily-Report.
// Everything here is computed from live data; nothing is stored.
const { Router } = require('express');
const M = require('../models');
const T = require('../lib/time');
const { requireAuth, staff, need } = require('../middleware/auth');
const { list, escapeRegex } = require('../lib/http');

const r = Router();
r.use(requireAuth, staff());
r.use('/reports', need('reports'));
r.use('/dashboard', need('clinical'));

const AGE_GROUPS = { under_18: [0, 17], '18_40': [18, 40], '41_60': [41, 60], over_60: [61, 200] };
const ageGroupOf = (age) => Object.keys(AGE_GROUPS).find((k) => age != null && age >= AGE_GROUPS[k][0] && age <= AGE_GROUPS[k][1]);

/** Date range + filters from the query (Doctor-Reports-Filter). */
function rangeOf(q) {
  const today = T.dayStart();
  const preset = q.range || '30_days';
  let from;
  let to = T.addDays(today, 1);
  if (q.from) from = T.parseDay(q.from);
  else if (preset === 'today') from = today;
  else if (preset === '7_days') from = T.addDays(today, -6);
  else if (preset === 'this_month') from = new Date(`${T.dayKey(today).slice(0, 7)}-01T00:00:00+05:30`);
  else if (preset === 'this_year') from = new Date(`${T.dayKey(today).slice(0, 4)}-01-01T00:00:00+05:30`);
  else from = T.addDays(today, -29);
  if (q.to) to = T.addDays(T.parseDay(q.to), 1);
  const len = to - from;
  return { from, to, prevFrom: new Date(from - len), prevTo: from };
}

const filtersOf = (q) => ({
  locationIds: list(q.locationIds),
  visitTypes: list(q.visitTypes),
  modes: list(q.modes),
  ageGroups: list(q.ageGroups),
  doctorId: q.doctorId,
});

/** Completed visits in range, filtered, with patient age attached. */
async function visits(req, from, to, f, extra = {}) {
  const q = { practiceId: req.practiceId, date: { $gte: from, $lt: to }, ...extra };
  if (!extra.status) q.status = 'completed';
  if (f.locationIds.length) q.locationId = { $in: f.locationIds };
  if (f.visitTypes.length) q.visitType = { $in: f.visitTypes };
  if (f.modes.length) q.mode = { $in: f.modes };
  if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
  const rows = await M.Appointment.find(q).populate('patientId', 'name phone gender ageYears ageRecordedAt dateOfBirth createdAt conditions').populate('locationId', 'name shortName').lean();
  return rows
    .map((a) => ({ ...a, age: a.patientId ? T.ageFrom(a.patientId) : null }))
    .filter((a) => !f.ageGroups.length || f.ageGroups.includes(ageGroupOf(a.age)));
}

const avg = (arr) => (arr.length ? arr.reduce((s, x) => s + x, 0) / arr.length : null);
const consultMin = (a) => (a.consultStartedAt && a.completedAt ? (new Date(a.completedAt) - new Date(a.consultStartedAt)) / 60000 : null);
const delta = (now, prev) => (prev ? Math.round(((now - prev) / prev) * 100) : null);
const countBy = (rows, key) => Object.entries(rows.reduce((acc, x) => { const k = key(x) ?? 'other'; acc[k] = (acc[k] || 0) + 1; return acc; }, {})).map(([k, n]) => ({ key: k, count: n })).sort((a, b) => b.count - a.count);

async function kpis(req, from, to, f) {
  const done = await visits(req, from, to, f);
  const missed = await visits(req, from, to, f, { status: 'missed' });
  const ids = done.map((a) => a._id);
  const [rxCount, paid] = await Promise.all([
    M.Prescription.countDocuments({ practiceId: req.practiceId, kind: 'digital', issuedAt: { $gte: from, $lt: to } }),
    M.Payment.aggregate([{ $match: { practiceId: req.practiceId, status: 'paid', paidAt: { $gte: from, $lt: to } } }, { $group: { _id: null, sum: { $sum: '$amount' } } }]),
  ]);
  const times = done.map(consultMin).filter((x) => x != null);
  return {
    done, ids,
    consultations: done.length,
    newPatients: done.filter((a) => a.visitType === 'new').length,
    avgConsultMin: times.length ? Math.round(avg(times)) : null,
    missed: missed.length,
    missedPct: done.length + missed.length ? Math.round((missed.length / (done.length + missed.length)) * 100) : 0,
    prescriptions: rxCount,
    prescriptionPct: done.length ? Math.round((rxCount / done.length) * 100) : 0,
    feesCollected: paid[0]?.sum || 0,
  };
}

r.get('/reports/summary', async (req, res) => {
  const { from, to, prevFrom, prevTo } = rangeOf(req.query);
  const f = filtersOf(req.query);
  const now = await kpis(req, from, to, f);
  const prev = req.query.compare === 'false' ? null : await kpis(req, prevFrom, prevTo, f);
  const consults = await M.Consultation.find({ appointmentId: { $in: now.ids } }, 'diagnoses').lean();
  const perDay = {};
  for (let d = from; d < to; d = T.addDays(d, 1)) perDay[T.dayKey(d)] = 0;
  for (const a of now.done) perDay[T.dayKey(a.date)] = (perDay[T.dayKey(a.date)] || 0) + 1;
  const fu = await M.FollowUp.find({ practiceId: req.practiceId, dueDate: { $gte: from, $lt: to }, outcome: { $ne: null } }, 'outcome').lean();
  const cmp = (k) => (prev ? { previous: prev[k], changePct: delta(now[k], prev[k]) } : {});
  res.json({
    range: { from, to, previousFrom: prev ? prevFrom : null, previousTo: prev ? prevTo : null },
    kpis: {
      consultations: { value: now.consultations, ...cmp('consultations') },
      newPatients: { value: now.newPatients, ...(prev ? { previous: prev.newPatients, change: now.newPatients - prev.newPatients } : {}) },
      avgConsultMin: { value: now.avgConsultMin, ...(prev ? { previous: prev.avgConsultMin } : {}) },
      missed: { value: now.missed, pct: now.missedPct },
      prescriptions: { value: now.prescriptions, pctOfConsultations: now.prescriptionPct },
      feesCollected: { value: now.feesCollected, ...cmp('feesCollected') },
    },
    byLocation: countBy(now.done, (a) => a.locationId?.shortName || a.locationId?.name),
    byVisitType: countBy(now.done, (a) => a.visitType),
    byMode: countBy(now.done, (a) => a.mode),
    byAgeGroup: countBy(now.done, (a) => ageGroupOf(a.age)),
    topDiagnoses: countBy(consults.flatMap((c) => c.diagnoses.map((d) => ({ name: d.name }))), (d) => d.name).slice(0, 8),
    perDay: Object.entries(perDay).map(([date, count]) => ({ date, count })),
    followUpCompliancePct: fu.length ? Math.round((fu.filter((x) => x.outcome === 'on_time').length / fu.length) * 100) : null,
  });
});

// Filter sheet: "Show N consultations" and per-option counts.
r.get('/reports/filter-counts', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  const all = await visits(req, from, to, { locationIds: [], visitTypes: [], modes: [], ageGroups: [] });
  const matching = await visits(req, from, to, filtersOf(req.query));
  res.json({
    matching: matching.length,
    location: countBy(all, (a) => String(a.locationId?._id)),
    visitType: countBy(all, (a) => a.visitType),
    mode: countBy(all, (a) => a.mode),
    ageGroup: countBy(all, (a) => ageGroupOf(a.age)),
  });
});

r.get('/reports/consultations', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  let rows = await visits(req, from, to, filtersOf(req.query));
  const consults = await M.Consultation.find({ appointmentId: { $in: rows.map((a) => a._id) } }, 'appointmentId diagnoses chiefComplaint').lean();
  const cmap = new Map(consults.map((c) => [String(c.appointmentId), c]));
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    rows = rows.filter((a) => re.test(a.patientId?.name || '') || re.test(a.patientId?.phone || '') || (cmap.get(String(a._id))?.diagnoses || []).some((d) => re.test(d.name)));
  }
  const items = rows.sort((a, b) => new Date(b.startAt) - new Date(a.startAt)).map((a) => ({
    appointmentId: a._id, date: a.date, startAt: a.consultStartedAt || a.startAt,
    patient: { id: a.patientId?._id, name: a.patientId?.name, age: a.age, gender: a.patientId?.gender, phone: req.query.includeMobiles === 'true' ? a.patientId?.phone : undefined },
    visitType: a.visitType, mode: a.mode, location: a.locationId?.shortName || a.locationId?.name,
    diagnoses: (cmap.get(String(a._id))?.diagnoses || []).map((d) => d.name),
    durationMin: consultMin(a) != null ? Math.round(consultMin(a)) : null,
    fee: a.fee, feeStatus: a.feeStatus,
  }));
  const times = rows.map(consultMin).filter((x) => x != null);
  res.json({
    totals: { consultations: rows.length, avgMin: times.length ? Math.round(avg(times)) : null, feesBilled: rows.reduce((s, a) => s + (a.fee || 0), 0) },
    items,
  });
});

r.get('/reports/prescriptions', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  const q = { practiceId: req.practiceId, kind: 'digital', issuedAt: { $gte: from, $lt: to } };
  if (req.query.doctorId) q.doctorId = req.query.doctorId === 'me' ? req.user._id : req.query.doctorId;
  const f = filtersOf(req.query);
  if (f.locationIds.length || f.visitTypes.length || f.modes.length || f.ageGroups.length) {
    // Only prescriptions from visits that match the filters.
    const appts = await visits(req, T.addDays(from, -1), to, f);
    q.consultationId = { $in: await M.Consultation.find({ appointmentId: { $in: appts.map((a) => a._id) } }).distinct('_id') };
  }
  let rx = await M.Prescription.find(q).sort({ issuedAt: -1 }).populate('patientId', 'name').lean();
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    rx = rx.filter((p) => re.test(p.patientId?.name || '') || p.items.some((i) => re.test(i.name)) || re.test(String(p.rxNumber).padStart(4, '0')));
  }
  const meds = countBy(rx.flatMap((p) => p.items), (i) => `${i.name}${i.strength ? ` ${i.strength}` : ''}`);
  const tests = countBy(rx.flatMap((p) => p.tests.map((t) => ({ t }))), (x) => x.t);
  res.json({
    totals: { prescriptions: rx.length, medicines: rx.reduce((s, p) => s + p.items.length, 0), labTests: rx.reduce((s, p) => s + p.tests.length, 0) },
    topMedicines: meds.slice(0, 10),
    topTests: tests.slice(0, 10),
    items: rx.map((p) => ({ id: p._id, patientId: p.patientId?._id, rxNumber: String(p.rxNumber).padStart(4, '0'), issuedAt: p.issuedAt, patient: p.patientId?.name, medicines: p.items.map((i) => `${i.name} ${i.strength || ''}`.trim()), tests: p.tests })),
  });
});

r.get('/reports/fees', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  const rows = await visits(req, from, to, filtersOf(req.query));
  const payments = await M.Payment.find({ practiceId: req.practiceId, createdAt: { $gte: from, $lt: to } }).populate('patientId', 'name').populate('locationId', 'name shortName').populate('appointmentId', 'startAt mode').lean();
  const paid = payments.filter((p) => p.status === 'paid');
  const sumBy = (arr, key) => Object.entries(arr.reduce((acc, x) => { const k = key(x) || 'other'; acc[k] = (acc[k] || 0) + x.amount; return acc; }, {})).map(([k, amount]) => ({ key: k, amount }));
  res.json({
    billed: rows.reduce((s, a) => s + (a.fee || 0), 0),
    collected: paid.reduce((s, p) => s + p.amount, 0),
    pendingAmount: payments.filter((p) => p.status === 'pending').reduce((s, p) => s + p.amount, 0),
    freeVisits: rows.filter((a) => !a.fee).length,
    billedByLocation: sumBy(rows.map((a) => ({ amount: a.fee || 0, loc: a.locationId?.shortName || a.locationId?.name })), (x) => x.loc),
    collectedByMethod: sumBy(paid, (p) => p.method),
    pending: payments.filter((p) => p.status === 'pending').map((p) => ({ id: p._id, patientId: p.patientId?._id, patient: p.patientId?.name, date: p.appointmentId?.startAt || p.createdAt, location: p.locationId?.shortName || p.locationId?.name, mode: p.appointmentId?.mode, amount: p.amount, linkSentAt: p.paymentLinkSentAt })),
  });
});

r.get('/reports/follow-ups', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  const fus = await M.FollowUp.find({ practiceId: req.practiceId, dueDate: { $gte: from, $lt: to } }).populate('patientId', 'name phone gender ageYears ageRecordedAt conditions').lean();
  const today = T.dayStart();
  const outcome = (f) => f.outcome || (f.dueDate < T.addDays(today, -3) && !['completed', 'booked'].includes(f.status) ? 'missed' : 'pending');
  const decided = fus.filter((f) => outcome(f) !== 'pending');
  const byCondition = {};
  for (const f of decided) {
    for (const c of f.patientId?.conditions || []) {
      byCondition[c.name] = byCondition[c.name] || { onTime: 0, total: 0 };
      byCondition[c.name].total += 1;
      if (outcome(f) === 'on_time') byCondition[c.name].onTime += 1;
    }
  }
  res.json({
    due: fus.length,
    onTime: fus.filter((f) => outcome(f) === 'on_time').length,
    late: fus.filter((f) => outcome(f) === 'late').length,
    missed: fus.filter((f) => outcome(f) === 'missed').length,
    onTimePct: decided.length ? Math.round((decided.filter((f) => outcome(f) === 'on_time').length / decided.length) * 100) : null,
    byCondition: Object.entries(byCondition).map(([condition, v]) => ({ condition, onTimePct: Math.round((v.onTime / v.total) * 100), total: v.total })).sort((a, b) => b.total - a.total),
    missedList: fus.filter((f) => outcome(f) === 'missed').map((f) => ({
      id: f._id, patient: f.patientId && { id: f.patientId._id, name: f.patientId.name, phone: f.patientId.phone, age: T.ageFrom(f.patientId), gender: f.patientId.gender, condition: f.patientId.conditions?.[0]?.name },
      dueDate: f.dueDate, daysLate: Math.round((today - f.dueDate) / T.DAY_MS),
    })),
  });
});

r.get('/reports/daily', async (req, res) => {
  const day = T.parseDay(req.query.date);
  const q = { practiceId: req.practiceId, startedAt: { $gte: day, $lt: T.addDays(day, 1) }, status: { $ne: 'draft' } };
  if (req.member.role === 'doctor' && req.query.all !== 'true') q.doctorId = req.user._id;
  const consults = await M.Consultation.find(q).sort({ startedAt: 1 }).populate('patientId', 'name gender ageYears ageRecordedAt dateOfBirth createdAt').populate('vitalsId').populate('appointmentId', 'visitType').populate('prescriptionId').lean();
  res.json({
    date: day,
    summary: { consultations: consults.length, new: consults.filter((c) => c.appointmentId?.visitType === 'new').length, followUp: consults.filter((c) => c.appointmentId?.visitType === 'follow_up').length },
    items: consults.map((c) => ({
      id: c._id, seenAt: c.startedAt, patient: c.patientId && { id: c.patientId._id, name: c.patientId.name, age: T.ageFrom(c.patientId), gender: c.patientId.gender },
      isNew: c.appointmentId?.visitType === 'new', complaint: c.chiefComplaint, diagnosis: c.diagnoses.map((d) => d.name).join(', '),
      vitals: c.vitalsId && { bp: c.vitalsId.bpSystolic ? `${c.vitalsId.bpSystolic}/${c.vitalsId.bpDiastolic}` : null, pulse: c.vitalsId.pulse, spo2: c.vitalsId.spo2, weightKg: c.vitalsId.weightKg },
      medicines: (c.prescriptionId?.items || c.medications).map((i) => ({ name: `${i.name} ${i.strength || ''}`.trim(), pattern: `${i.dose?.morning || 0}-${i.dose?.afternoon || 0}-${i.dose?.night || 0}`, frequency: i.frequency, foodRelation: i.foodRelation, duration: i.duration })),
      advice: c.prescriptionId?.advice || c.advice?.freeText, followUpDate: c.prescriptionId?.followUpDate || c.followUp?.date,
    })),
  });
});

// ── Home / dashboard ──
r.get('/dashboard', async (req, res) => {
  const today = T.dayStart();
  const week = T.addDays(today, -6);
  const mine = req.member.role === 'doctor' ? { doctorId: req.user._id } : {};
  const [todayAppts, last7, alerts, reviews, unread, nutrition, flaggedChats, aiMsgs] = await Promise.all([
    M.Appointment.find({ practiceId: req.practiceId, date: today, status: { $nin: ['cancelled', 'rescheduled'] }, ...mine }).lean(),
    M.Appointment.find({ practiceId: req.practiceId, date: { $gte: week }, status: 'completed', ...mine }).lean(),
    M.Alert.find({ practiceId: req.practiceId, status: 'open' }).sort({ createdAt: -1 }).limit(5).populate('patientId', 'name'),
    M.ChatReview.countDocuments({ practiceId: req.practiceId, status: 'needs_review' }),
    M.Conversation.countDocuments({ practiceId: req.practiceId, participants: { $elemMatch: { userId: req.user._id, unreadCount: { $gt: 0 } } } }),
    M.HealthLog.countDocuments({ sharedWith: req.user._id, type: 'meal', 'review.at': null, loggedAt: { $gte: T.addDays(today, -7) } }),
    M.ChatReview.countDocuments({ practiceId: req.practiceId, status: 'needs_review', createdAt: { $gte: week } }),
    M.Message.countDocuments({ senderType: 'ai', createdAt: { $gte: week }, conversationId: { $in: await M.Conversation.find({ practiceId: req.practiceId }).distinct('_id') } }),
  ]);
  const appIds = await M.Patient.find({ _id: { $in: await M.PatientEnrolment.find({ practiceId: req.practiceId, status: 'linked' }).distinct('patientId') }, userId: { $type: 'objectId' } }).distinct('_id');
  const active = new Set([
    ...(await M.HealthLog.find({ patientId: { $in: appIds }, loggedAt: { $gte: T.addDays(today, -7) } }).distinct('patientId')),
    ...(await M.Vitals.find({ patientId: { $in: appIds }, source: 'home', recordedAt: { $gte: T.addDays(today, -7) } }).distinct('patientId')),
  ].map(String));
  const count = (...s) => todayAppts.filter((a) => s.includes(a.status)).length;
  const times = last7.map(consultMin).filter((x) => x != null);
  const user = await M.User.findById(req.user._id, 'name');
  const location = req.user.activeLocationId ? await M.Location.findById(req.user.activeLocationId, 'name shortName') : null;
  const practice = await M.Practice.findById(req.practiceId, 'name');
  // "Set up your clinic" for doctors until every step is done.
  let setup;
  if (req.member.role === 'doctor') {
    const [prof, pinned, patients, team] = await Promise.all([
      M.DoctorProfile.findOne({ userId: req.user._id }, 'signature photo'),
      M.Location.exists({ practiceId: req.practiceId, status: 'active', geo: { $exists: true } }),
      M.PatientEnrolment.countDocuments({ practiceId: req.practiceId, status: 'linked' }),
      M.Member.countDocuments({ practiceId: req.practiceId, status: 'active' }),
    ]);
    const steps = [
      { key: 'signature', title: 'Add your signature', detail: 'Needed to issue prescriptions', screen: 'Profile', done: Boolean(prof?.signature?.key) },
      { key: 'photo', title: 'Add a profile photo', detail: 'Patients see it when they book', screen: 'Doctor-MyProfile', done: Boolean(prof?.photo?.key) },
      { key: 'pin', title: 'Pin your clinic on the map', detail: 'For “near me” search and directions', screen: 'Profile-Location', done: Boolean(pinned) },
      { key: 'patient', title: 'Add your first patient', detail: 'Or share your booking link', screen: 'Add-Patient', done: patients > 0 },
      ...(req.member.isOwner ? [{ key: 'team', title: 'Invite your front desk', detail: 'Optional · if someone helps you', screen: 'People-Add', done: team > 1, optional: true }] : []),
    ];
    if (steps.some((x) => !x.done && !x.optional)) setup = { done: steps.filter((x) => x.done).length, total: steps.length, steps };
  }
  res.json({
    setup,
    greetingName: user.name,
    date: today,
    practiceName: practice?.name,
    location: location && (location.shortName || location.name),
    unreadNotifications: await M.Notification.countDocuments({ userId: req.user._id, practiceId: req.practiceId, readAt: null }),
    today: { total: todayAppts.length, pending: count('booked', 'confirmed', 'waiting', 'in_consultation'), waiting: count('waiting'), completed: count('completed') },
    actionQueue: { unreadMessages: unread, checkInsOverdue: appIds.filter((id) => !active.has(String(id))).length, pendingActions: alerts.length + reviews, nutritionReviewsDue: nutrition },
    alerts: alerts.map((a) => ({ id: a._id, severity: a.severity, kind: a.kind, patient: a.patientId?.name, patientId: a.patientId?._id, conversationId: a.conversationId, detail: a.detail, at: a.createdAt })),
    last7Days: { consultations: last7.length, avgConsultMin: times.length >= 3 ? Math.round(avg(times)) : null },
    aiChats: { handled: aiMsgs - flaggedChats, escalated: flaggedChats },
    updatedAt: new Date(),
  });
});

// Clinical and analytics cards.
r.get('/dashboard/cards', async (req, res) => {
  const today = T.dayStart();
  const patientIds = await M.PatientEnrolment.find({ practiceId: req.practiceId, status: 'linked' }).distinct('patientId');
  const [labs30, readings90, patients, ldl, ecg, hr30] = await Promise.all([
    M.LabResult.find({ patientId: { $in: patientIds }, collectedAt: { $gte: T.addDays(today, -30) } }, 'values').lean(),
    M.Vitals.aggregate([
      { $match: { patientId: { $in: patientIds }, recordedAt: { $gte: T.addDays(today, -90) }, bpSystolic: { $ne: null } } },
      { $sort: { recordedAt: -1 } },
      { $group: { _id: '$patientId', sys: { $first: '$bpSystolic' }, dia: { $first: '$bpDiastolic' } } },
    ]),
    M.Patient.find({ _id: { $in: patientIds } }, 'conditions').lean(),
    M.LabResult.aggregate([
      { $match: { patientId: { $in: patientIds } } },
      { $unwind: '$values' },
      { $match: { 'values.analyte': /^LDL/i } },
      { $sort: { collectedAt: -1 } },
      { $group: { _id: '$patientId', value: { $first: '$values.value' } } },
    ]),
    M.LabResult.aggregate([
      { $match: { patientId: { $in: patientIds }, ecgInterpretation: { $ne: null }, collectedAt: { $gte: T.addDays(today, -180) } } },
      { $group: { _id: '$ecgInterpretation', n: { $sum: 1 } } },
    ]),
    M.Vitals.countDocuments({ patientId: { $in: patientIds }, recordedAt: { $gte: T.addDays(today, -30) }, $or: [{ pulse: { $lt: 50 } }, { pulse: { $gt: 100 } }] }),
  ]);
  const flags = { critical: 0, high: 0, low: 0, normal: 0 };
  for (const l of labs30) for (const v of l.values) flags[v.flag] = (flags[v.flag] || 0) + 1;
  const bp = { normal: 0, elevated: 0, stage1: 0, stage2: 0 };
  for (const x of readings90) {
    if (x.sys >= 140 || x.dia >= 90) bp.stage2 += 1;
    else if (x.sys >= 130 || x.dia >= 80) bp.stage1 += 1;
    else if (x.sys >= 120) bp.elevated += 1;
    else bp.normal += 1;
  }
  const registry = countBy(patients.flatMap((p) => p.conditions.map((c) => ({ c: c.name }))), (x) => x.c);
  const ldlBuckets = { under_100: 0, '100_129': 0, '130_159': 0, '160_plus': 0 };
  for (const x of ldl) {
    if (x.value == null) continue;
    if (x.value < 100) ldlBuckets.under_100 += 1;
    else if (x.value < 130) ldlBuckets['100_129'] += 1;
    else if (x.value < 160) ldlBuckets['130_159'] += 1;
    else ldlBuckets['160_plus'] += 1;
  }
  res.json({
    patients: patientIds.length,
    labFlags30d: { ...flags, total: Object.values(flags).reduce((a, b) => a + b, 0) },
    bpControl90d: { ...bp, noReading: patientIds.length - readings90.length },
    conditionRegistry: registry,
    noCondition: patients.filter((p) => !p.conditions.length).length,
    ldl: { ...ldlBuckets, withResult: ldl.length, target: 100 },
    ecg180d: Object.fromEntries(ecg.map((e) => [e._id, e.n])),
    heartRateFlags30d: hr30,
  });
});

module.exports = r;
module.exports.rangeOf = rangeOf;
module.exports.filtersOf = filtersOf;
module.exports.visits = visits;

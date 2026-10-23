// Doctor-Dashboard, Doctor-Home, Home-States, Cards-Clinical, Cards-Analytics,
// Doctor-Reports(+Filter), Report-Consultations/Prescriptions/Fees/FollowUps, Daily-Report,
// and the Report-Referrals "Add a referral" doctor search and suggestions.
// Everything here is computed from live data; nothing is stored.
const { Router } = require('express');
const { Types } = require('mongoose');
const M = require('../models');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice } = require('../middleware/auth');
const { list, escapeRegex } = require('../lib/http');
const { accessFor } = require('../services/access');

const r = Router();
r.use(requireAuth, staff());
r.use('/reports', need('reports'));
r.use('/dashboard', need('clinical'));

// Reports are also for the practice manager, who isn't clinical staff: they get the counts
// and money, not each patient's diagnoses, medicines or conditions.
const seesClinical = (req) => Boolean(req.member?.isOwner || req.perms?.clinical);

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
  if (!extra.status) {
    // A visit counts on the day it happened (seen early / late: its completion day, not the booked day).
    q.status = 'completed';
    delete q.date;
    q.$or = [{ completedAt: { $gte: from, $lt: to } }, { completedAt: null, date: { $gte: from, $lt: to } }];
  }
  if (f.locationIds.length) q.locationId = { $in: f.locationIds };
  if (f.visitTypes.length) q.visitType = { $in: f.visitTypes };
  if (f.modes.length) q.mode = { $in: f.modes };
  if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
  const rows = await M.Appointment.find(q).populate('patientId', PATIENT_FIELDS).populate('locationId', 'name shortName').lean();
  return rows
    .map((a) => ({ ...a, age: a.patientId ? T.ageFrom(a.patientId) : null }))
    .filter((a) => !f.ageGroups.length || f.ageGroups.includes(ageGroupOf(a.age)));
}
const PATIENT_FIELDS = 'name phone gender ageYears ageRecordedAt dateOfBirth createdAt conditions';
const OPEN_VISIT = ['booked', 'confirmed', 'waiting', 'in_consultation', 'missed'];

/**
 * Everyone seen in range: completed visits, plus issued consultations that no
 * completed visit stands for — a consult the doctor started straight from a
 * patient (no appointment), or one whose visit was never closed. A consult
 * with a completed visit counts once, as that visit. Consult rows carry
 * `viaConsult` and `apptId` (their visit, if any) and the visit's type, mode
 * and fee; without a visit they are "new" when it is the patient's first time
 * seen here, and in clinic.
 */
async function seenVisits(req, from, to, f) {
  const done = await visits(req, from, to, f);
  const q = { practiceId: req.practiceId, status: { $in: ['issued', 'sent'] }, completedAt: { $gte: from, $lt: to } };
  if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
  const consults = (await M.Consultation.find(q, 'patientId doctorId locationId appointmentId startedAt completedAt')
    .populate('patientId', PATIENT_FIELDS)
    .populate('appointmentId', 'status visitType mode fee feeStatus locationId startAt consultStartedAt')
    .lean())
    .filter((c) => c.patientId && c.appointmentId?.status !== 'completed');
  if (!consults.length) return done;
  const patientIds = [...new Set(consults.map((c) => String(c.patientId._id)))];
  // A consult started from the patient while their booking for that day stayed open is that visit.
  const open = await M.Appointment.find({
    practiceId: req.practiceId, patientId: { $in: patientIds }, status: { $in: OPEN_VISIT },
    date: { $gte: T.addDays(from, -1), $lt: T.addDays(to, 1) },
  }, 'patientId doctorId date status visitType mode fee feeStatus locationId startAt consultStartedAt').lean();
  const claimed = new Set(consults.filter((c) => c.appointmentId).map((c) => String(c.appointmentId._id)));
  const visitOf = (c) => {
    if (c.appointmentId) return c.appointmentId;
    const day = T.dayKey(c.completedAt);
    const same = open.filter((a) => String(a.patientId) === String(c.patientId._id) && T.dayKey(a.date) === day && !claimed.has(String(a._id)));
    const hit = same.find((a) => String(a.doctorId) === String(c.doctorId)) || same[0];
    if (hit) claimed.add(String(hit._id));
    return hit || null;
  };
  // First time seen here (completed visit or issued consult): "new".
  const oids = patientIds.map((id) => new Types.ObjectId(id));
  const [pastVisits, pastConsults] = await Promise.all([
    M.Appointment.aggregate([{ $match: { practiceId: req.practiceId, patientId: { $in: oids }, status: 'completed' } }, { $group: { _id: '$patientId', at: { $min: { $ifNull: ['$completedAt', '$date'] } } } }]),
    M.Consultation.aggregate([{ $match: { practiceId: req.practiceId, patientId: { $in: oids }, status: { $in: ['issued', 'sent'] } } }, { $group: { _id: '$patientId', at: { $min: '$completedAt' } } }]),
  ]);
  const firstSeen = new Map();
  for (const x of [...pastVisits, ...pastConsults]) {
    const k = String(x._id);
    if (x.at && (!firstSeen.has(k) || x.at < firstSeen.get(k))) firstSeen.set(k, x.at);
  }
  const locIds = [];
  const rows = consults.map((c) => {
    const appt = visitOf(c);
    const locationId = c.locationId || appt?.locationId || null;
    if (locationId) locIds.push(locationId);
    const first = firstSeen.get(String(c.patientId._id));
    return {
      _id: c._id, viaConsult: true, apptId: appt?._id || null, patientId: c.patientId, doctorId: c.doctorId, locationId,
      date: c.completedAt, startAt: c.startedAt, consultStartedAt: c.startedAt, completedAt: c.completedAt,
      visitType: appt?.visitType || (!first || first >= c.completedAt ? 'new' : 'follow_up'),
      mode: appt?.mode || 'in_clinic', fee: appt ? appt.fee : null, feeStatus: appt?.feeStatus || null,
      age: T.ageFrom(c.patientId),
    };
  });
  const locs = new Map((await M.Location.find({ _id: { $in: locIds } }, 'name shortName').lean()).map((l) => [String(l._id), l]));
  const extra = rows
    .map((a) => ({ ...a, locationId: a.locationId ? locs.get(String(a.locationId)) || null : null }))
    .filter((a) => !f.locationIds.length || (a.locationId && f.locationIds.includes(String(a.locationId._id))))
    .filter((a) => !f.visitTypes.length || f.visitTypes.includes(a.visitType))
    .filter((a) => !f.modes.length || f.modes.includes(a.mode))
    .filter((a) => !f.ageGroups.length || f.ageGroups.includes(ageGroupOf(a.age)));
  return [...done, ...extra];
}

/** The consultation behind each seen row, keyed by the row's _id (visit id, or the consult's own). */
async function consultsOf(rows, fields) {
  const appts = rows.filter((a) => !a.viaConsult).map((a) => a._id);
  const own = rows.filter((a) => a.viaConsult).map((a) => a._id);
  if (!appts.length && !own.length) return new Map();
  const ownIds = new Set(own.map(String));
  const list = await M.Consultation.find({ $or: [{ appointmentId: { $in: appts } }, { _id: { $in: own } }] }, `${fields} appointmentId status`).lean();
  const out = new Map();
  for (const c of list) {
    const key = ownIds.has(String(c._id)) ? String(c._id) : String(c.appointmentId);
    // A visit with a draft and an issued consult: the issued one.
    if (!out.has(key) || out.get(key).status === 'draft') out.set(key, c);
  }
  return out;
}

/** on_time / late / missed once known; "missed" 3 days after the due date with no visit booked. */
function followUpOutcome(f, today = T.dayStart()) {
  if (f.outcome) return f.outcome;
  if (f.status === 'cancelled') return 'pending';
  return f.dueDate < T.addDays(today, -3) && !['completed', 'booked'].includes(f.status) ? 'missed' : 'pending';
}

const avg = (arr) => (arr.length ? arr.reduce((s, x) => s + x, 0) / arr.length : null);
const consultMin = (a) => (a.consultStartedAt && a.completedAt ? (new Date(a.completedAt) - new Date(a.consultStartedAt)) / 60000 : null);
const delta = (now, prev) => (prev ? Math.round(((now - prev) / prev) * 100) : null);
const countBy = (rows, key) => Object.entries(rows.reduce((acc, x) => { const k = key(x) ?? 'other'; acc[k] = (acc[k] || 0) + 1; return acc; }, {})).map(([k, n]) => ({ key: k, count: n })).sort((a, b) => b.count - a.count);

const hasFilters = (f) => !!(f.locationIds.length || f.visitTypes.length || f.modes.length || f.ageGroups.length || f.doctorId);

/**
 * Booked, didn't come: marked missed, or still booked / confirmed after the day ended.
 * A booking the doctor saw through a consult (`seen` rows' apptId) is not missed.
 */
async function missedVisits(req, from, to, f, seen = []) {
  const today = T.dayStart();
  const came = new Set(seen.filter((a) => a.apptId).map((a) => String(a.apptId)));
  return visits(req, from, to < today ? to : today, f, { status: { $in: ['missed', 'booked', 'confirmed'] } })
    .then((rows) => rows.filter((a) => (a.status === 'missed' || new Date(a.date) < today) && !came.has(String(a._id))));
}

/** Payments of visits that match the filters (all visits in the practice when none are set). */
async function paymentScope(req, from, to, f) {
  if (!hasFilters(f)) return {};
  const appts = await visits(req, T.addDays(from, -31), to, f, { status: { $nin: [] } });
  return { appointmentId: { $in: appts.map((a) => a._id) } };
}

/** Digital prescriptions in range; with filters, only those from matching visits (or the chosen doctor). */
async function rxScope(req, from, to, f) {
  const q = { practiceId: req.practiceId, kind: 'digital', issuedAt: { $gte: from, $lt: to } };
  if (f.doctorId) q.doctorId = f.doctorId === 'me' ? req.user._id : f.doctorId;
  if (f.locationIds.length || f.visitTypes.length || f.modes.length || f.ageGroups.length) {
    // Consults of matching visits, and matching consults made without a visit.
    const seen = await seenVisits(req, T.addDays(from, -1), to, f);
    q.consultationId = { $in: [...(await consultsOf(seen, '_id')).values()].map((c) => c._id) };
  }
  return q;
}

async function kpis(req, from, to, f) {
  // Consultations = everyone seen: completed visits and consults issued without one (no double count).
  const done = await seenVisits(req, from, to, f);
  const missed = await missedVisits(req, from, to, f, done);
  const [rxCount, paid] = await Promise.all([
    rxScope(req, from, to, f).then((q) => M.Prescription.countDocuments(q)),
    paymentScope(req, from, to, f).then((scope) =>
      M.Payment.aggregate([{ $match: { practiceId: req.practiceId, status: 'paid', paidAt: { $gte: from, $lt: to }, ...scope } }, { $group: { _id: null, sum: { $sum: '$amount' } } }])),
  ]);
  const times = done.map(consultMin).filter((x) => x != null);
  return {
    done,
    consultations: done.length,
    newPatients: done.filter((a) => a.visitType === 'new').length,
    avgConsultMin: times.length ? Math.round(avg(times)) : null,
    missed: missed.length,
    missedPct: done.length + missed.length ? Math.round((missed.length / (done.length + missed.length)) * 100) : 0,
    prescriptions: rxCount,
    prescriptionPct: done.length ? Math.min(100, Math.round((rxCount / done.length) * 100)) : 0,
    feesCollected: paid[0]?.sum || 0,
  };
}

r.get('/reports/summary', async (req, res) => {
  const { from, to, prevFrom, prevTo } = rangeOf(req.query);
  const f = filtersOf(req.query);
  const now = await kpis(req, from, to, f);
  const prev = req.query.compare === 'false' ? null : await kpis(req, prevFrom, prevTo, f);
  const consults = [...(await consultsOf(now.done, 'diagnoses')).values()];
  const perDay = {};
  for (let d = from; d < to; d = T.addDays(d, 1)) perDay[T.dayKey(d)] = 0;
  for (const a of now.done) perDay[T.dayKey(a.date)] = (perDay[T.dayKey(a.date)] || 0) + 1;
  const fu = (await M.FollowUp.find({ practiceId: req.practiceId, dueDate: { $gte: from, $lt: to }, ...(f.doctorId ? { doctorId: f.doctorId === 'me' ? req.user._id : f.doctorId } : {}) }, 'outcome status dueDate').lean())
    .map((x) => ({ outcome: followUpOutcome(x) }))
    .filter((x) => x.outcome !== 'pending');
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
  const all = await seenVisits(req, from, to, { locationIds: [], visitTypes: [], modes: [], ageGroups: [] });
  const matching = await seenVisits(req, from, to, filtersOf(req.query));
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
  // Completed visits and consults issued without one (started straight from the patient).
  let rows = await seenVisits(req, from, to, filtersOf(req.query));
  const cmap = await consultsOf(rows, 'diagnoses chiefComplaint');
  const clinical = seesClinical(req);
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    rows = rows.filter((a) => re.test(a.patientId?.name || '') || re.test(a.patientId?.phone || '') || (clinical && (cmap.get(String(a._id))?.diagnoses || []).some((d) => re.test(d.name))));
  }
  const items = rows.sort((a, b) => new Date(b.startAt) - new Date(a.startAt)).map((a) => ({
    appointmentId: a.viaConsult ? a.apptId : a._id, consultationId: cmap.get(String(a._id))?._id || null, date: a.date, startAt: a.consultStartedAt || a.startAt,
    patient: { id: a.patientId?._id, name: a.patientId?.name, age: a.age, gender: a.patientId?.gender, phone: req.query.includeMobiles === 'true' ? a.patientId?.phone : undefined },
    visitType: a.visitType, mode: a.mode, location: a.locationId?.shortName || a.locationId?.name,
    diagnoses: clinical ? (cmap.get(String(a._id))?.diagnoses || []).map((d) => d.name) : [],
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
  const q = await rxScope(req, from, to, filtersOf(req.query));
  let rx = await M.Prescription.find(q).sort({ issuedAt: -1 }).populate('patientId', 'name').lean();
  const clinical = seesClinical(req);
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    rx = rx.filter((p) => re.test(p.patientId?.name || '') || (clinical && p.items.some((i) => re.test(i.name))) || re.test(String(p.rxNumber).padStart(4, '0')));
  }
  const meds = countBy(rx.flatMap((p) => p.items), (i) => `${i.name}${i.strength ? ` ${i.strength}` : ''}`);
  const tests = countBy(rx.flatMap((p) => p.tests.map((t) => ({ t }))), (x) => x.t);
  res.json({
    totals: { prescriptions: rx.length, medicines: rx.reduce((s, p) => s + p.items.length, 0), labTests: rx.reduce((s, p) => s + p.tests.length, 0) },
    topMedicines: meds.slice(0, 10),
    topTests: tests.slice(0, 10),
    items: rx.map((p) => ({ id: p._id, patientId: p.patientId?._id, rxNumber: String(p.rxNumber).padStart(4, '0'), issuedAt: p.issuedAt, patient: p.patientId?.name, medicines: clinical ? p.items.map((i) => `${i.name} ${i.strength || ''}`.trim()) : [], tests: clinical ? p.tests : [] })),
  });
});

r.get('/reports/fees', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  const f = filtersOf(req.query);
  const rows = await seenVisits(req, from, to, f);
  const scope = await paymentScope(req, from, to, f);
  const withVisit = { path: 'appointmentId', select: 'date startAt mode payAt locationId', populate: { path: 'locationId', select: 'name shortName' } };
  const payments = await M.Payment.find({
    practiceId: req.practiceId, ...scope,
    $or: [{ status: 'paid', paidAt: { $gte: from, $lt: to } }, { status: 'pending', createdAt: { $gte: from, $lt: to } }],
  }).populate('patientId', 'name').populate('locationId', 'name shortName').populate(withVisit).populate('markedPaidBy', 'name').lean();
  const paid = payments.filter((p) => p.status === 'paid');
  const sumBy = (arr, key) => Object.entries(arr.reduce((acc, x) => { const k = key(x) || 'other'; acc[k] = (acc[k] || 0) + x.amount; return acc; }, {})).map(([k, amount]) => ({ key: k, amount }));
  const locOf = (l) => l?.shortName || l?.name;
  const payLoc = (p) => locOf(p.locationId) || locOf(p.appointmentId?.locationId);
  // Billed = the fee of every visit in range, once: visits seen (completed, or seen through a
  // consult) and fees paid / due in range (prepaid online, pay at the clinic). A visit's own
  // payment stands for its fee — what was actually charged.
  const charges = new Map();
  for (const a of rows) charges.set(String(a.apptId || a._id), { amount: a.fee || 0, loc: locOf(a.locationId), free: a.fee === 0 });
  for (const p of payments) charges.set(String(p.appointmentId?._id || p._id), { amount: p.amount || 0, loc: payLoc(p), free: false });
  const billed = [...charges.values()];
  const row = (p) => ({
    id: p._id, patientId: p.patientId?._id, patient: p.patientId?.name, amount: p.amount, method: p.method || null,
    location: payLoc(p), visitDate: p.appointmentId?.startAt || p.appointmentId?.date || null, mode: p.appointmentId?.mode || null,
  });
  const [due, refunded] = await Promise.all([
    // Cancelled visits paid at the desk (or a failed online refund): money to give back.
    M.Payment.find({ practiceId: req.practiceId, status: 'paid', refundDue: true }).sort({ paidAt: -1 }).populate('patientId', 'name').populate('locationId', 'name shortName').populate(withVisit).lean(),
    // Given back in this period (online through Razorpay, or handed back at the desk).
    M.Payment.find({ practiceId: req.practiceId, ...scope, status: 'refunded', refundedAt: { $gte: from, $lt: to } }).sort({ refundedAt: -1 }).populate('patientId', 'name').populate('locationId', 'name shortName').populate(withVisit).populate('refundedBy', 'name').lean(),
  ]);
  res.json({
    billed: billed.reduce((s, x) => s + x.amount, 0),
    collected: paid.reduce((s, p) => s + p.amount, 0),
    pendingAmount: payments.filter((p) => p.status === 'pending').reduce((s, p) => s + p.amount, 0),
    freeVisits: billed.filter((x) => x.free && !x.amount).length,
    billedByLocation: sumBy(billed.filter((x) => x.amount), (x) => x.loc),
    collectedByMethod: sumBy(paid, (p) => p.method),
    // Each fee collected: who, how (online / cash / UPI / card), when paid, where, for which visit.
    collectedList: paid.sort((a, b) => new Date(b.paidAt) - new Date(a.paidAt)).map((p) => ({ ...row(p), paidAt: p.paidAt, refundDue: Boolean(p.refundDue), collectedBy: p.markedPaidBy?.name || null })),
    refundsDue: due.map((p) => ({ ...row(p), paidAt: p.paidAt, note: p.note })),
    refunded: refunded.map((p) => ({ ...row(p), paidAt: p.paidAt, refundedAt: p.refundedAt, refundedBy: p.refundedBy?.name || null, refundReason: p.refundReason || null })),
    refundedAmount: refunded.reduce((s, p) => s + p.amount, 0),
    // Patients who chose "Pay at the clinic": the desk collects these.
    toCollectAtClinic: payments.filter((p) => p.status === 'pending' && p.appointmentId?.payAt === 'clinic').reduce((s, p) => s + p.amount, 0),
    pending: payments.filter((p) => p.status === 'pending').map((p) => ({ ...row(p), payAt: p.appointmentId?.payAt || null, date: p.appointmentId?.startAt || p.createdAt, linkSentAt: p.paymentLinkSentAt })),
  });
});

// ── Report-Referrals: "Add a referral" helpers ──

// Find-doctor specialty (Specialty.key) → the department doctors refer to.
const DEPARTMENT_OF = {
  gp: 'General medicine', diabetes: 'Endocrinology', heart: 'Cardiology', women: 'Gynaecology', child: 'Paediatrics', skin: 'Dermatology',
  bones: 'Orthopaedics', mind: 'Psychiatry', stomach: 'Gastroenterology', eye: 'Ophthalmology', teeth: 'Dentistry', ent: 'ENT',
};
const MORE_DEPARTMENTS = ['Nephrology', 'Diabetology', 'Neurology', 'Pulmonology', 'Haematology', 'Urology', 'Rheumatology', 'Oncology'];

// Words in a reason, diagnosis or headline → the specialty to refer to (most fitting first).
const SPECIALTY_RULES = [
  [/creatinine|\begfr\b|\burea\b|kidney|renal|\bckd\b|proteinuria|protein in urine|albumin|\buacr\b|potassium|sodium|nephr/i, ['Nephrology']],
  [/hba1c|glucose|sugar|diabet/i, ['Diabetology', 'Endocrinology']],
  [/\btsh\b|\bt3\b|\bt4\b|thyro|cortisol|endocrin|pcos|pcod/i, ['Endocrinology']],
  [/\becg\b|\bbp\b|blood pressure|hypertension|\bldl\b|cholesterol|triglycer|lipid|troponin|chest pain|palpitation|heart|cardi|pulse/i, ['Cardiology']],
  [/ha?emoglobin|ana?emia|platelet|\bwbc\b|ferritin|haemat|hemat/i, ['Haematology']],
  [/sgpt|sgot|\balt\b|\bast\b|bilirubin|liver|hepat|gastr|stomach|acidity/i, ['Gastroenterology']],
  [/spo2|oxygen|asthma|copd|breath|lung|tubercul|pulmon/i, ['Pulmonology']],
  [/uric acid|gout|arthritis|joint|rheumat/i, ['Rheumatology']],
  [/retin|\beye\b|vision|fundus|cataract|glaucoma|ophthal/i, ['Ophthalmology']],
  [/pregnan|period|menstru|pcos|pcod|uter|ovar|gynae|gyne/i, ['Gynaecology']],
  [/depress|anxiety|insomnia|psychi/i, ['Psychiatry']],
  [/stroke|seizure|epilep|migraine|neuropath|parkinson|neuro/i, ['Neurology']],
  [/\bpsa\b|prostate|urinary|urolog/i, ['Urology']],
  [/skin|rash|eczema|psoriasis|acne|dermat/i, ['Dermatology']],
  [/bone|fracture|spine|orthop/i, ['Orthopaedics']],
  [/child|paediat|pediat/i, ['Paediatrics']],
];
const specialtiesFor = (text) => [...new Set(SPECIALTY_RULES.filter(([re]) => re.test(text || '')).flatMap(([, s]) => s))];
const uniqueText = (xs) => {
  const seen = new Set();
  return xs.filter((x) => x && !seen.has(x.toLowerCase()) && seen.add(x.toLowerCase()));
};

/** A doctor's specialty for the form: from their headline / tags, else their Find-doctor specialty. */
const doctorSpecialty = (p, labels) => specialtiesFor([p.headline, ...(p.specialisations || [])].join(' '))[0]
  || DEPARTMENT_OF[p.specialtyKeys?.[0]] || labels.get(p.specialtyKeys?.[0]) || null;

// "Referred to / by": doctors on MedPin, at any clinic, by name, specialty or clinic.
r.get('/reports/referral-doctors', need('clinical'), async (req, res) => {
  const text = String(req.query.q || '').trim().replace(/^dr\.?\s*/i, '');
  if (text.length < 2) return res.json({ items: [] });
  // From the start of a word, so "ra" finds "Dr. Rina", not every "Sarkar".
  const re = new RegExp(`(?:^|[^a-z0-9])${escapeRegex(text)}`, 'i');
  const [specKeys, practices, locations] = await Promise.all([
    M.Specialty.find({ $or: [{ label: re }, { aiRole: re }] }).distinct('key'),
    M.Practice.find({ name: re }).distinct('_id'),
    M.Location.find({ $or: [{ name: re }, { area: re }] }).distinct('_id'),
  ]);
  const deptKeys = Object.keys(DEPARTMENT_OF).filter((k) => re.test(DEPARTMENT_OF[k]));
  const atClinics = practices.length || locations.length
    ? await M.DoctorLocation.find({ status: 'active', $or: [{ practiceId: { $in: practices } }, { locationId: { $in: locations } }] }).distinct('doctorId')
    : [];
  const profiles = await M.DoctorProfile.find({
    userId: { $ne: req.user._id },
    $or: [{ displayName: re }, { headline: re }, { specialisations: re }, { specialtyKeys: { $in: [...specKeys, ...deptKeys] } }, { userId: { $in: atClinics } }],
  }, 'userId displayName headline specialtyKeys specialisations').limit(40).lean();
  const [places, labels] = await Promise.all([
    M.DoctorLocation.find({ doctorId: { $in: profiles.map((p) => p.userId) }, status: 'active' }, 'doctorId practiceId locationId')
      .populate('practiceId', 'name').populate('locationId', 'name shortName area city status').lean(),
    M.Specialty.find({ key: { $in: profiles.flatMap((p) => p.specialtyKeys || []) } }, 'key label').lean().then((xs) => new Map(xs.map((x) => [x.key, x.label]))),
  ]);
  const items = profiles.map((p) => {
    const mine = places.filter((d) => String(d.doctorId) === String(p.userId) && d.locationId?.status !== 'inactive');
    // Their place in this clinic first, else the first one.
    const at = mine.find((d) => String(d.practiceId?._id) === String(req.practiceId)) || mine[0];
    const clinic = at ? (at.locationId?.name || at.practiceId?.name || '').replace(/ — /g, ', ') : null;
    return {
      id: p.userId, name: p.displayName, specialty: doctorSpecialty(p, labels), headline: p.headline || null,
      clinic, area: at?.locationId?.area || at?.locationId?.city || null, sameClinic: Boolean(at && String(at.practiceId?._id) === String(req.practiceId)),
      byName: re.test(p.displayName),
    };
  });
  // Name matches first, then doctors with a clinic, A–Z.
  items.sort((a, b) => Number(b.byName) - Number(a.byName) || Number(Boolean(b.clinic)) - Number(Boolean(a.clinic)) || a.name.localeCompare(b.name));
  res.json({ items: items.slice(0, 10).map(({ byName, ...x }) => x) });
});

/** "Rising creatinine 1.8 mg/dL" — the analyte in running text keeps HbA1c / LDL as written. */
function labReason(v, prev) {
  const name = /^[A-Z][a-z]+(\s|$)/.test(v.analyte) ? v.analyte[0].toLowerCase() + v.analyte.slice(1) : v.analyte;
  const unit = !v.unit ? '' : v.unit === '%' ? '%' : ` ${v.unit}`;
  const value = v.value != null ? `${v.value}${unit}` : v.valueText || '';
  let word = v.flag === 'critical' ? 'Critical' : v.flag === 'high' ? 'High' : 'Low';
  if (v.value != null && prev?.value != null) {
    if (v.flag === 'high' && v.value > prev.value) word = 'Rising';
    if (v.flag === 'low' && v.value < prev.value) word = 'Falling';
  }
  return `${word} ${name}${value ? ` ${value}` : ''}`;
}

// Reason and specialty suggestions for "Add a referral", from the chosen patient's
// record: abnormal lab values, out-of-range readings, recent diagnoses, conditions.
r.get('/reports/referral-suggestions', need('clinical'), async (req, res) => {
  const reasons = [];
  const add = (text, kind) => reasons.push({ text, kind, specialties: specialtiesFor(text) });
  if (req.query.patientId) {
    const patient = await patientInPractice(req, req.query.patientId);
    const since = T.addDays(T.dayStart(), -365);
    // Only what the patient shares with this clinic.
    const acc = await accessFor({ userId: req.user._id, practiceId: req.practiceId }, patient);
    const [labs, vitals, consults] = await Promise.all([
      M.LabResult.find({ patientId: patient._id, collectedAt: { $gte: since }, ...(await acc.labFilter()) }, 'values collectedAt ecgInterpretation ecgNote').sort({ collectedAt: -1 }).limit(60).lean(),
      M.Vitals.find({ patientId: patient._id, recordedAt: { $gte: T.addDays(T.dayStart(), -90) }, ...acc.vitalsFilter() }).sort({ recordedAt: -1 }).limit(60).lean(),
      M.Consultation.find({ patientId: patient._id, practiceId: req.practiceId, status: { $ne: 'draft' } }, 'diagnoses startedAt').sort({ startedAt: -1 }).limit(5).lean(),
    ]);
    // Labs: each test's latest value, when it is out of range (critical first); the one before shows the trend.
    const byAnalyte = new Map();
    for (const l of labs) {
      for (const v of l.values || []) {
        const k = v.analyte.toLowerCase();
        if (!byAnalyte.has(k)) byAnalyte.set(k, []);
        byAnalyte.get(k).push(v);
      }
    }
    const flagged = [...byAnalyte.values()].filter(([v]) => ['critical', 'high', 'low'].includes(v.flag))
      .sort((a, b) => Number(b[0].flag === 'critical') - Number(a[0].flag === 'critical'));
    for (const [v, prev] of flagged.slice(0, 4)) add(labReason(v, prev), 'lab');
    const ecg = labs.find((l) => l.ecgInterpretation && l.ecgInterpretation !== 'unread');
    if (ecg && ['abnormal', 'borderline'].includes(ecg.ecgInterpretation)) add(ecg.ecgInterpretation === 'abnormal' ? 'ECG changes' : 'Borderline ECG', 'lab');
    // Readings: the latest of each, when out of range.
    const latest = (k) => vitals.find((x) => x[k] != null);
    const bp = latest('bpSystolic');
    if (bp && (bp.bpSystolic >= 140 || bp.bpDiastolic >= 90)) add(`High BP ${bp.bpSystolic}/${bp.bpDiastolic} mmHg`, 'vitals');
    if (bp && bp.bpSystolic < 90) add(`Low BP ${bp.bpSystolic}/${bp.bpDiastolic} mmHg`, 'vitals');
    const sp = latest('spo2');
    if (sp && sp.spo2 < 94) add(`Low SpO2 ${sp.spo2}%`, 'vitals');
    const pu = latest('pulse');
    if (pu && pu.pulse > 100) add(`Fast pulse ${pu.pulse}/min`, 'vitals');
    if (pu && pu.pulse < 50) add(`Slow pulse ${pu.pulse}/min`, 'vitals');
    const su = latest('bloodSugar');
    if (su && ((su.sugarType === 'fasting' && su.bloodSugar >= 126) || su.bloodSugar >= 200)) add(`High sugar ${su.bloodSugar} mg/dL`, 'vitals');
    const bmi = latest('bmi');
    if (bmi && bmi.bmi >= 30) add(`BMI ${Math.round(bmi.bmi * 10) / 10}`, 'vitals');
    // Recent diagnoses here, then the patient's conditions.
    for (const name of uniqueText(consults.flatMap((c) => (c.diagnoses || []).map((d) => d.name))).slice(0, 4)) add(name, 'diagnosis');
    // A condition already named by a diagnosis ("Type 2 diabetes" / "Type 2 diabetes mellitus") is left out.
    const named = reasons.map((x) => x.text.toLowerCase());
    for (const c of patient.conditions || []) {
      const n = c.name.toLowerCase();
      if (!named.some((t) => t.includes(n) || n.includes(t))) add(c.name, 'condition');
    }
  }
  const seen = new Set();
  const out = reasons.filter((x) => !seen.has(x.text.toLowerCase()) && seen.add(x.text.toLowerCase())).slice(0, 10);
  // Specialties: those the reasons point to, this clinic's usual ones, then MedPin's list.
  const [used, catalog] = await Promise.all([
    M.Referral.aggregate([{ $match: { practiceId: req.practiceId, specialty: { $nin: [null, ''] } } }, { $group: { _id: '$specialty', n: { $sum: 1 } } }, { $sort: { n: -1 } }, { $limit: 8 }]),
    M.Specialty.find({}, 'key label').sort({ order: 1 }).lean(),
  ]);
  res.json({
    reasons: out.map((x) => ({ text: x.text, kind: x.kind, specialty: x.specialties[0] || null })),
    specialties: uniqueText([
      ...out.flatMap((x) => x.specialties), ...used.map((u) => u._id),
      ...catalog.map((s) => DEPARTMENT_OF[s.key] || s.label), ...MORE_DEPARTMENTS,
    ]).slice(0, 24),
  });
});

r.get('/reports/follow-ups', async (req, res) => {
  const { from, to } = rangeOf(req.query);
  const f0 = filtersOf(req.query);
  const fus = await M.FollowUp.find({ practiceId: req.practiceId, dueDate: { $gte: from, $lt: to }, status: { $ne: 'cancelled' }, ...(f0.doctorId ? { doctorId: f0.doctorId === 'me' ? req.user._id : f0.doctorId } : {}) })
    .populate('patientId', 'name phone gender ageYears ageRecordedAt conditions').lean();
  const today = T.dayStart();
  const outcome = followUpOutcome;
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
      id: f._id, patient: f.patientId && { id: f.patientId._id, name: f.patientId.name, phone: f.patientId.phone, age: T.ageFrom(f.patientId), gender: f.patientId.gender, condition: seesClinical(req) ? f.patientId.conditions?.[0]?.name : undefined },
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
  // Today's fees for these visits: collected (online / at the desk) and still to collect.
  const todayPays = await M.Payment.find({ appointmentId: { $in: todayAppts.map((a) => a._id) }, status: { $in: ['pending', 'paid'] } }, 'status method amount').lean();
  const sum = (xs) => xs.reduce((s, p) => s + (p.amount || 0), 0);
  // A clinic without a front desk: the doctor confirms requests, checks patients in and collects fees.
  const { hasDesk } = require('../services/notify');
  const desk = await hasDesk(req.practiceId, req.user.activeLocationId);
  const waitingRequests = await M.AppointmentRequest.countDocuments({ practiceId: req.practiceId, status: 'pending', ...(req.member.role === 'doctor' ? { doctorId: req.user._id } : {}) });
  res.json({
    greetingName: user.name,
    hasDesk: desk,
    requests: { pending: waitingRequests },
    fees: {
      // Shown to a doctor who handles money: no front desk (they collect it themselves) or the
      // owner (they reconcile the day). A doctor in a clinic with a desk doesn't need it on Home.
      show: !desk || Boolean(req.member.isOwner),
      collected: sum(todayPays.filter((p) => p.status === 'paid')),
      online: sum(todayPays.filter((p) => p.status === 'paid' && p.method === 'online')),
      atClinic: sum(todayPays.filter((p) => p.status === 'paid' && p.method !== 'online')),
      toCollect: sum(todayPays.filter((p) => p.status === 'pending')),
    },
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
module.exports.seenVisits = seenVisits;
module.exports.followUpOutcome = followUpOutcome;

// Appointments, Appointments-Manage, Queue-Select, Queue-List, Staff-Today,
// Doctor-History, Report-Fees (payments).
const { Router } = require('express');
const { Types } = require('mongoose');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice, ownPractice } = require('../middleware/auth');
const { badRequest, notFound, conflict, forbidden, list, paging } = require('../lib/http');
const S = require('../services/scheduling');
const { notify } = require('../services/notify');

const r = Router();
r.use(requireAuth, staff());
r.use('/payments', need('fees'));

const view = (a) => {
  const p = a.patientId && a.patientId.name ? a.patientId : null;
  return {
    ...a.toJSON(),
    token: a.tokenNo ? String(a.tokenNo).padStart(2, '0') : null,
    patient: p ? { id: p._id, name: p.name, age: T.ageFrom(p), gender: p.gender, phone: p.phone, conditions: (p.conditions || []).map((c) => c.name) } : undefined,
    patientId: p ? p._id : a.patientId,
    doctor: a.doctorId?.name ? { id: a.doctorId._id, name: a.doctorId.name } : undefined,
    doctorId: a.doctorId?._id || a.doctorId,
    location: a.locationId?.name ? { id: a.locationId._id, name: a.locationId.shortName || a.locationId.name } : undefined,
    locationId: a.locationId?._id || a.locationId,
    waitingMin: a.status === 'waiting' && a.arrivedAt ? Math.round((Date.now() - a.arrivedAt) / 60000) : null,
    // The fee: its payment (to collect at the desk, or paid and how) — see withPayments().
    payment: a._payment || null,
    // The patient's profile photo (see withPayments, which fills it).
    patientPhoto: a._photo || null,
    // Who cancelled it (a name), for the visit and Fees.
    cancelledByName: a.cancelledByUser?.name || null,
    cancelledByUser: a.cancelledByUser?._id || a.cancelledByUser || null,
  };
};

/** Each visit's fee payment (id, status, method, amount), for the desk / doctor rows. */
async function withPayments(appts) {
  const ids = appts.map((a) => a._id);
  const pays = ids.length ? await M.Payment.find({ appointmentId: { $in: ids }, status: { $in: ['pending', 'paid', 'refunded'] } }).sort({ createdAt: -1 }) : [];
  const by = new Map();
  for (const p of pays) if (!by.has(String(p.appointmentId))) by.set(String(p.appointmentId), p);
  const photos = await require('../services/photos').photosFor(appts.map((a) => a.patientId?.userId));
  for (const a of appts) {
    if (a.patientId?.userId) a._photo = photos.get(String(a.patientId.userId)) || null;
    const p = by.get(String(a._id));
    a._payment = p ? { id: p._id, status: p.status, method: p.method || null, amount: p.amount, paidAt: p.paidAt || null, refundDue: Boolean(p.refundDue) } : null;
  }
  return appts;
}
// Patient, doctor and place: shared by appointments and consultations (History lists both).
const populateCore = (q) => q.populate('patientId', 'name gender ageYears ageRecordedAt dateOfBirth phone conditions createdAt userId').populate('doctorId', 'name').populate('locationId', 'name shortName');
// Appointments also carry who cancelled them (Consultation has no such field — populating it there throws).
const populate = (q) => populateCore(q).populate('cancelledByUser', 'name');

/**
 * What this staff member looks after: their locations (null = every one) and,
 * for a doctor's assistant, the doctors they assist (null = every doctor).
 * A doctor sees the whole practice's lists.
 */
function coverage(req) {
  const m = req.member || {};
  const locs = m.role === 'doctor' || m.allLocations || !m.locationIds?.length ? null : m.locationIds.map(String);
  const docs = m.role === 'doctor_assistant' && m.assistsDoctorIds?.length ? m.assistsDoctorIds.map(String) : null;
  return { locs, docs };
}

const isId = (x) => /^[0-9a-f]{24}$/i.test(String(x || ''));

const DESK = ['front_desk', 'practice_manager', 'doctor_assistant'];

/**
 * May this person act on a visit (book, move, cancel, change its status, take or
 * give back its fee)? The owner and practice managers: any visit. A doctor: their
 * own visits (booking: any doctor's — they schedule colleagues' follow-ups too).
 * The front desk: visits at the locations they cover; an assistant also only
 * with the doctors they assist. Anyone else: no.
 */
function assertCovers(req, { locationId, doctorId } = {}, { booking = false } = {}) {
  const m = req.member || {};
  if (m.isOwner || m.role === 'practice_manager') return;
  if (m.role === 'doctor') {
    if (!booking && doctorId && String(doctorId) !== String(req.user._id)) throw forbidden("This is another doctor's visit. Ask them or the front desk.", 'NOT_YOUR_VISIT');
    return;
  }
  if (!DESK.includes(m.role)) throw forbidden("Your role can't change visits", 'ROLE_REQUIRED');
  const { locs, docs } = coverage(req);
  const at = locationId?._id || locationId;
  const with_ = doctorId?._id || doctorId;
  if (locs && at && !locs.includes(String(at))) throw forbidden("This visit is at a location you don't cover", 'NOT_YOUR_LOCATION');
  if (docs && with_ && !docs.includes(String(with_))) throw forbidden("This visit is with a doctor you don't assist", 'NOT_YOUR_DOCTOR');
}

/** The visit a payment is for (location / doctor for the guard), or the payment's own location. */
async function paymentScope(p) {
  const appt = p.appointmentId ? await M.Appointment.findById(p.appointmentId, 'practiceId locationId doctorId patientId status') : null;
  return { appt, scope: appt ? { locationId: appt.locationId, doctorId: appt.doctorId } : { locationId: p.locationId } };
}

/** Why the clinic cancelled (the desk picks one of the quick reasons, or types one). */
const CANCEL_REASONS = ['Patient asked', 'Doctor unavailable', 'Clinic closed', 'Booked by mistake', 'Other'];

// Today / Upcoming / Past, or a single date.
r.get('/appointments', async (req, res) => {
  const { limit, skip } = paging(req.query, 200);
  const q = { practiceId: req.practiceId };
  // A list of the day's visits shows the places / doctors this person covers (one patient's visits: all of them).
  const scope = {};
  if (!req.query.patientId) {
    const { locs, docs } = coverage(req);
    if (locs && !req.query.locationId) scope.locationId = { $in: locs.map((id) => new Types.ObjectId(id)) };
    if (docs && !req.query.doctorId) scope.doctorId = { $in: docs.map((id) => new Types.ObjectId(id)) };
  }
  Object.assign(q, scope);
  const today = T.dayStart();
  const viewName = req.query.view || (req.query.date ? 'date' : 'today');
  if (viewName === 'today') q.date = today;
  else if (viewName === 'upcoming') q.date = { $gt: today };
  else if (viewName === 'past') q.date = { $lt: today };
  else if (viewName === 'date') q.date = T.parseDay(req.query.date);
  if (req.query.from || req.query.to) q.date = { ...(req.query.from ? { $gte: T.parseDay(req.query.from) } : {}), ...(req.query.to ? { $lte: T.parseDay(req.query.to) } : {}) };
  if (req.query.locationId) q.locationId = req.query.locationId;
  if (req.query.doctorId) q.doctorId = req.query.doctorId === 'me' ? req.user._id : req.query.doctorId;
  if (req.query.patientId) q.patientId = req.query.patientId;
  if (req.query.status) q.status = { $in: list(req.query.status) };
  else if (viewName !== 'past') q.status = { $nin: ['cancelled', 'rescheduled'] };
  const sort = viewName === 'past' ? { startAt: -1 } : { startAt: 1 };
  // Counts for the same dates, places and doctors as the list (every status).
  const oid = (x) => (isId(x) ? new Types.ObjectId(String(x)) : x);
  const range = { practiceId: req.practiceId, ...scope, date: q.date };
  if (q.locationId && !scope.locationId) range.locationId = oid(q.locationId);
  if (q.doctorId && !scope.doctorId) range.doctorId = oid(q.doctorId);
  if (q.patientId) range.patientId = oid(q.patientId);
  const [items, total, stats, inRange] = await Promise.all([
    populate(M.Appointment.find(q).sort(sort).skip(skip).limit(limit)).then(withPayments),
    M.Appointment.countDocuments(q),
    M.Appointment.aggregate([
      { $match: { practiceId: req.practiceId, ...scope, date: today } },
      { $group: { _id: '$status', n: { $sum: 1 } } },
    ]),
    M.Appointment.aggregate([{ $match: range }, { $group: { _id: '$status', n: { $sum: 1 } } }]),
  ]);
  const by = Object.fromEntries(stats.map((s) => [s._id, s.n]));
  const rb = Object.fromEntries(inRange.map((s) => [s._id, s.n]));
  const active = (m) => Object.entries(m).filter(([k]) => !['cancelled', 'rescheduled'].includes(k)).reduce((n, [, v]) => n + v, 0);
  const pending = await M.AppointmentRequest.countDocuments({ practiceId: req.practiceId, status: 'pending' });
  res.json({
    total,
    // Today's (whatever the view).
    stats: {
      booked: active(by),
      waitingRequests: pending,
      freedUp: (by.cancelled || 0),
      completed: by.completed || 0,
    },
    // This view's dates: Booked (not cancelled / moved), Freed up (cancelled), Done, Missed.
    rangeStats: {
      booked: active(rb),
      freedUp: rb.cancelled || 0,
      completed: rb.completed || 0,
      missed: rb.missed || 0,
      waitingRequests: pending,
    },
    items: items.map(view),
  });
});

// ── Booking at the desk (Staff-Book) ──
// The front desk books by phone or at the counter, often weeks ahead (a follow-up
// in a month), so the desk always sees at least this many days, more when the
// doctor's own booking window is longer.
const DESK_MIN_WINDOW = 14;
const deskWindow = (dl) => Math.max(dl?.schedule?.bookingWindowDays || 7, DESK_MIN_WINDOW);

// Doctors this person books for, each with the places they see patients at that
// this person covers (an assistant: the doctors they assist; desk staff: their
// locations). The signed-in doctor first.
r.get('/appointments/booking/doctors', async (req, res) => {
  const { locs, docs } = coverage(req);
  const [members, dls] = await Promise.all([
    M.Member.find({ practiceId: req.practiceId, role: 'doctor', status: 'active' }).populate('userId', 'name'),
    M.DoctorLocation.find({ practiceId: req.practiceId, status: 'active' }).populate('locationId', 'name shortName status'),
  ]);
  const photos = await require('../services/photos').doctorPhotos(members.map((m) => m.userId?._id));
  const items = [];
  for (const m of members) {
    if (!m.userId) continue;
    const id = String(m.userId._id);
    if (docs && !docs.includes(id)) continue;
    const locations = dls
      .filter((d) => String(d.doctorId) === id && d.locationId && d.locationId.status === 'active' && (!locs || locs.includes(String(d.locationId._id))))
      .map((d) => ({ id: d.locationId._id, name: d.locationId.shortName || d.locationId.name, windowDays: deskWindow(d), slotLengthMin: d.schedule?.slotLengthMin || 15 }));
    items.push({ userId: m.userId._id, name: m.userId.name, photo: photos.get(id) || null, me: id === String(req.user._id), locations });
  }
  items.sort((a, b) => Number(b.me) - Number(a.me));
  res.json({ items });
});

// What the desk should know about this patient before booking: their visits with
// each doctor (last reason / diagnosis), follow-ups due, tests asked with no
// report yet, reports in since the last visit, and visits already booked.
r.get('/appointments/booking/context', async (req, res) => {
  const patient = await patientInPractice(req, req.query.patientId);
  const pid = patient._id;
  const pq = { practiceId: req.practiceId, patientId: pid };
  const [visits, consults, followUps, upcoming, advised] = await Promise.all([
    M.Appointment.find({ ...pq, status: 'completed' }).sort({ completedAt: -1 }).limit(30).populate('doctorId', 'name'),
    M.Consultation.find({ ...pq, status: { $in: ['issued', 'sent'] } }, 'doctorId appointmentId chiefComplaint diagnoses startedAt completedAt').sort({ startedAt: -1 }).limit(30).populate('doctorId', 'name'),
    M.FollowUp.find({ ...pq, status: { $in: ['not_booked', 'no_reply', 'reports_in'] } }).sort({ dueDate: 1 }).limit(10).populate('doctorId', 'name'),
    populate(M.Appointment.find({ ...pq, date: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } }).sort({ startAt: 1 }).limit(10)),
    require('../services/advisedtests').advisedTests(patient).catch(() => []),
  ]);
  const dx = (c) => (c?.diagnoses || []).map((d) => d.name).filter(Boolean).join(', ') || null;
  // The last visit with each doctor (a booked visit, or a prescription given without one).
  const byAppt = new Map(consults.filter((c) => c.appointmentId).map((c) => [String(c.appointmentId), c]));
  const rows = [
    ...visits.map((a) => {
      const c = byAppt.get(String(a._id));
      return { doctorId: a.doctorId?._id || a.doctorId, doctorName: a.doctorId?.name || null, at: a.completedAt || a.startAt, reason: a.reason || c?.chiefComplaint || null, visitType: a.visitType, diagnosis: dx(c) };
    }),
    ...consults.filter((c) => !c.appointmentId).map((c) => ({
      doctorId: c.doctorId?._id || c.doctorId, doctorName: c.doctorId?.name || null, at: c.completedAt || c.startedAt, reason: c.chiefComplaint || null, visitType: null, diagnosis: dx(c),
    })),
  ].sort((a, b) => new Date(b.at) - new Date(a.at));
  const lastVisits = [];
  for (const v of rows) if (!lastVisits.some((x) => String(x.doctorId) === String(v.doctorId))) lastVisits.push(v);
  const lastAt = rows[0]?.at ? new Date(rows[0].at) : null;
  const photo = patient.userId ? (await require('../services/photos').photosFor([patient.userId])).get(String(patient.userId)) || null : null;
  res.json({
    patient: {
      id: pid, name: patient.name, phone: patient.phone, gender: patient.gender, age: T.ageFrom(patient), photo, hasApp: Boolean(patient.userId),
      conditions: (patient.conditions || []).map((c) => c.name).filter(Boolean),
    },
    lastVisits,
    followUps: followUps.map((f) => ({
      id: f._id, doctorId: f.doctorId?._id || f.doctorId, doctorName: f.doctorId?.name || null, locationId: f.locationId || null, dueDate: f.dueDate, status: f.status, adviceText: f.adviceText || null,
    })),
    // Asked for, no report yet (a wrong or unreadable upload still counts as to do).
    pendingTests: advised.filter((t) => ['todo', 'wrong', 'unreadable'].includes(t.status)).slice(0, 8)
      .map((t) => ({ name: t.name, doctorId: t.doctorId, forWhat: t.forWhat || null, bringBy: t.bringBy || null })),
    // Reports in since the last visit: something for the doctor to review.
    reportsIn: advised.filter((t) => t.status === 'done' || t.status === 'unchecked')
      .map((t) => ({ name: t.name, doctorId: t.doctorId, at: t.result?.date || t.lastUpload?.date || null }))
      .filter((t) => t.at && (!lastAt || new Date(t.at) > lastAt)).slice(0, 8),
    upcoming: upcoming.map((a) => ({
      id: a._id, startAt: a.startAt, status: a.status, token: a.tokenNo ? String(a.tokenNo).padStart(2, '0') : null,
      doctorId: a.doctorId?._id || a.doctorId, doctorName: a.doctorId?.name || null, locationName: a.locationId?.shortName || a.locationId?.name || null, visitType: a.visitType,
    })),
  });
});

// The days a doctor sees patients at a place, for the desk's day strip and
// calendar: open or why not (weekly hours, leave, clinic closed), free / all times.
// ?doctorId &locationId &from=YYYY-MM-DD &days (max 42) &until=YYYY-MM-DD (a
// follow-up due later than the booking window: those days are offered too).
r.get('/appointments/booking/days', async (req, res) => {
  const { doctorId, locationId } = req.query;
  if (!isId(doctorId) || !isId(locationId)) throw badRequest('Choose the doctor and place');
  const dl = await M.DoctorLocation.findOne({ doctorId, locationId, practiceId: req.practiceId, status: 'active' }, 'schedule');
  if (!dl) throw badRequest("The doctor doesn't practise at this location", 'NOT_PRACTISING_HERE');
  const today = T.dayStart();
  const windowDays = deskWindow(dl);
  let last = T.addDays(today, windowDays);
  if (req.query.until) {
    const until = T.addDays(T.parseDay(req.query.until), 7);
    const cap = T.addDays(today, 120);
    if (until > last) last = until < cap ? until : cap;
  }
  const from = req.query.from ? new Date(Math.max(+T.parseDay(req.query.from), +today)) : today;
  const want = Math.min(Math.max(Number(req.query.days) || 14, 1), 42);
  const dayList = [];
  for (let i = 0; i < want; i += 1) {
    const d = T.addDays(from, i);
    if (d > last) break;
    dayList.push(d);
  }
  const days = await Promise.all(dayList.map(async (d) => {
    const out = await S.slotsFor({ doctorId, locationId, day: d });
    const free = out.slots.filter((x) => x.available).length;
    return { date: T.dayKey(d), open: Boolean(out.open), reason: out.open ? (free ? null : 'full') : out.reason || null, note: out.note || null, free, total: out.slots.length };
  }));
  res.json({ windowDays, firstDate: T.dayKey(today), lastDate: T.dayKey(last), days });
});

r.get('/appointments/:id', async (req, res) => {
  const a = await populate(M.Appointment.findOne({ _id: req.params.id, practiceId: req.practiceId }));
  if (!a) throw notFound('Appointment');
  await withPayments([a]);
  // Manage appointment: what can happen next (services/scheduling.js TRANSITIONS).
  res.json({ ...view(a), nextStatuses: S.TRANSITIONS[a.status] || [] });
});

r.post('/appointments', async (req, res) => {
  const { patientId, doctorId, locationId, startAt, visitType, mode, reason, walkIn, requestId, confirmed } = req.body;
  await patientInPractice(req, patientId);
  if (visitType && !E.VISIT_TYPES.includes(visitType)) throw badRequest('Unknown visit type');
  assertCovers(req, { locationId, doctorId: doctorId === 'me' || !doctorId ? req.user._id : doctorId }, { booking: true });
  const appt = await S.book({
    practiceId: req.practiceId, locationId, doctorId: doctorId === 'me' || !doctorId ? req.user._id : doctorId, patientId,
    startAt, visitType, mode, reason, walkIn: Boolean(walkIn), channel: 'desk', bookedBy: req.user._id, requestId,
    confirmed: confirmed === true,
  });
  // A doctor booking a follow-up visit ("Schedule a follow-up") with nothing
  // advised yet: it is kept as a booked follow-up, so Follow-ups lists it and
  // the visit closes it when it happens.
  if (visitType === 'follow_up' && req.member.role === 'doctor' && String(appt.doctorId) === String(req.user._id)
    && !(await M.FollowUp.exists({ appointmentId: appt._id }))) {
    await M.FollowUp.create({
      practiceId: req.practiceId, patientId: appt.patientId, doctorId: appt.doctorId, locationId: appt.locationId,
      dueDate: appt.date, status: 'booked', appointmentId: appt._id, adviceText: reason || undefined,
    });
  }
  res.status(201).json(view(await populate(M.Appointment.findById(appt._id))));
});

// "Register walk-in": into today's queue now (token, status waiting). The doctor
// is the one asking, else the only doctor seeing patients here; with several,
// the desk chooses (CHOOSE_DOCTOR lists them).
r.post('/appointments/walk-in', async (req, res) => {
  const { patientId } = req.body;
  await patientInPractice(req, patientId);
  const dls = await M.DoctorLocation.find({ practiceId: req.practiceId, status: 'active' }).populate('doctorId', 'name').populate('locationId', 'name status');
  const mine = req.member.allLocations || !req.member.locationIds?.length ? null : new Set(req.member.locationIds.map(String));
  let options = dls.filter((d) => d.locationId?.status === 'active' && (!mine || mine.has(String(d.locationId._id))));
  if (req.body.locationId) options = options.filter((d) => String(d.locationId._id) === String(req.body.locationId));
  const doctorId = req.body.doctorId || (req.member.role === 'doctor' ? String(req.user._id) : null);
  if (doctorId) options = options.filter((d) => String(d.doctorId?._id) === String(doctorId));
  if (!options.length) throw conflict('No doctor sees patients at this clinic yet. Add a doctor schedule first.', 'NO_DOCTOR_HERE');
  if (options.length > 1) {
    const photos = await require('../services/photos').doctorPhotos(options.map((d) => d.doctorId._id));
    const choices = options.map((d) => ({ doctorId: d.doctorId._id, doctorName: d.doctorId.name, doctorPhoto: photos.get(String(d.doctorId._id)) || null, locationId: d.locationId._id, locationName: d.locationId.name }));
    throw conflict('Choose the doctor for this walk-in', 'CHOOSE_DOCTOR', { choices });
  }
  const dl = options[0];
  // The complaint typed at the desk is the visit's reason (the queue row shows it).
  const reason = typeof req.body.reason === 'string' ? req.body.reason.trim().slice(0, 500) || undefined : undefined;
  // Already in today's list for this doctor: arrived / with the doctor → not twice. A
  // booking for today (they came in without saying) → checked in on that booking,
  // keeping its token and fee. A visit already done today, or with another doctor, is
  // no obstacle: a new walk-in.
  const todays = await M.Appointment.findOne({ patientId, doctorId: dl.doctorId._id, date: T.dayStart(), status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } }).sort({ startAt: 1 });
  if (todays && ['waiting', 'in_consultation'].includes(todays.status)) {
    throw conflict("This patient is already in today's list for this doctor", 'ALREADY_TODAY');
  }
  if (todays) {
    assertCovers(req, todays);
    if (reason && !todays.reason) todays.reason = reason;
    await S.transition(todays, 'waiting', { by: req.user._id });
    return res.status(201).json({ ...view(await populate(M.Appointment.findById(todays._id))), checkedInBooking: true });
  }
  const appt = await S.book({
    practiceId: req.practiceId, locationId: dl.locationId._id, doctorId: dl.doctorId._id, patientId,
    startAt: new Date(), visitType: req.body.visitType || 'new', mode: 'in_clinic', reason, walkIn: true, channel: 'desk', bookedBy: req.user._id,
  });
  // The doctor sees a new patient waiting (unless they added them themselves).
  if (String(dl.doctorId._id) !== String(req.user._id)) {
    const patient = await M.Patient.findById(patientId, 'name');
    // In-app only: the doctor's open queue updates at once (a buzz for every walk-in in a busy clinic is noise).
    await notify([dl.doctorId._id], { type: 'queue_update', push: false, practiceId: req.practiceId, title: `Walk-in: ${patient?.name || 'patient'} · token ${appt.tokenNo}`, body: `Waiting at ${dl.locationId.name}`, screen: 'Queue-List' }).catch(() => {});
  }
  res.status(201).json(view(await populate(M.Appointment.findById(appt._id))));
});

// Check in, start, complete, mark missed, confirm.
r.post('/appointments/:id/status', async (req, res) => {
  const appt = await S.getAppointment(req.params.id, req.practiceId);
  assertCovers(req, appt);
  const to = req.body.status;
  if (!E.APPOINTMENT_STATUSES.includes(to) || ['cancelled', 'rescheduled'].includes(to)) throw badRequest('Use /cancel or /reschedule for those');
  // "With the doctor": the doctor, or the desk / assistant sending the patient in.
  if (to === 'in_consultation' && !['doctor', 'front_desk', 'doctor_assistant', 'practice_manager'].includes(req.member.role)) {
    throw conflict('Only the doctor or the desk can send the patient in', 'ROLE_REQUIRED');
  }
  // Undo a check-in: only while still waiting (not after the doctor saw them).
  if (to === 'booked' && appt.status !== 'waiting') throw conflict('Only a check-in can be undone', 'BAD_TRANSITION');
  await S.transition(appt, to, { by: req.user._id });
  res.json(view(await populate(M.Appointment.findById(appt._id))));
});

r.post('/appointments/:id/reschedule', async (req, res) => {
  const appt = await S.getAppointment(req.params.id, req.practiceId);
  const loc = /^[0-9a-f]{24}$/i.test(String(req.body.locationId || '')) ? req.body.locationId : undefined;
  if (loc && !(await M.Location.exists({ _id: loc, practiceId: req.practiceId }))) throw badRequest("Choose one of this clinic's branches");
  assertCovers(req, appt);
  if (loc) assertCovers(req, { locationId: loc, doctorId: appt.doctorId });
  // Moving a follow-up visit books it again (S.book), which would also mark the
  // patient's next still-unbooked follow-up as booked: those stay as they were.
  const open = await M.FollowUp.find({ practiceId: req.practiceId, patientId: appt.patientId, status: { $in: ['not_booked', 'no_reply'] } }, 'status');
  const next = await S.reschedule(appt, req.body.startAt, req.user._id, loc);
  for (const fu of open) {
    await M.FollowUp.updateOne({ _id: fu._id, appointmentId: next._id, status: 'booked' }, { $set: { status: fu.status }, $unset: { appointmentId: 1 } });
  }
  res.json(view(await populate(M.Appointment.findById(next._id))));
});

r.post('/appointments/:id/cancel', async (req, res) => {
  const appt = await S.getAppointment(req.params.id, req.practiceId);
  assertCovers(req, appt);
  // The patient is told why: one of the quick reasons, or what was typed.
  const reason = typeof req.body.reason === 'string' ? req.body.reason.trim().slice(0, 300) : '';
  if (!reason) throw badRequest(`Choose why the visit is cancelled (${CANCEL_REASONS.join(', ')})`, 'REASON_REQUIRED');
  if (appt.status === 'completed') throw conflict("A visit that's done can't be cancelled", 'BAD_TRANSITION');
  if (['booked', 'confirmed'].includes(appt.status) && appt.date < T.dayStart()) {
    throw conflict("This visit's day has passed. Mark it as missed instead.", 'DAY_PASSED');
  }
  await S.transition(appt, 'cancelled', { by: req.user._id, cancelledBy: req.member.role === 'doctor' ? 'doctor' : 'desk', reason });
  // The follow-up this visit was for is due again (Follow-ups shows Book, not a dead View).
  await M.FollowUp.updateMany({ appointmentId: appt._id, status: 'booked' }, { $set: { status: 'not_booked' }, $unset: { appointmentId: 1 } });
  await M.FollowUp.updateMany({ appointmentId: appt._id, status: 'reports_in' }, { $unset: { appointmentId: 1 } });
  res.json(view(appt));
});

// ── Requests waiting for a time ──
r.get('/appointment-requests', async (req, res) => {
  const status = req.query.status || 'pending';
  const items = await M.AppointmentRequest.find({ practiceId: req.practiceId, status }).sort({ createdAt: status === 'pending' ? 1 : -1 }).limit(200)
    .populate('patientId', 'name gender ageYears ageRecordedAt phone userId').populate('doctorId', 'name');
  // The patient's profile photo for the row's avatar.
  const photos = await require('../services/photos').photosFor(items.map((x) => x.patientId?.userId));
  res.json(items.map((x) => ({ ...x.toJSON(), patientPhoto: x.patientId?.userId ? photos.get(String(x.patientId.userId)) || null : null })));
});

r.get('/appointment-requests/:id', async (req, res) => {
  const request = ownPractice(req, await M.AppointmentRequest.findById(req.params.id), 'Request');
  await request.populate([{ path: 'patientId', select: 'name gender ageYears ageRecordedAt phone' }, { path: 'doctorId', select: 'name' }, { path: 'locationId', select: 'name shortName' }]);
  res.json(request);
});

r.post('/appointment-requests/:id/assign', async (req, res) => {
  const request = ownPractice(req, await M.AppointmentRequest.findById(req.params.id), 'Request');
  if (request.status !== 'pending') throw conflict('This request was already handled');
  const doctorId = req.body.doctorId || request.doctorId;
  const locationId = req.body.locationId || request.locationId;
  if (!doctorId || !locationId) throw badRequest('Choose a doctor and location');
  assertCovers(req, { locationId, doctorId }, { booking: true });
  const appt = await S.book({
    practiceId: req.practiceId, locationId, doctorId, patientId: request.patientId, startAt: req.body.startAt,
    visitType: request.visitType, mode: request.mode, reason: request.reason, channel: request.channel, bookedBy: req.user._id, requestId: request._id,
  });
  Object.assign(request, { status: 'scheduled', appointmentId: appt._id, handledBy: req.user._id, handledAt: new Date() });
  await request.save();
  res.json({ request, appointment: view(await populate(M.Appointment.findById(appt._id))) });
});

r.post('/appointment-requests/:id/decline', async (req, res) => {
  const request = ownPractice(req, await M.AppointmentRequest.findById(req.params.id), 'Request');
  if (request.status !== 'pending') throw conflict('This request was already handled');
  Object.assign(request, { status: 'declined', declineReason: req.body.reason, handledBy: req.user._id, handledAt: new Date() });
  await request.save();
  const patient = await M.Patient.findById(request.patientId, 'userId');
  if (patient?.userId) await notify([patient.userId], { type: 'request_declined', practiceId: req.practiceId, title: 'Your visit request was declined', body: req.body.reason, screen: 'Patient-Doctors' });
  res.json(request);
});

// ── Queue (Queue-Select / Queue-List) ──
r.get('/queue/locations', async (req, res) => {
  const dls = await M.DoctorLocation.find({ doctorId: req.user._id, status: 'active' }).populate('locationId');
  const profile = await M.DoctorProfile.findOne({ userId: req.user._id }, 'defaultQueueLocation');
  const today = T.dayStart();
  const out = [];
  for (const dl of dls) {
    const loc = dl.locationId;
    const { open, slots, reason } = await S.slotsFor({ doctorId: req.user._id, locationId: loc._id, day: today });
    const counts = await M.Appointment.aggregate([
      { $match: { doctorId: req.user._id, locationId: loc._id, date: today, status: { $nin: ['cancelled', 'rescheduled'] } } },
      { $group: { _id: '$status', n: { $sum: 1 } } },
    ]);
    const by = Object.fromEntries(counts.map((c) => [c._id, c.n]));
    let nextSession = null;
    if (!open) {
      for (let i = 1; i <= 14 && !nextSession; i += 1) {
        const s = await S.slotsFor({ doctorId: req.user._id, locationId: loc._id, day: T.addDays(today, i) });
        if (s.open && s.slots.length) nextSession = s.slots[0].startAt;
      }
    }
    const now = T.minuteOfDay(new Date());
    const sessions = (dl.schedule.week.find((w) => w.weekday === T.weekday(today)) || {}).sessions || [];
    out.push({
      locationId: loc._id, name: loc.name, type: loc.type,
      sessions, openNow: open && sessions.some((s) => now >= s.startMin && now < s.endMin),
      opensAt: open ? sessions.find((s) => s.startMin > now)?.startMin ?? null : null,
      closedReason: open ? null : reason, nextSession,
      booked: Object.values(by).reduce((a, b) => a + b, 0), waiting: by.waiting || 0, slotsLeft: slots.filter((s) => s.available).length,
      // Still to be seen today here (booked, arrived, with the doctor): the queue opens where these are.
      inConsult: by.in_consultation || 0,
      pending: (by.booked || 0) + (by.confirmed || 0) + (by.waiting || 0) + (by.in_consultation || 0),
    });
  }
  const def = profile?.defaultQueueLocation;
  res.json({ defaultLocationId: def?.forDate && def?.locationId && T.dayKey(def.forDate) === T.dayKey(new Date()) ? def.locationId : null, items: out });
});

r.get('/queue', async (req, res) => {
  const day = T.parseDay(req.query.date);
  const q = { practiceId: req.practiceId, date: day, status: { $nin: ['cancelled', 'rescheduled'] } };
  if (req.query.locationId) q.locationId = req.query.locationId;
  q.doctorId = req.query.doctorId || (req.member.role === 'doctor' ? req.user._id : undefined);
  if (!q.doctorId) delete q.doctorId;
  const appts = await withPayments(await populate(M.Appointment.find(q).sort({ tokenNo: 1 })));
  const ids = appts.map((a) => a._id);
  const patientIds = appts.map((a) => a.patientId._id);
  const [vitals, docs, briefs] = await Promise.all([
    M.Vitals.find({ appointmentId: { $in: ids } }).distinct('appointmentId'),
    M.MedicalRecord.aggregate([{ $match: { patientId: { $in: patientIds }, deletedAt: null, createdAt: { $gte: T.addDays(day, -7) } } }, { $group: { _id: '$patientId', n: { $sum: 1 } } }]),
    M.AiSummary.find({ patientId: { $in: patientIds }, audience: 'doctor', generatedAt: { $gte: T.addDays(day, -1) } }).distinct('patientId'),
  ]);
  const vset = new Set(vitals.map(String));
  const dmap = new Map(docs.map((d) => [String(d._id), d.n]));
  const bset = new Set(briefs.map(String));
  const waitTimes = appts.filter((a) => a.arrivedAt && a.consultStartedAt).map((a) => (a.consultStartedAt - a.arrivedAt) / 60000);
  const waiting = appts.filter((a) => a.status === 'waiting');
  const usualWait = waitTimes.length ? waitTimes.reduce((s, x) => s + x, 0) / waitTimes.length : 20;
  const nextId = waiting.sort((a, b) => a.tokenNo - b.tokenNo)[0]?._id;
  const items = appts.map((a) => {
    const v = view(a);
    return {
      ...v,
      hasVitals: vset.has(String(a._id)),
      documents: dmap.get(String(a.patientId._id)) || 0,
      aiBrief: bset.has(String(a.patientId._id)),
      isNext: String(a._id) === String(nextId),
      longWait: v.waitingMin != null && v.waitingMin > usualWait * 1.5,
      consultMin: a.consultStartedAt ? Math.round(((a.completedAt || new Date()) - a.consultStartedAt) / 60000) : null,
    };
  });
  const count = (s) => appts.filter((a) => a.status === s).length;
  // No front desk here: the doctor checks patients in and collects fees from the queue.
  const hasDesk = await require('../services/notify').hasDesk(req.practiceId, req.query.locationId || undefined);
  res.json({
    updatedAt: new Date(),
    hasDesk,
    stats: {
      all: appts.length, notArrived: count('booked') + count('confirmed'), waiting: count('waiting'), inConsultation: count('in_consultation'),
      completed: count('completed'), missed: count('missed'), avgWaitMin: waitTimes.length ? Math.round(usualWait) : null,
    },
    items,
  });
});

// Staff-Today: the front desk's day.
r.get('/staff/today', async (req, res) => {
  const today = T.dayStart();
  const locIds = req.member.allLocations ? undefined : req.member.locationIds;
  const q = { practiceId: req.practiceId, date: today, status: { $nin: ['cancelled', 'rescheduled'] }, ...(locIds?.length ? { locationId: { $in: locIds } } : {}) };
  const [appts, requests, unreadConvos] = await Promise.all([
    populate(M.Appointment.find(q).sort({ startAt: 1 })).then(withPayments),
    M.AppointmentRequest.find({ practiceId: req.practiceId, status: 'pending' }).sort({ createdAt: 1 }).populate('patientId', 'name').populate('doctorId', 'name'),
    M.Conversation.countDocuments({ practiceId: req.practiceId, participants: { $elemMatch: { userId: req.user._id, unreadCount: { $gt: 0 } } } }),
  ]);
  const doctors = [...new Set(appts.map((a) => a.doctorId?.name).filter(Boolean))];
  const count = (...s) => appts.filter((a) => s.includes(a.status)).length;
  res.json({
    date: today,
    summary: { booked: appts.length, checkedIn: count('waiting', 'in_consultation', 'completed'), done: count('completed'), missed: count('missed'), doctors },
    unreadChats: unreadConvos,
    unreadNotifications: await M.Notification.countDocuments({ userId: req.user._id, practiceId: req.practiceId, readAt: null }),
    userName: req.user.name,
    requests,
    items: appts.map(view),
  });
});

// Doctor-History: month summary + list.
// A consultation issued straight from a patient (Consult-Pick / the profile, no
// appointment) is a visit too: it is listed and counted as completed, so the
// doctor's history is not empty when they never booked a slot.
const ISSUED = ['issued', 'sent'];
const consultView = (c) => {
  const p = c.patientId && c.patientId.name ? c.patientId : null;
  const rx = c.prescriptionId && c.prescriptionId._id ? c.prescriptionId : null;
  const at = c.completedAt || c.startedAt;
  return {
    id: c._id,
    kind: 'consultation',
    consultationId: c._id,
    status: 'completed',
    startAt: at,
    date: T.dayStart(at),
    visitType: null,
    mode: 'in_clinic',
    walkIn: false,
    consultStartedAt: c.startedAt,
    completedAt: c.completedAt || null,
    reason: c.chiefComplaint || null,
    diagnosis: (c.diagnoses || []).map((d) => d.name).filter(Boolean).join(', ') || rx?.diagnosisSummary || null,
    prescriptionId: rx ? rx._id : c.prescriptionId || null,
    rxNumber: rx?.rxNumber ?? null,
    patient: p ? { id: p._id, name: p.name, age: T.ageFrom(p), gender: p.gender, phone: p.phone, conditions: (p.conditions || []).map((x) => x.name) } : undefined,
    patientId: p ? p._id : c.patientId,
    doctor: c.doctorId?.name ? { id: c.doctorId._id, name: c.doctorId.name } : undefined,
    doctorId: c.doctorId?._id || c.doctorId,
    location: c.locationId?.name ? { id: c.locationId._id, name: c.locationId.shortName || c.locationId.name } : undefined,
    locationId: c.locationId?._id || c.locationId,
  };
};

r.get('/history', async (req, res) => {
  const period = req.query.period || 'this_month';
  const now = new Date();
  const from = req.query.from ? T.parseDay(req.query.from) : period === 'last_3_months' ? T.addDays(T.dayStart(), -90) : period === 'this_year' ? new Date(`${now.getFullYear()}-01-01T00:00:00+05:30`) : new Date(`${T.dayKey(now).slice(0, 7)}-01T00:00:00+05:30`);
  const to = req.query.to ? T.addDays(T.parseDay(req.query.to), 1) : T.addDays(T.dayStart(), 1);
  const q = { practiceId: req.practiceId, date: { $gte: from, $lt: to } };
  const mineOnly = req.member.role === 'doctor' && req.query.all !== 'true';
  if (mineOnly) q.doctorId = req.user._id;
  const statuses = req.query.status ? list(req.query.status) : null;
  if (statuses) q.status = { $in: statuses };
  const cq = {
    practiceId: req.practiceId, appointmentId: null, status: { $in: ISSUED }, startedAt: { $gte: from, $lt: to },
    ...(mineOnly ? { doctorId: req.user._id } : {}),
  };
  const withConsults = !statuses || statuses.includes('completed');
  const { limit, skip } = paging(req.query, 200);
  // Both lists are newest first; take enough of each to fill this page after merging.
  const upTo = skip + limit;
  const [appts, totals, consults, consultCount] = await Promise.all([
    populate(M.Appointment.find(q).sort({ startAt: -1 }).limit(upTo)),
    M.Appointment.aggregate([{ $match: { ...q, status: { $exists: true } } }, { $group: { _id: '$status', n: { $sum: 1 } } }]),
    withConsults
      ? populateCore(M.Consultation.find(cq).sort({ startedAt: -1 }).limit(upTo)).populate('prescriptionId', 'rxNumber diagnosisSummary')
      : [],
    // Counted like the appointment totals above (whatever status filter is set).
    M.Consultation.countDocuments(cq),
  ]);
  // A completed appointment's own prescription, so "Prescription" opens it.
  const apptIds = appts.filter((a) => a.status === 'completed').map((a) => a._id);
  const linked = apptIds.length
    ? await M.Consultation.find({ appointmentId: { $in: apptIds }, status: { $in: ISSUED } }, 'appointmentId prescriptionId diagnoses').sort({ startedAt: -1 })
    : [];
  const byAppt = new Map();
  for (const c of linked) if (!byAppt.has(String(c.appointmentId))) byAppt.set(String(c.appointmentId), c);
  const rows = [
    ...appts.map((a) => {
      const c = byAppt.get(String(a._id));
      const v = view(a);
      return c ? { ...v, consultationId: c._id, prescriptionId: c.prescriptionId || null, diagnosis: (c.diagnoses || []).map((d) => d.name).filter(Boolean).join(', ') || null } : v;
    }),
    ...consults.map(consultView),
  ].sort((a, b) => new Date(b.startAt) - new Date(a.startAt)).slice(skip, upTo);
  const by = Object.fromEntries(totals.map((t) => [t._id, t.n]));
  const completed = (by.completed || 0) + consultCount;
  res.json({
    from, to,
    summary: { completed, missed: by.missed || 0, cancelled: by.cancelled || 0, total: Object.values(by).reduce((a, b) => a + b, 0) + consultCount },
    items: rows,
  });
});

// ── Payments (Report-Fees pending list, Mark as paid, payment link) ──
r.get('/payments', async (req, res) => {
  const q = { practiceId: req.practiceId };
  if (req.query.status) q.status = req.query.status;
  const items = await M.Payment.find(q).sort({ createdAt: -1 }).limit(200).populate('patientId', 'name phone').populate('locationId', 'name shortName').populate('appointmentId', 'startAt mode status payAt');
  res.json(items);
});

r.post('/payments/:id/mark-paid', async (req, res) => {
  const p = ownPractice(req, await M.Payment.findById(req.params.id), 'Payment');
  if (!E.PAYMENT_METHODS.includes(req.body.method)) throw badRequest('Choose how it was paid');
  assertCovers(req, (await paymentScope(p)).scope);
  // Already paid (online, or by someone else at the desk): not taken twice.
  if (p.status !== 'pending') throw conflict(p.status === 'paid' ? 'This fee is already paid' : 'This fee is not due', 'NOT_PENDING');
  Object.assign(p, { status: 'paid', method: req.body.method, paidAt: new Date(), markedPaidBy: req.user._id });
  await p.save();
  if (p.appointmentId) {
    await M.Appointment.updateOne({ _id: p.appointmentId }, { feeStatus: 'paid', payAt: 'clinic' });
    await require('../services/payments').feeReceipt(p).catch((err) => console.warn('[fee receipt]', err.message));
    // Every open list showing this visit's fee (desk, doctor's queue) updates.
    const appt = await M.Appointment.findById(p.appointmentId, 'practiceId locationId doctorId patientId');
    if (appt) await S.visitsChanged(appt);
  }
  res.json(p);
});

// Give a visit fee back: retry an online refund, or "handed back" at the desk.
r.post('/payments/:id/refund', async (req, res) => {
  const p = ownPractice(req, await M.Payment.findById(req.params.id), 'Payment');
  if (p.status !== 'paid') throw conflict(p.status === 'refunded' ? 'Already refunded' : 'Nothing was paid', 'NOT_PAID');
  const { appt: visit, scope } = await paymentScope(p);
  assertCovers(req, scope);
  // Already decided (the visit was cancelled: hand it back, or retry the online refund):
  // the desk carries it out. Money back on a visit that wasn't cancelled (goodwill, an
  // overcharge) is the doctor's, owner's or practice manager's call.
  const decided = p.refundDue === true || visit?.status === 'cancelled';
  if (!decided) {
    if (!req.member.isOwner && !req.perms?.refunds) {
      throw forbidden("Only the doctor, owner or practice manager can refund a visit that wasn't cancelled", 'PERMISSION_REQUIRED');
    }
    const why = typeof req.body.reason === 'string' ? req.body.reason.trim().slice(0, 300) : '';
    p.refundReason = why || 'Refund';
  }
  const out = await require('../services/payments').refundFee(p, { by: req.user._id, handedBack: req.body.handedBack === true });
  const appt = p.appointmentId ? await M.Appointment.findById(p.appointmentId, 'practiceId locationId doctorId patientId') : null;
  if (appt) await S.visitsChanged(appt);
  res.json(out);
});

// Let a fee go (nothing to pay for this visit): the doctor, owner or practice manager.
r.post('/payments/:id/waive', async (req, res) => {
  const p = ownPractice(req, await M.Payment.findById(req.params.id), 'Payment');
  if (!req.member.isOwner && !req.perms?.refunds) throw forbidden('Only the doctor, owner or practice manager can waive a fee', 'PERMISSION_REQUIRED');
  const { appt: visit, scope } = await paymentScope(p);
  assertCovers(req, scope);
  if (p.status !== 'pending') throw conflict(p.status === 'paid' ? 'This fee is already paid. Refund it instead.' : 'This fee is not due', 'NOT_PENDING');
  const why = typeof req.body.reason === 'string' ? req.body.reason.trim().slice(0, 300) : '';
  Object.assign(p, { status: 'waived', waivedBy: req.user._id, waivedAt: new Date(), note: why || 'Fee waived' });
  await p.save();
  if (visit) {
    await M.Appointment.updateOne({ _id: visit._id }, { feeStatus: 'waived' });
    await require('../services/care').chatNote(
      { practiceId: visit.practiceId, patientId: visit.patientId, locationId: visit.locationId, doctorId: visit.doctorId, by: req.user._id },
      `No fee for your visit: the ₹${p.amount} fee has been waived.`, 'fee_waived',
    );
    const patient = await M.Patient.findById(visit.patientId, 'userId');
    if (patient?.userId) {
      await notify([patient.userId], { type: 'fee_waived', practiceId: req.practiceId, title: 'No fee for your visit', body: `The ₹${p.amount} fee has been waived.`, screen: 'Patient-Doctors' }).catch(() => {});
    }
    await S.visitsChanged(visit);
  }
  res.json(p);
});

r.post('/payments/:id/link', async (req, res) => {
  const p = ownPractice(req, await M.Payment.findById(req.params.id), 'Payment');
  assertCovers(req, (await paymentScope(p)).scope);
  if (p.status !== 'pending') throw conflict('This fee is not pending');
  const patient = await M.Patient.findById(p.patientId, 'name phone userId');
  if (!patient?.userId && !patient?.phone) throw badRequest('This patient has no phone number or MedPin app to send a link to. Collect the fee at the counter.', 'NO_CONTACT');
  const url = await require('../services/payments').feeLink(p, patient);
  // Also in the clinic chat (a card with Pay), signed by whoever sent it.
  const conversationId = await require('../services/care').paymentRequestNote(p, { by: req.user._id }).catch((err) => { console.warn('[payment note]', err.message); return null; });
  if (patient.userId) {
    // One notice per fee: sending it again replaces the earlier one (no pile of "Pay ₹600").
    await M.Notification.deleteMany({ userId: patient.userId, type: 'payment_link', 'params.paymentId': String(p._id) });
    await notify([patient.userId], {
      type: 'payment_link', practiceId: req.practiceId, title: `Pay ₹${p.amount} for your visit`, body: `Tap to pay in the app, or open ${url}`, whatsapp: true,
      ...(conversationId ? { screen: 'Patient-DoctorChat', params: { conversationId, paymentId: String(p._id) } } : { params: { paymentId: String(p._id) } }),
    });
  }
  // Where it went, for the toast ("on the MedPin app" / "by SMS").
  res.json({ ...p.toJSON(), sentTo: patient.userId ? 'app' : 'sms' });
});

module.exports = r;

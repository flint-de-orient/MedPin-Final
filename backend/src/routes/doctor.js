// Doctor-MyProfile, Profile-Professional, Profile-Location, Profile-Schedule, Queue-Select default.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, unprocessable, isId, forbidden } = require('../lib/http');
const storage = require('../services/storage');
const { slotsFor, nextFreeSlot } = require('../services/scheduling');

const { uploader } = require('../lib/uploads');
const photoUpload = uploader({ kinds: ['image'], maxMb: 5, maxFiles: 1 });
const proofUpload = uploader({ kinds: ['image', 'pdf'], maxMb: 10, maxFiles: 1 });
const r = Router();
r.use(requireAuth, staff());

// A practitioner's own set-up — payouts, qualifications, signature, hours, leave, letterhead —
// is for those who see patients (doctors, the dietician). Assistants in the doctor panel
// keep their own notification and chat settings (PATCH /doctor/profile, below).
const PRACTITIONERS = ['doctor', 'dietician'];
const isPractitioner = (req) => PRACTITIONERS.includes(req.member?.role);
const PRACTITIONER_ONLY = /^\/doctor\/(payouts|qualifications|profile\/signature|leaves|letterhead)(\/|$)|^\/doctor\/locations\/./;
r.use((req, res, next) => {
  const write = req.method !== 'GET';
  if (PRACTITIONER_ONLY.test(req.path) && (write || /^\/doctor\/(payouts|leaves|letterhead)/.test(req.path)) && !isPractitioner(req)) {
    throw forbidden('This is for doctors only', 'DOCTORS_ONLY');
  }
  next();
});

const profileOf = async (userId) => {
  let p = await M.DoctorProfile.findOne({ userId });
  if (!p) {
    const user = await M.User.findById(userId, 'name');
    p = await M.DoctorProfile.create({ userId, displayName: user?.name || 'Doctor' });
  }
  return p;
};

const completion = (p) => {
  const checks = [p.photo?.key, p.bio, p.languagesSpoken?.length, p.qualifications?.length, p.registration?.number, p.specialisations?.length, p.signature?.key];
  return Math.round((checks.filter(Boolean).length / checks.length) * 100);
};

const profileView = (p) => ({
  ...p.toJSON(),
  photo: storage.withUrl(p.photo),
  signature: storage.withUrl(p.signature),
  signatureOriginal: undefined,
  qualifications: p.qualifications.map((q) => ({ ...q.toJSON(), proof: storage.withUrl(q.proof) })),
  yearsExperience: p.practisingSince ? new Date().getFullYear() - p.practisingSince : null,
  registrationDisplay: p.registration?.number ? `${p.registration.councilShort || ''} ${p.registration.number}`.trim() : null,
  completionPct: completion(p),
  isVerified: p.verifiedNow(),
});

r.get('/doctor/profile', async (req, res) => {
  const p = await profileOf(req.user._id);
  const locs = await M.DoctorLocation.find({ doctorId: req.user._id, status: 'active' }).populate('locationId', 'name shortName');
  const leave = await M.DoctorLeave.findOne({ doctorId: req.user._id, cancelledAt: null, endDate: { $gte: T.dayStart() } }).sort({ startDate: 1 });
  let next = null;
  for (const l of locs) {
    const s = await nextFreeSlot({ doctorId: req.user._id, locationId: l.locationId._id });
    if (s && (!next || s.startAt < next.startAt)) next = { ...s, location: l.locationId.shortName || l.locationId.name };
  }
  res.json({
    ...profileView(p),
    locations: locs.length,
    services: locs.reduce((n, l) => n + l.services.length, 0),
    upcomingLeave: leave,
    nextFreeSlot: next,
  });
});

const PROFILE_FIELDS = ['displayName', 'gender', 'profession', 'headline', 'specialtyKeys', 'specialisations', 'conditionsTreated', 'memberships', 'languagesSpoken', 'degreesSummary', 'practisingSince', 'registration', 'hprId', 'bio', 'offersVideo', 'acceptingBookings', 'presence', 'avgReplyMinutes', 'followUpReminder', 'payout', 'chatSettings', 'notificationPrefs'];
// Case-insensitive de-duplication that keeps the first spelling.
const dedupe = (list) => {
  const seen = new Map();
  for (const x of (list || []).map((s) => String(s).trim()).filter(Boolean)) if (!seen.has(x.toLowerCase())) seen.set(x.toLowerCase(), x);
  return [...seen.values()];
};

r.patch('/doctor/profile', async (req, res) => {
  const p = await profileOf(req.user._id);
  // Others in the doctor panel (an assistant): only their own name and settings.
  const body = pick(req.body, isPractitioner(req) ? PROFILE_FIELDS : ['displayName', 'chatSettings', 'notificationPrefs']);
  for (const k of ['specialisations', 'conditionsTreated', 'memberships']) if (body[k]) body[k] = dedupe(body[k]);
  if (body.registration) {
    body.registration = { ...(p.registration?.toObject?.() || {}), ...body.registration };
    if (req.body.registration.number && req.body.registration.number !== p.registration?.number) body.registration.status = 'in_review';
  }
  if (body.hprId && !/^(\d{2}-?\d{4}-?\d{4}-?\d{4}|[a-zA-Z0-9._]{3,}@hpr\.abdm)$/.test(String(body.hprId).trim())) throw badRequest('Enter your HPR ID like 71-1234-5678-9012 or name@hpr.abdm', 'BAD_HPR_ID');
  if (body.hprId && body.hprId !== p.hprId) p.hprLinkedAt = new Date();
  // Payouts: keep only the last 4 digits of a full account number.
  if (body.payout) {
    const acc = String(req.body.payout.accountNumber || '').replace(/\s/g, '');
    if (acc && !/^\d{9,18}$/.test(acc)) throw badRequest('Enter the bank account number (9–18 digits)', 'BAD_ACCOUNT');
    const banks = require('../services/banks');
    if (req.body.payout.upiId && !banks.upiInfo(req.body.payout.upiId).valid) throw badRequest('Enter a UPI ID like name@bank', 'BAD_UPI');
    // The IFSC decides the bank and branch (RBI directory), not what was typed.
    let fromIfsc = {};
    if (req.body.payout.ifsc) {
      const info = await banks.ifscInfo(req.body.payout.ifsc);
      if (!info.valid) throw badRequest('Enter an 11-character IFSC like HDFC0001234', 'BAD_IFSC');
      if (info.found === false) throw badRequest(`IFSC ${info.ifsc} doesn't exist. Check it on your cheque book or bank app.`, 'IFSC_NOT_FOUND');
      if (info.bank) fromIfsc = { bankName: info.bank, bankBranch: [info.branch, info.city].filter(Boolean).join(', ') || undefined };
    }
    body.payout = {
      ...(p.payout?.toObject?.() || {}),
      ...pick(req.body.payout, ['upiId', 'accountHolder', 'bankName', 'ifsc', 'preferred']),
      ...fromIfsc,
      ...(acc ? { bankAccountLast4: acc.slice(-4) } : {}),
      updatedAt: new Date(),
    };
  }
  for (const k of ['chatSettings', 'notificationPrefs']) {
    if (body[k]) body[k] = { ...(p[k]?.toObject?.() || {}), ...body[k] };
  }
  // Times are HH:MM (IST); anything else keeps the saved time, since notify.js,
  // presence.js and the away reply all compare clock times with them.
  const hhmm = (v) => /^([01]\d|2[0-3]):[0-5]\d$/.test(String(v));
  if (body.notificationPrefs?.digestAt !== undefined && !hhmm(body.notificationPrefs.digestAt)) {
    body.notificationPrefs.digestAt = p.notificationPrefs?.digestAt || '08:00';
  }
  for (const [k, sub, defaults] of [['notificationPrefs', 'quietHours', { from: '22:00', to: '07:00' }], ['chatSettings', 'replyHours', { from: '09:00', to: '20:00' }]]) {
    const v = body[k]?.[sub];
    if (!v) continue;
    const saved = p[k]?.[sub] || {};
    body[k][sub] = { ...(saved.toObject?.() || saved), ...v };
    for (const t of ['from', 'to']) if (!hhmm(body[k][sub][t])) body[k][sub][t] = saved[t] || defaults[t];
  }
  if (body.chatSettings?.awayMessage !== undefined) body.chatSettings.awayMessage = String(body.chatSettings.awayMessage || '').trim().slice(0, 300);
  Object.assign(p, body);
  // New payout details: set up where RazorpayX sends the money (needs the full account number now).
  if (body.payout) {
    await require('../services/payouts').linkPayoutAccount(p, String(req.body.payout.accountNumber || '').replace(/\s/g, '') || undefined).catch((err) => {
      console.warn('[payout account]', err.message);
    });
  }
  await p.save();
  if (body.displayName) await M.User.updateOne({ _id: req.user._id }, { name: body.displayName });
  res.json(profileView(p));
});

r.post('/doctor/profile/photo', photoUpload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Choose a photo');
  const p = await profileOf(req.user._id);
  p.photo = await storage.save(req.file.buffer, { folder: 'photos', name: req.file.originalname, mimeType: req.file.mimetype });
  await p.save();
  await M.User.updateOne({ _id: req.user._id }, { photo: p.photo }); // shown in the app's headers too
  res.json(profileView(p));
});

// "Printed on every prescription". Every upload goes through the signature
// checker: clear problems are refused (422 SIGNATURE_REJECTED); doubts such as
// a different name come back as 409 SIGNATURE_CHECK until sent again with
// accept=true. The cleaned, transparent version is what prints.
r.post('/doctor/profile/signature', photoUpload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Choose a signature image');
  const p = await profileOf(req.user._id);
  const result = await require('../services/signature').check(req.file.buffer, p.displayName);
  if (result.status === 'rejected') {
    throw unprocessable(result.issues.find((x) => x.severity === 'block').message, 'SIGNATURE_REJECTED', { issues: result.issues });
  }
  const accept = req.body.accept === 'true' || req.body.accept === true;
  if (result.status === 'warn' && !accept) {
    throw conflict('Please check this signature', 'SIGNATURE_CHECK', { issues: result.issues, readsAs: result.readsAs });
  }
  p.signatureOriginal = await storage.save(req.file.buffer, { folder: 'signatures', name: req.file.originalname, mimeType: req.file.mimetype });
  p.signature = result.cleaned
    ? await storage.save(result.cleaned, { folder: 'signatures', name: 'signature.png', mimeType: 'image/png' })
    : p.signatureOriginal;
  p.signatureCheck = { status: result.status, issues: result.issues, readsAs: result.readsAs, by: result.by, acceptedWarnings: result.status === 'warn', checkedAt: new Date() };
  await p.save();
  res.json(profileView(p));
});

// Check the signature already on file again (e.g. one added before the checker).
r.post('/doctor/profile/signature/recheck', async (req, res) => {
  const p = await profileOf(req.user._id);
  const file = p.signatureOriginal?.key ? p.signatureOriginal : p.signature;
  if (!file?.key) throw badRequest('Add a signature first', 'NO_SIGNATURE');
  const result = await require('../services/signature').check(await storage.read(file.key), p.displayName);
  const kept = p.signatureCheck?.acceptedWarnings && result.status === 'warn';
  p.signatureCheck = {
    status: result.status === 'rejected' ? 'warn' : result.status,
    // A stored signature that would now be refused stays usable but says why it should be replaced.
    issues: result.issues.map((x) => (x.severity === 'block' ? { ...x, severity: 'warn' } : x)),
    readsAs: result.readsAs, by: result.by, acceptedWarnings: kept, checkedAt: new Date(),
  };
  if (result.cleaned && !p.signatureOriginal?.key) {
    // First check of an old upload: keep the photo as the original and print the cleaned one.
    p.signatureOriginal = p.signature;
    p.signature = await storage.save(result.cleaned, { folder: 'signatures', name: 'signature.png', mimeType: 'image/png' });
  }
  await p.save();
  res.json(profileView(p));
});

// Payout form: IFSC → bank and branch; UPI ID → app and bank (services/banks.js).
r.get('/banks/ifsc/:code', async (req, res) => res.json(await require('../services/banks').ifscInfo(req.params.code)));
r.get('/banks/upi', async (req, res) => {
  const banks = require('../services/banks');
  const info = banks.upiInfo(req.query.vpa);
  // With Razorpay set up: is the UPI ID real, and whose name is on it.
  res.json(info.valid ? { ...info, ...(await banks.verifyVpa(info.vpa)) } : info);
});

// Online fees: what is waiting, the next payout day, past payouts.
r.get('/doctor/payouts', async (req, res) => res.json(await require('../services/payouts').summary(req.user._id)));

r.post('/doctor/qualifications', async (req, res) => {
  const p = await profileOf(req.user._id);
  if (!req.body.name || !String(req.body.name).trim()) throw badRequest('Enter the qualification');
  p.qualifications.push({ ...pick(req.body, ['name', 'institution', 'year']), proofStatus: 'upload' });
  await p.save();
  res.status(201).json(profileView(p));
});

r.delete('/doctor/qualifications/:qid', async (req, res) => {
  const p = await profileOf(req.user._id);
  p.qualifications.pull(req.params.qid);
  await p.save();
  res.json(profileView(p));
});

// "Upload proof" → In review
r.post('/doctor/qualifications/:qid/proof', proofUpload.single('file'), async (req, res) => {
  const p = await profileOf(req.user._id);
  const q = p.qualifications.id(req.params.qid);
  if (!q) throw notFound('Qualification');
  if (!req.file) throw badRequest('Choose the proof document');
  q.proof = await storage.save(req.file.buffer, { folder: 'proofs', name: req.file.originalname, mimeType: req.file.mimetype });
  q.proofStatus = 'review';
  q.proofNote = undefined;
  await p.save();
  await require('../services/verification').requestReview(p, q);
  res.json(profileView(p));
});

// ── Where I practise: services/fees and weekly schedule per location ──
r.get('/doctor/locations', async (req, res) => {
  const items = await M.DoctorLocation.find({ doctorId: req.user._id }).populate('locationId');
  res.json(items);
});

const validSchedule = (schedule) => {
  for (const day of schedule?.week || []) {
    if (!E.WEEKDAYS.includes(day.weekday)) throw badRequest('Unknown weekday');
    for (const s of day.sessions || []) {
      if (!(s.endMin > s.startMin)) throw badRequest('Enter times like 9:00 and 1:00', 'BAD_HOURS');
    }
  }
};

r.put('/doctor/locations/:locationId', async (req, res) => {
  const loc = await M.Location.findOne({ _id: req.params.locationId, practiceId: req.practiceId });
  if (!loc) throw notFound('Location');
  if (loc.status !== 'active') throw conflict('This location is not active');
  const body = pick(req.body, ['services', 'schedule']);
  validSchedule(body.schedule);
  let dl = await M.DoctorLocation.findOne({ doctorId: req.user._id, locationId: loc._id });
  if (!dl) dl = new M.DoctorLocation({ doctorId: req.user._id, locationId: loc._id, practiceId: req.practiceId });
  if (body.services) dl.services = body.services;
  if (body.schedule) {
    const s = { ...dl.schedule?.toObject?.(), ...body.schedule };
    // Walk-in places are kept per session: no more than the longest session has slots.
    const step = (s.slotLengthMin || 15) + (s.breakBetweenMin || 0);
    const lengths = (s.week || []).flatMap((d) => (d.sessions || []).map((x) => x.endMin - x.startMin)).filter((n) => n > 0);
    const slots = lengths.length ? Math.max(...lengths.map((n) => (n < (s.slotLengthMin || 15) ? 0 : Math.floor((n - (s.slotLengthMin || 15)) / step) + 1))) : null;
    if (slots != null && s.walkInPlaces > slots) s.walkInPlaces = slots;
    dl.schedule = s;
  }
  dl.status = 'active';
  dl.endedAt = undefined;
  await dl.save();
  res.json(dl);
});

// Copy hours from another location ("Copy hours").
r.post('/doctor/locations/:locationId/copy-from/:fromId', async (req, res) => {
  const from = await M.DoctorLocation.findOne({ doctorId: req.user._id, locationId: req.params.fromId });
  const to = await M.DoctorLocation.findOne({ doctorId: req.user._id, locationId: req.params.locationId });
  if (!from || !to) throw notFound('Location schedule');
  to.schedule.week = from.schedule.week;
  await to.save();
  res.json(to);
});

// "Stop practising here" — bookings stop, history is kept.
r.post('/doctor/locations/:locationId/stop', async (req, res) => {
  const dl = await M.DoctorLocation.findOneAndUpdate(
    { doctorId: req.user._id, locationId: req.params.locationId },
    { status: 'ended', endedAt: new Date() },
    { new: true },
  );
  if (!dl) throw notFound('Location');
  res.json(dl);
});

r.get('/doctors/:doctorId/slots', async (req, res) => {
  const { locationId, date } = req.query;
  if (!locationId) throw badRequest('locationId is required');
  res.json(await slotsFor({ doctorId: req.params.doctorId, locationId, day: T.parseDay(date) }));
});

// Doctors of this practice (for booking pickers).
r.get('/doctors', async (req, res) => {
  // Who can be booked (doctors and the dietician), at open branches — as far as this person
  // books: an assistant for the doctors they assist, branch staff at their branches.
  const me = req.member || {};
  const locs = me.role === 'doctor' || me.isOwner || me.allLocations || !me.locationIds?.length ? null : me.locationIds.map(String);
  const docs = me.role === 'doctor_assistant' && me.assistsDoctorIds?.length ? me.assistsDoctorIds.map(String) : null;
  const members = await M.Member.find({ practiceId: req.practiceId, role: { $in: ['doctor', 'dietician'] }, status: 'active' }).populate('userId', 'name');
  const dls = await M.DoctorLocation.find({ practiceId: req.practiceId, status: 'active' }).populate('locationId', 'name shortName status');
  const rows = members
    .filter((m) => m.userId && (!docs || docs.includes(String(m.userId._id))))
    .map((m) => ({
      userId: m.userId._id, name: m.userId.name, role: m.role,
      locations: dls
        .filter((d) => String(d.doctorId) === String(m.userId._id) && d.locationId?.status === 'active' && (!locs || locs.includes(String(d.locationId._id))))
        .map((d) => ({ id: d.locationId._id, name: d.locationId.shortName || d.locationId.name, services: d.services })),
    }))
    .filter((d) => d.locations.length);
  res.json(rows);
});

// ── Leave and clinic holidays ──
const leaveStatus = (l, now = new Date()) => (l.startDate > now ? 'planned' : l.endDate >= T.dayStart(now) ? 'active' : 'past');

/** The doctor's active locations (where they have a schedule and the clinic is open). */
async function myLocations(userId) {
  const dls = await M.DoctorLocation.find({ doctorId: userId, status: 'active' }).populate('locationId', 'name shortName status');
  return dls.map((d) => d.locationId).filter((l) => l && l.status === 'active');
}

/** Leave rows with how many booked patients they touch ("14 patients will be told"). */
async function leaveRows(userId, { upcomingOnly = false } = {}) {
  const q = { doctorId: userId, cancelledAt: null, ...(upcomingOnly ? { endDate: { $gte: T.dayStart() } } : {}) };
  const leaves = await M.DoctorLeave.find(q).sort({ startDate: 1 });
  const locs = await M.Location.find({ _id: { $in: leaves.map((l) => l.locationId).filter(Boolean) } }, 'name shortName');
  const names = new Map(locs.map((l) => [String(l._id), l.shortName || l.name]));
  const out = [];
  for (const l of leaves) {
    const affected = await M.Appointment.countDocuments({
      doctorId: userId, startAt: { $gte: l.startDate, $lt: T.addDays(l.endDate, 1) }, status: { $in: ['booked', 'confirmed'] },
      ...(l.locationId ? { locationId: l.locationId } : {}),
    });
    out.push({ ...l.toJSON(), locationName: l.locationId ? names.get(String(l.locationId)) || null : null, affectedPatients: affected, status: leaveStatus(l) });
  }
  return out;
}

r.get('/doctor/leaves', async (req, res) => res.json(await leaveRows(req.user._id)));

/**
 * Profile → Leave and holidays: the doctor's current and planned leave, and
 * the holidays (closures) of the clinics they practise at. Owners and practice
 * managers can add a clinic holiday (POST /api/locations/:id/closures).
 */
r.get('/doctor/time-off', async (req, res) => {
  const locs = await myLocations(req.user._id);
  const [leaves, closures] = await Promise.all([
    leaveRows(req.user._id, { upcomingOnly: true }),
    M.LocationClosure.find({ locationId: { $in: locs.map((l) => l._id) }, endDate: { $gte: T.dayStart() } }).sort({ startDate: 1 }),
  ]);
  const names = new Map(locs.map((l) => [String(l._id), l.shortName || l.name]));
  const holidays = [];
  for (const c of closures) {
    const affected = await M.Appointment.countDocuments({
      doctorId: req.user._id, locationId: c.locationId, startAt: { $gte: c.startDate, $lt: T.addDays(c.endDate, 1) }, status: { $in: ['booked', 'confirmed'] },
    });
    holidays.push({ ...c.toJSON(), locationName: names.get(String(c.locationId)) || null, affectedPatients: affected, status: leaveStatus(c) });
  }
  const manager = Boolean(req.member?.isOwner || req.member?.role === 'practice_manager');
  res.json({ leaves, holidays, canAddHoliday: manager, locations: locs.map((l) => ({ id: l._id, name: l.shortName || l.name })) });
});

r.post('/doctor/leaves', async (req, res) => {
  const reason = String(req.body.reason || '').trim();
  if (!reason) throw badRequest('Enter a reason', 'REASON_REQUIRED');
  if (!req.body.startDate) throw badRequest('Choose the dates', 'DATE_REQUIRED');
  const startDate = T.parseDay(req.body.startDate);
  const endDate = T.parseDay(req.body.endDate || req.body.startDate);
  if (endDate < startDate) throw badRequest('End date is before the start date');
  if (endDate < T.dayStart()) throw badRequest('Choose today or a later date', 'DATE_PAST');
  // One location (of the doctor's own) or all of them.
  let locationId = null;
  if (req.body.locationId) {
    const mine = await myLocations(req.user._id);
    const loc = mine.find((l) => String(l._id) === String(req.body.locationId));
    if (!loc) throw badRequest('Choose one of your locations', 'BAD_LOCATION');
    locationId = loc._id;
  }
  const overlap = await M.DoctorLeave.exists({
    doctorId: req.user._id, cancelledAt: null, startDate: { $lte: endDate }, endDate: { $gte: startDate },
    ...(locationId ? { $or: [{ locationId: null }, { locationId }] } : {}),
  });
  if (overlap) throw conflict('You already have leave on some of these days', 'LEAVE_OVERLAP');
  const leave = await M.DoctorLeave.create({ doctorId: req.user._id, locationId, reason, startDate, endDate });
  // Patients already booked in those days are told to pick another time.
  const q = { doctorId: req.user._id, startAt: { $gte: startDate, $lt: T.addDays(endDate, 1) }, status: { $in: ['booked', 'confirmed'] } };
  if (leave.locationId) q.locationId = leave.locationId;
  const affected = await M.Appointment.find(q).populate('patientId', 'userId name');
  const { notify } = require('../services/notify');
  const who = req.user.name || 'Your doctor';
  await notify(affected.map((a) => a.patientId?.userId).filter(Boolean), {
    type: 'doctor_leave', practiceId: req.practiceId, title: `${who} is on leave`,
    body: `${T.dayKey(startDate)}${+endDate !== +startDate ? ` to ${T.dayKey(endDate)}` : ''}. Please choose another time for your visit.`, screen: 'Patient-Doctors', whatsapp: true,
  });
  if (affected.length) {
    const desk = await require('../services/notify').deskOrDoctors(req.practiceId, { doctorId: req.user._id, ...(leave.locationId ? { locationId: leave.locationId } : {}) });
    await notify(desk, { type: 'doctor_leave', practiceId: req.practiceId, title: `${affected.length} visit${affected.length === 1 ? '' : 's'} to move`, body: `${who} is on leave ${T.dayKey(startDate)}${+endDate !== +startDate ? `–${T.dayKey(endDate)}` : ''}`, screen: 'Appointments' });
  }
  leave.patientsNotifiedAt = affected.length ? new Date() : undefined;
  await leave.save();
  res.status(201).json({ ...leave.toJSON(), patientsTold: affected.length });
});

// Cancel a leave: bookings open again for those days.
r.delete('/doctor/leaves/:id', async (req, res) => {
  if (!isId(req.params.id)) throw notFound('Leave');
  const leave = await M.DoctorLeave.findOneAndUpdate({ _id: req.params.id, doctorId: req.user._id, cancelledAt: null }, { cancelledAt: new Date() });
  if (!leave) throw notFound('Leave');
  // Patients who were told "on leave, choose another time" and still hold their visit:
  // it stands after all (no other leave covers it).
  let told = 0;
  if (leave.patientsNotifiedAt) {
    const q = { doctorId: req.user._id, startAt: { $gte: leave.startDate, $lt: T.addDays(leave.endDate, 1) }, status: { $in: ['booked', 'confirmed'] } };
    if (leave.locationId) q.locationId = leave.locationId;
    const still = [];
    for (const a of await M.Appointment.find(q).populate('patientId', 'userId')) {
      const other = await M.DoctorLeave.exists({ doctorId: req.user._id, cancelledAt: null, startDate: { $lte: a.date }, endDate: { $gte: a.date }, $or: [{ locationId: null }, { locationId: a.locationId }] });
      if (!other && a.patientId?.userId) still.push(a);
    }
    const { notify } = require('../services/notify');
    for (const a of still) {
      await notify([a.patientId.userId], {
        type: 'doctor_back', practiceId: a.practiceId, title: `${req.user.name || 'Your doctor'} is available after all`,
        body: `Your visit on ${T.dayKey(a.startAt)} at ${T.fmtTime(T.minuteOfDay(a.startAt))} stands.`, screen: 'Patient-DoctorDetail', params: { appointmentId: a._id }, whatsapp: true,
      });
    }
    told = still.length;
  }
  res.json({ ok: true, patientsTold: told });
});

// ── Prescription letterhead preview ──
// The real prescription PDF (services/rxpdf.js) for a sample patient, drawn with
// this location's letterhead (logo, printed name, registration fallback), the
// clinic's name / address / phone / hours and the doctor's own details and
// signature — exactly what an issued prescription from there prints. Watermarked
// PREVIEW · NOT ISSUED and never numbered or stored on a patient.
r.get('/doctor/letterhead/preview', async (req, res) => {
  const wanted = req.query.locationId && isId(String(req.query.locationId)) ? { locationId: req.query.locationId } : {};
  const dl = await M.DoctorLocation.findOne({ doctorId: req.user._id, practiceId: req.practiceId, status: 'active', ...wanted }).sort({ createdAt: 1 });
  const location = dl ? await M.Location.findById(dl.locationId) : wanted.locationId ? await M.Location.findOne({ _id: wanted.locationId, practiceId: req.practiceId }) : null;
  if (!location) throw notFound('Location');
  const [doctor, practice] = await Promise.all([profileOf(req.user._id), M.Practice.findById(req.practiceId, 'logo name')]);
  const image = async (file) => (file?.key ? storage.read(file.key).catch(() => null) : null);
  const [signature, logo] = await Promise.all([image(doctor.signature), image(location.letterhead?.logo || practice?.logo)]);
  const today = T.dayStart();
  const rx = {
    _id: null, rxNumber: null, kind: 'digital', doctorName: doctor.displayName || req.user.name, issuedAt: new Date(),
    validUntil: T.addDays(today, 30), followUpDate: T.addDays(today, 14), diagnosisSummary: 'Type 2 diabetes mellitus',
    items: [
      { name: 'Metformin', strength: '500 mg', form: 'tablet', frequency: 'daily', dose: { morning: 1, afternoon: 0, night: 1 }, foodRelation: 'after_food', duration: { value: 30, unit: 'days' }, quantity: 60, change: 'continued' },
      { name: 'Atorvastatin', strength: '10 mg', form: 'tablet', frequency: 'daily', dose: { morning: 0, afternoon: 0, night: 1 }, foodRelation: 'after_food', duration: { value: 30, unit: 'days' }, quantity: 30, change: 'new' },
    ],
    tests: ['HbA1c', 'Lipid profile'], advice: 'Walk for 30 minutes every day.\nCut down on sugar and fried food.',
  };
  const patient = { name: 'Sample patient', gender: 'female', ageYears: 52 };
  const { buffer, pages } = await require('../services/rxpdf').renderPrescription({
    rx, patient, doctor, location, vitals: null, complaint: 'Follow-up visit', signature, logo, practiceName: practice?.name, mode: 'in_clinic', preview: true,
  });
  const file = await storage.save(buffer, { folder: 'previews', name: `Letterhead preview · ${location.shortName || location.name}.pdf`.replace(/[\/:*?"<>|]/g, ''), mimeType: 'application/pdf', pages });
  res.json(storage.withUrl(file));
});

// Queue-Select "Don't ask again today"
r.put('/doctor/default-queue-location', async (req, res) => {
  const p = await profileOf(req.user._id);
  p.defaultQueueLocation = req.body.locationId ? { locationId: req.body.locationId, forDate: T.dayStart() } : undefined;
  await p.save();
  res.json({ ok: true });
});

module.exports = r;

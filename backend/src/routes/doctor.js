// Doctor-MyProfile, Profile-Professional, Profile-Location, Profile-Schedule, Queue-Select default.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict } = require('../lib/http');
const storage = require('../services/storage');
const { slotsFor, nextFreeSlot } = require('../services/scheduling');

const { uploader } = require('../lib/uploads');
const photoUpload = uploader({ kinds: ['image'], maxMb: 5, maxFiles: 1 });
const proofUpload = uploader({ kinds: ['image', 'pdf'], maxMb: 10, maxFiles: 1 });
const r = Router();
r.use(requireAuth, staff());

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
  qualifications: p.qualifications.map((q) => ({ ...q.toJSON(), proof: storage.withUrl(q.proof) })),
  yearsExperience: p.practisingSince ? new Date().getFullYear() - p.practisingSince : null,
  registrationDisplay: p.registration?.number ? `${p.registration.councilShort || ''} ${p.registration.number}`.trim() : null,
  completionPct: completion(p),
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
  const body = pick(req.body, PROFILE_FIELDS);
  for (const k of ['specialisations', 'conditionsTreated', 'memberships']) if (body[k]) body[k] = dedupe(body[k]);
  if (body.registration) {
    body.registration = { ...(p.registration?.toObject?.() || {}), ...body.registration };
    if (req.body.registration.number && req.body.registration.number !== p.registration?.number) body.registration.status = 'in_review';
  }
  if (body.hprId && body.hprId !== p.hprId) p.hprLinkedAt = new Date();
  // Payouts: keep only the last 4 digits of a full account number.
  if (body.payout) {
    const acc = String(req.body.payout.accountNumber || '').replace(/\s/g, '');
    if (acc && !/^\d{9,18}$/.test(acc)) throw badRequest('Enter the bank account number (9–18 digits)', 'BAD_ACCOUNT');
    body.payout = {
      ...(p.payout?.toObject?.() || {}),
      ...pick(req.body.payout, ['upiId', 'accountHolder', 'bankName', 'ifsc', 'preferred']),
      ...(acc ? { bankAccountLast4: acc.slice(-4) } : {}),
      updatedAt: new Date(),
    };
  }
  for (const k of ['chatSettings', 'notificationPrefs']) {
    if (body[k]) body[k] = { ...(p[k]?.toObject?.() || {}), ...body[k] };
  }
  Object.assign(p, body);
  await p.save();
  if (body.displayName) await M.User.updateOne({ _id: req.user._id }, { name: body.displayName });
  res.json(profileView(p));
});

r.post('/doctor/profile/photo', photoUpload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Choose a photo');
  const p = await profileOf(req.user._id);
  p.photo = await storage.save(req.file.buffer, { folder: 'photos', name: req.file.originalname, mimeType: req.file.mimetype });
  await p.save();
  res.json(profileView(p));
});

// "Printed on every prescription"
r.post('/doctor/profile/signature', photoUpload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Choose a signature image');
  const p = await profileOf(req.user._id);
  p.signature = await storage.save(req.file.buffer, { folder: 'signatures', name: req.file.originalname, mimeType: req.file.mimetype });
  await p.save();
  res.json(profileView(p));
});

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
  await p.save();
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
    const slots = s.week?.[0]?.sessions?.[0] ? Math.floor((s.week[0].sessions[0].endMin - s.week[0].sessions[0].startMin) / ((s.slotLengthMin || 15) + (s.breakBetweenMin || 0))) : null;
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
  const members = await M.Member.find({ practiceId: req.practiceId, role: 'doctor', status: 'active' }).populate('userId', 'name');
  const dls = await M.DoctorLocation.find({ practiceId: req.practiceId, status: 'active' }).populate('locationId', 'name shortName');
  res.json(members.map((m) => ({
    userId: m.userId._id, name: m.userId.name,
    locations: dls.filter((d) => String(d.doctorId) === String(m.userId._id)).map((d) => ({ id: d.locationId._id, name: d.locationId.shortName || d.locationId.name, services: d.services })),
  })));
});

// ── Leave ──
r.get('/doctor/leaves', async (req, res) => {
  const leaves = await M.DoctorLeave.find({ doctorId: req.user._id, cancelledAt: null }).sort({ startDate: 1 });
  const out = [];
  for (const l of leaves) {
    const affected = await M.Appointment.countDocuments({
      doctorId: req.user._id, startAt: { $gte: l.startDate, $lt: T.addDays(l.endDate, 1) }, status: { $in: ['booked', 'confirmed'] },
      ...(l.locationId ? { locationId: l.locationId } : {}),
    });
    const now = new Date();
    out.push({ ...l.toJSON(), affectedPatients: affected, status: l.startDate > now ? 'planned' : l.endDate >= T.dayStart(now) ? 'active' : 'past' });
  }
  res.json(out);
});

r.post('/doctor/leaves', async (req, res) => {
  if (!req.body.reason) throw badRequest('Enter a reason');
  const startDate = T.parseDay(req.body.startDate);
  const endDate = T.parseDay(req.body.endDate || req.body.startDate);
  if (endDate < startDate) throw badRequest('End date is before the start date');
  const leave = await M.DoctorLeave.create({ doctorId: req.user._id, locationId: req.body.locationId || null, reason: req.body.reason, startDate, endDate });
  // Patients already booked in those days are told to pick another time.
  const q = { doctorId: req.user._id, startAt: { $gte: startDate, $lt: T.addDays(endDate, 1) }, status: { $in: ['booked', 'confirmed'] } };
  if (leave.locationId) q.locationId = leave.locationId;
  const affected = await M.Appointment.find(q).populate('patientId', 'userId name');
  const { notify, practiceStaff } = require('../services/notify');
  const who = req.user.name || 'Your doctor';
  await notify(affected.map((a) => a.patientId?.userId).filter(Boolean), {
    type: 'doctor_leave', practiceId: req.practiceId, title: `${who} is on leave`,
    body: `${T.dayKey(startDate)}${+endDate !== +startDate ? ` to ${T.dayKey(endDate)}` : ''}. Please choose another time for your visit.`, screen: 'Patient-Doctors', whatsapp: true,
  });
  if (affected.length) {
    const desk = await practiceStaff(req.practiceId, { roles: ['front_desk', 'practice_manager'] });
    await notify(desk, { type: 'doctor_leave', practiceId: req.practiceId, title: `${affected.length} visit${affected.length === 1 ? '' : 's'} to move`, body: `${who} is on leave ${T.dayKey(startDate)}${+endDate !== +startDate ? `–${T.dayKey(endDate)}` : ''}`, screen: 'Appointments' });
  }
  res.status(201).json({ ...leave.toJSON(), patientsTold: affected.length });
});

r.delete('/doctor/leaves/:id', async (req, res) => {
  await M.DoctorLeave.updateOne({ _id: req.params.id, doctorId: req.user._id }, { cancelledAt: new Date() });
  res.json({ ok: true });
});

// Queue-Select "Don't ask again today"
r.put('/doctor/default-queue-location', async (req, res) => {
  const p = await profileOf(req.user._id);
  p.defaultQueueLocation = req.body.locationId ? { locationId: req.body.locationId, forDate: T.dayStart() } : undefined;
  await p.save();
  res.json({ ok: true });
});

module.exports = r;

// Account settings, devices, notifications, catalogs and signed file downloads.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const { requireAuth } = require('../middleware/auth');
const { pick, badRequest, notFound, escapeRegex, paging, forbidden, isId } = require('../lib/http');
const storage = require('../services/storage');
const env = require('../config/env');
const { sendEmail } = require('../services/email');
const { notify } = require('../services/notify');
const { accountSummary } = require('./auth');
const { uploader } = require('../lib/uploads');

const photoUpload = uploader({ kinds: ['image'], maxMb: 5, maxFiles: 1 });

const me = Router();
me.use(requireAuth);

me.get('/', async (req, res) => res.json(await accountSummary(req.user)));

me.patch('/', async (req, res) => {
  const body = pick(req.body, ['name', 'email', 'language', 'appLock']);
  if (body.language && !E.LANGUAGES.includes(body.language)) throw badRequest('Unknown language');
  if (body.email !== undefined) {
    body.email = String(body.email || '').trim().toLowerCase() || undefined;
    if (body.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)) throw badRequest('Enter a valid email address');
  }
  Object.assign(req.user, body);
  await req.user.save();
  res.json(await accountSummary(req.user));
});

// Profile photo for any account (patients, staff; doctors also see it on their public profile).
me.post('/photo', photoUpload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Choose a photo');
  const file = await storage.save(req.file.buffer, { folder: 'photos', name: req.file.originalname, mimeType: req.file.mimetype });
  req.user.photo = file;
  await req.user.save();
  await M.DoctorProfile.updateOne({ userId: req.user._id }, { photo: file });
  res.json(await accountSummary(req.user));
});

me.delete('/photo', async (req, res) => {
  req.user.photo = undefined;
  await req.user.save();
  // A doctor's public profile shows the same photo: removed there too (patients stop seeing it).
  await M.DoctorProfile.updateOne({ userId: req.user._id }, { $unset: { photo: 1 } });
  res.json(await accountSummary(req.user));
});

// Switch the practice used by staff endpoints (also settable per request with X-Practice-Id).
// Profile → Clinic: the choice is kept for the next sign-in and other devices.
me.post('/active-practice', async (req, res) => {
  if (!isId(String(req.body.practiceId || ''))) throw badRequest('Choose a clinic', 'BAD_PRACTICE');
  const member = await M.Member.findOne({ userId: req.user._id, practiceId: String(req.body.practiceId), status: 'active' });
  if (!member) throw forbidden('You are not a member of this practice', 'NOT_A_MEMBER');
  req.user.activePracticeId = member.practiceId;
  if (req.body.locationId && isId(String(req.body.locationId))) req.user.activeLocationId = String(req.body.locationId);
  await req.user.save();
  res.json({ ok: true, practiceId: member.practiceId, ...(await accountSummary(req.user)) });
});

me.post('/devices', async (req, res) => {
  // Plain strings only (a JSON object here would act as a query operator).
  const token = typeof req.body.token === 'string' ? req.body.token.trim() : '';
  const platform = String(req.body.platform || '');
  if (!token || token.length > 4096 || !E.PLATFORMS.includes(platform)) throw badRequest('token and platform are required');
  await M.DeviceToken.findOneAndUpdate({ token }, { userId: req.user._id, sessionId: req.sessionId || null, platform, localAlarms: req.body.localAlarms === true, lastSeenAt: new Date() }, { upsert: true });
  res.json({ ok: true });
});

// The phone tells what reminders it scheduled itself (medicine alarms, visits,
// daily log) — the server then pushes only the ones it doesn't cover.
me.post('/devices/reminders', async (req, res) => {
  const token = typeof req.body.token === 'string' ? req.body.token.trim() : '';
  if (!token) throw badRequest('token is required');
  const until = new Date(req.body.until);
  const at = typeof req.body.dailyLogAt === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(req.body.dailyLogAt) ? req.body.dailyLogAt : null;
  const r = await M.DeviceToken.updateOne(
    { token, userId: req.user._id },
    { remindersSyncedAt: new Date(), remindersUntil: Number.isNaN(+until) ? null : until, dailyLogAt: at, lastSeenAt: new Date() },
  );
  res.json({ ok: r.matchedCount > 0 });
});

// ── Privacy and data: signed-in devices ──
me.get('/sessions', async (req, res) => {
  const rows = await M.AuthSession.find({ userId: req.user._id, revokedAt: null, expiresAt: { $gt: new Date() } }).sort({ createdAt: -1 });
  res.json(rows.map((s) => ({
    id: s._id, platform: s.platform, deviceName: s.deviceName, ip: s.ip, signedInAt: s.createdAt, lastUsedAt: s.updatedAt,
    current: String(s._id) === String(req.sessionId),
  })));
});

me.post('/sessions/:id/revoke', async (req, res) => {
  const r = await M.AuthSession.updateOne({ _id: req.params.id, userId: req.user._id, revokedAt: null }, { revokedAt: new Date() });
  if (!r.modifiedCount) throw notFound('Device');
  await require('../lib/devicetokens').forgetSession(req.params.id); // that phone stops getting pushes
  res.json({ ok: true });
});

me.post('/sessions/revoke-others', async (req, res) => {
  const r = await M.AuthSession.updateMany(
    { userId: req.user._id, revokedAt: null, ...(req.sessionId ? { _id: { $ne: req.sessionId } } : {}) },
    { revokedAt: new Date() },
  );
  await M.DeviceToken.deleteMany({ userId: req.user._id, ...(typeof req.body.keepToken === 'string' && req.body.keepToken ? { token: { $ne: req.body.keepToken } } : {}) });
  res.json({ ok: true, signedOut: r.modifiedCount });
});

// Download my data: the account and (for doctors) the professional profile, as JSON.
me.post('/export', async (req, res) => {
  const [members, profile, patient] = await Promise.all([
    M.Member.find({ userId: req.user._id }).populate('practiceId', 'name'),
    M.DoctorProfile.findOne({ userId: req.user._id }).lean(),
    M.Patient.findOne({ userId: req.user._id }).lean(),
  ]);
  const data = {
    exportedAt: new Date(),
    account: { name: req.user.name, phone: req.user.phone, email: req.user.email, language: req.user.language, createdAt: req.user.createdAt },
    memberships: members.map((m) => ({ practice: m.practiceId?.name, role: m.role, status: m.status, joinedAt: m.joinedAt })),
    doctorProfile: profile ? { ...profile, payout: profile.payout ? { ...profile.payout, razorpayAccountId: undefined } : undefined, _id: undefined, __v: undefined } : null,
    patientProfile: patient ? { ...patient, _id: undefined, __v: undefined } : null,
  };
  const file = await storage.save(Buffer.from(JSON.stringify(data, null, 2)), { folder: 'exports', name: 'medpin-my-data.json', mimeType: 'application/json' });
  await M.AuditLog.create({ userId: req.user._id, action: 'account.export', ip: req.ip });
  res.status(201).json({ url: storage.signedUrl(file.key), name: file.name });
});

// Ask to delete the account (needs a person to check practice records first).
me.post('/delete-request', async (req, res) => {
  await M.AuditLog.create({ userId: req.user._id, action: 'account.delete_request', meta: { reason: req.body.reason }, ip: req.ip });
  await M.SupportRequest.create({ userId: req.user._id, practiceId: req.user.activePracticeId, topic: 'account', message: `Delete my account. ${req.body.reason || ''}`.trim() });
  if (env.support.email) await sendEmail({ to: env.support.email, subject: 'MedPin: account deletion request', text: `${req.user.name || ''} (+91 ${req.user.phone}) asked to delete their account.\nReason: ${req.body.reason || '—'}` });
  res.json({ ok: true });
});

// ── Help and support ──
// Words speech recognition should expect: the medicine catalog and common dose words.
me.get('/voice/phrases', async (_req, res) => {
  const meds = await M.Medicine.find({ active: { $ne: false } }, 'genericName brandNames').lean();
  const names = [...new Set(meds.flatMap((m) => [m.genericName, ...(m.brandNames || [])]).filter(Boolean))];
  res.json({ phrases: [...names, 'milligram', 'microgram', 'after food', 'before food', 'empty stomach', 'once a day', 'twice daily', 'at bedtime', 'when needed'].slice(0, 200) });
});

// Speak-to-type: misheard medicine names and medical words fixed before use (services/transcript.js).
me.post('/voice/clean', async (req, res) => {
  const { cleanTranscript } = require('../services/transcript');
  const purpose = ['medicine', 'question', 'symptoms', 'note'].includes(req.body.purpose) ? req.body.purpose : 'note';
  const alternates = Array.isArray(req.body.alternates) ? req.body.alternates.slice(0, 5).map(String) : [];
  res.json(await cleanTranscript({ text: req.body.text, alternates, purpose, language: String(req.body.language || 'en').slice(0, 5) }));
});

me.get('/support', (_req, res) => res.json({ email: env.support.email || null, phone: env.support.phone || null, whatsapp: env.support.whatsapp || null }));

me.post('/support', async (req, res) => {
  const message = String(req.body.message || '').trim();
  if (message.length < 10) throw badRequest('Tell us a little more (at least 10 characters)', 'MESSAGE_TOO_SHORT');
  const reqDoc = await M.SupportRequest.create({
    userId: req.user._id, practiceId: req.user.activePracticeId, topic: req.body.topic || 'problem', message,
    platform: req.body.platform, appVersion: req.body.appVersion,
  });
  if (env.support.email) {
    await sendEmail({
      to: env.support.email,
      subject: `MedPin support: ${reqDoc.topic}`,
      text: `From ${req.user.name || ''} (+91 ${req.user.phone})\n${req.body.platform || ''} ${req.body.appVersion || ''}\n\n${message}`,
    });
  }
  await notify([req.user._id], { type: 'support', title: 'We got your message', body: 'Our team will reply by email or phone.' });
  res.status(201).json(reqDoc);
});

// A doctor with no invite starts their own practice (they become its owner).
// "Start my clinic" (Auth-Clinic-Setup): the doctor, their clinic, its first
// location and a schedule there, so patients can book straight away.
const WEEK = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
me.post('/practices', async (req, res) => {
  const b = req.body;
  const name = String(b.name || '').trim();
  const doctorName = String(b.doctorName || req.user.name || '').trim();
  if (!doctorName) throw badRequest('Enter your full name', 'NAME_REQUIRED');
  if (!name) throw badRequest('Enter the clinic name', 'CLINIC_NAME_REQUIRED');
  const opensAt = Number.isInteger(b.opensAt) ? b.opensAt : 540;
  const closesAt = Number.isInteger(b.closesAt) ? b.closesAt : 1200;
  if (opensAt < 0 || closesAt > 1440 || closesAt - opensAt < 30) throw badRequest('Closing time must be at least 30 minutes after opening', 'BAD_HOURS');
  const days = Array.isArray(b.openDays) && b.openDays.length ? b.openDays.filter((d) => WEEK.includes(d)) : WEEK.filter((d) => d !== 'sun');
  if (!days.length) throw badRequest('Choose at least one open day', 'BAD_HOURS');
  const fee = b.fee == null || b.fee === '' ? 500 : Number(b.fee);
  if (!Number.isFinite(fee) || fee < 0 || fee > 100000) throw badRequest('Enter a valid consultation fee', 'BAD_FEE');
  if (b.pincode && !/^\d{6}$/.test(String(b.pincode))) throw badRequest('Pincode must be 6 digits', 'BAD_PINCODE');
  const specialty = b.specialtyKey ? await M.Specialty.findOne({ key: String(b.specialtyKey) }) : null;

  req.user.name = doctorName;
  if (b.termsAccepted) req.user.termsAcceptedAt = new Date();
  const practice = await M.Practice.create({ name, ownerUserId: req.user._id, tagline: b.tagline });
  const location = await M.Location.create({
    practiceId: practice._id, name: b.locationName || name, shortName: b.area, area: b.area, address: b.address, city: b.city, pincode: b.pincode,
    phone: b.clinicPhone ? String(b.clinicPhone).replace(/\D/g, '').slice(-10) : undefined,
    weeklyHours: WEEK.map((weekday) => ({ weekday, isOpen: days.includes(weekday), opensAt, closesAt })),
    // Map pin: "I'm at the clinic now" (lat / lng) or a pasted Google Maps link.
    googleMapsUrl: b.googleMapsUrl ? String(b.googleMapsUrl).slice(0, 500) : undefined,
    geo: require('../lib/geo').pointFromBody(b),
  });
  await M.Member.create({
    practiceId: practice._id, userId: req.user._id, role: 'doctor', isOwner: true, allLocations: true, phone: req.user.phone,
    qualifications: b.qualifications, registrationNo: b.registrationNo,
  });
  const profile = (await M.DoctorProfile.findOne({ userId: req.user._id })) || new M.DoctorProfile({ userId: req.user._id });
  profile.displayName = doctorName;
  if (specialty) {
    profile.specialtyKeys = [specialty.key];
    if (!profile.headline) profile.headline = specialty.label;
  }
  if (b.qualifications) profile.degreesSummary = String(b.qualifications).slice(0, 120);
  if (b.registrationNo) profile.registration = { ...(profile.registration?.toObject?.() || {}), number: String(b.registrationNo).slice(0, 40) };
  await profile.save();
  // The doctor practises at their first location with the clinic hours.
  await M.DoctorLocation.create({
    doctorId: req.user._id, locationId: location._id, practiceId: practice._id,
    services: [
      { name: 'New consultation', details: '15 min · in clinic', durationMin: 15, visitType: 'new', fee },
      { name: 'Follow-up', details: 'Repeat visit for the same problem', visitType: 'follow_up', fee },
    ],
    schedule: { week: WEEK.map((weekday) => ({ weekday, sessions: days.includes(weekday) ? [{ startMin: opensAt, endMin: closesAt }] : [] })), slotLengthMin: 15, walkInPlaces: 4 },
  });
  const now = new Date();
  await M.Subscription.create({
    practiceId: practice._id, planKey: 'starter', status: 'trialing', price: 999,
    currentPeriodStart: now, currentPeriodEnd: new Date(now.getTime() + 30 * 864e5),
  });
  req.user.activePracticeId = practice._id;
  req.user.activeLocationId = location._id;
  await req.user.save();
  res.status(201).json({ practice, location, ...(await accountSummary(req.user)) });
});

// ── Notifications (bell) ──
const notifications = Router();
notifications.use(requireAuth);
// "Delivered" ticks: the app is open on this person's phone (it polls its badges here), so
// chat messages to them reach "delivered". At most once a minute per person.
const deliveredAt = new Map();
function noteDelivered(userId) {
  const k = String(userId);
  const now = Date.now();
  if (now - (deliveredAt.get(k) || 0) < 60e3) return;
  deliveredAt.set(k, now);
  if (deliveredAt.size > 50000) deliveredAt.clear();
  require('../services/care').markDelivered(userId).catch((err) => console.warn('[delivered]', err.message));
}

notifications.get('/', async (req, res) => {
  noteDelivered(req.user._id);
  const { limit, skip } = paging(req.query);
  // ?practiceId= : a staff member's bell shows only that clinic's notifications.
  const scope = { userId: req.user._id, ...(isId(String(req.query.practiceId || '')) ? { practiceId: String(req.query.practiceId) } : {}) };
  const q = { ...scope, ...(req.query.unread === 'true' ? { readAt: null } : {}) };
  // urgent: unread emergencies (emergency alerts, urgent chats) turn the bell's dot red.
  const [items, unread, urgent] = await Promise.all([
    M.Notification.find(q).sort({ createdAt: -1 }).skip(skip).limit(limit),
    M.Notification.countDocuments({ ...scope, readAt: null }),
    M.Notification.countDocuments({ ...scope, readAt: null, type: /emergency|urgent/ }),
  ]);
  // Older notices were stored in English: shown in the app language the person uses now.
  const lang = req.user.language;
  if (lang === 'bn' || lang === 'hi') {
    const { translateNotice } = require('../lib/notify_i18n');
    return res.json({ items: items.map((n) => ({ ...n.toJSON(), ...translateNotice(n, lang) })), unread, urgent });
  }
  res.json({ items, unread, urgent });
});
notifications.post('/read-all', async (req, res) => {
  const scope = { userId: req.user._id, ...(isId(String(req.body.practiceId || '')) ? { practiceId: String(req.body.practiceId) } : {}) };
  await M.Notification.updateMany({ ...scope, readAt: null }, { readAt: new Date() });
  res.json({ ok: true });
});
notifications.post('/:id/read', async (req, res) => {
  const n = await M.Notification.findOneAndUpdate({ _id: req.params.id, userId: req.user._id }, { readAt: new Date() }, { new: true });
  if (!n) throw notFound('Notification');
  res.json(n);
});

// ── Catalogs (any signed-in user) ──
const catalog = Router();
catalog.use(requireAuth);
catalog.get('/specialties', async (_req, res) => res.json(await M.Specialty.find().sort({ order: 1 })));
catalog.get('/plans', async (_req, res) => res.json(await M.Plan.find({ active: true }).sort({ priceMonthly: 1 })));
catalog.get('/icd', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const filter = q ? { $or: [{ name: new RegExp(escapeRegex(q), 'i') }, { code: new RegExp(`^${escapeRegex(q)}`, 'i') }] } : {};
  res.json(await M.IcdCode.find(filter).limit(20));
});
catalog.get('/medicines', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const filter = { active: true, ...(q ? { $or: [{ genericName: new RegExp(escapeRegex(q), 'i') }, { brandNames: new RegExp(escapeRegex(q), 'i') }] } : {}) };
  res.json(await M.Medicine.find(filter).limit(20));
});
catalog.get('/lab-tests', async (req, res) => {
  const q = String(req.query.q || '').trim();
  res.json(await M.LabTest.find(q ? { name: new RegExp(escapeRegex(q), 'i') } : {}).limit(50));
});
catalog.get('/enums', (_req, res) => res.json(E));

// ── Signed file downloads: /files/<key>?exp&sig ──
const files = Router();
files.get('/*key', async (req, res) => {
  const key = [].concat(req.params.key).join('/');
  if (!storage.verifySignature(key, req.query.exp, req.query.sig)) throw forbidden('This link has expired', 'LINK_EXPIRED');
  let data;
  try {
    data = await storage.read(key);
  } catch {
    throw notFound('File');
  }
  const ext = key.split('.').pop().toLowerCase();
  const types = { pdf: 'application/pdf', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', csv: 'text/csv', json: 'application/json', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', mp3: 'audio/mpeg', m4a: 'audio/mp4', aac: 'audio/aac' };
  res.setHeader('Content-Type', types[ext] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'private, max-age=300');
  res.send(data);
});

module.exports = { me, notifications, catalog, files };

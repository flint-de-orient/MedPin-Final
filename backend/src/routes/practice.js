// Practice, Clinics, Clinic-Editor, Departments, People, People-Add, People-Member.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff, ownerOnly, ownPractice } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, normalizePhone } = require('../lib/http');
const storage = require('../services/storage');
const { issueOtp, checkOtp } = require('./auth');

const { uploader } = require('../lib/uploads');
const upload = uploader({ kinds: ['image'], maxMb: 5, maxFiles: 1 });
const r = Router();
r.use(requireAuth, staff());

// ── Practice ──
r.get('/practice', async (req, res) => {
  const practice = await M.Practice.findById(req.practiceId);
  const [locations, people, departments, doctorProfile, hoursSet] = await Promise.all([
    M.Location.countDocuments({ practiceId: req.practiceId, status: 'active' }),
    M.Member.countDocuments({ practiceId: req.practiceId, status: 'active' }),
    M.Department.countDocuments({ practiceId: req.practiceId }),
    M.DoctorProfile.findOne({ userId: practice.ownerUserId }, 'signature'),
    M.Location.exists({ practiceId: req.practiceId, 'weeklyHours.0': { $exists: true } }),
  ]);
  const hasMap = await M.Location.exists({ practiceId: req.practiceId, status: 'active', googleMapsUrl: { $nin: [null, ''] } });
  const hasClosures = await M.LocationClosure.exists({ locationId: { $in: await M.Location.find({ practiceId: req.practiceId }).distinct('_id') }, endDate: { $gte: new Date() } });
  const hasLetterhead = await M.Location.exists({ practiceId: req.practiceId, 'letterhead.doctorNamePrinted': { $nin: [null, ''] } });
  const readiness = [
    { key: 'signature', label: 'Add your digital signature', blocking: true, done: Boolean(doctorProfile?.signature?.key) },
    { key: 'map', label: 'Add a map link', blocking: false, done: Boolean(hasMap) },
    { key: 'closures', label: 'Set holiday closures', blocking: false, done: Boolean(hasClosures) },
    { key: 'hours', label: 'Clinic hours', blocking: false, done: Boolean(hoursSet) },
    { key: 'letterhead', label: 'Letterhead', blocking: false, done: Boolean(hasLetterhead) },
    { key: 'team', label: 'Team', blocking: false, done: people > 1 },
  ];
  res.json({
    practice: { ...practice.toJSON(), logo: storage.withUrl(practice.logo) },
    tiles: { locations, people, departments },
    readiness,
    role: req.member.role,
    isOwner: req.member.isOwner,
    permissions: req.perms,
  });
});

r.patch('/practice', ownerOnly, async (req, res) => {
  const body = pick(req.body, ['name', 'tagline', 'registrationNo', 'patientCallNumber', 'foodLogReviewCadence']);
  const practice = await M.Practice.findByIdAndUpdate(req.practiceId, body, { new: true, runValidators: true });
  res.json(practice);
});

r.post('/practice/logo', ownerOnly, upload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Choose a logo file');
  const logo = await saveLogo(req.file);
  const practice = await M.Practice.findByIdAndUpdate(req.practiceId, { logo: logo.file, logoIsDark: false }, { new: true });
  res.json({ logo: storage.withUrl(practice.logo), backgroundRemoved: logo.removed });
});

// ── Locations ──
r.get('/locations', async (req, res) => {
  const locations = await M.Location.find({ practiceId: req.practiceId }).sort({ status: 1, name: 1 });
  const ids = locations.map((l) => l._id);
  const [doctors, upcoming, today] = await Promise.all([
    M.DoctorLocation.aggregate([{ $match: { locationId: { $in: ids }, status: 'active' } }, { $group: { _id: '$locationId', n: { $sum: 1 } } }]),
    M.Appointment.aggregate([{ $match: { locationId: { $in: ids }, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] } } }, { $group: { _id: '$locationId', n: { $sum: 1 } } }]),
    M.Appointment.aggregate([{ $match: { locationId: { $in: ids }, date: T.dayStart(), status: { $nin: ['cancelled', 'rescheduled'] } } }, { $group: { _id: { l: '$locationId', s: '$status' }, n: { $sum: 1 } } }]),
  ]);
  const m = (arr) => new Map(arr.map((x) => [String(x._id), x.n]));
  const dm = m(doctors);
  const um = m(upcoming);
  const now = T.minuteOfDay(new Date());
  const wd = T.weekday(new Date());
  res.json({
    summary: {
      active: locations.filter((l) => l.status === 'active').length,
      inactive: locations.filter((l) => l.status === 'inactive').length,
      shared: locations.filter((l) => l.status === 'view_only').length,
    },
    items: locations.map((l) => {
      const h = l.weeklyHours.find((x) => x.weekday === wd);
      const openNow = l.status === 'active' && h?.isOpen && now >= h.opensAt && now < h.closesAt;
      const todayRows = today.filter((t) => String(t._id.l) === String(l._id));
      return {
        ...l.toJSON(),
        doctors: dm.get(String(l._id)) || 0,
        upcomingBookings: um.get(String(l._id)) || 0,
        today: {
          openNow: Boolean(openNow),
          opensAt: h?.isOpen ? h.opensAt : null,
          closesAt: h?.isOpen ? h.closesAt : null,
          booked: todayRows.reduce((s, t) => s + t.n, 0),
          waiting: todayRows.filter((t) => t._id.s === 'waiting').reduce((s, t) => s + t.n, 0),
        },
      };
    }),
  });
});

const LOCATION_FIELDS = ['name', 'shortName', 'type', 'address', 'area', 'city', 'pincode', 'landmark', 'phone', 'patientPhone', 'googleMapsUrl', 'hfrId', 'facilities', 'paymentMethods', 'collectFeeAtBooking', 'slotMinutes', 'weeklyHours', 'letterhead'];

/**
 * Map pin and Google Maps link from a request: lat / lng first, then the link
 * (short maps.app.goo.gl links are followed to find the coordinates). With a
 * pin and no link, a link to the pin is made so patients always get one.
 * Throws for a link that isn't Google Maps.
 */
async function mapFields(body) {
  const out = {};
  let url = body.googleMapsUrl == null ? undefined : String(body.googleMapsUrl).trim();
  if (url) {
    if (!/^https?:\/\/((www\.)?google\.[a-z.]+\/maps|maps\.google\.[a-z.]+|maps\.app\.goo\.gl|goo\.gl\/maps)/i.test(url)) {
      throw badRequest('Paste a Google Maps link (Share → Copy link in Google Maps)', 'BAD_MAPS_LINK');
    }
    out.googleMapsUrl = url.slice(0, 500);
  } else if (url === '') out.googleMapsUrl = '';
  let geo = require('../lib/geo').pointFrom(body.lat, body.lng);
  if (!geo && url) {
    geo = require('../lib/geo').pointFromMapsUrl(url);
    if (!geo) {
      const full = await require('../services/places').expandMapsLink(url).catch(() => null);
      if (full) geo = require('../lib/geo').pointFromMapsUrl(full);
    }
  }
  if (geo) out.geo = geo;
  return out;
}
const pinLink = (geo) => `https://www.google.com/maps/search/?api=1&query=${geo.coordinates[1]},${geo.coordinates[0]}`;
const validHours = (hours) => {
  for (const h of hours || []) {
    if (h.isOpen !== false && h.closesAt <= h.opensAt) throw badRequest('Closing time must be after opening time', 'BAD_HOURS');
  }
};

r.post('/locations', ownerOnly, async (req, res) => {
  const body = pick(req.body, LOCATION_FIELDS);
  validHours(body.weeklyHours);
  const map = await mapFields(req.body);
  const loc = await M.Location.create({
    ...body, ...map, practiceId: req.practiceId, ...(map.geo && !map.googleMapsUrl ? { googleMapsUrl: pinLink(map.geo) } : {}),
    weeklyHours: body.weeklyHours || E.WEEKDAYS.map((weekday) => ({ weekday, isOpen: weekday !== 'sun', opensAt: 540, closesAt: 1200 })),
  });
  res.status(201).json(loc);
});

const ownLocation = async (req) => {
  const loc = await M.Location.findById(req.params.id);
  ownPractice(req, loc, 'Location');
  if (loc.status === 'view_only' || loc.managedByPracticeId) throw conflict('View only · managed by another organisation', 'VIEW_ONLY');
  return loc;
};

r.get('/locations/:id', async (req, res) => {
  const loc = ownPractice(req, await M.Location.findById(req.params.id), 'Location');
  // A logo uploaded before backgrounds were removed is cleaned once, here.
  if (loc.letterhead?.logo?.key && loc.letterhead.logoBackgroundRemoved == null) {
    try {
      const original = await storage.read(loc.letterhead.logo.key);
      const logo = await saveLogo({ buffer: original, originalname: loc.letterhead.logo.name || 'logo', mimetype: loc.letterhead.logo.mimeType || 'image/png' });
      loc.letterhead = { ...loc.letterhead.toObject(), ...(logo.removed ? { logo: logo.file, logoIsDark: false } : {}), logoBackgroundRemoved: logo.removed };
      await loc.save();
    } catch (err) {
      console.warn('[logo clean]', err.message);
    }
  }
  const [closures, doctors] = await Promise.all([
    M.LocationClosure.find({ locationId: loc._id, endDate: { $gte: T.dayStart() } }).sort({ startDate: 1 }),
    M.DoctorLocation.find({ locationId: loc._id, status: 'active' }).populate('doctorId', 'name'),
  ]);
  const upcomingBookings = await M.Appointment.countDocuments({ locationId: loc._id, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] } });
  const json = loc.toJSON();
  if (json.letterhead?.logo) json.letterhead.logo = storage.withUrl(loc.letterhead.logo);
  res.json({ ...json, upcomingBookings, closures, doctors: doctors.map((d) => ({ doctorId: d.doctorId?._id, name: d.doctorId?.name, week: d.schedule.week })) });
});

r.patch('/locations/:id', ownerOnly, async (req, res) => {
  const loc = await ownLocation(req);
  const body = pick(req.body, LOCATION_FIELDS);
  validHours(body.weeklyHours);
  const map = await mapFields(req.body);
  Object.assign(loc, body, map);
  // Keep the patients' link in step with the pin when it was made from the pin (or is missing).
  const autoLink = !loc.googleMapsUrl || /maps\/search\/\?api=1&query=/.test(loc.googleMapsUrl);
  if (map.geo && autoLink && !map.googleMapsUrl) loc.googleMapsUrl = pinLink(map.geo);
  if (req.body.hfrId && !/^IN\d{10}$/.test(String(req.body.hfrId).trim())) throw badRequest('Enter the HFR ID like IN1910000123', 'BAD_HFR_ID');
  if (req.body.hfrId) loc.hfrLinkedAt = new Date();
  await loc.save();
  res.json(loc);
});

/** Saves a logo with its plain background made transparent (the original is kept beside it). */
async function saveLogo(file) {
  const { removeLogoBackground } = require('../services/images');
  const clean = await removeLogoBackground(file.buffer).catch(() => ({ buffer: file.buffer, mimeType: file.mimetype, removed: false }));
  if (clean.removed) await storage.save(file.buffer, { folder: 'logos/original', name: file.originalname, mimeType: file.mimetype });
  const name = clean.removed ? String(file.originalname || 'logo').replace(/\.[a-z0-9]+$/i, '') + '.png' : file.originalname;
  return { file: await storage.save(clean.buffer, { folder: 'logos', name, mimeType: clean.mimeType }), removed: clean.removed };
}

// Letterhead logo printed on this location's prescriptions.
r.post('/locations/:id/logo', ownerOnly, upload.single('file'), async (req, res) => {
  const loc = await ownLocation(req);
  if (!req.file) throw badRequest('Choose a logo file');
  if (!/^image\/(png|jpeg|webp)$/.test(req.file.mimetype)) throw badRequest('Use a PNG, JPG or WebP image');
  const logo = await saveLogo(req.file);
  loc.letterhead = { ...(loc.letterhead?.toObject?.() || {}), logo: logo.file, logoIsDark: false, logoBackgroundRemoved: logo.removed };
  await loc.save();
  res.json({ logo: storage.withUrl(loc.letterhead.logo), backgroundRemoved: logo.removed });
});

r.post('/locations/:id/deactivate', ownerOnly, async (req, res) => {
  const loc = await ownLocation(req);
  const upcoming = await M.Appointment.countDocuments({ locationId: loc._id, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] } });
  if (upcoming && !req.body.confirm) {
    throw conflict(`${upcoming} patients have upcoming bookings here`, 'HAS_UPCOMING', { upcoming });
  }
  loc.status = 'inactive';
  loc.deactivatedAt = new Date();
  await loc.save();
  res.json(loc);
});

r.post('/locations/:id/activate', ownerOnly, async (req, res) => {
  const loc = await ownLocation(req);
  loc.status = 'active';
  loc.deactivatedAt = undefined;
  await loc.save();
  res.json(loc);
});

r.post('/locations/:id/closures', ownerOnly, async (req, res) => {
  const loc = await ownLocation(req);
  const startDate = T.parseDay(req.body.startDate);
  const endDate = T.parseDay(req.body.endDate || req.body.startDate);
  if (endDate < startDate) throw badRequest('End date is before the start date');
  const closure = await M.LocationClosure.create({ locationId: loc._id, startDate, endDate, reason: req.body.reason || 'Closed all day', createdBy: req.user._id });
  res.status(201).json(closure);
});

r.delete('/locations/:id/closures/:closureId', ownerOnly, async (req, res) => {
  const loc = await ownLocation(req);
  await M.LocationClosure.deleteOne({ _id: req.params.closureId, locationId: loc._id });
  res.json({ ok: true });
});

// ── Departments ──
r.get('/departments', async (req, res) => {
  const deps = await M.Department.find({ $or: [{ practiceId: req.practiceId }, { practiceId: null }] }).sort({ name: 1 });
  const usage = await M.DashboardPanel.aggregate([{ $match: { practiceId: req.practiceId } }, { $group: { _id: '$departmentId', n: { $sum: 1 } } }]);
  const um = new Map(usage.map((u) => [String(u._id), u.n]));
  res.json(deps.map((d) => ({ ...d.toJSON(), shared: !d.practiceId, panels: um.get(String(d._id)) || 0 })));
});

r.post('/departments', ownerOnly, async (req, res) => {
  const name = String(req.body.name || '').trim();
  if (!name) throw badRequest('Enter a department name', 'NAME_REQUIRED');
  try {
    res.status(201).json(await M.Department.create({ practiceId: req.practiceId, name }));
  } catch (err) {
    if (err.code === 11000) throw conflict('That department already exists');
    throw err;
  }
});

r.patch('/departments/:id', ownerOnly, async (req, res) => {
  const name = String(req.body.name || '').trim();
  if (!name) throw badRequest('Enter a department name', 'NAME_REQUIRED');
  const dep = await M.Department.findOneAndUpdate({ _id: req.params.id, practiceId: req.practiceId }, { name }, { new: true });
  if (!dep) throw notFound('Department');
  res.json(dep);
});

// ── Team ──
const memberView = (m) => ({
  id: m._id, userId: m.userId?._id || m.userId, name: m.userId?.name, phone: m.userId?.phone || m.phone, role: m.role,
  department: m.departmentId ? { id: m.departmentId._id, name: m.departmentId.name } : null,
  locations: (m.locationIds || []).map((l) => ({ id: l._id, name: l.name })), allLocations: m.allLocations,
  isOwner: m.isOwner, status: m.status, joinedAt: m.joinedAt, qualifications: m.qualifications, registrationNo: m.registrationNo,
  permissions: M.ROLE_PERMISSIONS[m.role],
});

async function seats(practiceId) {
  const sub = await M.Subscription.findOne({ practiceId });
  const plan = sub ? await M.Plan.findOne({ key: sub.planKey }) : null;
  const used = await M.Member.countDocuments({ practiceId, status: 'active' });
  return { used, limit: plan?.seats ?? null, plan: plan?.name };
}

r.get('/members', async (req, res) => {
  const members = await M.Member.find({ practiceId: req.practiceId }).populate('userId', 'name phone').populate('departmentId', 'name').populate('locationIds', 'name');
  res.json({ seats: await seats(req.practiceId), items: members.map(memberView) });
});

r.get('/members/:id', async (req, res) => {
  const m = await M.Member.findOne({ _id: req.params.id, practiceId: req.practiceId }).populate('userId', 'name phone').populate('departmentId', 'name').populate('locationIds', 'name');
  if (!m) throw notFound('Member');
  res.json(memberView(m));
});

// People-Add: verify the new member's phone first.
r.post('/members/phone-otp', ownerOnly, async (req, res) => {
  res.json(await issueOtp(normalizePhone(req.body.phone), 'verify_member_phone'));
});

r.post('/members', ownerOnly, async (req, res) => {
  const { role, name, departmentId, locationIds = [], allLocations, qualifications, registrationNo, otpCode } = req.body;
  if (!E.MEMBER_ROLES.includes(role)) throw badRequest('Choose a role');
  if (!name) throw badRequest('Enter the full name');
  const phone = normalizePhone(req.body.phone);
  // The new team member confirms their number with the code sent to it.
  if (!otpCode) throw badRequest('Verify their mobile number with the code sent to it', 'OTP_REQUIRED');
  await checkOtp(phone, 'verify_member_phone', otpCode);
  const s = await seats(req.practiceId);
  if (s.limit != null && s.used >= s.limit) throw conflict(`All ${s.limit} seats on the ${s.plan} plan are used`, 'NO_SEATS', s);
  let user = await M.User.findOne({ phone });
  if (!user) user = await M.User.create({ phone, name, phoneVerifiedAt: new Date() });
  if (await M.Member.exists({ practiceId: req.practiceId, userId: user._id })) throw conflict('This person is already on the team');
  const member = await M.Member.create({
    practiceId: req.practiceId, userId: user._id, role, departmentId, locationIds, allLocations: Boolean(allLocations),
    qualifications: role === 'doctor' ? qualifications : undefined, registrationNo: role === 'doctor' ? registrationNo : undefined,
    phone, invitedBy: req.user._id,
  });
  if (role === 'doctor' && !(await M.DoctorProfile.exists({ userId: user._id }))) {
    await M.DoctorProfile.create({ userId: user._id, displayName: name, degreesSummary: qualifications, registration: registrationNo ? { number: registrationNo } : undefined });
  }
  await member.populate([{ path: 'userId', select: 'name phone' }, { path: 'departmentId', select: 'name' }, { path: 'locationIds', select: 'name' }]);
  res.status(201).json(memberView(member));
});

r.patch('/members/:id', ownerOnly, async (req, res) => {
  const m = await M.Member.findOne({ _id: req.params.id, practiceId: req.practiceId });
  if (!m) throw notFound('Member');
  const body = pick(req.body, ['role', 'departmentId', 'locationIds', 'allLocations', 'qualifications', 'registrationNo']);
  if (body.role && !E.MEMBER_ROLES.includes(body.role)) throw badRequest('Unknown role');
  if (m.isOwner && body.role && body.role !== m.role) throw conflict("The owner's role can't be changed");
  Object.assign(m, body);
  if (req.body.suspended !== undefined) {
    if (m.isOwner) throw conflict("The owner can't be suspended");
    m.status = req.body.suspended ? 'suspended' : 'active';
    m.suspendedAt = req.body.suspended ? new Date() : undefined;
    // "Suspended members lose access immediately"
    if (req.body.suspended && !(await M.Member.exists({ userId: m.userId, status: 'active', _id: { $ne: m._id } }))) {
      await M.AuthSession.updateMany({ userId: m.userId, revokedAt: null }, { revokedAt: new Date() });
    }
  }
  await m.save();
  await m.populate([{ path: 'userId', select: 'name phone' }, { path: 'departmentId', select: 'name' }, { path: 'locationIds', select: 'name' }]);
  res.json(memberView(m));
});

// ── Invites (Register step 2) ──
// Invite codes are switched off: staff are added in People with their phone
// number (and its code), then simply sign in.
const INVITES_OFF = () => Object.assign(new Error('Invite codes are off. Add the person in People with their mobile number.'), { status: 410, code: 'INVITES_OFF' });
r.post('/invites', ownerOnly, async () => {
  throw INVITES_OFF();
});

r.get('/invites', ownerOnly, async (req, res) => {
  res.json(await M.Invite.find({ practiceId: req.practiceId, usedAt: null, revokedAt: null }).sort({ createdAt: -1 }));
});

r.delete('/invites/:id', ownerOnly, async (req, res) => {
  await M.Invite.updateOne({ _id: req.params.id, practiceId: req.practiceId }, { revokedAt: new Date() });
  res.json({ ok: true });
});

module.exports = r;

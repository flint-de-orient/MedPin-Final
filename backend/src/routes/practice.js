// Practice, Clinics, Clinic-Editor, Departments, People, People-Add, People-Member.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff, need, ownerOnly, ownPractice } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, forbidden, normalizePhone, isId, escapeRegex } = require('../lib/http');
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
  // The doctor's name always prints; a letterhead is "set" once a clinic has its logo (or a printed name).
  const hasLetterhead = await M.Location.exists({
    practiceId: req.practiceId,
    $or: [{ 'letterhead.logo.key': { $nin: [null, ''] } }, { 'letterhead.doctorNamePrinted': { $nin: [null, ''] } }],
  });
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
    // The open branches: a checklist item opens that branch's editor (one branch) or the list.
    branches: (await M.Location.find({ practiceId: req.practiceId, status: 'active' }, 'name shortName').sort({ createdAt: 1 }).lean()).map((l) => ({ id: l._id, name: l.shortName || l.name })),
    role: req.member.role,
    isOwner: req.member.isOwner,
    permissions: req.perms,
  });
});

r.patch('/practice', ownerOnly, async (req, res) => {
  const body = pick(req.body, ['name', 'tagline', 'registrationNo', 'patientCallNumber', 'foodLogReviewCadence']);
  if (body.name !== undefined && String(body.name).trim().length < 2) throw badRequest('Enter the clinic name', 'NAME_REQUIRED');
  for (const k of ['name', 'tagline', 'registrationNo']) if (typeof body[k] === 'string') body[k] = body[k].trim().slice(0, 120);
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

// ── Who may change what at a location (permissions in models/practice.js) ──
const hasPerm = (req, perm) => Boolean(req.member?.isOwner || req.perms?.[perm]);
const coversLocation = (member, locationId) => Boolean(member?.isOwner || member?.allLocations
  || (member?.locationIds || []).some((l) => String(l._id || l) === String(locationId)));

/** Edit flags for the Clinic-Editor, with one honest line about what the caller can't change. */
function clinicAccess(req, loc) {
  const managed = loc.status === 'view_only' || Boolean(loc.managedByPracticeId);
  const details = !managed && hasPerm(req, 'manageClinic');
  const closures = !managed && (details || (hasPerm(req, 'closures') && coversLocation(req.member, loc._id)));
  let note = null;
  if (managed) note = 'View only · managed by another organisation.';
  else if (!details && closures) note = 'You can add and remove holidays and closures. Details and weekly hours are changed by the owner or practice manager.';
  else if (!details) note = 'Only the owner or practice manager can change these details. Ask them if something needs updating.';
  return { details, hours: details, closures, note };
}

/** May the caller change this doctor's hours? Their own always; others with doctorHours (an assistant: their doctors only). */
function mayChangeHours(req, doctorId) {
  if (String(doctorId) === String(req.user._id)) return true;
  if (!hasPerm(req, 'doctorHours')) return false;
  if (req.member.role === 'doctor_assistant' && !req.member.isOwner) return (req.member.assistsDoctorIds || []).some((d) => String(d) === String(doctorId));
  return true;
}

/** Everyone working at this location sees the change at once (open screens reload). */
async function signalLocation(req, loc) {
  const { signal, practiceStaff } = require('../services/notify');
  await signal(await practiceStaff(req.practiceId, { locationId: loc._id }), { type: 'location_changed', practiceId: req.practiceId, locationId: loc._id });
}

/** Booked visits from now on at this location that fall outside its weekly hours (or a doctor's new week). */
async function visitsOutsideHours(loc, { doctorId, week } = {}) {
  const q = { locationId: loc._id, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] }, ...(doctorId ? { doctorId } : {}) };
  const rows = await M.Appointment.find(q, 'startAt mode').limit(2000);
  return rows.filter((a) => {
    if (a.mode && a.mode !== 'in_clinic') return false;
    const wd = T.weekday(a.startAt);
    const m = T.minuteOfDay(a.startAt);
    if (week) {
      const day = week.find((w) => w.weekday === wd);
      return !(day?.sessions || []).some((x) => m >= x.startMin && m < x.endMin);
    }
    const h = (loc.weeklyHours || []).find((x) => x.weekday === wd);
    return h ? h.isOpen === false || m < h.opensAt || m >= h.closesAt : false;
  }).length;
}

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
  const photos = await require('../services/photos').doctorPhotos(doctors.map((d) => d.doctorId?._id).filter(Boolean));
  res.json({
    ...json, upcomingBookings, closures, can: clinicAccess(req, loc),
    doctors: doctors.filter((d) => d.doctorId).map((d) => ({
      doctorId: d.doctorId._id, name: d.doctorId.name, week: d.schedule.week, slotLengthMin: d.schedule.slotLengthMin,
      photo: photos.get(String(d.doctorId._id)) || null, isMe: String(d.doctorId._id) === String(req.user._id), canEdit: mayChangeHours(req, d.doctorId._id),
    })),
  });
});

r.patch('/locations/:id', need('manageClinic'), async (req, res) => {
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
  await signalLocation(req, loc);
  // New weekly hours: visits already booked outside them stay, and the desk is told to move them.
  const outsideHours = body.weeklyHours ? await visitsOutsideHours(loc) : 0;
  if (outsideHours) {
    const { notify, deskOrDoctors } = require('../services/notify');
    const desk = (await deskOrDoctors(req.practiceId, { locationId: loc._id })).filter((id) => String(id) !== String(req.user._id));
    await notify(desk, { type: 'clinic_hours_changed', practiceId: req.practiceId, title: `${outsideHours} visit${outsideHours === 1 ? '' : 's'} outside the new hours`, body: `${loc.shortName || loc.name} · weekly hours changed`, screen: 'Appointments' });
  }
  res.json({ ...loc.toJSON(), outsideHours });
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
r.post('/locations/:id/logo', need('manageClinic'), upload.single('file'), async (req, res) => {
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
  // Team members who work only here would be left with no location: they are
  // suspended (owners get every location). Both warnings come in one 409, so one
  // second tap (confirm) has seen everything.
  const here = await M.Member.find({ practiceId: req.practiceId, status: { $ne: 'removed' }, allLocations: { $ne: true }, locationIds: loc._id }).populate('userId', 'name');
  const stranded = here.filter((m) => m.locationIds.every((id) => String(id) === String(loc._id)));
  const toSuspend = stranded.filter((m) => !m.isOwner && m.status === 'active');
  if ((upcoming || toSuspend.length) && !req.body.confirm) {
    const names = toSuspend.map((m) => m.userId?.name || 'A team member');
    const parts = [
      upcoming && `${upcoming} patients have upcoming bookings here`,
      names.length && `${names.join(', ')} ${names.length === 1 ? 'works' : 'work'} only here and will be suspended`,
    ].filter(Boolean);
    throw conflict(parts.join('. '), upcoming ? 'HAS_UPCOMING' : 'MEMBERS_ONLY_HERE', { upcoming, members: names });
  }
  loc.status = 'inactive';
  loc.deactivatedAt = new Date();
  await loc.save();
  // Upcoming visits here can't happen: cancelled, so each patient is told (and a fee paid
  // online is refunded) instead of coming to a closed branch.
  const S = require('../services/scheduling');
  let cancelled = 0;
  for (const a of await M.Appointment.find({ locationId: loc._id, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] } })) {
    await S.transition(a, 'cancelled', { by: req.user._id, cancelledBy: 'desk', reason: `${loc.name} is closed. Please book at another branch.` })
      .then(() => { cancelled += 1; })
      .catch((err) => console.warn('[branch closed]', err.message));
  }
  await M.Member.updateMany({ practiceId: req.practiceId, locationIds: loc._id }, { $pull: { locationIds: loc._id } });
  for (const m of stranded) {
    if (m.isOwner) await M.Member.updateOne({ _id: m._id }, { allLocations: true });
    else if (m.status === 'active') await setSuspended(m._id, true);
  }
  res.json({ ...loc.toJSON(), suspendedMembers: toSuspend.length, visitsCancelled: cancelled });
});

r.post('/locations/:id/activate', ownerOnly, async (req, res) => {
  const loc = await ownLocation(req);
  loc.status = 'active';
  loc.deactivatedAt = undefined;
  await loc.save();
  res.json(loc);
});

/** Closure dates and times from a request (all day, or part of the day: fromMin–toMin). */
function closureFields(body) {
  if (!body.startDate) throw badRequest('Choose the date', 'DATE_REQUIRED');
  const startDate = T.parseDay(body.startDate);
  const endDate = T.parseDay(body.endDate || body.startDate);
  if (endDate < startDate) throw badRequest('End date is before the start date');
  if (endDate < T.dayStart()) throw badRequest('Choose today or a later date', 'DATE_PAST');
  const allDay = !(body.allDay === false || body.allDay === 'false');
  if (allDay) return { startDate, endDate, allDay, fromMin: undefined, toMin: undefined };
  const fromMin = Number(body.fromMin);
  const toMin = Number(body.toMin);
  if (!Number.isInteger(fromMin) || !Number.isInteger(toMin) || fromMin < 0 || toMin > 1440 || toMin <= fromMin) {
    throw badRequest('Choose an end time after the start time', 'BAD_HOURS');
  }
  return { startDate, endDate, allDay, fromMin, toMin };
}

/** Booked visits a closure touches (on those days; for part of the day, in those hours). */
async function closureVisits(loc, c) {
  const rows = await M.Appointment.find({
    locationId: loc._id, startAt: { $gte: c.startDate, $lt: T.addDays(c.endDate, 1) }, status: { $in: ['booked', 'confirmed'] },
  }).populate('patientId', 'userId');
  if (c.allDay !== false) return rows;
  return rows.filter((a) => {
    const m = T.minuteOfDay(a.startAt);
    return m >= c.fromMin && m < c.toMin;
  });
}

/** "2026-10-20 to 2026-10-23 · 2:00 PM – 6:00 PM" */
const closureWhen = (c) => `${T.dayKey(c.startDate)}${+c.endDate !== +c.startDate ? ` to ${T.dayKey(c.endDate)}` : ''}${c.allDay === false ? ` · ${T.fmtTime(c.fromMin)} – ${T.fmtTime(c.toMin)}` : ''}`;

/** The location, when the caller may change its closures (manageClinic, or closures at a location they cover). */
async function closureLocation(req) {
  const loc = await ownLocation(req);
  if (!clinicAccess(req, loc).closures) throw forbidden("Your role doesn't allow changing this location's closures", 'PERMISSION_REQUIRED');
  return loc;
}

// Before adding: how many booked patients would be told.
r.get('/locations/:id/closures/preview', async (req, res) => {
  const loc = await closureLocation(req);
  const c = closureFields(req.query);
  res.json({ booked: (await closureVisits(loc, c)).length });
});

r.post('/locations/:id/closures', async (req, res) => {
  const loc = await closureLocation(req);
  const c = closureFields(req.body);
  const overlapping = await M.LocationClosure.find({ locationId: loc._id, startDate: { $lte: c.endDate }, endDate: { $gte: c.startDate } });
  const clash = overlapping.some((o) => o.allDay !== false || c.allDay || (c.fromMin < o.toMin && c.toMin > o.fromMin));
  if (clash) throw conflict('This location is already closed then. Remove that closure first, or choose other dates.', 'CLOSURE_OVERLAP');
  const reason = String(req.body.reason || '').trim().slice(0, 120) || (c.allDay ? 'Closed all day' : 'Closed part of the day');
  const closure = await M.LocationClosure.create({ locationId: loc._id, ...c, reason, createdBy: req.user._id });
  // Patients already booked then are told, like a doctor's leave; the desk moves the visits.
  const affected = await closureVisits(loc, c);
  const { notify, deskOrDoctors } = require('../services/notify');
  const where = loc.shortName || loc.name;
  const days = closureWhen(c);
  await notify(affected.map((a) => a.patientId?.userId).filter(Boolean), {
    type: 'clinic_closed', practiceId: req.practiceId, title: `${where} is closed`,
    body: `${days} · ${reason}. Please choose another time for your visit.`, screen: 'Patient-Doctors', whatsapp: true,
  });
  const notMe = (ids) => ids.filter((id) => String(id) !== String(req.user._id));
  if (affected.length) {
    const desk = notMe(await deskOrDoctors(req.practiceId, { locationId: loc._id }));
    await notify(desk, { type: 'clinic_closed', practiceId: req.practiceId, title: `${affected.length} visit${affected.length === 1 ? '' : 's'} to move`, body: `${where} is closed ${days}`, screen: 'Appointments' });
  }
  // The doctors who practise here: their sessions then are off.
  const doctors = notMe(await M.DoctorLocation.find({ locationId: loc._id, status: 'active' }).distinct('doctorId'));
  await notify(doctors, {
    type: 'clinic_closed', practiceId: req.practiceId, title: `${where} closed · ${reason}`,
    body: `${days} · added by ${req.user.name || 'the clinic'}`, screen: 'Profile-Schedule', params: { locationId: String(loc._id) },
  });
  closure.patientsTold = affected.length;
  await closure.save();
  await signalLocation(req, loc);
  res.status(201).json({ ...closure.toJSON(), patientsTold: affected.length });
});

// Remove a closure: bookings open again; patients still booked then hear their visit stands.
r.delete('/locations/:id/closures/:closureId', async (req, res) => {
  const loc = await closureLocation(req);
  if (!isId(req.params.closureId)) throw notFound('Closure');
  const c = await M.LocationClosure.findOneAndDelete({ _id: req.params.closureId, locationId: loc._id });
  if (!c) throw notFound('Closure');
  let told = 0;
  if (c.endDate >= T.dayStart()) {
    const still = await closureVisits(loc, c);
    const { notify } = require('../services/notify');
    await notify(still.map((a) => a.patientId?.userId).filter(Boolean), {
      type: 'clinic_reopened', practiceId: req.practiceId, title: `${loc.shortName || loc.name} is open again`,
      body: `${closureWhen(c)} · your booked visit stands.`, screen: 'Patient-Doctors',
    });
    told = still.length;
  }
  await signalLocation(req, loc);
  res.json({ ok: true, patientsTold: told });
});

// A doctor's hours at this location (Clinic-Editor → Per-doctor hours).
r.put('/locations/:id/doctors/:doctorId/hours', async (req, res) => {
  const loc = await ownLocation(req);
  if (!isId(req.params.doctorId)) throw notFound('Doctor');
  if (!mayChangeHours(req, req.params.doctorId)) throw forbidden('Only the doctor, the owner or the practice manager can change these hours', 'PERMISSION_REQUIRED');
  const dl = await M.DoctorLocation.findOne({ doctorId: req.params.doctorId, locationId: loc._id, status: 'active' }).populate('doctorId', 'name');
  if (!dl || !dl.doctorId) throw notFound("Doctor's hours here");
  const given = Array.isArray(req.body.week) ? req.body.week : null;
  if (!given) throw badRequest('Send the week', 'BAD_HOURS');
  const week = E.WEEKDAYS.map((weekday) => {
    const day = given.find((w) => w && w.weekday === weekday);
    const sessions = (Array.isArray(day?.sessions) ? day.sessions : [])
      .map((x) => ({ startMin: Number(x?.startMin), endMin: Number(x?.endMin) }))
      .sort((a, b) => a.startMin - b.startMin);
    sessions.forEach((x, i) => {
      if (!Number.isInteger(x.startMin) || !Number.isInteger(x.endMin) || x.startMin < 0 || x.endMin > 1440 || x.endMin <= x.startMin) {
        throw badRequest('Closing time must be after opening time', 'BAD_HOURS');
      }
      if (i && x.startMin < sessions[i - 1].endMin) throw badRequest('Two sessions on the same day overlap', 'BAD_HOURS');
    });
    return { weekday, sessions };
  });
  dl.schedule.week = week;
  dl.markModified('schedule');
  await dl.save();
  const outsideHours = await visitsOutsideHours(loc, { doctorId: dl.doctorId._id, week });
  const { notify, deskOrDoctors } = require('../services/notify');
  const where = loc.shortName || loc.name;
  if (String(dl.doctorId._id) !== String(req.user._id)) {
    await notify([dl.doctorId._id], {
      type: 'schedule_changed', practiceId: req.practiceId, title: `Your hours at ${where} changed`,
      body: `Changed by ${req.user.name || 'the clinic'}`, screen: 'Profile-Schedule', params: { locationId: String(loc._id) },
    });
  }
  if (outsideHours) {
    const desk = (await deskOrDoctors(req.practiceId, { locationId: loc._id, doctorId: dl.doctorId._id })).filter((id) => String(id) !== String(req.user._id));
    await notify(desk, {
      type: 'schedule_changed', practiceId: req.practiceId, title: `${outsideHours} visit${outsideHours === 1 ? '' : 's'} outside ${dl.doctorId.name || 'the doctor'}'s new hours`,
      body: where, screen: 'Appointments',
    });
  }
  await signalLocation(req, loc);
  res.json({ doctorId: dl.doctorId._id, week, outsideHours });
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
// Roles where a department means something (the doctor's own specialty, or the
// doctors an assistant / dietician works with). Others get none.
const DEPARTMENT_ROLES = ['doctor', 'doctor_assistant', 'dietician'];
// Find-doctor specialty → the department it is in a clinic.
const SPECIALTY_DEPARTMENT = {
  gp: 'General medicine', diabetes: 'Diabetology', heart: 'Cardiology', women: 'Gynaecology', child: 'Paediatrics', skin: 'Dermatology',
  bones: 'Orthopaedics', mind: 'Psychiatry', stomach: 'Gastroenterology', eye: 'Ophthalmology', teeth: 'Dentistry', ent: 'ENT',
};
const ROLE_LABEL = {
  doctor: 'Doctor', front_desk: 'Front desk', doctor_assistant: "Doctor's assistant", dietician: 'Dietician',
  lab_manager: 'Lab manager', lab_technician: 'Lab technician', practice_manager: 'Practice manager',
};
const MEMBER_POPULATE = [
  { path: 'userId', select: 'name phone' }, { path: 'departmentId', select: 'name' }, { path: 'locationIds', select: 'name status' }, { path: 'assistsDoctorIds', select: 'name' },
];

const activeOwners = (practiceId) => M.Member.countDocuments({ practiceId, isOwner: true, status: 'active' });

/**
 * Why the caller can't change this member's access (null = they can): your own
 * access, an owner's access (only owners change owners), a removed member.
 */
function lockFor(req, m) {
  if (m.status === 'removed') return { code: 'MEMBER_REMOVED', reason: 'Removed from the team. Add them again to give access.' };
  if (String(m.userId?._id || m.userId) === String(req.user._id)) return { code: 'SELF_ACCESS', reason: "You can't change your own access. Another owner can." };
  if (m.isOwner && !req.member.isOwner) return { code: 'OWNER_REQUIRED', reason: "Only an owner can change an owner's access." };
  return null;
}

const memberView = (m, req, owners) => {
  const lock = req ? lockFor(req, m) : null;
  const lastOwner = m.isOwner && m.status === 'active' && owners <= 1;
  return {
    id: m._id, userId: m.userId?._id || m.userId, name: m.userId?.name, phone: m.userId?.phone || m.phone, role: m.role,
    department: m.departmentId ? { id: m.departmentId._id, name: m.departmentId.name } : null,
    locations: (m.locationIds || []).filter((l) => l.status !== 'inactive').map((l) => ({ id: l._id, name: l.name })), allLocations: m.allLocations,
    assists: (m.assistsDoctorIds || []).map((d) => ({ userId: d._id || d, name: d.name })),
    isOwner: m.isOwner, status: m.status, joinedAt: m.joinedAt, suspendedAt: m.suspendedAt, qualifications: m.qualifications, registrationNo: m.registrationNo,
    permissions: M.ROLE_PERMISSIONS[m.role],
    // What the caller may do with this member (People-Member hides the rest, with the reason).
    canEdit: !lock,
    canChangeRole: !lock && !m.isOwner,
    canSuspend: !lock && !lastOwner,
    canRemove: !lock && !lastOwner,
    lockReason: lock?.reason || (lastOwner ? 'The practice needs at least one owner.' : null),
  };
};

async function seats(practiceId) {
  const sub = await M.Subscription.findOne({ practiceId });
  const plan = sub ? await M.Plan.findOne({ key: sub.planKey }) : null;
  const used = await M.Member.countDocuments({ practiceId, status: 'active' });
  return { used, limit: plan?.seats ?? null, plan: plan?.name };
}

/**
 * What the Add / Edit forms offer: the active locations, the doctors who
 * practise at each (DoctorLocation) with the departments they practise in,
 * and every department name. A doctor's departments: their specialisations
 * that are departments here, else their Find-doctor specialty, else the
 * department on their membership.
 */
async function teamOptions(practiceId) {
  const [locations, doctors, deps] = await Promise.all([
    M.Location.find({ practiceId, status: 'active' }, 'name shortName').sort({ name: 1 }),
    M.Member.find({ practiceId, role: 'doctor', status: 'active' }).populate('userId', 'name').populate('departmentId', 'name'),
    M.Department.find({ $or: [{ practiceId }, { practiceId: null }] }, 'name').sort({ name: 1 }),
  ]);
  const ids = doctors.map((d) => d.userId?._id).filter(Boolean);
  const [profiles, dls] = await Promise.all([
    M.DoctorProfile.find({ userId: { $in: ids } }, 'userId displayName specialtyKeys specialisations'),
    M.DoctorLocation.find({ practiceId, doctorId: { $in: ids }, status: 'active' }, 'doctorId locationId'),
  ]);
  const known = new Map(deps.map((d) => [d.name.toLowerCase(), d.name]));
  const active = new Set(locations.map((l) => String(l._id)));
  const departmentsOf = (m, prof) => {
    const fromTags = (prof?.specialisations || []).map((s) => known.get(String(s).trim().toLowerCase())).filter(Boolean);
    if (fromTags.length) return [...new Set(fromTags)];
    const fromKeys = (prof?.specialtyKeys || []).map((k) => SPECIALTY_DEPARTMENT[k]).filter(Boolean);
    if (fromKeys.length) return [...new Set(fromKeys)];
    return m.departmentId?.name ? [m.departmentId.name] : [];
  };
  return {
    locations: locations.map((l) => ({ id: l._id, name: l.name, shortName: l.shortName })),
    doctors: doctors.filter((m) => m.userId).map((m) => {
      const prof = profiles.find((p) => String(p.userId) === String(m.userId._id));
      const at = dls.filter((d) => String(d.doctorId) === String(m.userId._id)).map((d) => String(d.locationId)).filter((id) => active.has(id));
      // No schedule anywhere yet: where their membership says they work.
      const where = at.length ? at : m.allLocations ? [...active] : (m.locationIds || []).map(String).filter((id) => active.has(id));
      return { userId: m.userId._id, name: prof?.displayName || m.userId.name, locationIds: where, departments: departmentsOf(m, prof) };
    }),
    departments: [...new Set([...deps.map((d) => d.name), ...Object.values(SPECIALTY_DEPARTMENT)])].sort((a, b) => a.localeCompare(b)),
  };
}

/** Department id from departmentId or a department name (made for the practice when new). */
async function departmentFor(req, body) {
  if (body.departmentId) {
    if (!isId(String(body.departmentId))) throw badRequest('Choose a department', 'BAD_DEPARTMENT');
    const dep = await M.Department.findOne({ _id: body.departmentId, $or: [{ practiceId: req.practiceId }, { practiceId: null }] });
    if (!dep) throw badRequest('Choose a department', 'BAD_DEPARTMENT');
    return dep._id;
  }
  const name = String(body.departmentName || '').trim();
  if (!name) return null;
  const same = { $regex: `^${escapeRegex(name)}$`, $options: 'i' };
  const dep = (await M.Department.findOne({ practiceId: req.practiceId, name: same })) || (await M.Department.findOne({ practiceId: null, name: same }))
    || (await M.Department.create({ practiceId: req.practiceId, name }));
  return dep._id;
}

/**
 * Checks and normalises who-works-where for a role: locations of this
 * practice that are active (at least one unless all locations); for a doctor's
 * assistant, the active doctor(s) they assist.
 */
async function accessFor(req, role, body, current = {}) {
  const allLocations = body.allLocations !== undefined ? Boolean(body.allLocations) : Boolean(current.allLocations);
  const wanted = body.locationIds !== undefined ? body.locationIds : (current.locationIds || []);
  const ids = [...new Set((Array.isArray(wanted) ? wanted : []).map(String))];
  if (ids.some((id) => !isId(id))) throw badRequest('Choose locations of this practice', 'BAD_LOCATION');
  const found = await M.Location.find({ _id: { $in: ids }, practiceId: req.practiceId, status: 'active' }, '_id');
  if (found.length !== ids.length && body.locationIds !== undefined) throw badRequest('Choose active locations of this practice', 'BAD_LOCATION');
  const locationIds = found.map((l) => l._id);
  if (!allLocations && !locationIds.length) throw badRequest('Choose at least one location', 'LOCATION_REQUIRED');
  let assistsDoctorIds = [];
  if (role === 'doctor_assistant') {
    const want = body.assistsDoctorIds !== undefined ? body.assistsDoctorIds : (current.assistsDoctorIds || []);
    const dIds = [...new Set((Array.isArray(want) ? want : []).map(String))].filter(isId);
    const docs = await M.Member.find({ practiceId: req.practiceId, role: 'doctor', status: 'active', userId: { $in: dIds } }, 'userId');
    if (docs.length !== dIds.length) throw badRequest('Choose doctors of this practice', 'BAD_DOCTOR');
    const anyDoctor = await M.Member.exists({ practiceId: req.practiceId, role: 'doctor', status: 'active' });
    if (!docs.length && anyDoctor) throw badRequest('Choose the doctor they assist', 'DOCTOR_REQUIRED');
    assistsDoctorIds = docs.map((d) => d.userId);
  }
  return { allLocations, locationIds, assistsDoctorIds };
}

/** Suspends / reactivates a member; suspended members lose access at once. */
async function setSuspended(memberId, suspended) {
  const m = await M.Member.findById(memberId);
  if (!m) return;
  m.status = suspended ? 'suspended' : 'active';
  m.suspendedAt = suspended ? new Date() : undefined;
  await m.save();
  if (suspended) await signOutUnlessMember(m);
}

/** Ends the person's sessions when this was their last active membership (a patient account stays usable elsewhere). */
async function signOutUnlessMember(m) {
  if (await M.Member.exists({ userId: m.userId, status: 'active', _id: { $ne: m._id } })) return;
  await M.AuthSession.updateMany({ userId: m.userId, revokedAt: null }, { revokedAt: new Date() });
  await M.DeviceToken.deleteMany({ userId: m.userId }); // signed out everywhere: no more pushes
}

/** Tells the member their access changed (server checks use the new access from the next request). */
async function tellAccessChanged(m, title) {
  const { notify, signal } = require('../services/notify');
  const names = m.allLocations ? [] : await M.Location.find({ _id: { $in: (m.locationIds || []).map((l) => l._id || l) } }).distinct('name');
  const where = m.allLocations ? 'All locations' : names.join(', ');
  await notify([m.userId], { type: 'member_access_changed', practiceId: m.practiceId, title, body: [ROLE_LABEL[m.role] || m.role, where].filter(Boolean).join(' · ') }).catch(() => {});
  await signal([m.userId], { type: 'membership_changed', practiceId: m.practiceId });
}

r.get('/members', async (req, res) => {
  const [members, owners] = await Promise.all([
    M.Member.find({ practiceId: req.practiceId, status: { $ne: 'removed' } }).populate(MEMBER_POPULATE),
    activeOwners(req.practiceId),
  ]);
  // Everyone's profile photo (a doctor's public photo first) for the avatars.
  const photos = await require('../services/photos').doctorPhotos(members.map((m) => m.userId?._id || m.userId));
  const items = members.map((m) => ({ ...memberView(m, req, owners), photo: photos.get(String(m.userId?._id || m.userId)) || null }));
  res.json({ seats: await seats(req.practiceId), items, meId: req.member._id });
});

r.get('/members/options', async (req, res) => res.json(await teamOptions(req.practiceId)));

// Profile → Account / Clinic details: my own membership here — role, department,
// the locations I cover with the doctors working at each, the doctors I work for
// (an assistant: the ones they assist; others: the doctors at their locations),
// when I joined and my permissions (the app says them in plain words).
r.get('/members/me', async (req, res) => {
  const m = await M.Member.findById(req.member._id).populate(MEMBER_POPULATE);
  const everywhere = m.isOwner || m.allLocations;
  const [practice, locs, owners] = await Promise.all([
    M.Practice.findById(req.practiceId, 'name'),
    M.Location.find({ practiceId: req.practiceId, status: 'active', ...(everywhere ? {} : { _id: { $in: (m.locationIds || []).map((l) => l._id || l) } }) }).sort({ name: 1 }),
    activeOwners(req.practiceId),
  ]);
  const dls = await M.DoctorLocation.find({ locationId: { $in: locs.map((l) => l._id) }, status: 'active' }).populate('doctorId', 'name');
  const assists = (m.assistsDoctorIds || []).filter((d) => d && d._id);
  const photos = await require('../services/photos').doctorPhotos([...dls.map((d) => d.doctorId?._id), ...assists.map((d) => d._id)].filter(Boolean));
  const doctor = (id, name) => ({ userId: id, name, photo: photos.get(String(id)) || null });
  const at = (l) => {
    const seen = new Set();
    return dls.filter((d) => d.doctorId && String(d.locationId) === String(l._id) && !seen.has(String(d.doctorId._id)) && seen.add(String(d.doctorId._id)))
      .map((d) => doctor(d.doctorId._id, d.doctorId.name));
  };
  const coverage = locs.map((l) => ({ id: l._id, name: l.name, shortName: l.shortName, address: l.address, doctors: at(l), can: clinicAccess(req, l) }));
  const mine = (d) => String(d.userId) !== String(req.user._id);
  const worksFor = m.role === 'doctor_assistant' && assists.length
    ? assists.map((d) => doctor(d._id, d.name))
    : [...new Map(coverage.flatMap((c) => c.doctors).filter(mine).map((d) => [String(d.userId), d])).values()];
  res.json({
    ...memberView(m, req, owners),
    permissions: req.perms,
    practice: { id: practice?._id, name: practice?.name },
    allLocations: everywhere,
    coverage,
    worksFor,
  });
});

r.get('/members/:id', async (req, res) => {
  if (!isId(req.params.id)) throw notFound('Member');
  const m = await M.Member.findOne({ _id: req.params.id, practiceId: req.practiceId }).populate(MEMBER_POPULATE);
  if (!m) throw notFound('Member');
  const uid = m.userId?._id || m.userId;
  const photo = uid ? (await require('../services/photos').doctorPhotos([uid])).get(String(uid)) || null : null;
  res.json({ ...memberView(m, req, await activeOwners(req.practiceId)), photo });
});

/** An active or suspended member with this phone: no new code is sent for them. */
async function existingMember(practiceId, phone) {
  const user = await M.User.findOne({ phone }, '_id');
  return user ? M.Member.findOne({ practiceId, userId: user._id, status: { $ne: 'removed' } }) : null;
}
const alreadyOnTeam = (m) => (m.status === 'suspended'
  ? conflict('This person is on the team but suspended. Reactivate them from People.', 'MEMBER_SUSPENDED')
  : conflict('This person is already on the team', 'ALREADY_MEMBER'));

// People-Add: verify the new member's phone first.
r.post('/members/phone-otp', ownerOnly, async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  const m = await existingMember(req.practiceId, phone);
  if (m) throw alreadyOnTeam(m);
  res.json(await issueOtp(phone, 'verify_member_phone'));
});

r.post('/members', ownerOnly, async (req, res) => {
  const { role, name, qualifications, registrationNo, otpCode } = req.body;
  if (!E.MEMBER_ROLES.includes(role)) throw badRequest('Choose a role');
  if (!name || !String(name).trim()) throw badRequest('Enter the full name');
  const phone = normalizePhone(req.body.phone);
  const before = await existingMember(req.practiceId, phone);
  if (before) throw alreadyOnTeam(before);
  const access = await accessFor(req, role, req.body);
  const departmentId = DEPARTMENT_ROLES.includes(role) ? await departmentFor(req, req.body) : null;
  // The new team member confirms their number with the code sent to it.
  if (!otpCode) throw badRequest('Verify their mobile number with the code sent to it', 'OTP_REQUIRED');
  await checkOtp(phone, 'verify_member_phone', otpCode);
  const s = await seats(req.practiceId);
  if (s.limit != null && s.used >= s.limit) throw conflict(`All ${s.limit} seats on the ${s.plan} plan are used`, 'NO_SEATS', s);
  let user = await M.User.findOne({ phone });
  if (!user) user = await M.User.create({ phone, name: String(name).trim(), phoneVerifiedAt: new Date() });
  const fields = {
    role, departmentId: departmentId || undefined, ...access,
    qualifications: role === 'doctor' ? qualifications : undefined, registrationNo: role === 'doctor' ? registrationNo : undefined,
    phone, invitedBy: req.user._id, status: 'active', suspendedAt: undefined, removedAt: undefined,
  };
  // Someone removed earlier comes back on their old membership (one per person and practice).
  let member = await M.Member.findOne({ practiceId: req.practiceId, userId: user._id });
  if (member) {
    Object.assign(member, fields, { joinedAt: new Date() });
    await member.save();
  } else {
    member = await M.Member.create({ practiceId: req.practiceId, userId: user._id, ...fields });
  }
  if (role === 'doctor' && !(await M.DoctorProfile.exists({ userId: user._id }))) {
    await M.DoctorProfile.create({ userId: user._id, displayName: String(name).trim(), degreesSummary: qualifications, registration: registrationNo ? { number: registrationNo } : undefined });
  }
  await member.populate(MEMBER_POPULATE);
  res.status(201).json(memberView(member, req, await activeOwners(req.practiceId)));
});

const sameIds = (a, b) => {
  const x = (a || []).map((v) => String(v._id || v)).sort();
  const y = (b || []).map((v) => String(v._id || v)).sort();
  return x.length === y.length && x.every((v, i) => v === y[i]);
};

// People-Member "Edit access": role, locations, the doctor(s) an assistant
// works for, department, suspend / reactivate. Nobody changes their own access,
// only owners change an owner, and the practice always keeps an active owner.
r.patch('/members/:id', ownerOnly, async (req, res) => {
  if (!isId(req.params.id)) throw notFound('Member');
  const m = await M.Member.findOne({ _id: req.params.id, practiceId: req.practiceId });
  if (!m) throw notFound('Member');
  const lock = lockFor(req, m);
  const role = req.body.role !== undefined ? req.body.role : m.role;
  if (!E.MEMBER_ROLES.includes(role)) throw badRequest('Unknown role');
  const access = await accessFor(req, role, req.body, m);
  const suspend = req.body.suspended === undefined ? undefined : Boolean(req.body.suspended);
  const accessChanged = role !== m.role || access.allLocations !== Boolean(m.allLocations)
    || !sameIds(access.locationIds, m.locationIds) || !sameIds(access.assistsDoctorIds, m.assistsDoctorIds);
  const statusChanged = suspend !== undefined && suspend !== (m.status === 'suspended');
  if (lock?.code === 'MEMBER_REMOVED') throw conflict(lock.reason, lock.code);
  if (lock?.code === 'OWNER_REQUIRED') throw forbidden(lock.reason, lock.code);
  if (lock?.code === 'SELF_ACCESS' && (accessChanged || statusChanged)) throw conflict(lock.reason, lock.code);
  if (m.isOwner && role !== m.role) throw conflict("An owner's role can't be changed", 'OWNER_ROLE');
  if (m.isOwner && suspend && statusChanged && (await activeOwners(req.practiceId)) <= 1) throw conflict('The practice needs at least one active owner', 'LAST_OWNER');
  // Reactivating needs a free seat like adding someone does.
  if (statusChanged && !suspend) {
    const s = await seats(req.practiceId);
    if (s.limit != null && s.used >= s.limit) throw conflict(`All ${s.limit} seats on the ${s.plan} plan are used`, 'NO_SEATS', s);
  }
  m.role = role;
  Object.assign(m, access);
  if (!DEPARTMENT_ROLES.includes(role)) m.departmentId = undefined;
  else if (req.body.departmentId !== undefined || req.body.departmentName !== undefined) m.departmentId = (await departmentFor(req, req.body)) || undefined;
  if (role === 'doctor') Object.assign(m, pick(req.body, ['qualifications', 'registrationNo']));
  else Object.assign(m, { qualifications: undefined, registrationNo: undefined });
  await m.save();
  if (statusChanged) await setSuspended(m._id, suspend);
  const fresh = await M.Member.findById(m._id).populate(MEMBER_POPULATE);
  if (accessChanged && fresh.status === 'active') await tellAccessChanged(fresh, 'Your access changed');
  if (statusChanged && !suspend) await tellAccessChanged(fresh, 'Your access is back on');
  res.json(memberView(fresh, req, await activeOwners(req.practiceId)));
});

// People-Member "Remove from team": access ends at once; their name stays on past records.
r.delete('/members/:id', ownerOnly, async (req, res) => {
  if (!isId(req.params.id)) throw notFound('Member');
  const m = await M.Member.findOne({ _id: req.params.id, practiceId: req.practiceId });
  if (!m || m.status === 'removed') throw notFound('Member');
  const lock = lockFor(req, m);
  if (lock?.code === 'OWNER_REQUIRED') throw forbidden(lock.reason, lock.code);
  if (lock?.code === 'SELF_ACCESS') throw conflict("You can't remove yourself from the team. Another owner can.", lock.code);
  if (m.isOwner && m.status === 'active' && (await activeOwners(req.practiceId)) <= 1) throw conflict('The practice needs at least one active owner', 'LAST_OWNER');
  m.status = 'removed';
  m.removedAt = new Date();
  m.isOwner = false;
  await m.save();
  await signOutUnlessMember(m);
  res.json({ ok: true });
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

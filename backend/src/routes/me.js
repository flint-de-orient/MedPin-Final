// Account settings, devices, notifications, catalogs and signed file downloads.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const { requireAuth } = require('../middleware/auth');
const { pick, badRequest, notFound, escapeRegex, paging, forbidden } = require('../lib/http');
const storage = require('../services/storage');
const { accountSummary } = require('./auth');

const me = Router();
me.use(requireAuth);

me.get('/', async (req, res) => res.json(await accountSummary(req.user)));

me.patch('/', async (req, res) => {
  const body = pick(req.body, ['name', 'email', 'language', 'appLock']);
  if (body.language && !E.LANGUAGES.includes(body.language)) throw badRequest('Unknown language');
  Object.assign(req.user, body);
  await req.user.save();
  res.json(await accountSummary(req.user));
});

// Switch the practice used by staff endpoints (also settable per request with X-Practice-Id).
me.post('/active-practice', async (req, res) => {
  const member = await M.Member.findOne({ userId: req.user._id, practiceId: req.body.practiceId, status: 'active' });
  if (!member) throw forbidden('You are not a member of this practice', 'NOT_A_MEMBER');
  req.user.activePracticeId = member.practiceId;
  if (req.body.locationId) req.user.activeLocationId = req.body.locationId;
  await req.user.save();
  res.json({ ok: true, practiceId: member.practiceId });
});

me.post('/devices', async (req, res) => {
  const { token, platform } = req.body;
  if (!token || !E.PLATFORMS.includes(platform)) throw badRequest('token and platform are required');
  await M.DeviceToken.findOneAndUpdate({ token }, { userId: req.user._id, platform, lastSeenAt: new Date() }, { upsert: true });
  res.json({ ok: true });
});

// A doctor with no invite starts their own practice (they become its owner).
me.post('/practices', async (req, res) => {
  const { name, locationName, area, address, city, pincode } = req.body;
  if (!name) throw badRequest('Enter the practice name');
  if (!req.user.name && !req.body.doctorName) throw badRequest('Enter your name first');
  if (req.body.doctorName) req.user.name = req.body.doctorName;
  const practice = await M.Practice.create({ name, ownerUserId: req.user._id, tagline: req.body.tagline });
  const location = await M.Location.create({
    practiceId: practice._id, name: locationName || name, shortName: area, area, address, city, pincode,
    weeklyHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((weekday) => ({ weekday, isOpen: weekday !== 'sun', opensAt: 540, closesAt: 1200 })),
  });
  await M.Member.create({ practiceId: practice._id, userId: req.user._id, role: 'doctor', isOwner: true, allLocations: true, phone: req.user.phone });
  if (!(await M.DoctorProfile.exists({ userId: req.user._id }))) {
    await M.DoctorProfile.create({ userId: req.user._id, displayName: req.user.name });
  }
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
notifications.get('/', async (req, res) => {
  const { limit, skip } = paging(req.query);
  const q = { userId: req.user._id, ...(req.query.unread === 'true' ? { readAt: null } : {}) };
  const [items, unread] = await Promise.all([
    M.Notification.find(q).sort({ createdAt: -1 }).skip(skip).limit(limit),
    M.Notification.countDocuments({ userId: req.user._id, readAt: null }),
  ]);
  res.json({ items, unread });
});
notifications.post('/read-all', async (req, res) => {
  await M.Notification.updateMany({ userId: req.user._id, readAt: null }, { readAt: new Date() });
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

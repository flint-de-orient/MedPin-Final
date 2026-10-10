// Auth-Login, Auth-OTP, Auth-Register.
const { Router } = require('express');
const M = require('../models');
const env = require('../config/env');
const { requireAuth } = require('../middleware/auth');
const { badRequest, unauthorized, conflict, notFound, normalizePhone, maskPhone, forbidden } = require('../lib/http');
const { hmac, randomDigits, randomToken, sha256, signAccess, ttlMs, safeEqual } = require('../lib/security');
const { sendOtp } = require('../services/sms');
const { verifyIdToken } = require('../services/firebase');

const r = Router();
const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_AFTER_S = 30;

/** Sends a 6-digit code. Shared with patient/member phone verification. */
async function issueOtp(phone, purpose) {
  const recent = await M.OtpRequest.countDocuments({ phone, createdAt: { $gte: new Date(Date.now() - 15 * 60000) } });
  if (recent >= 5) throw Object.assign(conflict('Too many codes requested. Try again in 15 minutes.', 'OTP_RATE_LIMIT'), { status: 429 });
  const last = await M.OtpRequest.findOne({ phone, purpose }).sort({ createdAt: -1 });
  if (last && Date.now() - last.createdAt < RESEND_AFTER_S * 1000) {
    throw Object.assign(conflict('Wait a few seconds before asking for a new code', 'OTP_TOO_SOON'), { status: 429 });
  }
  const code = randomDigits(6);
  await M.OtpRequest.create({ phone, purpose, codeHash: hmac(`${phone}:${code}`), expiresAt: new Date(Date.now() + OTP_TTL_MS) });
  // Dev sign-in (SMS_PROVIDER=dev, never in production): every number gets its code back.
  const testNumber = env.devOtpPhones.includes(phone) || env.smsProvider === 'dev';
  if (testNumber) console.log(`[sms:test-number] OTP for +91 ${phone}: ${code}`);
  else await sendOtp(phone, code, purpose);
  return { sent: true, maskedPhone: maskPhone(phone), resendInSec: RESEND_AFTER_S, ...(env.exposeDevOtp || testNumber ? { devCode: code } : {}) };
}

/** Checks a code; consumes it on success. */
async function checkOtp(phone, purpose, code) {
  if (!/^\d{6}$/.test(String(code || ''))) throw badRequest('Enter the 6-digit code', 'INVALID_CODE');
  const otp = await M.OtpRequest.findOne({ phone, purpose, consumedAt: null, expiresAt: { $gt: new Date() } }).sort({ createdAt: -1 });
  if (!otp) throw badRequest('The code has expired. Ask for a new one.', 'CODE_EXPIRED');
  if (otp.attempts >= 5) throw badRequest('Too many wrong tries. Ask for a new code.', 'TOO_MANY_ATTEMPTS');
  if (!safeEqual(otp.codeHash, hmac(`${phone}:${code}`))) {
    otp.attempts += 1;
    await otp.save();
    throw badRequest("That code isn't right", 'WRONG_CODE');
  }
  otp.consumedAt = new Date();
  await otp.save();
  return true;
}

async function createSession(user, req) {
  const refreshToken = randomToken();
  const session = await M.AuthSession.create({
    userId: user._id,
    tokenHash: sha256(refreshToken),
    platform: ['android', 'ios', 'web', 'windows'].includes(req.body?.platform) ? req.body.platform : undefined,
    deviceName: typeof req.body?.deviceName === 'string' ? req.body.deviceName.slice(0, 60) : undefined,
    lastUsedAt: new Date(),
    ip: req.ip,
    expiresAt: new Date(Date.now() + ttlMs(env.jwt.refreshTtl)),
  });
  return { accessToken: signAccess(user, session._id), refreshToken, expiresIn: Math.round(ttlMs(env.jwt.accessTtl) / 1000) };
}

/** What the app needs right after sign-in to pick the landing screen. */
async function accountSummary(user) {
  const members = await M.Member.find({ userId: user._id, status: { $in: ['active', 'suspended'] } }).populate('practiceId', 'name');
  const patient = await M.Patient.findOne({ userId: user._id }, 'name');
  const active = members.filter((m) => m.status === 'active');
  const first = active[0];
  // New number: choose "start my clinic", "I'm a patient" or "I have an invite code".
  let landing = 'Auth-Welcome';
  if (first) landing = first.role === 'front_desk' ? 'Staff-Today' : 'Doctor-Dashboard';
  else if (patient) landing = 'Main'; // patient home's screen name in the app
  return {
    user: { id: user._id, name: user.name, phone: user.phone, email: user.email, language: user.language, appLock: user.appLock },
    memberships: members.map((m) => ({
      id: m._id, practiceId: m.practiceId?._id, practiceName: m.practiceId?.name, role: m.role, isOwner: m.isOwner, status: m.status,
    })),
    patientId: patient?._id || null,
    landing,
  };
}

r.post('/otp/request', async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  // With Firebase, the app sends the SMS itself (test numbers still get a dev code here).
  if (env.smsProvider === 'firebase' && !env.devOtpPhones.includes(phone)) {
    return res.json({ sent: false, method: 'firebase', maskedPhone: maskPhone(phone), resendInSec: RESEND_AFTER_S });
  }
  return res.json({ method: 'server', ...(await issueOtp(phone, 'login')) });
});

/** Signs in a verified phone number: finds or creates the account, links a clinic's patient record. */
async function completeLogin(phone, req) {
  let user = await M.User.findOne({ phone });
  if (!user) user = await M.User.create({ phone, phoneVerifiedAt: new Date() });
  if (user.disabledAt) throw forbidden('This account is disabled');
  user.phoneVerifiedAt = user.phoneVerifiedAt || new Date();
  user.lastLoginAt = new Date();
  await user.save();
  // A clinic may already have registered this number as a patient.
  const patient = await M.Patient.findOne({ phone, userId: { $exists: false } });
  if (patient) {
    patient.userId = user._id;
    patient.phoneVerifiedAt = patient.phoneVerifiedAt || new Date();
    await patient.save();
    await M.Conversation.updateMany({ patientId: patient._id, 'participants.userId': { $ne: user._id } }, { $push: { participants: { userId: user._id, role: 'patient' } } });
    if (!user.name) await M.User.updateOne({ _id: user._id }, { name: patient.name });
  }
  return { ...(await createSession(user, req)), ...(await accountSummary(user)) };
}

r.post('/otp/verify', async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  await checkOtp(phone, 'login', req.body.code);
  res.json(await completeLogin(phone, req));
});

// Firebase Phone Auth: the app verified the code with Firebase and sends its ID token.
r.post('/firebase', async (req, res) => {
  if (env.smsProvider !== 'firebase') throw badRequest('Firebase sign-in is not enabled', 'FIREBASE_DISABLED');
  let payload;
  try {
    payload = await verifyIdToken(String(req.body.idToken || ''));
  } catch (err) {
    throw unauthorized(`Couldn't verify your sign-in (${err.message}). Please try again.`, 'FIREBASE_TOKEN_INVALID');
  }
  if (!payload.phone_number) throw badRequest('This sign-in has no phone number', 'NO_PHONE');
  const phone = normalizePhone(payload.phone_number);
  res.json(await completeLogin(phone, req));
});

// Rotation happens in place (same session id) and atomically: of two requests
// with the same token only one wins. The loser gets REFRESH_RACE (the app then
// uses the token the winner saved). A token reused long after it was rotated
// out means it leaked — the whole session is revoked.
const RACE_GRACE_MS = 60 * 1000;
r.post('/refresh', async (req, res) => {
  const token = String(req.body.refreshToken || '');
  if (!token) throw unauthorized('Sign in again', 'REFRESH_INVALID');
  const hash = sha256(token);
  const now = new Date();
  const fresh = randomToken();
  const session = await M.AuthSession.findOneAndUpdate(
    { tokenHash: hash, revokedAt: null, expiresAt: { $gt: now } },
    { $set: { tokenHash: sha256(fresh), prevTokenHash: hash, rotatedAt: now, lastUsedAt: now, ip: req.ip } },
    { new: true },
  );
  if (!session) {
    const old = await M.AuthSession.findOne({ prevTokenHash: hash, revokedAt: null });
    if (old && now - old.rotatedAt < RACE_GRACE_MS) throw unauthorized('Signing in again', 'REFRESH_RACE');
    if (old) {
      old.revokedAt = now;
      old.revokeReason = 'refresh_token_reuse';
      await old.save();
    }
    throw unauthorized('Sign in again', 'REFRESH_INVALID');
  }
  const user = await M.User.findById(session.userId);
  if (!user || user.disabledAt) throw unauthorized('Account not available');
  res.json({ accessToken: signAccess(user, session._id), refreshToken: fresh, expiresIn: Math.round(ttlMs(env.jwt.accessTtl) / 1000) });
});

r.post('/logout', async (req, res) => {
  if (req.body.refreshToken) {
    await M.AuthSession.updateOne({ tokenHash: sha256(String(req.body.refreshToken)) }, { revokedAt: new Date(), revokeReason: 'logout' });
  }
  if (req.body.deviceToken) await M.DeviceToken.deleteOne({ token: req.body.deviceToken });
  res.json({ ok: true });
});

r.get('/session', requireAuth, async (req, res) => res.json(await accountSummary(req.user)));

// Register step 2: preview the invite before entering details.
r.get('/invites/:code', requireAuth, async (req, res) => {
  const invite = await M.Invite.findOne({ code: String(req.params.code).toUpperCase(), usedAt: null, revokedAt: null })
    .populate('practiceId', 'name').populate('locationIds', 'name shortName');
  if (!invite || (invite.expiresAt && invite.expiresAt < new Date())) throw notFound('Invite');
  if (invite.phone && invite.phone !== req.user.phone) throw forbidden('This invite is for a different mobile number', 'INVITE_PHONE_MISMATCH');
  res.json({
    code: invite.code, practiceName: invite.practiceId?.name, role: invite.role,
    locations: invite.locationIds.map((l) => l.shortName || l.name),
    fields: invite.role === 'doctor' ? ['name', 'email', 'language', 'qualifications', 'registrationNo'] : ['name', 'email', 'language'],
  });
});

// Register step 3: join the practice with the invite.
r.post('/register', requireAuth, async (req, res) => {
  const { inviteCode, name, email, language, termsAccepted, qualifications, registrationNo } = req.body;
  if (!termsAccepted) throw badRequest('Please agree to the Terms of Use and Privacy Policy', 'TERMS_REQUIRED');
  if (!name || !String(name).trim()) throw badRequest('Enter your full name', 'NAME_REQUIRED');
  const invite = await M.Invite.findOne({ code: String(inviteCode || '').toUpperCase(), usedAt: null, revokedAt: null });
  if (!invite || (invite.expiresAt && invite.expiresAt < new Date())) throw badRequest("That invite code isn't valid", 'INVITE_INVALID');
  if (invite.phone && invite.phone !== req.user.phone) throw forbidden('This invite is for a different mobile number', 'INVITE_PHONE_MISMATCH');
  if (await M.Member.exists({ practiceId: invite.practiceId, userId: req.user._id })) throw conflict('You are already in this practice', 'ALREADY_MEMBER');

  Object.assign(req.user, { name: String(name).trim(), email: email || undefined, language: language || req.user.language, termsAcceptedAt: new Date(), activePracticeId: invite.practiceId });
  await req.user.save();
  await M.Member.create({
    practiceId: invite.practiceId, userId: req.user._id, role: invite.role, departmentId: invite.departmentId,
    locationIds: invite.locationIds, phone: req.user.phone, invitedBy: invite.createdBy, qualifications, registrationNo,
  });
  if (invite.role === 'doctor' && !(await M.DoctorProfile.exists({ userId: req.user._id }))) {
    await M.DoctorProfile.create({ userId: req.user._id, displayName: req.user.name, degreesSummary: qualifications, registration: registrationNo ? { number: registrationNo } : undefined });
  }
  invite.usedBy = req.user._id;
  invite.usedAt = new Date();
  await invite.save();
  res.status(201).json(await accountSummary(req.user));
});

module.exports = { router: r, issueOtp, checkOtp, accountSummary };

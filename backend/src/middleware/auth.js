// Authentication and access context.
//   requireAuth   → req.user
//   staff         → req.member, req.practiceId, req.perms (practice from X-Practice-Id)
//   patientOnly   → req.patient
const M = require('../models');
const { verifyAccess } = require('../lib/security');
const { unauthorized, forbidden, notFound, isId } = require('../lib/http');

async function requireAuth(req, _res, next) {
  if (req.user) return next(); // already checked by an earlier router
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return next(unauthorized('Sign in to continue'));
  let payload;
  try {
    payload = verifyAccess(token);
  } catch {
    return next(unauthorized('Session expired', 'TOKEN_EXPIRED'));
  }
  const [user, session] = await Promise.all([
    M.User.findById(payload.sub),
    payload.sid ? M.AuthSession.findById(payload.sid, 'revokedAt expiresAt') : null,
  ]);
  if (!user || user.disabledAt) return next(unauthorized('Account not available'));
  // Signed out on this device, or from another device ("sign out other devices").
  if (payload.sid && (!session || session.revokedAt || session.expiresAt < new Date())) {
    return next(unauthorized('Signed out on this device', 'SESSION_REVOKED'));
  }
  req.user = user;
  req.sessionId = payload.sid;
  // When this person last used the app (a doctor's live status); at most one write per 2 minutes.
  const now = Date.now();
  if (!user.lastActiveAt || now - user.lastActiveAt > 2 * 60e3) {
    user.lastActiveAt = new Date(now);
    M.User.updateOne({ _id: user._id }, { lastActiveAt: user.lastActiveAt }).catch(() => {});
  }
  return next();
}

/** Loads the active practice membership. Optionally requires roles or a permission. */
const staff = ({ roles, perm } = {}) =>
  async function staffContext(req, _res, next) {
    let { member } = req;
    if (!member) {
      const wanted = req.headers['x-practice-id'] || req.user.activePracticeId;
      const q = { userId: req.user._id, status: 'active' };
      if (wanted && isId(String(wanted))) q.practiceId = wanted;
      member = await M.Member.findOne(q).sort({ isOwner: -1, joinedAt: 1 });
      if (!member && wanted && !req.headers['x-practice-id']) {
        member = await M.Member.findOne({ userId: req.user._id, status: 'active' }).sort({ joinedAt: 1 });
      }
      if (!member) return next(forbidden('You are not a member of this practice', 'NOT_A_MEMBER'));
    }
    if (roles && !roles.includes(member.role)) return next(forbidden(`Only ${roles.join(' or ')} can do this`, 'ROLE_REQUIRED'));
    const perms = M.ROLE_PERMISSIONS[member.role] || { viewPatients: true };
    if (perm && !perms[perm]) return next(forbidden("Your role doesn't allow this", 'PERMISSION_REQUIRED'));
    req.member = member;
    req.practiceId = member.practiceId;
    req.perms = perms;
    return next();
  };

/** After staff(): requires one of the role permissions (models/practice.js ROLE_PERMISSIONS). */
const need = (...perms) => (req, _res, next) => {
  if (req.member?.isOwner && !perms.includes('prescribe')) return next(); // owners run their practice
  if (perms.some((p) => req.perms?.[p])) return next();
  return next(forbidden("Your role doesn't allow this", 'PERMISSION_REQUIRED'));
};

/** Practice owner (or practice manager) only. */
const ownerOnly = (req, _res, next) => {
  if (req.member?.isOwner || req.member?.role === 'practice_manager') return next();
  return next(forbidden('Only the practice owner can do this', 'OWNER_REQUIRED'));
};

async function patientOnly(req, _res, next) {
  const patient = await M.Patient.findOne({ userId: req.user._id });
  if (!patient) return next(notFound('Patient profile'));
  req.patient = patient;
  return next();
}

/** The patient must be linked to the caller's practice. Returns the patient. */
async function patientInPractice(req, patientId) {
  if (!isId(patientId)) throw notFound('Patient');
  const link = await M.PatientEnrolment.exists({ patientId, practiceId: req.practiceId, status: 'linked' });
  if (!link) throw notFound('Patient');
  const patient = await M.Patient.findById(patientId);
  if (!patient) throw notFound('Patient');
  return patient;
}

/** Throws unless the doc belongs to the caller's practice. */
const ownPractice = (req, doc, what = 'Item') => {
  if (!doc || String(doc.practiceId) !== String(req.practiceId)) throw notFound(what);
  return doc;
};

module.exports = {
  need, requireAuth, staff, ownerOnly, patientOnly, patientInPractice, ownPractice };

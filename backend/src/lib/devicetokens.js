// Push tokens of phones that are still signed in.
//
// Each token remembers the sign-in session that registered it (me.js
// POST /devices). Signing out revokes that session, so its phone gets nothing
// more — even when the sign-out request never named the token (phone offline,
// app didn't know its token yet), the session expired, or it was signed out
// from another device. Dead rows are removed as they are found.
const { Types } = require('mongoose');
const M = require('../models');

/**
 * DeviceToken rows matching `filter` whose session is still active.
 * Rows from before sessions were recorded (no sessionId) count only while
 * their user has some active session; the app re-registers them on its next start.
 */
async function liveDevices(filter, projection) {
  const rows = await M.DeviceToken.find(filter, projection ? `${projection} userId sessionId lastSeenAt` : undefined).lean();
  if (!rows.length) return rows;
  const now = new Date();
  const sids = [...new Set(rows.filter((r) => r.sessionId).map((r) => String(r.sessionId)))];
  const legacyUsers = [...new Set(rows.filter((r) => !r.sessionId).map((r) => String(r.userId)))];
  const [sessions, usersWithSession, signOuts] = await Promise.all([
    sids.length ? M.AuthSession.find({ _id: { $in: sids }, revokedAt: null, expiresAt: { $gt: now } }, '_id').lean() : [],
    legacyUsers.length ? M.AuthSession.distinct('userId', { userId: { $in: legacyUsers }, revokedAt: null, expiresAt: { $gt: now } }) : [],
    // Each old-style row's user: when they last signed out.
    legacyUsers.length
      ? M.AuthSession.aggregate([{ $match: { userId: { $in: legacyUsers.map((id) => new Types.ObjectId(id)) }, revokedAt: { $ne: null } } }, { $group: { _id: '$userId', at: { $max: '$revokedAt' } } }])
      : [],
  ]);
  const liveSid = new Set(sessions.map((s) => String(s._id)));
  const liveUser = new Set(usersWithSession.map(String));
  const lastSignOut = new Map(signOuts.map((s) => [String(s._id), s.at]));
  const keep = [];
  const dead = [];
  for (const r of rows) {
    // Old-style row: dead once its user signed out after the phone last registered it.
    const out = lastSignOut.get(String(r.userId));
    const ok = r.sessionId ? liveSid.has(String(r.sessionId)) : liveUser.has(String(r.userId)) && !(out && (!r.lastSeenAt || out > r.lastSeenAt));
    (ok ? keep : dead).push(r);
  }
  if (dead.length) await M.DeviceToken.deleteMany({ _id: { $in: dead.map((r) => r._id) } }).catch(() => {});
  return keep;
}

/** Just the tokens (for sendPush). */
async function liveTokens(filter) {
  return [...new Set((await liveDevices(filter, 'token')).map((r) => r.token))];
}

/** A session ended (sign-out, "sign out other devices", expiry): forget its phones. */
async function forgetSession(sessionId) {
  if (sessionId) await M.DeviceToken.deleteMany({ sessionId });
}

module.exports = { liveDevices, liveTokens, forgetSession };

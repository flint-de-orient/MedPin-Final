// A doctor's status for patients, worked out live (not a stored setting):
//
// - in_clinic: a consultation is open, or one of their clinic sessions is on
//   right now (weekly schedule, minus leave and clinic closures).
// - available: not in a session, inside their chat reply hours, and active
//   in the app in the last 15 minutes.
// - away: anything else; note says when they are next in ("Back today at 5:00 PM").
//
// The doctor can choose "Away" (Profile → Chat): then they are never shown as
// available (being in a clinic session still shows).
//
// avgReplyMinutes: the median time the doctor took to answer patients' chat
// messages over the last 30 days; their own estimate until there are 3 replies.
const M = require('../models');
const T = require('../lib/time');

const ACTIVE_MS = 15 * 60e3;
const REPLY_CACHE_MS = 30 * 60e3;
const replyCache = new Map(); // doctorId → { at, minutes }

const hhmm = (s) => {
  const [h, m] = String(s || '').split(':').map(Number);
  return Number.isFinite(h) ? h * 60 + (m || 0) : null;
};

/** Sessions of one doctor on one day: [{ startMin, endMin, locationName }]. */
async function sessionsOn(doctorId, day, dls) {
  const d = T.dayStart(day);
  const end = T.addDays(d, 1);
  const leave = await M.DoctorLeave.find({ doctorId, cancelledAt: null, startDate: { $lt: end }, endDate: { $gte: d } }, 'locationId');
  const out = [];
  for (const dl of dls) {
    const loc = dl.locationId;
    if (!loc || loc.status !== 'active') continue;
    if (leave.some((l) => !l.locationId || String(l.locationId) === String(loc._id))) continue;
    if (await M.LocationClosure.exists({ locationId: loc._id, startDate: { $lt: end }, endDate: { $gte: d }, allDay: { $ne: false } })) continue;
    const hours = (loc.weeklyHours || []).find((h) => h.weekday === T.weekday(d));
    if (hours && hours.isOpen === false) continue;
    const opens = hours?.opensAt ?? 0;
    const closes = hours?.closesAt ?? 24 * 60;
    const week = (dl.schedule?.week || []).find((w) => w.weekday === T.weekday(d));
    for (const s of week?.sessions || []) {
      const startMin = Math.max(s.startMin, opens);
      const endMin = Math.min(s.endMin, closes);
      if (endMin > startMin) out.push({ startMin, endMin, locationName: loc.shortName || loc.name });
    }
  }
  return out.sort((a, b) => a.startMin - b.startMin);
}

/** "today at 5:00 PM", "tomorrow at 9:00 AM", "Mon at 9:00 AM". */
function whenLabel(day, minute, now) {
  const days = Math.round((T.dayStart(day) - T.dayStart(now)) / T.DAY_MS);
  const at = T.fmtTime(minute);
  if (days === 0) return `today at ${at}`;
  if (days === 1) return `tomorrow at ${at}`;
  const wd = T.weekday(day);
  return `${wd[0].toUpperCase()}${wd.slice(1)} at ${at}`;
}

/** Median reply time (minutes) to patients' chat messages, last 30 days. */
async function replyMinutes(doctorId, now = new Date()) {
  const hit = replyCache.get(String(doctorId));
  if (hit && Date.now() - hit.at < REPLY_CACHE_MS && Math.abs(now - hit.now) < REPLY_CACHE_MS) return hit.minutes;
  const since = new Date(now - 30 * T.DAY_MS);
  // Chats the doctor has answered in.
  const convIds = await M.Message.distinct('conversationId', { senderId: doctorId, createdAt: { $gte: since } });
  const msgs = convIds.length
    ? await M.Message.find({ conversationId: { $in: convIds }, createdAt: { $gte: since }, senderType: { $in: ['patient', 'doctor'] }, 'meta.auto': { $ne: true } },'conversationId senderType senderId createdAt')
      .sort({ createdAt: 1 }).limit(5000)
    : [];
  const waiting = new Map(); // conversation → when the patient's unanswered message came
  const delays = [];
  for (const m of msgs) {
    const c = String(m.conversationId);
    if (m.senderType === 'patient') {
      if (!waiting.has(c)) waiting.set(c, m.createdAt);
    } else if (String(m.senderId) === String(doctorId) && waiting.has(c)) {
      const mins = (m.createdAt - waiting.get(c)) / 60e3;
      if (mins >= 0 && mins <= 24 * 60) delays.push(mins);
      waiting.delete(c);
    }
  }
  let minutes = null;
  if (delays.length >= 3) {
    delays.sort((a, b) => a - b);
    const mid = delays[Math.floor(delays.length / 2)];
    minutes = Math.max(1, Math.round(mid < 60 ? mid : Math.round(mid / 30) * 30));
  }
  replyCache.set(String(doctorId), { at: Date.now(), now, minutes });
  return minutes;
}

/**
 * { presence, presenceNote, avgReplyMinutes } for a doctor (a DoctorProfile
 * or its userId) right now.
 */
async function presenceOf(profileOrId, now = new Date()) {
  const prof = profileOrId?.userId ? profileOrId : await M.DoctorProfile.findOne({ userId: profileOrId });
  if (!prof) return { presence: 'away', presenceNote: null, avgReplyMinutes: null };
  const doctorId = prof.userId;
  const [dls, user, openConsult, reply] = await Promise.all([
    M.DoctorLocation.find({ doctorId, status: 'active' }).populate('locationId', 'name shortName status weeklyHours'),
    M.User.findById(doctorId, 'lastActiveAt'),
    M.Consultation.exists({ doctorId, status: 'draft', startedAt: { $gte: new Date(now - 3 * 3600e3) } }),
    replyMinutes(doctorId, now),
  ]);
  const replyEst = reply ?? prof.avgReplyMinutes ?? null;
  const minute = T.minuteOfDay(now);
  const today = await sessionsOn(doctorId, now, dls);
  const current = today.find((s) => s.startMin <= minute && minute < s.endMin);
  if (openConsult || current) {
    const until = current ? ` until ${T.fmtTime(current.endMin)}` : '';
    return {
      presence: 'in_clinic',
      presenceNote: current ? `${current.locationName}${until}` : 'with a patient',
      avgReplyMinutes: replyEst,
    };
  }
  const rh = prof.chatSettings?.replyHours || {};
  const from = hhmm(rh.from) ?? 9 * 60;
  const to = hhmm(rh.to) ?? 20 * 60;
  const inReplyHours = minute >= from && minute < to;
  const active = user?.lastActiveAt && now - user.lastActiveAt < ACTIVE_MS;
  const chose = prof.presence === 'away' ? 'away' : 'auto';
  if (chose === 'auto' && inReplyHours && active && prof.chatSettings?.whoCanMessage !== 'nobody') {
    const r = replyEst;
    return { presence: 'available', presenceNote: r ? `replies in ~${r < 60 ? `${r} min` : `${Math.round(r / 60)} h`}` : null, avgReplyMinutes: r };
  }
  // Next time they're in: a later session today, else the next 7 days.
  let next = today.find((s) => s.startMin > minute) ? { day: now, minute: today.find((s) => s.startMin > minute).startMin } : null;
  for (let i = 1; i <= 7 && !next; i += 1) {
    const day = T.addDays(T.dayStart(now), i);
    const s = (await sessionsOn(doctorId, day, dls))[0];
    if (s) next = { day, minute: s.startMin };
  }
  // Inside reply hours but not active now: replies later today.
  const note = next ? `Back ${whenLabel(next.day, next.minute, now)}` : inReplyHours ? 'Replies later today' : null;
  return { presence: 'away', presenceNote: note, avgReplyMinutes: replyEst };
}

module.exports = { presenceOf, replyMinutes, sessionsOn };

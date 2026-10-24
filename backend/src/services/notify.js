// Creates in-app notifications and fans out to push / WhatsApp.
const M = require('../models');
const T = require('../lib/time');
const { sendPush, sendWhatsApp } = require('./push');
const { sendEmail } = require('./email');
const { translateNotice, LANGS } = require('../lib/notify_i18n');

/**
 * @param {ObjectId[]} userIds
 * @param {{type, title, body?, screen?, params?, practiceId?, whatsapp?: boolean, push?: boolean}} n
 *   push: false — in the app only, no phone notification (e.g. a patient sharing a
 *   report: a doctor with thousands of patients sees it marked on the patient and
 *   in the morning summary, not as a buzz each time).
 */
/** A user id from an id or a populated user. */
const idOf = (x) => String(x?._id || x);

async function notify(userIds, n) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(idOf))];
  if (!ids.length) return [];
  // About a family member on the holder's phone (a child's visit): the notice says who it is
  // for, and opening it switches the app to that profile.
  if (n.forPatientId) {
    const fp = await M.Patient.findById(n.forPatientId, 'name primary').lean();
    const { forPatientId, ...rest } = n;
    n = fp && fp.primary === false ? { ...rest, params: { ...(rest.params || {}), forPatientId: String(fp._id), forName: fp.name } } : rest;
  }
  const channels = ['in_app', ...(n.push === false ? [] : ['push']), ...(n.whatsapp ? ['whatsapp'] : [])];
  // Each person reads it in their app language (Bengali / Hindi: lib/notify_i18n.js);
  // type, screen and params stay the same for everyone.
  const langOf = new Map((await M.User.find({ _id: { $in: ids }, language: { $in: LANGS } }, 'language').lean()).map((u) => [String(u._id), u.language]));
  const texts = new Map();
  const textFor = (id) => {
    const lang = langOf.get(id) || 'en';
    if (!texts.has(lang)) texts.set(lang, lang === 'en' ? { title: n.title, body: n.body } : translateNotice(n, lang));
    return texts.get(lang);
  };
  const docs = await M.Notification.insertMany(
    ids.map((userId) => ({
      userId,
      practiceId: n.practiceId,
      type: n.type,
      ...textFor(userId),
      screen: n.screen,
      params: n.params,
      channels,
      sentAt: new Date(),
    })),
  );
  // Delivery failures never fail the request that triggered them.
  (async () => {
    const profiles = await M.DoctorProfile.find({ userId: { $in: ids } }, 'userId notificationPrefs chatSettings');
    const prefs = new Map(profiles.map((d) => [String(d.userId), d.notificationPrefs]));
    // "Urgent chats ring through even in quiet hours" (Chat settings) — on unless switched off.
    const urgentThrough = new Map(profiles.map((d) => [String(d.userId), d.chatSettings?.urgentAlerts !== false]));
    const isUrgent = /emergency|urgent/.test(n.type);
    const urgentFor = (id) => isUrgent && urgentThrough.get(id) !== false;
    const typeOn = (p) => {
      const t = p?.types || {};
      // Emergencies and urgent alerts always come through (Chat settings → urgent alerts).
      if (/emergency|urgent/.test(n.type)) return true;
      if (/appointment|request|visit|queue|doctor_leave|clinic_closed|reschedul|fee_|refund/.test(n.type)) return t.appointments !== false;
      if (/message/.test(n.type)) return t.messages !== false;
      if (/lab|record|prescription|alert_watch/.test(n.type)) return t.labResults !== false;
      if (/follow_up|morning_summary/.test(n.type)) return t.followUps !== false;
      return true;
    };
    const quiet = (p, id) => {
      if (!p?.quietHours?.enabled || urgentFor(id)) return false;
      const now = T.minuteOfDay(new Date());
      const from = T.hhmmToMin(p.quietHours.from || '22:00');
      const to = T.hhmmToMin(p.quietHours.to || '07:00');
      return from <= to ? now >= from && now < to : now >= from || now < to;
    };
    const pushIds = ids.filter((id) => {
      const p = prefs.get(id);
      return !p || urgentFor(id) || (p.push !== false && typeOn(p) && !quiet(p, id));
    });
    // Only phones still signed in (a signed-out phone gets nothing).
    const devices = n.push === false ? [] : await require('../lib/devicetokens').liveDevices({ userId: { $in: pushIds } }, 'userId token');
    const data = { screen: n.screen || '', type: n.type, notificationId: '', ...(n.practiceId ? { practiceId: String(n.practiceId) } : {}), ...Object.fromEntries(Object.entries(n.params || {}).map(([k, v]) => [k, String(v)])) };
    // One push per language, each phone once (in its owner's language).
    const byLang = new Map();
    const seen = new Set();
    for (const d of devices) {
      if (!d.token || seen.has(d.token)) continue;
      seen.add(d.token);
      const lang = langOf.get(String(d.userId)) || 'en';
      if (!byLang.has(lang)) byLang.set(lang, { id: String(d.userId), tokens: [] });
      byLang.get(lang).tokens.push(d.token);
    }
    for (const { id, tokens } of byLang.values()) await sendPush(tokens, { ...textFor(id), data, urgent: isUrgent });
    // Everyone not buzzed (in-app only, push or this type switched off, quiet hours): a
    // silent "notifications changed", so an open list and the bell's dot update at once.
    const pushed = new Set(n.push === false ? [] : pushIds);
    const quietIds = ids.filter((id) => !pushed.has(id));
    if (quietIds.length) await signal(quietIds, { type: 'notifications_changed', ...(n.practiceId ? { practiceId: String(n.practiceId) } : {}) });
    if (n.whatsapp) {
      const waIds = ids.filter((id) => {
        const p = prefs.get(id);
        return !p || (p.whatsapp !== false && typeOn(p) && !quiet(p, id));
      });
      const users = await M.User.find({ _id: { $in: waIds } }, 'phone');
      // WhatsApp stays in English: it goes out as the approved (English) Meta templates.
      await Promise.allSettled(users.map((u) => sendWhatsApp(u.phone, `${n.title}${n.body ? ` — ${n.body}` : ''}`, { template: n.type, params: n.waParams })));
    }
    // Email copy for staff who switched it on (Profile → Notifications → Email).
    // In-app-only notices (push: false, e.g. a shared report) don't go by email either.
    const emailIds = n.push === false ? [] : ids.filter((id) => prefs.get(id)?.email === true && typeOn(prefs.get(id)) && !quiet(prefs.get(id), id));
    if (emailIds.length) {
      const users = await M.User.find({ _id: { $in: emailIds }, email: { $exists: true, $ne: '' } }, 'email');
      await Promise.allSettled(users.map((u) => {
        const t = textFor(String(u._id));
        return sendEmail({ to: u.email, subject: `MedPin: ${t.title}`, text: `${t.title}${t.body ? `\n\n${t.body}` : ''}` });
      }));
    }
  })().catch((err) => console.warn('[notify]', err.message));
  return docs;
}

/** User ids of active members of a practice, optionally filtered by role / location. */
async function practiceStaff(practiceId, { roles, locationId } = {}) {
  const q = { practiceId, status: 'active' };
  if (roles) q.role = { $in: roles };
  const members = await M.Member.find(q, 'userId locationIds allLocations');
  return members
    .filter((m) => !locationId || m.allLocations || m.locationIds.some((l) => String(l) === String(locationId)))
    .map((m) => m.userId);
}

/**
 * Who should hear about a patient's clinical event in a practice: the doctor
 * named on it, plus the patient's care-team doctors there; if the patient has
 * none yet, every doctor of the practice. Never the front desk.
 */
async function clinicians(practiceId, patientId, { doctorId, roles = ['doctor'] } = {}) {
  const members = await M.Member.find({ practiceId, status: 'active', role: { $in: roles } }, 'userId');
  const memberIds = new Set(members.map((m) => String(m.userId)));
  const team = await M.CareTeamAccess.find({ patientId, userId: { $in: [...memberIds] }, accessLevel: { $ne: 'not_shared' } }, 'userId');
  const ids = new Set(team.map((t) => String(t.userId)));
  if (doctorId && memberIds.has(String(doctorId))) ids.add(String(doctorId));
  return ids.size ? [...ids] : [...memberIds];
}

/**
 * Silent "something changed" to these people's phones (no notification shown):
 * an open chat refreshes at once instead of waiting for its next check.
 */
async function signal(userIds, data) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(idOf))];
  if (!ids.length) return;
  try {
    const tokens = await require('../lib/devicetokens').liveTokens({ userId: { $in: ids } });
    await sendPush(tokens, { data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) });
  } catch (err) {
    console.warn('[signal]', err.message);
  }
}

/**
 * Who does the front desk's work here: the front desk / practice manager at
 * that location; in a clinic without one, the doctor it's about (or every
 * doctor of the clinic) — they handle requests, check-ins and fees themselves.
 */
// Who does the front desk's work: receptionists, practice managers and doctors' assistants.
const DESK_ROLES = ['front_desk', 'practice_manager', 'doctor_assistant'];

async function deskOrDoctors(practiceId, { locationId, doctorId } = {}) {
  const desk = await deskFor(practiceId, { locationId, doctorId });
  if (desk.length) return desk;
  if (doctorId) return [doctorId];
  return practiceStaff(practiceId, { roles: ['doctor'], locationId });
}

/** Does this clinic (location) have someone at the front desk? */
async function hasDesk(practiceId, locationId) {
  return (await deskFor(practiceId, { locationId })).length > 0;
}

/** The front desk / managers at that location, and the assistants of [doctorId] there. */
async function deskFor(practiceId, { locationId, doctorId } = {}) {
  const members = await M.Member.find({ practiceId, status: 'active', role: { $in: DESK_ROLES } }, 'userId role locationIds allLocations assistsDoctorIds');
  return members
    .filter((m) => !locationId || m.allLocations || (m.locationIds || []).some((l) => String(l) === String(locationId)))
    .filter((m) => m.role !== 'doctor_assistant' || !doctorId || !(m.assistsDoctorIds || []).length || m.assistsDoctorIds.some((d) => String(d) === String(doctorId)))
    .map((m) => m.userId);
}

/**
 * Doctors' assistants who work for any of [doctorIds] here (an assistant with no
 * doctors chosen assists everyone). They see clinical alerts (alerts permission).
 */
async function assistantsOf(practiceId, doctorIds = []) {
  const want = new Set(doctorIds.map(idOf));
  const members = await M.Member.find({ practiceId, status: 'active', role: 'doctor_assistant' }, 'userId assistsDoctorIds');
  return members
    .filter((m) => !(m.assistsDoctorIds || []).length || !want.size || m.assistsDoctorIds.some((d) => want.has(String(d))))
    .map((m) => m.userId);
}

/**
 * Where a patient is looked after in a practice, for "who at the desk":
 * the next visit's (else the latest visit's) location and doctor, else the
 * branch they registered at; the doctor falls back to their main doctor here.
 */
async function patientPlace(practiceId, patientId) {
  const now = new Date();
  const next = await M.Appointment.findOne({ practiceId, patientId, startAt: { $gte: now }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } }, 'locationId doctorId').sort({ startAt: 1 });
  const last = next || (await M.Appointment.findOne({ practiceId, patientId, locationId: { $ne: null } }, 'locationId doctorId').sort({ startAt: -1 }));
  let locationId = last?.locationId;
  if (!locationId) locationId = (await M.PatientEnrolment.findOne({ practiceId, patientId }, 'homeLocationId'))?.homeLocationId;
  let doctorId = last?.doctorId;
  if (!doctorId) doctorId = (await M.CareTeamAccess.findOne({ practiceId, patientId, isPrimary: true }, 'userId'))?.userId;
  return { locationId: locationId || undefined, doctorId: doctorId || undefined };
}

module.exports = { notify, practiceStaff, clinicians, signal, deskOrDoctors, deskFor, hasDesk, assistantsOf, patientPlace, DESK_ROLES };

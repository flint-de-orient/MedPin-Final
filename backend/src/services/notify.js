// Creates in-app notifications and fans out to push / WhatsApp.
const M = require('../models');
const T = require('../lib/time');
const { sendPush, sendWhatsApp } = require('./push');
const { sendEmail } = require('./email');

/**
 * @param {ObjectId[]} userIds
 * @param {{type, title, body?, screen?, params?, practiceId?, whatsapp?: boolean, push?: boolean}} n
 *   push: false — in the app only, no phone notification (e.g. a patient sharing a
 *   report: a doctor with thousands of patients sees it marked on the patient and
 *   in the morning summary, not as a buzz each time).
 */
async function notify(userIds, n) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(String))];
  if (!ids.length) return [];
  const channels = ['in_app', ...(n.push === false ? [] : ['push']), ...(n.whatsapp ? ['whatsapp'] : [])];
  const docs = await M.Notification.insertMany(
    ids.map((userId) => ({
      userId,
      practiceId: n.practiceId,
      type: n.type,
      title: n.title,
      body: n.body,
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
      if (/appointment|request|visit/.test(n.type)) return t.appointments !== false;
      if (/message/.test(n.type)) return t.messages !== false;
      if (/lab|record|prescription/.test(n.type)) return t.labResults !== false;
      if (/follow_up/.test(n.type)) return t.followUps !== false;
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
    const tokens = n.push === false ? [] : await M.DeviceToken.find({ userId: { $in: pushIds } }).distinct('token');
    const data = { screen: n.screen || '', type: n.type, notificationId: '', ...Object.fromEntries(Object.entries(n.params || {}).map(([k, v]) => [k, String(v)])) };
    if (tokens.length) await sendPush(tokens, { title: n.title, body: n.body, data, urgent: isUrgent });
    if (n.whatsapp) {
      const waIds = ids.filter((id) => {
        const p = prefs.get(id);
        return !p || (p.whatsapp !== false && typeOn(p) && !quiet(p, id));
      });
      const users = await M.User.find({ _id: { $in: waIds } }, 'phone');
      await Promise.allSettled(users.map((u) => sendWhatsApp(u.phone, `${n.title}${n.body ? ` — ${n.body}` : ''}`, { template: n.type, params: n.waParams })));
    }
    // Email copy for staff who switched it on (Profile → Notifications → Email).
    const emailIds = ids.filter((id) => prefs.get(id)?.email === true && typeOn(prefs.get(id)) && !quiet(prefs.get(id), id));
    if (emailIds.length) {
      const users = await M.User.find({ _id: { $in: emailIds }, email: { $exists: true, $ne: '' } }, 'email');
      await Promise.allSettled(users.map((u) => sendEmail({ to: u.email, subject: `MedPin: ${n.title}`, text: `${n.title}${n.body ? `\n\n${n.body}` : ''}` })));
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
  const ids = [...new Set((userIds || []).filter(Boolean).map(String))];
  if (!ids.length) return;
  try {
    const tokens = await M.DeviceToken.find({ userId: { $in: ids } }).distinct('token');
    await sendPush(tokens, { data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) });
  } catch (err) {
    console.warn('[signal]', err.message);
  }
}

module.exports = { notify, practiceStaff, clinicians, signal };

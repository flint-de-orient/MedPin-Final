// Creates in-app notifications and fans out to push / WhatsApp.
const M = require('../models');
const T = require('../lib/time');
const { sendPush, sendWhatsApp } = require('./push');

/**
 * @param {ObjectId[]} userIds
 * @param {{type, title, body?, screen?, params?, practiceId?, whatsapp?: boolean}} n
 */
async function notify(userIds, n) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(String))];
  if (!ids.length) return [];
  const channels = ['in_app', 'push', ...(n.whatsapp ? ['whatsapp'] : [])];
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
    const prefs = new Map((await M.DoctorProfile.find({ userId: { $in: ids } }, 'userId notificationPrefs')).map((d) => [String(d.userId), d.notificationPrefs]));
    const urgent = /emergency|urgent/.test(n.type);
    const typeOn = (p) => {
      const t = p?.types || {};
      if (/appointment|request|visit/.test(n.type)) return t.appointments !== false;
      if (/message/.test(n.type)) return t.messages !== false;
      if (/lab|record|prescription/.test(n.type)) return t.labResults !== false;
      if (/follow_up/.test(n.type)) return t.followUps !== false;
      return true;
    };
    const quiet = (p) => {
      if (!p?.quietHours?.enabled || urgent) return false;
      const now = T.minuteOfDay(new Date());
      const from = T.hhmmToMin(p.quietHours.from || '22:00');
      const to = T.hhmmToMin(p.quietHours.to || '07:00');
      return from <= to ? now >= from && now < to : now >= from || now < to;
    };
    const pushIds = ids.filter((id) => {
      const p = prefs.get(id);
      return !p || urgent || (p.push !== false && typeOn(p) && !quiet(p));
    });
    const tokens = await M.DeviceToken.find({ userId: { $in: pushIds } }).distinct('token');
    await sendPush(tokens, { title: n.title, body: n.body, data: { screen: n.screen || '', type: n.type } });
    if (n.whatsapp) {
      const waIds = ids.filter((id) => {
        const p = prefs.get(id);
        return !p || (p.whatsapp !== false && typeOn(p) && !quiet(p));
      });
      const users = await M.User.find({ _id: { $in: waIds } }, 'phone');
      await Promise.allSettled(users.map((u) => sendWhatsApp(u.phone, `${n.title}${n.body ? ` — ${n.body}` : ''}`)));
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

module.exports = { notify, practiceStaff };

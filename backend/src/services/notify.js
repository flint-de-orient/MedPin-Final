// Creates in-app notifications and fans out to push / WhatsApp.
const M = require('../models');
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
    const tokens = await M.DeviceToken.find({ userId: { $in: ids } }).distinct('token');
    await sendPush(tokens, { title: n.title, body: n.body, data: { screen: n.screen || '', type: n.type } });
    if (n.whatsapp) {
      const users = await M.User.find({ _id: { $in: ids } }, 'phone');
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

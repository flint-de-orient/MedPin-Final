// When a patient's medicines or visits change (a doctor issues a prescription,
// a visit is booked or moved), their phone is told at once with a silent push
// so it re-schedules its own alarms (lib/data/med_alarms.dart). Several changes
// in a row send one.
const pending = new Map();

function remindersChanged(patientId) {
  const key = String(patientId || '');
  if (!key || pending.has(key)) return;
  pending.set(key, setTimeout(async () => {
    pending.delete(key);
    try {
      const M = require('../models');
      const p = await M.Patient.findById(key, 'userId');
      if (p?.userId) await require('./notify').signal([p.userId], { type: 'reminders_changed' });
    } catch (err) {
      console.warn('[reminders]', err.message);
    }
  }, 3000).unref?.() || true);
}

/**
 * Does one of these phones already ring a reminder at [at] for something last
 * changed at [changedAt]? It does when it scheduled its reminders after that
 * change and far enough ahead.
 */
function phoneCovers(devices, changedAt, at) {
  return (devices || []).some((d) => d.localAlarms && d.remindersSyncedAt && d.remindersUntil
    && d.remindersSyncedAt >= (changedAt || 0) && d.remindersUntil >= at);
}

module.exports = { remindersChanged, phoneCovers };

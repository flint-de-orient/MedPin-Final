// Background jobs: reminders and summaries. Runs every minute inside the API
// process (started by server.js; JOBS=off disables it). Every reminder is
// recorded in ReminderLog first, so it is sent once even across restarts or
// several API processes.
//
//   dose reminders      at each dose time, to patients with medicine reminders on
//   visit reminders     24 h and 2 h before a booked visit
//   follow-up reminders N days before the due date (doctor's Follow-up reminder setting)
//   low stock           a medicine with ≤ 3 days left, once a day
//   daily log           at the patient's daily-log reminder time if nothing was logged
//   daily summary       20:00 IST to doctors with "Daily summary" on
const M = require('../models');
const T = require('../lib/time');
const { notify } = require('./notify');
const { ensureDoses } = require('./care');
const { dosesPerDay, doseText } = require('./clinical');

const SLOT_LABEL = { morning: 'Morning', afternoon: 'Afternoon', night: 'Night' };
const FOOD = { before_food: 'before food', after_food: 'after food', with_food: 'with food', empty_stomach: 'on an empty stomach' };

/** Runs [fn] only the first time [key] is seen. */
async function once(key, fn) {
  try {
    await M.ReminderLog.create({ key });
  } catch (err) {
    if (err.code === 11000) return false;
    throw err;
  }
  await fn();
  return true;
}

const visitText = async (a) => {
  const [doctor, loc] = await Promise.all([M.User.findById(a.doctorId, 'name'), M.Location.findById(a.locationId, 'name shortName')]);
  return `${T.fmtTime(T.minuteOfDay(a.startAt))} with ${doctor?.name || 'your doctor'}${loc ? ` · ${loc.shortName || loc.name}` : ''}${a.tokenNo ? ` · token ${a.tokenNo}` : ''}`;
};

// ── Each job ─────────────────────────────────────────────

/** Makes sure today's (and tomorrow's) dose rows exist for every patient taking medicines. */
async function prepareDoses(now) {
  const day = T.dayKey(now);
  await once(`doses-ready:${day}`, async () => {
    const ids = await M.MedicationCourse.distinct('patientId', { status: 'active', trackingEnabled: true });
    const patients = await M.Patient.find({ _id: { $in: ids } });
    for (const p of patients) await ensureDoses(p, now, T.addDays(now, 1)).catch(() => {});
  });
}

async function doseReminders(now, since) {
  const doses = await M.DoseLog.find({ status: 'due', scheduledAt: { $gt: since, $lte: now } }).limit(2000);
  if (!doses.length) return;
  const patients = new Map((await M.Patient.find({ _id: { $in: doses.map((d) => d.patientId) } }, 'userId settings')).map((p) => [String(p._id), p]));
  const courses = new Map((await M.MedicationCourse.find({ _id: { $in: doses.map((d) => d.courseId) } }, 'name strength foodRelation dose')).map((c) => [String(c._id), c]));
  for (const d of doses) {
    const p = patients.get(String(d.patientId));
    const c = courses.get(String(d.courseId));
    if (!p?.userId || p.settings?.medReminders === false || !c) continue;
    await once(`dose:${d._id}`, () =>
      notify([p.userId], {
        type: 'dose_reminder', title: `Time for ${c.name}${c.strength ? ` ${c.strength}` : ''}`,
        body: [SLOT_LABEL[d.slot] && `${SLOT_LABEL[d.slot]} dose`, FOOD[c.foodRelation]].filter(Boolean).join(' · '),
        screen: 'Patient-Medicines', params: { doseId: d._id },
      }),
    );
  }
}

async function visitReminders(now) {
  for (const [hours, label] of [[24, 'tomorrow'], [2, 'in 2 hours']]) {
    const from = new Date(now.getTime() + (hours * 60 - 10) * 60000);
    const to = new Date(now.getTime() + hours * 3600e3);
    const appts = await M.Appointment.find({ status: { $in: ['booked', 'confirmed'] }, startAt: { $gt: from, $lte: to } }).limit(1000);
    for (const a of appts) {
      const p = await M.Patient.findById(a.patientId, 'userId settings');
      if (!p?.userId || p.settings?.visitReminders === false) continue;
      await once(`visit${hours}:${a._id}`, async () =>
        notify([p.userId], {
          type: 'visit_reminder', practiceId: a.practiceId, title: `Your visit is ${label}`, body: await visitText(a),
          screen: 'Patient-DoctorDetail', params: { doctorId: a.doctorId, appointmentId: a._id }, whatsapp: hours === 24,
        }),
      );
    }
  }
}

async function followUpReminders(now) {
  if (T.minuteOfDay(now) < 10 * 60) return; // from 10:00 IST
  const today = T.dayStart(now);
  const due = await M.FollowUp.find({ status: 'not_booked', dueDate: { $gte: today, $lt: T.addDays(today, 31) } }).limit(2000);
  for (const f of due) {
    const prof = await M.DoctorProfile.findOne({ userId: f.doctorId }, 'followUpReminder displayName');
    const days = prof?.followUpReminder?.daysBefore ?? 3;
    const channels = prof?.followUpReminder?.channels || ['whatsapp', 'app'];
    const left = Math.round((T.dayStart(f.dueDate) - today) / 864e5);
    if (left !== days) continue;
    const p = await M.Patient.findById(f.patientId, 'userId phone');
    if (!p) continue;
    await once(`followup:${f._id}:${days}`, async () => {
      if (p.userId && channels.includes('app')) {
        await notify([p.userId], {
          type: 'follow_up_reminder', practiceId: f.practiceId, title: `Follow-up due ${days === 0 ? 'today' : days === 1 ? 'tomorrow' : `in ${days} days`}`,
          body: `${prof?.displayName || 'Your doctor'} asked you to come back on ${T.dayKey(f.dueDate)}. Book a time in the app.`,
          screen: 'Patient-Doctors', whatsapp: channels.includes('whatsapp'),
        });
      } else if (channels.includes('whatsapp')) {
        await require('./push').sendWhatsApp(p.phone, `Follow-up due on ${T.dayKey(f.dueDate)} with ${prof?.displayName || 'your doctor'}. Please book a visit.`, { template: 'follow_up_reminder' });
      }
      f.remindersSent = (f.remindersSent || 0) + 1;
      f.lastRemindedAt = now;
      await f.save();
    });
  }
}

async function lowStock(now) {
  if (T.minuteOfDay(now) < 9 * 60) return; // from 09:00 IST
  const day = T.dayKey(now);
  const courses = await M.MedicationCourse.find({ status: 'active', stockUnits: { $ne: null } }).limit(5000);
  for (const c of courses) {
    const perDay = c.frequency === 'weekly' ? dosesPerDay(c.dose) / 7 : dosesPerDay(c.dose);
    if (!perDay) continue;
    const daysLeft = Math.floor(c.stockUnits / perDay);
    if (daysLeft > 3) continue;
    const p = await M.Patient.findById(c.patientId, 'userId');
    if (!p?.userId) continue;
    await once(`stock:${c._id}:${day}`, () =>
      notify([p.userId], {
        type: 'low_stock', title: daysLeft <= 0 ? `${c.name} has run out` : `${c.name} runs out in ${daysLeft} day${daysLeft === 1 ? '' : 's'}`,
        body: `${c.stockUnits} left · ${doseText(c.dose)}. Reorder now so you don't miss doses.`, screen: 'Patient-Medicines', params: { courseId: c._id },
      }),
    );
  }
}

async function dailyLogReminders(now) {
  const day = T.dayKey(now);
  const minute = T.minuteOfDay(now);
  const patients = await M.Patient.find({ userId: { $ne: null }, 'settings.dailyLogReminder': { $ne: false } }, 'userId settings').limit(5000);
  for (const p of patients) {
    if (minute < T.hhmmToMin(p.settings?.dailyLogReminderAt || '20:00')) continue;
    const logged = await M.HealthLog.exists({ patientId: p._id, loggedAt: { $gte: T.dayStart(now) } });
    if (logged) continue;
    await once(`log:${p._id}:${day}`, () =>
      notify([p.userId], { type: 'daily_log_reminder', title: "Log today's meals", body: 'A quick photo or a line is enough. Your care team sees it.', screen: 'Patient-Log' }),
    );
  }
}

async function dailyDigest(now) {
  if (T.minuteOfDay(now) < 20 * 60) return; // 20:00 IST
  const day = T.dayKey(now);
  const today = T.dayStart(now);
  const doctors = await M.Member.find({ role: 'doctor', status: 'active' }, 'userId practiceId').populate('practiceId', 'name');
  for (const m of doctors) {
    const prof = await M.DoctorProfile.findOne({ userId: m.userId }, 'notificationPrefs');
    if (prof?.notificationPrefs?.dailyDigest === false) continue;
    await once(`digest:${m.userId}:${m.practiceId?._id}:${day}`, async () => {
      const base = { practiceId: m.practiceId?._id, doctorId: m.userId, date: today };
      const [seen, missed, followUps, alerts, unread] = await Promise.all([
        M.Appointment.countDocuments({ ...base, status: 'completed' }),
        M.Appointment.countDocuments({ ...base, status: 'missed' }),
        M.FollowUp.countDocuments({ practiceId: m.practiceId?._id, doctorId: m.userId, status: 'not_booked', dueDate: { $gte: today, $lt: T.addDays(today, 3) } }),
        M.Alert.countDocuments({ practiceId: m.practiceId?._id, status: 'open' }),
        M.Conversation.countDocuments({ practiceId: m.practiceId?._id, participants: { $elemMatch: { userId: m.userId, unreadCount: { $gt: 0 } } } }),
      ]);
      if (!seen && !missed && !followUps && !alerts && !unread) return;
      await notify([m.userId], {
        type: 'daily_digest', practiceId: m.practiceId?._id, title: `Your day at ${m.practiceId?.name || 'the clinic'}`,
        body: [`${seen} seen`, missed && `${missed} missed`, followUps && `${followUps} follow-ups due in 3 days`, alerts && `${alerts} open alerts`, unread && `${unread} chats waiting`].filter(Boolean).join(' · '),
        screen: 'Doctor-Dashboard',
      });
    });
  }
}

// ── Runner ───────────────────────────────────────────────

let timer = null;
let last = new Date(Date.now() - 60000);
let running = false;

async function tick() {
  if (running) return;
  running = true;
  const now = new Date();
  const since = last;
  last = now;
  for (const [name, job] of [
    ['prepareDoses', () => prepareDoses(now)], ['doses', () => doseReminders(now, since)], ['visits', () => visitReminders(now)],
    ['followUps', () => followUpReminders(now)], ['lowStock', () => lowStock(now)], ['dailyLog', () => dailyLogReminders(now)], ['digest', () => dailyDigest(now)],
  ]) {
    try {
      await job();
    } catch (err) {
      console.warn(`[jobs] ${name}: ${err.message}`);
    }
  }
  running = false;
}

function start({ everyMs = 60000 } = {}) {
  if (timer) return;
  timer = setInterval(tick, everyMs);
  timer.unref?.();
  setTimeout(tick, 5000).unref?.();
  console.log('Background jobs on (reminders, summaries)');
}

function stop() {
  clearInterval(timer);
  timer = null;
}

module.exports = { start, stop, tick, doseReminders, visitReminders, followUpReminders, lowStock, dailyLogReminders, dailyDigest, prepareDoses };

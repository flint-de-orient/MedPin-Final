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
const { liveDevices } = require('../lib/devicetokens');
const M = require('../models');
const env = require('../config/env');
const T = require('../lib/time');
const { notify } = require('./notify');
const { ensureDoses } = require('./care');
const { dosesPerDay, doseText } = require('./clinical');

const SLOT_LABEL = { morning: 'Morning', afternoon: 'Afternoon', night: 'Night' };
const FOOD = { before_food: 'before food', after_food: 'after food', with_food: 'with food', empty_stomach: 'on an empty stomach' };

/**
 * Runs [fn] only the first time [key] is seen. If [fn] fails (a database hiccup, the push
 * service down), the key is released so the next minute's run tries again.
 */
async function once(key, fn) {
  try {
    await M.ReminderLog.create({ key });
  } catch (err) {
    if (err.code === 11000) return false;
    throw err;
  }
  try {
    await fn();
  } catch (err) {
    await M.ReminderLog.deleteOne({ key }).catch(() => {});
    throw err;
  }
  return true;
}

/** Every 15 minutes (jobs that need no minute-by-minute check). */
const quarter = (now) => T.minuteOfDay(now) % 15 === 0;

const visitText = async (a) => {
  const [doctor, loc] = await Promise.all([M.User.findById(a.doctorId, 'name'), M.Location.findById(a.locationId, 'name shortName')]);
  return `${T.fmtTime(T.minuteOfDay(a.startAt))} with ${doctor?.name || 'your doctor'}${loc ? ` · ${loc.shortName || loc.name}` : ''}${a.tokenNo ? ` · token ${a.tokenNo}` : ''}`;
};

// ── Each job ─────────────────────────────────────────────

/**
 * Makes sure today's (and tomorrow's) dose rows exist for every patient taking medicines.
 * First, courses whose last day has passed are completed (no longer "current"), and those
 * patients' phones drop their alarms.
 */
async function prepareDoses(now) {
  const day = T.dayKey(now);
  await once(`doses-ready:${day}`, async () => {
    const done = { status: 'active', endDate: { $ne: null, $lt: T.dayStart(now) } };
    const finished = await M.MedicationCourse.distinct('patientId', done);
    if (finished.length) {
      await M.MedicationCourse.updateMany(done, { status: 'completed' });
      const { remindersChanged } = require('./reminders');
      for (const id of finished) remindersChanged(id);
    }
    const ids = await M.MedicationCourse.distinct('patientId', { status: 'active', trackingEnabled: true });
    const patients = await M.Patient.find({ _id: { $in: ids } });
    for (const p of patients) await ensureDoses(p, now, T.addDays(now, 1)).catch(() => {});
  });
}

async function doseReminders(now, since) {
  const doses = await M.DoseLog.find({ status: 'due', scheduledAt: { $gt: since, $lte: now } });
  if (!doses.length) return;
  const patients = new Map((await M.Patient.find({ _id: { $in: doses.map((d) => d.patientId) } }, 'userId settings')).map((p) => [String(p._id), p]));
  // Only medicines still being taken: a course stopped or finished since its doses were made rings nothing.
  const courses = new Map((await M.MedicationCourse.find({ _id: { $in: doses.map((d) => d.courseId) }, status: 'active' }, 'name strength foodRelation dose endDate stoppedAt')).map((c) => [String(c._id), c]));
  // Phones that ring alarms themselves don't need the server's push too — for the doses
  // they have scheduled (a dose changed after the phone last synced, or beyond what it
  // scheduled, still gets the push).
  const { phoneCovers } = require('./reminders');
  const phones = new Map();
  for (const t of await liveDevices({ userId: { $in: [...patients.values()].map((p) => p.userId).filter(Boolean) }, localAlarms: true })) {
    if (!phones.has(String(t.userId))) phones.set(String(t.userId), []);
    phones.get(String(t.userId)).push(t);
  }
  // Medicines due at the same time: one reminder listing them, not one each.
  const groups = new Map();
  for (const d of doses) {
    const p = patients.get(String(d.patientId));
    const c = courses.get(String(d.courseId));
    if (!p?.userId || p.settings?.medReminders === false || !c || phoneCovers(phones.get(String(p.userId)), d.updatedAt, d.scheduledAt)) continue;
    const key = `${d.patientId}:${d.scheduledAt.getTime()}`;
    if (!groups.has(key)) groups.set(key, { p, slot: d.slot, items: [] });
    groups.get(key).items.push({ d, c });
  }
  for (const [key, g] of groups) {
    const names = g.items.map(({ c }) => `${c.name}${c.strength ? ` ${c.strength}` : ''}`);
    const foods = [...new Set(g.items.map(({ c }) => FOOD[c.foodRelation]).filter(Boolean))];
    await once(`dosegroup:${key}`, () =>
      notify([g.p.userId], { forPatientId: g.p._id,
        type: 'dose_reminder',
        title: names.length === 1 ? `Time for ${names[0]}` : `Time for ${names.length} medicines`,
        body: [names.length > 1 ? names.join(', ') : null, SLOT_LABEL[g.slot] && `${SLOT_LABEL[g.slot]} dose`, foods.join(' / ')].filter(Boolean).join(' · '),
        screen: 'Patient-Medicines', params: { doseId: g.items[0].d._id },
      }),
    );
  }
}

async function visitReminders(now) {
  // "A day before" (up to 24 h ahead, until 2 h before) and "2 hours before".
  // Any visit in the window not yet reminded gets it, so a server pause loses nothing.
  for (const [hours, until] of [[24, 2], [2, 0]]) {
    const from = new Date(now.getTime() + until * 3600e3);
    const to = new Date(now.getTime() + hours * 3600e3);
    const field = hours === 24 ? 'reminded24At' : 'reminded2At';
    for await (const a of M.Appointment.find({ status: { $in: ['booked', 'confirmed'] }, startAt: { $gt: from, $lte: to }, [field]: null }).cursor()) {
      // Looked at once: sent now, or not needed (booked late, reminders off, the phone rings it).
      await M.Appointment.updateOne({ _id: a._id }, { [field]: now }, { timestamps: false });
      // Booked only shortly before (e.g. this morning for this evening): the confirmation was enough.
      if (a.createdAt && a.startAt - a.createdAt < (hours === 24 ? 12 : 2) * 3600e3) continue;
      const p = await M.Patient.findById(a.patientId, 'userId settings');
      if (!p?.userId || p.settings?.visitReminders === false) continue;
      // The patient's phone has this visit's reminders scheduled itself.
      const devices = await liveDevices({ userId: p.userId, localAlarms: true });
      if (require('./reminders').phoneCovers(devices, a.updatedAt, a.startAt)) continue;
      const mins = Math.round((a.startAt - now) / 60000);
      const label = hours === 2
        ? (mins < 90 ? `in ${mins} minutes` : 'in about 2 hours')
        : T.dayKey(a.startAt) === T.dayKey(now) ? 'today' : 'tomorrow';
      try {
        await once(`visit${hours}:${a._id}`, async () =>
          notify([p.userId], { forPatientId: p._id,
            type: 'visit_reminder', practiceId: a.practiceId, title: `Your visit is ${label}`, body: await visitText(a),
            screen: 'Patient-DoctorDetail', params: { doctorId: a.doctorId, appointmentId: a._id }, whatsapp: hours === 24,
          }),
        );
      } catch (err) {
        await M.Appointment.updateOne({ _id: a._id }, { $unset: { [field]: 1 } }, { timestamps: false }); // tried again next minute
        throw err;
      }
    }
  }
}

async function followUpReminders(now, { force = false } = {}) {
  if (T.minuteOfDay(now) < 10 * 60) return; // from 10:00 IST
  if (!force && !quarter(now)) return;
  const today = T.dayStart(now);
  // Only when the doctor left "Remind the patient" on.
  const due = M.FollowUp.find({ status: 'not_booked', remindPatient: { $ne: false }, remindersSent: { $in: [0, null] }, dueDate: { $gte: today, $lt: T.addDays(today, 31) } }).cursor();
  for await (const f of due) {
    const prof = await M.DoctorProfile.findOne({ userId: f.doctorId }, 'followUpReminder displayName');
    const days = prof?.followUpReminder?.daysBefore ?? 3;
    const channels = prof?.followUpReminder?.channels || ['whatsapp', 'app'];
    const left = Math.round((T.dayStart(f.dueDate) - today) / 864e5);
    // From that many days before (a day the server was down, or a follow-up set closer than
    // that, still gets it) — once per follow-up.
    if (left > days || left < 0 || f.remindersSent > 0) continue;
    const p = await M.Patient.findById(f.patientId, 'userId phone');
    if (!p) continue;
    await once(`followup:${f._id}`, async () => {
      if (p.userId && channels.includes('app')) {
        await notify([p.userId], { forPatientId: p._id,
          type: 'follow_up_reminder', practiceId: f.practiceId, title: `Follow-up due ${left === 0 ? 'today' : left === 1 ? 'tomorrow' : `in ${left} days`}`,
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
  if (T.minuteOfDay(now) < 9 * 60 || !quarter(now)) return; // from 09:00 IST, every 15 min
  const day = T.dayKey(now);
  for await (const c of M.MedicationCourse.find({ status: 'active', stockUnits: { $ne: null } }).cursor()) {
    const perDay = require('./clinical').stockPerDay(c);
    if (!perDay) continue;
    const daysLeft = Math.floor(c.stockUnits / perDay);
    if (daysLeft > 3) continue;
    const p = await M.Patient.findById(c.patientId, 'userId');
    if (!p?.userId) continue;
    await once(`stock:${c._id}:${day}`, () =>
      notify([p.userId], { forPatientId: p._id,
        type: 'low_stock', title: daysLeft <= 0 ? `${c.name} has run out` : `${c.name} runs out in ${daysLeft} day${daysLeft === 1 ? '' : 's'}`,
        body: env.pharmacyOrdering
          ? `${c.stockUnits} left · ${doseText(c.dose)}. Reorder now so you don't miss doses.`
          : `${c.stockUnits} left · ${doseText(c.dose)}. Buy a refill from your chemist so you don't miss doses.`,
        screen: 'Patient-Medicines', params: { courseId: c._id },
      }),
    );
  }
}

async function dailyLogReminders(now) {
  const day = T.dayKey(now);
  const minute = T.minuteOfDay(now);
  for await (const p of M.Patient.find({ userId: { $ne: null }, primary: { $ne: false }, 'settings.dailyLogReminder': { $ne: false } }, 'userId settings').cursor()) {
    const at = /^\d{2}:\d{2}$/.test(p.settings?.dailyLogReminderAt || '') ? p.settings.dailyLogReminderAt : '20:00';
    if (minute < T.hhmmToMin(at)) continue;
    const logged = await M.HealthLog.exists({ patientId: p._id, loggedAt: { $gte: T.dayStart(now) } });
    if (logged) continue;
    // On when the patient switched it on, or (not chosen) when their care team asked for a meal log.
    if (!p.settings?.dailyLogReminderChosen && !(await require('../routes/patient').dailyLogUsed(p))) continue;
    // Their phone rings it itself at this time.
    const phone = (await liveDevices({ userId: p.userId, localAlarms: true, dailyLogAt: at, remindersUntil: { $gte: now } })).length > 0;
    if (phone) continue;
    await once(`log:${p._id}:${day}`, () =>
      notify([p.userId], { forPatientId: p._id, type: 'daily_log_reminder', title: "Log today's meals", body: 'A quick photo or a line is enough. Your care team sees it.', screen: 'Patient-Log' }),
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

/**
 * The doctor's morning summary (their own time, default 08:00): what patients
 * shared since yesterday's summary and which results need a look, patients
 * whose medicine-taking dropped, and patients asked to log meals who stopped.
 * One notification instead of one per patient — a doctor with thousands of
 * patients isn't buzzed all day. Urgent things still come at once (alerts).
 */
async function morningSummary(now) {
  const nowMin = T.minuteOfDay(now);
  const day = T.dayKey(now);
  const since = T.addDays(now, -1);
  const doctors = await M.Member.find({ role: { $in: ['doctor', 'dietician'] }, status: 'active' }, 'userId practiceId role').populate('practiceId', 'name');
  if (nowMin < 5 * 60) return; // nobody's summary is before 05:00
  const done = new Set((await M.ReminderLog.find({ key: new RegExp(`^morning:.*:${day}$`) }, 'key')).map((r) => r.key));
  for (const m of doctors) {
    const key = `morning:${m.userId}:${m.practiceId?._id}:${day}`;
    if (done.has(key)) continue; // already sent today
    const prof = await M.DoctorProfile.findOne({ userId: m.userId }, 'notificationPrefs');
    const prefs = prof?.notificationPrefs;
    if (prefs?.dailyDigest === false) continue;
    if (nowMin < T.hhmmToMin(prefs?.digestAt || '08:00')) continue;
    await once(key, async () => {
      const team = await M.CareTeamAccess.find({ userId: m.userId, practiceId: m.practiceId?._id, accessLevel: { $ne: 'not_shared' } }).distinct('patientId');
      if (!team.length) return;
      const [shared, abnormal, asked] = await Promise.all([
        M.MedicalRecord.countDocuments({ patientId: { $in: team }, 'sharedWith.userId': m.userId, deletedAt: null, updatedAt: { $gte: since } }),
        M.MedicalRecord.countDocuments({ patientId: { $in: team }, 'sharedWith.userId': m.userId, deletedAt: null, updatedAt: { $gte: since }, flagTone: 'high' }),
        M.MedicalRecord.countDocuments({ patientId: { $in: team }, 'sharedWith.userId': m.userId, deletedAt: null, updatedAt: { $gte: since }, 'forTests.0': { $exists: true } }),
      ]);
      // Taking their medicines from this doctor: under 70% over the last 7 days (6+ doses counted).
      const myCourses = await M.MedicationCourse.find({ patientId: { $in: team }, doctorId: m.userId, status: 'active', frequency: { $ne: 'as_needed' } }).distinct('_id');
      const counted = myCourses.length
        ? await M.DoseLog.aggregate([
          { $match: { courseId: { $in: myCourses }, scheduledAt: { $gte: T.addDays(now, -7), $lte: T.addMinutes(now, -120) } } },
          { $group: { _id: '$patientId', taken: { $sum: { $cond: [{ $eq: ['$status', 'taken'] }, 1, 0] } }, total: { $sum: 1 } } },
        ])
        : [];
      const dropped = counted.filter((c) => c.total >= 6 && c.taken / c.total < 0.7).length;
      // Asked to log meals (this doctor / dietician reviews them) and nothing for 2 days.
      const askedToLog = await M.TreatmentPlan.find({ practiceId: m.practiceId?._id, nutritionBy: m.userId }).distinct('patientId');
      const logging = askedToLog.length ? await M.HealthLog.find({ patientId: { $in: askedToLog }, type: 'meal', loggedAt: { $gte: T.addDays(now, -2) } }).distinct('patientId') : [];
      const notLogging = askedToLog.length - logging.length;
      // Patients who wrote since yesterday (overnight too) and haven't had this doctor read it.
      const waiting = await M.Conversation.countDocuments({
        practiceId: m.practiceId?._id, type: m.role === 'dietician' ? 'nutrition' : 'care', patientId: { $in: team },
        'lastMessage.at': { $gte: since }, participants: { $elemMatch: { userId: m.userId, unreadCount: { $gt: 0 } } },
      });
      const parts = [
        waiting && `${waiting} ${waiting === 1 ? 'patient' : 'patients'} wrote, waiting for a reply`,
        shared && `${shared} ${shared === 1 ? 'report' : 'reports'} shared${abnormal ? ` (${abnormal} out of range)` : ''}${asked ? ` · ${asked} you asked for` : ''}`,
        dropped && `${dropped} ${dropped === 1 ? 'patient' : 'patients'} below 70% on medicines`,
        notLogging > 0 && `${notLogging} not logging meals`,
      ].filter(Boolean);
      if (!parts.length) return;
      await notify([m.userId], {
        type: 'morning_summary', practiceId: m.practiceId?._id, title: `Your patients since yesterday · ${m.practiceId?.name || 'clinic'}`,
        body: parts.join(' · '), screen: 'Doctor-Patients',
      });
    });
  }
}

/**
 * One-time: app lock used to be on for every new account. Patients never chose
 * it, so it's switched off for them once (they can turn it on in Profile).
 * Doctors and staff keep theirs: their phones hold many patients' records.
 */
/**
 * Watches and rings: every 4 hours, patients whose phone synced Health Connect
 * before (and not in the last 3 hours) get a silent push; the app syncs in the
 * background (lib/data/push.dart pushBackground), so readings arrive without
 * the app being opened.
 */
async function deviceSyncNudge(now) {
  const slot = Math.floor(T.minuteOfDay(now) / 240); // 4-hour windows
  await once(`devicesync:${T.dayKey(now)}:${slot}`, async () => {
    const before = new Date(now.getTime() - 3 * 3600e3);
    const ids = await M.Patient.find({ userId: { $ne: null }, 'deviceSync.at': { $ne: null, $lt: before } }).limit(5000).distinct('userId');
    if (ids.length) await require('./notify').signal(ids, { type: 'device_sync' });
  });
}

let appLockChecked = false;
async function appLockOffForPatients() {
  if (appLockChecked) return;
  appLockChecked = true;
  await once('migrate:app-lock-off-patients-v1', async () => {
    const staff = await M.Member.find({ status: { $ne: 'removed' } }).distinct('userId');
    const patients = await M.Patient.find({ userId: { $ne: null } }).distinct('userId');
    const r = await M.User.updateMany({ _id: { $in: patients, $nin: staff }, appLock: true }, { appLock: false });
    console.log(`[jobs] app lock switched off for ${r.modifiedCount} patient accounts`);
  });
}

/** Doctors' online fees, paid out every Monday from 10:00 IST. */
async function payouts(now) {
  const ist = new Date(now.getTime() + T.IST_MS);
  if (ist.getUTCDay() !== 1 || T.minuteOfDay(now) < 10 * 60) return;
  await once(`payouts:${T.dayKey(now)}`, () => require('./payouts').run(now));
}

/** Health scores once a night (03:00 IST) for patients with recent data. */
async function healthScores(now) {
  if (T.minuteOfDay(now) < 3 * 60) return;
  await once(`scores:${T.dayKey(now)}`, async () => {
    const since = T.addDays(T.dayStart(now), -14);
    const ids = new Set([
      ...(await M.DoseLog.find({ scheduledAt: { $gte: since } }).distinct('patientId')),
      ...(await M.Vitals.find({ recordedAt: { $gte: since } }).distinct('patientId')),
    ].map(String));
    const { refreshScore } = require('./health');
    for (const p of await M.Patient.find({ _id: { $in: [...ids].slice(0, 5000) } })) {
      await refreshScore(p).catch((err) => console.warn('[jobs] score', err.message));
    }
  });
}

/** Booked / confirmed for a day that has ended and nobody came: marked missed
 *  (History, Reports and follow-ups then agree). */
async function noShows(now) {
  const { transition } = require('./scheduling');
  const stale = await M.Appointment.find({ status: { $in: ['booked', 'confirmed'] }, date: { $lt: T.dayStart(now) } }).limit(500);
  for (const a of stale) await transition(a, 'missed').catch((err) => console.warn('[jobs] no-show', err.message));
}

/**
 * An emergency (urgent chat, a dangerous home reading) that no clinician has
 * acknowledged within 15 minutes: the front desk covering the patient is asked,
 * once, to tell the doctor in person — they can interrupt a consultation. The
 * desk opens the patient's chat (they don't have the clinical alerts screen).
 * Older than a day: left alone (nobody is paged about yesterday's alert).
 */
const ESCALATE_AFTER_MIN = 15;
/**
 * Doctors with no front desk: instead of a push for every patient message, one
 * summary at most every 2 hours inside their reply hours (Chat settings), naming who
 * wrote since the last one. Doctors with a desk aren't sent this (the desk answers
 * first); urgent messages always come through at once (care.postMessage).
 */
async function chatRollup(now) {
  if (T.minuteOfDay(now) % 10 !== 0) return;
  const since = new Date(now.getTime() - 2 * 3600e3);
  // Patients still waiting for a person: nobody at the clinic has written since their last
  // message (MedPin AI's or an automatic note's answer doesn't count as a reply).
  const recent = await M.Conversation.find(
    { type: 'care', 'lastMessage.senderType': { $in: ['patient', 'ai', 'system', 'doctor', 'staff'] }, 'lastMessage.at': { $gte: since }, isUrgent: { $ne: true } },
    'practiceId patientId participants lastMessage',
  ).populate('patientId', 'name').lean();
  const convos = [];
  for (const c of recent) {
    const lastHuman = await M.Message.findOne({ conversationId: c._id, senderType: { $in: ['patient', 'doctor', 'staff'] }, 'meta.auto': { $ne: true }, deletedForEveryoneAt: null }, 'senderType').sort({ createdAt: -1 }).lean();
    if (lastHuman?.senderType === 'patient') convos.push(c);
  }
  // Each doctor hears about their own patients (care team), not every patient of the clinic.
  const teamOf = new Map();
  const myPatient = async (doctorId, patientId, practiceId) => {
    const k = `${doctorId}:${practiceId}`;
    if (!teamOf.has(k)) {
      const doctors = await M.Member.countDocuments({ practiceId, status: 'active', role: 'doctor' });
      teamOf.set(k, doctors <= 1 ? null : new Set((await M.CareTeamAccess.find({ userId: doctorId, practiceId, accessLevel: { $ne: 'not_shared' } }, 'patientId').lean()).map((x) => String(x.patientId))));
    }
    const set = teamOf.get(k);
    return set === null || set.has(String(patientId?._id || patientId));
  };
  const byDoctor = new Map(); // doctorId → { practiceId, names[] }
  // A branch with its own front desk: the desk handles those chats (the doctor isn't rolled up);
  // a branch without one: its doctors are, even when another branch has a desk.
  const { hasDesk, patientPlace } = require('./notify');
  const branchDesk = new Map();
  const deskHandles = async (c) => {
    const place = await patientPlace(c.practiceId, c.patientId?._id || c.patientId).catch(() => ({}));
    const k = `${c.practiceId}:${place.locationId || ''}`;
    if (!branchDesk.has(k)) branchDesk.set(k, await hasDesk(c.practiceId, place.locationId || undefined));
    return branchDesk.get(k);
  };
  for (const c of convos) {
    if (await deskHandles(c)) continue;
    for (const p of c.participants || []) {
      if (p.role !== 'doctor' || !(p.unreadCount > 0)) continue;
      if (!(await myPatient(p.userId, c.patientId, c.practiceId))) continue;
      const key = `${p.userId}:${c.practiceId}`;
      const e = byDoctor.get(key) || { doctorId: p.userId, practiceId: c.practiceId, names: [] };
      e.names.push(c.patientId?.name || 'A patient');
      byDoctor.set(key, e);
    }
  }
  if (!byDoctor.size) return;
  const bucket = Math.floor(T.minuteOfDay(now) / 120);
  for (const e of byDoctor.values()) {
    const prof = await M.DoctorProfile.findOne({ userId: e.doctorId }, 'chatSettings');
    const from = T.hhmmToMin(prof?.chatSettings?.replyHours?.from || '09:00');
    const to = T.hhmmToMin(prof?.chatSettings?.replyHours?.to || '20:00');
    const m = T.minuteOfDay(now);
    if (!(from <= to ? m >= from && m < to : m >= from || m < to)) continue;
    const names = [...new Set(e.names)];
    await once(`chatRollup:${e.doctorId}:${e.practiceId}:${T.dayKey(now)}:${bucket}`, () => notify([e.doctorId], {
      type: 'message_digest', practiceId: e.practiceId,
      title: names.length === 1 ? `${names[0]} is waiting for a reply` : `${names.length} patients are waiting for a reply`,
      body: names.slice(0, 3).join(', ') + (names.length > 3 ? ` +${names.length - 3}` : ''),
      screen: 'Doctor-Messages',
    }));
  }
}

async function escalateEmergencies(now) {
  const { deskFor, clinicians, assistantsOf, patientPlace } = require('./notify');
  const { shortName } = require('./care');
  const due = await M.Alert.find({
    severity: 'emergency', status: 'open', escalatedAt: null,
    createdAt: { $lte: T.addMinutes(now, -ESCALATE_AFTER_MIN), $gte: T.addDays(now, -1) },
  }).limit(200);
  for (const a of due) {
    await once(`alert-escalate:${a._id}`, async () => {
      await M.Alert.updateOne({ _id: a._id }, { escalatedAt: now });
      const place = await patientPlace(a.practiceId, a.patientId);
      const doctorId = a.doctorId || place.doctorId;
      const doctors = (await clinicians(a.practiceId, a.patientId, { doctorId })).map(String);
      const team = new Set([...doctors, ...(await assistantsOf(a.practiceId, doctors)).map(String)]);
      const desk = (await deskFor(a.practiceId, { locationId: place.locationId, doctorId })).map(String).filter((id) => !team.has(id));
      if (!desk.length) return;
      const [patient, doctor] = await Promise.all([M.Patient.findById(a.patientId, 'name'), doctorId ? M.User.findById(doctorId, 'name') : null]);
      await notify(desk, {
        type: 'emergency_escalation', practiceId: a.practiceId,
        title: `${shortName(doctor?.name) || 'The doctor'} hasn't seen an emergency for ${patient?.name || 'a patient'} yet`,
        body: `Please let the doctor know. ${a.detail}`.slice(0, 200),
        screen: 'Patient-Thread', params: { alertId: a._id, patientId: a.patientId, ...(a.conversationId ? { conversationId: a.conversationId } : {}) },
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
    ['escalate', () => escalateEmergencies(now)], ['chatRollup', () => chatRollup(now)], ['prepareDoses', () => prepareDoses(now)], ['doses', () => doseReminders(now, since)], ['visits', () => visitReminders(now)], ['morning', () => morningSummary(now)], ['appLock', () => appLockOffForPatients()], ['deviceSync', () => deviceSyncNudge(now)],
    ['followUps', () => followUpReminders(now)], ['lowStock', () => lowStock(now)], ['dailyLog', () => dailyLogReminders(now)], ['digest', () => dailyDigest(now)],
    ['scores', () => healthScores(now)], ['noShows', () => noShows(now)],
    ['payouts', () => payouts(now)],
    // A clinic's MedPin month (or trial) ended unpaid: Payment due, the owner told once.
    ['billing', () => (quarter(now) ? require('./billing').remindDue(now) : null)],
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

module.exports = { once, chatRollup, escalateEmergencies, noShows, start, stop, tick, morningSummary, doseReminders, visitReminders, followUpReminders, lowStock, dailyLogReminders, dailyDigest, prepareDoses, healthScores };

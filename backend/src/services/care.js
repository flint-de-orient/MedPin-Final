// Alerts, care conversations and medicine adherence.
const M = require('../models');
const T = require('../lib/time');
const { notify, practiceStaff, clinicians } = require('./notify');

// ── Alerts ────────────────────────────────────────────────

async function raiseAlert({ practiceId, patientId, doctorId, severity, kind, title, detail, sourceModel, sourceId, conversationId }) {
  const alert = await M.Alert.create({ practiceId, patientId, doctorId, severity, kind, title, detail, sourceModel, sourceId, conversationId });
  // Clinical alerts reach the patient's own doctors (the one named, plus the care team).
  const staffIds = await clinicians(practiceId, patientId, { doctorId });
  const patient = await M.Patient.findById(patientId, 'name');
  await notify(staffIds, {
    type: `alert_${severity}`, practiceId,
    title: `${severity === 'emergency' ? 'Emergency' : severity === 'urgent' ? 'Urgent' : 'Watch'}: ${patient?.name || 'patient'}`,
    body: detail, screen: 'Alerts', params: { alertId: alert._id },
  });
  return alert;
}

const DEFAULT_LIMITS = { bpSystolicMax: 160, bpDiastolicMax: 100, sugarFastingMax: 250, pulseMin: 45, pulseMax: 120, spo2Min: 92 };

/** Raises alerts for a home reading outside the patient's limits, in every linked practice. */
async function checkReading(vitals, patient) {
  const L = { ...DEFAULT_LIMITS, ...(patient.alertLimits?.toObject ? patient.alertLimits.toObject() : patient.alertLimits || {}) };
  const out = [];
  if (vitals.bpSystolic && (vitals.bpSystolic >= L.bpSystolicMax || vitals.bpDiastolic >= L.bpDiastolicMax)) {
    const severe = vitals.bpSystolic >= 180 || vitals.bpDiastolic >= 120;
    out.push({ severity: severe ? 'emergency' : 'urgent', detail: `Home BP reading ${vitals.bpSystolic}/${vitals.bpDiastolic} mmHg, above the alert limit.` });
  }
  if (vitals.spo2 && vitals.spo2 < L.spo2Min) out.push({ severity: vitals.spo2 < 88 ? 'emergency' : 'urgent', detail: `SpO₂ ${vitals.spo2}%, below ${L.spo2Min}%.` });
  if (vitals.pulse && (vitals.pulse < L.pulseMin || vitals.pulse > L.pulseMax)) out.push({ severity: 'watch', detail: `Heart rate ${vitals.pulse} bpm, outside ${L.pulseMin}–${L.pulseMax}.` });
  if (vitals.bloodSugar && vitals.sugarType === 'fasting' && vitals.bloodSugar >= L.sugarFastingMax) out.push({ severity: 'urgent', detail: `Fasting sugar ${vitals.bloodSugar} mg/dL.` });
  if (vitals.bloodSugar && vitals.bloodSugar < 70) out.push({ severity: vitals.bloodSugar < 54 ? 'emergency' : 'urgent', detail: `Low blood sugar ${vitals.bloodSugar} mg/dL.` });
  if (!out.length) return [];
  const practices = await M.PatientEnrolment.find({ patientId: patient._id, status: 'linked' }).distinct('practiceId');
  const alerts = [];
  for (const practiceId of practices) {
    for (const a of out) {
      alerts.push(await raiseAlert({ practiceId, patientId: patient._id, kind: 'reading', sourceModel: 'Vitals', sourceId: vitals._id, ...a }));
    }
  }
  return alerts;
}

// ── Conversations ─────────────────────────────────────────

const CARE_ROLES = { care: ['doctor', 'front_desk', 'doctor_assistant', 'practice_manager'], nutrition: ['dietician', 'doctor'] };

/** The patient ↔ practice thread (created on first use). */
async function careConversation(patientId, practiceId, type = 'care') {
  let convo = await M.Conversation.findOne({ patientId, practiceId, type });
  if (convo) return convo;
  const patient = await M.Patient.findById(patientId, 'userId');
  const members = await M.Member.find({ practiceId, status: 'active', role: { $in: CARE_ROLES[type] } }, 'userId role');
  const participants = members.map((m) => ({ userId: m.userId, role: m.role === 'doctor' ? 'doctor' : m.role === 'dietician' ? 'dietician' : 'staff' }));
  if (patient?.userId) participants.push({ userId: patient.userId, role: 'patient' });
  try {
    convo = await M.Conversation.create({ type, practiceId, patientId, participants });
  } catch (err) {
    if (err.code !== 11000) throw err;
    convo = await M.Conversation.findOne({ patientId, practiceId, type });
  }
  return convo;
}

/** Adds a user to a thread if they aren't in it yet. */
async function ensureParticipant(convo, userId, role) {
  if (convo.participants.some((p) => String(p.userId) === String(userId))) return convo;
  convo.participants.push({ userId, role });
  await convo.save();
  return convo;
}

const SENDER_LABEL = { ai: 'AI', system: 'Clinic' };

/** "Dr. Ananya Sen" → "Dr. Sen"; "Tania Roy" → "Tania". */
function shortName(name) {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '';
  if (/^dr\.?$/i.test(parts[0])) return parts.length > 1 ? `Dr. ${parts[parts.length - 1]}` : 'Dr.';
  return parts[0];
}

/** Saves a message, updates the thread preview and unread counts, and notifies. */
async function postMessage(convo, { sender, senderType, text, kind = 'text', ...rest }) {
  const msg = await M.Message.create({ conversationId: convo._id, senderId: sender?._id, senderType, text, kind, ...rest });
  const senderId = sender ? String(sender._id) : null;
  convo.lastMessage = {
    text: text || (kind === 'voice' ? 'Voice message' : kind === 'record' ? 'Shared a record' : 'Attachment'),
    senderType,
    senderId: sender?._id,
    senderLabel: SENDER_LABEL[senderType] || shortName(sender?.name) || 'Clinic',
    at: msg.createdAt,
  };
  for (const p of convo.participants) {
    if (String(p.userId) !== senderId) p.unreadCount = (p.unreadCount || 0) + 1;
  }
  if (rest.isUrgent && !convo.isUrgent) {
    convo.isUrgent = true;
    convo.urgentSince = new Date();
  }
  if (senderType === 'patient') convo.triage = convo.triage || 'needs_attention';
  await convo.save();
  const toPatient = convo.participants.filter((p) => p.role === 'patient' && String(p.userId) !== senderId).map((p) => p.userId);
  let toStaff = [];
  if (senderType === 'patient') {
    // The patient's own clinicians hear about it (dietician for nutrition threads); the front
    // desk sees it in their inbox. Clinicians who joined later are added to the thread now.
    toStaff = await clinicians(convo.practiceId, convo.patientId, { roles: convo.type === 'nutrition' ? ['dietician', 'doctor'] : ['doctor'] });
    let changed = false;
    for (const id of toStaff) {
      if (!convo.participants.some((p) => String(p.userId) === String(id))) {
        convo.participants.push({ userId: id, role: convo.type === 'nutrition' ? 'dietician' : 'doctor', unreadCount: 1 });
        changed = true;
      }
    }
    if (changed) await convo.save();
  }
  const base = { type: rest.isUrgent ? 'urgent_message' : 'message', practiceId: convo.practiceId, body: (text || '').slice(0, 120) };
  if (toStaff.length) {
    await notify(toStaff, { ...base, title: rest.isUrgent ? `Urgent message from ${convo.lastMessage.senderLabel}` : `New message from ${convo.lastMessage.senderLabel}`, screen: 'Patient-Thread', params: { conversationId: convo._id } });
  }
  if (toPatient.length) {
    await notify(toPatient, { ...base, title: `New message from ${convo.lastMessage.senderLabel}`, screen: 'Patient-DoctorChat', params: { conversationId: convo._id } });
  }
  if (senderType === 'patient') await awayReply(convo).catch(() => {});
  return msg;
}

/**
 * Chat settings → "Reply hours" and "Away message": a patient writing outside
 * the primary doctor's reply hours gets the away message once (per 12 h).
 */
async function awayReply(convo) {
  const team = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, isPrimary: true });
  const profile = team && (await M.DoctorProfile.findOne({ userId: team.userId }, 'chatSettings displayName'));
  const cs = profile?.chatSettings;
  if (!cs?.awayMessage || !cs.replyHours?.from || !cs.replyHours?.to) return;
  const now = T.minuteOfDay(new Date());
  const from = T.hhmmToMin(cs.replyHours.from);
  const to = T.hhmmToMin(cs.replyHours.to);
  const inHours = from <= to ? now >= from && now < to : now >= from || now < to;
  if (inHours) return;
  const recent = await M.Message.exists({ conversationId: convo._id, senderType: 'system', 'meta.away': true, createdAt: { $gte: new Date(Date.now() - 12 * 3600e3) } });
  if (recent) return;
  await M.Message.create({ conversationId: convo._id, senderType: 'system', kind: 'text', text: cs.awayMessage, meta: { away: true } });
}

/** Marks a thread read for one user. */
async function markRead(convo, userId) {
  const p = convo.participants.find((x) => String(x.userId) === String(userId));
  if (!p) return convo;
  p.unreadCount = 0;
  p.lastReadAt = new Date();
  await convo.save();
  await M.Message.updateMany(
    { conversationId: convo._id, senderId: { $ne: userId }, deliveryStatus: { $ne: 'seen' } },
    { deliveryStatus: 'seen', seenAt: new Date() },
  );
  return convo;
}

// ── Medicine doses and adherence ──────────────────────────

const SLOTS = ['morning', 'afternoon', 'night'];

/** Meal times by slot (settings.reminderTimes is the patient's breakfast / lunch / dinner). */
const MEALS = { morning: '08:00', afternoon: '13:30', night: '20:30' };

/**
 * When a dose is due: around the meal of its slot, by how it's taken —
 * before food 30 min before, after food 15 min after, with food at the meal,
 * empty stomach 45 min before, at bedtime at the patient's bedtime.
 * Minutes after midnight (IST).
 */
function doseMinute(settings, slot, foodRelation) {
  const times = settings?.reminderTimes || {};
  const meal = T.hhmmToMin(/^\d{2}:\d{2}$/.test(times[slot] || '') ? times[slot] : MEALS[slot]);
  if (foodRelation === 'bedtime') {
    const bed = settings?.bedAt && /^\d{2}:\d{2}$/.test(settings.bedAt) ? T.hhmmToMin(settings.bedAt) : null;
    return bed ?? Math.min(23 * 60 + 30, meal + 120);
  }
  const offset = { before_food: -30, after_food: 15, with_food: 0, empty_stomach: -45 }[foodRelation] ?? 0;
  return Math.max(0, Math.min(24 * 60 - 1, meal + offset));
}
const MISSED_AFTER_MIN = 180; // a dose not marked 3 h after its time counts as missed

/** Creates the scheduled doses for each day in [from, to] (idempotent). */
async function ensureDoses(patient, from, to = from) {
  const start = T.dayStart(from);
  const end = T.dayStart(to);
  const courses = await M.MedicationCourse.find({
    patientId: patient._id, trackingEnabled: true, startDate: { $lte: end },
    $or: [{ endDate: null }, { endDate: { $gte: start } }], status: { $ne: 'stopped' },
  });
  const ops = [];
  for (let day = start; day <= end; day = T.addDays(day, 1)) {
    for (const c of courses) {
      if (c.startDate > day || (c.endDate && c.endDate < day) || (c.stoppedAt && c.stoppedAt < day)) continue;
      if (c.frequency === 'weekly' && c.weekday && c.weekday !== T.weekday(day)) continue;
      for (const slot of SLOTS) {
        if (!(c.dose?.[slot] > 0)) continue;
        const scheduledAt = T.atMinute(day, doseMinute(patient.settings, slot, c.foodRelation));
        ops.push({
          updateOne: {
            filter: { courseId: c._id, scheduledAt },
            update: { $setOnInsert: { courseId: c._id, patientId: patient._id, scheduledAt, slot, status: 'due' } },
            upsert: true,
          },
        });
      }
    }
  }
  if (ops.length) await M.DoseLog.bulkWrite(ops, { ordered: false });
  // Future doses that are no longer in the schedule (a reminder time changed,
  // a medicine was stopped or its dose edited) go, so no alarm rings for them.
  const keep = new Set(ops.map((o) => `${o.updateOne.filter.courseId}|${o.updateOne.filter.scheduledAt.getTime()}`));
  const now = new Date();
  const stale = await M.DoseLog.find(
    { patientId: patient._id, status: 'due', scheduledAt: { $gt: now > start ? now : start, $lt: T.addDays(end, 1) } },
    'courseId scheduledAt',
  );
  const drop = stale.filter((d) => !keep.has(`${d.courseId}|${d.scheduledAt.getTime()}`)).map((d) => d._id);
  if (drop.length) await M.DoseLog.deleteMany({ _id: { $in: drop } });
}

const effectiveStatus = (d, now = new Date()) =>
  d.status === 'due' && d.scheduledAt < T.addMinutes(now, -MISSED_AFTER_MIN) ? 'missed' : d.status;

/** Adherence over the last `days` days: overall, per doctor, per medicine, and the slot with most misses. */
/** Adherence over [days]. With [acc] (a clinic viewer) only medicines it may see count. */
async function adherence(patient, days = 30, acc) {
  const now = new Date();
  const from = T.addDays(T.dayStart(now), -(days - 1));
  await ensureDoses(patient, from, now);
  const allCourses = await M.MedicationCourse.find({ patientId: patient._id });
  const courses = acc ? allCourses.filter((c) => acc.courseVisible(c)) : allCourses;
  const doses = await M.DoseLog.find({ patientId: patient._id, courseId: { $in: courses.map((c) => c._id) }, scheduledAt: { $gte: from, $lte: now } });
  const courseById = new Map(courses.map((c) => [String(c._id), c]));
  const pct = (taken, total) => (total ? Math.round((taken / total) * 100) : null);
  const tally = () => ({ taken: 0, total: 0 });
  const overall = tally();
  const byCourse = new Map();
  const byDoctor = new Map();
  const missesBySlot = { morning: 0, afternoon: 0, night: 0 };
  for (const d of doses) {
    const s = effectiveStatus(d, now);
    if (s === 'due') continue; // not yet due enough to count
    const c = courseById.get(String(d.courseId));
    const doc = c?.doctorId ? String(c.doctorId) : c?.prescriberName || 'self';
    for (const t of [overall, byCourse.get(String(d.courseId)) || byCourse.set(String(d.courseId), tally()).get(String(d.courseId)), byDoctor.get(doc) || byDoctor.set(doc, tally()).get(doc)]) {
      t.total += 1;
      if (s === 'taken') t.taken += 1;
    }
    if (s !== 'taken') missesBySlot[d.slot] += 1;
  }
  const worstSlot = Object.entries(missesBySlot).sort((a, b) => b[1] - a[1])[0];
  return {
    days,
    overallPct: pct(overall.taken, overall.total),
    perMedicine: courses
      .filter((c) => c.status === 'active')
      .map((c) => {
        const t = byCourse.get(String(c._id));
        return { courseId: c._id, name: c.name, strength: c.strength, doctorId: c.doctorId, prescriber: c.prescriberName, tracked: c.trackingEnabled, pct: t ? pct(t.taken, t.total) : null, isNew: !t };
      }),
    perDoctor: [...byDoctor.entries()].map(([doctor, t]) => ({ doctor, pct: pct(t.taken, t.total) })),
    mostMissedSlot: worstSlot && worstSlot[1] > 0 ? { slot: worstSlot[0], misses: worstSlot[1] } : null,
  };
}

module.exports = { doseMinute, MEALS, raiseAlert, checkReading, careConversation, ensureParticipant, postMessage, markRead, ensureDoses, adherence, effectiveStatus };

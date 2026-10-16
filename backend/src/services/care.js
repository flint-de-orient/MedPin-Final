// Alerts, care conversations and medicine adherence.
const M = require('../models');
const T = require('../lib/time');
const { notify, clinicians, signal, deskFor, assistantsOf, patientPlace } = require('./notify');

// ── Alerts ────────────────────────────────────────────────

async function raiseAlert({ practiceId, patientId, doctorId, severity, kind, title, detail, sourceModel, sourceId, conversationId }) {
  const alert = await M.Alert.create({ practiceId, patientId, doctorId, severity, kind, title, detail, sourceModel, sourceId, conversationId });
  // Clinical alerts reach the patient's own doctors (the one named, plus the care team) and
  // their assistants (who see Clinical alerts) — never the front desk: a home reading or a
  // lab value is the doctor's to judge.
  const doctors = await clinicians(practiceId, patientId, { doctorId });
  const team = [...new Set([...doctors, ...(await assistantsOf(practiceId, doctors))].map(String))];
  const patient = await M.Patient.findById(patientId, 'name');
  const name = patient?.name || 'patient';
  await notify(team, {
    type: `alert_${severity}`, practiceId, push: severity !== 'watch',
    title: `${severity === 'emergency' ? 'Emergency' : severity === 'urgent' ? 'Urgent' : 'Watch'}: ${name}`,
    body: detail, screen: 'Alerts', params: { alertId: alert._id, patientId, ...(conversationId ? { conversationId } : {}) },
  });
  // The patient asked for help (urgent chat): the front desk covering them hears too — they
  // answer the clinic phone and can interrupt the doctor. They open the chat (not the
  // clinical alerts), call the patient and note that the doctor was told.
  if (kind === 'urgent_chat') {
    const place = await patientPlace(practiceId, patientId);
    const desk = (await deskFor(practiceId, { locationId: place.locationId, doctorId: doctorId || place.doctorId })).map(String).filter((id) => !team.includes(id));
    if (desk.length) {
      await notify(desk, {
        type: 'urgent_chat', practiceId, title: `Urgent: ${name} needs help`, body: detail,
        screen: 'Patient-Thread', params: { alertId: alert._id, patientId, ...(conversationId ? { conversationId } : {}) },
      });
    }
  }
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
/** The thread's preview line ("Dr. Sen: hello") for a message. */
function previewOf(msg, senderName) {
  return {
    text: msg.text || (msg.kind === 'voice' ? 'Voice message' : msg.kind === 'record' ? 'Shared a record' : 'Attachment'),
    senderType: msg.senderType,
    senderId: msg.senderId?._id || msg.senderId,
    senderLabel: SENDER_LABEL[msg.senderType] || shortName(senderName) || 'Clinic',
    at: msg.createdAt,
  };
}

const idOf = (x) => (x?._id || x ? String(x?._id || x) : null);
const STAFF_ROLES = ['doctor', 'front_desk', 'practice_manager', 'doctor_assistant', 'dietician'];

/**
 * Who signs an automatic note: the person who did it (a doctor or staff member
 * booking, collecting, cancelling); otherwise (the patient booked or paid in the
 * app, a background job) someone at the desk covering that visit's location and
 * doctor — the one who last wrote in this patient's chat, else the one most
 * recently in the app — and in a clinic without a front desk, the visit's doctor
 * (else the patient's main doctor here). Returns a Member (userId, role) or null.
 */
async function noteSender({ practiceId, patientId, locationId, doctorId, by }, convo) {
  const patient = await M.Patient.findById(patientId, 'userId');
  const notPatient = (id) => Boolean(id) && String(id) !== String(patient?.userId || '');
  if (notPatient(idOf(by))) {
    const m = await M.Member.findOne({ practiceId, userId: idOf(by), status: 'active', role: { $in: STAFF_ROLES } }, 'userId role');
    if (m) return m;
  }
  const desk = (await deskFor(practiceId, { locationId: idOf(locationId) || undefined, doctorId: idOf(doctorId) || undefined })).map(String).filter(notPatient);
  let pick = null;
  if (desk.length === 1) pick = desk[0];
  else if (desk.length > 1) {
    const wrote = await M.Message.findOne({ conversationId: convo._id, senderId: { $in: desk }, 'meta.auto': { $ne: true } }, 'senderId').sort({ createdAt: -1 });
    if (wrote) pick = String(wrote.senderId);
    else {
      const users = await M.User.find({ _id: { $in: desk } }, 'lastActiveAt');
      users.sort((a, b) => (b.lastActiveAt || 0) - (a.lastActiveAt || 0) || String(a._id).localeCompare(String(b._id)));
      pick = String(users[0]?._id || desk[0]);
    }
  }
  if (!pick && notPatient(idOf(doctorId))) pick = idOf(doctorId);
  if (!pick) {
    const team = await M.CareTeamAccess.findOne({ practiceId, patientId, isPrimary: true }, 'userId');
    if (notPatient(team?.userId)) pick = String(team.userId);
  }
  return pick ? M.Member.findOne({ practiceId, userId: pick, status: 'active' }, 'userId role') : null;
}

/**
 * A note from the clinic in the patient's chat: the visit booked / confirmed /
 * moved / cancelled, the fee paid or refunded — so the chat is the patient's
 * full record of what happened. It is sent from a real person's account (see
 * noteSender) and marked automatic (meta.auto). The notification for the same
 * event is sent separately, so this doesn't notify again: only the patient's
 * unread count goes up, and open chats refresh at once. With nobody to sign it,
 * it is a plain clinic line (senderType system), as before.
 *
 * @param ctx {practiceId, patientId, locationId?, doctorId?, by?} — an appointment works too
 */
async function chatNote(ctx, text, event, extraMeta = {}) {
  const practiceId = idOf(ctx?.practiceId);
  const patientId = idOf(ctx?.patientId);
  if (!practiceId || !patientId || !text) return null;
  try {
    let convo = await careConversation(patientId, practiceId);
    const sender = await noteSender({ practiceId, patientId, locationId: ctx.locationId, doctorId: ctx.doctorId, by: ctx.by }, convo).catch((err) => {
      console.warn('[chat note sender]', err.message);
      return null;
    });
    let user = null;
    if (sender) {
      convo = await ensureParticipant(convo, sender.userId, sender.role === 'doctor' ? 'doctor' : sender.role === 'dietician' ? 'dietician' : 'staff');
      user = await M.User.findById(sender.userId, 'name');
    }
    const msg = await M.Message.create({
      conversationId: convo._id, kind: 'text', text, meta: { ...extraMeta, event, auto: true },
      ...(sender ? { senderId: sender.userId, senderType: sender.role === 'doctor' ? 'doctor' : 'staff' } : { senderType: 'system' }),
    });
    convo.lastMessage = previewOf(msg, user?.name);
    for (const p of convo.participants) if (p.role === 'patient') p.unreadCount = (p.unreadCount || 0) + 1;
    await convo.save();
    await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
    return msg;
  } catch (err) {
    console.warn('[chat note]', err.message);
    return null;
  }
}

/**
 * "Send payment link": the request also goes into the patient's clinic chat, from whoever
 * sent it, as a card with Pay (patient) / Paid (everyone) — not only a notification.
 * Asked again within 12 h: no second card (the notification is re-sent instead).
 * Returns the conversation id (the notification opens that chat).
 */
async function paymentRequestNote(payment, { by } = {}) {
  const appt = payment.appointmentId ? await M.Appointment.findById(payment.appointmentId, 'practiceId locationId doctorId patientId startAt') : null;
  const practiceId = appt?.practiceId || payment.practiceId;
  const patientId = appt?.patientId || payment.patientId;
  if (!practiceId || !patientId) return null;
  const convo = await careConversation(patientId, practiceId);
  const recent = await M.Message.exists({ conversationId: convo._id, 'meta.event': 'payment_request', 'meta.paymentId': String(payment._id), createdAt: { $gte: new Date(Date.now() - 12 * 3600e3) } });
  if (recent) return convo._id;
  const when = appt?.startAt ? ` for your visit on ${T.dayKey(appt.startAt)}, ${T.fmtTime(T.minuteOfDay(appt.startAt))}` : ' for your visit';
  await chatNote(
    { practiceId, patientId, locationId: appt?.locationId, doctorId: appt?.doctorId, by },
    `Please pay ₹${payment.amount}${when}. Tap Pay to pay in the app, or pay at the clinic.`,
    'payment_request',
    { paymentId: String(payment._id), appointmentId: appt?._id ? String(appt._id) : null },
  );
  return convo._id;
}

/**
 * After a message is deleted for everyone: the thread's preview becomes the
 * newest message still there, and people who hadn't read it lose its unread
 * count. Everyone in the thread is told, so open chats update at once.
 */
async function messageDeleted(convo, msg) {
  const latest = await M.Message.findOne({ conversationId: convo._id, deletedForEveryoneAt: null }).sort({ createdAt: -1 }).populate('senderId', 'name');
  convo.lastMessage = latest ? previewOf(latest, latest.senderId?.name) : undefined;
  for (const p of convo.participants) {
    if (String(p.userId) !== String(msg.senderId) && p.unreadCount > 0 && (!p.lastReadAt || p.lastReadAt < msg.createdAt)) p.unreadCount -= 1;
  }
  await convo.save();
  await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
}

/**
 * [quietForStaff]: the staff aren't notified here because the caller tells them
 * itself (Patient-Emergency raises an alert that reaches the doctor and the desk).
 */
async function postMessage(convo, { sender, senderType, text, kind = 'text', quietForStaff = false, ...rest }) {
  const msg = await M.Message.create({ conversationId: convo._id, senderId: sender?._id, senderType, text, kind, ...rest });
  const senderId = sender ? String(sender._id) : null;
  convo.lastMessage = previewOf(msg, sender?.name);
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
  let toDesk = [];
  let deskOpen = false;
  if (senderType === 'patient' && convo.type === 'care' && !quietForStaff) {
    // The clinic's shared inbox: the front desk covering this patient (their branch and
    // doctor) hears about it too — they answer most messages (visits, fees, reports).
    const place = await patientPlace(convo.practiceId, convo.patientId);
    toDesk = (await deskFor(convo.practiceId, place)).map(String).filter((id) => id !== senderId && !toStaff.map(String).includes(id));
    deskOpen = toDesk.length > 0 && (await openNow(place?.locationId));
  }
  if (quietForStaff) toStaff = [];
  const staffTitle = rest.isUrgent ? `Urgent message from ${convo.lastMessage.senderLabel}` : `New message from ${convo.lastMessage.senderLabel}`;
  const staffNotice = { ...base, title: staffTitle, screen: 'Patient-Thread', params: { conversationId: convo._id } };
  let toldStaff = [];
  if (senderType === 'patient' && !rest.isUrgent) {
    // Routine patient messages (a doctor may have thousands of patients):
    //  - doctors: no push and no bell item; the Messages badge shows it. Only a doctor who is in
    //    the middle of this conversation (wrote here in the last 2 h) gets a push for the reply.
    //    A doctor with no front desk gets a summary every 2 h in reply hours (jobs.chatRollup).
    //  - front desk: a push while their clinic is open, otherwise it waits in their bell;
    //    several messages in a row from one patient stay one notice.
    const since = new Date(Date.now() - 2 * 3600e3);
    const active = toStaff.length
      ? (await M.Message.distinct('senderId', { conversationId: convo._id, senderId: { $in: toStaff }, 'meta.auto': { $ne: true }, createdAt: { $gte: since } })).map(String)
      : [];
    const activeDocs = toStaff.map(String).filter((id) => active.includes(id));
    if (activeDocs.length) toldStaff.push(...(await chatNotice(activeDocs, staffNotice, convo._id)));
    if (toDesk.length) toldStaff.push(...(await chatNotice(toDesk, staffNotice, convo._id, { push: deskOpen })));
  } else {
    // Urgent messages, and staff writing to staff: everyone named, at once.
    if (toStaff.length) await notify(toStaff, staffNotice);
    if (toDesk.length) await notify(toDesk, staffNotice);
    toldStaff = [...toStaff, ...toDesk];
  }
  if (toPatient.length) {
    // The patient is waiting for the clinic's answer: always told (a quick burst of replies is one notice).
    await chatNotice(toPatient.map(String), { ...base, title: `New message from ${convo.lastMessage.senderLabel}`, screen: 'Patient-DoctorChat', params: { conversationId: convo._id } }, convo._id);
  }
  if (senderType !== 'patient' && senderType !== 'system' && senderId) {
    // Someone at the clinic answered: the others' "new message" notices for this chat are done.
    await settleChatNotices(convo, senderId);
  }
  // Everyone else in the thread (staff who weren't notified, the sender's other phone): refresh now.
  const told = new Set([...toPatient, ...toldStaff].map(String));
  await signal(convo.participants.map((p) => p.userId).filter((id) => !told.has(String(id))), { type: 'chat_changed', conversationId: convo._id });
  if (senderType === 'patient') await awayReply(convo).catch(() => {});
  return msg;
}

/** Is a clinic location open now (its weekly hours, 30 min either side for the desk arriving / closing up)? */
async function openNow(locationId) {
  if (!locationId) return true; // no branch known: treat as open (better a push than a missed message)
  const loc = await M.Location.findById(locationId, 'weeklyHours');
  if (!loc?.weeklyHours?.length) return true; // hours never set: open
  const h = loc.weeklyHours.find((d) => d.weekday === T.weekday(new Date()));
  if (!h || !h.isOpen || h.opensAt == null || h.closesAt == null) return false;
  const now = T.minuteOfDay(new Date());
  return now >= h.opensAt - 30 && now <= h.closesAt + 30;
}

/**
 * One "new message" notice per person per chat: while they still have an unread one
 * for this conversation from the last 10 minutes it is updated (latest text, no new
 * buzz); otherwise a new one is sent (push unless [push] is false). Returns the ids told.
 */
async function chatNotice(ids, n, conversationId, { push = true } = {}) {
  if (!ids.length) return [];
  const recent = await M.Notification.find(
    { userId: { $in: ids }, readAt: null, type: n.type, 'params.conversationId': conversationId, createdAt: { $gte: new Date(Date.now() - 10 * 60e3) } },
    'userId',
  );
  const quiet = new Set(recent.map((x) => String(x.userId)));
  if (quiet.size) {
    await M.Notification.updateMany({ _id: { $in: recent.map((x) => x._id) } }, { body: n.body });
    await signal([...quiet], { type: 'notifications_changed', ...(n.practiceId ? { practiceId: String(n.practiceId) } : {}) });
  }
  const fresh = ids.filter((id) => !quiet.has(String(id)));
  if (fresh.length) {
    // An older unread notice for this chat is replaced by the new one (the bell keeps one per chat).
    await M.Notification.deleteMany({ userId: { $in: fresh }, readAt: null, type: n.type, 'params.conversationId': conversationId });
    await notify(fresh, push ? n : { ...n, push: false });
  }
  return ids;
}

/** A reply from the clinic: everyone else's unread "new message" notices for that chat are read. */
async function settleChatNotices(convo, byUserId) {
  const q = { readAt: null, type: 'message', 'params.conversationId': convo._id, userId: { $ne: byUserId } };
  const users = await M.Notification.distinct('userId', q);
  if (!users.length) return;
  const patientUsers = convo.participants.filter((p) => p.role === 'patient').map((p) => String(p.userId));
  const staff = users.map(String).filter((id) => !patientUsers.includes(id));
  if (!staff.length) return;
  await M.Notification.updateMany({ ...q, userId: { $in: staff } }, { readAt: new Date() });
  await signal(staff, { type: 'notifications_changed', ...(convo.practiceId ? { practiceId: String(convo.practiceId) } : {}) });
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
  // One dose per medicine, day and slot. A dose is matched by that, not by its
  // exact time, so changing meal times (or a medicine's food timing) moves the
  // dose instead of adding a second one; duplicates left by older versions merge.
  const want = new Map(); // key → { course, slot, scheduledAt }
  for (let day = start; day <= end; day = T.addDays(day, 1)) {
    for (const c of courses) {
      if (c.startDate > day || (c.endDate && c.endDate < day) || (c.stoppedAt && c.stoppedAt < day)) continue;
      // "When needed" (e.g. paracetamol for fever): no set times — no alarm, never a missed dose.
      if (c.frequency === 'as_needed') continue;
      // Weekly: on its day; without one set, the weekday it started.
      if (c.frequency === 'weekly' && (c.weekday || T.weekday(c.startDate)) !== T.weekday(day)) continue;
      for (const slot of SLOTS) {
        if (!(c.dose?.[slot] > 0)) continue;
        want.set(`${c._id}|${T.dayKey(day)}|${slot}`, { course: c, slot, scheduledAt: T.atMinute(day, doseMinute(patient.settings, slot, c.foodRelation)) });
      }
    }
  }
  const existing = await M.DoseLog.find({ patientId: patient._id, scheduledAt: { $gte: start, $lt: T.addDays(end, 1) } }).sort({ scheduledAt: 1 });
  const groups = new Map();
  for (const d of existing) {
    const key = `${d.courseId}|${T.dayKey(d.scheduledAt)}|${d.slot}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(d);
  }
  const now = new Date();
  const drop = [];
  const moves = [];
  const inserts = [];
  for (const [key, w] of want) {
    const list = groups.get(key) || [];
    groups.delete(key);
    if (!list.length) {
      inserts.push({ courseId: w.course._id, patientId: patient._id, scheduledAt: w.scheduledAt, slot: w.slot, status: 'due' });
      continue;
    }
    // Keep the one the patient marked (taken / skipped), else the first; the rest are duplicates.
    const keep = list.find((d) => d.status === 'taken') || list.find((d) => d.status !== 'due') || list[0];
    for (const d of list) if (d !== keep) drop.push(d._id);
    if (keep.status === 'due' && keep.scheduledAt.getTime() !== w.scheduledAt.getTime()) moves.push({ id: keep._id, scheduledAt: w.scheduledAt });
  }
  // Doses no longer in the schedule (medicine stopped, dose or slot changed): future, unmarked ones go.
  // A "when needed" medicine never had a schedule: its unmarked doses go whatever the date (they
  // were never missed); the ones the patient marked taken stay.
  const asNeeded = new Set((await M.MedicationCourse.find({ patientId: patient._id, frequency: 'as_needed' }, '_id')).map((c) => String(c._id)));
  for (const list of groups.values()) {
    for (const d of list) {
      if (asNeeded.has(String(d.courseId)) ? d.status !== 'taken' : d.status === 'due' && d.scheduledAt > now) drop.push(d._id);
    }
  }
  if (drop.length) await M.DoseLog.deleteMany({ _id: { $in: drop } });
  for (const m of moves) await M.DoseLog.updateOne({ _id: m.id }, { scheduledAt: m.scheduledAt }).catch(() => {});
  if (inserts.length) await M.DoseLog.insertMany(inserts, { ordered: false }).catch(() => {});
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
  const visible = acc ? allCourses.filter((c) => acc.courseVisible(c)) : allCourses;
  // "When needed" medicines aren't on a schedule, so they don't count for or against.
  const courses = visible.filter((c) => c.frequency !== 'as_needed');
  const doses = await M.DoseLog.find({ patientId: patient._id, courseId: { $in: courses.map((c) => c._id) }, scheduledAt: { $gte: from, $lte: now } });
  const courseById = new Map(courses.map((c) => [String(c._id), c]));
  const pct = (taken, total) => (total ? Math.round((taken / total) * 100) : null);
  const tally = () => ({ taken: 0, total: 0, since: null });
  // A percentage of a few doses misleads ("100%" on day 2): until there are 6, show "2 of 2 doses".
  const ENOUGH = 6;
  const view = (t) => (t ? { pct: pct(t.taken, t.total), taken: t.taken, total: t.total, since: t.since, enough: t.total >= ENOUGH } : null);
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
      if (!t.since || d.scheduledAt < t.since) t.since = d.scheduledAt;
    }
    if (s !== 'taken') missesBySlot[d.slot] += 1;
  }
  const worstSlot = Object.entries(missesBySlot).sort((a, b) => b[1] - a[1])[0];
  return {
    days,
    overallPct: pct(overall.taken, overall.total),
    overall: view(overall.total ? overall : null),
    perMedicine: visible
      .filter((c) => c.status === 'active')
      .map((c) => {
        const t = byCourse.get(String(c._id));
        const asNeeded = c.frequency === 'as_needed';
        return {
          courseId: c._id, name: c.name, strength: c.strength, doctorId: c.doctorId, prescriber: c.prescriberName, tracked: c.trackingEnabled, asNeeded,
          pct: t ? pct(t.taken, t.total) : null, isNew: !t && !asNeeded, ...(t ? { taken: t.taken, total: t.total, since: t.since, enough: t.total >= ENOUGH } : {}),
        };
      }),
    perDoctor: [...byDoctor.entries()].map(([doctor, t]) => ({ doctor, ...view(t) })),
    mostMissedSlot: worstSlot && worstSlot[1] > 0 ? { slot: worstSlot[0], misses: worstSlot[1] } : null,
  };
}

module.exports = {
  openNow,
  paymentRequestNote, chatNote, shortName, doseMinute, MEALS, raiseAlert, checkReading, careConversation, ensureParticipant, postMessage, messageDeleted, markRead, ensureDoses, adherence, effectiveStatus };

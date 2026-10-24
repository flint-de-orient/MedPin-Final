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

const DEFAULT_LIMITS = { bpSystolicMax: 160, bpDiastolicMax: 100, sugarFastingMax: 250, sugarRandomMax: 300, pulseMin: 45, pulseMax: 120, spo2Min: 92 };

/** What is wrong with a reading (for the clinic's alert) and what the patient should do now. */
function readingFindings(vitals, patient) {
  const L = { ...DEFAULT_LIMITS, ...(patient.alertLimits?.toObject ? patient.alertLimits.toObject() : patient.alertLimits || {}) };
  for (const k of Object.keys(L)) if (L[k] == null) L[k] = DEFAULT_LIMITS[k];
  const out = [];
  if (vitals.bpSystolic && (vitals.bpSystolic >= L.bpSystolicMax || vitals.bpDiastolic >= L.bpDiastolicMax)) {
    const severe = vitals.bpSystolic >= 180 || vitals.bpDiastolic >= 120;
    out.push({ severity: severe ? 'emergency' : 'urgent', detail: `Home BP reading ${vitals.bpSystolic}/${vitals.bpDiastolic} mmHg, above the alert limit.`, advice: severe ? 'bp_severe' : 'high' });
  }
  if (vitals.spo2 && vitals.spo2 < L.spo2Min) out.push({ severity: vitals.spo2 < 88 ? 'emergency' : 'urgent', detail: `SpO₂ ${vitals.spo2}%, below ${L.spo2Min}%.`, advice: vitals.spo2 < 88 ? 'emergency' : 'high' });
  if (vitals.pulse && (vitals.pulse < L.pulseMin || vitals.pulse > L.pulseMax)) {
    const severe = vitals.pulse < 40 || vitals.pulse > 150;
    out.push({ severity: severe ? 'emergency' : 'watch', detail: `Heart rate ${vitals.pulse} bpm, outside ${L.pulseMin}–${L.pulseMax}.`, advice: severe ? 'emergency' : 'recheck' });
  }
  const sugar = vitals.bloodSugar;
  if (sugar && sugar >= 400) {
    // Very high whenever it was taken (risk of DKA / a hyperglycaemic emergency).
    const detail = vitals.sugarType === 'fasting' ? `Very high blood sugar ${sugar} mg/dL (fasting).`
      : vitals.sugarType === 'post_meal' ? `Very high blood sugar ${sugar} mg/dL (post-meal).` : `Very high blood sugar ${sugar} mg/dL.`;
    out.push({ severity: 'emergency', detail, advice: 'sugar_very_high' });
  } else if (sugar && vitals.sugarType === 'fasting' && sugar >= L.sugarFastingMax) {
    out.push({ severity: 'urgent', detail: `Fasting sugar ${sugar} mg/dL.`, advice: 'high' });
  } else if (sugar && vitals.sugarType !== 'fasting' && sugar >= L.sugarRandomMax) {
    out.push({ severity: 'urgent', detail: vitals.sugarType === 'post_meal' ? `After-meal sugar ${sugar} mg/dL.` : `Random sugar ${sugar} mg/dL.`, advice: 'high' });
  }
  if (sugar && sugar < 70) out.push({ severity: sugar < 54 ? 'emergency' : 'urgent', detail: `Low blood sugar ${sugar} mg/dL.`, advice: 'sugar_low' });
  return out;
}

// What the patient is told at once (the app shows it; Bengali / Hindi in the app's word lists).
const PATIENT_ADVICE = {
  sugar_low: 'Low sugar: take 3 teaspoons of sugar or glucose in water, or a sweet drink, now. Check again in 15 minutes. If you feel faint or confused, call 108.',
  sugar_very_high: 'Your sugar is very high. Drink water and check again. If you feel very thirsty, sleepy, are vomiting or breathing fast, call 108 or go to the nearest emergency now.',
  bp_severe: 'Your BP is very high. Sit and rest for 5 minutes, then check again. If you have chest pain, a bad headache, weakness or trouble speaking or seeing, call 108 now.',
  emergency: 'This reading is dangerous. If you feel unwell, call 108 or go to the nearest emergency now.',
  high: 'This reading is high. Rest, check again later today, and contact your clinic if it stays high.',
  recheck: 'This reading is outside your usual range. Rest and check again.',
};
const RANK = { watch: 1, urgent: 2, emergency: 3 };
/** The most serious finding, as the patient's message ({ severity, advice } or null). */
function patientAdvice(findings) {
  if (!findings.length) return null;
  const worst = [...findings].sort((a, b) => RANK[b.severity] - RANK[a.severity])[0];
  // Low sugar is acted on first whatever else is off (it is the one that can't wait).
  const low = findings.find((f) => f.advice === 'sugar_low');
  const pick = low && RANK[low.severity] >= RANK[worst.severity] - 1 ? low : worst;
  return { severity: worst.severity, advice: PATIENT_ADVICE[pick.advice] || PATIENT_ADVICE.recheck };
}

/** Raises alerts for a home reading outside the patient's limits, in every linked practice. */
async function checkReading(vitals, patient, findings = readingFindings(vitals, patient)) {
  const out = findings.map(({ severity, detail }) => ({ severity, detail }));
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

/** Adds a user to a thread if they aren't in it yet (atomic: never overwrites someone else's change). */
async function ensureParticipant(convo, userId, role) {
  if (convo.participants.some((p) => String(p.userId) === String(userId))) return convo;
  await addParticipants(convo._id, [{ userId, role }]);
  return (await M.Conversation.findById(convo._id)) || convo;
}

/** Adds the people not yet in the thread, one atomic update each. */
async function addParticipants(convoId, people) {
  for (const p of people) {
    await M.Conversation.updateOne({ _id: convoId, 'participants.userId': { $ne: p.userId } }, { $push: { participants: p } });
  }
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
    await M.Conversation.updateOne(
      { _id: convo._id },
      { $set: { lastMessage: previewOf(msg, user?.name) }, $inc: { 'participants.$[p].unreadCount': 1 } },
      { arrayFilters: [{ 'p.role': 'patient' }] },
    );
    // Done by someone at the clinic (the desk booked the visit, took the fee, sent the payment
    // request): the patient's message has been acted on, so it no longer "Needs attention".
    // A note with nobody behind it (a fee paid online) leaves it as it is.
    if (ctx.by && (await M.Member.exists({ practiceId, userId: idOf(ctx.by), status: 'active' }))) {
      await M.Conversation.updateOne({ _id: convo._id, triage: 'needs_attention' }, { $unset: { triage: 1 } });
    }
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
  // Who it raised an unread for (an automatic note: only the patient), and who hasn't read it yet.
  const raised = convo.participants
    .filter((p) => String(p.userId) !== String(msg.senderId) && (!msg.meta?.auto || p.role === 'patient') && (!p.lastReadAt || p.lastReadAt < msg.createdAt))
    .map((p) => p.userId);
  await M.Conversation.updateOne(
    { _id: convo._id },
    { ...(latest ? { $set: { lastMessage: previewOf(latest, latest.senderId?.name) } } : { $unset: { lastMessage: 1 } }), $inc: { 'participants.$[p].unreadCount': -1 } },
    { arrayFilters: [{ 'p.userId': { $in: raised }, 'p.unreadCount': { $gt: 0 } }] },
  );
  // The bell no longer shows what was deleted.
  if (msg.text) {
    await M.Notification.updateMany({ 'params.conversationId': { $in: [convo._id, String(convo._id)] }, body: msg.text.slice(0, 120) }, { body: 'Message deleted' });
  }
  await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
  await signal(convo.participants.map((p) => p.userId), { type: 'notifications_changed', ...(convo.practiceId ? { practiceId: String(convo.practiceId) } : {}) });
}

/**
 * [quietForStaff]: the staff aren't notified here because the caller tells them
 * itself (Patient-Emergency raises an alert that reaches the doctor and the desk).
 */
async function postMessage(convo, { sender, senderType, text, kind = 'text', quietForStaff = false, ...rest }) {
  // Only a patient can mark their message urgent (it is their emergency); staff messages never are.
  const urgent = senderType === 'patient' && rest.isUrgent === true;
  const msg = await M.Message.create({ conversationId: convo._id, senderId: sender?._id, senderType, text, kind, ...rest, isUrgent: urgent });
  const senderId = sender ? String(sender._id) : null;
  // One atomic update: the preview, everyone else's unread +1, the urgent / needs-attention marks.
  // (Saving the whole thread from an older copy could undo a read or a new participant.)
  const set = { lastMessage: previewOf(msg, sender?.name) };
  if (urgent && !convo.isUrgent) Object.assign(set, { isUrgent: true, urgentSince: new Date() });
  if (senderType === 'patient' && !convo.triage) set.triage = 'needs_attention';
  await M.Conversation.updateOne(
    { _id: convo._id },
    { $set: set, $inc: { 'participants.$[p].unreadCount': 1 } },
    { arrayFilters: [{ 'p.userId': { $ne: sender?._id || null } }] },
  );
  const lastMessage = set.lastMessage;
  let toStaff = [];
  if (senderType === 'patient') {
    // The patient's own clinicians hear about it (dietician for nutrition threads); the front
    // desk sees it in their inbox. Clinicians who joined later are added to the thread now.
    toStaff = await clinicians(convo.practiceId, convo.patientId, { roles: convo.type === 'nutrition' ? ['dietician', 'doctor'] : ['doctor'] });
    const missing = toStaff.filter((id) => !convo.participants.some((p) => String(p.userId) === String(id)));
    if (missing.length) {
      const roles = new Map((await M.Member.find({ practiceId: convo.practiceId, userId: { $in: missing } }, 'userId role')).map((m) => [String(m.userId), m.role]));
      await addParticipants(convo._id, missing.map((id) => ({ userId: id, role: roles.get(String(id)) === 'dietician' ? 'dietician' : 'doctor', unreadCount: 1 })));
    }
  }
  // The thread as it is now (for who to tell).
  convo = (await M.Conversation.findById(convo._id)) || convo;
  // An urgent message from the patient always has an open emergency behind it (so the doctor
  // can resolve it and the thread isn't left marked urgent with nothing to act on).
  let alertRaised = false;
  if (urgent && !quietForStaff) {
    const open = await M.Alert.exists({ conversationId: convo._id, kind: 'urgent_chat', status: { $in: ['open', 'acknowledged'] } });
    if (!open) {
      alertRaised = true;
      await raiseAlert({
        practiceId: convo.practiceId, patientId: convo.patientId, severity: 'emergency', kind: 'urgent_chat',
        detail: (text || 'Urgent message').slice(0, 300), sourceModel: 'Message', sourceId: msg._id, conversationId: convo._id,
      }).catch((err) => console.warn('[urgent alert]', err.message));
    }
  }
  const toPatient = convo.participants.filter((p) => p.role === 'patient' && String(p.userId) !== senderId).map((p) => p.userId);
  const base = { type: urgent ? 'urgent_message' : 'message', practiceId: convo.practiceId, body: (text || (kind === 'voice' ? 'Voice message' : kind === 'attachment' ? 'Photo or file' : '')).slice(0, 120) };
  let toDesk = [];
  let deskOpen = false;
  if (senderType === 'patient' && !quietForStaff) {
    const place = await patientPlace(convo.practiceId, convo.patientId);
    if (convo.type === 'care') {
      // The clinic's shared inbox: the front desk covering this patient (their branch and
      // doctor) hears about it too — they answer most messages (visits, fees, reports).
      toDesk = (await deskFor(convo.practiceId, place)).map(String).filter((id) => id !== senderId && !toStaff.map(String).includes(id));
      // Desk staff who joined after the chat began: in it now, with this message unread.
      const newDesk = toDesk.filter((id) => !convo.participants.some((p) => String(p.userId) === id));
      if (newDesk.length) await addParticipants(convo._id, newDesk.map((id) => ({ userId: id, role: 'staff', unreadCount: 1 })));
    } else if (convo.type === 'nutrition') {
      // Nutrition chats are the dietician's inbox, as care chats are the desk's: one notice
      // per chat, pushed in clinic hours. Doctors on the thread follow the doctor rule.
      const diet = new Set((await M.Member.find({ practiceId: convo.practiceId, status: 'active', role: 'dietician', userId: { $in: toStaff } }, 'userId')).map((m) => String(m.userId)));
      toDesk = toStaff.map(String).filter((id) => diet.has(id));
      toStaff = toStaff.filter((id) => !diet.has(String(id)));
    }
    deskOpen = toDesk.length > 0 && (await openNow(place?.locationId));
  }
  if (quietForStaff) toStaff = [];
  const staffTitle = urgent ? `Urgent message from ${lastMessage.senderLabel}` : `New message from ${lastMessage.senderLabel}`;
  const staffNotice = { ...base, title: staffTitle, screen: 'Patient-Thread', params: { conversationId: convo._id } };
  let toldStaff = [];
  if (convo.type === 'direct' && senderId) {
    // A colleague's message: the others in the chat are told at once (one notice per chat).
    const others = convo.participants.map((p) => String(p.userId)).filter((id) => id !== senderId);
    toldStaff.push(...(await chatNotice(others, staffNotice, convo._id)));
  } else if (senderType === 'patient' && !urgent) {
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
    // No front desk for this patient (their branch has none): the doctors' bell keeps one quiet
    // item per chat (no buzz), so the message isn't only a badge count until the roll-up.
    if (!toDesk.length && convo.type === 'care') {
      const quiet = toStaff.map(String).filter((id) => !activeDocs.includes(id));
      if (quiet.length) toldStaff.push(...(await chatNotice(quiet, staffNotice, convo._id, { push: false })));
    }
  } else {
    // Urgent: a new emergency was just raised (its alert already told the doctor and the desk);
    // follow-ups while it is open: one notice per chat, pushed at once.
    const everyone = [...toStaff, ...toDesk].map(String);
    if (!alertRaised && everyone.length) await chatNotice(everyone, staffNotice, convo._id);
    toldStaff = everyone;
  }
  if (toPatient.length) {
    // The patient is waiting for the clinic's answer: always told (a quick burst of replies is one notice).
    await chatNotice(toPatient.map(String), {
      ...base, title: `New message from ${lastMessage.senderLabel}`, screen: 'Patient-DoctorChat',
      params: { conversationId: convo._id, ...(senderType === 'doctor' && senderId ? { doctorId: senderId } : {}) },
    }, convo._id);
  }
  if (senderType !== 'patient' && senderType !== 'system' && senderId) {
    // Someone at the clinic answered: the others' "new message" notices for this chat are done.
    await settleChatNotices(convo, senderId);
  }
  // Everyone else in the thread (staff who weren't notified, the sender's other phone): refresh now.
  const told = new Set([...toPatient, ...toldStaff].map(String));
  await signal(convo.participants.map((p) => p.userId).filter((id) => !told.has(String(id))), { type: 'chat_changed', conversationId: convo._id });
  // The patient wrote again: a chat marked "Handled" is open again.
  if (senderType === 'patient' && convo.handledAt) await M.Conversation.updateOne({ _id: convo._id }, { $unset: { handledAt: 1, handledBy: 1 } });
  if (senderType === 'patient') await awayReply(convo, msg).catch(() => {});
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
const URGENT_AWAY = 'The clinic is closed now. If this is an emergency, call 108 or go to the nearest emergency department. Your doctor has been told.';

async function awayReply(convo, patientMsg) {
  // Urgent (marked, or emergency words): not the routine "I'll reply in the morning" but
  // what to do now — the urgent alert already went to the doctor.
  const urgent = Boolean(patientMsg?.isUrgent || require('./assistant').isEmergencyText(patientMsg?.text || ''));
  const team = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, isPrimary: true });
  const profile = team && (await M.DoctorProfile.findOne({ userId: team.userId }, 'chatSettings displayName'));
  const cs = profile?.chatSettings;
  if (!cs?.awayMessage || !cs.replyHours?.from || !cs.replyHours?.to) return;
  const now = T.minuteOfDay(new Date());
  const from = T.hhmmToMin(cs.replyHours.from);
  const to = T.hhmmToMin(cs.replyHours.to);
  const inHours = from <= to ? now >= from && now < to : now >= from || now < to;
  if (inHours) return;
  const recent = await M.Message.exists({ conversationId: convo._id, senderType: 'system', 'meta.away': true, ...(urgent ? { 'meta.urgent': true } : {}), createdAt: { $gte: new Date(Date.now() - 12 * 3600e3) } });
  if (recent) return;
  const msg = await M.Message.create({ conversationId: convo._id, senderType: 'system', kind: 'text', text: urgent ? URGENT_AWAY : cs.awayMessage, meta: { away: true, ...(urgent ? { urgent: true } : {}) } });
  await M.Conversation.updateOne(
    { _id: convo._id },
    { $set: { lastMessage: previewOf(msg, null) }, $inc: { 'participants.$[p].unreadCount': 1 } },
    { arrayFilters: [{ 'p.role': 'patient' }] },
  );
  await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
}

/** Marks a thread read for one user. */
async function markRead(convo, userId) {
  const p = convo.participants.find((x) => String(x.userId) === String(userId));
  if (!p) return convo;
  const now = new Date();
  await M.Conversation.updateOne(
    { _id: convo._id },
    { $set: { 'participants.$[p].unreadCount': 0, 'participants.$[p].lastReadAt': now } },
    { arrayFilters: [{ 'p.userId': p.userId }] },
  );
  p.unreadCount = 0;
  p.lastReadAt = now;
  // "Seen" belongs to the other side: the patient reading marks the clinic's (and MedPin AI's)
  // messages; someone at the clinic reading marks the patient's — never a colleague's reply to
  // the patient. In a chat between colleagues, the other person's messages.
  const isPatient = p.role === 'patient';
  const side = convo.type === 'direct' ? {} : { senderType: isPatient ? { $ne: 'patient' } : 'patient' };
  const seen = await M.Message.updateMany(
    { conversationId: convo._id, senderId: { $ne: userId }, ...side, deliveryStatus: { $ne: 'seen' }, createdAt: { $lte: now } },
    { deliveryStatus: 'seen', seenAt: now },
  );
  // This chat's "new message" notices for the reader are done: the bell clears, and the next
  // message buzzes again instead of only updating an old unread notice.
  const read = await M.Notification.updateMany(
    { userId, readAt: null, type: { $in: ['message', 'urgent_message'] }, 'params.conversationId': { $in: [convo._id, String(convo._id)] } },
    { readAt: now },
  );
  if (read.modifiedCount) await signal([userId], { type: 'notifications_changed', ...(convo.practiceId ? { practiceId: String(convo.practiceId) } : {}) });
  // The sender's ticks turn "Seen" at once.
  if (seen.modifiedCount) {
    await signal(convo.participants.map((x) => x.userId).filter((id) => String(id) !== String(userId)), { type: 'chat_changed', conversationId: convo._id });
  }
  return convo;
}

/**
 * "Delivered": the app of someone in these chats fetched its badges (it is
 * open on their phone), so messages to them that are only "sent" reach
 * "delivered". Per side, like "Seen".
 */
async function markDelivered(userId) {
  const convos = await M.Conversation.find({ 'participants.userId': userId, 'lastMessage.at': { $gte: new Date(Date.now() - 30 * 864e5) } }, 'type participants.userId participants.role').limit(500).lean();
  if (!convos.length) return;
  const now = new Date();
  const changed = [];
  for (const c of convos) {
    const me = c.participants.find((x) => String(x.userId) === String(userId));
    const side = c.type === 'direct' ? {} : { senderType: me?.role === 'patient' ? { $ne: 'patient' } : 'patient' };
    const r = await M.Message.updateMany({ conversationId: c._id, senderId: { $ne: userId }, ...side, deliveryStatus: 'sent' }, { deliveryStatus: 'delivered', deliveredAt: now });
    if (r.modifiedCount) changed.push(c);
  }
  for (const c of changed) {
    await signal(c.participants.map((x) => x.userId).filter((id) => String(id) !== String(userId)), { type: 'chat_changed', conversationId: c._id });
  }
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
        const scheduledAt = T.atMinute(day, doseMinute(patient.settings, slot, c.foodRelation));
        if (c.trackingSince && scheduledAt < c.trackingSince) continue; // while it was off
        want.set(`${c._id}|${T.dayKey(day)}|${slot}`, { course: c, slot, scheduledAt });
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
  openNow, CARE_ROLES, markDelivered, addParticipants,
  paymentRequestNote, chatNote, shortName, doseMinute, MEALS, raiseAlert, checkReading, readingFindings, patientAdvice, careConversation, ensureParticipant, postMessage, messageDeleted, markRead, ensureDoses, adherence, effectiveStatus };

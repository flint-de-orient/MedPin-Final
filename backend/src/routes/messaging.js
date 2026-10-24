// Care, Nutrition, Patient-Thread, Doctor-Messages, Doctor-Messages-New,
// Chat-Review, Chat-Review-Detail, Chat-Summaries, Doctor-AI, Doctor-AI-Chat.
const { Router } = require('express');
const M = require('../models');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice, ownPractice } = require('../middleware/auth');
const { badRequest, notFound, forbidden, conflict, escapeRegex, paging, isId } = require('../lib/http');
const storage = require('../services/storage');
const { careConversation, ensureParticipant, postMessage, messageDeleted, markRead, CARE_ROLES } = require('../services/care');
const { signal } = require('../services/notify');
const { patientSuggestions } = require('../services/chatsuggest');
const assistant = require('../services/assistant');

const { uploader } = require('../lib/uploads');
// Chat attachments: photos, PDFs and voice notes.
const upload = uploader({ kinds: ['image', 'pdf', 'audio'], maxMb: 20, maxFiles: 1 });

/** Thread access for both apps: a participant, or a practice member allowed to chat. */
async function openConversation(req, id) {
  if (!isId(id)) throw notFound('Conversation');
  const convo = await M.Conversation.findById(id);
  if (!convo) throw notFound('Conversation');
  const rows = convo.participants.filter((p) => String(p.userId) === String(req.user._id));
  const mine = rows[0];
  // The patient of the thread is always in it (even if their account was once listed with
  // another role too). Everyone else only while they still work at that clinic (someone who
  // left loses its chats), and nutrition chats are for the dietician and doctors only.
  if (rows.some((p) => p.role === 'patient') || (mine && !convo.practiceId)) return convo;
  const member = convo.practiceId ? await M.Member.findOne({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' }) : null;
  const allowed = member && M.ROLE_PERMISSIONS[member.role]?.chats && (convo.type !== 'nutrition' || CARE_ROLES.nutrition.includes(member.role));
  if (mine && (allowed || (convo.type === 'direct' && member))) return convo;
  if (!mine && allowed && convo.type !== 'direct') {
    return ensureParticipant(convo, req.user._id, roleInThread(member.role));
  }
  throw notFound('Conversation');
}

/** A clinic member's role in a thread. */
const roleInThread = (role) => (role === 'doctor' ? 'doctor' : role === 'dietician' ? 'dietician' : 'staff');

const senderTypeFor = async (req, convo) => {
  const mine = convo.participants.filter((x) => String(x.userId) === String(req.user._id));
  // The thread's own patient writes as the patient, unless they are also on this clinic's team.
  const patient = convo.patientId ? await M.Patient.findById(convo.patientId, 'userId') : null;
  if (patient?.userId && String(patient.userId) === String(req.user._id)) {
    const member = convo.practiceId ? await M.Member.exists({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' }) : null;
    if (!member) return 'patient';
  }
  if (mine.some((x) => x.role === 'patient') && !mine.some((x) => x.role !== 'patient')) return 'patient';
  if (mine.some((x) => x.role === 'doctor')) return 'doctor';
  if (mine.some((x) => x.role === 'patient')) return 'patient';
  return 'staff';
};

const ROLE_LABEL = {
  doctor: 'Doctor', front_desk: 'Front desk', doctor_assistant: "Doctor's assistant", dietician: 'Dietician',
  practice_manager: 'Practice manager', lab_manager: 'Lab manager', lab_technician: 'Lab technician',
};

/** The patient's open emergency for the thread's staff banner (Call the patient · Doctor informed). */
async function urgentAlertOf(convo, viewer) {
  const a = await M.Alert.findOne({
    practiceId: convo.practiceId, patientId: convo.patientId, status: { $in: ['open', 'acknowledged'] },
    $or: [{ conversationId: convo._id, kind: 'urgent_chat' }, { escalatedAt: { $ne: null } }],
  }).sort({ createdAt: -1 }).populate('acknowledged.by', 'name').populate('deskNotes.by', 'name').populate('doctorId', 'name');
  if (!a) return null;
  return {
    id: a._id, kind: a.kind, severity: a.severity, status: a.status, detail: a.detail, createdAt: a.createdAt, escalatedAt: a.escalatedAt || null,
    doctor: a.doctorId?.name || null,
    acknowledgedBy: a.acknowledged?.by?.name || null, acknowledgedAt: a.acknowledged?.at || null,
    deskNotes: (a.deskNotes || []).map((n) => ({ text: n.text, at: n.at, by: n.by?.name || null })),
    canManage: Boolean(M.ROLE_PERMISSIONS[viewer.role]?.manageAlerts),
  };
}

// Photos keep the same link all day, so a chat that refreshes every few
// seconds shows them from the phone's cache instead of downloading them again.
const fileView = (f) => (f?.key && /^image\//.test(f.mimeType || '') ? { ...(f.toObject ? f.toObject() : f), url: storage.stableUrl(f.key) } : storage.withUrl(f));

const messageView = (m, userId) => ({
  ...m.toJSON(),
  auto: Boolean(m.meta?.auto), // an automatic note (visit booked, fee paid…) sent from this person's account
  text: m.deletedForEveryoneAt ? null : m.text,
  deleted: Boolean(m.deletedForEveryoneAt),
  attachment: m.deletedForEveryoneAt ? undefined : fileView(m.attachment),
  voice: m.voice?.file && !m.deletedForEveryoneAt ? { ...m.voice.toJSON?.(), file: { ...(m.voice.file.toObject ? m.voice.file.toObject() : m.voice.file), url: storage.stableUrl(m.voice.file.key) } } : undefined,
  mine: String(m.senderId?._id || m.senderId) === String(userId), // senderId may be populated
});

/** The thread as the patient's app needs it (no staff ids, unread counts or triage). */
const patientConvoView = (convo) => {
  const c = convo.toJSON();
  return {
    id: c.id || c._id, _id: c._id, type: c.type, practiceId: c.practiceId, patientId: c.patientId, isUrgent: c.isUrgent,
    aiEnabled: c.aiEnabled, pinnedMessageId: c.pinnedMessageId, lastMessage: c.lastMessage, createdAt: c.createdAt, updatedAt: c.updatedAt,
    // They asked for a person ("Talk to the clinic") and nobody has replied yet.
    humanRequested: Boolean(convo.humanRequestedAt && convo.humanRequestedAt > new Date(Date.now() - 24 * 3600e3)),
  };
};

// ── Shared thread endpoints (staff + patient) ──
const threads = Router();
threads.use(requireAuth);

threads.get('/:id/messages', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  // ?since=<at from the last answer>: when neither the thread nor any of its messages
  // (new, read, deleted, paid) changed since, say so and skip the full load.
  const now = new Date();
  if (req.query.since && !req.query.before) {
    const since = new Date(String(req.query.since));
    if (!Number.isNaN(+since)) {
      const [lastMsg, lastAlert] = await Promise.all([
        M.Message.findOne({ conversationId: convo._id }, 'updatedAt').sort({ updatedAt: -1 }).lean(),
        // The emergency banner (acknowledged, desk notes) lives on the alert.
        M.Alert.findOne({ conversationId: convo._id }, 'updatedAt').sort({ updatedAt: -1 }).lean(),
      ]);
      const staffSeen = convo.staffViewingAt && convo.staffViewingAt > since; // the clinic opening it changes the AI line only
      if (convo.updatedAt <= since && (!lastMsg || lastMsg.updatedAt <= since) && (!lastAlert || lastAlert.updatedAt <= since) && !staffSeen) {
        const inThreadNow = convo.participants.find((p) => String(p.userId) === String(req.user._id));
        if (inThreadNow && inThreadNow.role !== 'patient' && !(convo.staffViewingAt > T.addMinutes(now, -1))) {
          await M.Conversation.updateOne({ _id: convo._id }, { $set: { staffViewingAt: now } }, { timestamps: false });
        }
        return res.json({ unchanged: true, at: now });
      }
    }
  }
  const { limit } = paging(req.query, 100);
  const q = { conversationId: convo._id, hiddenFor: { $ne: req.user._id } };
  if (req.query.before) q.createdAt = { $lt: new Date(req.query.before) };
  const msgs = (await M.Message.find(q).sort({ createdAt: -1 }).limit(limit).populate('senderId', 'name')).reverse();
  // Someone at the clinic has the thread open: MedPin AI stays quiet meanwhile (one write a minute at most).
  const inThread = convo.participants.find((p) => String(p.userId) === String(req.user._id));
  if (inThread && inThread.role !== 'patient' && !req.query.before && !(convo.staffViewingAt > T.addMinutes(new Date(), -1))) {
    convo.staffViewingAt = new Date();
    await M.Conversation.updateOne({ _id: convo._id }, { staffViewingAt: convo.staffViewingAt }, { timestamps: false });
  }
  const pinned = convo.pinnedMessageId ? await M.Message.findById(convo.pinnedMessageId) : null;
  const patient = convo.patientId ? await M.Patient.findById(convo.patientId, 'name userId') : null;
  const isPatientView = Boolean(patient?.userId) && String(patient.userId) === String(req.user._id) && inThread?.role === 'patient';
  const lastSeen = patient?.userId ? convo.participants.find((p) => String(p.userId) === String(patient.userId))?.lastReadAt : null;
  const patientIsOnlyPatient = Boolean(patient?.userId) && !(convo.practiceId && (await M.Member.exists({ userId: patient.userId, practiceId: convo.practiceId, status: 'active' })));
  // The thread's own patient gets quick replies picked from the latest message and their day.
  const suggestions = patient?.userId && String(patient.userId) === String(req.user._id) && !req.query.before
    ? await patientSuggestions(convo, msgs).catch(() => [])
    : undefined;
  const nextVisit = convo.patientId ? await M.Appointment.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, startAt: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting'] } }).sort({ startAt: 1 }) : null;
  // Shared records show as cards ("HbA1c · 7.4%, shared report · 30 Sep").
  const recIds = msgs.filter((m) => m.recordId).map((m) => m.recordId);
  const recs = recIds.length ? await M.MedicalRecord.find({ _id: { $in: recIds }, deletedAt: null }, 'kind title recordDate sourceName flagLabel files prescriptionId') : [];
  const recordOf = (m) => {
    const x = m.recordId && recs.find((r) => String(r._id) === String(m.recordId));
    // With its file, so the card opens the report itself.
    const file = x?.files?.[0];
    return x ? {
      id: x._id, kind: x.kind, title: x.title, date: x.recordDate, sourceName: x.sourceName, flagLabel: x.flagLabel,
      prescriptionId: x.prescriptionId || null, url: file?.key ? storage.signedUrl(file.key) : null, mimeType: file?.mimeType || null, name: file?.name || null,
    } : undefined;
  };
  // Who wrote each message, with their profile photo (a doctor's public photo first).
  const senderPhotos = await require('../services/photos').doctorPhotos(msgs.map((m) => m.senderId?._id || m.senderId));
  // …and their role here ("Tania · Front desk"): the clinic shares one thread per patient.
  const staffIds = [...new Set(msgs.filter((m) => m.senderId && m.senderType !== 'patient').map((m) => String(m.senderId?._id || m.senderId)))];
  const roles = new Map(convo.practiceId && staffIds.length
    ? (await M.Member.find({ practiceId: convo.practiceId, userId: { $in: staffIds } }, 'userId role')).map((x) => [String(x.userId), x.role])
    : []);
  const viewer = convo.practiceId && String(patient?.userId || '') !== String(req.user._id)
    ? await M.Member.findOne({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' }, 'role')
    : null;
  // Payment requests in this page of messages: their payments, so the cards show Pay / Paid now.
  const payIds = msgs.filter((m) => m.meta?.event === 'payment_request' && /^[a-f\d]{24}$/i.test(String(m.meta.paymentId || ''))).map((m) => m.meta.paymentId);
  const payOf = new Map((payIds.length ? await M.Payment.find({ _id: { $in: payIds } }, 'amount status method appointmentId') : []).map((p) => [String(p._id), p]));
  res.json({
    at: now, // the phone sends it back as ?since= on its next check
    conversation: {
      ...(isPatientView ? patientConvoView(convo) : convo.toJSON()),
      aiPaused: assistant.aiPaused(convo),
      patient: patient && {
        id: patient._id, name: patient.name, lastSeenAt: lastSeen,
        photo: patient.userId ? (await require('../services/photos').photosFor([patient.userId])).get(String(patient.userId)) || null : null,
      },
      nextVisit: nextVisit && { startAt: nextVisit.startAt, token: String(nextVisit.tokenNo).padStart(2, '0') },
      // Staff only: the patient's open emergency (urgent chat, or one the desk was asked to pass on).
      urgentAlert: viewer && convo.type === 'care' ? await urgentAlertOf(convo, viewer) : undefined,
    },
    pinned: pinned && !pinned.deletedForEveryoneAt && !(pinned.hiddenFor || []).some((u) => String(u) === String(req.user._id)) ? messageView(pinned, req.user._id) : null,
    suggestions,
    items: msgs.map((m) => {
      const v = { ...messageView(m, req.user._id), record: m.deletedForEveryoneAt ? undefined : recordOf(m), senderPhoto: senderPhotos.get(String(m.senderId?._id || m.senderId)) || null };
      if (isPatientView) {
        // The patient's app: no review flags, staff ids or who hid what.
        v.ai = m.ai ? { escalated: Boolean(m.ai.escalated) } : undefined;
        delete v.hiddenFor;
        v.meta = m.meta ? { auto: m.meta.auto, event: m.meta.event, away: m.meta.away } : undefined;
      }
      if (m.meta?.event === 'payment_request') {
        const p = payOf.get(String(m.meta.paymentId));
        if (p) v.payment = { id: p._id, amount: p.amount, status: p.status, method: p.method || null, appointmentId: m.meta.appointmentId || (p.appointmentId ? String(p.appointmentId) : null) };
      }
      const role = m.senderType !== 'patient' ? roles.get(String(m.senderId?._id || m.senderId)) : null;
      if (role) Object.assign(v, { senderRole: role, senderRoleLabel: ROLE_LABEL[role] || null });
      // Older messages the thread's patient sent while listed with another role: shown as theirs.
      if (patientIsOnlyPatient && String(m.senderId?._id || m.senderId) === String(patient.userId) && v.senderType !== 'patient' && v.senderType !== 'system') v.senderType = 'patient';
      return v;
    }),
  });
});

threads.post('/:id/messages', upload.single('file'), async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  // The same message sent again (the first try timed out but was saved): the saved one, once.
  const clientId = typeof req.body.clientId === 'string' && /^[\w-]{8,64}$/.test(req.body.clientId) ? req.body.clientId : null;
  if (clientId) {
    const saved = await M.Message.findOne({ conversationId: convo._id, clientId, senderId: req.user._id });
    if (saved) return res.status(201).json({ message: messageView(saved, req.user._id), aiReply: null, aiPending: false, duplicate: true });
  }
  const senderType = await senderTypeFor(req, convo);
  const text = String(req.body.text || '').trim();
  const extra = {};
  let kind = 'text';
  if (req.file) {
    const f = await storage.save(req.file.buffer, { folder: 'chat', name: req.file.originalname, mimeType: req.file.mimetype });
    if (req.file.mimetype.startsWith('audio/')) {
      kind = 'voice';
      const sec = Number(req.body.durationSec);
      extra.voice = { file: f, durationSec: Number.isFinite(sec) && sec > 0 ? Math.min(Math.round(sec), 3600) : undefined };
    } else {
      kind = 'attachment';
      extra.attachment = f;
    }
  }
  if (req.body.recordId && !req.file) {
    const rec = isId(req.body.recordId) ? await M.MedicalRecord.findOne({ _id: req.body.recordId, patientId: convo.patientId, deletedAt: null }) : null;
    if (!rec) throw notFound('Record');
    kind = 'record';
    extra.recordId = rec._id;
    // Sharing a record in chat shares it with this thread's clinical team (doctors, their
    // assistants, the dietician) — not the front desk or the practice manager.
    const staffIds = convo.participants.filter((p) => p.role !== 'patient').map((p) => p.userId);
    const clinical = convo.practiceId
      ? (await M.Member.find({ practiceId: convo.practiceId, status: 'active', userId: { $in: staffIds } }, 'userId role')).filter((m) => M.ROLE_PERMISSIONS[m.role]?.clinical).map((m) => String(m.userId))
      : [];
    const already = new Set(rec.sharedWith.map((s) => String(s.userId)));
    for (const id of clinical) if (!already.has(id)) rec.sharedWith.push({ userId: id });
    await rec.save();
  }
  if (!text && kind === 'text') throw badRequest('Type a message', 'EMPTY_MESSAGE');
  if (req.body.replyToId) {
    // A reply quotes a message of this chat (not one from someone else's).
    if (!isId(req.body.replyToId) || !(await M.Message.exists({ _id: req.body.replyToId, conversationId: convo._id }))) throw badRequest('That message is no longer in this chat');
    extra.replyToId = req.body.replyToId;
  }
  const msg = await postMessage(convo, { sender: req.user, senderType, text: text || undefined, kind, isUrgent: req.body.isUrgent === true || req.body.isUrgent === 'true', ...(clientId ? { clientId } : {}), ...extra });
  // Staff replying pauses the AI in this thread for a while (atomic, like the message itself).
  if (senderType !== 'patient') {
    convo.aiPausedAt = new Date();
    // The clinic answered: a "talk to the clinic" request is done too.
    await M.Conversation.updateOne({ _id: convo._id }, { $set: { aiPausedBy: req.user._id, aiPausedAt: convo.aiPausedAt }, $unset: { humanRequestedAt: 1 } });
    await M.Conversation.updateOne({ _id: convo._id, triage: 'needs_attention' }, { $unset: { triage: 1 } });
  }
  // The message is saved: answer now. MedPin AI's reply (and the emergency
  // check) runs in the background and arrives in the thread a moment later;
  // aiPending tells the app to show "MedPin AI is typing…".
  let aiPending = false;
  // A question, or a photo / PDF on its own (a medicine strip, a report): MedPin AI may answer
  // (and the emergency check runs). Voice notes: the clinic listens.
  if (senderType === 'patient' && (text || kind === 'attachment')) {
    aiPending = await assistant.willReplyInCareThread(convo).catch(() => false);
    setImmediate(() => {
      assistant.replyInCareThread(convo, msg).catch((err) => console.warn('[ai reply]', err.message));
    });
  }
  res.status(201).json({ message: messageView(msg, req.user._id), aiReply: null, aiPending });
});

// "Talk to the clinic": the patient wants a person, not MedPin AI. The AI stays out of this
// chat until someone replies (or a day passes), and the clinic is told at once.
threads.post('/:id/handoff', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  if (!convo.participants.some((p) => String(p.userId) === String(req.user._id) && p.role === 'patient')) throw forbidden('Only the patient can ask for this');
  const already = convo.humanRequestedAt && convo.humanRequestedAt > T.addMinutes(new Date(), -60);
  await M.Conversation.updateOne({ _id: convo._id }, { $set: { humanRequestedAt: new Date() } });
  if (!already) {
    const care = require('../services/care');
    const notifier = require('../services/notify');
    const patient = await M.Patient.findById(convo.patientId, 'name');
    const place = await notifier.patientPlace(convo.practiceId, convo.patientId);
    const desk = convo.type === 'care' ? await notifier.deskFor(convo.practiceId, place) : [];
    const team = desk.length ? desk : await notifier.clinicians(convo.practiceId, convo.patientId, { roles: convo.type === 'nutrition' ? ['dietician', 'doctor'] : ['doctor'] });
    await notifier.notify(team, {
      type: 'message', practiceId: convo.practiceId, push: await care.openNow(place?.locationId),
      title: `${patient?.name || 'A patient'} wants to talk to someone at the clinic`,
      body: 'MedPin AI is paused in this chat until you reply.', screen: 'Patient-Thread', params: { conversationId: convo._id },
    });
    // The note is for the patient: in their app language.
    const lang = await assistant.patientLanguage(await M.Patient.findById(convo.patientId, 'userId'));
    const note = {
      en: 'You asked to talk to the clinic. Someone will reply here soon.',
      bn: 'আপনি ক্লিনিকের সঙ্গে কথা বলতে চেয়েছেন। শিগগিরই এখানে কেউ উত্তর দেবেন।',
      hi: 'आपने क्लिनिक से बात करनी चाही है। जल्द ही यहाँ कोई जवाब देगा।',
    }[['bn', 'hi'].includes(lang) ? lang : 'en'];
    await care.chatNote({ practiceId: convo.practiceId, patientId: convo.patientId }, note, 'handoff').catch(() => null);
  }
  await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
  res.json({ ok: true });
});

// The clinic's inbox: give this chat to a colleague (or take it back), or mark it handled.
threads.post('/:id/assign', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  if (!convo.practiceId || convo.type === 'direct') throw badRequest('Only patient chats can be assigned');
  const me = await M.Member.findOne({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' }, 'role');
  if (!me) throw forbidden('Only the clinic can assign this chat');
  const to = req.body.userId ? String(req.body.userId) : null;
  if (to) {
    if (!isId(to)) throw badRequest('Choose a colleague');
    const member = await M.Member.findOne({ userId: to, practiceId: convo.practiceId, status: 'active', role: { $in: ['doctor', 'front_desk', 'doctor_assistant', 'practice_manager', 'dietician'] } }, 'role');
    if (!member) throw badRequest('Choose someone at this clinic', 'NOT_A_COLLEAGUE');
    await M.Conversation.updateOne({ _id: convo._id }, { assignedTo: to, assignedBy: req.user._id, assignedAt: new Date() });
    // They're in the chat (with it unread), and told it's theirs now.
    if (!convo.participants.some((p) => String(p.userId) === to)) {
      await M.Conversation.updateOne({ _id: convo._id, 'participants.userId': { $ne: to } }, { $push: { participants: { userId: to, role: member.role === 'doctor' ? 'doctor' : member.role === 'dietician' ? 'dietician' : 'staff', unreadCount: 1 } } });
    }
    if (to !== String(req.user._id)) {
      const patient = await M.Patient.findById(convo.patientId, 'name');
      await require('../services/notify').notify([to], {
        type: 'chat_assigned', practiceId: convo.practiceId,
        title: `${req.user.name || 'A colleague'} gave you ${patient?.name || 'a patient'}'s chat`, screen: 'Patient-Thread', params: { conversationId: convo._id },
      }).catch(() => {});
    }
  } else {
    await M.Conversation.updateOne({ _id: convo._id }, { $unset: { assignedTo: 1, assignedBy: 1, assignedAt: 1 } });
  }
  await signal(convo.participants.map((p) => p.userId).filter((u) => String(u) !== String(req.user._id)), { type: 'chat_changed', conversationId: convo._id });
  res.json({ ok: true, assignedTo: to });
});

threads.post('/:id/handled', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  if (!convo.practiceId || convo.type === 'direct') throw badRequest('Only patient chats can be marked handled');
  const me = await M.Member.exists({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' });
  if (!me) throw forbidden('Only the clinic can mark this chat');
  const handled = req.body.handled !== false;
  await M.Conversation.updateOne({ _id: convo._id }, handled ? { handledAt: new Date(), handledBy: req.user._id } : { $unset: { handledAt: 1, handledBy: 1 } });
  if (handled) await markRead(convo, req.user._id);
  res.json({ ok: true, handled });
});

// MedPin AI on or off for one patient's chat (the doctor, dietician or their assistant).
threads.patch('/:id/ai', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  const member = convo.practiceId ? await M.Member.findOne({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' }, 'role') : null;
  if (!member || !M.ROLE_PERMISSIONS[member.role]?.clinical) throw forbidden('Only the doctor or dietician can change MedPin AI for a chat');
  const on = req.body.on === true;
  await M.Conversation.updateOne({ _id: convo._id }, { $set: { aiEnabled: on } });
  await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
  res.json({ ok: true, aiEnabled: on });
});

threads.post('/:id/read', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  await markRead(convo, req.user._id);
  const isStaff = convo.participants.find((p) => String(p.userId) === String(req.user._id))?.role !== 'patient';
  if (isStaff && req.body.pauseAi !== false) {
    await M.Conversation.updateOne({ _id: convo._id }, { $set: { aiPausedBy: req.user._id, aiPausedAt: new Date() } });
  }
  res.json({ ok: true });
});

threads.post('/:id/pin', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  // The pinned message is the clinic's note for everyone in a patient chat.
  if (convo.type !== 'direct' && convo.participants.find((p) => String(p.userId) === String(req.user._id))?.role === 'patient') {
    throw forbidden('Only the clinic can pin a message');
  }
  if (req.body.messageId) {
    const msg = isId(req.body.messageId) ? await M.Message.findOne({ _id: req.body.messageId, conversationId: convo._id, deletedForEveryoneAt: null }) : null;
    if (!msg) throw notFound('Message');
  }
  await M.Conversation.updateOne({ _id: convo._id }, req.body.messageId ? { $set: { pinnedMessageId: req.body.messageId } } : { $unset: { pinnedMessageId: 1 } });
  await signal(convo.participants.map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id });
  res.json({ ok: true, pinnedMessageId: req.body.messageId || null });
});

threads.post('/:id/messages/:messageId/hide', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  if (!isId(req.params.messageId)) throw notFound('Message');
  await M.Message.updateOne({ _id: req.params.messageId, conversationId: convo._id }, { $addToSet: { hiddenFor: req.user._id } });
  await signal([req.user._id], { type: 'chat_changed', conversationId: convo._id }); // the person's other phone
  res.json({ ok: true });
});

threads.delete('/:id/messages/:messageId', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  const msg = isId(req.params.messageId) ? await M.Message.findOne({ _id: req.params.messageId, conversationId: convo._id }) : null;
  if (!msg) throw notFound('Message');
  if (String(msg.senderId) !== String(req.user._id)) throw forbidden('You can only delete your own messages');
  if (msg.deletedForEveryoneAt) return res.json({ ok: true }); // already deleted (a second tap)
  // Atomic: of two taps at once, only one counts.
  const done = await M.Message.updateOne({ _id: msg._id, deletedForEveryoneAt: null }, { deletedForEveryoneAt: new Date() });
  if (!done.modifiedCount) return res.json({ ok: true });
  if (String(convo.pinnedMessageId || '') === String(msg._id)) await M.Conversation.updateOne({ _id: convo._id }, { $unset: { pinnedMessageId: 1 } });
  await messageDeleted(convo, msg);
  res.json({ ok: true });
});

// ── Staff inbox ──
const inbox = Router();
inbox.use(requireAuth, staff({ perm: 'chats' }));

inbox.get('/', async (req, res) => {
  const type = req.query.type || 'care';
  const q = type === 'direct'
    ? { type: 'direct', 'participants.userId': req.user._id, practiceId: { $in: [req.practiceId, null] } }
    : { practiceId: req.practiceId, type: { $in: type === 'all' ? ['care', 'nutrition'] : [type] } };
  if (req.query.q && type !== 'direct') {
    // Searching: every chat of the patients whose name or phone matches, however old.
    const re = new RegExp(escapeRegex(String(req.query.q)), 'i');
    const pts = await M.Patient.find({ $or: [{ name: re }, { phone: re }] }, '_id').limit(500).lean();
    q.$or = [{ patientId: { $in: pts.map((p) => p._id) } }, { 'lastMessage.text': re }];
  }
  // Views of the clinic's inbox: given to me, not given to anyone, still open (not handled).
  if (type !== 'direct') {
    if (req.query.view === 'mine') q.assignedTo = req.user._id;
    if (req.query.view === 'unassigned') q.assignedTo = null;
    if (req.query.view === 'open') q.handledAt = null;
  }
  const convos = await M.Conversation.find(q).sort({ 'lastMessage.at': -1 }).limit(Math.min(Number(req.query.limit) || 300, 500)).populate('patientId', 'name gender ageYears ageRecordedAt phone conditions userId').populate('assignedTo', 'name');
  // Patients' profile photos for the avatars.
  const photos = await require('../services/photos').photosFor(convos.map((c) => c.patientId?.userId));
  const mine = (c) => c.participants.find((p) => String(p.userId) === String(req.user._id));
  let rows = convos.map((c) => ({
    id: c._id, type: c.type, isUrgent: c.isUrgent, triage: c.triage, lastMessage: c.lastMessage,
    unread: mine(c)?.unreadCount || 0,
    patient: c.patientId && {
      id: c.patientId._id, name: c.patientId.name, age: T.ageFrom(c.patientId), gender: c.patientId.gender, conditions: c.patientId.conditions.map((x) => x.name),
      photo: c.patientId.userId ? photos.get(String(c.patientId.userId)) || null : null,
    },
    participants: c.participants.map((p) => ({ userId: p.userId, role: p.role })),
    assignedTo: c.assignedTo ? { id: c.assignedTo._id || c.assignedTo, name: c.assignedTo.name || null } : null,
    handled: Boolean(c.handledAt),
  }));
  if (type === 'direct') {
    // Chats with colleagues: who the other person is (name, role here, photo).
    const otherIds = [...new Set(convos.flatMap((c) => c.participants.map((p) => String(p.userId)).filter((id) => id !== String(req.user._id))))];
    const [users, members, faces] = await Promise.all([
      M.User.find({ _id: { $in: otherIds } }, 'name').lean(),
      M.Member.find({ practiceId: req.practiceId, userId: { $in: otherIds } }, 'userId role').lean(),
      require('../services/photos').doctorPhotos(otherIds),
    ]);
    const nameOf = new Map(users.map((u) => [String(u._id), u.name]));
    const roleOf = new Map(members.map((m) => [String(m.userId), m.role]));
    rows = rows.map((x) => {
      const id = x.participants.map((p) => String(p.userId)).find((u) => u !== String(req.user._id));
      const role = roleOf.get(id);
      return { ...x, other: id ? { id, name: nameOf.get(id) || 'Colleague', role: role || null, roleLabel: role ? ROLE_LABEL[role] || null : 'Another clinic', photo: faces.get(id) || null } : null };
    });
  }
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    rows = rows.filter((x) => re.test(x.patient?.name || '') || re.test(x.other?.name || '') || re.test(x.lastMessage?.text || '') || re.test(x.lastMessage?.senderLabel || ''));
  }
  // A doctor in a clinic with several doctors: unread counts their own patients (care team) and
  // chats they have written in — not every patient of the clinic.
  if (req.member.role === 'doctor' && type !== 'direct') {
    const doctors = await M.Member.countDocuments({ practiceId: req.practiceId, status: 'active', role: 'doctor' });
    if (doctors > 1) {
      const mineP = new Set((await M.CareTeamAccess.find({ userId: req.user._id, practiceId: req.practiceId, accessLevel: { $ne: 'not_shared' } }, 'patientId').lean()).map((x) => String(x.patientId)));
      const wrote = new Set((await M.Message.distinct('conversationId', { conversationId: { $in: rows.map((x) => x.id) }, senderId: req.user._id })).map(String));
      rows = rows.map((x) => (x.unread > 0 && !mineP.has(String(x.patient?.id)) && !wrote.has(String(x.id)) && !x.isUrgent ? { ...x, unread: 0, otherDoctor: true } : x));
    }
  }
  const unreadCount = rows.filter((x) => x.unread > 0).length;
  if (req.query.tab === 'unread') rows = rows.filter((x) => x.unread > 0);
  const pendingEnrolments = await M.PatientEnrolment.countDocuments({ practiceId: req.practiceId, status: 'pending_code' });
  res.json({ unread: unreadCount, urgent: rows.filter((x) => x.isUrgent).length, pendingEnrolments, items: rows });
});

// Doctor-Messages-New: open the patient's care thread or a direct thread with a colleague.
inbox.post('/', async (req, res) => {
  if (req.body.patientId) {
    await patientInPractice(req, req.body.patientId);
    const type = req.body.type === 'nutrition' || (req.body.type == null && req.member.role === 'dietician') ? 'nutrition' : 'care';
    if (type === 'nutrition' && !CARE_ROLES.nutrition.includes(req.member.role)) throw forbidden('Nutrition chats are for the dietician and doctors');
    const convo = await careConversation(req.body.patientId, req.practiceId, type);
    return res.json(await ensureParticipant(convo, req.user._id, roleInThread(req.member.role)));
  }
  const otherId = req.body.userId;
  if (!otherId || String(otherId) === String(req.user._id)) throw badRequest('Choose who to message');
  const other = await M.User.findById(otherId);
  if (!other) throw notFound('Person');
  let convo = await M.Conversation.findOne({ type: 'direct', 'participants.userId': { $all: [req.user._id, other._id] }, 'participants.2': { $exists: false } });
  if (!convo) {
    const otherMember = await M.Member.findOne({ userId: other._id, practiceId: req.practiceId });
    convo = await M.Conversation.create({
      type: 'direct', practiceId: req.practiceId,
      participants: [{ userId: req.user._id, role: roleInThread(req.member.role) }, { userId: other._id, role: otherMember ? roleInThread(otherMember.role) : 'colleague' }],
    });
  }
  return res.status(201).json(convo);
});

// People to start a chat with. Patients: everyone linked to this clinic
// (registered here, or who found the doctor in the patient app and booked or
// wrote), most recently active first — not only this week's appointments, so
// a doctor who consulted without a booking still finds their patients.
inbox.get('/contacts', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const re = q ? new RegExp(escapeRegex(q), 'i') : null;
  const digits = q.replace(/\D/g, '');
  const match = (name, phone) => !q || re.test(name || '') || (digits.length >= 3 && String(phone || '').includes(digits));
  const team = await M.Member.find({ practiceId: req.practiceId, status: 'active', userId: { $ne: req.user._id } }).populate('userId', 'name phone').populate('departmentId', 'name');
  const linked = await M.PatientEnrolment.find({ practiceId: req.practiceId, status: 'linked' }).distinct('patientId');
  const pq = { _id: { $in: linked } };
  if (q) {
    const or = [{ name: re }];
    if (digits.length >= 3) or.push({ phone: new RegExp(escapeRegex(digits.replace(/^91(?=\d{10}$)/, ''))) });
    pq.$or = or;
  }
  const pts = await M.Patient.find(pq, 'name phone gender ageYears ageRecordedAt dateOfBirth userId').limit(1000);
  const ids = pts.map((p) => p._id);
  // Last activity here: a visit, a consultation or a chat message.
  const now = new Date();
  const [appts, consults, convos, week] = await Promise.all([
    M.Appointment.aggregate([{ $match: { practiceId: req.practiceId, patientId: { $in: ids }, startAt: { $lte: now } } }, { $group: { _id: '$patientId', at: { $max: '$startAt' } } }]),
    M.Consultation.aggregate([{ $match: { practiceId: req.practiceId, patientId: { $in: ids } } }, { $group: { _id: '$patientId', at: { $max: '$startedAt' } } }]),
    M.Conversation.find({ practiceId: req.practiceId, patientId: { $in: ids }, 'lastMessage.at': { $ne: null } }, 'patientId lastMessage.at'),
    M.Appointment.find({ practiceId: req.practiceId, patientId: { $in: ids }, date: { $gte: T.addDays(T.dayStart(), -7) } }, 'patientId status startAt').sort({ startAt: -1 }),
  ]);
  const last = new Map();
  const seen = (id, at) => {
    if (!at) return;
    const k = String(id);
    if (!last.has(k) || last.get(k) < at) last.set(k, at);
  };
  for (const a of appts) seen(a._id, a.at);
  for (const c of consults) seen(c._id, c.at);
  for (const c of convos) seen(c.patientId, c.lastMessage?.at);
  // This week's visit status ("in queue", "seen recently") for the row.
  const status = new Map();
  for (const a of week) if (!status.has(String(a.patientId))) status.set(String(a.patientId), a.status);
  const rows = pts
    .map((p) => ({ p, at: last.get(String(p._id)) || null }))
    .sort((a, b) => (b.at ? b.at.getTime() : 0) - (a.at ? a.at.getTime() : 0) || String(a.p.name || '').localeCompare(String(b.p.name || '')))
    .slice(0, 200);
  // Profile photos for the avatars: patients' own, the team's (a doctor's public photo first).
  const photos = require('../services/photos');
  const teamRows = team.filter((m) => m.userId && match(m.userId.name, m.userId.phone));
  const [patientPhotos, teamPhotos] = await Promise.all([
    photos.photosFor(rows.map(({ p }) => p.userId)),
    photos.doctorPhotos(teamRows.map((m) => m.userId._id)),
  ]);
  res.json({
    patients: rows.map(({ p, at }) => ({
      id: p._id, name: p.name, phone: p.phone, age: T.ageFrom(p), gender: p.gender, today: status.get(String(p._id)) || null, lastActiveAt: at,
      photo: p.userId ? patientPhotos.get(String(p.userId)) || null : null,
    })),
    team: teamRows.map((m) => ({ userId: m.userId._id, name: m.userId.name, role: m.role, department: m.departmentId?.name, photo: teamPhotos.get(String(m.userId._id)) || null })),
  });
});

// ── Chat review (flagged AI answers) ──
inbox.get('/reviews', need('ai'), async (req, res) => {
  const status = req.query.status || 'needs_review';
  const q = { practiceId: req.practiceId, ...(status === 'all' ? {} : { status }) };
  let items = await M.ChatReview.find(q).sort({ createdAt: -1 }).limit(200).populate('patientId', 'name').populate('reviewed.by', 'name');
  const order = { high: 0, medium: 1, low: 2 };
  items.sort((a, b) => (a.status === b.status ? order[a.urgency] - order[b.urgency] : a.status === 'needs_review' ? -1 : 1));
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    items = items.filter((x) => re.test(x.patientId?.name || '') || re.test(x.title || '') || re.test(x.excerpt || ''));
  }
  const flagged = await M.ChatReview.countDocuments({ practiceId: req.practiceId, status: 'needs_review' });
  res.json({ flagged, items });
});

inbox.post('/reviews/:id/reviewed', need('ai'), async (req, res) => {
  const review = ownPractice(req, await M.ChatReview.findById(req.params.id), 'Review');
  review.status = 'reviewed';
  review.reviewed = { by: req.user._id, at: new Date() };
  await review.save();
  res.json(review);
});

// ── Chat summaries ──
inbox.get('/summaries', need('ai'), async (req, res) => {
  const day = req.query.date === 'yesterday' ? T.addDays(T.dayStart(), -1) : T.parseDay(req.query.date === 'today' ? undefined : req.query.date);
  if (req.query.refresh === 'true' || !(await M.ChatSummary.exists({ practiceId: req.practiceId, date: day }))) {
    await assistant.summarizeDay(req.practiceId, day);
  }
  const q = { practiceId: req.practiceId, date: day };
  if (req.query.scope === 'mine') q.doctorId = req.user._id;
  const items = await M.ChatSummary.find(q).sort({ needsReply: -1, lastMessageAt: -1 }).populate('patientId', 'name');
  res.json({ date: day, patientsWrote: items.length, needReply: items.filter((x) => x.needsReply).length, items });
});

// ── Doctor AI assistant ──
const ai = Router();
ai.use(requireAuth, staff(), need('ai'));

ai.get('/sessions', async (req, res) => {
  res.json(await M.AiSession.find({ userId: req.user._id, ownerType: 'doctor' }).sort({ lastAt: -1 }).limit(50).populate('patientId', 'name'));
});

ai.post('/sessions', async (req, res) => {
  if (req.body.patientId) await patientInPractice(req, req.body.patientId);
  const s = await M.AiSession.create({ ownerType: 'doctor', userId: req.user._id, practiceId: req.practiceId, patientId: req.body.patientId, title: req.body.title, lastAt: new Date() });
  res.status(201).json(s);
});

const ownSession = async (req) => {
  const s = await M.AiSession.findOne({ _id: req.params.id, userId: req.user._id });
  if (!s) throw notFound('Conversation');
  return s;
};

ai.patch('/sessions/:id', async (req, res) => {
  const s = await ownSession(req);
  if (req.body.patientId !== undefined) {
    if (req.body.patientId) await patientInPractice(req, req.body.patientId);
    s.patientId = req.body.patientId || undefined;
  }
  await s.save();
  res.json(s);
});

ai.delete('/sessions/:id', async (req, res) => {
  const s = await ownSession(req);
  await M.AiMessage.deleteMany({ sessionId: s._id });
  await s.deleteOne();
  res.json({ ok: true });
});

ai.get('/sessions/:id/messages', async (req, res) => {
  const s = await ownSession(req);
  res.json(await M.AiMessage.find({ sessionId: s._id }).sort({ createdAt: 1 }));
});

ai.post('/sessions/:id/messages', async (req, res) => {
  const s = await ownSession(req);
  const text = String(req.body.text || '').trim();
  if (!text) throw badRequest('Ask a question', 'EMPTY_MESSAGE');
  const question = await M.AiMessage.create({ sessionId: s._id, role: 'user', text, inputMode: req.body.inputMode, voiceLanguage: req.body.voiceLanguage });
  // A failed AI call still answers, so the chat never has a question left hanging.
  const out = await assistant.doctorAnswer(s, text, req.practiceId, { excludeId: question._id }).catch((err) => {
    console.warn('[ai]', err.message);
    return { text: "I couldn't answer just now. Please try again in a moment.", scripted: true, failed: true };
  });
  const answer = await M.AiMessage.create({
    sessionId: s._id, role: 'assistant', text: out.text, aiModel: out.model, latencyMs: out.latencyMs, inputTokens: out.inputTokens, outputTokens: out.outputTokens,
    payload: out.scripted ? { scripted: true, ...(out.failed ? { failed: true } : {}) } : undefined,
  });
  s.title = s.title || text.slice(0, 80);
  s.lastAt = new Date();
  await s.save();
  res.status(201).json({ question, answer });
});

const memory = require('../services/ai_memory');

// "What MedPin AI remembers": see, add and delete the notes; memory on / off.
ai.get('/memories', async (req, res) => res.json(await memory.list({ ownerType: 'doctor', userId: req.user._id })));
ai.post('/memories', async (req, res) => {
  const note = await memory.add({ ownerType: 'doctor', userId: req.user._id }, req.body?.text);
  if (!note) throw badRequest('Write what MedPin AI should remember', 'EMPTY_NOTE');
  res.status(201).json(note);
});
ai.delete('/memories/:id', async (req, res) => {
  if (!isId(req.params.id)) throw notFound('Note');
  await memory.remove({ ownerType: 'doctor', userId: req.user._id }, req.params.id);
  res.json({ ok: true });
});
ai.delete('/memories', async (req, res) => {
  await memory.clear({ ownerType: 'doctor', userId: req.user._id });
  res.json({ ok: true });
});
ai.put('/memories/settings', async (req, res) => {
  await memory.setEnabled({ ownerType: 'doctor', userId: req.user._id }, req.body?.enabled !== false);
  res.json(await memory.list({ ownerType: 'doctor', userId: req.user._id }));
});

ai.post('/messages/:id/vote', async (req, res) => {
  const vote = Number(req.body.vote);
  if (![-1, 0, 1].includes(vote)) throw badRequest('vote must be -1, 0 or 1');
  const msg = await M.AiMessage.findById(req.params.id);
  if (!msg || !(await M.AiSession.exists({ _id: msg.sessionId, userId: req.user._id }))) throw notFound('Message');
  msg.vote = msg.vote === vote ? 0 : vote; // tapping the same vote again clears it
  await msg.save();
  res.json(msg);
});

// Patient brief for the queue / consultation ("AI brief").
ai.post('/patients/:patientId/brief', async (req, res) => {
  const patient = await patientInPractice(req, req.params.patientId);
  const { patientSummary } = require('../services/clinical');
  const aiSvc = require('../services/ai');
  if (!aiSvc.enabled()) throw conflict('Add GEMINI_API_KEY (or ANTHROPIC_API_KEY) to turn on AI briefs', 'AI_DISABLED');
  await assistant.useAiChat(req.practiceId);
  const { accessFor } = require('../services/access');
  const summary = await patientSummary(patient, req.practiceId, await accessFor({ userId: req.user._id, practiceId: req.practiceId }, patient));
  const recent = await M.Message.find({ conversationId: { $in: await M.Conversation.find({ patientId: patient._id, practiceId: req.practiceId }).distinct('_id') }, senderType: 'patient', createdAt: { $gte: T.addDays(new Date(), -7) } }).limit(30);
  const out = await aiSvc.completeJson({
    system: 'Write a pre-visit brief for the doctor: a 2-3 sentence summary of the patient\'s current state from the record, and one line on what the patient asked about this week (empty if nothing). Be factual; quote values with dates.',
    messages: [{ role: 'user', content: JSON.stringify({ record: summary, patient_messages_this_week: recent.map((m) => m.text).filter(Boolean) }) }],
    schema: { type: 'object', properties: { summary: { type: 'string' }, asked_about: { type: 'string' } }, required: ['summary', 'asked_about'], additionalProperties: false },
    effort: 'low',
  });
  if (!out?.data) throw conflict('Could not write a brief right now', 'AI_FAILED');
  const brief = await M.AiSummary.create({
    patientId: patient._id, audience: 'doctor', practiceId: req.practiceId, body: out.data.summary,
    contextNote: out.data.asked_about || undefined, aiModel: out.model,
    sources: { labReports: summary.abnormalResults.length, medicineLog: summary.currentMedicines.length > 0 },
  });
  res.status(201).json(brief);
});

module.exports = { threads, inbox, ai };

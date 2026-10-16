// Care, Nutrition, Patient-Thread, Doctor-Messages, Doctor-Messages-New,
// Chat-Review, Chat-Review-Detail, Chat-Summaries, Doctor-AI, Doctor-AI-Chat.
const { Router } = require('express');
const M = require('../models');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice, ownPractice } = require('../middleware/auth');
const { badRequest, notFound, forbidden, conflict, escapeRegex, paging, isId } = require('../lib/http');
const storage = require('../services/storage');
const { careConversation, ensureParticipant, postMessage, messageDeleted, markRead } = require('../services/care');
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
  if (convo.participants.some((p) => String(p.userId) === String(req.user._id))) return convo;
  if (convo.practiceId) {
    const member = await M.Member.findOne({ userId: req.user._id, practiceId: convo.practiceId, status: 'active' });
    if (member && M.ROLE_PERMISSIONS[member.role]?.chats && convo.type !== 'direct') {
      return ensureParticipant(convo, req.user._id, member.role === 'doctor' ? 'doctor' : member.role === 'dietician' ? 'dietician' : 'staff');
    }
  }
  throw notFound('Conversation');
}

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

const messageView = (m, userId) => ({
  ...m.toJSON(),
  text: m.deletedForEveryoneAt ? null : m.text,
  deleted: Boolean(m.deletedForEveryoneAt),
  attachment: storage.withUrl(m.attachment),
  voice: m.voice?.file ? { ...m.voice.toJSON?.(), file: storage.withUrl(m.voice.file) } : undefined,
  mine: String(m.senderId?._id || m.senderId) === String(userId), // senderId may be populated
});

// ── Shared thread endpoints (staff + patient) ──
const threads = Router();
threads.use(requireAuth);

threads.get('/:id/messages', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  const { limit } = paging(req.query, 100);
  const q = { conversationId: convo._id, hiddenFor: { $ne: req.user._id } };
  if (req.query.before) q.createdAt = { $lt: new Date(req.query.before) };
  const msgs = (await M.Message.find(q).sort({ createdAt: -1 }).limit(limit).populate('senderId', 'name')).reverse();
  const pinned = convo.pinnedMessageId ? await M.Message.findById(convo.pinnedMessageId) : null;
  const patient = convo.patientId ? await M.Patient.findById(convo.patientId, 'name userId') : null;
  const lastSeen = patient?.userId ? convo.participants.find((p) => String(p.userId) === String(patient.userId))?.lastReadAt : null;
  const patientIsOnlyPatient = Boolean(patient?.userId) && !(convo.practiceId && (await M.Member.exists({ userId: patient.userId, practiceId: convo.practiceId, status: 'active' })));
  // The thread's own patient gets quick replies picked from the latest message and their day.
  const suggestions = patient?.userId && String(patient.userId) === String(req.user._id) && !req.query.before
    ? await patientSuggestions(convo, msgs).catch(() => [])
    : undefined;
  const nextVisit = convo.patientId ? await M.Appointment.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, startAt: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting'] } }).sort({ startAt: 1 }) : null;
  // Shared records show as cards ("HbA1c · 7.4%, shared report · 30 Sep").
  const recIds = msgs.filter((m) => m.recordId).map((m) => m.recordId);
  const recs = recIds.length ? await M.MedicalRecord.find({ _id: { $in: recIds } }, 'kind title recordDate sourceName flagLabel') : [];
  const recordOf = (m) => {
    const x = m.recordId && recs.find((r) => String(r._id) === String(m.recordId));
    return x ? { id: x._id, kind: x.kind, title: x.title, date: x.recordDate, sourceName: x.sourceName, flagLabel: x.flagLabel } : undefined;
  };
  res.json({
    conversation: {
      ...convo.toJSON(),
      aiPaused: Boolean(convo.aiPausedAt && convo.aiPausedAt > T.addMinutes(new Date(), -10)),
      patient: patient && {
        id: patient._id, name: patient.name, lastSeenAt: lastSeen,
        photo: patient.userId ? (await require('../services/photos').photosFor([patient.userId])).get(String(patient.userId)) || null : null,
      },
      nextVisit: nextVisit && { startAt: nextVisit.startAt, token: String(nextVisit.tokenNo).padStart(2, '0') },
    },
    pinned: pinned && !pinned.deletedForEveryoneAt ? messageView(pinned, req.user._id) : null,
    suggestions,
    items: msgs.map((m) => {
      const v = { ...messageView(m, req.user._id), record: recordOf(m) };
      // Older messages the thread's patient sent while listed with another role: shown as theirs.
      if (patientIsOnlyPatient && String(m.senderId?._id || m.senderId) === String(patient.userId) && v.senderType !== 'patient' && v.senderType !== 'system') v.senderType = 'patient';
      return v;
    }),
  });
});

threads.post('/:id/messages', upload.single('file'), async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  const senderType = await senderTypeFor(req, convo);
  const text = String(req.body.text || '').trim();
  const extra = {};
  let kind = 'text';
  if (req.file) {
    const f = await storage.save(req.file.buffer, { folder: 'chat', name: req.file.originalname, mimeType: req.file.mimetype });
    if (req.file.mimetype.startsWith('audio/')) {
      kind = 'voice';
      extra.voice = { file: f, durationSec: Number(req.body.durationSec) || undefined };
    } else {
      kind = 'attachment';
      extra.attachment = f;
    }
  }
  if (req.body.recordId) {
    const rec = await M.MedicalRecord.findOne({ _id: req.body.recordId, patientId: convo.patientId });
    if (!rec) throw notFound('Record');
    kind = 'record';
    extra.recordId = rec._id;
    // Sharing a record in chat shares it with the care team in this thread.
    const staffIds = convo.participants.filter((p) => p.role !== 'patient').map((p) => String(p.userId));
    const already = new Set(rec.sharedWith.map((s) => String(s.userId)));
    for (const id of staffIds) if (!already.has(id)) rec.sharedWith.push({ userId: id });
    await rec.save();
  }
  if (!text && kind === 'text') throw badRequest('Type a message', 'EMPTY_MESSAGE');
  if (req.body.replyToId) extra.replyToId = req.body.replyToId;
  const msg = await postMessage(convo, { sender: req.user, senderType, text: text || undefined, kind, isUrgent: req.body.isUrgent === true || req.body.isUrgent === 'true', ...extra });
  // Staff replying pauses the AI in this thread for a while.
  if (senderType !== 'patient') {
    convo.aiPausedBy = req.user._id;
    convo.aiPausedAt = new Date();
    if (convo.triage === 'needs_attention') convo.triage = undefined;
    await convo.save();
  }
  // The message is saved: answer now. MedPin AI's reply (and the emergency
  // check) runs in the background and arrives in the thread a moment later;
  // aiPending tells the app to show "MedPin AI is typing…".
  let aiPending = false;
  if (senderType === 'patient' && text) {
    aiPending = await assistant.willReplyInCareThread(convo).catch(() => false);
    setImmediate(() => {
      assistant.replyInCareThread(convo, msg).catch((err) => console.warn('[ai reply]', err.message));
    });
  }
  res.status(201).json({ message: messageView(msg, req.user._id), aiReply: null, aiPending });
});

threads.post('/:id/read', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  await markRead(convo, req.user._id);
  const isStaff = convo.participants.find((p) => String(p.userId) === String(req.user._id))?.role !== 'patient';
  if (isStaff && req.body.pauseAi !== false) {
    convo.aiPausedBy = req.user._id;
    convo.aiPausedAt = new Date();
    await convo.save();
  }
  res.json({ ok: true });
});

threads.post('/:id/pin', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  if (req.body.messageId) {
    const msg = await M.Message.findOne({ _id: req.body.messageId, conversationId: convo._id });
    if (!msg) throw notFound('Message');
  }
  convo.pinnedMessageId = req.body.messageId || undefined;
  await convo.save();
  res.json({ ok: true, pinnedMessageId: convo.pinnedMessageId || null });
});

threads.post('/:id/messages/:messageId/hide', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  await M.Message.updateOne({ _id: req.params.messageId, conversationId: convo._id }, { $addToSet: { hiddenFor: req.user._id } });
  res.json({ ok: true });
});

threads.delete('/:id/messages/:messageId', async (req, res) => {
  const convo = await openConversation(req, req.params.id);
  const msg = await M.Message.findOne({ _id: req.params.messageId, conversationId: convo._id });
  if (!msg) throw notFound('Message');
  if (String(msg.senderId) !== String(req.user._id)) throw forbidden('You can only delete your own messages');
  msg.deletedForEveryoneAt = new Date();
  await msg.save();
  await messageDeleted(convo, msg);
  res.json({ ok: true });
});

// ── Staff inbox ──
const inbox = Router();
inbox.use(requireAuth, staff({ perm: 'chats' }));

inbox.get('/', async (req, res) => {
  const type = req.query.type || 'care';
  const q = type === 'direct'
    ? { type: 'direct', 'participants.userId': req.user._id }
    : { practiceId: req.practiceId, type: { $in: type === 'all' ? ['care', 'nutrition'] : [type] } };
  const convos = await M.Conversation.find(q).sort({ 'lastMessage.at': -1 }).limit(300).populate('patientId', 'name gender ageYears ageRecordedAt phone conditions userId');
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
  }));
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    rows = rows.filter((x) => re.test(x.patient?.name || '') || re.test(x.lastMessage?.text || '') || re.test(x.lastMessage?.senderLabel || ''));
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
    const convo = await careConversation(req.body.patientId, req.practiceId, req.body.type === 'nutrition' ? 'nutrition' : 'care');
    await ensureParticipant(convo, req.user._id, req.member.role === 'doctor' ? 'doctor' : 'staff');
    return res.json(convo);
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
      participants: [{ userId: req.user._id, role: req.member.role === 'doctor' ? 'doctor' : 'staff' }, { userId: other._id, role: otherMember ? (otherMember.role === 'doctor' ? 'doctor' : 'staff') : 'colleague' }],
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
  const pts = await M.Patient.find(pq, 'name phone gender ageYears ageRecordedAt dateOfBirth').limit(1000);
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
  res.json({
    patients: rows.map(({ p, at }) => ({ id: p._id, name: p.name, phone: p.phone, age: T.ageFrom(p), gender: p.gender, today: status.get(String(p._id)) || null, lastActiveAt: at })),
    team: team.filter((m) => m.userId && match(m.userId.name, m.userId.phone)).map((m) => ({ userId: m.userId._id, name: m.userId.name, role: m.role, department: m.departmentId?.name })),
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

// MedPin AI's memory.
//
// 1. Within a conversation: the newest turns go to the model as they are; older turns
//    are condensed into the session's summary (kept up to date after each answer), so a
//    long chat isn't silently cut off.
// 2. Between conversations: short notes (AiMemory) the AI keeps about the person it talks
//    to — a doctor's way of working, a patient's routine, food, goals and what they asked
//    it to remember. "Remember …" / "Forget …" in a chat work; the owner sees, adds and
//    deletes the notes in the app and can turn memory off.
// 3. Who the conversation is about: patients named in earlier questions stay in context
//    ("and her HbA1c?").
//
// Safety: a doctor's notes never hold patient details (those belong in the record — a
// note naming a patient here is dropped). A patient's health notes are what they said,
// not checked by a doctor: the record wins when they differ.
const M = require('../models');
const ai = require('./ai');

const MAX_NOTES = 40; // per person: the least recently used go first
const KEEP_TURNS = 30; // messages sent as they are; older ones are in the summary
const SUMMARY_EVERY = 6; // condense once this many messages have fallen out of the window
const SESSION_PATIENTS = 3;

const KINDS = ['preference', 'about', 'routine', 'goal', 'health_note'];
const clean = (s) => String(s || '').replace(/\s+/g, ' ').trim().slice(0, 240);
const owner = ({ ownerType, userId, patientId }) => ({ ownerType, userId, ...(ownerType === 'patient' ? { patientId } : {}) });

async function enabledFor(userId) {
  const u = await M.User.findById(userId, 'aiMemory').lean();
  return u?.aiMemory !== false;
}

// Notes are shown to their owner ("What MedPin AI remembers"): written in their app language.
const NOTE_LANGUAGE = { en: 'English', bn: 'Bengali (Bengali script)', hi: 'Hindi (Devanagari script)' };

/** The notes for [who], newest first (and marks them used). */
async function notesFor(who) {
  if (!(await enabledFor(who.userId))) return [];
  const notes = await M.AiMemory.find(owner(who)).sort({ updatedAt: -1 }).limit(MAX_NOTES).lean();
  if (notes.length) await M.AiMemory.updateMany({ _id: { $in: notes.map((n) => n._id) } }, { lastUsedAt: new Date() }, { timestamps: false });
  return notes;
}

/** The system-prompt part with [notes] for a doctor or a patient. */
function notesPrompt(notes, ownerType) {
  if (!notes.length) return '';
  const lines = notes.map((n) => `- [${n.kind}] ${n.text}`).join('\n');
  return ownerType === 'doctor'
    ? `What you remember about this doctor from earlier conversations (they can see and delete these). Follow their preferences unless this question asks otherwise; don't mention these notes unless it helps:\n${lines}`
    : `What this patient told you in earlier conversations (they can see and delete these). Use it to make answers fit their life (routine, food, goals). Health notes are what the patient said, not checked by a doctor: their record wins when they differ, and never treat a note as a diagnosis. Don't recite these notes unless it helps:\n${lines}`;
}

/** The session's condensed earlier turns, for the system prompt. */
function summaryPrompt(session) {
  return session.summary ? `Earlier in this conversation (condensed): ${session.summary}` : '';
}

/** The last [KEEP_TURNS] messages of the session, as model messages. */
async function recentTurns(session, { excludeId } = {}) {
  const history = await M.AiMessage.find({ sessionId: session._id, ...(excludeId ? { _id: { $ne: excludeId } } : {}) }).sort({ createdAt: -1 }).limit(KEEP_TURNS);
  const messages = history.reverse().map((m) => ({ role: m.role, content: m.text || '' })).filter((m) => m.content);
  while (messages.length && messages[0].role !== 'user') messages.shift();
  return messages;
}

/**
 * Patients this doctor's conversation is about: the chip, the ones named now, then the ones
 * named earlier (kept on the session for the next question).
 */
async function sessionPatients(session, mentioned) {
  const ids = [];
  const add = (id) => id && !ids.some((x) => String(x) === String(id)) && ids.push(id);
  add(session.patientId);
  for (const p of mentioned) add(p._id);
  for (const id of session.patientIds || []) add(id);
  const keep = ids.filter((id) => String(id) !== String(session.patientId || '')).slice(0, SESSION_PATIENTS);
  if (JSON.stringify(keep.map(String)) !== JSON.stringify((session.patientIds || []).map(String))) {
    await M.AiSession.updateOne({ _id: session._id }, { patientIds: keep });
    session.patientIds = keep;
  }
  return ids.slice(0, SESSION_PATIENTS);
}

const LEARN_SCHEMA = {
  type: 'object',
  properties: {
    add: { type: 'array', items: { type: 'object', properties: { text: { type: 'string' }, kind: { type: 'string', enum: KINDS } }, required: ['text', 'kind'], additionalProperties: false } },
    update: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, text: { type: 'string' } }, required: ['id', 'text'], additionalProperties: false } },
    remove: { type: 'array', items: { type: 'string' } },
  },
  required: ['add', 'update', 'remove'],
  additionalProperties: false,
};

const LEARN_RULES = {
  doctor: [
    'You keep short notes about a doctor that will help MedPin AI assist them in later conversations.',
    'Keep: how they like answers (length, bullets, language, units), guidelines or first-line choices they say they follow, their routine and practice set-up (clinic days, focus areas), and anything they explicitly ask you to remember.',
    'Never keep anything about a particular patient (names, results, conditions): that belongs in the patient record, not in notes. Never keep one-off questions, passwords, codes, phone numbers or payment details.',
  ],
  patient: [
    'You keep short notes about a patient that will help MedPin AI answer them better in later conversations.',
    'Keep lasting facts they tell you about themselves: daily routine and work shifts, food habits (vegetarian, fasting days), activity, who helps them with medicines, goals, how they like things explained, and anything they explicitly ask you to remember. A health fact they state (an allergy, a medicine they take elsewhere, pregnancy) is kept as kind health_note in their words, e.g. "Says they are allergic to sulfa drugs".',
    'Never keep passing symptoms of the day, one-off questions, passwords, OTP codes, phone numbers or payment details.',
  ],
};

/** Applies the model's changes to [who]'s notes (also used by the tests). */
async function applyChanges(who, changes, { sessionId, practiceId } = {}) {
  const notes = await M.AiMemory.find(owner(who)).lean();
  const mine = new Map(notes.map((n) => [String(n._id), n]));
  // A doctor's note that names a patient of this clinic is dropped (that's the record's job).
  const namesPatient = async (text) => {
    if (who.ownerType !== 'doctor' || !practiceId) return false;
    const { patientsMentioned } = require('./practice_brief');
    return (await patientsMentioned(text, practiceId, 1)).length > 0;
  };
  const removed = (changes.remove || []).filter((id) => mine.has(String(id)));
  if (removed.length) await M.AiMemory.deleteMany({ _id: { $in: removed } });
  for (const u of changes.update || []) {
    const text = clean(u.text);
    if (!text || !mine.has(String(u.id)) || removed.includes(u.id) || (await namesPatient(text))) continue;
    await M.AiMemory.updateOne({ _id: u.id }, { text });
  }
  const have = new Set(notes.filter((n) => !removed.includes(String(n._id))).map((n) => n.text.toLowerCase()));
  for (const a of changes.add || []) {
    const text = clean(a.text);
    if (text.length < 3 || have.has(text.toLowerCase()) || (await namesPatient(text))) continue;
    have.add(text.toLowerCase());
    await M.AiMemory.create({ ...owner(who), text, kind: KINDS.includes(a.kind) ? a.kind : 'about', source: 'chat', sessionId });
  }
  // At most MAX_NOTES: the ones not used or changed for longest go.
  const all = await M.AiMemory.find(owner(who), '_id').sort({ updatedAt: -1 }).lean();
  if (all.length > MAX_NOTES) await M.AiMemory.deleteMany({ _id: { $in: all.slice(MAX_NOTES).map((n) => n._id) } });
}

// Short small talk ("ok", "thanks") has nothing to remember; "remember / forget" always counts.
const ASKS_MEMORY = /\b(remember|forget|don'?t forget|note that|keep in mind)\b|মনে রাখ|ভুলে যা|মনে রেখ|याद रख|भूल जा|ध्यान रख|yaad rakh|bhool ja|mone rakh|bhule ja/i;
const worthLearning = (question) => ASKS_MEMORY.test(question) || String(question || '').trim().length >= 25;

/** After an answer: updates [who]'s notes from this exchange (quietly; never fails the chat). */
async function learn(who, { question, answer, sessionId, practiceId }) {
  if (!ai.enabled() || !worthLearning(question) || !(await enabledFor(who.userId))) return;
  const lang = NOTE_LANGUAGE[(await M.User.findById(who.userId, 'language').lean())?.language] || NOTE_LANGUAGE.en;
  const notes = await M.AiMemory.find(owner(who)).sort({ updatedAt: -1 }).limit(MAX_NOTES).lean();
  const out = await ai.completeJson({
    system: [
      ...LEARN_RULES[who.ownerType],
      'You get the current notes (with ids) and the latest exchange. Return only changes: add new lasting facts, update a note that is now different (same id), remove notes the person says are wrong or asks you to forget ("forget that I…"). Most exchanges need no change: return empty lists.',
      `Write each new or updated note as one short line in ${lang}, in the third person, without dates or the person's name; keep medicine names and numbers as written. Don't add what a note already says, in any language.`,
    ].join('\n'),
    messages: [{ role: 'user', content: JSON.stringify({ notes: notes.map((n) => ({ id: String(n._id), kind: n.kind, text: n.text })), they_said: question, medpin_ai_answered: String(answer || '').slice(0, 1500) }) }],
    schema: LEARN_SCHEMA,
    effort: 'low',
    maxTokens: 800,
  });
  if (out?.data) await applyChanges(who, out.data, { sessionId, practiceId });
}

/** Condenses the turns that fell out of the window into the session summary. */
async function summarize(session) {
  if (!ai.enabled()) return;
  const newest = await M.AiMessage.find({ sessionId: session._id }, 'createdAt').sort({ createdAt: -1 }).skip(KEEP_TURNS - 1).limit(1).lean();
  if (!newest.length) return; // everything still fits
  const windowStart = newest[0].createdAt;
  const pending = await M.AiMessage.find({
    sessionId: session._id, createdAt: { $lt: windowStart, ...(session.summarizedUntil ? { $gt: session.summarizedUntil } : {}) },
  }).sort({ createdAt: 1 }).limit(80).lean();
  if (pending.length < SUMMARY_EVERY) return;
  const out = await ai.completeJson({
    system: 'Update the running summary of a conversation with MedPin AI. Keep what later questions may refer back to: who and what was discussed, values and dates quoted, decisions, open questions, and what the person asked to be done. At most 180 words, plain text, in English.',
    messages: [{ role: 'user', content: JSON.stringify({ summary_so_far: session.summary || '', earlier_messages: pending.map((m) => ({ role: m.role, text: String(m.text || '').slice(0, 1200) })) }) }],
    schema: { type: 'object', properties: { summary: { type: 'string' } }, required: ['summary'], additionalProperties: false },
    effort: 'low',
    maxTokens: 600,
  });
  if (!out?.data?.summary) return;
  // Only if nobody else summarized meanwhile (two answers finishing together).
  await M.AiSession.updateOne(
    { _id: session._id, summarizedUntil: session.summarizedUntil || null },
    { summary: out.data.summary.slice(0, 2000), summarizedUntil: pending[pending.length - 1].createdAt },
  );
}

/** After each answer, in the background: learn and keep the summary up to date. */
function afterAnswer(session, who, exchange) {
  setImmediate(() => {
    Promise.all([
      learn(who, { ...exchange, sessionId: session._id }).catch((err) => console.warn('[ai memory]', err.message)),
      summarize(session).catch((err) => console.warn('[ai summary]', err.message)),
    ]);
  });
}

// ── The "What MedPin AI remembers" screen ──
const view = (n) => ({ id: n._id, text: n.text, kind: n.kind, source: n.source, createdAt: n.createdAt, updatedAt: n.updatedAt });

async function list(who) {
  const [u, items] = await Promise.all([M.User.findById(who.userId, 'aiMemory').lean(), M.AiMemory.find(owner(who)).sort({ updatedAt: -1 }).limit(MAX_NOTES).lean()]);
  return { enabled: u?.aiMemory !== false, max: MAX_NOTES, items: items.map(view) };
}

async function add(who, text) {
  const t = clean(text);
  if (t.length < 3) return null;
  const existing = await M.AiMemory.findOne({ ...owner(who), text: t });
  if (existing) return view(existing);
  const n = await M.AiMemory.create({ ...owner(who), text: t, kind: 'about', source: 'added' });
  await applyChanges(who, {}); // keeps the cap
  return view(n);
}

const remove = (who, id) => M.AiMemory.deleteOne({ ...owner(who), _id: id });
const clear = (who) => M.AiMemory.deleteMany(owner(who));

/** Memory off: nothing new is kept, and what was kept is forgotten. */
async function setEnabled(who, enabled) {
  await M.User.updateOne({ _id: who.userId }, { aiMemory: Boolean(enabled) });
  if (!enabled) await M.AiMemory.deleteMany({ userId: who.userId });
}

module.exports = {
  notesFor, notesPrompt, summaryPrompt, recentTurns, sessionPatients, afterAnswer, applyChanges, learn, summarize,
  list, add, remove, clear, setEnabled, worthLearning, KEEP_TURNS,
};

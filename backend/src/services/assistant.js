// MedPin AI: patient chat replies (grounded in the practice knowledge base and
// flagged for doctor review), the doctor assistant, patient "Ask AI",
// daily chat summaries, and reading lab reports into structured results.
const storage = require('./storage');
const M = require('../models');
const T = require('../lib/time');
const ai = require('./ai');
const { conflict } = require('../lib/http');
const { patientSummary } = require('./clinical');
const { postMessage, raiseAlert } = require('./care');
const { notify, signal, clinicians } = require('./notify');

// Emergency words in English, Bengali and Hindi (and how they are often typed in English letters).
const EMERGENCY_WORDS = [
  'chest pain', 'chest tightness', "can't breathe", 'cannot breathe', 'not breathing', 'hard to breathe', 'faint',
  'unconscious', 'stroke', 'severe bleeding', 'heart attack', 'seizure', 'suicide', 'kill myself',
  // Bengali
  'বুকে ব্যথা', 'বুকে চাপ', 'শ্বাস নিতে পারছি না', 'শ্বাসকষ্ট', 'নিঃশ্বাস নিতে কষ্ট', 'অজ্ঞান', 'স্ট্রোক', 'খুব রক্ত', 'রক্তপাত', 'হার্ট অ্যাটাক', 'খিঁচুনি', 'আত্মহত্যা', 'মরে যেতে চাই',
  // Hindi
  'सीने में दर्द', 'छाती में दर्द', 'सांस नहीं', 'साँस नहीं', 'सांस लेने में', 'साँस लेने में', 'बेहोश', 'स्ट्रोक', 'बहुत खून', 'दिल का दौरा', 'हार्ट अटैक', 'दौरा पड़', 'आत्महत्या', 'मरना चाहता', 'मरना चाहती',
  // In English letters
  'seene me dard', 'seene mein dard', 'chhati me dard', 'saans nahi', 'sans nahi', 'behosh', 'buke byatha', 'shash nite parchi na',
];
const isEmergencyText = (text) => EMERGENCY_WORDS.some((w) => String(text || '').toLowerCase().includes(w));
const AI_PAUSE_MIN = 10;

// ── Languages (English, Bengali, Hindi) ──
const LANG_NAMES = { en: 'English', bn: 'Bengali (বাংলা)', hi: 'Hindi (हिन्दी)' };
/**
 * How MedPin AI picks its language: the person's own latest message first
 * (script included — Bengali or Hindi typed in English letters is answered the
 * same way), their app language when that is unclear.
 */
function languageRule(appLang, { clinician = false } = {}) {
  const fallback = LANG_NAMES[appLang] || 'English';
  return [
    'Language: reply in the language and script of the latest message you are answering — Bengali in Bengali script, Hindi in Devanagari, English in English.',
    'If they wrote Bengali or Hindi in English letters (e.g. "amar sugar kom hoye geche", "mera sugar badh gaya hai"), reply in that language in the same English letters.',
    `If the message is only a photo, a number or a word that could be any language, reply in ${fallback} (their app language).`,
    'Keep medicine names, test names, units and numbers exactly as written (Metformin 500 mg, HbA1c 7.4%, BP 140/90). Never mix two languages in one sentence.',
    clinician
      ? 'Keep standard clinical terms in English where doctors use them.'
      : 'Use the simple everyday words a patient uses at home, not textbook terms; address them politely (Bengali আপনি, Hindi आप).',
  ].join(' ');
}

/** A short fixed line in the person's app language. */
const LINES = {
  aiOffPatient: {
    en: 'MedPin AI is not available right now. You can message your doctor from the Doctors tab.',
    bn: 'MedPin AI এখন চালু নেই। Doctors ট্যাব থেকে আপনার ডাক্তারকে মেসেজ করতে পারেন।',
    hi: 'MedPin AI अभी उपलब्ध नहीं है। Doctors टैब से अपने डॉक्टर को संदेश भेज सकते हैं।',
  },
  emergency: {
    en: 'This could be serious. Please call 108 or go to the nearest emergency department now, and use Emergency in the app to alert your doctor.',
    bn: 'এটা গুরুতর হতে পারে। এখনই 108-এ ফোন করুন বা কাছের ইমার্জেন্সিতে যান, আর অ্যাপের Emergency দিয়ে ডাক্তারকে জানান।',
    hi: 'यह गंभीर हो सकता है। अभी 108 पर कॉल करें या नज़दीकी इमरजेंसी में जाएँ, और ऐप में Emergency से अपने डॉक्टर को बताएँ।',
  },
  failed: {
    en: "MedPin AI couldn't answer just now. Please try again, or message your doctor from the Doctors tab.",
    bn: 'MedPin AI এই মুহূর্তে উত্তর দিতে পারেনি। আবার চেষ্টা করুন, বা Doctors ট্যাব থেকে ডাক্তারকে মেসেজ করুন।',
    hi: 'MedPin AI अभी जवाब नहीं दे सका। फिर कोशिश करें, या Doctors टैब से अपने डॉक्टर को संदेश भेजें।',
  },
  cantAnswer: {
    en: "I can't answer that safely here. Please ask your doctor — you can message them from the Doctors tab.",
    bn: 'এটার উত্তর এখানে নিরাপদে দিতে পারছি না। আপনার ডাক্তারকে জিজ্ঞাসা করুন — Doctors ট্যাব থেকে মেসেজ করতে পারেন।',
    hi: 'इसका जवाब मैं यहाँ सुरक्षित रूप से नहीं दे सकता। कृपया अपने डॉक्टर से पूछें — Doctors टैब से संदेश भेज सकते हैं।',
  },
};
const line = (key, lang) => LINES[key][['bn', 'hi'].includes(lang) ? lang : 'en'];
/** A patient's app language (en | bn | hi). */
async function patientLanguage(patient) {
  if (!patient?.userId) return 'en';
  return (await M.User.findById(patient.userId, 'language'))?.language || 'en';
}
// A burst of messages ("hi" / "my sugar is 250" / "what do I do") gets one reply: wait a moment.
const gatherMs = () => Number(process.env.AI_GATHER_MS ?? 2500);
// "Talk to the clinic": MedPin AI stays out for up to a day, or until the clinic replies.
const AI_HUMAN_HOURS = 24;
// The clinic is "in the thread" while its open screen keeps refreshing (every 4 s).
const AI_VIEWING_MIN = 2;

/** Is MedPin AI quiet in this thread: a clinic reply in the last 10 min, or someone at the clinic has it open. */
function aiPaused(convo, now = new Date()) {
  return Boolean(
    (convo.aiPausedAt && convo.aiPausedAt > T.addMinutes(now, -AI_PAUSE_MIN))
    || (convo.staffViewingAt && convo.staffViewingAt > T.addMinutes(now, -AI_VIEWING_MIN))
    || (convo.humanRequestedAt && convo.humanRequestedAt > T.addMinutes(now, -AI_HUMAN_HOURS * 60)),
  );
}

/** Would this month's AI chat limit be passed? (Checked before answering; counted only after.) */
async function aiLimitReached(practiceId) {
  if (!practiceId) return false;
  const sub = await M.Subscription.findOne({ practiceId });
  const plan = sub ? await M.Plan.findOne({ key: sub.planKey }) : null;
  if (!plan) return false;
  const periodStart = sub?.currentPeriodStart || new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  const usage = await M.UsageCounter.findOne({ practiceId, periodStart });
  return Boolean(usage && usage.aiChats >= plan.aiChatsPerMonth);
}

/**
 * Who the patient's chat is with, for MedPin AI to answer in that field: the
 * nutrition chat's dietician; else the patient's main doctor here, else the
 * doctor of their latest visit, else any doctor on their care team.
 */
async function threadClinician(convo) {
  if (convo.type === 'nutrition') {
    const diet = await M.Member.findOne({ practiceId: convo.practiceId, status: 'active', role: 'dietician', userId: { $in: convo.participants.map((p) => p.userId) } }, 'userId');
    if (diet) return diet.userId;
  }
  const primary = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, isPrimary: true, accessLevel: { $ne: 'not_shared' } }, 'userId');
  if (primary) return primary.userId;
  const visit = await M.Appointment.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, status: { $nin: ['cancelled', 'rescheduled'] } }, 'doctorId').sort({ startAt: -1 });
  if (visit?.doctorId) return visit.doctorId;
  const any = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, accessLevel: { $ne: 'not_shared' } }, 'userId');
  return any?.userId || null;
}

// Photos / PDFs the patient sends with a question (a medicine strip, a report):
// up to 3 from the message being answered, sent to the model to read.
const AI_MAX_FILES = 3;
const AI_MAX_BYTES = 8 * 1024 * 1024;

/** The patient's files since the clinic or MedPin AI last wrote, as model blocks (photos shrunk to 1280 px). */
async function patientFiles(history) {
  const turn = [];
  for (let i = history.length - 1; i >= 0 && history[i].senderType === 'patient'; i -= 1) turn.unshift(history[i]);
  const files = turn.filter((m) => m.kind === 'attachment' && m.attachment?.key && /^image\/|^application\/pdf$/.test(m.attachment.mimeType || '')).slice(-AI_MAX_FILES);
  const blocks = [];
  for (const m of files) {
    try {
      let buf = await storage.read(m.attachment.key);
      if (!buf || buf.length > AI_MAX_BYTES) continue;
      let type = m.attachment.mimeType;
      if (type.startsWith('image/')) {
        buf = await require('sharp')(buf).rotate().resize({ width: 1280, height: 1280, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 82 }).toBuffer();
        type = 'image/jpeg';
      }
      blocks.push({ type: type === 'application/pdf' ? 'document' : 'image', source: { type: 'base64', media_type: type, data: buf.toString('base64') } });
    } catch (err) {
      console.warn('[ai photo]', err.message);
    }
  }
  return blocks;
}

// What MedPin AI may and may not do when talking to a patient.
const PATIENT_SAFETY_RULES = [
  'You are not a doctor. Never diagnose: do not say or suggest which disease or condition the patient has or might have.',
  'Never prescribe: do not recommend any medicine, supplement or home remedy by name (including over-the-counter ones), and never start, stop, skip, double or change a dose.',
  'Never order or recommend specific tests or scans. If the patient asks whether they need one, say their doctor will decide.',
  'You may: explain in plain words what is already in their own record (their prescribed medicines and instructions, test results and what the reference ranges mean), give general healthy-living information, help them prepare questions for their doctor, and say which kind of specialist usually handles a concern.',
  'If something sounds urgent or like an emergency (chest pain, trouble breathing, fainting, stroke signs, severe bleeding, thoughts of self-harm, very high or low sugar or BP readings), tell them to call 108 or go to the nearest emergency department now.',
  'Answer in the language the patient writes in, in 2-5 short sentences, warm and clear.',
].join('\n- ');

/** Plan limit for AI chats in the current cycle; increments usage. */
async function useAiChat(practiceId) {
  if (!practiceId) return;
  const sub = await M.Subscription.findOne({ practiceId });
  const plan = sub ? await M.Plan.findOne({ key: sub.planKey }) : null;
  const periodStart = sub?.currentPeriodStart || new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  const usage = await M.UsageCounter.findOneAndUpdate({ practiceId, periodStart }, { $setOnInsert: { aiChats: 0 } }, { upsert: true, new: true });
  if (plan && usage.aiChats >= plan.aiChatsPerMonth) throw conflict('AI chat limit reached for this month', 'AI_LIMIT');
  await M.UsageCounter.updateOne({ _id: usage._id }, { $inc: { aiChats: 1 } });
}

/** Approved entries for the practice: its own plus adopted MedPin entries. */
async function knowledgeFor(practiceId, query) {
  const adopted = await M.KnowledgeAdoption.find({ practiceId }).distinct('entryId');
  const base = { status: 'approved', $or: [{ practiceId }, { _id: { $in: adopted } }] };
  let entries = [];
  // Semantic match with embeddings (Gemini); entries are embedded on first use.
  if (query && ai.provider() === 'gemini') {
    try {
      const all = await M.KnowledgeEntry.find(base).select('+embedding +embeddedText').limit(300);
      const q = await ai.embed(query);
      if (q) {
        for (const e of all) {
          const text = `${e.title}\n${e.summary || ''}\n${e.content}`;
          if (!e.embedding?.length || e.embeddedText !== text) {
            e.embedding = await ai.embed(text);
            e.embeddedText = text;
            await e.save();
          }
        }
        entries = all
          .map((e) => ({ e, score: ai.cosine(q, e.embedding) }))
          .filter((x) => x.score > 0.45)
          .sort((a, b) => b.score - a.score)
          .slice(0, 6)
          .map((x) => x.e);
        if (entries.length) return entries;
      }
    } catch (err) {
      console.warn('[knowledge embed]', err.message);
    }
  }
  if (query) {
    entries = await M.KnowledgeEntry.find({ ...base, $text: { $search: query } }, { score: { $meta: 'textScore' } })
      .sort({ score: { $meta: 'textScore' } }).limit(8).catch(() => []);
  }
  if (!entries.length) entries = await M.KnowledgeEntry.find(base).sort({ updatedAt: -1 }).limit(8);
  return entries;
}

const REPLY_SCHEMA = {
  type: 'object',
  properties: {
    reply: { type: 'string' },
    urgency: { type: 'string', enum: ['none', 'low', 'medium', 'high'] },
    needs_doctor: { type: 'boolean' },
    reason: { type: 'string', enum: ['none', 'symptom_question', 'dosage_question', 'low_confidence', 'outside_knowledge_base', 'other'] },
    cited_entry_ids: { type: 'array', items: { type: 'string' } },
  },
  required: ['reply', 'urgency', 'needs_doctor', 'reason', 'cited_entry_ids'],
  additionalProperties: false,
};

const patientContext = (s) =>
  JSON.stringify({
    patient: { name: s.patient.name, age: s.patient.age, gender: s.patient.gender },
    conditions: s.conditions.map((c) => c.name),
    allergies: s.allergies.map((a) => a.allergen),
    current_medicines: s.currentMedicines.map((m) => `${m.name} ${m.strength || ''} ${m.pattern}`.trim()),
    abnormal_results: s.abnormalResults.slice(0, 8).map((r) => `${r.analyte} ${r.value} ${r.unit || ''} (${r.flag})`),
    latest_vitals: s.latestVitals && pickVitals(s.latestVitals),
    next_visit: s.nextVisit?.startAt,
  });
const pickVitals = (v) => ({ bp: v.bpSystolic && `${v.bpSystolic}/${v.bpDiastolic}`, pulse: v.pulse, spo2: v.spo2, weightKg: v.weightKg, sugar: v.bloodSugar, sugarType: v.sugarType, at: v.recordedAt });

/** Called after a patient posts in a care thread. Returns the AI message or null. */
/** Will MedPin AI answer in this thread now? (Quick: no AI call.) */
async function willReplyInCareThread(convo) {
  if (!ai.enabled() || !convo.aiEnabled || aiPaused(convo) || !['care', 'nutrition'].includes(convo.type)) return false;
  if (await aiLimitReached(convo.practiceId)) return false;
  const primary = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, isPrimary: true });
  if (primary) {
    const prof = await M.DoctorProfile.findOne({ userId: primary.userId }, 'chatSettings');
    if (prof?.chatSettings?.aiReplies === false) return false;
  }
  return true;
}

async function replyInCareThread(convo, patientMessage) {
  const urgentByWords = isEmergencyText(patientMessage.text);
  if (urgentByWords) {
    // One open emergency per chat: more messages with the same words don't raise more.
    const open = await M.Alert.exists({ conversationId: convo._id, kind: 'urgent_chat', status: { $in: ['open', 'acknowledged'] } });
    if (!open) {
      await raiseAlert({
        practiceId: convo.practiceId, patientId: convo.patientId, severity: 'emergency', kind: 'urgent_chat',
        detail: patientMessage.text.slice(0, 300), sourceModel: 'Message', sourceId: patientMessage._id, conversationId: convo._id,
      });
    }
  }
  const done = () => signal(convo.participants.filter((p) => p.role === 'patient').map((p) => p.userId), { type: 'chat_changed', conversationId: convo._id }).catch(() => {});
  if (!ai.enabled() || !['care', 'nutrition'].includes(convo.type)) return null;
  // A burst of messages gets one reply, to the newest of them.
  if (gatherMs() > 0) await new Promise((r) => setTimeout(r, gatherMs()));
  const newer = await M.Message.exists({ conversationId: convo._id, senderType: 'patient', createdAt: { $gt: patientMessage.createdAt }, deletedForEveryoneAt: null });
  if (newer) return null; // that message's reply covers this one
  // Fresh state: the clinic may have opened or answered the thread since; AI may be off for it.
  const skip = async () => {
    const now = await M.Conversation.findById(convo._id, 'aiPausedAt staffViewingAt humanRequestedAt aiEnabled');
    if (!now || !now.aiEnabled || aiPaused(now)) return true;
    return Boolean(await M.Message.exists({ conversationId: convo._id, senderType: { $in: ['doctor', 'staff'] }, 'meta.auto': { $ne: true }, createdAt: { $gt: patientMessage.createdAt } }));
  };
  if (await skip()) return done() && null;
  // The patient's main doctor can turn MedPin AI replies off (Chat settings).
  const primary = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, isPrimary: true });
  if (primary) {
    const prof = await M.DoctorProfile.findOne({ userId: primary.userId }, 'chatSettings');
    if (prof?.chatSettings?.aiReplies === false) return done() && null;
  }
  if (await aiLimitReached(convo.practiceId)) return done() && null;
  // Answer in the field of the doctor (or dietician) this chat is with.
  const clinicianId = await threadClinician(convo);
  const who = clinicianId ? await doctorContext(clinicianId, convo.practiceId) : null;

  const patient = await M.Patient.findById(convo.patientId);
  const summary = await patientSummary(patient, convo.practiceId);
  const lang = await patientLanguage(patient);
  const kb = await knowledgeFor(convo.practiceId, patientMessage.text);
  const history = (await M.Message.find({ conversationId: convo._id, deletedForEveryoneAt: null }).sort({ createdAt: -1 }).limit(20)).reverse();
  const practice = await M.Practice.findById(convo.practiceId, 'name');
  // What the patient told MedPin AI earlier (routine, food, goals) — on their own account.
  const memory = require('./ai_memory');
  const notes = patient?.userId ? await memory.notesFor({ ownerType: 'patient', userId: patient.userId, patientId: patient._id }) : [];

  const name = who?.parts?.name || null;
  const system = [
    `You are the MedPin assistant for ${practice?.name || 'the clinic'}, replying to a patient in their chat with the care team.`,
    who && name
      ? `This chat is with ${name}${who.field ? ` (${who.field})` : ''}${who.parts.conditions_they_treat?.length ? `, who treats ${[].concat(who.parts.conditions_they_treat).slice(0, 12).join(', ')}` : ''}. Answer as their clinic's assistant, within that field. A question outside it (another part of the body, another specialty): give only general safe guidance, say ${name} will advise or may refer them to the right doctor, and set needs_doctor true. Refer to them as ${name} or "your doctor".`
      : '',
    convo.type === 'nutrition' ? 'This is the nutrition chat: food, meals, diet plans and food logs. Keep to general, safe nutrition guidance from the clinic knowledge entries; the dietician sets the plan.' : '',
    languageRule(lang),
    `Rules:\n- ${PATIENT_SAFETY_RULES}\n- Questions about doses, new symptoms, test needs or changing treatment: say the doctor will confirm, and set needs_doctor true.`,
    'Ground medical guidance in the clinic knowledge entries below and cite their ids. If the answer is not covered there, keep it general, say the care team will follow up, and set reason to outside_knowledge_base.',
    'Set urgency high and needs_doctor true for anything that could be an emergency, and tell the patient to call 108 or go to the nearest emergency department.',
    'Photos and PDFs the patient sent are attached to their message. Read what is printed on them. A medicine strip, box or bottle: give the name and strength you can read; if it matches a medicine in the patient record, say so and repeat how their doctor prescribed it (dose, times, with or without food); if it is not on their list, say so, tell them not to take it until their doctor confirms, and set needs_doctor true. You may say in plain words what that kind of medicine is generally used for. A prescription or report: say briefly what it shows without interpreting results as a diagnosis; their doctor will review it. A photo of the body (rash, wound, swelling): do not describe a cause; say the doctor will look at it and set needs_doctor true. If the photo is blurred or the label is not visible, ask for a clear photo of the label. Never guess a name you cannot read.',
    `Patient record (JSON): ${patientContext(summary)}`,
    memory.notesPrompt(notes, 'patient'),
    `Clinic knowledge entries (JSON): ${JSON.stringify(kb.map((k) => ({ id: String(k._id), title: k.title, content: k.content })))}`,
  ].filter(Boolean).join('\n\n');
  const fileLabel = (m) => (m.kind === 'attachment' ? (/^image\//.test(m.attachment?.mimeType || '') ? '[photo]' : '[file]') : m.kind === 'voice' ? '[voice message]' : m.kind === 'record' ? '[shared record]' : '');
  const messages = [];
  for (const m of history) {
    const role = m.senderType === 'patient' ? 'user' : 'assistant';
    const content = m.senderType === 'patient' ? [fileLabel(m), m.text].filter(Boolean).join(' ') || '[attachment]' : `${m.senderType === 'ai' ? '' : `[${m.senderType}] `}${m.text || ''}`;
    if (messages.length && messages[messages.length - 1].role === role) messages[messages.length - 1].content += `\n${content}`;
    else messages.push({ role, content });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift();
  if (!messages.length) return null;
  // The photos / PDFs of the message being answered go with it, for the model to read.
  const files = await patientFiles(history);
  const last = messages[messages.length - 1];
  if (files.length && last.role === 'user') last.content = [{ type: 'text', text: last.content }, ...files];

  // Chat replies are short: low effort keeps them quick.
  const out = await ai.completeJson({ system, messages, schema: REPLY_SCHEMA, effort: 'low', vision: files.length > 0 });
  // No answer (model down, refused): the patient's "typing…" stops; the clinic replies as usual.
  if (!out || out.refused || !out.data) return done() && null;
  // The clinic answered while the model was thinking: theirs stands.
  if (await skip()) return done() && null;
  await useAiChat(convo.practiceId).catch(() => {}); // counted only when an answer is sent
  const d = out.data;
  const flagged = d.needs_doctor || d.reason !== 'none' || ['medium', 'high'].includes(d.urgency) || urgentByWords;
  const citations = kb.filter((k) => d.cited_entry_ids.includes(String(k._id))).map((k) => ({ label: k.sourceCitation || k.title, knowledgeEntryId: k._id }));
  const msg = await postMessage(convo, {
    sender: null,
    senderType: 'ai',
    text: d.reply,
    ai: {
      flagged, urgency: d.urgency === 'none' ? 'low' : d.urgency, responseSource: 'model', fallbackUsed: false,
      latencyMs: out.latencyMs, aiModel: out.model, citations, escalated: d.needs_doctor,
    },
  });
  if (flagged) {
    const urgency = d.urgency === 'high' || urgentByWords ? 'high' : d.urgency === 'medium' ? 'medium' : 'low';
    const review = await M.ChatReview.create({
      practiceId: convo.practiceId, patientId: convo.patientId, conversationId: convo._id, messageId: msg._id,
      reason: d.reason === 'none' ? 'other' : d.reason, title: (patientMessage.text || 'Photo').slice(0, 80), excerpt: d.reply.slice(0, 200),
      urgency,
    });
    // The doctor (dietician) the chat is with hears about it: a push when it's urgent, else the bell.
    const toldIds = clinicianId ? [clinicianId] : await clinicians(convo.practiceId, convo.patientId);
    await notify(toldIds, {
      type: 'chat_review', practiceId: convo.practiceId, push: urgency === 'high',
      title: `MedPin AI asked you to check a reply to ${patient?.name || 'a patient'}`,
      body: (patientMessage.text || 'Photo').slice(0, 120), screen: 'Chat-Review-Detail', params: { reviewId: review._id, conversationId: convo._id },
    }).catch((err) => console.warn('[chat review notice]', err.message));
  }
  return msg;
}

/** "Dr. Arjun Sen — Diabetologist · Internal medicine (Endocrinology department) …" for the prompt. */
async function doctorContext(userId, practiceId) {
  const [profile, member] = await Promise.all([
    M.DoctorProfile.findOne({ userId }),
    M.Member.findOne({ userId, practiceId }).populate('departmentId', 'name'),
  ]);
  const specialties = await M.Specialty.find({ key: { $in: profile?.specialtyKeys || [] } }, 'aiRole');
  const parts = {
    name: profile?.displayName,
    profession: profile?.profession || member?.role,
    headline: profile?.headline,
    specialisations: profile?.specialisations?.length ? profile.specialisations : specialties.map((x) => x.aiRole),
    department: member?.departmentId?.name,
    conditions_they_treat: profile?.conditionsTreated,
    qualifications: profile?.degreesSummary,
  };
  const field = [parts.headline, ...(parts.specialisations || []), parts.department].filter(Boolean);
  return { parts, field: [...new Set(field)].join(', ') };
}

/** Doctor assistant answer in an AI session. */
async function doctorAnswer(session, question, practiceId, { excludeId } = {}) {
  if (!ai.enabled()) {
    return { text: 'The AI assistant is not set up yet. Add GEMINI_API_KEY (or ANTHROPIC_API_KEY) to the backend .env to turn it on.', scripted: true };
  }
  await useAiChat(practiceId);
  const doc = await doctorContext(session.userId, practiceId);
  let context = '';
  const { accessFor } = require('./access');
  const { practiceBrief, patientsMentioned } = require('./practice_brief');
  const memory = require('./ai_memory');
  // The patient this chat is about, anyone the question names ("How is Priya's sugar?"), and
  // the ones named earlier in this conversation ("and her HbA1c?"). Still linked here only;
  // only what this doctor may see of each patient goes to the AI.
  const ids = await memory.sessionPatients(session, await patientsMentioned(question, practiceId));
  const linked = new Set((await M.PatientEnrolment.find({ patientId: { $in: ids }, practiceId, status: 'linked' }).distinct('patientId')).map(String));
  const found = await M.Patient.find({ _id: { $in: ids.filter((id) => linked.has(String(id))) } });
  const about = ids.map((id) => found.find((p) => String(p._id) === String(id))).filter(Boolean);
  for (const patient of about) {
    const acc = await accessFor({ userId: session.userId, practiceId }, patient);
    context += `\n\nPatient ${patient.name} (JSON): ${patientContext(await patientSummary(patient, practiceId, acc))}`;
  }
  const [today, brief, kb] = await Promise.all([
    M.Appointment.find({ practiceId, doctorId: session.userId, date: T.dayStart() }).populate('patientId', 'name'),
    practiceBrief(session.userId, practiceId),
    knowledgeFor(practiceId, question).catch(() => []),
  ]);
  // Earlier turns of this chat (the newest as they are, older ones condensed); the new
  // question is added once, at the end. Notes kept from earlier conversations.
  const messages = await memory.recentTurns(session, { excludeId });
  messages.push({ role: 'user', content: question });
  const notes = await memory.notesFor({ ownerType: 'doctor', userId: session.userId });
  const system = [
    'You are MedPin AI, a clinical assistant for a doctor in an Indian outpatient practice. Be concise and precise; use bullet points for lists. Quote values with units and dates from the record. Say clearly when something is not in the record. You support the doctor\'s judgement and do not replace it.',
    doc.field
      ? `You are assisting ${doc.parts.name || 'the doctor'}, whose field is: ${doc.field}. Answer from that specialty's point of view: lead with the findings, risks, guideline targets and follow-up that matter most in this field, use its usual terminology, and point out anything that falls outside the specialty and may need a referral (say to which specialty).`
      : '',
    `Doctor profile (JSON): ${JSON.stringify(doc.parts)}`,
    `Today: ${T.dayKey(new Date())}. Today's appointments: ${JSON.stringify(today.map((a) => ({ time: a.startAt, patient: a.patientId?.name, status: a.status, type: a.visitType })))}`,
    `This clinic's records (JSON; use for questions across patients): ${JSON.stringify(brief)}`,
    kb.length ? `The clinic's approved knowledge base (prefer it when relevant): ${JSON.stringify(kb.map((e) => ({ title: e.title, text: e.summary || e.content })))}` : '',
    'If a question needs data that is not given here, say exactly what is missing instead of guessing.',
    about.length > 1 ? `This conversation has been about: ${about.map((p) => p.name).join(', ')} (the first is the current one unless the question says otherwise). If it is unclear which patient "he", "she" or "they" means, ask.` : '',
    memory.notesPrompt(notes, 'doctor'),
    'If the doctor asks you to remember or forget something about how they work, say briefly that you will (it is kept in "What MedPin AI remembers"). Facts about a patient are not kept in memory: suggest adding them to the patient\'s record instead.',
    memory.summaryPrompt(session),
    languageRule((await M.User.findById(session.userId, 'language'))?.language, { clinician: true }),
  ].filter(Boolean).join('\n') + context;
  const out = await ai.complete({ system, messages, effort: 'medium' });
  if (!out || out.refused) return { ...(out || {}), text: "I can't help with that request.", refused: true };
  memory.afterAnswer(session, { ownerType: 'doctor', userId: session.userId }, { question, answer: out.text, practiceId });
  return out;
}

/** Patient "Ask MedPin AI". */
async function patientAnswer(session, question, patient, { excludeId } = {}) {
  const lang = await patientLanguage(patient);
  if (!ai.enabled()) {
    return { text: line('aiOffPatient', lang), scripted: true };
  }
  const practiceIds = await M.PatientEnrolment.find({ patientId: patient._id, status: 'linked' }).distinct('practiceId');
  if (practiceIds[0]) await useAiChat(practiceIds[0]);
  const summary = await patientSummary(patient, practiceIds[0]);
  const memory = require('./ai_memory');
  const who = { ownerType: 'patient', userId: session.userId, patientId: patient._id };
  const messages = await memory.recentTurns(session, { excludeId });
  messages.push({ role: 'user', content: question });
  const notes = await memory.notesFor(who);
  const system = [
    'You are MedPin AI in the MedPin patient app, helping a patient in India understand their own health record and use the app.',
    `Rules:\n- ${PATIENT_SAFETY_RULES}`,
    'If they ask which doctor to see, name the kind of specialist (put its key in specialist_key) and suggest Find a doctor in the app.',
    'Before answering, check your reply against the rules. Set breaks_rules true if it names a diagnosis, recommends a medicine or dose change, or recommends a test.',
    `Their record (JSON): ${patientContext(summary)}`,
    memory.notesPrompt(notes, 'patient'),
    'If they ask you to remember or forget something, say briefly that you will; they can see it in "What MedPin AI remembers". If they tell you a health fact (an allergy, a medicine from elsewhere), also suggest they tell their doctor or add it to their record.',
    memory.summaryPrompt(session),
    languageRule(lang),
  ].filter(Boolean).join('\n');
  // Short answers for patients: low effort keeps them quick.
  const out = await ai.completeJson({ system, messages, schema: PATIENT_ANSWER_SCHEMA, effort: 'low' });
  const emergencyWords = isEmergencyText(question);
  const fallback = emergencyWords ? line('emergency', lang) : line('cantAnswer', lang);
  // The model's raw output (its `text`) never reaches the patient: the safe line does.
  if (!out?.data || out.refused) return { ...(out || {}), text: fallback, refused: true, emergency: emergencyWords };
  const d = out.data;
  // Self-check failed: don't show an answer that diagnoses or prescribes.
  const text = d.breaks_rules ? fallback : d.reply;
  if (!d.breaks_rules) memory.afterAnswer(session, who, { question, answer: text });
  return { ...out, text, emergency: emergencyWords || d.emergency, specialistKey: d.specialist_key || null, blocked: Boolean(d.breaks_rules) };
}

const PATIENT_ANSWER_SCHEMA = {
  type: 'object',
  properties: {
    reply: { type: 'string' },
    emergency: { type: 'boolean' },
    specialist_key: { type: 'string', enum: ['', 'gp', 'diabetes', 'heart', 'women', 'child', 'skin', 'bones', 'mind', 'stomach', 'eye', 'teeth', 'ent'] },
    breaks_rules: { type: 'boolean' },
  },
  required: ['reply', 'emergency', 'specialist_key', 'breaks_rules'],
  additionalProperties: false,
};

/** Daily digest rows for Chat-Summaries. */
async function summarizeDay(practiceId, day) {
  const start = T.dayStart(day);
  const end = T.addDays(start, 1);
  const convos = await M.Conversation.find({ practiceId, type: { $in: ['care', 'nutrition'] }, 'lastMessage.at': { $gte: start } });
  const rows = [];
  for (const c of convos) {
    const msgs = await M.Message.find({ conversationId: c._id, createdAt: { $gte: start, $lt: end }, deletedForEveryoneAt: null }).sort({ createdAt: 1 });
    const fromPatient = msgs.filter((m) => m.senderType === 'patient');
    if (!fromPatient.length) continue;
    const last = msgs[msgs.length - 1];
    const flagged = msgs.find((m) => m.ai?.flagged);
    const needsReply = last.senderType === 'patient' || Boolean(flagged && !(await M.ChatReview.exists({ messageId: flagged._id, status: 'reviewed' })));
    let summary = fromPatient.map((m) => m.text).filter(Boolean).join(' · ').slice(0, 240);
    if (ai.enabled()) {
      const out = await ai.complete({
        system: 'Summarise this patient chat for their doctor in one or two short sentences: what the patient wanted, what was answered, and anything still open.',
        messages: [{ role: 'user', content: msgs.map((m) => `${m.senderType}: ${m.text || '[attachment]'}`).join('\n') }],
        effort: 'low',
        maxTokens: 4096,
      });
      if (out?.text) summary = out.text;
    }
    const review = flagged ? await M.ChatReview.findOne({ messageId: flagged._id }) : null;
    const careDoctor = await M.CareTeamAccess.findOne({ patientId: c.patientId, role: 'doctor', isPrimary: true });
    rows.push(
      await M.ChatSummary.findOneAndUpdate(
        { conversationId: c._id, date: start },
        {
          practiceId, patientId: c.patientId, doctorId: careDoctor?.userId, messageCount: msgs.length, lastMessageAt: last.createdAt,
          needsReply, flagLabel: review ? `Flagged: ${review.reason.replace(/_/g, ' ')}` : undefined, summary,
        },
        { upsert: true, new: true },
      ),
    );
  }
  return rows;
}

const LAB_SCHEMA = {
  type: 'object',
  properties: {
    // What the file is: the app tells the patient when it isn't the test report they meant to send.
    document_type: { type: 'string', enum: ['lab_report', 'imaging_or_ecg', 'bp_or_sugar_log', 'eye_exam', 'prescription', 'other_medical', 'not_medical', 'unreadable'] },
    lab_name: { type: 'string' },
    collected_on: { type: 'string', description: 'YYYY-MM-DD or empty' },
    tests: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          test_name: { type: 'string' },
          page_from: { type: 'integer' },
          page_to: { type: 'integer' },
          summary: { type: 'string' },
          values: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                analyte: { type: 'string' },
                value: { type: 'string' },
                unit: { type: 'string' },
                ref_text: { type: 'string' },
                flag: { type: 'string', enum: ['critical', 'high', 'low', 'normal'] },
              },
              required: ['analyte', 'value', 'unit', 'ref_text', 'flag'],
              additionalProperties: false,
            },
          },
        },
        required: ['test_name', 'page_from', 'page_to', 'summary', 'values'],
        additionalProperties: false,
      },
    },
  },
  required: ['document_type', 'lab_name', 'collected_on', 'tests'],
  additionalProperties: false,
};

/** Reads an uploaded report (PDF or image) into tests and values. Returns null without AI. */
/**
 * Reads a report. [buffer] is one file, or a list of [{ buffer, mimetype }] —
 * the pages of one report photographed one by one, read together in order.
 */
async function extractLabReport(buffer, mimeType) {
  if (!ai.enabled()) return null;
  const files = Array.isArray(buffer) ? buffer.slice(0, 10) : [{ buffer, mimetype: mimeType }];
  const blocks = files.map((f) => (f.mimetype === 'application/pdf'
    ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: f.buffer.toString('base64') } }
    : { type: 'image', source: { type: 'base64', media_type: f.mimetype, data: f.buffer.toString('base64') } }));
  const many = files.length > 1;
  const out = await ai.completeJson({
    system: 'You read Indian medical test reports: lab reports, ECG / X-ray / ultrasound / echo reports, eye (fundus) examinations, and home BP or sugar logs. '
      + 'Extract every test, panel or examination with its values or findings exactly as printed (a BP log: one test "Home blood pressure log" with each reading as a value). '
      + 'Use the test names printed on the report, not the file name. Write each summary as one plain-language sentence for the patient. Use flag "normal" when no reference range is printed. '
      + 'Set document_type to what the file is; when it is a prescription, not a medical document, or too blurred / cut off to read, return no tests.',
    messages: [{ role: 'user', content: [...blocks, { type: 'text', text: many ? `These ${files.length} images are the pages of one report, in order (page 1 first). Extract the tests from it.` : 'Extract the tests from this report.' }] }],
    schema: LAB_SCHEMA,
    effort: 'medium',
    vision: true,
    maxTokens: 16000,
  });
  return out?.data || null;
}

const RX_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['document_type', 'doctor_name', 'clinic_name', 'prescribed_on', 'diagnosis', 'tests_advised', 'medicines'],
  properties: {
    // What the file is: the app says so when a test report was uploaded as a prescription.
    document_type: { type: 'string', enum: ['prescription', 'lab_report', 'other_medical', 'not_medical', 'unreadable'] },
    doctor_name: { type: 'string', description: 'Prescribing doctor as printed, or empty' },
    clinic_name: { type: 'string', description: 'Clinic / hospital as printed, or empty' },
    prescribed_on: { type: 'string', description: 'Date of the prescription, YYYY-MM-DD, or empty' },
    diagnosis: { type: 'string', description: 'Diagnosis / complaint as written (short), or empty' },
    tests_advised: { type: 'array', items: { type: 'string' }, description: 'Investigations the doctor advised, as written' },
    medicines: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'strength', 'morning', 'afternoon', 'night', 'frequency', 'food', 'duration_days', 'instructions'],
        properties: {
          name: { type: 'string' },
          // SOS / "when needed" / "if pain" → as_needed; "once a week" → weekly; not written → unclear.
          frequency: { type: 'string', enum: ['daily', 'weekly', 'as_needed', 'unclear'] },
          strength: { type: 'string', description: 'e.g. "500 mg"; empty if not printed' },
          morning: { type: 'number' },
          afternoon: { type: 'number' },
          night: { type: 'number' },
          food: { type: 'string', enum: ['before_food', 'after_food', 'with_food', 'empty_stomach', 'any'] },
          duration_days: { type: 'number', description: '0 when not printed or ongoing' },
          instructions: { type: 'string' },
        },
      },
    },
  },
};

/**
 * Reads the medicines on an uploaded prescription exactly as written (no
 * advice, no changes). The patient reviews them before anything is added.
 */
async function extractPrescription(buffer, mimeType) {
  if (!ai.enabled()) return null;
  // One file, or the pages of one prescription photographed one by one.
  const files = Array.isArray(buffer) ? buffer.slice(0, 10) : [{ buffer, mimetype: mimeType }];
  const blocks = files.map((f) => (f.mimetype === 'application/pdf'
    ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: f.buffer.toString('base64') } }
    : { type: 'image', source: { type: 'base64', media_type: f.mimetype, data: f.buffer.toString('base64') } }));
  const out = await ai.completeJson({
    system: 'You transcribe Indian doctor prescriptions. List every medicine exactly as written: name, strength, how many to take in the morning / afternoon / night (1-0-1 means 1 morning and 1 night; ½ is 0.5), how often (SOS, "when needed", "if fever / pain" = as_needed; "once a week" = weekly; when no timing is written = unclear), food relation and duration. '
      + 'Also copy the doctor\'s name, the clinic / hospital, the date, the diagnosis and the advised tests as written. Do not add, remove, change or recommend anything. If a field is not written, leave it empty or 0. '
      + 'Set document_type to what the file is; when it is a lab report, not medical or unreadable, return no medicines.',
    messages: [{ role: 'user', content: [...blocks, { type: 'text', text: 'Transcribe this prescription.' }] }],
    schema: RX_SCHEMA,
    effort: 'medium',
    vision: true,
    maxTokens: 4000,
  });
  return out?.data || null;
}

module.exports = {
  line, languageRule, patientLanguage,
  aiPaused, aiLimitReached, threadClinician, willReplyInCareThread, replyInCareThread, doctorAnswer, patientAnswer, summarizeDay, extractLabReport, extractPrescription, isEmergencyText, useAiChat };

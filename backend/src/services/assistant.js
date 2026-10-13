// MedPin AI: patient chat replies (grounded in the practice knowledge base and
// flagged for doctor review), the doctor assistant, patient "Ask AI",
// daily chat summaries, and reading lab reports into structured results.
const M = require('../models');
const T = require('../lib/time');
const ai = require('./ai');
const { conflict } = require('../lib/http');
const { patientSummary } = require('./clinical');
const { postMessage, raiseAlert } = require('./care');

const EMERGENCY_WORDS = [
  'chest pain', 'chest tightness', "can't breathe", 'cannot breathe', 'not breathing', 'hard to breathe', 'faint',
  'unconscious', 'stroke', 'severe bleeding', 'heart attack', 'seizure', 'suicide', 'kill myself',
];
const isEmergencyText = (text) => EMERGENCY_WORDS.some((w) => String(text).toLowerCase().includes(w));
const AI_PAUSE_MIN = 10;

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
  const paused = convo.aiPausedAt && convo.aiPausedAt > T.addMinutes(new Date(), -AI_PAUSE_MIN);
  if (!ai.enabled() || !convo.aiEnabled || paused || convo.type !== 'care') return false;
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
    await raiseAlert({
      practiceId: convo.practiceId, patientId: convo.patientId, severity: 'emergency', kind: 'urgent_chat',
      detail: patientMessage.text.slice(0, 300), sourceModel: 'Message', sourceId: patientMessage._id, conversationId: convo._id,
    });
  }
  const paused = convo.aiPausedAt && convo.aiPausedAt > T.addMinutes(new Date(), -AI_PAUSE_MIN);
  if (!ai.enabled() || !convo.aiEnabled || paused || convo.type !== 'care') return null;
  // The patient's main doctor can turn MedPin AI replies off (Chat settings).
  const primary = await M.CareTeamAccess.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, isPrimary: true });
  if (primary) {
    const prof = await M.DoctorProfile.findOne({ userId: primary.userId }, 'chatSettings');
    if (prof?.chatSettings?.aiReplies === false) return null;
  }
  await useAiChat(convo.practiceId);

  const patient = await M.Patient.findById(convo.patientId);
  const summary = await patientSummary(patient, convo.practiceId);
  const kb = await knowledgeFor(convo.practiceId, patientMessage.text);
  const history = (await M.Message.find({ conversationId: convo._id, deletedForEveryoneAt: null }).sort({ createdAt: -1 }).limit(20)).reverse();
  const practice = await M.Practice.findById(convo.practiceId, 'name');

  const system = [
    `You are the MedPin assistant for ${practice?.name || 'the clinic'}, replying to a patient in their chat with the care team.`,
    `Rules:\n- ${PATIENT_SAFETY_RULES}\n- Questions about doses, new symptoms, test needs or changing treatment: say the doctor will confirm, and set needs_doctor true.`,
    'Ground medical guidance in the clinic knowledge entries below and cite their ids. If the answer is not covered there, keep it general, say the care team will follow up, and set reason to outside_knowledge_base.',
    'Set urgency high and needs_doctor true for anything that could be an emergency, and tell the patient to call 108 or go to the nearest emergency department.',
    `Patient record (JSON): ${patientContext(summary)}`,
    `Clinic knowledge entries (JSON): ${JSON.stringify(kb.map((k) => ({ id: String(k._id), title: k.title, content: k.content })))}`,
  ].join('\n\n');
  const messages = [];
  for (const m of history) {
    const role = m.senderType === 'patient' ? 'user' : 'assistant';
    const content = m.senderType === 'patient' ? m.text || '[attachment]' : `${m.senderType === 'ai' ? '' : `[${m.senderType}] `}${m.text || ''}`;
    if (messages.length && messages[messages.length - 1].role === role) messages[messages.length - 1].content += `\n${content}`;
    else messages.push({ role, content });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift();
  if (!messages.length) return null;

  // Chat replies are short: low effort keeps them quick.
  const out = await ai.completeJson({ system, messages, schema: REPLY_SCHEMA, effort: 'low' });
  if (!out || out.refused || !out.data) return null;
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
    await M.ChatReview.create({
      practiceId: convo.practiceId, patientId: convo.patientId, conversationId: convo._id, messageId: msg._id,
      reason: d.reason === 'none' ? 'other' : d.reason, title: patientMessage.text.slice(0, 80), excerpt: d.reply.slice(0, 200),
      urgency: d.urgency === 'high' || urgentByWords ? 'high' : d.urgency === 'medium' ? 'medium' : 'low',
    });
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
  // The patient this chat is about, plus anyone the question names ("How is Priya's sugar?").
  // Only what this doctor may see of each patient goes to the AI.
  const about = [];
  if (session.patientId) {
    const p = await M.Patient.findById(session.patientId);
    if (p) about.push(p);
  }
  for (const p of await patientsMentioned(question, practiceId)) {
    if (!about.some((a) => String(a._id) === String(p._id))) about.push(await M.Patient.findById(p._id));
  }
  for (const patient of about.slice(0, 3)) {
    const acc = await accessFor({ userId: session.userId, practiceId }, patient);
    context += `\n\nPatient ${patient.name} (JSON): ${patientContext(await patientSummary(patient, practiceId, acc))}`;
  }
  const [today, brief, kb] = await Promise.all([
    M.Appointment.find({ practiceId, doctorId: session.userId, date: T.dayStart() }).populate('patientId', 'name'),
    practiceBrief(session.userId, practiceId),
    knowledgeFor(practiceId, question).catch(() => []),
  ]);
  // Earlier turns of this chat (the new question is added once, at the end).
  const history = await M.AiMessage.find({ sessionId: session._id, ...(excludeId ? { _id: { $ne: excludeId } } : {}) }).sort({ createdAt: -1 }).limit(30);
  const messages = history.reverse().map((m) => ({ role: m.role, content: m.text || '' })).filter((m) => m.content);
  messages.push({ role: 'user', content: question });
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
  ].join('\n') + context;
  const out = await ai.complete({ system, messages, effort: 'medium' });
  if (out.refused) return { text: "I can't help with that request.", refused: true, ...out };
  return out;
}

/** Patient "Ask MedPin AI". */
async function patientAnswer(session, question, patient, { excludeId } = {}) {
  if (!ai.enabled()) {
    return { text: 'MedPin AI is not available right now. You can message your doctor from the Doctors tab.', scripted: true };
  }
  const practiceIds = await M.PatientEnrolment.find({ patientId: patient._id, status: 'linked' }).distinct('practiceId');
  if (practiceIds[0]) await useAiChat(practiceIds[0]);
  const summary = await patientSummary(patient, practiceIds[0]);
  const history = await M.AiMessage.find({ sessionId: session._id, ...(excludeId ? { _id: { $ne: excludeId } } : {}) }).sort({ createdAt: -1 }).limit(20);
  const messages = history.reverse().map((m) => ({ role: m.role, content: m.text || '' })).filter((m) => m.content);
  messages.push({ role: 'user', content: question });
  const system = [
    'You are MedPin AI in the MedPin patient app, helping a patient in India understand their own health record and use the app.',
    `Rules:\n- ${PATIENT_SAFETY_RULES}`,
    'If they ask which doctor to see, name the kind of specialist (put its key in specialist_key) and suggest Find a doctor in the app.',
    'Before answering, check your reply against the rules. Set breaks_rules true if it names a diagnosis, recommends a medicine or dose change, or recommends a test.',
    `Their record (JSON): ${patientContext(summary)}`,
  ].join('\n');
  // Short answers for patients: low effort keeps them quick.
  const out = await ai.completeJson({ system, messages, schema: PATIENT_ANSWER_SCHEMA, effort: 'low' });
  const emergencyWords = isEmergencyText(question);
  const fallback = emergencyWords
    ? 'This could be serious. Please call 108 or go to the nearest emergency department now, and use Emergency in the app to alert your doctor.'
    : "I can't answer that safely here. Please ask your doctor — you can message them from the Doctors tab.";
  if (!out?.data || out.refused) return { text: fallback, refused: true, emergency: emergencyWords, ...(out || {}) };
  const d = out.data;
  // Self-check failed: don't show an answer that diagnoses or prescribes.
  const text = d.breaks_rules ? fallback : d.reply;
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
  required: ['lab_name', 'collected_on', 'tests'],
  additionalProperties: false,
};

/** Reads an uploaded report (PDF or image) into tests and values. Returns null without AI. */
async function extractLabReport(buffer, mimeType) {
  if (!ai.enabled()) return null;
  const block = mimeType === 'application/pdf'
    ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: buffer.toString('base64') } }
    : { type: 'image', source: { type: 'base64', media_type: mimeType, data: buffer.toString('base64') } };
  const out = await ai.completeJson({
    system: 'You read Indian laboratory reports. Extract every test panel with its values exactly as printed. Write each summary as one plain-language sentence for the patient. Use flag "normal" when no reference range is printed.',
    messages: [{ role: 'user', content: [block, { type: 'text', text: 'Extract the tests from this report.' }] }],
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
  required: ['doctor_name', 'medicines'],
  properties: {
    doctor_name: { type: 'string', description: 'Prescribing doctor as printed, or empty' },
    medicines: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'strength', 'morning', 'afternoon', 'night', 'food', 'duration_days', 'instructions'],
        properties: {
          name: { type: 'string' },
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
  const block = mimeType === 'application/pdf'
    ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: buffer.toString('base64') } }
    : { type: 'image', source: { type: 'base64', media_type: mimeType, data: buffer.toString('base64') } };
  const out = await ai.completeJson({
    system: 'You transcribe Indian doctor prescriptions. List every medicine exactly as written: name, strength, how many to take in the morning / afternoon / night (1-0-1 means 1 morning and 1 night), food relation and duration. Do not add, remove, change or recommend anything. If a field is not written, leave it empty or 0.',
    messages: [{ role: 'user', content: [block, { type: 'text', text: 'Transcribe the medicines on this prescription.' }] }],
    schema: RX_SCHEMA,
    effort: 'medium',
    vision: true,
    maxTokens: 4000,
  });
  return out?.data || null;
}

module.exports = { willReplyInCareThread, replyInCareThread, doctorAnswer, patientAnswer, summarizeDay, extractLabReport, extractPrescription, isEmergencyText, useAiChat };

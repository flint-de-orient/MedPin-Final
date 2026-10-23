// Chats, AI assistant, chat review, knowledge base and feedback
// (Care, Nutrition, Patient-Thread, Doctor-Messages*, Patient-DoctorChat,
// Patient-Chat, Doctor-AI*, Patient-AskAI, Chat-Review*, Chat-Summaries,
// Knowledge*, Feedback).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, enumOf, fileSchema, actionStamp, baseOptions } = require('./common');

const participantSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    role: enumOf(E.PARTICIPANT_ROLES, { required: true }),
    unreadCount: { type: Number, default: 0 },
    lastReadAt: Date,
    mutedAt: Date,
  },
  { _id: false },
);

// Care / nutrition threads are patient ↔ clinic (all permitted staff see them);
// direct threads are between team members or colleagues.
const conversationSchema = new Schema(
  {
    type: enumOf(E.CONVERSATION_TYPES, { required: true }),
    practiceId: ref('Practice'),
    patientId: ref('Patient'),
    participants: [participantSchema],
    isUrgent: { type: Boolean, default: false }, // urgent chat from Patient-Emergency
    urgentSince: Date,
    triage: enumOf(E.TRIAGE_CHIPS), // "Needs attention", "Check-in due", "Review due"
    aiEnabled: { type: Boolean, default: true },
    aiPausedBy: ref('User'), // "AI assistant is paused while you're in this thread"
    aiPausedAt: Date,
    // Someone at the clinic has the thread open (its screen refreshes every few
    // seconds): MedPin AI stays quiet while they are there (services/assistant.js).
    staffViewingAt: Date,
    pinnedMessageId: ref('Message'),
    lastMessage: {
      text: String,
      senderType: enumOf(E.SENDER_TYPES),
      senderId: ref('User'),
      senderLabel: String, // "AI", "You", "Tania", "Dietician"
      at: Date,
    },
  },
  baseOptions,
);
conversationSchema.index({ practiceId: 1, type: 1, 'lastMessage.at': -1 });
conversationSchema.index({ 'participants.userId': 1, 'lastMessage.at': -1 });
conversationSchema.index(
  { patientId: 1, practiceId: 1, type: 1 },
  { unique: true, partialFilterExpression: { patientId: { $type: 'objectId' } } }, // direct threads have no patientId
);

const aiMetaSchema = new Schema(
  {
    flagged: { type: Boolean, default: false },
    urgency: enumOf(E.REVIEW_URGENCIES),
    responseSource: enumOf(E.AI_RESPONSE_SOURCES, { default: 'model' }),
    fallbackUsed: { type: Boolean, default: false },
    confidence: Number,
    latencyMs: Number,
    aiModel: String,
    citations: [
      {
        label: String, // "ADA Standards of Care 2026 §9"
        knowledgeEntryId: { type: Schema.Types.ObjectId, ref: 'KnowledgeEntry' },
        _id: false,
      },
    ],
    escalated: { type: Boolean, default: false }, // "I've asked Dr. Sen to confirm"
  },
  { _id: false },
);

const messageSchema = new Schema(
  {
    conversationId: ref('Conversation', true),
    senderId: ref('User'), // null for AI / system
    senderType: enumOf(E.SENDER_TYPES, { required: true }),
    kind: enumOf(E.MESSAGE_KINDS, { default: 'text' }),
    text: { type: String, maxlength: 4000 },
    meta: Schema.Types.Mixed, // e.g. { away: true } for the automatic away reply
    voice: { file: fileSchema, durationSec: Number },
    attachment: fileSchema, // photo / PDF
    recordId: ref('MedicalRecord'), // shared report or prescription card
    prescriptionId: ref('Prescription'),
    replyToId: ref('Message'),
    isUrgent: { type: Boolean, default: false },
    deliveryStatus: enumOf(E.DELIVERY_STATUSES, { default: 'sent' }),
    deliveredAt: Date,
    seenAt: Date,
    hiddenFor: [{ type: Schema.Types.ObjectId, ref: 'User' }],
    deletedForEveryoneAt: Date,
    ai: aiMetaSchema,
  },
  baseOptions,
);
messageSchema.index({ conversationId: 1, createdAt: -1 });
messageSchema.index({ 'ai.flagged': 1, createdAt: -1 }, { partialFilterExpression: { 'ai.flagged': true } });

// Flagged AI answers for a doctor to check (Chat-Review).
const chatReviewSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    conversationId: ref('Conversation', true),
    messageId: ref('Message', true),
    reason: enumOf(E.REVIEW_REASONS, { required: true }),
    title: String, // "Dosage question answered by AI"
    excerpt: String,
    urgency: enumOf(E.REVIEW_URGENCIES, { default: 'medium' }),
    status: enumOf(E.REVIEW_STATUSES, { default: 'needs_review' }),
    reviewed: actionStamp,
  },
  baseOptions,
);
chatReviewSchema.index({ practiceId: 1, status: 1, urgency: 1, createdAt: -1 });

// AI daily digest per conversation (Chat-Summaries).
const chatSummarySchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    conversationId: ref('Conversation', true),
    doctorId: ref('User'), // "My patients" filter
    date: { type: Date, required: true },
    messageCount: Number,
    lastMessageAt: Date,
    needsReply: { type: Boolean, default: false },
    flagLabel: String, // "Flagged: dosage timing"
    summary: String,
  },
  baseOptions,
);
chatSummarySchema.index({ conversationId: 1, date: 1 }, { unique: true });
chatSummarySchema.index({ practiceId: 1, date: -1 });

// Doctor AI assistant and patient "Ask MedPin AI" sessions.
const aiSessionSchema = new Schema(
  {
    ownerType: enumOf(E.AI_OWNER_TYPES, { required: true }),
    userId: ref('User', true),
    practiceId: ref('Practice'),
    patientId: ref('Patient'), // "Talking about" chip, or the patient's own session
    title: String,
    lastAt: Date,
  },
  baseOptions,
);
aiSessionSchema.index({ userId: 1, lastAt: -1 });

const aiMessageSchema = new Schema(
  {
    sessionId: ref('AiSession', true),
    role: enumOf(E.AI_ROLES, { required: true }),
    text: String,
    inputMode: enumOf(E.INPUT_MODES, { default: 'typed' }),
    voiceLanguage: enumOf(E.LANGUAGES),
    payload: Schema.Types.Mixed, // structured answer cards (abnormal results, meds…)
    sources: {
      labReports: Number,
      prescriptions: Number,
      medicineLog: Boolean,
      refs: [{ refModel: String, refId: Schema.Types.ObjectId, _id: false }],
    },
    vote: { type: Number, enum: [-1, 0, 1], default: 0 },
    aiModel: String,
    latencyMs: Number,
    inputTokens: Number,
    outputTokens: Number,
  },
  baseOptions,
);
aiMessageSchema.index({ sessionId: 1, createdAt: 1 });

// AI summaries shown to doctors (patient brief) and patients (home summary).
const aiSummarySchema = new Schema(
  {
    patientId: ref('Patient', true),
    audience: enumOf(E.SUMMARY_AUDIENCES, { required: true }),
    practiceId: ref('Practice'),
    body: { type: String, required: true },
    focusItems: [String],
    contextNote: String, // "This week Priya asked about: missed doses…"
    sources: { labReports: Number, prescriptions: Number, medicineLog: Boolean },
    aiModel: String,
    generatedAt: { type: Date, default: Date.now },
  },
  baseOptions,
);
aiSummarySchema.index({ patientId: 1, audience: 1, generatedAt: -1 });

// practiceId null = shared by MedPin (read-only, can be adopted).
const knowledgeEntrySchema = new Schema(
  {
    practiceId: ref('Practice'),
    title: { type: String, required: true },
    summary: String,
    content: { type: String, required: true, maxlength: 2000 },
    status: enumOf(E.KB_STATUSES, { default: 'draft' }),
    language: enumOf(E.LANGUAGES, { default: 'en' }),
    category: enumOf(E.KB_CATEGORIES, { default: 'other' }),
    sourceCitation: String,
    tags: [{ type: String, lowercase: true, trim: true }],
    createdBy: ref('User'),
    updatedBy: ref('User'),
    authorLabel: String, // "MedPin clinical team"
    submittedAt: Date,
    approved: actionStamp, // only approved entries ground the AI
    retiredAt: Date,
    retiredNote: String,
    supersededById: ref('KnowledgeEntry'),
    // Semantic search (Gemini embeddings); refreshed when the text changes.
    embedding: { type: [Number], select: false },
    embeddedText: { type: String, select: false },
  },
  baseOptions,
);
knowledgeEntrySchema.index({ practiceId: 1, status: 1 });
knowledgeEntrySchema.index({ title: 'text', content: 'text', tags: 'text' });

const knowledgeAdoptionSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    entryId: ref('KnowledgeEntry', true),
    adoptedBy: ref('User', true),
    adoptedAt: { type: Date, default: Date.now },
  },
  baseOptions,
);
knowledgeAdoptionSchema.index({ practiceId: 1, entryId: 1 }, { unique: true });

const feedbackSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    doctorId: ref('User'),
    appointmentId: ref('Appointment'),
    rating: { type: Number, required: true, min: 1, max: 5 },
    category: enumOf(E.FEEDBACK_CATEGORIES, { default: 'care' }),
    comment: { type: String, maxlength: 2000 },
    readBy: [{ userId: { type: Schema.Types.ObjectId, ref: 'User' }, at: Date, _id: false }],
    reply: { text: String, by: { type: Schema.Types.ObjectId, ref: 'User' }, at: Date },
  },
  baseOptions,
);
feedbackSchema.index({ practiceId: 1, createdAt: -1 });

module.exports = {
  Conversation: model('Conversation', conversationSchema),
  Message: model('Message', messageSchema),
  ChatReview: model('ChatReview', chatReviewSchema),
  ChatSummary: model('ChatSummary', chatSummarySchema),
  AiSession: model('AiSession', aiSessionSchema),
  AiMessage: model('AiMessage', aiMessageSchema),
  AiSummary: model('AiSummary', aiSummarySchema),
  KnowledgeEntry: model('KnowledgeEntry', knowledgeEntrySchema),
  KnowledgeAdoption: model('KnowledgeAdoption', knowledgeAdoptionSchema),
  Feedback: model('Feedback', feedbackSchema),
};

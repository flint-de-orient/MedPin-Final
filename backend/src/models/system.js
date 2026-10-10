// Notifications, exports, audit trail and sequence counters.
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, enumOf, fileSchema, baseOptions } = require('./common');

// In-app bell items, plus the record of any push / SMS / WhatsApp sent.
const notificationSchema = new Schema(
  {
    userId: ref('User', true),
    practiceId: ref('Practice'),
    type: { type: String, required: true }, // appointment_cancelled, follow_up_reminder, urgent_chat…
    title: { type: String, required: true },
    body: String,
    screen: String, // design stem to open, e.g. "Patient-Thread"
    params: Schema.Types.Mixed,
    channels: [enumOf(E.NOTIFICATION_CHANNELS)],
    sentAt: Date,
    readAt: Date,
  },
  baseOptions,
);
notificationSchema.index({ userId: 1, readAt: 1, createdAt: -1 });
notificationSchema.index({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 180 });

// Downloads and exports (History-Download, Report-Download, Export). Kept as an
// audit of every file that contains patient data.
const exportJobSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    requestedBy: ref('User', true),
    kind: enumOf(E.EXPORT_KINDS, { required: true }),
    reportType: String, // consultations, prescriptions, fees, follow_ups, referrals, daily
    datasets: [String], // patients, clinical_summary, alerts
    format: enumOf(E.EXPORT_FORMATS, { required: true }),
    filters: Schema.Types.Mixed, // dates, locations, visit types, modes, age groups
    includeMobiles: { type: Boolean, default: false },
    emailCopy: { type: Boolean, default: false },
    status: enumOf(E.JOB_STATUSES, { default: 'queued' }),
    rowCount: Number,
    file: fileSchema,
    error: String,
    completedAt: Date,
  },
  baseOptions,
);
exportJobSchema.index({ practiceId: 1, createdAt: -1 });

// Who read or changed patient data (needed for medical-record compliance).
const auditLogSchema = new Schema(
  {
    practiceId: ref('Practice'),
    userId: ref('User'),
    action: { type: String, required: true }, // e.g. patient.view, prescription.issue
    entity: String,
    entityId: Schema.Types.ObjectId,
    patientId: ref('Patient'),
    meta: Schema.Types.Mixed,
    ip: String,
  },
  { ...baseOptions, timestamps: { createdAt: true, updatedAt: false } },
);
auditLogSchema.index({ practiceId: 1, createdAt: -1 });

// Help and support: "Report a problem" / "Ask a question".
const supportRequestSchema = new Schema(
  {
    userId: ref('User', true),
    practiceId: ref('Practice'),
    topic: enumOf(['problem', 'question', 'billing', 'account', 'feature'], { default: 'problem' }),
    message: { type: String, required: true, maxlength: 4000 },
    platform: String,
    appVersion: String,
    status: enumOf(['open', 'answered', 'closed'], { default: 'open' }),
  },
  baseOptions,
);
supportRequestSchema.index({ userId: 1, createdAt: -1 });

// Atomic sequences, e.g. _id "rx:<practiceId>" for prescription numbers.
const counterSchema = new Schema({
  _id: { type: String, required: true },
  seq: { type: Number, default: 0 },
});

counterSchema.statics.next = async function next(name) {
  const doc = await this.findOneAndUpdate({ _id: name }, { $inc: { seq: 1 } }, { new: true, upsert: true });
  return doc.seq;
};

// One row per reminder already sent ("dose:<id>", "visit24:<id>"…), so the
// scheduler never sends the same reminder twice, even after a restart.
const reminderLogSchema = new Schema({ key: { type: String, required: true, unique: true }, at: { type: Date, default: Date.now } });
reminderLogSchema.index({ at: 1 }, { expireAfterSeconds: 45 * 24 * 3600 });

module.exports = {
  ReminderLog: model('ReminderLog', reminderLogSchema),
  Notification: model('Notification', notificationSchema),
  ExportJob: model('ExportJob', exportJobSchema),
  AuditLog: model('AuditLog', auditLogSchema),
  SupportRequest: model('SupportRequest', supportRequestSchema),
  Counter: model('Counter', counterSchema),
};

// Records, lab results, health log and clinical alerts
// (Patient-Records, Records-Add, Records-Review, PP-Tests, Patient-Log, Alerts).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, enumOf, fileSchema, actionStamp, baseOptions } = require('./common');

// A record in the patient's file. One uploaded PDF can be split by the AI
// into several records (one per test), each pointing at its page range.
const medicalRecordSchema = new Schema(
  {
    // Medicines read from an uploaded prescription (AI), until the patient adds them.
    extractedMedicines: [Schema.Types.Mixed],
    extractedDoctor: String,
    medicinesAddedAt: Date,
    patientId: ref('Patient', true),
    kind: enumOf(E.RECORD_KINDS, { required: true }),
    title: { type: String, required: true }, // "Lipid profile"
    forTests: [String], // the doctor's tests this report was checked to contain ("HbA1c", "Lipid profile")
    // What its content showed against the tests it was uploaded for (services/advisedtests.js checkReport):
    // { asked, found, missing, detected, readable, documentType, auto, at }.
    testCheck: { type: Schema.Types.Mixed, default: undefined },
    recordDate: { type: Date, required: true }, // collected / issued on
    origin: enumOf(E.RECORD_ORIGINS, { required: true }),
    sourceName: String, // "SRL Diagnostics", "Dr. Arjun Sen", "uploaded by you"
    practiceId: ref('Practice'),
    doctorId: ref('User'),
    prescriptionId: ref('Prescription'),
    uploadSource: enumOf(E.UPLOAD_SOURCES),
    files: [fileSchema],
    pageFrom: Number, // "Pages 1–2"
    pageTo: Number,
    batchId: Schema.Types.ObjectId, // records created from the same upload
    status: enumOf(E.RECORD_STATUSES, { default: 'ready' }),
    aiSummary: String,
    flagLabel: String, // "2 high", "Normal", "New"
    flagTone: enumOf(['high', 'ok', 'new']),
    sharedWith: [
      {
        userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
        sharedAt: { type: Date, default: Date.now },
        _id: false,
      },
    ],
    uploadedBy: ref('User'),
    attachedToMessageId: ref('Message'),
    deletedAt: Date,
  },
  baseOptions,
);
medicalRecordSchema.index({ patientId: 1, recordDate: -1 });
medicalRecordSchema.index({ 'sharedWith.userId': 1 });
medicalRecordSchema.index({ title: 'text', aiSummary: 'text', sourceName: 'text' });

const analyteSchema = new Schema({
  analyte: { type: String, required: true }, // "LDL cholesterol"
  value: Number,
  valueText: String, // for non-numeric results
  unit: String, // mg/dL, %, ng/mL, mIU/L, g/dL, mmol/L
  refLow: Number,
  refHigh: Number,
  refText: String, // "below 100", "0.7–1.2"
  flag: enumOf(E.RESULT_FLAGS, { default: 'normal' }),
});

// Structured values of one test (read from the report by the AI, or typed).
const labResultSchema = new Schema(
  {
    patientId: ref('Patient', true),
    recordId: ref('MedicalRecord'),
    practiceId: ref('Practice'),
    testName: { type: String, required: true }, // "Lipid profile"
    panel: String,
    labName: String,
    collectedAt: { type: Date, required: true },
    values: [analyteSchema],
    abnormalCount: { type: Number, default: 0 },
    hasCritical: { type: Boolean, default: false },
    ecgInterpretation: enumOf(E.ECG_INTERPRETATIONS),
    ecgNote: String, // "Normal sinus rhythm · 12-lead"
    reviewed: actionStamp, // doctor reviewed abnormal result
  },
  baseOptions,
);
labResultSchema.index({ patientId: 1, collectedAt: -1 });
labResultSchema.index({ patientId: 1, 'values.analyte': 1, collectedAt: -1 }); // trends
labResultSchema.index({ practiceId: 1, collectedAt: -1, abnormalCount: -1 });

// Meal / exercise / steps from the patient's log sheet.
const healthLogSchema = new Schema(
  {
    patientId: ref('Patient', true),
    type: enumOf(E.LOG_TYPES, { required: true }),
    loggedAt: { type: Date, default: Date.now },
    mealType: enumOf(E.MEAL_TYPES),
    exerciseType: enumOf(E.EXERCISE_TYPES),
    durationMin: Number,
    steps: { type: Number, min: 0 },
    fromDevice: Boolean, // synced from a watch / phone (Health Connect, Apple Health)
    stepSource: String, // 'phone' (its own step sensor) or 'watch'
    note: String, // "2 rotis, dal, salad"
    photo: fileSchema,
    inputMode: enumOf(E.INPUT_MODES, { default: 'typed' }),
    sharedWith: [{ type: Schema.Types.ObjectId, ref: 'User' }],
    activityPlanId: ref('ActivityPlan'),
    review: {
      dueAt: Date, // practice food-log cadence
      by: { type: Schema.Types.ObjectId, ref: 'User' },
      at: Date,
      comment: String,
    },
  },
  baseOptions,
);
healthLogSchema.index({ patientId: 1, loggedAt: -1 });
healthLogSchema.index({ sharedWith: 1, 'review.dueAt': 1 });

// Clinical alerts: emergency chat, home reading above limit, critical lab…
const alertSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    doctorId: ref('User'),
    severity: enumOf(E.ALERT_SEVERITIES, { required: true }),
    kind: enumOf(E.ALERT_KINDS, { required: true }),
    status: enumOf(E.ALERT_STATUSES, { default: 'open' }),
    title: String,
    detail: { type: String, required: true }, // "Home BP reading 172/104 mmHg, above his alert limit."
    sourceModel: String, // "Message", "Vitals", "LabResult"
    sourceId: Schema.Types.ObjectId,
    conversationId: ref('Conversation'),
    note: String, // "Called patient, advised to come in"
    noteBy: ref('User'),
    noteAt: Date,
    acknowledged: actionStamp,
    resolved: actionStamp,
  },
  baseOptions,
);
alertSchema.index({ practiceId: 1, status: 1, severity: 1, createdAt: -1 });

module.exports = {
  MedicalRecord: model('MedicalRecord', medicalRecordSchema),
  LabResult: model('LabResult', labResultSchema),
  HealthLog: model('HealthLog', healthLogSchema),
  Alert: model('Alert', alertSchema),
};

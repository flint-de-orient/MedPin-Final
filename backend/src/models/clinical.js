// Consultation, prescriptions, vitals, medicines and adherence
// (Consult-*, Prescriptions, PP-*, Daily-Report, Patient-Medicines, Patient-Adherence).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, enumOf, fileSchema, baseOptions } = require('./common');

// ── Catalogs ──────────────────────────────────────────────

const icdCodeSchema = new Schema(
  {
    code: { type: String, required: true, unique: true }, // "E11.9"
    name: { type: String, required: true }, // "Type 2 diabetes mellitus"
  },
  baseOptions,
);
icdCodeSchema.index({ name: 'text', code: 'text' });

const medicineSchema = new Schema(
  {
    genericName: { type: String, required: true }, // "Glimepiride"
    brandNames: [String],
    form: { type: String, default: 'Tablet' },
    drugClass: String, // "sulfonylurea" — checked against allergies
    strengths: [{ value: Number, unit: String, _id: false }], // 1, 2, 4 mg
    unitsPerStrip: { type: Number, default: 10 },
    mrpPerStrip: { type: Number, min: 0 }, // ₹ per strip, used for pharmacy quotes
    active: { type: Boolean, default: true },
  },
  baseOptions,
);
medicineSchema.index({ genericName: 'text', brandNames: 'text' });

// Tests and panels ("Diabetes panel" → HbA1c, Fasting glucose, Post-prandial glucose).
const labTestSchema = new Schema(
  {
    name: { type: String, required: true, unique: true },
    panel: String,
    unit: String,
    refLow: Number,
    refHigh: Number,
    refText: String, // "< 100"
  },
  baseOptions,
);

// ── Visit ─────────────────────────────────────────────────

const diagnosisSchema = new Schema({
  name: { type: String, required: true },
  icdCode: String,
  source: enumOf(E.DIAGNOSIS_SOURCES, { default: 'catalog' }),
  reason: String, // AI suggestion reason: "Vitamin D 14 ng/mL on 18 Jul"
  reusedFrom: Date, // "Reused from 12 Mar 2026"
});

const labOrderSchema = new Schema({
  testName: { type: String, required: true },
  panel: String,
  source: enumOf(['ai', 'typed', 'panel'], { default: 'typed' }),
  selected: { type: Boolean, default: true },
});

const adviceItemSchema = new Schema({
  text: { type: String, required: true },
  category: enumOf(E.ADVICE_CATEGORIES, { default: 'general' }),
  included: { type: Boolean, default: true },
});

const rxItemSchema = new Schema({
  medicineId: ref('Medicine'),
  name: { type: String, required: true }, // "Metformin"
  strength: String, // "500 mg"
  form: String,
  // M-A-N dose pattern; "1-0-1" = morning 1, afternoon 0, night 1
  dose: {
    morning: { type: Number, min: 0, default: 0 },
    afternoon: { type: Number, min: 0, default: 0 },
    night: { type: Number, min: 0, default: 0 },
  },
  frequency: enumOf(E.FREQUENCIES, { default: 'daily' }),
  weekday: enumOf(E.WEEKDAYS), // "Once a week · Sunday"
  foodRelation: enumOf(E.FOOD_RELATIONS),
  instructions: String, // "before breakfast"
  duration: {
    value: Number,
    unit: enumOf(E.DURATION_UNITS, { default: 'days' }),
  },
  quantity: Number, // doses per day × days
  change: enumOf(E.RX_CHANGE, { default: 'new' }),
  caution: String, // "Sulfa allergy · sulfonylurea"
  entrySource: enumOf(E.ENTRY_SOURCES, { default: 'typed' }),
});

// The consultation (prescription draft while status = draft).
const consultationSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    locationId: ref('Location'),
    doctorId: ref('User', true),
    patientId: ref('Patient', true),
    appointmentId: ref('Appointment'), // null for walk-ins started from Consult-Pick
    status: enumOf(E.CONSULT_STATUSES, { default: 'draft' }),
    startedAt: { type: Date, default: Date.now },
    completedAt: Date,
    durationSec: Number,
    chiefComplaint: String,
    complaintLanguage: enumOf(E.LANGUAGES),
    vitalsId: ref('Vitals'),
    printVitalsOnRx: { type: Boolean, default: true },
    diagnoses: [diagnosisSchema],
    medications: [rxItemSchema], // draft medicines; copied to the prescription on issue
    labOrders: [labOrderSchema],
    advice: { items: [adviceItemSchema], freeText: String },
    validity: {
      preset: enumOf(E.VALIDITY_PRESETS, { default: '1_month' }),
      validUntil: Date,
    },
    followUp: {
      enabled: { type: Boolean, default: false },
      preset: enumOf(E.FOLLOW_UP_PRESETS),
      date: Date,
      remindPatient: { type: Boolean, default: true }, // 2 days before
    },
    prescriptionId: ref('Prescription'),
    aiBriefUsed: Boolean,
    draftSavedAt: Date,
  },
  baseOptions,
);
consultationSchema.index({ practiceId: 1, startedAt: -1 });
consultationSchema.index({ doctorId: 1, startedAt: -1 });
consultationSchema.index({ patientId: 1, startedAt: -1 });

// Issued prescription document (digital, or a scanned paper one).
const prescriptionSchema = new Schema(
  {
    practiceId: ref('Practice'),
    locationId: ref('Location'),
    doctorId: ref('User'),
    doctorName: String, // for prescriptions from outside MedPin
    patientId: ref('Patient', true),
    consultationId: ref('Consultation'),
    rxNumber: Number, // sequential per practice: "Rx 0286"
    kind: enumOf(E.RX_KINDS, { default: 'digital' }),
    source: enumOf(E.RX_SOURCES, { default: 'this_clinic' }),
    uploadedBy: ref('User'),
    issuedAt: { type: Date, default: Date.now },
    validUntil: Date,
    diagnosisSummary: String,
    items: [rxItemSchema],
    tests: [String],
    advice: String,
    followUpDate: Date,
    file: fileSchema, // generated PDF or scan
    sentAt: Date, // "Prescription sent to Priya"
  },
  baseOptions,
);
prescriptionSchema.index({ practiceId: 1, rxNumber: 1 }, {
  unique: true,
  partialFilterExpression: { rxNumber: { $type: 'number' } },
});
prescriptionSchema.index({ patientId: 1, issuedAt: -1 });

// ── Vitals and readings ───────────────────────────────────

// Clinic vitals and home readings share one collection.
const vitalsSchema = new Schema(
  {
    patientId: ref('Patient', true),
    practiceId: ref('Practice'),
    appointmentId: ref('Appointment'),
    consultationId: ref('Consultation'),
    recordedAt: { type: Date, default: Date.now },
    recordedBy: ref('User'),
    recordedByRole: enumOf(['patient', ...E.MEMBER_ROLES]),
    source: enumOf(E.VITAL_SOURCES, { default: 'clinic' }),
    bpSystolic: { type: Number, min: 40, max: 300 },
    bpDiastolic: { type: Number, min: 20, max: 200 },
    pulse: { type: Number, min: 20, max: 250 },
    spo2: { type: Number, min: 50, max: 100 },
    temperatureF: { type: Number, min: 90, max: 110 },
    weightKg: { type: Number, min: 2, max: 400 },
    heightCm: { type: Number, min: 30, max: 250 },
    bmi: Number, // weight / (height/100)², stored for reports
    bloodSugar: { type: Number, min: 10, max: 1000 }, // mg/dL
    sugarType: enumOf(E.SUGAR_TYPES),
    note: String,
  },
  baseOptions,
);
vitalsSchema.index({ patientId: 1, recordedAt: -1 });

// ── Medicines the patient is taking ───────────────────────

// One running medicine on Patient-Medicines (from a prescription item or added by hand).
const medicationCourseSchema = new Schema(
  {
    patientId: ref('Patient', true),
    prescriptionId: ref('Prescription'),
    rxItemId: Schema.Types.ObjectId,
    doctorId: ref('User'),
    prescriberName: String, // "Dr. Rina Mitra"
    medicineId: ref('Medicine'),
    name: { type: String, required: true },
    strength: String,
    dose: { morning: Number, afternoon: Number, night: Number },
    frequency: enumOf(E.FREQUENCIES, { default: 'daily' }),
    weekday: enumOf(E.WEEKDAYS),
    foodRelation: enumOf(E.FOOD_RELATIONS),
    instructions: String,
    startDate: { type: Date, required: true },
    endDate: Date, // null = ongoing
    trackingEnabled: { type: Boolean, default: true },
    stockUnits: { type: Number, min: 0 }, // "6 · 3 days"
    stockUpdatedAt: Date,
    unitsPerStrip: { type: Number, default: 10 },
    status: enumOf(E.COURSE_STATUSES, { default: 'active' }),
    stoppedAt: Date,
  },
  baseOptions,
);
medicationCourseSchema.index({ patientId: 1, status: 1 });

// One scheduled dose: Taken / Skipped / missed (drives adherence %).
const doseLogSchema = new Schema(
  {
    courseId: ref('MedicationCourse', true),
    patientId: ref('Patient', true),
    scheduledAt: { type: Date, required: true },
    slot: enumOf(E.DOSE_SLOTS, { required: true }),
    status: enumOf(E.DOSE_STATUSES, { default: 'due' }),
    takenAt: Date,
    remindedAt: Date,
  },
  baseOptions,
);
doseLogSchema.index({ courseId: 1, scheduledAt: 1 }, { unique: true });
doseLogSchema.index({ patientId: 1, scheduledAt: -1 });

// ── Treatment plan (PP-Treatment) ─────────────────────────

const treatmentPlanSchema = new Schema(
  {
    patientId: ref('Patient', true),
    practiceId: ref('Practice'),
    doctorId: ref('User', true),
    consultationId: ref('Consultation'),
    nextVisitAt: Date,
    sections: [
      {
        category: enumOf(E.ADVICE_CATEGORIES, { required: true }),
        items: [String],
        _id: false,
      },
    ],
    nutritionBy: ref('User'), // "Covered by Mou Banerjee, Dietician"
    healthSummary: String, // patient-facing AI summary
    focusItems: [String], // "FOCUS THIS WEEK"
  },
  baseOptions,
);
treatmentPlanSchema.index({ patientId: 1, doctorId: 1 }, { unique: true });

module.exports = {
  IcdCode: model('IcdCode', icdCodeSchema),
  Medicine: model('Medicine', medicineSchema),
  LabTest: model('LabTest', labTestSchema),
  Consultation: model('Consultation', consultationSchema),
  Prescription: model('Prescription', prescriptionSchema),
  Vitals: model('Vitals', vitalsSchema),
  MedicationCourse: model('MedicationCourse', medicationCourseSchema),
  DoseLog: model('DoseLog', doseLogSchema),
  TreatmentPlan: model('TreatmentPlan', treatmentPlanSchema),
};

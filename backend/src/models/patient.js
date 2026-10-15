// Patient profile, consent, clinic links and care-team sharing
// (Add-Patient, Add-Patient-Existing, Consult-QuickAdd, Patient-Me, Patient-Track).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, phone, enumOf, pointSchema, baseOptions } = require('./common');

const conditionSchema = new Schema({
  name: { type: String, required: true }, // "Type 2 diabetes"
  icdCode: String, // "E11.9"
  since: Date, // "since Jun 2025"
  addedBy: ref('User'),
});

const allergySchema = new Schema({
  allergen: { type: String, required: true }, // "Sulfa drugs"
  drugClass: String, // matched against medicine drug class for cautions
  addedBy: ref('User'),
});

const addressSchema = new Schema({
  label: String, // "Home"
  line: { type: String, required: true }, // "Flat 3B, 12 Purbachal Rd, Salt Lake"
  area: String,
  city: String,
  pincode: { type: String, match: /^\d{6}$/ },
  geo: pointSchema,
  isDefault: { type: Boolean, default: false },
});

// One patient record per phone number across MedPin: clinics link to it
// with the patient's consent code instead of creating duplicates.
const patientSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User' }, // set once the patient joins the app
    name: { type: String, required: true, trim: true },
    phone: { ...phone(true), unique: true },
    phoneVerifiedAt: Date,
    dateOfBirth: Date,
    ageYears: { type: Number, min: 0, max: 130 }, // when only age was given
    ageRecordedAt: Date,
    gender: enumOf(E.GENDERS, { required: true }),
    bloodGroup: enumOf(E.BLOOD_GROUPS),
    heightCm: { type: Number, min: 50, max: 250 },
    weightKg: { type: Number, min: 2, max: 400 },
    conditions: [conditionSchema],
    allergies: [allergySchema],
    emergencyContact: { name: String, phone: phone() },
    addresses: [addressSchema],
    area: String, // "near Salt Lake" for doctor search
    geo: pointSchema,
    riskLevel: enumOf(E.RISK_LEVELS),
    // Last watch / phone sync, what it brought in, and when data last came from a watch or ring app.
    deviceSync: {
      at: Date, source: String, readings: Number, stepDays: Number,
      devices: { watch: { at: Date, apps: [String] }, ring: { at: Date, apps: [String] } },
    },
    // Who sees the daily log (meals, exercise, steps): the patient's choice. Unset: those whose access includes the log.
    logShareWith: { type: [{ type: Schema.Types.ObjectId, ref: 'User' }], default: undefined },
    healthScore: { value: { type: Number, min: 0, max: 100 }, weeklyDelta: Number, computedAt: Date },
    trackedMeasures: {
      type: [enumOf(E.TRACKED_MEASURES)],
      default: ['blood_sugar', 'blood_pressure'],
      validate: [(v) => v.length <= 4, 'Track up to 4 measures'],
    },
    // Limits that raise an alert ("above his alert limit")
    alertLimits: {
      bpSystolicMax: Number,
      bpDiastolicMax: Number,
      sugarFastingMax: Number,
      pulseMin: Number,
      pulseMax: Number,
      spo2Min: Number,
    },
    targets: { sugarFasting: Number, hba1c: Number, ldl: Number, stepsPerDay: { type: Number, default: 8000 } },
    settings: {
      medReminders: { type: Boolean, default: true },
      dailyLogReminder: { type: Boolean, default: true },
      dailyLogReminderAt: { type: String, default: '20:00' },
      visitReminders: { type: Boolean, default: true },
      // Breakfast / lunch / dinner (doses are timed around them: services/care.js doseMinute).
      reminderTimes: {
        morning: { type: String, default: '08:00' },
        afternoon: { type: String, default: '13:30' },
        night: { type: String, default: '20:30' },
      },
      bedAt: { type: String, default: '22:30' }, // "at bedtime" doses
    },
    createdByPracticeId: ref('Practice'),
    createdBy: ref('User'),
    smsInviteSentAt: Date, // QuickAdd: invite to join MedPin
  },
  baseOptions,
);
patientSchema.index({ userId: 1 }, { unique: true, partialFilterExpression: { userId: { $type: 'objectId' } } });
patientSchema.index({ name: 'text' });
patientSchema.index({ geo: '2dsphere' });

// Rotating 6-digit code in the patient app; a clinic enters it to link the record.
const consentCodeSchema = new Schema(
  {
    patientId: ref('Patient', true),
    codeHash: { type: String, required: true },
    expiresAt: { type: Date, required: true },
    usedAt: Date,
    usedByPracticeId: ref('Practice'),
    wrongTries: { type: Number, default: 0 }, // 5 wrong tries cancel the code
  },
  baseOptions,
);
consentCodeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 3600 });

// Patient ↔ practice link ("Priya shares her full record with City Care Clinic").
const patientEnrolmentSchema = new Schema(
  {
    patientId: ref('Patient', true),
    practiceId: ref('Practice', true),
    status: enumOf(E.ENROLMENT_STATUSES, { default: 'pending_code' }),
    shareScope: enumOf(E.SHARE_SCOPES, { default: 'full' }),
    clinicPatientNo: String, // optional practice file number
    homeLocationId: ref('Location'), // the branch they were registered at (their "usual" one until visits say otherwise)
    linkedBy: ref('User'),
    linkedAt: Date,
    revokedAt: Date,
  },
  baseOptions,
);
patientEnrolmentSchema.index({ patientId: 1, practiceId: 1 }, { unique: true });

// Patient-controlled access per care-team member ("Who can see your record").
const careTeamAccessSchema = new Schema(
  {
    patientId: ref('Patient', true),
    userId: ref('User', true), // doctor, dietician…
    practiceId: ref('Practice'),
    role: enumOf(E.MEMBER_ROLES),
    accessLevel: enumOf(E.ACCESS_LEVELS, { default: 'full_record' }),
    since: { type: Date, default: Date.now }, // "Your doctor since June 2025"
    isPrimary: Boolean,
    changedAt: Date,
    viewerNotifiedAt: Date, // "They are told when you change it"
  },
  baseOptions,
);
careTeamAccessSchema.index({ patientId: 1, userId: 1 }, { unique: true });

// Planned activity on Patient-Home ("Evening walk · 30 min · 3 of 5 this week").
const activityPlanSchema = new Schema(
  {
    patientId: ref('Patient', true),
    name: { type: String, required: true },
    exerciseType: enumOf(E.EXERCISE_TYPES, { default: 'walk' }),
    durationMin: Number,
    plannedTime: String, // "18:00"
    daysPerWeek: { type: Number, min: 1, max: 7 },
    completions: [Date],
    setBy: ref('User'),
    active: { type: Boolean, default: true },
  },
  baseOptions,
);

module.exports = {
  Patient: model('Patient', patientSchema),
  ConsentCode: model('ConsentCode', consentCodeSchema),
  PatientEnrolment: model('PatientEnrolment', patientEnrolmentSchema),
  CareTeamAccess: model('CareTeamAccess', careTeamAccessSchema),
  ActivityPlan: model('ActivityPlan', activityPlanSchema),
};

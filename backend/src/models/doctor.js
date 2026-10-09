// Doctor profile, practice locations, services/fees, schedule and leave
// (Doctor-MyProfile, Profile-Professional, Profile-Location, Profile-Schedule,
// Patient-FindDoctor directory).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, rupees, minuteOfDay, enumOf, fileSchema, baseOptions } = require('./common');

// Specialty tiles on Find doctor (gp, diabetes, heart, women, child, skin…).
const specialtySchema = new Schema(
  {
    key: { type: String, required: true, unique: true },
    label: { type: String, required: true }, // "Diabetes & thyroid"
    aiRole: String, // "Diabetes and thyroid specialist"
    keywords: [String], // symptom words that map to this specialty
    order: Number,
  },
  baseOptions,
);

const qualificationSchema = new Schema({
  name: { type: String, required: true, trim: true }, // "MD, Internal Medicine"
  institution: String, // "IPGMER, Kolkata"
  year: { type: Number, min: 1950, max: 2100 },
  proofStatus: enumOf(E.PROOF_STATUSES, { default: 'upload' }),
  proof: fileSchema,
});

const doctorProfileSchema = new Schema(
  {
    userId: { ...ref('User', true), unique: true },
    displayName: { type: String, required: true }, // "Dr. Arjun Sen"
    gender: enumOf(E.GENDERS), // "Female doctor" filter
    profession: enumOf(E.PROFESSIONS, { default: 'doctor' }),
    headline: String, // "Diabetologist · Internal medicine"
    specialtyKeys: [{ type: String, index: true }], // Specialty.key, for search
    specialisations: [String], // tag list
    conditionsTreated: [String], // patient-search keywords
    memberships: [String], // "RSSDI member"
    languagesSpoken: [enumOf(E.SPOKEN_LANGUAGES)],
    qualifications: [qualificationSchema],
    degreesSummary: String, // "MBBS, MD"
    practisingSince: Number,
    registration: {
      council: String, // "West Bengal Medical Council"
      councilShort: String, // "WBMC"
      number: String, // "64213"
      year: Number,
      status: enumOf(E.VERIFICATION_STATUSES, { default: 'not_submitted' }),
    },
    hprId: String, // ABDM Healthcare Professional Registry
    hprLinkedAt: Date,
    isVerified: { type: Boolean, default: false },
    photo: fileSchema,
    bio: { type: String, maxlength: 2000 },
    signature: fileSchema, // required before prescriptions can be sent
    offersVideo: { type: Boolean, default: false },
    acceptingBookings: { type: Boolean, default: true },
    presence: enumOf(E.DOCTOR_PRESENCE, { default: 'away' }),
    avgReplyMinutes: Number,
    followUpReminder: {
      daysBefore: { type: Number, default: 3 },
      channels: { type: [enumOf(E.REMINDER_CHANNELS)], default: ['whatsapp', 'app'] },
    },
    payout: {
      upiId: String,
      bankAccountLast4: String,
      ifsc: String,
      razorpayAccountId: String,
    },
    // Queue-Select "Don't ask again today"
    defaultQueueLocation: { locationId: ref('Location'), forDate: Date },
    recentSearches: { type: [String], default: [] },
  },
  baseOptions,
);
doctorProfileSchema.index({ displayName: 'text', specialisations: 'text', conditionsTreated: 'text' });

const sessionSchema = new Schema({ startMin: minuteOfDay, endMin: minuteOfDay }, { _id: false });

const scheduleDaySchema = new Schema(
  {
    weekday: enumOf(E.WEEKDAYS, { required: true }),
    sessions: [sessionSchema], // empty = closed
  },
  { _id: false },
);

const serviceSchema = new Schema({
  name: { type: String, required: true }, // "New consultation"
  details: String, // "15 min · in clinic"
  durationMin: Number,
  mode: enumOf(E.VISIT_MODES, { default: 'in_clinic' }),
  visitType: enumOf(E.VISIT_TYPES),
  fee: { ...rupees, default: 0 }, // 0 = Free
  freeWithinDays: Number, // "Report review · within 7 days of a visit"
});

// Where a doctor practises: services/fees and the weekly schedule for that place.
const doctorLocationSchema = new Schema(
  {
    doctorId: ref('User', true),
    locationId: ref('Location', true),
    practiceId: ref('Practice', true),
    services: [serviceSchema],
    schedule: {
      week: [scheduleDaySchema],
      slotLengthMin: { type: Number, min: 5, max: 60, default: 15 },
      patientsPerSlot: { type: Number, min: 1, max: 6, default: 1 },
      walkInPlaces: { type: Number, min: 0, default: 0 },
      breakBetweenMin: { type: Number, min: 0, max: 30, default: 0 },
      bookingWindowDays: { type: Number, min: 1, max: 60, default: 7 },
      cancelCutoffHours: { type: Number, min: 1, max: 48, default: 2 },
      onlineBooking: { type: Boolean, default: true },
      requireApproval: { type: Boolean, default: false },
    },
    status: enumOf(['active', 'ended'], { default: 'active' }),
    endedAt: Date, // "Stop practising here" — history is kept
  },
  baseOptions,
);
doctorLocationSchema.index({ doctorId: 1, locationId: 1 }, { unique: true });

// Leave / holidays: "Durga Puja · 19 – 23 Oct · 14 patients will be told".
const doctorLeaveSchema = new Schema(
  {
    doctorId: ref('User', true),
    locationId: ref('Location'), // null = all locations
    reason: { type: String, required: true },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    patientsNotifiedAt: Date,
    cancelledAt: Date,
  },
  baseOptions,
);

module.exports = {
  Specialty: model('Specialty', specialtySchema),
  DoctorProfile: model('DoctorProfile', doctorProfileSchema),
  DoctorLocation: model('DoctorLocation', doctorLocationSchema),
  DoctorLeave: model('DoctorLeave', doctorLeaveSchema),
};

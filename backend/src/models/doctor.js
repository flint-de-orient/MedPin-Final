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
  proofNote: String, // why a proof was not accepted
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
    signature: fileSchema, // required before prescriptions can be sent (the cleaned, transparent PNG)
    signatureOriginal: fileSchema, // the photo as uploaded, kept for re-checks
    // Signature checker result (services/signature.js).
    signatureCheck: {
      status: { type: String, enum: ['ok', 'warn'] },
      issues: [{ _id: false, code: String, severity: String, message: String }],
      readsAs: String,
      by: String, // 'image' or 'image+ai'
      acceptedWarnings: Boolean, // the doctor chose to use it anyway
      checkedAt: Date,
    },
    offersVideo: { type: Boolean, default: false },
    acceptingBookings: { type: Boolean, default: true },
    presence: enumOf(E.DOCTOR_PRESENCE, { default: 'auto' }), // the doctor's choice; what patients see is live
    avgReplyMinutes: Number, // the doctor's own estimate, used until enough replies are measured
    followUpReminder: {
      daysBefore: { type: Number, default: 3 },
      channels: { type: [enumOf(E.REMINDER_CHANNELS)], default: ['whatsapp', 'app'] },
    },
    payout: {
      upiId: { type: String, trim: true, match: [/^[\w.-]{2,}@[a-zA-Z]{2,}$/, 'Enter a UPI ID like name@bank'] },
      accountHolder: { type: String, trim: true },
      bankName: { type: String, trim: true },
      bankBranch: { type: String, trim: true }, // from the IFSC: "Salt Lake, Kolkata"
      bankAccountLast4: { type: String, match: /^\d{4}$/ }, // only the last 4 digits are stored
      ifsc: { type: String, uppercase: true, trim: true, match: [/^[A-Z]{4}0[A-Z0-9]{6}$/, 'Enter an 11-character IFSC like HDFC0001234'] },
      preferred: enumOf(['upi', 'bank']),
      updatedAt: Date,
      razorpayAccountId: String,
      razorpayContactId: String, // RazorpayX contact for this doctor
      razorpayFundAccountId: String, // where payouts go (the UPI ID or bank account above)
      fundAccountFor: String, // 'upi:<id>' or 'bank:<last4>' the fund account was made for
    },
    // Chat and urgent messages
    chatSettings: {
      whoCanMessage: enumOf(['booked', 'anyone', 'nobody'], { default: 'booked' }),
      aiReplies: { type: Boolean, default: true }, // MedPin AI answers my patients' chats
      urgentAlerts: { type: Boolean, default: true },
      replyHours: { from: { type: String, default: '09:00' }, to: { type: String, default: '20:00' } },
      awayMessage: { type: String, maxlength: 300 },
    },
    // Notifications (in-app items are always kept)
    notificationPrefs: {
      push: { type: Boolean, default: true },
      whatsapp: { type: Boolean, default: true },
      email: { type: Boolean, default: false },
      dailyDigest: { type: Boolean, default: true },
      quietHours: {
        enabled: { type: Boolean, default: false },
        from: { type: String, default: '22:00' },
        to: { type: String, default: '07:00' },
      },
      types: {
        appointments: { type: Boolean, default: true },
        messages: { type: Boolean, default: true },
        labResults: { type: Boolean, default: true },
        followUps: { type: Boolean, default: true },
      },
    },
    // Queue-Select "Don't ask again today"
    defaultQueueLocation: { locationId: ref('Location'), forDate: Date },
    recentSearches: { type: [String], default: [] },
  },
  baseOptions,
);
doctorProfileSchema.index({ displayName: 'text', specialisations: 'text', conditionsTreated: 'text' });

// The blue "Verified" tick: a registration number on file and every degree's
// proof approved by the MedPin team. Kept up to date on every save, so adding
// a degree, a new proof (back in review) or clearing the registration removes it.
doctorProfileSchema.methods.verifiedNow = function verifiedNow() {
  return Boolean(this.registration?.number) && this.qualifications.length > 0 && this.qualifications.every((q) => q.proofStatus === 'verified');
};
doctorProfileSchema.pre('save', function setVerified() {
  this.isVerified = this.verifiedNow();
});

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

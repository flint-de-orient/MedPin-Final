// Practice, locations, hours, departments and team
// (Practice, Clinics, Clinic-Editor, Departments, People*, Profile-Location).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, phone, anyPhone, minuteOfDay, enumOf, fileSchema, pointSchema, baseOptions } = require('./common');

const practiceSchema = new Schema(
  {
    name: { type: String, required: true, trim: true }, // "City Care Clinic"
    tagline: String, // "Diabetes and heart care since 2011"
    registrationNo: String, // "WB/CE/2011/0412"
    logo: fileSchema,
    logoIsDark: Boolean, // "Dark background detected — we'll print a light version"
    patientCallNumber: anyPhone, // Profile: clinic number patients call
    foodLogReviewCadence: enumOf(E.FOOD_LOG_REVIEW_CADENCES, { default: 'every_3_days' }),
    // "Call next" in the queue (the patient is told it's their turn); the owner can turn it off.
    callNext: { type: Boolean, default: true },
    // Who MedPin's plan invoices are billed to (Plan & billing → Billing details).
    billing: {
      name: { type: String, maxlength: 120 }, // legal / trade name
      address: { type: String, maxlength: 300 },
      state: { type: String, maxlength: 60 },
      gstin: { type: String, maxlength: 15 },
      _id: false,
    },
    // The clinic's own reply templates for patient chats ("Clinic timings", "Report received").
    replyTemplates: [{ title: { type: String, maxlength: 60 }, text: { type: String, maxlength: 1000 }, _id: false }],
    ownerUserId: ref('User', true),
  },
  baseOptions,
);

// Printed at the top of prescriptions from a location.
const letterheadSchema = new Schema(
  {
    tagline: String,
    doctorNamePrinted: String, // "Dr. Arjun Sen, MBBS, MD (Medicine)"
    registrationNo: String,
    logo: fileSchema,
    logoIsDark: Boolean,
    logoBackgroundRemoved: Boolean, // the plain background was made transparent
  },
  { _id: false },
);

// Clinic weekly hours, one row per weekday (Clinic-Editor).
const clinicHoursSchema = new Schema(
  {
    weekday: enumOf(E.WEEKDAYS, { required: true }),
    isOpen: { type: Boolean, default: true },
    opensAt: minuteOfDay, // 540 = 9:00 AM
    closesAt: minuteOfDay,
  },
  { _id: false },
);

const locationSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    // Shared desks such as "Apollo Diagnostics desk" are managed by another org.
    managedByPracticeId: ref('Practice'),
    name: { type: String, required: true, trim: true }, // "City Care Clinic — Salt Lake"
    shortName: String, // "Salt Lake"
    type: enumOf(E.LOCATION_TYPES, { default: 'clinic' }),
    status: enumOf(E.LOCATION_STATUSES, { default: 'active' }),
    address: String,
    area: { type: String, index: true }, // "Salt Lake" — doctor search
    city: String,
    pincode: { type: String, match: /^\d{6}$/ },
    landmark: String,
    phone: anyPhone,
    patientPhone: anyPhone,
    geo: pointSchema,
    googleMapsUrl: String,
    hfrId: String, // ABDM Health Facility Registry
    hfrLinkedAt: Date,
    facilities: [String], // Wheelchair access, Parking, Lab sample collection, Pharmacy
    paymentMethods: [enumOf(E.PAYMENT_METHODS)],
    collectFeeAtBooking: { type: Boolean, default: false },
    slotMinutes: { type: Number, min: 5, max: 60, default: 15 },
    weeklyHours: [clinicHoursSchema],
    letterhead: letterheadSchema,
    deactivatedAt: Date, // locations are never deleted
  },
  baseOptions,
);
locationSchema.index({ geo: '2dsphere' });

// Holidays: "Durga Puja · Tue 20 – Fri 23 Oct 2026 · closed all day".
const locationClosureSchema = new Schema(
  {
    locationId: ref('Location', true),
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    reason: { type: String, default: 'Closed all day' },
    allDay: { type: Boolean, default: true },
    // Part of the day (allDay false): closed from fromMin to toMin on each of those days.
    fromMin: minuteOfDay,
    toMin: minuteOfDay,
    createdBy: ref('User'),
    patientsTold: Number, // booked patients told to choose another day
  },
  baseOptions,
);

// practiceId null = shared MedPin department (read-only for practices).
const departmentSchema = new Schema(
  {
    practiceId: ref('Practice'),
    name: { type: String, required: [true, 'Enter a department name'], trim: true },
  },
  baseOptions,
);
departmentSchema.index({ practiceId: 1, name: 1 }, { unique: true });

// A user's membership in a practice. Permissions come from the role.
const memberSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    userId: ref('User', true),
    role: enumOf(E.MEMBER_ROLES, { required: true }),
    departmentId: ref('Department'),
    locationIds: [{ type: Schema.Types.ObjectId, ref: 'Location' }],
    allLocations: { type: Boolean, default: false },
    isOwner: { type: Boolean, default: false },
    // 'removed': taken off the team (People → Remove); kept so their history still has a name.
    status: enumOf([...E.MEMBER_STATUSES, 'removed'], { default: 'active' }),
    suspendedAt: Date,
    removedAt: Date,
    // Doctor's assistant: the doctor(s) they work for (People-Add / People-Member).
    assistsDoctorIds: [{ type: Schema.Types.ObjectId, ref: 'User' }],
    joinedAt: { type: Date, default: Date.now },
    // Doctor-only fields on People-Add
    qualifications: String, // "MBBS, DNB (Endocrinology)"
    registrationNo: String, // "WBMC 71842"
    phone: phone(), // copy for the team list
    invitedBy: ref('User'),
  },
  baseOptions,
);
memberSchema.index({ practiceId: 1, userId: 1 }, { unique: true });

// Dashboard panels by department ("Used by 2 dashboard panels").
const dashboardPanelSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    departmentId: ref('Department'),
    kind: { type: String, required: true }, // e.g. lab_flags, bp_control, ldl, ecg
    title: String,
    order: Number,
    config: Schema.Types.Mixed,
  },
  baseOptions,
);

// Fixed permissions per role (common_d9: "There's no separate permission step").
// What each role may do in its practice (owners also pass ownerOnly checks).
//   clinical      doctor-side screens: dashboard, consultations (read), clinician tabs
//   prescribe     write consultations, issue / send prescriptions
//   editRecords   conditions, allergies, treatment plan, patient details
//   labs          enter lab results;  labReview  mark results reviewed
//   alerts        see clinical alerts; manageAlerts  acknowledge / resolve them
//   ai            MedPin AI assistant, chat reviews and summaries
//   reports       MIS reports;  fees  payments & fee collection
//   billing       plan & invoices;  exports  downloads with patient phone numbers
const ROLE_PERMISSIONS = {
  doctor: {
    viewPatients: true, clinical: true, prescribe: true, editRecords: true, labs: true, labReview: true, chats: true,
    alerts: true, manageAlerts: true, ai: true, reports: true, fees: true, billing: false, exports: true,
  },
  front_desk: {
    viewPatients: true, clinical: false, prescribe: false, editRecords: false, labs: false, labReview: false, chats: true,
    alerts: false, manageAlerts: false, ai: false, reports: false, fees: true, billing: false, exports: false,
  },
  doctor_assistant: {
    viewPatients: true, clinical: true, prescribe: false, editRecords: true, labs: true, labReview: false, chats: true,
    alerts: true, manageAlerts: false, ai: true, reports: false, fees: true, billing: false, exports: false,
  },
  dietician: {
    viewPatients: true, clinical: true, prescribe: false, editRecords: true, labs: false, labReview: false, chats: true,
    alerts: false, manageAlerts: false, ai: true, reports: false, fees: false, billing: false, exports: false,
  },
  // Lab staff enter results; "reviewed" means a doctor has seen it (the patient is told so).
  lab_manager: {
    viewPatients: true, clinical: false, prescribe: false, editRecords: false, labs: true, labReview: false, chats: false,
    alerts: false, manageAlerts: false, ai: false, reports: false, fees: false, billing: false, exports: false,
  },
  lab_technician: {
    viewPatients: true, clinical: false, prescribe: false, editRecords: false, labs: true, labReview: false, chats: false,
    alerts: false, manageAlerts: false, ai: false, reports: false, fees: false, billing: false, exports: false,
  },
  practice_manager: {
    viewPatients: true, clinical: false, prescribe: false, editRecords: false, labs: false, labReview: false, chats: true,
    alerts: false, manageAlerts: false, ai: false, reports: true, fees: true, billing: true, exports: true,
  },
};

// Clinic set-up (Clinic-Editor), like a clinic's admin / reception split:
//   manageClinic  location details, weekly hours, letterhead, map pin, holidays
//   closures      add / remove holidays & closures at the locations they cover
//                 (the front desk keeps the calendar; booked patients are told)
//   doctorHours   change a doctor's hours at a location (an assistant: only the
//                 doctors they assist; every doctor may change their own)
// Owners pass every check (middleware need()).
const CLINIC_PERMISSIONS = {
  practice_manager: { manageClinic: true, closures: true, doctorHours: true },
  front_desk: { closures: true },
  doctor_assistant: { doctorHours: true },
};
for (const [role, perms] of Object.entries(ROLE_PERMISSIONS)) {
  Object.assign(perms, { manageClinic: false, closures: false, doctorHours: false }, CLINIC_PERMISSIONS[role]);
}

// Recording vitals (BP, pulse, SpO2, temperature, weight, sugar): the doctor, and
// the people who take them in a real clinic before the patient goes in — the
// front desk, the doctor's assistant, the practice manager; a dietician weighs.
// Lab staff don't (their readings come in on the lab report).
const VITALS_ROLES = ['doctor', 'front_desk', 'doctor_assistant', 'practice_manager', 'dietician'];
for (const [role, perms] of Object.entries(ROLE_PERMISSIONS)) perms.vitals = VITALS_ROLES.includes(role);

// Giving money back that nobody had to (a goodwill refund or an overcharge on a
// visit that wasn't cancelled) and letting a fee go: the doctor, owner or practice
// manager. The desk still carries out refunds already due (a cancelled visit's
// fee handed back, an online refund retried) with `fees`.
const REFUND_ROLES = ['doctor', 'practice_manager'];
for (const [role, perms] of Object.entries(ROLE_PERMISSIONS)) perms.refunds = REFUND_ROLES.includes(role);

module.exports = {
  Practice: model('Practice', practiceSchema),
  Location: model('Location', locationSchema),
  LocationClosure: model('LocationClosure', locationClosureSchema),
  Department: model('Department', departmentSchema),
  Member: model('Member', memberSchema),
  DashboardPanel: model('DashboardPanel', dashboardPanelSchema),
  ROLE_PERMISSIONS,
};

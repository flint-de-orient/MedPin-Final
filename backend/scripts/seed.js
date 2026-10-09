// Loads the catalogs the app needs, plus the demo practice used in the design
// (City Care Clinic, Dr. Arjun Sen, Tania Ghosh, Priya Sharma).
// Safe to run more than once: catalogs are upserted, demo data is added once.
// Usage: npm run db:seed            (catalogs + demo)
//        npm run db:seed -- --catalogs-only
const { connect, disconnect } = require('../src/db');
const env = require('../src/config/env');
const M = require('../src/models');

const upsertAll = (Model, key, rows) =>
  Model.bulkWrite(
    rows.map((row) => ({ updateOne: { filter: { [key]: row[key] }, update: { $set: row }, upsert: true } })),
  );

const PLANS = [
  { key: 'starter', name: 'Starter', priceMonthly: 999, seats: 3, activePatients: 150, aiChatsPerMonth: 1000 },
  { key: 'clinic', name: 'Clinic', priceMonthly: 2499, seats: 8, activePatients: 500, aiChatsPerMonth: 3000 },
  { key: 'hospital', name: 'Hospital', priceMonthly: 7999, seats: 25, activePatients: 2000, aiChatsPerMonth: 12000 },
];

const SPECIALTIES = [
  ['gp', 'General', 'General physician'],
  ['diabetes', 'Diabetes & thyroid', 'Diabetes and thyroid specialist'],
  ['heart', 'Heart', 'Heart specialist (cardiologist)'],
  ['women', "Women's health", 'Gynaecologist'],
  ['child', 'Child', 'Child specialist (paediatrician)'],
  ['skin', 'Skin & hair', 'Skin specialist (dermatologist)'],
  ['bones', 'Bones & joints', 'Bone and joint specialist (orthopaedic)'],
  ['mind', 'Mind', 'Mental health specialist (psychiatrist)'],
  ['stomach', 'Stomach', 'Stomach specialist (gastroenterologist)'],
  ['eye', 'Eye', 'Eye specialist (ophthalmologist)'],
  ['teeth', 'Teeth', 'Dentist'],
  ['ent', 'Ear, nose & throat', 'ENT specialist'],
].map(([key, label, aiRole], order) => ({ key, label, aiRole, order }));

const SHARED_DEPARTMENTS = ['Cardiology', 'General medicine', 'Gynaecology', 'Nephrology'];

const ICD = [
  ['I10', 'Essential hypertension'],
  ['E78.1', 'Hypertriglyceridaemia'],
  ['E78.2', 'Mixed dyslipidaemia'],
  ['E78.5', 'Dyslipidaemia'],
  ['E05.9', 'Hyperthyroidism'],
  ['E03.9', 'Hypothyroidism'],
  ['E11.9', 'Type 2 diabetes mellitus'],
  ['E11.65', 'Type 2 diabetes mellitus, poorly controlled'],
  ['E28.2', 'Polycystic ovary syndrome'],
  ['E66.9', 'Obesity'],
  ['E55.9', 'Vitamin D deficiency'],
  ['D50.9', 'Iron deficiency anaemia'],
  ['K21.9', 'Gastro-oesophageal reflux disease'],
  ['G43.9', 'Migraine'],
  ['J45.9', 'Asthma'],
  ['N18.9', 'Chronic kidney disease'],
  ['I25.10', 'Coronary artery disease'],
  ['R07.89', 'Other chest pain'],
].map(([code, name]) => ({ code, name }));

// [name, drug class, strengths, MRP per strip of 10 (₹)]
const MEDICINES = [
  ['Metformin', 'biguanide', [[500, 'mg'], [850, 'mg'], [1000, 'mg']], 40],
  ['Glimepiride', 'sulfonylurea', [[1, 'mg'], [2, 'mg'], [4, 'mg']], 75],
  ['Telmisartan', 'angiotensin receptor blocker', [[20, 'mg'], [40, 'mg'], [80, 'mg']], 95],
  ['Levothyroxine', 'thyroid hormone', [[25, 'mcg'], [50, 'mcg'], [75, 'mcg'], [100, 'mcg']], 120],
  ['Atorvastatin', 'statin', [[10, 'mg'], [20, 'mg'], [40, 'mg']], 60],
  ['Vitamin D3', 'vitamin', [[60000, 'IU']], 45],
  ['Myo-inositol', 'supplement', [[2, 'g']], 350],
].map(([genericName, drugClass, s, mrpPerStrip]) => ({
  genericName,
  drugClass,
  form: genericName === 'Vitamin D3' ? 'Capsule' : 'Tablet',
  strengths: s.map(([value, unit]) => ({ value, unit })),
  mrpPerStrip,
}));

const PHARMACIES = [
  { name: 'CarePlus Online', type: 'online', deliveryFee: 0, discountPct: 12, deliveryEtaText: 'Delivers tomorrow by 11 AM · free delivery' },
  { name: 'QuickMeds', type: 'online', deliveryFee: 15, discountPct: 5, deliveryEtaText: 'Delivers today in 2 hours' },
  { name: 'Salt Lake Medicals', type: 'nearby', discountPct: 8, pickupEtaMin: 30, geo: { type: 'Point', coordinates: [88.4135, 22.5872] } },
  { name: 'Purbachal Pharmacy', type: 'nearby', discountPct: 10, pickupEtaMin: 45, geo: { type: 'Point', coordinates: [88.4012, 22.5801] } },
];

const LAB_TESTS = [
  ['HbA1c', 'Diabetes panel', '%', null, 5.7],
  ['Fasting glucose', 'Diabetes panel', 'mg/dL', 70, 99],
  ['Post-prandial glucose', 'Diabetes panel', 'mg/dL', null, 140],
  ['Lipid profile', 'Lipid panel', null, null, null],
  ['TSH', 'Thyroid panel', 'mIU/L', 0.4, 4.0],
  ['Free T4', 'Thyroid panel', 'ng/dL', 0.8, 1.8],
  ['Serum creatinine', 'Kidney panel', 'mg/dL', 0.7, 1.2],
  ['Urine albumin', 'Kidney panel', 'mg/g', null, 30],
  ['Vitamin D', null, 'ng/mL', 30, 100],
  ['CBC', null, null, null, null],
  ['ECG', null, null, null, null],
  ['Troponin I', null, 'ng/mL', null, 0.04],
  ['Urine routine', null, null, null, null],
].map(([name, panel, unit, refLow, refHigh]) => ({ name, panel, unit, refLow, refHigh }));

async function seedCatalogs() {
  await upsertAll(M.Plan, 'key', PLANS);
  await upsertAll(M.Specialty, 'key', SPECIALTIES);
  await upsertAll(M.IcdCode, 'code', ICD);
  await upsertAll(M.Medicine, 'genericName', MEDICINES);
  await upsertAll(M.LabTest, 'name', LAB_TESTS);
  await upsertAll(M.Pharmacy, 'name', PHARMACIES);
  await M.Department.bulkWrite(
    SHARED_DEPARTMENTS.map((name) => ({
      updateOne: { filter: { practiceId: null, name }, update: { $set: { practiceId: null, name } }, upsert: true },
    })),
  );
  console.log('  catalogs: plans, specialties, ICD-10 codes, medicines, lab tests, pharmacies, shared departments');
}

async function seedDemo() {
  if (await M.Practice.exists({ name: 'City Care Clinic' })) {
    console.log('  demo data already present, skipped');
    return;
  }
  const now = new Date();
  const doctor = await M.User.create({ phone: '9330414463', phoneVerifiedAt: now, name: 'Dr. Arjun Sen' });
  const desk = await M.User.create({ phone: '9876518210', phoneVerifiedAt: now, name: 'Tania Ghosh' });
  const patientUser = await M.User.create({ phone: '9876543210', phoneVerifiedAt: now, name: 'Priya Sharma' });

  const practice = await M.Practice.create({
    name: 'City Care Clinic',
    tagline: 'Diabetes and heart care since 2011',
    registrationNo: 'WB/CE/2011/0412',
    patientCallNumber: '+91 33 4000 1234',
    ownerUserId: doctor._id,
  });
  const week = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  const saltLake = await M.Location.create({
    practiceId: practice._id,
    name: 'City Care Clinic — Salt Lake',
    shortName: 'Salt Lake',
    area: 'Salt Lake',
    city: 'Kolkata',
    pincode: '700064',
    address: 'DD-24, Sector 1, Salt Lake, Kolkata 700064',
    landmark: 'Opposite Tank 9, near City Centre',
    phone: '033 4012 5678',
    geo: { coordinates: [88.4116, 22.5867] },
    paymentMethods: ['upi', 'cash', 'card'],
    facilities: ['Wheelchair access', 'Parking', 'Lab sample collection', 'Pharmacy'],
    weeklyHours: week.map((weekday, i) => ({
      weekday,
      isOpen: weekday !== 'sun',
      opensAt: 540,
      closesAt: i < 5 ? 1200 : 840,
    })),
    letterhead: {
      tagline: 'Diabetes, thyroid and heart care',
      doctorNamePrinted: 'Dr. Arjun Sen, MBBS, MD (Medicine)',
      registrationNo: 'WBMC 64213',
    },
  });
  const endo = await M.Department.create({ practiceId: practice._id, name: 'Endocrinology' });
  await M.Department.create({ practiceId: practice._id, name: 'Diabetology' });
  await M.Member.create([
    { practiceId: practice._id, userId: doctor._id, role: 'doctor', isOwner: true, allLocations: true, departmentId: endo._id, qualifications: 'MBBS, MD (Medicine)', registrationNo: 'WBMC 64213', phone: doctor.phone },
    { practiceId: practice._id, userId: desk._id, role: 'front_desk', locationIds: [saltLake._id], departmentId: endo._id, phone: desk.phone },
  ]);
  await M.Subscription.create({
    practiceId: practice._id, planKey: 'clinic', price: 2499,
    currentPeriodStart: new Date('2026-09-14'), currentPeriodEnd: new Date('2026-10-14'),
  });
  await M.Invite.create({ code: 'CCC-4821', practiceId: practice._id, role: 'front_desk', locationIds: [saltLake._id], createdBy: doctor._id });

  await M.DoctorProfile.create({
    userId: doctor._id,
    displayName: 'Dr. Arjun Sen',
    gender: 'male',
    headline: 'Diabetologist · Internal medicine',
    specialtyKeys: ['diabetes'],
    specialisations: ['Diabetology', 'Internal medicine'],
    conditionsTreated: ['Type 2 diabetes', 'Hypertension', 'Thyroid disorders', 'PCOS', 'Obesity'],
    memberships: ['RSSDI member', 'API member'],
    languagesSpoken: ['English', 'Bengali'],
    degreesSummary: 'MBBS, MD',
    practisingSince: 2010,
    qualifications: [
      { name: 'MBBS', institution: 'Calcutta Medical College', year: 2008, proofStatus: 'verified' },
      { name: 'MD, Internal Medicine', institution: 'IPGMER, Kolkata', year: 2012, proofStatus: 'verified' },
      { name: 'Fellowship in Diabetology', institution: 'RSSDI', year: 2014, proofStatus: 'upload' },
    ],
    registration: { council: 'West Bengal Medical Council', councilShort: 'WBMC', number: '64213', year: 2008, status: 'verified' },
    isVerified: true,
    offersVideo: true,
    presence: 'in_clinic',
    avgReplyMinutes: 15,
  });
  await M.DoctorLocation.create({
    doctorId: doctor._id,
    locationId: saltLake._id,
    practiceId: practice._id,
    services: [
      { name: 'New consultation', details: '15 min · in clinic', durationMin: 15, visitType: 'new', fee: 600 },
      { name: 'Follow-up', details: 'Repeat visit for the same problem', visitType: 'follow_up', fee: 600 },
      { name: 'Report review', details: 'Within 7 days of a visit', visitType: 'report_review', fee: 0, freeWithinDays: 7 },
      { name: 'Video consultation', details: '15 min', mode: 'video', fee: 600 },
    ],
    schedule: {
      week: week.map((weekday) => ({
        weekday,
        sessions: weekday === 'sun' ? [] : [{ startMin: 540, endMin: weekday === 'sat' ? 690 : 780 }],
      })),
      slotLengthMin: 15,
      walkInPlaces: 4,
    },
  });

  const priya = await M.Patient.create({
    userId: patientUser._id,
    name: 'Priya Sharma',
    phone: '9876543210',
    phoneVerifiedAt: now,
    gender: 'female',
    ageYears: 29,
    ageRecordedAt: now,
    heightCm: 158,
    weightKg: 68.5,
    conditions: [{ name: 'Type 2 diabetes', icdCode: 'E11.9' }, { name: 'PCOS', icdCode: 'E28.2' }],
    allergies: [{ allergen: 'Sulfa drugs', drugClass: 'sulfonamide' }],
    area: 'Salt Lake',
    addresses: [{ label: 'Home', line: 'Flat 3B, 12 Purbachal Rd, Salt Lake', area: 'Salt Lake', city: 'Kolkata', isDefault: true }],
    healthScore: { value: 74, weeklyDelta: 3, computedAt: now },
    targets: { sugarFasting: 130, hba1c: 7 },
    createdByPracticeId: practice._id,
  });
  await M.PatientEnrolment.create({ patientId: priya._id, practiceId: practice._id, status: 'linked', linkedBy: doctor._id, linkedAt: now });
  await M.CareTeamAccess.create({ patientId: priya._id, userId: doctor._id, practiceId: practice._id, role: 'doctor', accessLevel: 'full_with_logs', isPrimary: true, since: new Date('2025-06-01') });

  const day = new Date(now);
  day.setHours(0, 0, 0, 0);
  const startAt = new Date(day);
  startAt.setHours(17, 0, 0, 0);
  await M.Appointment.create({
    practiceId: practice._id, locationId: saltLake._id, doctorId: doctor._id, patientId: priya._id,
    date: day, startAt, tokenNo: 4, visitType: 'follow_up', status: 'confirmed', fee: 600, channel: 'app',
    todos: [{ text: 'Upload HbA1c report' }, { text: "Log today's fasting sugar" }, { text: 'Note down questions for Dr. Sen' }],
  });
  await M.Conversation.create({
    type: 'care', practiceId: practice._id, patientId: priya._id,
    participants: [{ userId: patientUser._id, role: 'patient' }, { userId: doctor._id, role: 'doctor' }],
  });
  console.log('  demo: City Care Clinic, Dr. Arjun Sen, Tania Ghosh (front desk), Priya Sharma (patient), 1 appointment');
}

(async () => {
  await connect();
  console.log(`Seeding ${env.mongo.uri} / ${env.mongo.dbName}`);
  await seedCatalogs();
  if (!process.argv.includes('--catalogs-only')) await seedDemo();
  await disconnect();
})().catch(async (err) => {
  console.error(err);
  await disconnect();
  process.exit(1);
});

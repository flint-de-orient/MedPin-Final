// A working day at City Care Clinic, built on the demo from `npm run db:seed`:
// a second doctor and location, the design's patients, today's queue, a month of
// past visits with prescriptions, lab results, alerts, chats, follow-ups,
// referrals, fees, knowledge base, feedback and invoices.
// Runs once (skips if already loaded). Usage: npm run db:seed:clinic
const { connect, disconnect } = require('../src/db');
const env = require('../src/config/env');
const M = require('../src/models');
const T = require('../src/lib/time');
const { issueConsultation } = require('../src/services/clinical');
const { careConversation, postMessage, raiseAlert } = require('../src/services/care');
const { nextToken } = require('../src/services/scheduling');

// Keep the seed quiet: no push/WhatsApp/AI work while loading.
env.ai.provider = 'off';

const today = T.dayStart();
const at = (dayOffset, hhmm) => T.atMinute(T.addDays(today, dayOffset), T.hhmmToMin(hhmm));

async function main() {
  const practice = await M.Practice.findOne({ name: 'City Care Clinic' });
  if (!practice) throw new Error('Run `npm run db:seed` first (it creates City Care Clinic).');
  if (await M.Patient.exists({ phone: '9831120764' })) {
    console.log('  clinic day already loaded, skipped');
    return;
  }
  const sen = await M.User.findById(practice.ownerUserId);
  const desk = await M.User.findOne({ phone: '9876518210' });
  const saltLake = await M.Location.findOne({ practiceId: practice._id, shortName: 'Salt Lake' });
  const endo = await M.Department.findOne({ practiceId: practice._id, name: 'Endocrinology' });
  const cardioDept = await M.Department.findOne({ practiceId: null, name: 'Cardiology' });

  // ── Second location, second doctor, more team ──
  const newTown = await M.Location.create({
    practiceId: practice._id, name: 'City Care — New Town', shortName: 'New Town', area: 'New Town', city: 'Kolkata',
    address: 'AA-II, Action Area 2, New Town, Kolkata 700161', phone: '033 4012 9900', geo: { coordinates: [88.4795, 22.5958] },
    paymentMethods: ['upi', 'cash'], slotMinutes: 20,
    weeklyHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((weekday) => ({ weekday, isOpen: ['tue', 'thu', 'sat'].includes(weekday), opensAt: 1020, closesAt: 1230 })),
  });
  await M.LocationClosure.create([
    { locationId: saltLake._id, startDate: T.addDays(today, 11), endDate: T.addDays(today, 14), reason: 'Durga Puja · closed all day' },
  ]);
  const mitra = await M.User.create({ phone: '9811122233', name: 'Dr. Rina Mitra', phoneVerifiedAt: new Date() });
  const mou = await M.User.create({ phone: '9811122244', name: 'Mou Banerjee', phoneVerifiedAt: new Date() });
  const rohit = await M.User.create({ phone: '9831120486', name: 'Rohit Saha', phoneVerifiedAt: new Date() });
  const diab = await M.Department.findOne({ practiceId: practice._id, name: 'Diabetology' });
  await M.Member.create([
    { practiceId: practice._id, userId: mitra._id, role: 'doctor', departmentId: cardioDept?._id, locationIds: [saltLake._id], phone: mitra.phone, qualifications: 'MBBS, DM (Cardiology)', registrationNo: 'WBMC 58210' },
    { practiceId: practice._id, userId: mou._id, role: 'dietician', departmentId: diab?._id, allLocations: true, phone: mou.phone },
    { practiceId: practice._id, userId: rohit._id, role: 'doctor_assistant', departmentId: endo._id, locationIds: [saltLake._id], phone: rohit.phone },
  ]);
  await M.DoctorProfile.create({
    userId: mitra._id, displayName: 'Dr. Rina Mitra', gender: 'female', headline: 'Cardiologist', specialtyKeys: ['heart'],
    specialisations: ['Cardiology'], languagesSpoken: ['English', 'Bengali', 'Hindi'], degreesSummary: 'MBBS, DM', practisingSince: 2012,
    isVerified: true, offersVideo: true, presence: 'available', avgReplyMinutes: 10,
  });
  const week = (days, start, end) => ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((weekday) => ({ weekday, sessions: days.includes(weekday) ? [{ startMin: start, endMin: end }] : [] }));
  await M.DoctorLocation.create([
    { doctorId: mitra._id, locationId: saltLake._id, practiceId: practice._id, services: [{ name: 'New consultation', visitType: 'new', fee: 800 }, { name: 'Follow-up', visitType: 'follow_up', fee: 600 }], schedule: { week: week(['tue', 'thu'], 1020, 1200), slotLengthMin: 15 } },
    { doctorId: sen._id, locationId: newTown._id, practiceId: practice._id, services: [{ name: 'New consultation', visitType: 'new', fee: 500 }, { name: 'Follow-up', visitType: 'follow_up', fee: 500 }, { name: 'Report review', visitType: 'report_review', fee: 0, freeWithinDays: 7 }], schedule: { week: week(['tue', 'wed', 'thu', 'sat'], 1080, 1230), slotLengthMin: 20, walkInPlaces: 2 } },
  ]);
  await M.DoctorProfile.updateOne({ userId: sen._id }, { presence: 'in_clinic' });

  // ── Patients from the design ──
  const people = [
    ['Rahul Das', '9831120764', 'male', 45, ['Hypertension'], [], 'high'],
    ['Aisha Khan', '9831120765', 'female', 34, ['Type 2 diabetes'], [], 'moderate'],
    ['Moumita Roy', '9831120766', 'female', 52, ['Coronary artery disease', 'Dyslipidaemia'], ['Penicillin'], 'high'],
    ['Sujit Mondal', '9831120767', 'male', 61, ['Chronic kidney disease', 'Hypertension'], [], 'critical'],
    ['Farhana Islam', '9831120768', 'female', 38, ['Hypothyroidism'], [], 'low'],
    ['Debasish Bose', '9831120769', 'male', 57, ['Type 2 diabetes', 'Hypertension'], [], 'moderate'],
    ['Amit Pal', '9831120770', 'male', 42, ['Type 2 diabetes'], [], 'low'],
  ];
  const P = {};
  for (const [name, phone, gender, ageYears, conditions, allergies, riskLevel] of people) {
    const p = await M.Patient.create({
      name, phone, gender, ageYears, ageRecordedAt: new Date(), riskLevel, area: 'Salt Lake',
      conditions: conditions.map((c) => ({ name: c })), allergies: allergies.map((a) => ({ allergen: a })),
      heightCm: gender === 'male' ? 170 : 158, weightKg: gender === 'male' ? 76 : 64, createdByPracticeId: practice._id,
    });
    await M.PatientEnrolment.create({ patientId: p._id, practiceId: practice._id, status: 'linked', linkedBy: desk._id, linkedAt: T.addDays(today, -120) });
    await M.CareTeamAccess.create({ patientId: p._id, userId: name === 'Moumita Roy' ? mitra._id : sen._id, practiceId: practice._id, role: 'doctor', isPrimary: true, accessLevel: 'full_record', since: T.addDays(today, -200) });
    P[name] = p;
  }
  const priya = await M.Patient.findOne({ phone: '9876543210' });
  P['Priya Sharma'] = priya;
  await M.CareTeamAccess.create({ patientId: priya._id, userId: mou._id, practiceId: practice._id, role: 'dietician', accessLevel: 'full_with_logs', since: T.addDays(today, -90) });
  await M.CareTeamAccess.create({ patientId: priya._id, userId: mitra._id, practiceId: practice._id, role: 'doctor', accessLevel: 'full_record', since: T.addDays(today, -60) });

  // ── Lab results ──
  const lab = (p, testName, daysAgo, values, labName = 'SRL Diagnostics') => M.LabResult.create({
    patientId: p._id, practiceId: practice._id, testName, labName, collectedAt: T.addDays(today, -daysAgo), values,
    abnormalCount: values.filter((v) => v.flag !== 'normal').length, hasCritical: values.some((v) => v.flag === 'critical'),
  });
  await lab(priya, 'Diabetes panel', 83, [
    { analyte: 'HbA1c', value: 7.2, unit: '%', refText: 'below 5.7', refHigh: 5.7, flag: 'high' },
    { analyte: 'Fasting glucose', value: 138, unit: 'mg/dL', refText: '70–99', refLow: 70, refHigh: 99, flag: 'high' },
  ]);
  await lab(priya, 'Lipid profile', 9, [
    { analyte: 'LDL cholesterol', value: 162, unit: 'mg/dL', refText: 'below 100', refHigh: 100, flag: 'high' },
    { analyte: 'Triglycerides', value: 210, unit: 'mg/dL', refText: 'below 150', refHigh: 150, flag: 'high' },
    { analyte: 'HDL cholesterol', value: 46, unit: 'mg/dL', refText: 'above 40', refLow: 40, flag: 'normal' },
  ]);
  await lab(priya, 'Vitamin D', 83, [{ analyte: 'Vitamin D', value: 14, unit: 'ng/mL', refText: '30–100', refLow: 30, refHigh: 100, flag: 'low' }]);
  await lab(P['Sujit Mondal'], 'Renal function test', 1, [
    { analyte: 'Potassium', value: 6.1, unit: 'mmol/L', refText: '3.5–5.1', refLow: 3.5, refHigh: 5.1, flag: 'critical' },
    { analyte: 'Serum creatinine', value: 2.4, unit: 'mg/dL', refText: '0.7–1.2', refLow: 0.7, refHigh: 1.2, flag: 'high' },
  ], 'City Care lab');
  await lab(P['Farhana Islam'], 'Thyroid profile', 2, [{ analyte: 'TSH', value: 9.8, unit: 'mIU/L', refText: '0.4–4.0', refLow: 0.4, refHigh: 4.0, flag: 'high' }]);
  await lab(P['Aisha Khan'], 'Complete blood count', 5, [{ analyte: 'Haemoglobin', value: 9.1, unit: 'g/dL', refText: '12–15.5', refLow: 12, refHigh: 15.5, flag: 'low' }]);
  await lab(P['Moumita Roy'], 'ECG', 3, [], 'City Care lab').then((r) => M.LabResult.updateOne({ _id: r._id }, { ecgInterpretation: 'borderline', ecgNote: 'Sinus rhythm, borderline ST changes · 12-lead' }));

  // ── Vitals and medicines for Priya ──
  for (let d = 6; d >= 0; d -= 1) {
    await M.Vitals.create({ patientId: priya._id, recordedAt: at(-d, '07:45'), source: 'home', recordedByRole: 'patient', bloodSugar: [146, 139, 151, 142, 137, 148, 142][6 - d], sugarType: 'fasting', bpSystolic: [126, 130, 124, 128, 131, 127, 128][6 - d], bpDiastolic: [80, 84, 79, 82, 85, 81, 82][6 - d] });
  }

  // ── A month of past visits (with real prescriptions) ──
  const tokenFor = (locId, day) => nextToken(locId, day);
  async function pastVisit(p, daysAgo, time, { doctor = sen, loc = saltLake, type = 'follow_up', fee = 600, paid = 'upi', complaint, dx, meds = [], tests = [], followUpDays, mode = 'in_clinic' }) {
    const startAt = at(-daysAgo, time);
    const appt = await M.Appointment.create({
      practiceId: practice._id, locationId: loc._id, doctorId: doctor._id, patientId: p._id, date: T.dayStart(startAt), startAt,
      tokenNo: await tokenFor(loc._id, startAt), visitType: type, mode, status: 'completed', channel: 'desk', fee, feeStatus: fee ? (paid ? 'paid' : 'pending') : 'free',
      arrivedAt: T.addMinutes(startAt, -12), consultStartedAt: startAt, completedAt: T.addMinutes(startAt, 9 + (daysAgo % 5)),
    });
    if (fee) await M.Payment.create({ practiceId: practice._id, locationId: loc._id, patientId: p._id, appointmentId: appt._id, amount: fee, status: paid ? 'paid' : 'pending', method: paid || undefined, paidAt: paid ? appt.completedAt : undefined, createdAt: startAt });
    const vitals = await M.Vitals.create({ patientId: p._id, practiceId: practice._id, appointmentId: appt._id, recordedAt: T.addMinutes(startAt, -8), recordedBy: desk._id, recordedByRole: 'front_desk', source: 'clinic', bpSystolic: 120 + (daysAgo % 25), bpDiastolic: 78 + (daysAgo % 12), pulse: 72 + (daysAgo % 15), spo2: 98, weightKg: p.weightKg });
    const consult = await M.Consultation.create({
      practiceId: practice._id, locationId: loc._id, doctorId: doctor._id, patientId: p._id, appointmentId: appt._id, vitalsId: vitals._id,
      startedAt: startAt, chiefComplaint: complaint, diagnoses: dx.map((name) => ({ name })), medications: meds,
      labOrders: tests.map((testName) => ({ testName })), advice: { items: [{ text: 'Walk 30 minutes, 5 days a week', category: 'activity' }], freeText: 'Come back with fasting sugar.' },
      followUp: followUpDays ? { enabled: true, date: T.addDays(T.dayStart(startAt), followUpDays) } : { enabled: false },
    });
    const rx = await issueConsultation(consult, doctor);
    await M.Prescription.updateOne({ _id: rx._id }, { issuedAt: startAt });
    await M.Consultation.updateOne({ _id: consult._id }, { completedAt: appt.completedAt, durationSec: 540 });
    await M.MedicationCourse.updateMany({ prescriptionId: rx._id }, { startDate: T.dayStart(startAt) });
    await M.FollowUp.updateMany({ consultationId: consult._id }, { advisedOn: startAt });
    return { appt, consult, rx };
  }
  const metformin = { name: 'Metformin', strength: '500 mg', dose: { morning: 1, night: 1 }, foodRelation: 'after_food', duration: { value: 3, unit: 'months' } };
  const telmi = { name: 'Telmisartan', strength: '40 mg', dose: { morning: 1 }, foodRelation: 'after_food', duration: { value: 1, unit: 'months' } };
  const levo = { name: 'Levothyroxine', strength: '50 mcg', dose: { morning: 1 }, foodRelation: 'empty_stomach', duration: { value: 3, unit: 'months' } };
  const atorva = { name: 'Atorvastatin', strength: '10 mg', dose: { night: 1 }, foodRelation: 'after_food', duration: { value: 3, unit: 'months' } };
  const glim = { name: 'Glimepiride', strength: '1 mg', dose: { morning: 1 }, foodRelation: 'before_food', duration: { value: 1, unit: 'months' } };

  await pastVisit(priya, 10, '09:04', { type: 'follow_up', complaint: 'Tiredness and excess thirst, 2 weeks', dx: ['Type 2 diabetes mellitus', 'Polycystic ovary syndrome'], meds: [metformin, glim], tests: ['HbA1c', 'Lipid profile'], followUpDays: 14 });
  await pastVisit(P['Rahul Das'], 24, '09:30', { complaint: 'Headaches in the morning', dx: ['Essential hypertension'], meds: [telmi], followUpDays: 14 });
  await pastVisit(P['Debasish Bose'], 18, '10:00', { complaint: 'Sugar high on home readings', dx: ['Type 2 diabetes mellitus', 'Essential hypertension'], meds: [metformin, telmi], tests: ['HbA1c'], followUpDays: 21, paid: null });
  await pastVisit(P['Farhana Islam'], 15, '11:00', { type: 'new', fee: 600, complaint: 'Weight gain and tiredness', dx: ['Hypothyroidism'], meds: [levo], tests: ['TSH'], followUpDays: 28, paid: 'cash' });
  await pastVisit(P['Moumita Roy'], 12, '17:15', { doctor: mitra, fee: 800, type: 'new', complaint: 'Chest discomfort on exertion', dx: ['Coronary artery disease', 'Dyslipidaemia'], meds: [atorva], tests: ['ECG', 'Lipid profile'], followUpDays: 20, paid: 'card' });
  await pastVisit(P['Sujit Mondal'], 30, '09:15', { complaint: 'Swelling in feet', dx: ['Chronic kidney disease', 'Essential hypertension'], meds: [telmi], tests: ['Kidney function'], followUpDays: 21 });
  await pastVisit(P['Aisha Khan'], 6, '10:30', { type: 'new', complaint: 'Fatigue, breathlessness on stairs', dx: ['Iron deficiency anaemia', 'Type 2 diabetes mellitus'], meds: [metformin], tests: ['CBC'], followUpDays: 10, paid: null });
  await pastVisit(P['Amit Pal'], 3, '09:45', { complaint: 'Routine diabetes review', dx: ['Type 2 diabetes mellitus'], meds: [metformin], followUpDays: 30, mode: 'video', loc: newTown, fee: 500 });
  await pastVisit(P['Rahul Das'], 2, '18:20', { type: 'report_review', fee: 0, complaint: 'Review home BP readings', dx: ['Essential hypertension'], meds: [telmi], loc: newTown });
  // A missed and a cancelled booking for the history.
  for (const [p, daysAgo, status] of [[P['Debasish Bose'], 4, 'missed'], [P['Amit Pal'], 8, 'cancelled']]) {
    const startAt = at(-daysAgo, '11:30');
    await M.Appointment.create({ practiceId: practice._id, locationId: saltLake._id, doctorId: sen._id, patientId: p._id, date: T.dayStart(startAt), startAt, tokenNo: await tokenFor(saltLake._id, startAt), visitType: 'follow_up', status, cancelledBy: status === 'cancelled' ? 'patient' : undefined, cancelledAt: status === 'cancelled' ? T.addDays(startAt, -1) : undefined, missedAt: status === 'missed' ? startAt : undefined, fee: 600, feeStatus: status === 'cancelled' ? 'waived' : 'pending' });
  }

  // ── Today's queue at Salt Lake (Dr. Sen) ──
  const queue = [
    ['08:30', 'Amit Pal', 'completed', 'follow_up'],
    ['09:00', 'Aisha Khan', 'completed', 'follow_up'],
    ['09:30', 'Rahul Das', 'in_consultation', 'follow_up'],
    ['10:00', 'Debasish Bose', 'waiting', 'follow_up'],
    ['10:30', 'Farhana Islam', 'waiting', 'report_review'],
    ['11:00', 'Sujit Mondal', 'booked', 'follow_up'],
    ['11:30', 'Moumita Roy', 'confirmed', 'new'],
  ];
  for (const [time, name, status, visitType] of queue) {
    const startAt = at(0, time);
    const done = status === 'completed';
    const appt = await M.Appointment.create({
      practiceId: practice._id, locationId: saltLake._id, doctorId: sen._id, patientId: P[name]._id, date: today, startAt, endAt: T.addMinutes(startAt, 15),
      tokenNo: await tokenFor(saltLake._id, today), visitType, status, channel: 'desk', fee: visitType === 'report_review' ? 0 : 600,
      feeStatus: visitType === 'report_review' ? 'free' : done ? 'paid' : 'pending',
      arrivedAt: ['waiting', 'in_consultation', 'completed'].includes(status) ? T.addMinutes(startAt, -15) : undefined,
      consultStartedAt: ['in_consultation', 'completed'].includes(status) ? T.addMinutes(startAt, 2) : undefined,
      completedAt: done ? T.addMinutes(startAt, 11) : undefined,
    });
    if (appt.fee) await M.Payment.create({ practiceId: practice._id, locationId: saltLake._id, patientId: appt.patientId, appointmentId: appt._id, amount: appt.fee, status: done ? 'paid' : 'pending', method: done ? 'upi' : undefined, paidAt: done ? appt.completedAt : undefined });
    if (['waiting', 'in_consultation'].includes(status) && name !== 'Farhana Islam') {
      await M.Vitals.create({ patientId: P[name]._id, practiceId: practice._id, appointmentId: appt._id, recordedAt: T.addMinutes(startAt, -10), recordedBy: desk._id, recordedByRole: 'front_desk', source: 'clinic', bpSystolic: 148, bpDiastolic: 94, pulse: 88, spo2: 97, weightKg: P[name].weightKg });
    }
  }

  // ── Requests waiting for a time ──
  await M.AppointmentRequest.create([
    { practiceId: practice._id, patientId: P['Debasish Bose']._id, doctorId: sen._id, visitType: 'follow_up', reason: 'Follow-up for sugar', preferredTime: 'Any morning this week', channel: 'app', createdAt: at(0, '08:20') },
    { practiceId: practice._id, patientId: P['Farhana Islam']._id, doctorId: sen._id, visitType: 'new', reason: 'New consultation: fever and body ache for 3 days', preferredTime: 'Thu or Fri, after 5 PM', channel: 'whatsapp', createdAt: at(-1, '18:40') },
  ]);

  // ── Alerts ──
  const urgentConvo = await careConversation(priya._id, practice._id);
  const msg1 = await postMessage(urgentConvo, { sender: null, senderType: 'patient', text: 'Chest tightness, hard to breathe.', isUrgent: true });
  await raiseAlert({ practiceId: practice._id, patientId: priya._id, doctorId: sen._id, severity: 'emergency', kind: 'urgent_chat', detail: 'Chest tightness, hard to breathe.', sourceModel: 'Message', sourceId: msg1._id, conversationId: urgentConvo._id });
  await raiseAlert({ practiceId: practice._id, patientId: P['Rahul Das']._id, severity: 'urgent', kind: 'reading', detail: 'Home BP reading 172/104 mmHg, above his alert limit.' });
  await raiseAlert({ practiceId: practice._id, patientId: P['Sujit Mondal']._id, severity: 'urgent', kind: 'lab', detail: 'Potassium 6.1 mmol/L · ref 3.5–5.1 (critical).' });
  const watch = await raiseAlert({ practiceId: practice._id, patientId: P['Farhana Islam']._id, severity: 'watch', kind: 'lab', detail: 'TSH 9.8 mIU/L, up from 6.2 in July.' });
  watch.status = 'acknowledged';
  watch.acknowledged = { by: sen._id, at: at(0, '09:20') };
  watch.note = 'Called patient, advised to come in';
  watch.noteBy = sen._id;
  watch.noteAt = at(0, '09:20');
  await watch.save();

  // ── Chats (patient care threads, AI replies, a flagged answer) ──
  const chat = async (name, lines) => {
    const c = await careConversation(P[name]._id, practice._id);
    let last;
    for (const [who, text, ai] of lines) {
      last = await postMessage(c, { sender: who === 'doctor' ? sen : who === 'staff' ? desk : null, senderType: who, text, ...(ai ? { ai } : {}) });
    }
    return { c, last };
  };
  const r1 = await chat('Sujit Mondal', [
    ['patient', 'My feet are more swollen today. Should I take an extra tablet?'],
    ['ai', 'Please do not change your medicine dose. I have asked Dr. Sen to look at this today.', { flagged: true, urgency: 'medium', escalated: true, citations: [{ label: 'Clinic knowledge base: "Swelling and kidney disease"' }], latencyMs: 1400 }],
  ]);
  await M.ChatReview.create({ practiceId: practice._id, patientId: P['Sujit Mondal']._id, conversationId: r1.c._id, messageId: r1.last._id, reason: 'dosage_question', title: 'Dosage question answered by AI', excerpt: r1.last.text, urgency: 'medium' });
  const r2 = await chat('Rahul Das', [
    ['patient', 'BP is 172/104 and I have a headache.'],
    ['ai', 'That reading is high. If the headache is severe or you feel unwell, call 108. I have alerted your doctor.', { flagged: true, urgency: 'high', escalated: true, latencyMs: 1200 }],
  ]);
  await M.ChatReview.create({ practiceId: practice._id, patientId: P['Rahul Das']._id, conversationId: r2.c._id, messageId: r2.last._id, reason: 'symptom_question', title: 'Symptom question: BP with headache', excerpt: r2.last.text, urgency: 'high' });
  await chat('Farhana Islam', [['patient', 'Shared my thyroid report from today.'], ['staff', 'Thank you, Farhana. Dr. Sen will review it before your visit.']]);
  await chat('Aisha Khan', [['patient', 'Can I take the iron tablet with tea?'], ['doctor', 'Please take it with water, at least an hour away from tea.']]);
  await postMessage(urgentConvo, { sender: null, senderType: 'patient', text: 'Should I take the tablet before or after food?' });

  // ── Referrals ──
  await M.Referral.create([
    { practiceId: practice._id, patientId: P['Sujit Mondal']._id, doctorId: sen._id, direction: 'sent', counterpartName: 'Dr. Sourav Lahiri', specialty: 'Nephrology', reason: 'Rising creatinine', referredAt: T.addDays(today, -20), status: 'seen', seenAt: T.addDays(today, -12) },
    { practiceId: practice._id, patientId: P['Debasish Bose']._id, doctorId: sen._id, direction: 'sent', counterpartName: 'Eye clinic', specialty: 'Ophthalmology', reason: 'Diabetic eye check', referredAt: T.addDays(today, -9), status: 'awaiting' },
    { practiceId: practice._id, patientId: P['Moumita Roy']._id, doctorId: mitra._id, direction: 'received', counterpartName: 'Dr. Nandita Gupta', specialty: 'Gynaecology', reason: 'Palpitations', referredAt: T.addDays(today, -14), status: 'seen', seenAt: T.addDays(today, -12) },
  ]);

  // ── Knowledge base and feedback ──
  const kb = [
    ['Metformin timing', 'Take metformin with your meals or right after them. This lowers stomach upset. If you miss a dose, skip it — never take two together.', 'approved', 'medicines', ['metformin', 'diabetes', 'dosage timing'], 'ADA Standards of Care 2026, Section 9'],
    ['Home BP: when to call us', 'Check BP sitting, after 5 minutes of rest. Call the clinic if it is above 160/100 twice, or call 108 if you have chest pain, weakness or confusion.', 'approved', 'hypertension', ['blood pressure', 'home readings'], 'ISH 2020 guideline'],
    ['Iron tablets and tea', 'Take iron tablets with water or orange juice, at least one hour before or two hours after tea or coffee.', 'approved', 'medicines', ['iron', 'anaemia'], ''],
    ['When to repeat HbA1c', 'HbA1c shows the average sugar of 3 months. We repeat it every 3 months until it is in target, then every 6 months.', 'approved', 'diabetes', ['hba1c', 'diabetes'], ''],
    ['Fasting days with diabetes', 'If you fast, check sugar more often and ask your doctor before changing medicine timing.', 'pending', 'diabetes', ['fasting', 'diabetes'], ''],
    ['Monsoon fever: dengue checks', 'Old guidance for fever during monsoon.', 'retired', 'infections', ['fever', 'dengue'], ''],
  ];
  for (const [title, content, status, category, tags, sourceCitation] of kb) {
    await M.KnowledgeEntry.create({ practiceId: practice._id, title, summary: content.split('. ')[0], content, status, category, tags, sourceCitation, createdBy: sen._id, updatedBy: sen._id, ...(status === 'approved' ? { approved: { by: sen._id, at: T.addDays(today, -30) } } : {}), ...(status === 'retired' ? { retiredAt: T.addDays(today, -27), retiredNote: 'Superseded by the 2026 clinic fever protocol.' } : {}) });
  }
  await M.KnowledgeEntry.create({ practiceId: null, title: 'Thyroid tablet on an empty stomach', summary: 'Take levothyroxine 30–60 minutes before breakfast.', content: 'Take levothyroxine with water, 30–60 minutes before breakfast, and keep 4 hours away from calcium or iron.', status: 'approved', category: 'thyroid', tags: ['levothyroxine', 'thyroid', 'dosage timing'], sourceCitation: 'American Thyroid Association, Hypothyroidism guidelines', authorLabel: 'MedPin clinical team' });
  await M.Feedback.create([
    { practiceId: practice._id, patientId: P['Moumita Roy']._id, doctorId: mitra._id, rating: 5, category: 'care', comment: 'Dr. Mitra explained everything patiently.', readBy: [{ userId: sen._id, at: T.addDays(today, -1) }, { userId: desk._id, at: T.addDays(today, -1) }], reply: { text: 'Thank you, Moumita. See you at your follow-up.', by: desk._id, at: T.addDays(today, -1) }, createdAt: T.addDays(today, -1) },
    { practiceId: practice._id, patientId: P['Debasish Bose']._id, rating: 2, category: 'care', comment: 'Waited over an hour past my booked time.', createdAt: T.addDays(today, -1) },
    { practiceId: practice._id, patientId: P['Aisha Khan']._id, rating: 4, category: 'app', comment: 'Reminders are helpful. Uploading reports could be easier.', createdAt: T.addDays(today, -2) },
    { practiceId: practice._id, patientId: P['Rahul Das']._id, doctorId: sen._id, rating: 5, category: 'care', comment: 'Quick and clear.', createdAt: T.addDays(today, -3) },
  ]);

  // ── Billing history ──
  const sub = await M.Subscription.findOne({ practiceId: practice._id });
  for (let i = 1; i <= 6; i += 1) {
    const d = new Date(sub.currentPeriodStart);
    d.setMonth(d.getMonth() - (i - 1));
    await M.Invoice.create({ practiceId: practice._id, number: `MP-${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}-0412`, issuedAt: d, description: 'Clinic plan · monthly', amount: 2499, status: 'paid', paidAt: d });
  }
  await M.UsageCounter.updateOne({ practiceId: practice._id, periodStart: sub.currentPeriodStart }, { aiChats: 1860 }, { upsert: true });
  await M.Practice.updateOne({ _id: practice._id }, { patientCallNumber: '+91 33 4000 1234' });

  console.log(`  clinic day: ${Object.keys(P).length} patients, today's queue of ${queue.length}, 9 past visits, alerts, chats, referrals, knowledge base, feedback, invoices`);
}

(async () => {
  await connect();
  console.log(`Loading a clinic day into ${env.mongo.dbName}`);
  await main();
  await disconnect();
})().catch(async (err) => {
  console.error(err);
  await disconnect();
  process.exit(1);
});

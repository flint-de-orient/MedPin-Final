// End-to-end schema test against a throwaway database (<db>_schema_test).
// Walks the main UI flows, checks validation and unique rules, then drops the DB.
// Usage: npm run db:test
const assert = require('assert/strict');
const env = require('../src/config/env');

env.mongo.dbName = `${env.mongo.dbName}_schema_test`;
const { connect, disconnect, mongoose } = require('../src/db');
const M = require('../src/models');

let passed = 0;
const step = async (name, fn) => {
  await fn();
  passed += 1;
  console.log(`  ✓ ${name}`);
};
const rejects = async (promise, pattern) => {
  await assert.rejects(promise, (err) => pattern.test(err.message));
};
const today = new Date('2026-09-29T00:00:00+05:30');
const at = (hhmm) => new Date(`2026-09-29T${hhmm}:00+05:30`);

(async () => {
  const conn = await connect();
  await conn.dropDatabase();
  for (const Model of Object.values(mongoose.models)) await Model.syncIndexes();
  console.log(`Testing schema in ${env.mongo.dbName}`);

  const ctx = {};

  await step('auth: user, OTP and invite', async () => {
    ctx.doctor = await M.User.create({ phone: '9830041275', name: 'Dr. Arjun Sen', language: 'en' });
    ctx.desk = await M.User.create({ phone: '9876518210', name: 'Tania Ghosh' });
    await rejects(M.User.create({ phone: '9830041275' }), /duplicate key/);
    await rejects(M.User.create({ phone: '12345' }), /10-digit/);
    await M.OtpRequest.create({
      phone: '9830041275', purpose: 'login', codeHash: 'x', expiresAt: new Date(Date.now() + 300e3),
    });
  });

  await step('practice, location, hours, departments, team', async () => {
    ctx.practice = await M.Practice.create({ name: 'City Care Clinic', ownerUserId: ctx.doctor._id });
    ctx.location = await M.Location.create({
      practiceId: ctx.practice._id,
      name: 'City Care Clinic — Salt Lake',
      shortName: 'Salt Lake',
      area: 'Salt Lake',
      geo: { coordinates: [88.4116, 22.5867] },
      paymentMethods: ['upi', 'cash', 'card'],
      weeklyHours: [{ weekday: 'mon', opensAt: 540, closesAt: 1200 }],
    });
    const dept = await M.Department.create({ practiceId: ctx.practice._id, name: 'Endocrinology' });
    await rejects(M.Department.create({ practiceId: ctx.practice._id, name: 'Endocrinology' }), /duplicate key/);
    await M.Member.create({
      practiceId: ctx.practice._id, userId: ctx.doctor._id, role: 'doctor', isOwner: true, departmentId: dept._id,
      allLocations: true,
    });
    await M.Member.create({
      practiceId: ctx.practice._id, userId: ctx.desk._id, role: 'front_desk', locationIds: [ctx.location._id],
    });
    await rejects(M.Member.create({ practiceId: ctx.practice._id, userId: ctx.desk._id, role: 'chef' }), /enum/);
    await M.Invite.create({
      code: 'ccc-4821', practiceId: ctx.practice._id, role: 'front_desk', createdBy: ctx.doctor._id,
    });
    await rejects(
      M.Invite.create({ code: 'BAD', practiceId: ctx.practice._id, role: 'doctor', createdBy: ctx.doctor._id }),
      /code/,
    );
  });

  await step('doctor profile, services, schedule, leave', async () => {
    await M.DoctorProfile.create({
      userId: ctx.doctor._id,
      displayName: 'Dr. Arjun Sen',
      specialtyKeys: ['diabetes'],
      languagesSpoken: ['English', 'Bengali'],
      qualifications: [{ name: 'MBBS', institution: 'Calcutta Medical College', year: 2008, proofStatus: 'verified' }],
      registration: { council: 'West Bengal Medical Council', councilShort: 'WBMC', number: '64213', year: 2008 },
    });
    await M.DoctorLocation.create({
      doctorId: ctx.doctor._id,
      locationId: ctx.location._id,
      practiceId: ctx.practice._id,
      services: [{ name: 'New consultation', fee: 600 }, { name: 'Report review', fee: 0, freeWithinDays: 7 }],
      schedule: { week: [{ weekday: 'mon', sessions: [{ startMin: 540, endMin: 780 }] }], walkInPlaces: 4 },
    });
    await rejects(
      M.DoctorLocation.create({
        doctorId: ctx.doctor._id, locationId: ctx.location._id, practiceId: ctx.practice._id,
        schedule: { slotLengthMin: 2 },
      }),
      /slotLengthMin|duplicate/,
    );
    await M.DoctorLeave.create({
      doctorId: ctx.doctor._id, reason: 'Durga Puja', startDate: new Date('2026-10-19'), endDate: new Date('2026-10-23'),
    });
  });

  await step('patient, consent code, enrolment, care-team access', async () => {
    ctx.patient = await M.Patient.create({
      name: 'Priya Sharma', phone: '9876543210', gender: 'female', ageYears: 29, heightCm: 158, weightKg: 68.5,
      conditions: [{ name: 'Type 2 diabetes', icdCode: 'E11.9' }, { name: 'PCOS', icdCode: 'E28.2' }],
      allergies: [{ allergen: 'Sulfa drugs', drugClass: 'sulfonamide' }],
    });
    // Two patients without an app account must not collide on userId.
    await M.Patient.create({ name: 'Rahul Das', phone: '9831120764', gender: 'male' });
    await rejects(M.Patient.create({ name: 'Dup', phone: '9876543210', gender: 'male' }), /duplicate key/);
    await rejects(
      M.Patient.create({
        name: 'X', phone: '9000000001', gender: 'male',
        trackedMeasures: ['blood_sugar', 'blood_pressure', 'hba1c', 'weight', 'spo2'],
      }),
      /up to 4/,
    );
    await M.ConsentCode.create({ patientId: ctx.patient._id, codeHash: 'h', expiresAt: new Date(Date.now() + 60e3) });
    await M.PatientEnrolment.create({ patientId: ctx.patient._id, practiceId: ctx.practice._id, status: 'linked' });
    await M.CareTeamAccess.create({
      patientId: ctx.patient._id, userId: ctx.doctor._id, practiceId: ctx.practice._id, accessLevel: 'full_with_logs',
    });
  });

  await step('request → appointment → check-in → consultation', async () => {
    const req = await M.AppointmentRequest.create({
      practiceId: ctx.practice._id, patientId: ctx.patient._id, doctorId: ctx.doctor._id, channel: 'whatsapp',
    });
    ctx.appt = await M.Appointment.create({
      practiceId: ctx.practice._id, locationId: ctx.location._id, doctorId: ctx.doctor._id,
      patientId: ctx.patient._id, requestId: req._id, date: today, startAt: at('11:00'), tokenNo: 4, fee: 600,
    });
    await rejects(
      M.Appointment.create({
        practiceId: ctx.practice._id, locationId: ctx.location._id, doctorId: ctx.doctor._id,
        patientId: ctx.patient._id, date: today, startAt: at('11:15'), tokenNo: 4,
      }),
      /duplicate key/,
    );
    req.status = 'scheduled';
    req.appointmentId = ctx.appt._id;
    await req.save();
    Object.assign(ctx.appt, { status: 'waiting', arrivedAt: at('10:52'), checkedInBy: ctx.desk._id });
    await ctx.appt.save();
    await rejects(M.Appointment.updateOne({ _id: ctx.appt._id }, { status: 'teleported' }, { runValidators: true }), /enum/);
  });

  await step('vitals, diagnosis, prescription with Rx number', async () => {
    const vitals = await M.Vitals.create({
      patientId: ctx.patient._id, appointmentId: ctx.appt._id, recordedBy: ctx.desk._id, recordedByRole: 'front_desk',
      bpSystolic: 128, bpDiastolic: 82, pulse: 78, spo2: 98, weightKg: 68.5, heightCm: 158, bloodSugar: 142,
      sugarType: 'fasting', bmi: 27.4,
    });
    await rejects(M.Vitals.create({ patientId: ctx.patient._id, spo2: 140 }), /spo2/);
    const consult = await M.Consultation.create({
      practiceId: ctx.practice._id, locationId: ctx.location._id, doctorId: ctx.doctor._id,
      patientId: ctx.patient._id, appointmentId: ctx.appt._id, vitalsId: vitals._id,
      chiefComplaint: 'Tiredness and excess thirst, 2 weeks',
      diagnoses: [{ name: 'Type 2 diabetes mellitus', icdCode: 'E11.9' }],
      labOrders: [{ testName: 'HbA1c', panel: 'Diabetes panel', source: 'panel' }],
      advice: { items: [{ text: 'Walk 30 minutes, 5 days a week', category: 'activity' }] },
      followUp: { enabled: true, preset: '2_weeks', date: new Date('2026-10-13') },
    });
    const rxNumber = await M.Counter.next(`rx:${ctx.practice._id}`);
    assert.equal(rxNumber, 1);
    ctx.rx = await M.Prescription.create({
      practiceId: ctx.practice._id, doctorId: ctx.doctor._id, patientId: ctx.patient._id,
      consultationId: consult._id, rxNumber,
      items: [{
        name: 'Metformin', strength: '500 mg', dose: { morning: 1, night: 1 }, foodRelation: 'after_food',
        duration: { value: 3, unit: 'months' }, quantity: 180,
      }],
      tests: ['HbA1c'],
    });
    await rejects(
      M.Prescription.create({ practiceId: ctx.practice._id, patientId: ctx.patient._id, rxNumber }),
      /duplicate key/,
    );
    consult.status = 'issued';
    consult.prescriptionId = ctx.rx._id;
    await consult.save();
    await M.FollowUp.create({
      practiceId: ctx.practice._id, patientId: ctx.patient._id, doctorId: ctx.doctor._id,
      consultationId: consult._id, dueDate: new Date('2026-10-13'),
    });
    await M.Payment.create({
      practiceId: ctx.practice._id, patientId: ctx.patient._id, appointmentId: ctx.appt._id,
      amount: 600, method: 'upi', status: 'paid', paidAt: new Date(),
    });
  });

  await step('medicine course, dose logs (unique per slot)', async () => {
    const course = await M.MedicationCourse.create({
      patientId: ctx.patient._id, prescriptionId: ctx.rx._id, rxItemId: ctx.rx.items[0]._id,
      name: 'Metformin', strength: '500 mg', dose: { morning: 1, night: 1 }, startDate: today, stockUnits: 6,
    });
    await M.DoseLog.create({ courseId: course._id, patientId: ctx.patient._id, scheduledAt: at('07:30'), slot: 'morning', status: 'taken', takenAt: at('07:32') });
    await rejects(
      M.DoseLog.create({ courseId: course._id, patientId: ctx.patient._id, scheduledAt: at('07:30'), slot: 'morning' }),
      /duplicate key/,
    );
    await M.Cart.create({ patientId: ctx.patient._id, items: [{ courseId: course._id, name: 'Metformin 500 mg', strips: 2 }] });
    await rejects(M.Cart.create({ patientId: ctx.patient._id, items: [{ name: 'X', strips: 120 }] }), /strips|duplicate/);
  });

  await step('records, lab results, health log, alert', async () => {
    const rec = await M.MedicalRecord.create({
      patientId: ctx.patient._id, kind: 'test_result', title: 'Lipid profile', recordDate: new Date('2026-09-30'),
      origin: 'shared_by_patient', sourceName: 'Suraksha Diagnostics', uploadSource: 'pdf',
      files: [{ key: 'records/abc.pdf', pages: 6 }], pageFrom: 1, pageTo: 2,
      sharedWith: [{ userId: ctx.doctor._id }], flagLabel: '2 high', flagTone: 'high',
    });
    await M.LabResult.create({
      patientId: ctx.patient._id, recordId: rec._id, testName: 'Lipid profile', collectedAt: new Date('2026-09-30'),
      values: [{ analyte: 'LDL cholesterol', value: 158, unit: 'mg/dL', refText: 'below 100', refHigh: 100, flag: 'high' }],
      abnormalCount: 1,
    });
    await M.HealthLog.create({ patientId: ctx.patient._id, type: 'meal', mealType: 'breakfast', note: '2 rotis, dal, salad', sharedWith: [ctx.doctor._id] });
    await rejects(M.HealthLog.create({ patientId: ctx.patient._id, type: 'meal', mealType: 'brunch' }), /enum/);
    const alert = await M.Alert.create({
      practiceId: ctx.practice._id, patientId: ctx.patient._id, severity: 'emergency', kind: 'urgent_chat',
      detail: 'Chest tightness, hard to breathe.',
    });
    alert.status = 'acknowledged';
    alert.acknowledged = { by: ctx.doctor._id, at: new Date() };
    await alert.save();
  });

  await step('chat, AI flag review, summaries, knowledge base, feedback', async () => {
    const convo = await M.Conversation.create({
      type: 'care', practiceId: ctx.practice._id, patientId: ctx.patient._id, isUrgent: true,
      participants: [{ userId: ctx.doctor._id, role: 'doctor', unreadCount: 2 }],
    });
    const aiMsg = await M.Message.create({
      conversationId: convo._id, senderType: 'ai', text: 'Take both doses at dinner.',
      ai: { flagged: true, urgency: 'medium', citations: [{ label: 'ADA Standards of Care 2026 §9' }], latencyMs: 1400 },
    });
    await M.ChatReview.create({
      practiceId: ctx.practice._id, patientId: ctx.patient._id, conversationId: convo._id, messageId: aiMsg._id,
      reason: 'dosage_question', urgency: 'medium',
    });
    await M.ChatSummary.create({
      practiceId: ctx.practice._id, patientId: ctx.patient._id, conversationId: convo._id, date: today,
      messageCount: 3, needsReply: true, summary: 'Wants Metformin at night.',
    });
    await rejects(
      M.ChatSummary.create({ practiceId: ctx.practice._id, patientId: ctx.patient._id, conversationId: convo._id, date: today }),
      /duplicate key/,
    );
    const session = await M.AiSession.create({ ownerType: 'doctor', userId: ctx.doctor._id, patientId: ctx.patient._id });
    await M.AiMessage.create({ sessionId: session._id, role: 'user', text: 'Compare reports', inputMode: 'spoken', voiceLanguage: 'en' });
    await rejects(M.AiMessage.create({ sessionId: session._id, role: 'assistant', vote: 5 }), /vote/);
    const shared = await M.KnowledgeEntry.create({ title: 'Thyroid tablet on an empty stomach', content: 'Take it…', status: 'approved' });
    await M.KnowledgeAdoption.create({ practiceId: ctx.practice._id, entryId: shared._id, adoptedBy: ctx.doctor._id });
    await rejects(M.KnowledgeEntry.create({ title: 'Long', content: 'x'.repeat(2001) }), /content/);
    await M.Feedback.create({ practiceId: ctx.practice._id, patientId: ctx.patient._id, rating: 5, category: 'care' });
    await rejects(M.Feedback.create({ practiceId: ctx.practice._id, patientId: ctx.patient._id, rating: 6 }), /rating/);
  });

  await step('billing, pharmacy order, notification, export, audit', async () => {
    await M.Plan.create({ key: 'clinic', name: 'Clinic', priceMonthly: 2499, seats: 8, activePatients: 500, aiChatsPerMonth: 3000 });
    await M.Subscription.create({ practiceId: ctx.practice._id, planKey: 'clinic', price: 2499 });
    await rejects(M.Subscription.create({ practiceId: ctx.practice._id, planKey: 'starter' }), /duplicate key/);
    await M.Invoice.create({ practiceId: ctx.practice._id, issuedAt: new Date('2026-09-14'), amount: 2499, status: 'paid' });
    await rejects(M.Invoice.create({ practiceId: ctx.practice._id, issuedAt: new Date(), amount: 24.99 }), /amount/);
    const pharmacy = await M.Pharmacy.create({ name: 'CarePlus Online', type: 'online' });
    await M.Order.create({
      patientId: ctx.patient._id, pharmacyId: pharmacy._id, mode: 'delivery', total: 138,
      items: [{ name: 'Metformin 500 mg', strips: 2, lineTotal: 138 }],
    });
    await M.Notification.create({ userId: ctx.doctor._id, type: 'urgent_chat', title: 'Urgent chat from Priya Sharma' });
    await M.ExportJob.create({ practiceId: ctx.practice._id, requestedBy: ctx.doctor._id, kind: 'report', format: 'pdf' });
    await M.AuditLog.create({ practiceId: ctx.practice._id, userId: ctx.doctor._id, action: 'patient.view', patientId: ctx.patient._id });
  });

  await step('geo query: locations near a point', async () => {
    const near = await M.Location.find({
      geo: { $near: { $geometry: { type: 'Point', coordinates: [88.41, 22.58] }, $maxDistance: 3000 } },
    });
    assert.equal(near.length, 1);
  });

  await conn.dropDatabase();
  console.log(`\nAll ${passed} schema checks passed (${Object.keys(mongoose.models).length} collections). Test database dropped.`);
  await disconnect();
})().catch(async (err) => {
  console.error('\n✗ FAILED:', err);
  await disconnect();
  process.exit(1);
});

// End-to-end API test: starts the server on a throwaway database
// (<db>_api_test), drives the main flows of all three apps over HTTP,
// checks permissions, then drops the database.
// Usage: npm run test:api
const assert = require('assert/strict');
const env = require('../src/config/env');

env.mongo.dbName = `${env.mongo.dbName}_api_test`;
env.port = 0;
// Tests never send real SMS: force dev OTP mode even when MSG91 keys are set.
env.msg91.authKey = '';
env.exposeDevOtp = true;
// …and never call a real AI provider (see scripts/test-ai.js for that).
env.ai.provider = 'off';
env.smsProvider = 'msg91'; // server-issued codes (Firebase sign-in is checked separately below)
env.firebase.projectId = 'medpin-test';
const { connect, disconnect, mongoose } = require('../src/db');
const M = require('../src/models');
const { createApp } = require('../src/app');

let base;
let passed = 0;
const step = async (name, fn) => {
  try {
    await fn();
    passed += 1;
    console.log(`  ✓ ${name}`);
  } catch (err) {
    console.error(`  ✗ ${name}`);
    throw err;
  }
};

/** Tiny client: api(token)('POST', '/path', body) → { status, body } */
const api = (token, practiceId) => async (method, path, body, { form } = {}) => {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (practiceId) headers['x-practice-id'] = String(practiceId);
  let payload;
  if (form) payload = form;
  else if (body !== undefined) {
    headers['content-type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  const res = await fetch(`${base}${path}`, { method, headers, body: payload });
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  return { status: res.status, body: json };
};
const ok = (res, status = 200) => {
  if (res.status !== status) throw new Error(`Expected ${status}, got ${res.status}: ${JSON.stringify(res.body)}`);
  return res.body;
};

async function login(phone) {
  const anon = api();
  const sent = ok(await anon('POST', '/api/auth/otp/request', { phone }));
  assert.match(sent.devCode, /^\d{6}$/, 'dev OTP code returned without an SMS provider');
  const wrong = await anon('POST', '/api/auth/otp/verify', { phone, code: sent.devCode === '000000' ? '111111' : '000000' });
  assert.equal(wrong.status, 400);
  return ok(await anon('POST', '/api/auth/otp/verify', { phone, code: sent.devCode, platform: 'android' }));
}

const tinyPdf = () => Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 200 200]/Parent 2 0 R>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF');
const tinyPng = () => Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');
const fileForm = (field, buffer, name, type, extra = {}) => {
  const fd = new FormData();
  fd.append(field, new Blob([buffer], { type }), name);
  for (const [k, v] of Object.entries(extra)) fd.append(k, v);
  return fd;
};

(async () => {
  const conn = await connect();
  await conn.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
  // Catalogs the app expects (normally from `npm run db:seed`).
  await M.Plan.create([
    { key: 'starter', name: 'Starter', priceMonthly: 999, seats: 3, activePatients: 150, aiChatsPerMonth: 1000 },
    { key: 'clinic', name: 'Clinic', priceMonthly: 2499, seats: 8, activePatients: 500, aiChatsPerMonth: 3000 },
  ]);
  await M.Medicine.create([
    { genericName: 'Metformin', drugClass: 'biguanide', strengths: [{ value: 500, unit: 'mg' }], mrpPerStrip: 40 },
    { genericName: 'Glimepiride', drugClass: 'sulfonylurea', strengths: [{ value: 1, unit: 'mg' }, { value: 2, unit: 'mg' }, { value: 4, unit: 'mg' }], mrpPerStrip: 75 },
  ]);
  await M.LabTest.create({ name: 'HbA1c', panel: 'Diabetes panel', unit: '%' });
  await M.Pharmacy.create([
    { name: 'CarePlus Online', type: 'online', deliveryFee: 15, discountPct: 10, deliveryEtaText: 'Delivers tomorrow by 11 AM' },
    { name: 'Salt Lake Medicals', type: 'nearby', pickupEtaMin: 30 },
  ]);

  const server = createApp().listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
  env.publicUrl = base;
  console.log(`Testing API at ${base} (db ${env.mongo.dbName})`);

  const ctx = {};

  await step('health + auth guard', async () => {
    const h = ok(await api()('GET', '/health'));
    assert.equal(h.db, 'connected');
    assert.equal((await api()('GET', '/api/practice')).status, 401);
    assert.equal((await api()('POST', '/api/auth/otp/request', { phone: '12345' })).status, 400);
    // Firebase sign-in: disabled in this mode, and forged tokens never pass.
    assert.equal((await api()('POST', '/api/auth/firebase', { idToken: 'x' })).status, 400);
    env.smsProvider = 'firebase';
    const fb = ok(await api()('POST', '/api/auth/otp/request', { phone: '9811100001' }));
    assert.equal(fb.method, 'firebase');
    assert.equal(fb.devCode, undefined, 'no server code when Firebase sends the SMS');
    const jwt = require('jsonwebtoken');
    const forged = jwt.sign({ phone_number: '+919811100001', sub: 'x' }, 'not-google', { algorithm: 'HS256', header: { kid: 'fake' } });
    assert.equal((await api()('POST', '/api/auth/firebase', { idToken: forged })).status, 401);
    env.smsProvider = 'msg91';
  });

  await step('doctor signs in with OTP and creates a practice', async () => {
    const s = await login('+91 98300 41275');
    assert.equal(s.landing, 'Auth-Welcome', 'a new number chooses doctor / patient / invite');
    ctx.doc = api(s.accessToken);
    ctx.docRefresh = s.refreshToken;
    const out = ok(await ctx.doc('POST', '/api/me/practices', { name: 'City Care Clinic', doctorName: 'Dr. Arjun Sen', locationName: 'City Care Clinic — Salt Lake', area: 'Salt Lake', city: 'Kolkata' }), 201);
    ctx.practiceId = out.practice.id;
    ctx.locationId = out.location.id;
    assert.equal(out.landing, 'Doctor-Dashboard');
    const refreshed = ok(await api()('POST', '/api/auth/refresh', { refreshToken: ctx.docRefresh }));
    assert.ok(refreshed.accessToken);
    const late = await api()('POST', '/api/auth/refresh', { refreshToken: ctx.docRefresh });
    assert.equal(late.status, 401, 'refresh tokens rotate');
    assert.equal(late.body.error.code, 'REFRESH_RACE', 'a late duplicate is a race, not a theft');
    // Two requests racing with the same token: exactly one wins.
    const both = await Promise.all([1, 2, 3].map(() => api()('POST', '/api/auth/refresh', { refreshToken: refreshed.refreshToken })));
    assert.equal(both.filter((r) => r.status === 200).length, 1, 'only one parallel refresh succeeds');
    const winner = both.find((r) => r.status === 200).body;
    ok(await api(winner.accessToken)('GET', '/api/me'));
    // The clinic is bookable at once: the doctor practises at its first location.
    const slots = ok(await ctx.doc('GET', `/api/doctors/${out.user.id}/slots?locationId=${ctx.locationId}&date=${new Date(Date.now() + 2 * 864e5).toISOString().slice(0, 10)}`));
    assert.notEqual(slots.reason, 'not_practising_here', 'new clinic has a schedule');
  });

  await step('practice readiness, location hours, departments', async () => {
    const p = ok(await ctx.doc('GET', '/api/practice'));
    assert.equal(p.readiness.find((x) => x.key === 'signature').done, false);
    const bad = await ctx.doc('PATCH', `/api/locations/${ctx.locationId}`, { weeklyHours: [{ weekday: 'mon', opensAt: 600, closesAt: 540 }] });
    assert.equal(bad.status, 400);
    ok(await ctx.doc('PATCH', `/api/locations/${ctx.locationId}`, { lat: 22.5867, lng: 88.4116, googleMapsUrl: 'https://maps.app.goo.gl/x' }));
    ok(await ctx.doc('POST', '/api/departments', { name: 'Endocrinology' }), 201);
    assert.equal((await ctx.doc('POST', '/api/departments', { name: '' })).status, 400);
    ok(await ctx.doc('POST', `/api/locations/${ctx.locationId}/closures`, { startDate: '2027-10-20', endDate: '2027-10-23', reason: 'Durga Puja' }), 201);
  });

  await step('doctor profile, signature, schedule and services', async () => {
    ok(await ctx.doc('PATCH', '/api/doctor/profile', {
      headline: 'Diabetologist · Internal medicine', specialtyKeys: ['diabetes'], languagesSpoken: ['English', 'Bengali'], gender: 'male',
      specialisations: ['Diabetology', 'diabetology', 'Internal medicine'], practisingSince: 2010, offersVideo: true,
    }));
    const prof = ok(await ctx.doc('GET', '/api/doctor/profile'));
    assert.deepEqual(prof.specialisations, ['Diabetology', 'Internal medicine'], 'tags are de-duplicated');
    ok(await ctx.doc('POST', '/api/doctor/qualifications', { name: 'MBBS', institution: 'Calcutta Medical College', year: 2008 }), 201);
    const week = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((weekday) => ({ weekday, sessions: [{ startMin: 0, endMin: 1440 }] }));
    ok(await ctx.doc('PUT', `/api/doctor/locations/${ctx.locationId}`, {
      services: [{ name: 'New consultation', visitType: 'new', fee: 600 }, { name: 'Follow-up', visitType: 'follow_up', fee: 500 }, { name: 'Report review', visitType: 'report_review', fee: 0, freeWithinDays: 7 }],
      schedule: { week, slotLengthMin: 15, walkInPlaces: 2 },
    }));
    const me = ok(await ctx.doc('GET', '/api/me'));
    ctx.doctorUserId = me.user.id;
  });

  await step('invite front desk; they register with the code', async () => {
    const invite = ok(await ctx.doc('POST', '/api/invites', { role: 'front_desk', locationIds: [ctx.locationId] }), 201);
    assert.match(invite.code, /^[A-Z]{3}-\d{4}$/);
    const s = await login('9749681391');
    const desk = api(s.accessToken);
    const preview = ok(await desk('GET', `/api/auth/invites/${invite.code}`));
    assert.equal(preview.role, 'front_desk');
    assert.equal((await desk('POST', '/api/auth/register', { inviteCode: invite.code, name: 'Tania Ghosh' })).status, 400, 'terms required');
    const reg = ok(await desk('POST', '/api/auth/register', { inviteCode: invite.code, name: 'Tania Ghosh', termsAccepted: true, language: 'bn' }), 201);
    assert.equal(reg.landing, 'Staff-Today');
    ctx.desk = desk;
    const team = ok(await ctx.doc('GET', '/api/members'));
    assert.equal(team.seats.used, 2);
  });

  await step('front desk registers a patient (phone verified by OTP)', async () => {
    const sent = ok(await ctx.desk('POST', '/api/patients/phone-otp', { phone: '9230592842' }));
    const p = ok(await ctx.desk('POST', '/api/patients', { name: 'Priya Sharma', phone: '9230592842', gender: 'female', ageYears: 29, address: '14/2 Beliaghata Main Road', otpCode: sent.devCode }), 201);
    ctx.patientId = p.id;
    const dup = await ctx.desk('POST', '/api/patients', { name: 'Dup', phone: '92305 92842', gender: 'female', ageYears: 30 });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.error.code, 'PATIENT_EXISTS');
    const look = ok(await ctx.desk('GET', '/api/patients/lookup?phone=9230592842'));
    assert.equal(look.linked, true);
    ok(await ctx.doc('POST', `/api/patients/${ctx.patientId}/allergies`, { allergens: 'Sulfa drugs, peanuts, sulfa drugs' }), 201);
    ok(await ctx.doc('POST', `/api/patients/${ctx.patientId}/conditions`, { name: 'Type 2 diabetes', icdCode: 'E11.9' }), 201);
    const list = ok(await ctx.doc('GET', '/api/patients?q=priya'));
    assert.equal(list.items.length, 1);
    assert.deepEqual(list.items[0].allergies, ['Sulfa drugs', 'peanuts']);
    assert.equal((await ctx.desk('POST', `/api/patients/${ctx.patientId}/allergies`, { allergens: 'x' })).status, 403, 'front desk cannot edit records');
  });

  await step('desk books a slot, checks the patient in', async () => {
    const slots = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}`));
    let free = slots.slots.find((s) => s.available && !s.walkIn);
    let day = 0;
    while (!free && day < 2) {
      day += 1;
      const d = new Date(Date.now() + day * 864e5).toISOString().slice(0, 10);
      free = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${d}`)).slots.find((s) => s.available && !s.walkIn);
    }
    assert.ok(free, 'a free slot exists');
    const appt = ok(await ctx.desk('POST', '/api/appointments', { patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: free.startAt, visitType: 'new', reason: 'Tiredness' }), 201);
    assert.equal(appt.token, '01');
    assert.equal(appt.fee, 600);
    const taken = await ctx.desk('POST', '/api/appointments', { patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: free.startAt });
    assert.equal(taken.status, 409, 'slot can only be booked once');
    ctx.apptId = appt.id;
    ctx.slot = free;
    assert.equal((await ctx.desk('POST', `/api/appointments/${appt.id}/status`, { status: 'completed' })).status, 409, 'invalid transition rejected');
    ok(await ctx.desk('POST', `/api/appointments/${appt.id}/status`, { status: 'waiting' }));
    ok(await ctx.desk('POST', `/api/patients/${ctx.patientId}/vitals`, { bpSystolic: 128, bpDiastolic: 82, pulse: 78, spo2: 98, weightKg: 68.5, heightCm: 158, bloodSugar: 142, sugarType: 'fasting', appointmentId: appt.id }), 201);
    const today = ok(await ctx.desk('GET', '/api/staff/today'));
    if (day === 0) assert.equal(today.summary.checkedIn, 1);
  });

  await step('doctor queue → consultation → prescription', async () => {
    const queue = ok(await ctx.doc('GET', `/api/queue?locationId=${ctx.locationId}&date=${new Date(ctx.slot.startAt).toISOString().slice(0, 10)}`));
    const row = queue.items.find((x) => x.id === ctx.apptId);
    assert.ok(row && row.hasVitals, 'queue shows vitals recorded');
    assert.equal((await ctx.desk('POST', '/api/consultations', { appointmentId: ctx.apptId })).status, 403, 'front desk cannot prescribe');
    const c = ok(await ctx.doc('POST', '/api/consultations', { appointmentId: ctx.apptId }), 201);
    ctx.consultId = c.id;
    assert.ok(c.vitalsId, 'desk vitals attached to the consultation');
    const noDose = await ctx.doc('PATCH', `/api/consultations/${c.id}`, { medications: [{ name: 'Metformin', strength: '500 mg', dose: {} }] });
    assert.equal(noDose.status, 400);
    const draft = ok(await ctx.doc('PATCH', `/api/consultations/${c.id}`, {
      chiefComplaint: 'Tiredness and excess thirst, 2 weeks',
      diagnoses: [{ name: 'Type 2 diabetes mellitus', icdCode: 'E11.9' }],
      medications: [
        { name: 'Metformin', strength: '500 mg', dose: { morning: 1, night: 1 }, foodRelation: 'after_food', duration: { value: 30, unit: 'days' } },
        { name: 'Glimepiride', strength: '3 mg', dose: { morning: 1 }, foodRelation: 'before_food', duration: { value: 30, unit: 'days' } },
      ],
      labOrders: [{ testName: 'HbA1c' }, { testName: 'hba1c' }],
      advice: { items: [{ text: 'Walk 30 minutes, 5 days a week', category: 'activity' }] },
      followUp: { enabled: true, preset: '2_weeks' },
    }));
    assert.equal(draft.labOrders.length, 1, 'tests de-duplicated');
    assert.match(draft.medications[1].caution, /Sulfa/i, 'sulfa allergy flagged on a sulfonylurea');
    const checks = ok(await ctx.doc('GET', `/api/consultations/${c.id}/checks`));
    assert.ok(checks[1].warnings.some((w) => w.type === 'strength'), '3 mg is not a catalog strength');
    const issued = ok(await ctx.doc('POST', `/api/consultations/${c.id}/issue`));
    ctx.rxId = issued.prescription.id;
    assert.equal(issued.prescription.rxNumber, 1);
    assert.equal(issued.prescription.items[0].quantity, 60);
    const pdf = await fetch(issued.prescription.file.url);
    assert.equal(pdf.status, 200);
    assert.equal(pdf.headers.get('content-type'), 'application/pdf');
    // Flip one hex digit of the signature (always a real change).
    const tampered = await fetch(issued.prescription.file.url.replace(/sig=(\w)/, (_, c) => `sig=${c === '0' ? '1' : '0'}`));
    assert.equal(tampered.status, 403, 'signed links cannot be forged');
    assert.equal((await ctx.doc('POST', `/api/consultations/${c.id}/issue`)).status, 409);
    const appt = ok(await ctx.doc('GET', `/api/appointments/${ctx.apptId}`));
    assert.equal(appt.status, 'completed');
    const noSig = await ctx.doc('POST', `/api/prescriptions/${ctx.rxId}/send`);
    assert.equal(noSig.body.error.code, 'SIGNATURE_REQUIRED');
    ok(await ctx.doc('POST', '/api/doctor/profile/signature', undefined, { form: fileForm('file', tinyPng(), 'sig.png', 'image/png') }));
    ok(await ctx.doc('POST', `/api/prescriptions/${ctx.rxId}/send`));
  });

  await step('patient signs in; record created by the clinic is theirs', async () => {
    const s = await login('9230592842');
    assert.equal(s.landing, 'Main');
    assert.equal(s.patientId, ctx.patientId);
    ctx.pat = api(s.accessToken);
    const me = ok(await ctx.pat('GET', '/api/patient/me'));
    assert.equal(me.bmi, 27.4);
    ok(await ctx.pat('PATCH', '/api/patient/me', { bloodGroup: 'B+', emergencyContact: { name: 'Rohit Sharma', phone: '9830012345' }, language: 'hi' }));
    assert.equal((await ctx.pat('GET', '/api/practice')).status, 403, 'patients cannot use staff endpoints');
  });

  await step('patient medicines, doses, adherence', async () => {
    const meds = ok(await ctx.pat('GET', '/api/patient/medicines'));
    assert.equal(meds.running, 2);
    const doses = ok(await ctx.pat('GET', '/api/patient/doses'));
    assert.ok(doses.total >= 2);
    const course = meds.items.find((m) => m.name === 'Metformin');
    ok(await ctx.pat('PATCH', `/api/patient/medicines/${course.id}`, { stockUnits: 6 }));
    const dose = doses.items.find((d) => d.medicine.name === 'Metformin');
    ok(await ctx.pat('POST', `/api/patient/doses/${dose.id}`, { status: 'taken' }));
    const after = ok(await ctx.pat('GET', '/api/patient/medicines'));
    assert.equal(after.items.find((m) => m.name === 'Metformin').stock.units, 5, 'taking a dose lowers stock');
    ok(await ctx.pat('GET', '/api/patient/adherence'));
    const home = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.ok(home.tasks.some((t) => t.kind === 'dose' && t.done));
    assert.ok(home.slides.some((x) => x.kind === 'refill'), 'refill slide when stock is low');
  });

  await step('home BP reading raises an alert; staff acknowledge and resolve', async () => {
    const r = ok(await ctx.pat('POST', '/api/patient/readings', { bpSystolic: 172, bpDiastolic: 104 }), 201);
    assert.equal(r.alerted, true);
    const alerts = ok(await ctx.doc('GET', '/api/alerts'));
    const a = alerts.items.find((x) => x.kind === 'reading');
    assert.ok(a);
    ok(await ctx.doc('POST', `/api/alerts/${a.id}/acknowledge`, { note: 'Called patient, advised to come in' }));
    assert.equal((await ctx.doc('POST', `/api/alerts/${a.id}/acknowledge`)).status, 409);
    ok(await ctx.doc('POST', `/api/alerts/${a.id}/resolve`));
  });

  await step('chat: patient ↔ clinic, unread counts, urgent help', async () => {
    const convos = ok(await ctx.pat('GET', '/api/patient/conversations'));
    assert.ok(convos.length >= 1, 'care thread exists (prescription was sent there)');
    ctx.convoId = convos[0].id;
    ok(await ctx.pat('POST', `/api/conversations/${ctx.convoId}/messages`, { text: 'Should I take the tablet before food?' }), 201);
    assert.equal((await ctx.pat('POST', `/api/conversations/${ctx.convoId}/messages`, { text: '  ' })).status, 400);
    const inbox = ok(await ctx.desk('GET', '/api/inbox?tab=unread'));
    assert.ok(inbox.items.some((x) => x.id === ctx.convoId));
    const thread = ok(await ctx.desk('GET', `/api/conversations/${ctx.convoId}/messages`));
    assert.ok(thread.items.length >= 2);
    ok(await ctx.desk('POST', `/api/conversations/${ctx.convoId}/read`));
    const reply = ok(await ctx.doc('POST', `/api/conversations/${ctx.convoId}/messages`, { text: 'After food, please.' }), 201);
    ok(await ctx.doc('POST', `/api/conversations/${ctx.convoId}/pin`, { messageId: reply.message.id }));
    const urgent = ok(await ctx.pat('POST', '/api/patient/urgent', { doctorId: ctx.doctorUserId, text: 'Chest tightness, hard to breathe.' }), 201);
    assert.equal(urgent.call, '108');
    const em = ok(await ctx.doc('GET', '/api/alerts?severity=emergency'));
    assert.ok(em.items.length >= 1);
  });

  await step('find a doctor, request a visit, desk assigns a time', async () => {
    const found = ok(await ctx.pat('GET', '/api/patient/doctors/search?specialty=diabetes&lat=22.58&lng=88.41'));
    assert.equal(found.items.length, 1);
    assert.equal(found.items[0].mine, true);
    assert.ok(found.items[0].km < 3);
    const detail = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}`));
    assert.ok(detail.lastVisit);
    const req = ok(await ctx.pat('POST', '/api/patient/visit-requests', { doctorId: ctx.doctorUserId, visitType: 'follow_up', preferredTime: 'Thu or Fri, after 5 PM' }), 201);
    const pending = ok(await ctx.desk('GET', '/api/appointment-requests'));
    assert.ok(pending.some((x) => x.id === req.request.id));
    const tomorrow = new Date(Date.now() + 864e5).toISOString().slice(0, 10);
    const slots = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${tomorrow}`));
    const free = slots.slots.find((s) => s.available && !s.walkIn);
    const assigned = ok(await ctx.desk('POST', `/api/appointment-requests/${req.request.id}/assign`, { startAt: free.startAt }));
    assert.equal(assigned.request.status, 'scheduled');
    const fus = ok(await ctx.doc('GET', '/api/follow-ups'));
    assert.equal(fus.items[0].status, 'booked', 'booking a follow-up visit marks the follow-up booked');
    const mine = ok(await ctx.pat('GET', '/api/patient/appointments'));
    assert.equal(mine.items.length, 1);
    const moved = ok(await ctx.desk('POST', `/api/appointments/${assigned.appointment.id}/reschedule`, { startAt: slots.slots.filter((s) => s.available && !s.walkIn)[1].startAt }));
    assert.ok(moved.rescheduledFromId);
    ok(await ctx.pat('GET', '/api/notifications'));
  });

  await step('records: upload, split into tests, share; trends', async () => {
    const up = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'report.pdf', 'application/pdf', { kind: 'test_result', sourceName: 'Suraksha Diagnostics', shareWith: ctx.doctorUserId }) }), 201);
    const split = ok(await ctx.pat('POST', `/api/patient/records/${up.record.id}/split`, {
      collectedAt: '2026-09-30',
      tests: [{ testName: 'Lipid profile', pageFrom: 1, pageTo: 2, summary: 'LDL is high.', values: [{ analyte: 'LDL cholesterol', value: '158', unit: 'mg/dL', refText: 'below 100', flag: 'high' }] }],
    }), 201);
    assert.equal(split[0].flagLabel, '1 high');
    assert.equal((await ctx.pat('POST', `/api/patient/records/${up.record.id}/split`, { tests: [] })).status, 404, 'parent replaced');
    const recs = ok(await ctx.pat('GET', '/api/patient/records'));
    assert.ok(recs.counts.prescription >= 1 && recs.counts.test_result >= 1);
    const labs = ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}/lab-results?filter=abnormal`));
    assert.equal(labs.abnormalFindings, 1);
    const trend = ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}/trends/LDL cholesterol`));
    assert.equal(trend[0].value, 158);
    const profile = ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}`));
    assert.ok(profile.abnormalResults.length >= 1 && profile.currentMedicines.length === 2);
  });

  await step('pharmacy: cart, quotes, order', async () => {
    const meds = ok(await ctx.pat('GET', '/api/patient/medicines'));
    const cart = ok(await ctx.pat('POST', '/api/patient/cart/items', { courseId: meds.items.find((m) => m.name === 'Metformin').id, packOption: '1_month' }), 201);
    assert.equal(cart.items[0].strips, 6);
    const quotes = ok(await ctx.pat('GET', '/api/patient/pharmacies/quotes?mode=delivery'));
    assert.equal(quotes.items[0].total, 6 * 36 + 15);
    ok(await ctx.pat('POST', '/api/patient/addresses', { line: 'Flat 3B, 12 Purbachal Rd, Salt Lake', isDefault: true }), 201);
    const order = ok(await ctx.pat('POST', '/api/patient/orders', { pharmacyId: quotes.items[0].pharmacy.id, mode: 'delivery' }), 201);
    assert.equal(order.status, 'placed');
    assert.equal(ok(await ctx.pat('GET', '/api/patient/cart')).count, 0);
  });

  await step('consent code links the patient to a second practice', async () => {
    const s = await login('9811122233');
    const doc2 = api(s.accessToken);
    ok(await doc2('POST', '/api/me/practices', { name: 'Heart Point', doctorName: 'Dr. Rina Mitra' }), 201);
    assert.equal((await doc2('GET', `/api/patients/${ctx.patientId}`)).status, 404, 'not linked yet');
    const code = ok(await ctx.pat('POST', '/api/patient/consent-code'));
    assert.equal((await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: '000000' === code.code ? '111111' : '000000' })).status, 400);
    ok(await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: code.display }));
    ok(await doc2('GET', `/api/patients/${ctx.patientId}`));
    assert.equal((await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: code.code })).status, 400, 'codes are single-use');
  });

  await step('knowledge base workflow and feedback', async () => {
    const e = ok(await ctx.doc('POST', '/api/knowledge', { title: 'Metformin timing', content: 'Take metformin with or right after meals.', category: 'medicines', tags: ['Metformin', 'metformin', 'Dosage timing'] }), 201);
    assert.deepEqual(e.tags, ['metformin', 'dosage timing']);
    assert.equal((await ctx.doc('POST', `/api/knowledge/${e.id}/approve`)).status, 409, 'must be submitted first');
    ok(await ctx.doc('POST', `/api/knowledge/${e.id}/submit`));
    assert.equal((await ctx.desk('POST', `/api/knowledge/${e.id}/approve`)).status, 403, 'only doctors approve');
    ok(await ctx.doc('POST', `/api/knowledge/${e.id}/approve`));
    const kb = ok(await ctx.doc('GET', '/api/knowledge'));
    assert.equal(kb.counts.approved, 1);
    const fb = ok(await ctx.pat('POST', '/api/patient/feedback', { practiceId: ctx.practiceId, rating: 5, comment: 'Very kind doctor' }), 201);
    ok(await ctx.desk('POST', `/api/feedback/${fb.id}/reply`, { text: 'Thank you, Priya.' }));
    const list = ok(await ctx.doc('GET', '/api/feedback'));
    assert.equal(list.averageRating, 5);
  });

  await step('reports, fees, dashboard', async () => {
    const sum = ok(await ctx.doc('GET', '/api/reports/summary?range=30_days'));
    assert.equal(sum.kpis.consultations.value, 1);
    assert.equal(sum.kpis.prescriptions.value, 1);
    assert.equal(sum.topDiagnoses[0].key, 'Type 2 diabetes mellitus');
    const reg = ok(await ctx.doc('GET', '/api/reports/consultations'));
    assert.equal(reg.items[0].diagnoses[0], 'Type 2 diabetes mellitus');
    const pending = ok(await ctx.doc('GET', '/api/payments?status=pending'));
    const first = pending.find((p) => p.amount === 600);
    assert.equal((await ctx.desk('POST', `/api/payments/${first.id}/mark-paid`, {})).status, 400);
    ok(await ctx.desk('POST', `/api/payments/${first.id}/mark-paid`, { method: 'upi' }));
    const fees = ok(await ctx.doc('GET', '/api/reports/fees'));
    assert.equal(fees.collected, 600);
    ok(await ctx.doc('GET', '/api/reports/prescriptions'));
    ok(await ctx.doc('GET', '/api/reports/follow-ups'));
    ok(await ctx.doc('GET', '/api/reports/daily'));
    const dash = ok(await ctx.doc('GET', '/api/dashboard'));
    assert.equal(dash.greetingName, 'Dr. Arjun Sen');
    ok(await ctx.doc('GET', '/api/dashboard/cards'));
    ok(await ctx.doc('GET', '/api/history?period=this_month'));
  });

  await step('billing limits and exports', async () => {
    const b = ok(await ctx.doc('GET', '/api/billing'));
    assert.equal(b.usage.seats.used, 2);
    ok(await ctx.doc('POST', '/api/billing/switch', { planKey: 'clinic' }));
    assert.equal((await ctx.desk('POST', '/api/billing/switch', { planKey: 'starter' })).status, 403, 'owner only');
    for (const format of ['csv', 'xlsx', 'pdf', 'json']) {
      const job = ok(await ctx.doc('POST', '/api/exports', { kind: 'appointment_history', format, filters: { from: '2026-01-01' } }), 201);
      assert.equal(job.status, 'done');
      assert.equal((await fetch(job.url)).status, 200);
    }
    assert.equal((await ctx.desk('POST', '/api/exports', { kind: 'data_export', format: 'csv', datasets: ['patients'] })).status, 409, 'patient data export is owner only');
    const data = ok(await ctx.doc('POST', '/api/exports', { kind: 'data_export', format: 'csv', datasets: ['patients', 'clinical_summary', 'alerts'] }), 201);
    assert.ok(data.rowCount >= 1);
    assert.ok(await M.AuditLog.exists({ action: 'export.create' }), 'exports are audited');
  });

  await step('team: suspend a member revokes access', async () => {
    const team = ok(await ctx.doc('GET', '/api/members'));
    const tania = team.items.find((m) => m.role === 'front_desk');
    ok(await ctx.doc('PATCH', `/api/members/${tania.id}`, { suspended: true }));
    assert.equal((await ctx.desk('GET', '/api/staff/today')).status, 401, 'suspension signs them out at once');
    ok(await ctx.doc('PATCH', `/api/members/${tania.id}`, { suspended: false }));
  });

  await step('AI endpoints respond without a key (graceful fallback)', async () => {
    const s = ok(await ctx.doc('POST', '/api/ai/sessions', { patientId: ctx.patientId }), 201);
    const out = ok(await ctx.doc('POST', `/api/ai/sessions/${s.id}/messages`, { text: 'Summarise this patient' }), 201);
    assert.ok(out.answer.text);
    const v = ok(await ctx.doc('POST', `/api/ai/messages/${out.answer.id}/vote`, { vote: 1 }));
    assert.equal(v.vote, 1);
    assert.equal(ok(await ctx.doc('POST', `/api/ai/messages/${out.answer.id}/vote`, { vote: 1 })).vote, 0, 'same vote again clears it');
    ok(await ctx.pat('POST', '/api/patient/ai/ask', { text: 'Is HbA1c 7.2% high?' }), 201);
    ok(await ctx.doc('GET', '/api/inbox/summaries?date=today'));
    ok(await ctx.doc('GET', '/api/inbox/reviews'));
  });

  await step('new doctor screens: settings, devices, support, lab report, knowledge, AI history', async () => {
    // Payouts: only the last 4 digits are kept; bad IFSC is rejected.
    assert.equal((await ctx.doc('PATCH', '/api/doctor/profile', { payout: { ifsc: 'BAD' } })).status, 400);
    const pay = ok(await ctx.doc('PATCH', '/api/doctor/profile', { payout: { upiId: 'arjun@okhdfc', accountHolder: 'Arjun Sen', ifsc: 'hdfc0001234', accountNumber: '50100123456789' } }));
    assert.equal(pay.payout.bankAccountLast4, '6789');
    assert.equal(pay.payout.ifsc, 'HDFC0001234');
    assert.equal(JSON.stringify(pay).includes('50100123456789'), false, 'full account number is never stored');
    // Chat settings are enforced: "nobody" blocks a patient starting a chat.
    ok(await ctx.doc('PATCH', '/api/doctor/profile', { chatSettings: { whoCanMessage: 'nobody' }, notificationPrefs: { quietHours: { enabled: true } } }));
    assert.equal((await ctx.pat('POST', '/api/patient/conversations', { doctorId: ctx.doctorUserId })).body.error.code, 'CHAT_OFF');
    const prof = ok(await ctx.doc('PATCH', '/api/doctor/profile', { chatSettings: { whoCanMessage: 'booked' } }));
    assert.equal(prof.notificationPrefs.quietHours.enabled, true, 'settings merge instead of replacing');
    // Signed-in devices.
    const sessions = ok(await ctx.doc('GET', '/api/me/sessions'));
    assert.ok(sessions.length >= 1);
    const support = ok(await ctx.doc('GET', '/api/me/support'));
    assert.ok('email' in support);
    assert.equal((await ctx.doc('POST', '/api/me/support', { message: 'hi' })).status, 400);
    ok(await ctx.doc('POST', '/api/me/support', { topic: 'problem', message: 'The queue did not refresh after check-in.' }), 201);
    const mine = ok(await ctx.doc('POST', '/api/me/export'), 201);
    assert.equal((await fetch(mine.url)).status, 200);
    // Lab report detail with previous values.
    const labs = ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}/lab-results`));
    const detail = ok(await ctx.doc('GET', `/api/lab-results/${labs.items[0].id}`));
    assert.equal(detail.patient.name, 'Priya Sharma');
    assert.ok(Array.isArray(detail.values));
    // Knowledge: duplicate, delete the draft copy, approved entries can't be deleted.
    const kb = ok(await ctx.doc('GET', '/api/knowledge'));
    const approved = kb.items.find((e) => e.status === 'approved');
    const copy = ok(await ctx.doc('POST', `/api/knowledge/${approved.id}/duplicate`), 201);
    assert.equal(copy.status, 'draft');
    ok(await ctx.doc('DELETE', `/api/knowledge/${copy.id}`));
    assert.equal((await ctx.doc('DELETE', `/api/knowledge/${approved.id}`)).status, 409);
    // AI history: delete a conversation.
    const s = ok(await ctx.doc('POST', '/api/ai/sessions', {}), 201);
    ok(await ctx.doc('DELETE', `/api/ai/sessions/${s.id}`));
    assert.equal((await ctx.doc('GET', `/api/ai/sessions/${s.id}/messages`)).status, 404);
  });

  server.close();
  await conn.dropDatabase();
  console.log(`\nAll ${passed} API checks passed. Test database dropped.`);
  await disconnect();
  process.exit(0);
})().catch(async (err) => {
  console.error('\n', err);
  await disconnect().catch(() => {});
  process.exit(1);
});

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
// Never call Razorpay from tests (even when real keys are in .env); steps that
// need keys set fake ones and answer for Razorpay themselves.
Object.assign(env.razorpay, { keyId: undefined, keySecret: undefined, webhookSecret: undefined, payoutAccountNumber: undefined });
// Never send real email from tests.
env.smtp.host = undefined;
// The area name for "near …" answers from a fixed table, never the internet.
require('../src/services/places').reverse = async (lat) => (lat > 22.6 ? { area: 'New Town', city: 'Kolkata' } : { area: 'Salt Lake', city: 'Kolkata' });
// IFSC lookups answer from a fixed table, never the internet.
require('../src/services/banks').fetchImpl = async (url) => {
  const code = url.split('/').pop();
  const known = { HDFC0001234: { BANK: 'HDFC Bank', BRANCH: 'SALT LAKE', CITY: 'KOLKATA', STATE: 'WEST BENGAL', IFSC: code } };
  if (url.endsWith('/validate/vpa')) return { ok: false, status: 500, json: async () => ({}) }; // not reached: no keys in tests
  return known[code] ? { ok: true, status: 200, json: async () => known[code] } : { ok: false, status: 404, json: async () => ({}) };
};
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
// A pen signature on white paper (as a phone photo would give), and a faint one.
const sigPng = (stroke = '#1a1a2e') => require('sharp')(Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="700" height="260"><rect width="100%" height="100%" fill="#fbfbf8"/><path d="M60 150 C120 40, 160 220, 220 120 S320 60, 360 150 S460 200, 520 110 S600 90, 640 160" stroke="${stroke}" stroke-width="7" fill="none"/></svg>`,
)).png().toBuffer();
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
  await M.LabTest.create([{ name: 'HbA1c', panel: 'Diabetes panel', unit: '%' }, { name: 'Lipid profile', panel: 'Lipid panel' }]);
  await M.IcdCode.create({ code: 'E11.9', name: 'Type 2 diabetes mellitus' });
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

  await step('MSG91: codes go through the Flow API with the approved template (network stubbed)', async () => {
    const { sendOtp, FLOW_URL } = require('../src/services/sms');
    const saved = { ...env.msg91 };
    const realFetch = global.fetch;
    const sent = [];
    Object.assign(env.msg91, { authKey: 'test-key', senderId: 'MEDPIN', loginTemplateId: 'tpl-login', registerTemplateId: 'tpl-register' });
    let answer = { type: 'success', message: 'req-1' };
    global.fetch = async (url, opts) => {
      sent.push({ url: String(url), opts, body: JSON.parse(opts.body) });
      return { ok: true, status: 200, json: async () => answer };
    };
    try {
      await sendOtp('9830012345', '482917', 'login');
      await sendOtp('9830012345', '135790', 'register');
      assert.equal(sent[0].url, FLOW_URL);
      assert.equal(sent[0].opts.headers.authkey, 'test-key');
      assert.deepEqual(sent[0].body, { template_id: 'tpl-login', sender: 'MEDPIN', short_url: '0', recipients: [{ mobiles: '919830012345', OTP: '482917', otp: '482917' }] });
      assert.equal(sent[1].body.template_id, 'tpl-register');
      // MSG91 can say 200 { type: 'error' }: that must not count as sent.
      answer = { type: 'error', message: 'Invalid template' };
      await assert.rejects(() => sendOtp('9830012345', '111111', 'login'), /Invalid template/);
    } finally {
      global.fetch = realFetch;
      Object.assign(env.msg91, saved);
    }
  });

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
    ctx.docToken = s.accessToken;
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

  await step('owner adds front desk in People (phone + code); they sign in', async () => {
    assert.equal((await ctx.doc('POST', '/api/invites', { role: 'front_desk' })).status, 410, 'invite codes are off');
    assert.equal((await ctx.doc('POST', '/api/members', { role: 'front_desk', name: 'Tania Ghosh', phone: '9749681391' })).status, 400, 'phone must be verified');
    const sent = ok(await ctx.doc('POST', '/api/members/phone-otp', { phone: '9749681391' }));
    ok(await ctx.doc('POST', '/api/members', { role: 'front_desk', name: 'Tania Ghosh', phone: '9749681391', locationIds: [ctx.locationId], otpCode: sent.devCode }), 201);
    const s = await login('9749681391');
    assert.equal(s.landing, 'Staff-Today');
    const desk = api(s.accessToken);
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
    // Preview: the draft as its PDF; nothing issued or numbered.
    const rxBefore = await M.Prescription.countDocuments({ consultationId: c.id });
    const pv = ok(await ctx.doc('GET', `/api/consultations/${c.id}/preview`));
    const pvPdf = Buffer.from(await (await fetch(pv.url)).arrayBuffer());
    assert.equal(pvPdf.subarray(0, 5).toString(), '%PDF-', 'a PDF');
    assert.equal(await M.Prescription.countDocuments({ consultationId: c.id }), rxBefore, 'no prescription created');
    assert.equal(ok(await ctx.doc('GET', `/api/consultations/${c.id}`)).consultation.status, 'draft');
    assert.equal((await ctx.desk('GET', `/api/consultations/${c.id}/preview`)).status, 403, 'only those who prescribe');
    // MedPin AI suggestions (AI stubbed: nothing is sent anywhere).
    const off = ok(await ctx.doc('POST', `/api/consultations/${c.id}/ai-suggestions`));
    assert.equal(off.available, false, 'AI off: says so');
    const aiMod = require('../src/services/ai');
    const saved = { enabled: aiMod.enabled, completeJson: aiMod.completeJson };
    let calls = 0;
    aiMod.enabled = () => true;
    aiMod.completeJson = async ({ messages }) => {
      calls += 1;
      const facts = JSON.parse(messages[0].content);
      assert.ok(facts.allergies.some((a) => /sulfa/i.test(a)), 'the AI is told about allergies');
      assert.ok(!JSON.stringify(facts).includes('9230592842'), 'no phone numbers sent');
      return {
        model: 'stub',
        data: {
          diagnoses: [{ name: 'Diabetes type 2', icdCode: 'E11.9', likelihood: 'likely', reason: 'Thirst and tiredness for 2 weeks' }],
          tests: [{ name: 'lipid profile', reason: 'Cardiovascular risk' }],
          medicines: [
            { name: 'Glimepiride', strength: '1 mg', form: 'Tablet', morning: 1, afternoon: 0, night: 0, frequency: 'daily', foodRelation: 'before_food', durationValue: 30, durationUnit: 'days', reason: 'Add-on', caution: '' },
            { name: 'Vildagliptin', strength: '50 mg', form: 'Tablet', morning: 1, afternoon: 0, night: 1, frequency: 'daily', foodRelation: 'none', durationValue: 1, durationUnit: 'months', reason: 'Add-on, low hypo risk', caution: 'Check liver function' },
          ],
          redFlags: ['Vomiting with drowsiness'],
        },
      };
    };
    try {
      const s = ok(await ctx.doc('POST', `/api/consultations/${c.id}/ai-suggestions`));
      assert.equal(s.diagnoses[0].name, 'Type 2 diabetes mellitus', 'named as in the ICD catalog');
      assert.equal(s.diagnoses[0].icdCode, 'E11.9');
      assert.equal(s.tests[0].name, 'Lipid profile', 'matched to the test catalog');
      assert.ok(!s.medicines.some((m) => m.item.name === 'Glimepiride'), 'sulfonylurea dropped for a sulfa allergy');
      const v = s.medicines.find((m) => m.item.name === 'Vildagliptin');
      assert.deepEqual(v.item.dose, { morning: 1, afternoon: 0, night: 1 });
      assert.equal(v.item.foodRelation, undefined);
      assert.equal(v.item.entrySource, 'suggestion');
      assert.deepEqual(s.redFlags, ['Vomiting with drowsiness']);
      const again = ok(await ctx.doc('POST', `/api/consultations/${c.id}/ai-suggestions`));
      assert.equal(again.cached, true);
      assert.equal(calls, 1, 'reused until the consultation changes');
      assert.equal((await ctx.desk('POST', `/api/consultations/${c.id}/ai-suggestions`)).status, 403, 'only those who prescribe');
    } finally {
      Object.assign(aiMod, saved);
    }
    // No signature yet: issuing is refused and the draft stays a draft (nothing half-issued).
    const noSig = await ctx.doc('POST', `/api/consultations/${c.id}/issue`);
    assert.equal(noSig.status, 409);
    assert.equal(noSig.body.error.code, 'SIGNATURE_REQUIRED');
    assert.equal(ok(await ctx.doc('GET', `/api/consultations/${c.id}`)).consultation.status, 'draft', 'still editable');
    // Signature checker: a 1px image and a blank page are refused with the reason.
    const tiny = await ctx.doc('POST', '/api/doctor/profile/signature', undefined, { form: fileForm('file', tinyPng(), 'sig.png', 'image/png') });
    assert.equal(tiny.status, 422);
    assert.equal(tiny.body.error.code, 'SIGNATURE_REJECTED');
    assert.ok(tiny.body.error.details.issues.some((x) => x.code === 'TOO_SMALL'));
    const blank = await require('sharp')({ create: { width: 700, height: 260, channels: 3, background: '#ffffff' } }).png().toBuffer();
    assert.equal((await ctx.doc('POST', '/api/doctor/profile/signature', undefined, { form: fileForm('file', blank, 'sig.png', 'image/png') })).body.error.details.issues[0].code, 'NO_INK');
    // A faint signature needs "use it anyway"; then it is saved with the warning noted.
    const faint = await ctx.doc('POST', '/api/doctor/profile/signature', undefined, { form: fileForm('file', await sigPng('#8a8a8a'), 'sig.png', 'image/png') });
    assert.equal(faint.status, 409);
    assert.equal(faint.body.error.code, 'SIGNATURE_CHECK');
    const used = ok(await ctx.doc('POST', '/api/doctor/profile/signature', undefined, { form: fileForm('file', await sigPng('#8a8a8a'), 'sig.png', 'image/png', { accept: 'true' }) }));
    assert.equal(used.signatureCheck.status, 'warn');
    assert.equal(used.signatureCheck.acceptedWarnings, true);
    // A clear one passes; what prints is the cleaned, transparent PNG.
    const good = ok(await ctx.doc('POST', '/api/doctor/profile/signature', undefined, { form: fileForm('file', await sigPng(), 'sig.png', 'image/png') }));
    assert.equal(good.signatureCheck.status, 'ok');
    assert.equal(good.signature.mimeType, 'image/png');
    const meta = await require('sharp')(Buffer.from(await (await fetch(good.signature.url)).arrayBuffer())).metadata();
    assert.equal(meta.hasAlpha, true, 'paper made transparent');
    assert.ok(meta.width < 700, 'cropped to the ink');
    assert.equal(ok(await ctx.doc('POST', '/api/doctor/profile/signature/recheck')).signatureCheck.status, 'ok');
    // Profile photo: saved on the account (shown in app headers) and on the doctor profile.
    const withPhoto = ok(await ctx.doc('POST', '/api/me/photo', undefined, { form: fileForm('file', tinyPng(), 'me.png', 'image/png') }));
    assert.ok(withPhoto.user.photoUrl, 'the session shows the photo');
    assert.equal((await fetch(withPhoto.user.photoUrl)).status, 200);
    assert.ok(ok(await ctx.doc('GET', '/api/doctor/profile')).photo?.url, 'the public profile has it too');
    const issued = ok(await ctx.doc('POST', `/api/consultations/${c.id}/issue`));
    ctx.rxId = issued.prescription.id;
    assert.equal(issued.prescription.rxNumber, 1);
    assert.equal(issued.prescription.items[0].quantity, 60);
    const pdf = await fetch(issued.prescription.file.url);
    assert.equal(pdf.status, 200);
    assert.equal(pdf.headers.get('content-type'), 'application/pdf');
    assert.match(Buffer.from(await pdf.arrayBuffer()).toString('latin1'), /\/Subtype\s*\/Image/, 'the signature image is printed');
    // Flip one hex digit of the signature (always a real change).
    const tampered = await fetch(issued.prescription.file.url.replace(/sig=(\w)/, (_, c) => `sig=${c === '0' ? '1' : '0'}`));
    assert.equal(tampered.status, 403, 'signed links cannot be forged');
    // View / Download: a fresh link, the current layout, named for the patient.
    const fresh = ok(await ctx.doc('GET', `/api/prescriptions/${ctx.rxId}/pdf`));
    assert.match(fresh.name, /^Prescription RX-0001 · .+\.pdf$/);
    const freshPdf = Buffer.from(await (await fetch(fresh.url)).arrayBuffer()).toString('latin1');
    assert.ok((freshPdf.match(/\/Subtype\s*\/Image/g) || []).length >= 2, 'signature and verification QR are printed');
    assert.equal(ok(await ctx.doc('GET', `/api/prescriptions/${ctx.rxId}`)).pdfVersion, require('../src/services/rxpdf').PDF_VERSION);
    // A new clinic logo reaches prescriptions already issued: the PDF is drawn again.
    const before = (await M.Prescription.findById(ctx.rxId)).file.key;
    assert.equal(ok(await ctx.doc('GET', `/api/prescriptions/${ctx.rxId}/pdf`)).key, before, 'nothing changed: same file');
    ok(await ctx.doc('POST', '/api/practice/logo', undefined, { form: fileForm('file', tinyPng(), 'logo2.png', 'image/png') }));
    const loc0 = await M.Location.findById((await M.Prescription.findById(ctx.rxId)).locationId);
    if (loc0?.letterhead?.logo) await M.Location.updateOne({ _id: loc0._id }, { $unset: { 'letterhead.logo': 1 } });
    assert.notEqual(ok(await ctx.doc('GET', `/api/prescriptions/${ctx.rxId}/pdf`)).key, before, 'new logo: redrawn');
    // QR verification page: genuine with the token, not verified without it.
    const { verifyUrl } = require('../src/services/rxpdf');
    const vpage = await fetch(verifyUrl(ctx.rxId).replace(/^https?:\/\/[^/]+/, base));
    assert.equal(vpage.status, 200);
    const vhtml = await vpage.text();
    assert.match(vhtml, /Genuine/);
    assert.doesNotMatch(vhtml, /9\d{9}/, 'the verify page never shows the phone number');
    assert.equal((await fetch(`${base}/rx/${ctx.rxId}/verify?t=nope`)).status, 404);
    assert.equal((await ctx.doc('POST', `/api/consultations/${c.id}/issue`)).status, 409);
    const appt = ok(await ctx.doc('GET', `/api/appointments/${ctx.apptId}`));
    assert.equal(appt.status, 'completed');
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
    // Reminder settings are checked; a new dose time replaces the old one (no alarm at both).
    assert.equal((await ctx.pat('PATCH', '/api/patient/me', { settings: { dailyLogReminderAt: '25:99' } })).status, 400);
    const me = ok(await ctx.pat('PATCH', '/api/patient/me', { settings: { dailyLogReminderAt: '21:30', bogus: 1 } }));
    assert.equal(me.settings.dailyLogReminderAt, '21:30');
    assert.equal(me.settings.bogus, undefined, 'unknown settings are not saved');
    const tomorrow = new Date(Date.now() + 864e5 + 5.5 * 3600e3).toISOString().slice(0, 10);
    const before = ok(await ctx.pat('GET', `/api/patient/doses?date=${tomorrow}`));
    const old = me.settings.reminderTimes?.morning || '07:30';
    ok(await ctx.pat('PATCH', '/api/patient/me', { settings: { reminderTimes: { morning: '06:45' } } }));
    const moved = ok(await ctx.pat('GET', `/api/patient/doses?date=${tomorrow}`));
    const morning = moved.items.filter((d) => d.slot === 'morning');
    assert.ok(morning.length > 0, 'there are morning doses tomorrow');
    assert.equal(morning.length, before.items.filter((d) => d.slot === 'morning').length, 'same number of morning doses');
    // Breakfast at 06:45 IST: after food 07:00, before food 06:15, with food / no rule 06:45 (UTC = IST − 5:30).
    const expectUtc = { after_food: '01:30', before_food: '00:45', with_food: '01:15', empty_stomach: '00:30' };
    for (const d of morning) {
      const rel = d.medicine?.foodRelation;
      assert.equal(new Date(d.at).toISOString().slice(11, 16), expectUtc[rel] || '01:15', `${d.medicine?.name} (${rel}) timed around breakfast moved from ${old} to 06:45`);
    }
    // Meal log: a task only once the dietician / doctor asks for it ("Ask to log meals").
    const homeNoLog = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.equal(homeNoLog.dailyLog, false, 'nobody asked: no meal log');
    assert.ok(!homeNoLog.tasks.some((x) => x.kind === 'log'), 'no "Log your meals" task');
    assert.equal((await ctx.desk('PUT', `/api/patients/${ctx.patientId}/meal-log`, { on: true })).status, 403, 'front desk cannot ask');
    const asked = ok(await ctx.doc('PUT', `/api/patients/${ctx.patientId}/meal-log`, { on: true }));
    assert.equal(asked.on, true);
    assert.equal(ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}`)).mealLog.on, true, 'the profile shows it is asked, and by whom');
    const homeLog = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.equal(homeLog.dailyLog, true);
    assert.ok(homeLog.tasks.some((x) => x.kind === 'log'), 'shown once asked');
    ok(await ctx.doc('PUT', `/api/patients/${ctx.patientId}/meal-log`, { on: false }));
    assert.equal(ok(await ctx.pat('GET', '/api/patient/home')).dailyLog, false, 'off again');
    ok(await ctx.pat('PATCH', '/api/patient/me', { settings: { reminderTimes: { morning: old }, dailyLogReminderAt: '20:00' } }));
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
    // Voice notes go into chats as audio (content-checked like every upload).
    const m4a = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypM4A '), Buffer.alloc(24)]);
    const vn = ok(await ctx.doc('POST', `/api/conversations/${ctx.convoId}/messages`, undefined, { form: fileForm('file', m4a, 'voice-note.m4a', 'audio/mp4', { durationSec: '7' }) }), 201);
    assert.equal(vn.message.kind, 'voice');
    assert.equal(vn.message.voice.durationSec, 7);
    assert.equal((await fetch(vn.message.voice.file.url)).status, 200, 'the note plays from its link');
    // The thread's patient is always the patient, even if their account was listed with another role first.
    const patUserId = (await M.Patient.findById(ctx.patientId)).userId;
    await M.Conversation.updateOne({ _id: ctx.convoId }, { $push: { participants: { $each: [{ userId: patUserId, role: 'staff' }], $position: 0 } } });
    const own = ok(await ctx.pat('POST', `/api/conversations/${ctx.convoId}/messages`, { text: 'Is it fine to walk after lunch?' }), 201);
    assert.equal(own.message.senderType, 'patient', 'shown on the patient side in every app');
    await M.Message.updateOne({ _id: own.message.id }, { senderType: 'staff' }); // an older mislabelled one
    const seen = ok(await ctx.doc('GET', `/api/conversations/${ctx.convoId}/messages`)).items.find((x) => x.id === own.message.id);
    assert.equal(seen.senderType, 'patient');
    assert.equal(seen.mine, false, "not the doctor's own");
    await M.Conversation.updateOne({ _id: ctx.convoId }, { $pull: { participants: { userId: patUserId, role: 'staff' } } });
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
    assert.equal(found.from, 'here', 'distances from the phone');
    assert.equal(found.area, 'Salt Lake', 'the area the phone is in');
    // Video only when a video consultation service exists.
    const dl = await M.DoctorLocation.findOne({ doctorId: ctx.doctorUserId });
    const hasVideo = dl.services.some((s) => s.mode === 'video');
    assert.equal(found.items[0].video, Boolean(hasVideo && (await M.DoctorProfile.findOne({ userId: ctx.doctorUserId })).offersVideo));
    // From another place the distance changes, on the list and the detail.
    const far = ok(await ctx.pat('GET', '/api/patient/doctors/search?specialty=diabetes&lat=22.62&lng=88.46'));
    assert.ok(far.items[0].km > found.items[0].km);
    assert.equal(far.area, 'New Town');
    const farDetail = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}?lat=22.62&lng=88.46`));
    assert.equal(farDetail.km, far.items[0].km, 'detail measures from the same place');
    const detail = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}`));
    assert.ok(detail.lastVisit);
    const req = ok(await ctx.pat('POST', '/api/patient/visit-requests', { doctorId: ctx.doctorUserId, visitType: 'follow_up', preferredTime: 'Thu or Fri, after 5 PM' }), 201);
    const pending = ok(await ctx.desk('GET', '/api/appointment-requests'));
    assert.ok(pending.some((x) => x.id === req.request.id));
    // The next day the clinic is open (slots follow the clinic's weekly hours: closed Sundays).
    let free;
    let slots;
    for (let i = 1; i <= 7 && !free; i += 1) {
      const date = new Date(Date.now() + i * 864e5).toISOString().slice(0, 10);
      slots = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${date}`));
      if (new Date(`${date}T12:00:00+05:30`).getUTCDay() === 0) assert.equal(slots.open, false, 'no slots on the clinic closed day');
      free = slots.slots.find((x) => x.available && !x.walkIn);
    }
    const assigned = ok(await ctx.desk('POST', `/api/appointment-requests/${req.request.id}/assign`, { startAt: free.startAt }));
    assert.equal(assigned.request.status, 'scheduled');
    const fus = ok(await ctx.doc('GET', '/api/follow-ups'));
    assert.equal(fus.items[0].status, 'booked', 'booking a follow-up visit marks the follow-up booked');
    const mine = ok(await ctx.pat('GET', '/api/patient/appointments'));
    assert.equal(mine.items.length, 1);
    const moved = ok(await ctx.desk('POST', `/api/appointments/${assigned.appointment.id}/reschedule`, { startAt: slots.slots.filter((s) => s.available && !s.walkIn)[1].startAt }));
    assert.ok(moved.rescheduledFromId);
    assert.equal((await ctx.desk('POST', `/api/appointments/${moved.id}/reschedule`, { startAt: free.startAt, locationId: '000000000000000000000000' })).status, 400, "only this clinic's branches");
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
    // The patient's own copy; someone else's prescription id is not found.
    assert.match(ok(await ctx.pat('GET', `/api/patient/prescriptions/${ctx.rxId}/pdf`)).url, /\/files\//);
    assert.equal((await ctx.pat('GET', '/api/patient/prescriptions/000000000000000000000000/pdf')).status, 404);
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
    // The cart lists the prescriptions that can go with it and what each covers.
    const withRx = ok(await ctx.pat('GET', '/api/patient/cart'));
    const rx0 = withRx.prescriptions.find((p) => p.kind === 'digital');
    assert.ok(rx0, "the doctor's prescription is offered");
    assert.deepEqual(rx0.covers, [withRx.items[0].name], 'it lists the Metformin in the cart');
    assert.deepEqual(withRx.uncovered, [], 'every cart medicine is covered');
    const order = ok(await ctx.pat('POST', '/api/patient/orders', { pharmacyId: quotes.items[0].pharmacy.id, mode: 'delivery', attach: [String(rx0.id)] }), 201);
    assert.deepEqual(order.prescriptionIds.map(String), [String(rx0.id)], 'only the ticked prescription goes with it');
    assert.equal(order.status, 'placed');
    assert.equal(ok(await ctx.pat('GET', '/api/patient/cart')).count, 0);
    assert.ok(order.prescriptionIds.length > 0, 'valid prescriptions go with the order');

    // The pharmacy works the order from its private link (token sent by WhatsApp / email).
    const { sha256 } = require('../src/lib/security');
    await M.Order.updateOne({ _id: order.id }, { pharmacyTokenHash: sha256('pharmacy-test-token') });
    assert.equal((await fetch(`${base}/pharmacy/orders/${order.id}?t=wrong`)).status, 404, 'the link needs its token');
    const page = await fetch(`${base}/pharmacy/orders/${order.id}?t=pharmacy-test-token`);
    assert.equal(page.status, 200);
    const html = await page.text();
    assert.match(html, /Priya Sharma/);
    assert.match(html, /Rx \d{4}/, 'the prescription is shown to the pharmacy');
    const course = await M.MedicationCourse.findOne({ patientId: ctx.patientId, name: 'Metformin' });
    const stockBefore = course.stockUnits || 0;
    for (const status of ['confirmed', 'packed', 'out_for_delivery', 'delivered']) {
      const r = await fetch(`${base}/pharmacy/orders/${order.id}/status`, { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `t=pharmacy-test-token&status=${status}` });
      assert.equal(r.status, 303, `pharmacy sets ${status}`);
    }
    const delivered = (ok(await ctx.pat('GET', '/api/patient/orders')))[0];
    assert.equal(delivered.status, 'delivered');
    assert.equal((await M.MedicationCourse.findById(course._id)).stockUnits, stockBefore + 6 * 10, 'stock goes up by what was delivered');
    assert.ok((await M.Notification.find({ userId: (await M.Patient.findById(ctx.patientId)).userId, type: 'order_update' })).length >= 4, 'the patient hears each step');
    const skip = await fetch(`${base}/pharmacy/orders/${order.id}/status`, { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 't=pharmacy-test-token&status=confirmed' });
    assert.equal(skip.status, 409, 'no going back after delivery');
    // A second order the patient cancels.
    ok(await ctx.pat('POST', '/api/patient/cart/items', { courseId: course._id, packOption: '1_month' }), 201);
    const second = ok(await ctx.pat('POST', '/api/patient/orders', { pharmacyId: quotes.items[0].pharmacy.id, mode: 'pickup' }), 201);
    assert.equal(ok(await ctx.pat('POST', `/api/patient/orders/${second.id}/cancel`)).status, 'cancelled');

    // Pay online in the app (Razorpay Checkout): start → Checkout → confirm. No keys here: test mode.
    ok(await ctx.pat('POST', '/api/patient/cart/items', { courseId: course._id, packOption: '1_month' }), 201);
    const third = ok(await ctx.pat('POST', '/api/patient/orders', { pharmacyId: quotes.items[0].pharmacy.id, mode: 'pickup', payOnline: true }), 201);
    assert.equal(third.payment, 'online');
    const co = ok(await ctx.pat('POST', '/api/patient/checkout', { kind: 'order', id: third.id }));
    assert.deepEqual([co.test, co.amount, co.currency, co.title], [true, third.total, 'INR', 'Medicines']);
    assert.equal(co.prefill.contact, '+919230592842');
    const forged = await ctx.pat('POST', '/api/patient/checkout/confirm', { kind: 'order', id: third.id, orderId: 'order_someone_else' });
    assert.deepEqual([forged.status, forged.body.error.code], [400, 'BAD_SIGNATURE']);
    const done = ok(await ctx.pat('POST', '/api/patient/checkout/confirm', { kind: 'order', id: third.id, orderId: co.orderId }));
    assert.equal(done.paid, true);
    assert.equal(ok(await ctx.pat('POST', '/api/patient/checkout/confirm', { kind: 'order', id: third.id, orderId: co.orderId })).already, true, 'confirming twice is fine');
    assert.equal((await ctx.pat('POST', '/api/patient/checkout', { kind: 'order', id: third.id })).status, 409, 'nothing left to pay');
    const paidOrder = await M.Order.findById(third.id);
    assert.equal(paidOrder.pay.status, 'paid');
    await M.Order.updateOne({ _id: third.id }, { pharmacyTokenHash: sha256('pharmacy-test-token-2') });
    assert.match(await (await fetch(`${base}/pharmacy/orders/${third.id}?t=pharmacy-test-token-2`)).text(), /Paid online/);
    assert.equal((await ctx.pat('POST', `/api/patient/orders/${third.id}/pay`)).status, 409, 'already paid');
    ok(await ctx.pat('POST', `/api/patient/orders/${third.id}/cancel`));
    assert.equal((await M.Order.findById(third.id)).pay.status, 'refunded', 'a paid order that is cancelled is refunded');

    {
      const checkout = require('../src/services/checkout');
      const saved = { ...env.razorpay };
      const realFetch = checkout.fetchImpl;
      Object.assign(env.razorpay, { keyId: 'rzp_test_key', keySecret: 'test_secret' });
      let created = 0;
      checkout.fetchImpl = async (url, opts) => {
        assert.equal(url, 'https://api.razorpay.com/v1/orders');
        const body = JSON.parse(opts.body);
        created += 1;
        return { ok: true, status: 200, json: async () => ({ id: 'order_RZP123', amount: body.amount, notes: body.notes }) };
      };
      try {
        ok(await ctx.pat('POST', '/api/patient/cart/items', { courseId: course._id, packOption: '1_month' }), 201);
        const fourth = ok(await ctx.pat('POST', '/api/patient/orders', { pharmacyId: quotes.items[0].pharmacy.id, mode: 'pickup', payOnline: true }), 201);
        const live = ok(await ctx.pat('POST', '/api/patient/checkout', { kind: 'order', id: fourth.id }));
        assert.deepEqual([live.test, live.keyId, live.orderId], [false, 'rzp_test_key', 'order_RZP123']);
        ok(await ctx.pat('POST', '/api/patient/checkout', { kind: 'order', id: fourth.id }));
        assert.equal(created, 1, 'a second try reuses the Razorpay order');
        const bad = await ctx.pat('POST', '/api/patient/checkout/confirm', { kind: 'order', id: fourth.id, orderId: 'order_RZP123', paymentId: 'pay_1', signature: 'x'.repeat(64) });
        assert.equal(bad.body.error.code, 'BAD_SIGNATURE', 'a made-up signature is refused');
        assert.notEqual((await M.Order.findById(fourth.id)).pay.status, 'paid');
        const sig = require('crypto').createHmac('sha256', 'test_secret').update('order_RZP123|pay_1').digest('hex');
        const good = ok(await ctx.pat('POST', '/api/patient/checkout/confirm', { kind: 'order', id: fourth.id, orderId: 'order_RZP123', paymentId: 'pay_1', signature: sig }));
        assert.deepEqual([good.paid, good.paymentId], [true, 'pay_1']);
        const o4 = await M.Order.findById(fourth.id);
        assert.deepEqual([o4.pay.status, o4.pay.razorpayPaymentId], ['paid', 'pay_1']);
      } finally {
        Object.assign(env.razorpay, saved);
        checkout.fetchImpl = realFetch;
      }
    }

    // An uploaded prescription's medicines (read by AI) are added when the patient says so.
    const rec = await M.MedicalRecord.create({
      patientId: ctx.patientId, kind: 'prescription', title: 'Paper prescription', origin: 'uploaded_by_patient', recordDate: new Date(),
      extractedDoctor: 'Dr. Outside', extractedMedicines: [{ name: 'Atorvastatin', strength: '10 mg', morning: 0, afternoon: 0, night: 1, food: 'after_food', duration_days: 30, instructions: '' }],
    });
    const list = ok(await ctx.pat('GET', '/api/patient/medicines'));
    assert.ok(list.fromUploads.some((u) => String(u.recordId) === String(rec._id)), 'suggested from the upload');
    const added = ok(await ctx.pat('POST', `/api/patient/records/${rec._id}/add-medicines`, {}), 201);
    assert.equal(added.added, 1);
    assert.ok(ok(await ctx.pat('GET', '/api/patient/medicines')).items.some((m) => m.name === 'Atorvastatin'));
    assert.ok(!ok(await ctx.pat('GET', '/api/patient/medicines')).fromUploads.some((u) => String(u.recordId) === String(rec._id)), 'not suggested again');
  });

  await step('consent code links the patient to a second practice', async () => {
    const s = await login('9811122233');
    const doc2 = api(s.accessToken);
    ok(await doc2('POST', '/api/me/practices', { name: 'Heart Point', doctorName: 'Dr. Rina Mitra' }), 201);
    assert.equal((await doc2('GET', `/api/patients/${ctx.patientId}`)).status, 404, 'not linked yet');
    const code = ok(await ctx.pat('POST', '/api/patient/consent-code'));
    assert.equal((await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: '000000' === code.code ? '111111' : '000000' })).status, 400);
    assert.equal(ok(await ctx.pat('GET', `/api/patient/consent-code/${code.id}`)).status, 'active');
    assert.ok(new Date(code.expiresAt) - Date.now() > 4 * 60 * 1000, 'valid about 5 minutes');
    ok(await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: code.display }));
    ok(await doc2('GET', `/api/patients/${ctx.patientId}`));
    const used = ok(await ctx.pat('GET', `/api/patient/consent-code/${code.id}`));
    assert.equal(used.status, 'used');
    assert.equal(used.practice, 'Heart Point', 'the app says which clinic used it');
    assert.equal((await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: code.code })).status, 400, 'codes are single-use');
    // 5 wrong tries cancel a code, even the right one after.
    const c2 = ok(await ctx.pat('POST', '/api/patient/consent-code'));
    const wrong = c2.code === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) assert.equal((await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: wrong })).status, 400);
    assert.equal((await doc2('POST', '/api/patients/link', { phone: '9230592842', consentCode: c2.code })).status, 400, 'cancelled after 5 wrong tries');
    assert.equal(ok(await ctx.pat('GET', `/api/patient/consent-code/${c2.id}`)).status, 'expired');
    ctx.doc2 = doc2;
    ctx.doc2Id = s.user.id;
  });

  await step('privacy: the patient decides what another clinic sees', async () => {
    const count = async (path) => {
      const b = ok(await ctx.doc2('GET', path));
      return Array.isArray(b) ? b.length : (b.items || []).length;
    };
    const paths = [`/api/patients/${ctx.patientId}/prescriptions`, `/api/patients/${ctx.patientId}/records`, `/api/patients/${ctx.patientId}/lab-results`, `/api/patients/${ctx.patientId}/vitals`];
    const shared = [];
    for (const path of paths) shared.push(await count(path));
    assert.ok(shared[0] > 0, 'with the consent code the new clinic sees the first clinic\'s prescriptions');
    // The patient sets the new clinic's doctor to "Not shared".
    ok(await ctx.pat('PATCH', `/api/patient/care-team/${ctx.doc2Id}`, { accessLevel: 'not_shared' }));
    for (const path of paths) assert.equal(await count(path), 0, `not shared: ${path} hides the other clinic's data`);
    const prof = ok(await ctx.doc2('GET', `/api/patients/${ctx.patientId}`));
    assert.equal(prof.accessLevel, 'not_shared');
    assert.equal(prof.currentMedicines.length, 0, 'medicines from the other clinic are hidden');
    assert.equal(prof.latestVitals, null, 'vitals from the other clinic are hidden');
    assert.ok(prof.allergies.length > 0, 'allergies stay visible for safety');
    // The first clinic keeps seeing its own records.
    assert.ok((ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}/prescriptions`)).items || []).length > 0, 'a clinic always sees its own prescriptions');
    // Prescriptions and tests only.
    ok(await ctx.pat('PATCH', `/api/patient/care-team/${ctx.doc2Id}`, { accessLevel: 'prescriptions_and_tests' }));
    assert.ok(await count(paths[0]) > 0, 'prescriptions visible again');
    assert.equal(await count(paths[3]), 0, 'clinic vitals still hidden at prescriptions-and-tests');
    ok(await ctx.pat('PATCH', `/api/patient/care-team/${ctx.doc2Id}`, { accessLevel: 'full_record' }));
  });

  await step('roles: each staff role can only do its job', async () => {
    // Front desk: no clinical alerts, consult drafts, lab review, AI, reports or exports.
    for (const [method, path] of [['GET', '/api/alerts'], ['GET', '/api/consultations/pick'], ['GET', '/api/ai/sessions'], ['GET', '/api/reports/summary'], ['GET', '/api/inbox/reviews'], ['GET', '/api/dashboard']]) {
      assert.equal((await ctx.desk(method, path)).status, 403, `front desk blocked: ${path}`);
    }
    ok(await ctx.desk('GET', '/api/payments'));
    ok(await ctx.desk('GET', '/api/inbox?type=all'));
    // Add a lab technician (phone + code): can enter results, nothing else clinical.
    const sent = ok(await ctx.doc('POST', '/api/members/phone-otp', { phone: '9811100077' }));
    ok(await ctx.doc('POST', '/api/members', { role: 'lab_technician', name: 'Lab Tech', phone: '9811100077', allLocations: true, otpCode: sent.devCode }), 201);
    const s = await login('9811100077');
    assert.equal(s.landing, 'Staff-Today', 'lab roles use the desk panel, not the doctor dashboard');
    const lab = api(s.accessToken);
    ok(await lab('POST', `/api/patients/${ctx.patientId}/lab-results`, { testName: 'Fasting sugar', collectedAt: '2026-10-01', values: [{ analyte: 'Glucose', value: 98, unit: 'mg/dL', flag: 'normal' }] }), 201);
    for (const path of ['/api/reports/summary', '/api/billing', '/api/ai/sessions', '/api/alerts', '/api/inbox?type=all', '/api/payments']) {
      assert.equal((await lab('GET', path)).status, 403, `lab technician blocked: ${path}`);
    }
    assert.equal((await lab('POST', '/api/exports', { kind: 'appointment_history', format: 'csv', includeMobiles: true })).status, 403);
    // Uploads are checked by content: a program renamed .png is refused.
    const fd = new FormData();
    fd.append('file', new Blob([Buffer.from('MZ fake program, not an image')], { type: 'image/png' }), 'photo.png');
    const up = await fetch(`${base}/api/doctor/profile/photo`, { method: 'POST', headers: { authorization: `Bearer ${ctx.docToken}` }, body: fd });
    assert.equal(up.status, 400, 'fake image rejected');
    assert.equal((await up.json()).error.code, 'BAD_FILE_TYPE');
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
    const after = ok(await ctx.doc('GET', '/api/reports/summary?range=30_days'));
    assert.equal(after.kpis.feesCollected.value, fees.collected, 'the Reports card and Fees report agree');
    // Filters apply to every card (a location with no visits → all zero).
    const none = ok(await ctx.doc('GET', '/api/reports/summary?range=30_days&locationIds=000000000000000000000000'));
    assert.equal(none.kpis.consultations.value, 0);
    assert.equal(none.kpis.prescriptions.value, 0, 'prescriptions follow the location filter');
    assert.equal(none.kpis.feesCollected.value, 0, 'fees follow the location filter');
    assert.equal(ok(await ctx.doc('GET', '/api/reports/fees?locationIds=000000000000000000000000')).collected, 0);
    // A visit still "booked" after its day ended counts as missed.
    const T = require('../src/lib/time');
    const seen = await M.Appointment.findOne({ practiceId: ctx.practiceId, status: 'completed' }).lean();
    const yesterday = T.addDays(T.dayStart(), -1);
    const noShow = await M.Appointment.create({
      practiceId: ctx.practiceId, locationId: seen.locationId, doctorId: seen.doctorId, patientId: seen.patientId,
      date: yesterday, startAt: T.atMinute(yesterday, 11 * 60), endAt: T.atMinute(yesterday, 11 * 60 + 10), tokenNo: 99, status: 'booked', visitType: 'follow_up', mode: seen.mode,
    });
    const withMissed = ok(await ctx.doc('GET', '/api/reports/summary?range=30_days'));
    assert.equal(withMissed.kpis.missed.value, after.kpis.missed.value + 1, 'booked and never came = missed');
    // The nightly check marks it missed, so History shows it too (counted once).
    await require('../src/services/jobs').noShows(new Date());
    assert.equal((await M.Appointment.findById(noShow._id)).status, 'missed');
    const hist = ok(await ctx.doc('GET', `/api/history?from=${T.dayKey(yesterday)}`));
    assert.ok(hist.items.some((x) => x.id === String(noShow._id) && x.status === 'missed'), 'History lists the no-show as missed');
    assert.equal(ok(await ctx.doc('GET', '/api/reports/summary?range=30_days')).kpis.missed.value, withMissed.kpis.missed.value);
    await M.Appointment.deleteOne({ _id: noShow._id });
    // Referrals: added with the patient's location, filtered by it, cancelled; a received one is
    // seen once the patient has a completed visit here.
    const sentRef = ok(await ctx.doc('POST', '/api/referrals', { patientId: ctx.patientId, direction: 'sent', counterpartName: 'Eye clinic', specialty: 'Ophthalmology', reason: 'Diabetic eye check' }), 201);
    assert.ok(sentRef.locationId, 'location from the latest visit');
    assert.equal((await ctx.doc('POST', '/api/referrals', { patientId: ctx.patientId, direction: 'sent', counterpartName: '  ' })).status, 400);
    const sentList = ok(await ctx.doc('GET', `/api/referrals?direction=sent&range=30_days&locationIds=${sentRef.locationId}`));
    assert.ok(sentList.items.some((x) => x.id === sentRef.id));
    assert.equal(ok(await ctx.doc('GET', '/api/referrals?direction=sent&locationIds=000000000000000000000000')).items.length, 0, 'location filter applies');
    ok(await ctx.doc('POST', `/api/referrals/${sentRef.id}/cancel`));
    assert.equal((await ctx.doc('POST', `/api/referrals/${sentRef.id}/seen`)).status, 409, 'a cancelled referral cannot be seen');
    const recv = await M.Referral.create({ practiceId: ctx.practiceId, patientId: ctx.patientId, doctorId: ctx.doctorUserId, direction: 'received', counterpartName: 'Dr. Lahiri', referredAt: new Date(Date.now() - 40 * 864e5) });
    const recvList = ok(await ctx.doc('GET', '/api/referrals?direction=received'));
    assert.equal(recvList.items.find((x) => x.id === String(recv._id)).status, 'seen', 'seen after the patient came in');
    ok(await ctx.doc('GET', '/api/reports/prescriptions'));
    ok(await ctx.doc('GET', '/api/reports/follow-ups'));
    ok(await ctx.doc('GET', '/api/reports/daily'));
    const dash = ok(await ctx.doc('GET', '/api/dashboard'));
    assert.equal(dash.greetingName, 'Dr. Arjun Sen');
    ok(await ctx.doc('GET', '/api/dashboard/cards'));
    ok(await ctx.doc('GET', '/api/history?period=this_month'));
  });

  await step('billing limits and exports', async () => {
    // Email a report: no address → asked for; with one but email not set up → says so (and the file is still made).
    const noMail = ok(await ctx.doc('POST', '/api/exports', { kind: 'report', reportType: 'referrals', format: 'pdf', emailCopy: true, filters: {} }), 201);
    assert.equal(noMail.emailMissing, true);
    assert.ok(noMail.url);
    assert.equal((await ctx.doc('PATCH', '/api/me', { email: 'not-an-email' })).status, 400);
    ok(await ctx.doc('PATCH', '/api/me', { email: 'doctor@example.com' }));
    const notSetUp = ok(await ctx.doc('POST', '/api/exports', { kind: 'report', reportType: 'referrals', format: 'pdf', emailCopy: true, filters: {} }), 201);
    assert.equal(notSetUp.emailMissing, false);
    assert.equal(notSetUp.emailNotSetUp, true);
    assert.equal(notSetUp.emailed, false);
    const b = ok(await ctx.doc('GET', '/api/billing'));
    assert.equal(b.usage.seats.used, 3, 'doctor, front desk, lab technician');
    ok(await ctx.doc('POST', '/api/billing/switch', { planKey: 'clinic' }));
    assert.equal((await ctx.desk('POST', '/api/billing/switch', { planKey: 'starter' })).status, 403, 'owner only');
    for (const format of ['csv', 'xlsx', 'pdf', 'json']) {
      const job = ok(await ctx.doc('POST', '/api/exports', { kind: 'appointment_history', format, filters: { from: '2026-01-01' } }), 201);
      assert.equal(job.status, 'done');
      assert.equal((await fetch(job.url)).status, 200);
    }
    assert.equal((await ctx.desk('POST', '/api/exports', { kind: 'data_export', format: 'csv', datasets: ['patients'] })).status, 403, 'front desk cannot export patient data');
    // Each report download has its own rows (not the consultations register).
    for (const [type, key] of [['fees', 'fees'], ['follow_ups', 'follow_ups'], ['referrals', 'referrals'], ['daily', 'daily'], ['prescriptions', 'prescriptions'], ['consultations', 'consultations']]) {
      const job = ok(await ctx.doc('POST', '/api/exports', { kind: 'report', reportType: type, format: 'json', filters: { from: '2026-01-01' } }), 201);
      const data = await (await fetch(job.url)).json();
      assert.deepEqual(Object.keys(data), [key], `${type} export has its own data`);
      assert.equal(job.emailed, false);
    }
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

  await step('reminders and notifications go to the right people, once', async () => {
    const jobs = require('../src/services/jobs');
    const T = require('../src/lib/time');
    const patient = await M.Patient.findById(ctx.patientId);
    const kinds = async (userId) => (await M.Notification.find({ userId }).lean()).map((n) => n.type);
    // Medicine alarm at the dose time (once).
    const course = await M.MedicationCourse.findOne({ patientId: patient._id, status: 'active' });
    const now = new Date();
    const dose = await M.DoseLog.create({ courseId: course._id, patientId: patient._id, scheduledAt: new Date(now.getTime() - 20000), slot: 'morning', status: 'due' });
    await jobs.doseReminders(now, new Date(now.getTime() - 60000));
    await jobs.doseReminders(now, new Date(now.getTime() - 60000));
    const doseNotes = await M.Notification.find({ userId: patient.userId, type: 'dose_reminder', 'params.doseId': dose._id });
    assert.equal(doseNotes.length, 1, 'one alarm per dose, never twice');
    assert.match(doseNotes[0].title, new RegExp(course.name));
    // Low stock (once a day).
    course.stockUnits = 2;
    await course.save();
    const tenAm = T.atMinute(new Date(), 600);
    await jobs.lowStock(tenAm);
    await jobs.lowStock(tenAm);
    assert.equal((await kinds(patient.userId)).filter((k) => k === 'low_stock').length, 1, 'low-stock warning once a day');
    // Visit reminder 24 h before.
    const appt = await M.Appointment.findOne({ patientId: patient._id }).sort({ startAt: -1 });
    appt.status = 'booked';
    appt.startAt = new Date(now.getTime() + 24 * 3600e3 - 120000);
    await appt.save();
    await jobs.visitReminders(now);
    assert.ok((await kinds(patient.userId)).includes('visit_reminder'), 'visit reminder sent a day before');
    // Daily summary at 20:00 for the doctor.
    await jobs.dailyDigest(T.atMinute(new Date(), 20 * 60 + 5));
    // An emergency reaches the patient's doctor, not the front desk.
    const deskUser = (await M.Member.findOne({ practiceId: ctx.practiceId, role: 'front_desk' })).userId;
    const before = await M.Notification.countDocuments({ userId: deskUser, type: /alert_/ });
    ok(await ctx.pat('POST', '/api/patient/urgent', { doctorId: ctx.doctorUserId, text: 'Chest pain since morning' }), 201);
    await new Promise((r) => setTimeout(r, 300));
    assert.equal(await M.Notification.countDocuments({ userId: deskUser, type: /alert_/ }), before, 'front desk does not get clinical alerts');
    assert.ok((await kinds(ctx.doctorUserId)).some((k) => /alert_emergency|urgent_message/.test(k)), "the patient's doctor is alerted");
  });

  await step("prescription in the patient's language", async () => {
    const rx = await M.Prescription.findOne({ patientId: ctx.patientId, kind: 'digital', consultationId: { $ne: null } });
    assert.ok(rx, 'the patient has a digital prescription');
    const id = String(rx._id);
    const en = ok(await ctx.pat('GET', `/api/patient/prescriptions/${id}/pdf`));
    const bn = ok(await ctx.pat('GET', `/api/patient/prescriptions/${id}/pdf?lang=bn`));
    assert.equal(bn.lang, 'bn');
    assert.notEqual(bn.key, en.key, 'a separate Bengali file');
    assert.match(bn.name, /বাংলা/);
    const again = ok(await ctx.pat('GET', `/api/patient/prescriptions/${id}/pdf?lang=bn`));
    assert.equal(again.key, bn.key, 'kept and reused');
    assert.equal(ok(await ctx.pat('GET', `/api/patient/prescriptions/${id}/pdf?lang=xx`)).lang, 'en');
  });

  await step('AI endpoints respond without a key (graceful fallback)', async () => {
    // Speak-to-type: medicine names heard wrong are matched to the catalog (AI is off in tests).
    const ph = ok(await ctx.doc('GET', '/api/me/voice/phrases'));
    assert.ok(ph.phrases.includes('Metformin'));
    const fixed = ok(await ctx.doc('POST', '/api/me/voice/clean', { text: 'met for min 500 twice daily after food', purpose: 'medicine' }));
    assert.equal(fixed.text, 'Metformin 500 twice daily after food');
    assert.equal(fixed.source, 'catalog');
    const kept = ok(await ctx.pat('POST', '/api/me/voice/clean', { text: 'skin doctor near me', purpose: 'symptoms' }));
    assert.equal(kept.text, 'skin doctor near me', 'nothing changed when nothing was misheard');
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
    assert.equal(pay.payout.bankName, 'HDFC Bank', 'bank name comes from the IFSC');
    assert.equal(pay.payout.bankBranch, 'Salt Lake, Kolkata');
    // Lookups for the form, and a code that doesn't exist.
    const ifsc = ok(await ctx.doc('GET', '/api/banks/ifsc/hdfc0001234'));
    assert.deepEqual([ifsc.found, ifsc.bank, ifsc.branch, ifsc.city], [true, 'HDFC Bank', 'Salt Lake', 'Kolkata']);
    assert.equal(ok(await ctx.doc('GET', '/api/banks/ifsc/SBIN0999999')).found, false);
    assert.equal(ok(await ctx.doc('GET', '/api/banks/ifsc/XYZ')).valid, false);
    const missing = await ctx.doc('PATCH', '/api/doctor/profile', { payout: { ifsc: 'SBIN0999999' } });
    assert.deepEqual([missing.status, missing.body.error.code], [400, 'IFSC_NOT_FOUND']);
    const upi = ok(await ctx.doc('GET', '/api/banks/upi?vpa=tanmoy.d@oksbi'));
    assert.deepEqual([upi.valid, upi.app, upi.bank], [true, 'Google Pay', null], "a payment app's handle doesn't name the person's bank");
    assert.equal(upi.checked, false, 'no Razorpay keys: the name check is off');
    const own = ok(await ctx.doc('GET', '/api/banks/upi?vpa=tanmoy.d@sbi'));
    assert.deepEqual([own.app, own.bank], ['SBI YONO', 'State Bank of India'], "a bank's own handle does");
    // With Razorpay keys: the UPI ID is checked and the name on it returned.
    const banks = require('../src/services/banks');
    const saved = { ...env.razorpay };
    const realFetch = banks.fetchImpl;
    Object.assign(env.razorpay, { keyId: 'rzp_test_x', keySecret: 'y' });
    banks.fetchImpl = async (url, opts) => {
      assert.match(url, /validate\/vpa$/);
      const { vpa } = JSON.parse(opts.body);
      return vpa.startsWith('ghost')
        ? { ok: false, status: 400, json: async () => ({ success: false }) }
        : { ok: true, status: 200, json: async () => ({ vpa, success: true, customer_name: 'TANMOY DAS' }) };
    };
    try {
      const named = ok(await ctx.doc('GET', '/api/banks/upi?vpa=tanmoydas5242@oksbi'));
      assert.deepEqual([named.checked, named.exists, named.name], [true, true, 'TANMOY DAS']);
      const ghost = ok(await ctx.doc('GET', '/api/banks/upi?vpa=ghost@oksbi'));
      assert.deepEqual([ghost.checked, ghost.exists], [true, false]);
    } finally {
      Object.assign(env.razorpay, saved);
      banks.fetchImpl = realFetch;
    }
    assert.equal(ok(await ctx.doc('GET', '/api/banks/upi?vpa=nope')).valid, false);
    assert.equal(ok(await ctx.doc('GET', '/api/banks/upi?vpa=me@newbankx')).known, false, 'unknown handles are allowed but flagged');
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

  await step('maps, payments, walk-ins, health score, device sync, proofs', async () => {
    // Map: coordinates from a pasted Google Maps link; bad points are ignored.
    const loc = ok(await ctx.doc('PATCH', `/api/locations/${ctx.locationId}`, { googleMapsUrl: 'https://www.google.com/maps/place/City+Care/@22.5867,88.4171,17z' }));
    assert.deepEqual(loc.geo.coordinates, [88.4171, 22.5867]);
    // Only Google Maps links are accepted; a pin without a link gets one made from it.
    assert.equal((await ctx.doc('PATCH', `/api/locations/${ctx.locationId}`, { googleMapsUrl: 'https://example.com/where' })).body.error.code, 'BAD_MAPS_LINK');
    const pinned = ok(await ctx.doc('PATCH', `/api/locations/${ctx.locationId}`, { googleMapsUrl: '', lat: 22.5871, lng: 88.4175 }));
    assert.equal(pinned.googleMapsUrl, 'https://www.google.com/maps/search/?api=1&query=22.5871,88.4175');
    assert.equal((await ctx.doc('GET', '/api/geo/search?q=ab')).body.error.code, 'QUERY_TOO_SHORT');
    // Letterhead logo on a black background → transparent PNG.
    const logoJpg = await require('sharp')(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="300" height="300"><rect width="300" height="300" fill="#000"/><path d="M60 250 L150 40 L240 250 Z" fill="#1d7ea6"/></svg>')).jpeg().toBuffer();
    const logo = ok(await ctx.doc('POST', `/api/locations/${ctx.locationId}/logo`, undefined, { form: fileForm('file', logoJpg, 'logo.jpg', 'image/jpeg') }));
    assert.equal(logo.backgroundRemoved, true);
    assert.equal(logo.logo.mimeType, 'image/png');
    assert.equal((await require('sharp')(Buffer.from(await (await fetch(logo.logo.url)).arrayBuffer())).metadata()).hasAlpha, true);
    ok(await ctx.pat('PATCH', '/api/patient/me', { lat: 'x', lng: 91 }));
    ok(await ctx.pat('PATCH', '/api/patient/me', { lat: 22.58, lng: 88.43 }));
    const found = ok(await ctx.pat('GET', '/api/patient/doctors/search'));
    const card = found.items.find((d) => String(d.doctorId) === String(ctx.doctorUserId));
    assert.ok(card && card.km != null && card.km < 5, 'distance from the patient to the clinic');
    const detail = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}`));
    assert.ok(detail.places.some((x) => x.lat === 22.5871), 'directions get the clinic pin');
    assert.equal((await ctx.doc('PATCH', '/api/doctor/profile', { hprId: 'nope' })).status, 400, 'HPR ID format is checked');

    // Walk-in: straight into today's queue with a token; not twice.
    const walk = ok(await ctx.doc('POST', '/api/appointments/walk-in', { patientId: ctx.patientId }), 201);
    assert.equal(walk.status, 'waiting');
    assert.ok(walk.tokenNo >= 1);
    assert.equal((await ctx.doc('POST', '/api/appointments/walk-in', { patientId: ctx.patientId })).body.error.code, 'ALREADY_TODAY');

    // Pay the visit fee in the app (Checkout; test mode without keys). The desk's
    // payment link still works too (checked on its own page).
    const fee = await M.Payment.findOne({ appointmentId: walk.id, status: 'pending' });
    assert.ok(fee, 'the walk-in has a fee to pay');
    {
      const link = ok(await ctx.pat('POST', `/api/patient/appointments/${walk.id}/pay`));
      assert.equal((await fetch(link.url)).status, 200, 'the payment link page opens');
      const co = ok(await ctx.pat('POST', '/api/patient/checkout', { kind: 'fee', id: walk.id }));
      assert.deepEqual([co.title, co.amount], ['Consultation fee', fee.amount]);
      assert.match(co.detail, /Dr\./, 'shows the doctor');
      ok(await ctx.pat('POST', '/api/patient/checkout/confirm', { kind: 'fee', id: walk.id, orderId: co.orderId }));
      assert.equal((await M.Appointment.findById(walk.id)).feeStatus, 'paid');
      assert.equal((await M.Payment.findById(fee._id)).method, 'online');
      assert.equal((await ctx.pat('POST', `/api/patient/appointments/${walk.id}/pay`)).status, 409, 'nothing left to pay');
      // Payouts: after the 2-day hold the weekly run bundles the doctor's online fees.
      await M.Payment.updateOne({ _id: fee._id }, { paidAt: new Date(Date.now() - 3 * 864e5) });
      const before = ok(await ctx.doc('GET', '/api/doctor/payouts'));
      assert.ok(before.waiting.amount >= fee.amount, 'the fee waits for the next payout');
      const made = await require('../src/services/payouts').run(new Date());
      const mineOut = made.find((x) => String(x.doctorId) === String(ctx.doctorUserId));
      assert.ok(mineOut, 'a payout for the doctor');
      assert.equal(mineOut.status, 'pending', 'waits until RazorpayX is set up');
      assert.equal(mineOut.destination, 'arjun@okhdfc');
      const after = ok(await ctx.doc('GET', '/api/doctor/payouts'));
      assert.equal(after.items[0].status, 'pending');
      assert.ok(after.waiting.amount < before.waiting.amount, 'no longer waiting');
      assert.equal((await require('../src/services/payouts').run(new Date())).length, 0, 'never paid twice');
    }

    // Setup checklist for a doctor; Home health score and summary; device readings once only.
    const day = new Date().toISOString().slice(0, 10);
    const at = new Date(Date.now() - 3600e3).toISOString();
    const sync = { source: 'Health Connect', days: [{ date: day, steps: 6400 }], readings: [{ kind: 'pulse', at, value: 72 }, { kind: 'bp', at, value: 128, value2: 82 }, { kind: 'spo2', at, value: 300 }] };
    const first = ok(await ctx.pat('POST', '/api/patient/device-sync', sync));
    assert.equal(first.readings, 2, 'an impossible SpO2 is skipped');
    const again = ok(await ctx.pat('POST', '/api/patient/device-sync', sync));
    assert.equal(again.readings, 0, 'the same readings are not added twice');
    assert.equal(await M.HealthLog.countDocuments({ patientId: ctx.patientId, type: 'steps', fromDevice: true }), 1);
    const score = ok(await ctx.pat('GET', '/api/patient/health-score'));
    assert.ok(score.parts.length >= 1);
    assert.ok(score.value == null || (score.value >= 0 && score.value <= 100));
    const summary = ok(await ctx.pat('GET', '/api/patient/health-summary'));
    assert.ok(summary.body.length > 10, 'a summary even without AI');
    const home = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.ok(home.deviceSync?.at, 'Home shows the last sync');
    assert.deepEqual([home.deviceSync.readings, home.deviceSync.stepDays], [0, 1], 'the last sync says what it brought in');
    assert.ok(!home.deviceSync.devices?.watch?.at, 'no watch app in the data: not connected');
    ok(await ctx.pat('POST', '/api/patient/device-sync', { source: 'Health Connect', days: [], readings: [], origins: ['com.android.healthconnect.controller', 'com.mi.health'] }));
    const dev = ok(await ctx.pat('GET', '/api/patient/home')).deviceSync.devices;
    assert.deepEqual(dev.watch.apps, ['Mi Fitness'], 'a watch app counts as a watch');
    assert.ok(!dev.ring?.at, 'no ring');
    // Steps counted by the phone itself (no watch): shown as "counted by your phone".
    ok(await ctx.pat('POST', '/api/patient/device-sync', { source: 'Phone', stepSource: 'phone', days: [{ date: day, steps: 7100, source: 'phone' }], readings: [] }));
    const home2 = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.deepEqual([home2.steps.today, home2.steps.source], [7100, 'phone']);
    // Typed steps are the day's total: saving again replaces it, and it's never added to the phone's count.
    ok(await ctx.pat('POST', '/api/patient/logs', { type: 'steps', steps: 6000 }), 201);
    ok(await ctx.pat('POST', '/api/patient/logs', { type: 'steps', steps: 9000 }), 201);
    const home3 = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.deepEqual([home3.steps.today, home3.steps.source], [9000, 'manual'], 'the higher of 9000 typed and 7100 counted');
    assert.equal(await M.HealthLog.countDocuments({ patientId: ctx.patientId, type: 'steps', fromDevice: { $ne: true } }), 1, 'one typed entry per day');
    assert.equal((await ctx.pat('POST', '/api/patient/logs', { type: 'steps', steps: 999999 })).status, 400);
    // Who sees the daily log: the ticks become the setting; Home shows it; "Change" saves it.
    const opts = ok(await ctx.pat('GET', '/api/patient/logs/options'));
    const everyone = opts.shareWith.map((x) => String(x.userId));
    ok(await ctx.pat('POST', '/api/patient/logs', { type: 'steps', steps: 9100, sharedWith: everyone.join(',') }), 201);
    assert.equal(ok(await ctx.pat('GET', '/api/patient/home')).logSharedWith.length, everyone.length, 'all ticked: all shown');
    assert.ok(ok(await ctx.pat('GET', '/api/patient/logs/options')).shareWith.every((x) => x.selected), 'the sheet starts ticked as last saved');
    ok(await ctx.pat('PUT', '/api/patient/log-sharing', { userIds: [everyone[0]] }));
    assert.deepEqual(ok(await ctx.pat('GET', '/api/patient/home')).logSharedWith.map((x) => String(x.userId)), [everyone[0]]);
    ok(await ctx.pat('PUT', '/api/patient/log-sharing', { userIds: [] }));
    assert.equal(ok(await ctx.pat('GET', '/api/patient/home')).logSharedWith.length, 0, 'private');
    // HbA1c on Home comes from lab reports.
    await M.LabResult.create({ patientId: ctx.patientId, testName: 'HbA1c', collectedAt: new Date(), values: [{ analyte: 'HbA1c', value: 7.4, unit: '%' }] });
    const tr = ok(await ctx.pat('GET', '/api/patient/home')).tracked;
    assert.equal(tr.hba1c.at(-1).value, 7.4);

    // Proof review: the signed link works, a wrong token doesn't, approving tells the doctor.
    const prof = ok(await ctx.doc('POST', '/api/doctor/qualifications', { name: 'MBBS', institution: 'Calcutta Medical College', year: 2010 }), 201);
    const q = prof.qualifications.find((x) => x.name === 'MBBS');
    ok(await ctx.doc('POST', `/api/doctor/qualifications/${q.id || q._id}/proof`, undefined, { form: fileForm('file', tinyPng(), 'mbbs.png', 'image/png') }));
    const { reviewUrl } = require('../src/services/verification');
    const url = reviewUrl(ctx.doctorUserId, q.id || q._id).replace(/^https?:\/\/[^/]+/, base);
    assert.equal((await fetch(url.replace(/t=\w+/, 't=bad'))).status, 404);
    assert.equal((await fetch(url)).status, 200);
    const t = new URL(url).searchParams.get('t');
    const decided = await fetch(url.split('?')[0], { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `t=${t}&decision=approve` });
    assert.equal(decided.status, 303);
    const after = ok(await ctx.doc('GET', '/api/doctor/profile'));
    assert.equal(after.qualifications.find((x) => x.name === 'MBBS').proofStatus, 'verified');
    // The blue tick follows the rule: registration on file and every degree verified.
    assert.equal(after.isVerified, Boolean(after.registration?.number) && after.qualifications.every((x) => x.proofStatus === 'verified'));
    const more = ok(await ctx.doc('POST', '/api/doctor/qualifications', { name: 'Fellowship', institution: 'RSSDI', year: 2015 }), 201);
    assert.equal(more.isVerified, false, 'a new degree without proof removes the tick');
    assert.equal((await M.DoctorProfile.findOne({ userId: ctx.doctorUserId })).isVerified, false);
    // The doctor's photo also shows in the app's headers (account summary).
    const me = ok(await ctx.doc('GET', '/api/me'));
    assert.ok(me.user.photoUrl, 'header photo');
  });

  await step("a doctor's status is worked out live", async () => {
    const { presenceOf } = require('../src/services/presence');
    const T = require('../src/lib/time');
    const dl = await M.DoctorLocation.findOne({ doctorId: ctx.doctorUserId, status: 'active' });
    const day = dl.schedule.week.find((w) => w.sessions?.length);
    assert.ok(day, 'the doctor has a weekly session');
    // A day ahead when the clinic is really open (no leave or closure), per the booking rules.
    const { slotsFor } = require('../src/services/scheduling');
    let d = null;
    for (let i = 3; i < 30 && !d; i += 1) {
      const c = T.addDays(T.dayStart(new Date()), i);
      if ((await slotsFor({ doctorId: ctx.doctorUserId, locationId: dl.locationId, day: c, now: new Date(0) })).open) d = c;
    }
    assert.ok(d, 'an open clinic day');
    const s = (dl.schedule.week.find((w) => w.weekday === T.weekday(d)) || day).sessions[0];
    const at = (min) => T.atMinute(d, min);
    const prof = await M.DoctorProfile.findOne({ userId: ctx.doctorUserId });
    // In a session: "In clinic · Salt Lake until …".
    // The session as it really runs (inside the clinic's opening hours).
    const dls0 = await M.DoctorLocation.find({ doctorId: ctx.doctorUserId, status: 'active' }).populate('locationId', 'name shortName status weeklyHours');
    const real = (await require('../src/services/presence').sessionsOn(ctx.doctorUserId, d, dls0))[0];
    assert.ok(real, 'a session that day');
    const inClinic = await presenceOf(prof, at(real.startMin + 10));
    assert.equal(inClinic.presence, 'in_clinic');
    assert.match(inClinic.presenceNote, / until \d{1,2}:\d{2} (AM|PM)$/);
    // 2 AM: away, with when they're next in.
    const night = await presenceOf(prof, at(2 * 60));
    assert.equal(night.presence, 'away');
    assert.match(night.presenceNote, /^Back (today|tomorrow|[A-Z][a-z]{2}) at /);
    // In reply hours, outside a session, using the app now: available.
    const free = [21 * 60 - 30, 19 * 60, 13 * 60 + 15, 8 * 60].map((m) => m).find((m) => {
      const rh = prof.chatSettings?.replyHours || { from: '09:00', to: '20:00' };
      const [fh, fm] = rh.from.split(':').map(Number);
      const [th, tm] = rh.to.split(':').map(Number);
      const inSession = real.startMin <= m && m < real.endMin;
      return m >= fh * 60 + fm && m < th * 60 + tm && !inSession;
    });
    if (free != null) {
      await M.User.updateOne({ _id: ctx.doctorUserId }, { lastActiveAt: at(free - 5) });
      assert.equal((await presenceOf(prof, at(free))).presence, 'available');
      // Not used the app for an hour: not "available".
      assert.equal((await presenceOf(prof, at(free + 60))).presence, 'away');
      // The doctor chose "Away": never shown as available.
      prof.presence = 'away';
      await M.User.updateOne({ _id: ctx.doctorUserId }, { lastActiveAt: at(free - 5) });
      assert.equal((await presenceOf(prof, at(free))).presence, 'away');
      prof.presence = 'auto';
    }
    // Reply time: the median of real replies (3 or more) to patients.
    const convo = await M.Conversation.findOne({ patientId: ctx.patientId, type: 'care' });
    const t0 = new Date(Date.now() - 3 * 3600e3);
    const rows = [];
    for (const [i, mins] of [[0, 4], [1, 6], [2, 30]]) {
      const asked = new Date(t0.getTime() + i * 40 * 60e3);
      rows.push({ conversationId: convo._id, senderType: 'patient', kind: 'text', text: `q${i}`, createdAt: asked });
      rows.push({ conversationId: convo._id, senderType: 'doctor', senderId: ctx.doctorUserId, kind: 'text', text: `a${i}`, createdAt: new Date(asked.getTime() + mins * 60e3) });
    }
    await M.Message.insertMany(rows);
    const { replyMinutes } = require('../src/services/presence');
    assert.equal(await replyMinutes(ctx.doctorUserId, new Date(Date.now() + 31 * 60e3)), 6, 'median of 4, 6 and 30 minutes');
    // Patients get the live status in Find a doctor.
    const found = ok(await ctx.pat('GET', '/api/patient/doctors/search'));
    assert.ok(['available', 'in_clinic', 'away'].includes(found.items[0].presence));
    assert.ok('presenceNote' in found.items[0]);
  });

  await step('front desk books a confirmed visit; the bell shows emergencies', async () => {
    // The earlier "sign out other devices" step ended this session; sign in again.
    await M.OtpRequest.deleteMany({ phone: '9749681391' }); // test only: skip the resend wait
    ctx.desk = api((await login('9749681391')).accessToken);
    // Pick a free time a few days ahead, as the Book appointment screen does.
    let free = null;
    for (let day = 2; day < 14 && !free; day += 1) {
      const d = new Date(Date.now() + day * 864e5).toISOString().slice(0, 10);
      free = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${d}`)).slots.find((s) => s.available && !s.walkIn);
    }
    assert.ok(free, 'a free slot exists');
    const appt = ok(await ctx.desk('POST', '/api/appointments', {
      patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: free.startAt, visitType: 'follow_up', reason: 'Sugar review', confirmed: true,
    }), 201);
    assert.equal(appt.status, 'confirmed', 'a desk booking is confirmed straight away');
    const patient = await M.Patient.findById(ctx.patientId, 'userId');
    if (patient.userId) assert.ok(await M.Notification.exists({ userId: patient.userId, type: 'appointment_booked', title: 'Visit confirmed' }), 'the patient is told');
    ok(await ctx.desk('POST', `/api/appointments/${appt.id}/cancel`, {}));

    // Bell: urgent counts only unread emergencies.
    const deskUser = ok(await ctx.desk('GET', '/api/me')).user.id;
    await M.Notification.updateMany({ userId: deskUser }, { readAt: new Date() });
    await M.Notification.create({ userId: deskUser, practiceId: ctx.practiceId, type: 'appointment_booked', title: 'Visit booked' });
    let bell = ok(await ctx.desk('GET', '/api/notifications?limit=1'));
    assert.equal(bell.unread, 1);
    assert.equal(bell.urgent, 0, 'an ordinary notification keeps the dot blue');
    await M.Notification.create({ userId: deskUser, practiceId: ctx.practiceId, type: 'alert_emergency', title: 'Emergency: Priya Sharma' });
    bell = ok(await ctx.desk('GET', '/api/notifications?limit=1'));
    assert.deepEqual([bell.unread, bell.urgent], [2, 1], 'an emergency turns it red');
    ok(await ctx.desk('POST', '/api/notifications/read-all', {}));
    bell = ok(await ctx.desk('GET', '/api/notifications?limit=1'));
    assert.deepEqual([bell.unread, bell.urgent], [0, 0], 'no dot once read');
  });

  await step('branches: each patient shows where they go; the list filters by branch', async () => {
    const list = ok(await ctx.doc('GET', '/api/patients'));
    assert.ok(list.locations.length >= 1, "the clinic's branches for the filter");
    const row = list.items.find((p) => String(p.id) === String(ctx.patientId));
    assert.ok(row.branch?.usual?.name, 'usual branch on the row');
    assert.ok(row.branch.seenAt.includes(String(row.branch.usual.id)));
    const here = ok(await ctx.doc('GET', `/api/patients?locationId=${row.branch.usual.id}`));
    assert.ok(here.items.some((p) => String(p.id) === String(ctx.patientId)), 'listed under the branch they visit');
    const none = ok(await ctx.doc('GET', '/api/patients?locationId=000000000000000000000000'));
    assert.equal(none.items.length, 0);
    const detail = ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}`));
    assert.equal(String(detail.branch.usual.id), String(row.branch.usual.id), 'same on the profile');
    const visits = ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}/visits`));
    assert.ok(visits.some((v) => v.location?.name), 'each visit names its branch');
    const enrol = await M.PatientEnrolment.findOne({ patientId: ctx.patientId });
    assert.ok(enrol.homeLocationId, 'registered at a branch');
  });

  await step('asking for a code twice quickly reuses the one just sent', async () => {
    const { issueOtp, checkOtp } = require('../src/routes/auth');
    const first = await issueOtp('9000012345', 'register');
    assert.ok(first.devCode);
    const again = await issueOtp('9000012345', 'register');
    assert.equal(again.reused, true);
    assert.ok(again.resendInSec > 0 && again.resendInSec <= 30);
    assert.equal(again.devCode, undefined, 'no new code');
    assert.equal(await checkOtp('9000012345', 'register', first.devCode), true, 'the first code still works');
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

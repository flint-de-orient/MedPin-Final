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
// Never push to real phones from tests.
env.fcm.projectId = '';
env.fcm.privateKey = '';
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
    // A sign-in that is being used doesn't run out: each refresh extends it.
    const sec = require('../src/lib/security');
    await M.AuthSession.updateOne({ tokenHash: sec.sha256(ctx.docRefresh) }, { expiresAt: new Date(Date.now() + 864e5) });
    const refreshed = ok(await api()('POST', '/api/auth/refresh', { refreshToken: ctx.docRefresh }));
    assert.ok(refreshed.accessToken);
    const slid = await M.AuthSession.findOne({ tokenHash: sec.sha256(refreshed.refreshToken) });
    assert.ok(slid.expiresAt > new Date(Date.now() + 20 * 864e5), 'refresh extends the sign-in (sliding)');
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
    // Weight from the profile becomes a reading; a newer reading updates the profile.
    ok(await ctx.pat('PATCH', '/api/patient/me', { weightKg: 71 }));
    const pid = (await M.Patient.findOne({ userId: (await M.User.findOne({ phone: ctx.patientPhone || { $exists: true }, name: { $exists: true } }))?._id }))?._id;
    const meNow = ok(await ctx.pat('GET', '/api/patient/me'));
    assert.equal(meNow.weightKg ?? meNow.patient?.weightKg, 71);
    const patientId = meNow.id || meNow._id || meNow.patient?.id || pid;
    assert.ok(await M.Vitals.exists({ patientId, weightKg: 71 }), 'the profile weight is a reading too');
    await M.Vitals.create({ patientId, weightKg: 70.5, recordedAt: new Date(Date.now() + 1000), source: 'clinic' });
    const meAfter = ok(await ctx.pat('GET', '/api/patient/me'));
    assert.equal(meAfter.weightKg ?? meAfter.patient?.weightKg, 70.5, 'a newer reading updates the profile');
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
    // Your case: a dose taken at the old time, then the meal time changes → still one dose, still taken.
    const dayDoses = ok(await ctx.pat('GET', `/api/patient/doses?date=${tomorrow}`));
    const first = dayDoses.items.find((d) => d.slot === 'morning');
    ok(await ctx.pat('POST', `/api/patient/doses/${first.id}`, { status: 'taken' }));
    ok(await ctx.pat('PATCH', '/api/patient/me', { settings: { reminderTimes: { morning: '07:10' } } }));
    const afterMove = ok(await ctx.pat('GET', `/api/patient/doses?date=${tomorrow}`));
    const sameMed = afterMove.items.filter((d) => d.slot === 'morning' && d.medicine?.name === first.medicine?.name);
    assert.equal(sameMed.length, 1, 'one dose per medicine and slot, not one at each time');
    assert.equal(sameMed[0].status, 'taken', 'and it stays taken');
    // Duplicates left from before (old time + new time) merge, keeping the taken one.
    const dupOf = await M.DoseLog.findById(first.id);
    await M.DoseLog.create({ courseId: dupOf.courseId, patientId: dupOf.patientId, slot: 'morning', status: 'due', scheduledAt: new Date(dupOf.scheduledAt.getTime() + 15 * 60000) });
    const merged = ok(await ctx.pat('GET', `/api/patient/doses?date=${tomorrow}`));
    assert.equal(merged.items.filter((d) => d.slot === 'morning' && d.medicine?.name === first.medicine?.name).length, 1, 'duplicate merged');
    ok(await ctx.pat('PATCH', '/api/patient/me', { settings: { reminderTimes: { morning: old } } }));

    // Daily log: the patient's own goals, today's exercise, and a history with what / how much / from where.
    assert.equal((await ctx.pat('PATCH', '/api/patient/me', { goals: { stepsPerDay: 50 } })).status, 400, 'sensible step goal');
    ok(await ctx.pat('PATCH', '/api/patient/me', { goals: { stepsPerDay: 9000, exerciseMinPerDay: 40 } }));
    ok(await ctx.pat('POST', '/api/patient/logs', { type: 'exercise', exerciseType: 'walk', durationMin: 25 }), 201);
    const homeEx = ok(await ctx.pat('GET', '/api/patient/home'));
    assert.equal(homeEx.steps.goal, 9000);
    assert.equal(homeEx.exercise.goal, 40);
    assert.ok(homeEx.exercise.minutes >= 25, "today's exercise minutes");
    const hist = ok(await ctx.pat('GET', '/api/patient/logs/history?days=7'));
    assert.equal(hist.days.length, 7, 'one entry per day, newest first');
    assert.ok(hist.days[0].exercise.items.some((x) => x.exerciseType === 'walk' && x.durationMin === 25 && x.source === 'You'));
    assert.equal(hist.days[0].steps.goal, 9000);
    assert.equal(hist.days[1].exercise.minutes, 0, 'each day starts again at 0');

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
    assert.ok(homeLog.logSharedWith.some((x) => String(x.userId) === String(ctx.doctorUserId)), 'the log goes to whoever asked');
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
    // Quick replies follow the latest message: a sugar question gets a sugar answer.
    const ask = ok(await ctx.doc('POST', `/api/conversations/${ctx.convoId}/messages`, { text: 'Can you share your fasting sugar today?' }), 201);
    const seenByPatient = ok(await ctx.pat('GET', `/api/conversations/${ctx.convoId}/messages`));
    assert.ok(seenByPatient.suggestions.length >= 1 && seenByPatient.suggestions.length <= 3);
    assert.ok(/sugar/i.test(seenByPatient.suggestions[0].label), 'the first quick reply answers the question');
    assert.equal(ok(await ctx.doc('GET', `/api/conversations/${ctx.convoId}/messages`)).suggestions, undefined, 'only the patient gets quick replies');
    // Deleting it: the doctor's card and the thread preview go back to the message before.
    ok(await ctx.doc('DELETE', `/api/conversations/${ctx.convoId}/messages/${ask.message.id}`));
    const card = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}`)).conversation;
    assert.equal(card.latest.text, 'After food, please.');
    assert.equal(card.latest.from, 'doctor');
    assert.equal((await M.Conversation.findById(ctx.convoId)).lastMessage.text, 'After food, please.');
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
    // Booking sheet: places, days with free times, and the chosen day's times.
    const book = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}/booking`));
    assert.ok(book.places.length >= 1 && book.locationId);
    assert.ok(book.days.length >= 2, 'today plus the booking window');
    const freeDay = book.days.find((d) => d.free > 0);
    if (freeDay) {
      const day = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}/booking?locationId=${book.locationId}&date=${freeDay.date}`));
      assert.equal(day.date, freeDay.date);
      assert.equal(day.slots.length, freeDay.free, 'the day lists its free times');
    }
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
    // The doctor's HbA1c is a test to do, with what it checks and how to prepare; a report for it marks it done.
    const before = ok(await ctx.pat('GET', '/api/patient/records')).advisedTests.find((t) => /hba1c/i.test(t.name));
    assert.ok(before, 'the prescribed test is listed');
    assert.equal(before.status, 'todo');
    assert.match(before.prep, /fasting/i);
    // Home's "Lab tests" card lists it (at most 3, with the full count) until a result is in.
    const homeBefore = ok(await ctx.pat('GET', '/api/patient/home')).pendingTests;
    assert.ok(homeBefore.items.length <= 3 && homeBefore.total >= homeBefore.items.length);
    const dueA1c = homeBefore.items.find((t) => t.name === before.name);
    assert.ok(dueA1c, 'a test to do is on Home');
    assert.equal(dueA1c.fasting, false, 'HbA1c needs no fasting');
    // A report counts for a test only when its content shows that test — whatever the file is called.
    // (MedPin AI is off in tests: the report reader is stubbed with what it would read.)
    const assistant = require('../src/services/assistant');
    const realRead = assistant.extractLabReport;
    const uploadFor = async (name, file = 'report.pdf') => ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), file, 'application/pdf', { kind: 'test_result', forTests: before.name }) }), 201);
    const statusNow = async () => ok(await ctx.pat('GET', '/api/patient/records')).advisedTests.find((t) => t.name === before.name);
    try {
      // A blood count uploaded as "HbA1c.pdf": not counted, and the app is told what the report really is.
      assistant.extractLabReport = async () => ({ document_type: 'lab_report', lab_name: 'Suraksha', collected_on: '', tests: [{ test_name: 'Complete Blood Count', page_from: 1, page_to: 1, summary: '', values: [{ analyte: 'Haemoglobin', value: '13.1', unit: 'g/dL', ref_text: '13-17', flag: 'normal' }] }] });
      const wrong = await uploadFor(before.name, 'HbA1c.pdf');
      assert.deepEqual(wrong.testCheck.found, [], 'the file name proves nothing');
      assert.deepEqual(wrong.testCheck.detected, ['Complete Blood Count']);
      assert.equal(wrong.record.title, 'Complete Blood Count', 'named after what it contains');
      let now = await statusNow();
      assert.equal(now.status, 'wrong');
      assert.deepEqual(now.lastUpload.detected, ['Complete Blood Count']);
      assert.ok(ok(await ctx.pat('GET', '/api/patient/home')).pendingTests.items.some((t) => t.name === before.name && t.status === 'wrong'), 'still to do on Home');
      // Too blurred to read.
      assistant.extractLabReport = async () => ({ document_type: 'unreadable', lab_name: '', collected_on: '', tests: [] });
      const blurred = await uploadFor(before.name);
      assert.equal(blurred.testCheck.readable, false);
      assert.equal((await statusNow()).status, 'unreadable');
      assert.notEqual(blurred.record.status, 'processing', 'nothing to check: not left "To check"');
      // MedPin AI unavailable: uploaded, not checked — the doctor will look; it leaves the Home card.
      assistant.extractLabReport = realRead;
      await uploadFor(before.name);
      assert.equal((await statusNow()).status, 'unchecked');
      // The real HbA1c report, under any file name: done.
      assistant.extractLabReport = async () => ({ document_type: 'lab_report', lab_name: 'Suraksha', collected_on: '2026-10-15', tests: [{ test_name: 'Glycosylated Haemoglobin', page_from: 1, page_to: 1, summary: 'Average sugar is high.', values: [{ analyte: 'HbA1c', value: '7.9', unit: '%', ref_text: 'below 5.7', flag: 'high' }] }] });
      const forIt = await uploadFor(before.name, 'IMG_2041.pdf');
      assert.deepEqual(forIt.testCheck.found, [before.name]);
      now = await statusNow();
      assert.equal(now.status, 'done');
      assert.equal(String(now.result.recordId), String(forIt.record.id));
      // A report added from "Add record" (no test picked) counts for the tests it contains.
      const auto = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'scan.pdf', 'application/pdf', { kind: 'test_result' }) }), 201);
      assert.equal(auto.testCheck, null, 'every test is done: nothing to check it against');
    } finally {
      assistant.extractLabReport = realRead;
    }
    const homeAfter = ok(await ctx.pat('GET', '/api/patient/home')).pendingTests;
    assert.equal(homeAfter.total, homeBefore.total - 1, 'an uploaded result leaves the Lab tests card');
    assert.ok(!homeAfter.items.some((t) => t.name === before.name));
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

  await step('sharing waits for the patient; readings from lab reports; when-needed medicines; reminders', async () => {
    const T = require('../src/lib/time');
    // A shared report: in the app only for the doctor (no push), and "New" on the patient until opened.
    const before = await M.Notification.countDocuments({ userId: ctx.doctorUserId, type: 'record_shared' });
    const up = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'scan.pdf', 'application/pdf', { kind: 'test_result', shareWith: ctx.doctorUserId }) }), 201);
    assert.deepEqual(up.heldShare, [], 'nothing to check: shared now');
    const note = await M.Notification.findOne({ userId: ctx.doctorUserId, type: 'record_shared' }).sort({ createdAt: -1 });
    assert.equal(await M.Notification.countDocuments({ userId: ctx.doctorUserId, type: 'record_shared' }), before + 1);
    assert.ok(!note.channels.includes('push'), 'a shared report is not a push');
    const row = ok(await ctx.doc('GET', '/api/patients?limit=100')).items.find((p) => String(p.id) === String(ctx.patientId));
    assert.ok(row.newReports >= 1, 'marked New for the doctor');
    ok(await ctx.doc('GET', `/api/patients/${ctx.patientId}`));
    assert.equal(ok(await ctx.doc('GET', '/api/patients?limit=100')).items.find((p) => String(p.id) === String(ctx.patientId)).newReports, 0, 'opening the patient clears it');

    // A report uploaded for a test that turns out to be another test: not shared until the patient keeps it.
    const assistant = require('../src/services/assistant');
    const realRead = assistant.extractLabReport;
    try {
      const rx = await M.Prescription.findOne({ patientId: ctx.patientId, 'tests.0': { $exists: true } });
      assistant.extractLabReport = async () => ({ document_type: 'prescription', lab_name: '', collected_on: '', tests: [] });
      const held = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'x.pdf', 'application/pdf', { kind: 'test_result', forTests: rx.tests[0], shareWith: ctx.doctorUserId }) }), 201);
      assert.deepEqual(held.heldShare, [String(ctx.doctorUserId)], 'held until the patient chooses');
      assert.equal((await M.MedicalRecord.findById(held.record.id)).sharedWith.length, 0);

      // The right report for a test the doctor asked for: shared at once, and the doctor is told
      // it's theirs ("… report you asked for"), in the bell — no buzz (only critical values push).
      const asked = rx.tests[0];
      assistant.extractLabReport = async () => ({ document_type: 'lab_report', lab_name: 'Suraksha', collected_on: '', tests: [{ test_name: asked, page_from: 1, page_to: 1, summary: '', values: [{ analyte: asked, value: '7.9', unit: '%', ref_text: '4-5.6', flag: 'high' }] }] });
      const right = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'scan.pdf', 'application/pdf', { kind: 'test_result', forTests: asked, shareWith: ctx.doctorUserId }) }), 201);
      assert.deepEqual(right.heldShare, [], 'not held: the doctor is told now, even if the patient leaves "Check your report"');
      assert.equal((await M.MedicalRecord.findById(right.record.id)).sharedWith.length, 1);
      const told = await M.Notification.findOne({ userId: ctx.doctorUserId, type: 'report_in' }).sort({ createdAt: -1 });
      assert.ok(told && /report you asked for$/.test(told.title), `the doctor sees it's their test: ${told?.title}`);
      assert.ok(!told.channels.includes('push'), 'in the bell, not a push');

      // A confirmed fasting sugar from a lab report becomes a reading (tiles, score, doctor's view)…
      assistant.extractLabReport = async () => null;
      const lab = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'fbs.pdf', 'application/pdf', { kind: 'test_result' }) }), 201);
      await M.MedicalRecord.updateOne({ _id: lab.record.id }, { status: 'processing' });
      const saved = ok(await ctx.pat('POST', `/api/patient/records/${lab.record.id}/split`, {
        collectedAt: T.dayKey(new Date()),
        tests: [{ testName: 'Fasting Blood Sugar', pageFrom: 1, pageTo: 1, summary: '', values: [{ analyte: 'Glucose, Fasting', value: '148', unit: 'mg/dL', refText: '70-100', flag: 'high' }] }],
      }), 201);
      const reading = await M.Vitals.findOne({ patientId: ctx.patientId, source: 'lab', bloodSugar: 148 });
      assert.ok(reading, 'the lab value is a reading');
      assert.equal(reading.sugarType, 'fasting');
      const home = ok(await ctx.pat('GET', '/api/patient/home'));
      // On the Fasting sugar tile with its source (the newest value wins, so a later home reading stays last).
      assert.ok(home.tracked.blood_sugar.some((x) => x.value === 148 && x.source === 'lab'), 'the lab sugar is on the tile');
      // …and goes when the report is deleted.
      ok(await ctx.pat('DELETE', `/api/patient/records/${saved[0].id || saved[0]._id}`));
      assert.equal(await M.Vitals.countDocuments({ fromLabId: reading.fromLabId }), 0);
    } finally {
      assistant.extractLabReport = realRead;
    }

    // "When needed" medicines: no doses on a schedule, never missed, no "runs out" warning.
    const asNeeded = await M.MedicationCourse.create({
      patientId: ctx.patientId, name: 'Paracetamol', strength: '650 mg', dose: { morning: 1 }, frequency: 'as_needed',
      startDate: T.addDays(T.dayStart(), -3), status: 'active', stockUnits: 4, trackingEnabled: true,
    });
    const doses = ok(await ctx.pat('GET', `/api/patient/doses?date=${T.dayKey(new Date())}`));
    assert.ok(!doses.items.some((d) => String(d.medicine?.id || d.courseId) === String(asNeeded._id)), 'no scheduled dose');
    assert.equal(await M.DoseLog.countDocuments({ courseId: asNeeded._id, status: { $ne: 'taken' } }), 0);
    const meds = ok(await ctx.pat('GET', '/api/patient/medicines'));
    const pm = (meds.items || meds).find((c) => String(c.id) === String(asNeeded._id));
    assert.equal(pm.asNeeded, true);
    await M.MedicationCourse.deleteOne({ _id: asNeeded._id });

    // App lock is off for a new account.
    assert.equal(new M.User({ phone: '9000000001', name: 'New' }).appLock, false);

    // Reminders: the daily-log one is on only once chosen (or a meal log was asked for).
    const me = ok(await ctx.pat('GET', '/api/patient/me'));
    assert.equal(typeof me.reminders.dailyLog, 'boolean');
    assert.equal(me.reminders.ring, true, 'medicine alarms ring like an alarm by default');
    const after = ok(await ctx.pat('PATCH', '/api/patient/me', { settings: { dailyLogReminder: true } }));
    assert.equal(after.reminders.dailyLog, true);
    // The phone says what it scheduled; the server then pushes only what it doesn't cover.
    ok(await ctx.pat('POST', '/api/me/devices', { token: 'test-phone-token', platform: 'android', localAlarms: true }));
    const until = T.addDays(new Date(), 7);
    assert.equal(ok(await ctx.pat('POST', '/api/me/devices/reminders', { token: 'test-phone-token', until: until.toISOString(), dailyLogAt: '20:00' })).ok, true);
    const { phoneCovers } = require('../src/services/reminders');
    const phones = await M.DeviceToken.find({ token: 'test-phone-token' });
    assert.equal(phoneCovers(phones, T.addDays(new Date(), -1), T.addDays(new Date(), 2)), true, 'scheduled on the phone');
    assert.equal(phoneCovers(phones, T.addDays(new Date(), 1), T.addDays(new Date(), 2)), false, 'changed after the phone synced: pushed');
    assert.equal(phoneCovers(phones, T.addDays(new Date(), -1), T.addDays(new Date(), 9)), false, 'beyond what it scheduled: pushed');
    await M.DeviceToken.deleteOne({ token: 'test-phone-token' });
  });

  await step('fees: pay at the clinic, collect once, refunds; no front desk; records renamed', async () => {
    const T = require('../src/lib/time');
    // A free slot in the next days.
    let free = null;
    for (let day = 1; day <= 6 && !free; day += 1) {
      const d = T.dayKey(T.addDays(new Date(), day));
      free = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${d}`)).slots.find((s) => s.available && !s.walkIn);
    }
    assert.ok(free, 'a free slot');
    const appt = ok(await ctx.desk('POST', '/api/appointments', { patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: free.startAt, visitType: 'follow_up' }), 201);
    // "Pay at the clinic" is kept: the desk and doctor see "collect".
    const chose = ok(await ctx.pat('POST', `/api/patient/appointments/${appt.id}/pay-at-clinic`, {}));
    assert.equal(chose.payAt, 'clinic');
    const list = ok(await ctx.desk('GET', `/api/appointments?view=date&date=${T.dayKey(new Date(free.startAt))}`));
    const row = list.items.find((a) => a.id === appt.id);
    assert.equal(row.payAt, 'clinic');
    assert.equal(row.payment.status, 'pending');
    // Collected at the desk once (a second "mark paid" is refused); the patient gets a receipt.
    ok(await ctx.desk('POST', `/api/payments/${row.payment.id}/mark-paid`, { method: 'cash' }));
    assert.equal((await ctx.desk('POST', `/api/payments/${row.payment.id}/mark-paid`, { method: 'upi' })).status, 409, 'not taken twice');
    const patientUser = (await M.Patient.findById(ctx.patientId)).userId;
    assert.ok(await M.Notification.exists({ userId: patientUser, type: 'fee_paid' }), 'receipt to the patient');
    // Cancelled after paying at the desk: a refund to hand back, then marked handed back.
    ok(await ctx.desk('POST', `/api/appointments/${appt.id}/cancel`, { reason: 'Clinic closed' }));
    let pay = await M.Payment.findById(row.payment.id);
    assert.equal(pay.refundDue, true, 'refund due at the desk');
    ok(await ctx.desk('POST', `/api/payments/${pay._id}/refund`, { handedBack: true }));
    pay = await M.Payment.findById(pay._id);
    assert.equal(pay.status, 'refunded');
    assert.equal((await M.Appointment.findById(appt.id)).feeStatus, 'refunded');
    assert.ok(await M.Notification.exists({ userId: patientUser, type: 'fee_refunded' }));
    assert.ok(pay.refundedBy, 'who handed it back is kept');
    const cancelled = ok(await ctx.desk('GET', `/api/appointments/${appt.id}`));
    assert.ok(cancelled.cancelledByName, 'who cancelled is shown');
    assert.equal(cancelled.cancelReason, 'Clinic closed');

    // Front-desk policy: who may act on which visit, and who may give money back.
    const P = M.ROLE_PERMISSIONS;
    assert.deepEqual([P.doctor.refunds, P.practice_manager.refunds, P.front_desk.refunds, P.doctor_assistant.refunds], [true, true, false, false], 'discretionary refunds: doctor / manager');
    assert.deepEqual([P.front_desk.vitals, P.doctor_assistant.vitals, P.practice_manager.vitals, P.lab_technician.vitals], [true, true, true, false], 'who takes vitals');
    const freeSlots = async (n) => {
      const out = [];
      for (let day = 1; day <= 12 && out.length < n; day += 1) {
        const d = T.dayKey(T.addDays(new Date(), day));
        for (const s of ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${d}`)).slots) {
          if (s.available && !s.walkIn && out.length < n) out.push(s);
        }
      }
      assert.equal(out.length, n, 'free slots');
      return out;
    };
    const [s1, s2] = await freeSlots(2);
    const visit = ok(await ctx.desk('POST', '/api/appointments', { patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: s1.startAt, visitType: 'follow_up', confirmed: true }), 201);
    const other = ok(await ctx.desk('POST', '/api/appointments', { patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: s2.startAt, visitType: 'follow_up' }), 201);
    assert.equal((await ctx.desk('POST', `/api/appointments/${visit.id}/cancel`, {})).status, 400, 'a cancel needs a reason');
    // The desk moved to another branch: this visit isn't theirs to change.
    const deskMember = await M.Member.findOne({ userId: (await M.User.findOne({ phone: '9749681391' }))._id, practiceId: (await M.Location.findById(ctx.locationId)).practiceId });
    const was = { locationIds: deskMember.locationIds, allLocations: deskMember.allLocations };
    await M.Member.updateOne({ _id: deskMember._id }, { locationIds: [new (require('mongoose').Types.ObjectId)()], allLocations: false });
    const away = await ctx.desk('POST', `/api/appointments/${visit.id}/cancel`, { reason: 'Patient asked' });
    assert.deepEqual([away.status, away.body?.error?.code], [403, 'NOT_YOUR_LOCATION'], 'desk at another location: 403');
    assert.equal((await ctx.desk('POST', `/api/appointments/${visit.id}/status`, { status: 'waiting' })).status, 403);
    const visitPay = ok(await ctx.doc('GET', `/api/appointments/${visit.id}`)).payment;
    if (visitPay) assert.equal((await ctx.desk('POST', `/api/payments/${visitPay.id}/mark-paid`, { method: 'cash' })).status, 403, 'nor collect its fee');
    await M.Member.updateOne({ _id: deskMember._id }, was);
    // Back at this branch: collect, then a refund of a visit that wasn't cancelled is the doctor's call.
    if (visitPay) {
      ok(await ctx.desk('POST', `/api/payments/${visitPay.id}/mark-paid`, { method: 'cash' }));
      const goodwill = await ctx.desk('POST', `/api/payments/${visitPay.id}/refund`, { handedBack: true, reason: 'Overcharged' });
      assert.deepEqual([goodwill.status, goodwill.body?.error?.code], [403, 'PERMISSION_REQUIRED'], "the desk can't refund a visit that wasn't cancelled");
      ok(await ctx.doc('POST', `/api/payments/${visitPay.id}/refund`, { handedBack: true, reason: 'Overcharged' }));
      const back = await M.Payment.findById(visitPay.id);
      assert.deepEqual([back.status, back.refundReason], ['refunded', 'Overcharged'], 'the doctor can');
      assert.equal((await M.Appointment.findById(visit.id)).status, 'confirmed', 'the visit stays booked');
    }
    const otherPay = ok(await ctx.doc('GET', `/api/appointments/${other.id}`)).payment;
    if (otherPay) {
      assert.equal((await ctx.desk('POST', `/api/payments/${otherPay.id}/waive`, {})).status, 403, "the desk can't waive a fee");
      ok(await ctx.doc('POST', `/api/payments/${otherPay.id}/waive`, { reason: 'Old patient' }));
      assert.equal((await M.Payment.findById(otherPay.id)).status, 'waived');
    }
    ok(await ctx.desk('POST', `/api/appointments/${visit.id}/cancel`, { reason: 'Booked by mistake' }));
    ok(await ctx.desk('POST', `/api/appointments/${other.id}/cancel`, { reason: 'Booked by mistake' }));

    // A clinic without a front desk: requests go to the doctor; the dashboard says so.
    const { deskOrDoctors, hasDesk } = require('../src/services/notify');
    const practice = (await M.Location.findById(ctx.locationId)).practiceId;
    if (!(await hasDesk(practice, ctx.locationId))) {
      assert.deepEqual((await deskOrDoctors(practice, { locationId: ctx.locationId, doctorId: ctx.doctorUserId })).map(String), [String(ctx.doctorUserId)]);
    } else {
      const desk = await deskOrDoctors(practice, { locationId: ctx.locationId, doctorId: ctx.doctorUserId });
      assert.ok(desk.length >= 1 && !desk.map(String).includes(String(ctx.doctorUserId)), 'the desk does it when there is one');
    }
    const dash = ok(await ctx.doc('GET', '/api/dashboard'));
    assert.equal(typeof dash.hasDesk, 'boolean');
    assert.equal(typeof dash.requests.pending, 'number');
    assert.equal(typeof dash.fees.collected, 'number');

    // Records: the patient renames one, and says a "prescription" is a test report after all.
    const up = ok(await ctx.pat('POST', '/api/patient/records', undefined, { form: fileForm('files', tinyPdf(), 'rx.pdf', 'application/pdf', { kind: 'prescription' }) }), 201);
    const renamed = ok(await ctx.pat('PATCH', `/api/patient/records/${up.record.id}`, { title: 'Dr. Mitra · thyroid', sourceName: 'Dr. Rina Mitra', recordDate: T.dayKey(T.addDays(new Date(), -3)) }));
    assert.equal(renamed.record.title, 'Dr. Mitra · thyroid');
    assert.equal(renamed.record.sourceName, 'Dr. Rina Mitra');
    assert.equal((await ctx.pat('PATCH', `/api/patient/records/${up.record.id}`, { recordDate: T.dayKey(T.addDays(new Date(), 3)) })).status, 400, 'no future dates');
    const asTest = ok(await ctx.pat('PATCH', `/api/patient/records/${up.record.id}`, { kind: 'test_result' }));
    assert.equal(asTest.record.kind, 'test_result');
    assert.equal(asTest.record.status, 'processing', 'read as a report next');
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

  await step('clinic set-up: the front desk keeps closures, not hours; staff in two clinics choose one', async () => {
    // A fresh session for the front desk (suspension above signed them out), without another code.
    const deskUser = await M.User.findOne({ phone: '9749681391' });
    const sec = require('../src/lib/security');
    const sid = await M.AuthSession.create({ userId: deskUser._id, tokenHash: sec.sha256(sec.randomToken()), expiresAt: new Date(Date.now() + 864e5) });
    const s = { accessToken: sec.signAccess(deskUser, sid._id), user: { id: String(deskUser._id) } };
    const desk = api(s.accessToken);
    const loc = ok(await desk('GET', `/api/locations/${ctx.locationId}`));
    assert.deepEqual([loc.can.details, loc.can.hours, loc.can.closures], [false, false, true], 'front desk: closures only');
    assert.match(loc.can.note, /holidays and closures/);
    assert.equal((await desk('PATCH', `/api/locations/${ctx.locationId}`, { name: 'Renamed' })).status, 403, 'front desk cannot change details');
    const owner = ok(await ctx.doc('GET', `/api/locations/${ctx.locationId}`));
    assert.deepEqual([owner.can.details, owner.can.closures], [true, true]);
    const row = loc.doctors.find((d) => String(d.doctorId) === String(ctx.doctorUserId));
    assert.equal(row.canEdit, false, "front desk sees the doctor's hours read-only");
    assert.equal((await desk('PUT', `/api/locations/${ctx.locationId}/doctors/${ctx.doctorUserId}/hours`, { week: row.week })).status, 403);
    // A part-day closure: only those slots go.
    let day;
    let before;
    for (let i = 2; i < 10 && !day; i += 1) {
      const d = new Date(Date.now() + i * 864e5).toISOString().slice(0, 10);
      const sl = ok(await desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${d}`));
      if (sl.open && sl.slots.length > 8) [day, before] = [d, sl];
    }
    assert.ok(day, 'a bookable day');
    const from = before.slots[2].minute;
    const preview = ok(await desk('GET', `/api/locations/${ctx.locationId}/closures/preview?startDate=${day}&allDay=false&fromMin=${from}&toMin=${from + 60}`));
    assert.equal(typeof preview.booked, 'number');
    assert.equal((await desk('POST', `/api/locations/${ctx.locationId}/closures`, { startDate: day, allDay: false, fromMin: from, toMin: from })).status, 400, 'end after start');
    const c = ok(await desk('POST', `/api/locations/${ctx.locationId}/closures`, { startDate: day, allDay: false, fromMin: from, toMin: from + 60, reason: 'Staff meeting' }), 201);
    assert.equal(c.allDay, false);
    const after = ok(await desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${day}`));
    assert.ok(after.open, 'the rest of the day stays bookable');
    assert.ok(!after.slots.some((x) => x.minute + 15 > from && x.minute < from + 60), 'no slots in the closed hour');
    assert.equal((await desk('POST', `/api/locations/${ctx.locationId}/closures`, { startDate: day, reason: 'Again' })).body.error.code, 'CLOSURE_OVERLAP');
    ok(await desk('DELETE', `/api/locations/${ctx.locationId}/closures/${c.id}`));
    assert.equal(ok(await desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${day}`)).slots.length, before.slots.length, 'open again');
    // The owner changes the doctor's hours here; overlapping sessions are refused.
    const overlap = row.week.map((w) => ({ weekday: w.weekday, sessions: [{ startMin: 540, endMin: 780 }, { startMin: 720, endMin: 900 }] }));
    assert.equal((await ctx.doc('PUT', `/api/locations/${ctx.locationId}/doctors/${ctx.doctorUserId}/hours`, { week: overlap })).status, 400);
    const saved = ok(await ctx.doc('PUT', `/api/locations/${ctx.locationId}/doctors/${ctx.doctorUserId}/hours`, { week: row.week }));
    assert.equal(saved.week.length, 7);
    // My own membership (Profile → Account / Clinic details).
    const me = ok(await desk('GET', '/api/members/me'));
    assert.equal(me.role, 'front_desk');
    assert.equal(me.practice.name, 'City Care Clinic');
    assert.ok(me.coverage.some((l) => String(l.id) === String(ctx.locationId) && l.doctors.some((d) => String(d.userId) === String(ctx.doctorUserId))), 'locations with their doctors');
    assert.ok(me.worksFor.some((d) => String(d.userId) === String(ctx.doctorUserId)));
    assert.equal(me.permissions.closures, true);
    // The front desk's own photo: saved, and in every account summary (header avatar, after a restart).
    const photo = ok(await desk('POST', '/api/me/photo', undefined, { form: fileForm('file', tinyPng(), 'me.png', 'image/png') }));
    assert.ok(photo.user.photoUrl, 'photo link in the summary');
    assert.ok(ok(await desk('GET', '/api/auth/session')).user.photoUrl, 'and when the session is restored');
    const team = ok(await ctx.doc('GET', '/api/members'));
    assert.ok(team.items.find((x) => String(x.userId) === String(s.user.id))?.photo, 'the team sees it too');
    // A second clinic: the choice is kept and staff endpoints follow it; a header still wins.
    const other = await M.Practice.create({ name: 'Lake View Clinic', ownerUserId: ctx.doctorUserId });
    const m2 = await M.Member.create({ practiceId: other._id, userId: s.user.id, role: 'front_desk', allLocations: true });
    const sess = ok(await desk('GET', '/api/auth/session'));
    assert.equal(sess.memberships.filter((m) => m.status === 'active').length, 2);
    const sw = ok(await desk('POST', '/api/me/active-practice', { practiceId: String(other._id) }));
    assert.equal(String(sw.activePracticeId), String(other._id));
    assert.equal(ok(await desk('GET', '/api/members/me')).practice.name, 'Lake View Clinic');
    assert.equal(ok(await api(s.accessToken, ctx.practiceId)('GET', '/api/members/me')).practice.name, 'City Care Clinic', 'x-practice-id wins');
    assert.equal((await desk('POST', '/api/me/active-practice', { practiceId: '000000000000000000000000' })).status, 403);
    ok(await desk('POST', '/api/me/active-practice', { practiceId: String(ctx.practiceId) }));
    await M.Member.deleteOne({ _id: m2._id });
    await M.Practice.deleteOne({ _id: other._id });
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
    const day = require('../src/lib/time').dayKey(new Date()); // the clinic's (IST) day, also just after midnight
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
    // In their app language (this patient chose Hindi).
    if (patient.userId) assert.ok(await M.Notification.exists({ userId: patient.userId, type: 'appointment_booked', title: 'विज़िट पक्की' }), 'the patient is told');
    ok(await ctx.desk('POST', `/api/appointments/${appt.id}/cancel`, { reason: 'Patient asked' }));

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

  await step('automatic chat notes are signed by a real person (desk at the branch, else the doctor)', async () => {
    const care = require('../src/services/care');
    const deskUser = String(ok(await ctx.desk('GET', '/api/me')).user.id);
    const patient = await M.Patient.findById(ctx.patientId, 'userId');
    const convoOf = (pid) => M.Conversation.findOne({ patientId: pid, practiceId: ctx.practiceId, type: 'care' });
    const unread = (c, uid) => c.participants.find((p) => String(p.userId) === String(uid))?.unreadCount || 0;
    const base = { practiceId: ctx.practiceId, patientId: ctx.patientId, locationId: ctx.locationId, doctorId: ctx.doctorUserId };
    // The desk books: the "Visit booked" note is theirs (staff, automatic); only the patient's unread goes up.
    let free = null;
    for (let day = 2; day < 14 && !free; day += 1) {
      const d = new Date(Date.now() + day * 864e5).toISOString().slice(0, 10);
      free = ok(await ctx.desk('GET', `/api/doctors/${ctx.doctorUserId}/slots?locationId=${ctx.locationId}&date=${d}`)).slots.find((s) => s.available && !s.walkIn);
    }
    const before = await convoOf(ctx.patientId);
    const appt = ok(await ctx.desk('POST', '/api/appointments', { patientId: ctx.patientId, doctorId: ctx.doctorUserId, locationId: ctx.locationId, startAt: free.startAt, visitType: 'follow_up' }), 201);
    const booked = await M.Message.findOne({ conversationId: before._id, 'meta.event': 'visit_booked' }).sort({ createdAt: -1 });
    assert.equal(String(booked.senderId), deskUser, 'sent from the desk member who booked');
    assert.equal(booked.senderType, 'staff');
    assert.equal(booked.meta.auto, true);
    const after = await convoOf(ctx.patientId);
    assert.equal(String(after.lastMessage.senderId), deskUser, 'the preview shows who sent it');
    assert.equal(unread(after, patient.userId), unread(before, patient.userId) + 1, "the patient's unread goes up");
    if (before.participants.some((p) => String(p.userId) === deskUser)) assert.equal(unread(after, deskUser), unread(before, deskUser), "the sender's doesn't");
    assert.equal(unread(after, ctx.doctorUserId), unread(before, ctx.doctorUserId), "the other staff's don't");
    const view = ok(await ctx.pat('GET', `/api/conversations/${before._id}/messages`)).items.find((m) => m.id === String(booked._id));
    assert.equal(view.auto, true);
    assert.equal(view.senderRoleLabel, 'Front desk');
    assert.equal(view.senderId.name, 'Tania Ghosh');
    // The doctor cancels: signed by the doctor.
    ok(await ctx.doc('POST', `/api/appointments/${appt.id}/cancel`, { reason: 'Doctor away' }));
    const cancelled = await M.Message.findOne({ conversationId: before._id, 'meta.event': 'visit_cancelled' }).sort({ createdAt: -1 });
    assert.equal(String(cancelled.senderId), String(ctx.doctorUserId));
    assert.equal(cancelled.senderType, 'doctor');
    // Done by the patient (booked / paid in the app): the desk at that branch signs it.
    const byPatient = await care.chatNote({ ...base, by: patient.userId }, 'Payment received: ₹500 online.', 'fee_paid');
    assert.equal(String(byPatient.senderId), deskUser);
    // Two at the desk: the one who last wrote in this chat, else the one most recently in the app.
    const rina = await M.User.create({ name: 'Rina Das', phone: '9000000111', lastActiveAt: new Date(Date.now() + 60e3) });
    await M.Member.create({ practiceId: ctx.practiceId, userId: rina._id, role: 'front_desk', locationIds: [ctx.locationId] });
    await M.Message.create({ conversationId: before._id, senderId: rina._id, senderType: 'staff', text: 'Your report is in.' });
    assert.equal(String((await care.chatNote(base, 'Visit confirmed.', 'visit_confirmed')).senderId), String(rina._id), 'the last to write');
    await M.Message.create({ conversationId: before._id, senderId: deskUser, senderType: 'staff', text: 'See you tomorrow.' });
    assert.equal(String((await care.chatNote(base, 'Visit confirmed.', 'visit_confirmed')).senderId), deskUser);
    const asha = await M.Patient.create({ name: 'Asha Roy', gender: 'female', phone: '9000000222' });
    assert.equal(String((await care.chatNote({ ...base, patientId: asha._id }, 'Visit booked.', 'visit_booked')).senderId), String(rina._id), 'nobody wrote yet: most recently active');
    // A branch without a front desk: the visit's doctor.
    const branch = await M.Location.create({ practiceId: ctx.practiceId, name: 'City Care — New Town' });
    const solo = await care.chatNote({ ...base, locationId: branch._id }, 'Visit booked.', 'visit_booked');
    assert.equal(String(solo.senderId), String(ctx.doctorUserId));
    assert.equal(solo.senderType, 'doctor');
    // Old clinic lines (no sender) still come through.
    await M.Message.create({ conversationId: before._id, senderType: 'system', text: 'Visit booked (old note).', meta: { event: 'visit_booked' } });
    const old = ok(await ctx.pat('GET', `/api/conversations/${before._id}/messages`)).items.find((m) => m.text === 'Visit booked (old note).');
    assert.equal(old.senderType, 'system');
    // The doctor's own "latest message" on the patient's doctor page skips automatic notes.
    const card = ok(await ctx.pat('GET', `/api/patient/doctors/${ctx.doctorUserId}`)).conversation;
    assert.notEqual(card.latestFromDoctor?.text, 'Visit booked.');
    await M.Member.deleteOne({ userId: rina._id });
    await M.Location.deleteOne({ _id: branch._id });
    ctx.rinaId = rina._id;
  });

  await step('emergencies: doctor and desk on an urgent chat, clinicians only on readings, escalation, resolve clears every bell', async () => {
    const jobs = require('../src/services/jobs');
    const deskUser = String(ok(await ctx.desk('GET', '/api/me')).user.id);
    const count = (userId, q = {}) => M.Notification.countDocuments({ userId, ...q });
    await M.Notification.updateMany({ userId: deskUser }, { readAt: new Date() });
    // Earlier steps' emergencies for this patient are dealt with (so only this step's count).
    await M.Alert.updateMany({ practiceId: ctx.practiceId, status: { $ne: 'resolved' } }, { status: 'resolved' });
    // A patient's message reaches the desk covering them (the clinic's shared inbox).
    const msgsBefore = await count(deskUser, { type: 'message' });
    const convo = await M.Conversation.findOne({ patientId: ctx.patientId, practiceId: ctx.practiceId, type: 'care' });
    ok(await ctx.pat('POST', `/api/conversations/${convo._id}/messages`, { text: 'Can I come at 6 instead?' }), 201);
    assert.equal(await count(deskUser, { type: 'message' }), msgsBefore + 1, 'the desk hears about patient messages');
    // Patient-Emergency: one alert to the doctor (no second "urgent message"), the desk gets the chat.
    const docUrgentMsgs = await count(ctx.doctorUserId, { type: 'urgent_message' });
    const u = ok(await ctx.pat('POST', '/api/patient/urgent', { doctorId: ctx.doctorUserId, text: 'Severe chest pain, sweating.' }), 201);
    assert.ok(await M.Notification.exists({ userId: ctx.doctorUserId, type: 'alert_emergency', 'params.alertId': new mongoose.Types.ObjectId(u.alertId) }), 'the doctor gets the alert');
    assert.equal(await count(ctx.doctorUserId, { type: 'urgent_message' }), docUrgentMsgs, 'not twice');
    const deskNote = await M.Notification.findOne({ userId: deskUser, type: 'urgent_chat' }).sort({ createdAt: -1 });
    assert.ok(deskNote, 'the desk is told');
    assert.equal(deskNote.screen, 'Patient-Thread', 'they open the chat, not clinical alerts');
    assert.equal(String(deskNote.params.conversationId), String(u.conversationId));
    assert.equal(await count(deskUser, { type: /^alert_/, readAt: null }), 0, 'no clinical alert for the desk');
    assert.equal(ok(await ctx.desk('GET', `/api/notifications?limit=1&practiceId=${ctx.practiceId}`)).urgent, 1, 'red dot');
    // The desk sees it on the thread, can't acknowledge or resolve, can say "Doctor informed".
    const thread = ok(await ctx.desk('GET', `/api/conversations/${u.conversationId}/messages`));
    assert.equal(String(thread.conversation.urgentAlert.id), String(u.alertId));
    assert.equal(thread.conversation.urgentAlert.canManage, false);
    assert.equal(ok(await ctx.pat('GET', `/api/conversations/${u.conversationId}/messages`)).conversation.urgentAlert, undefined, 'not shown to the patient');
    assert.equal((await ctx.desk('POST', `/api/alerts/${u.alertId}/acknowledge`)).status, 403);
    assert.equal((await ctx.desk('POST', `/api/alerts/${u.alertId}/resolve`)).status, 403);
    ok(await ctx.desk('POST', `/api/alerts/${u.alertId}/desk-note`, {}));
    assert.equal((await M.Alert.findById(u.alertId)).status, 'open', "a desk note doesn't close it");
    const onAlert = ok(await ctx.doc('GET', '/api/alerts')).items.find((a) => String(a.id) === String(u.alertId));
    assert.deepEqual(onAlert.deskNotes.map((n) => [n.text, n.by]), [['Doctor informed', 'Tania Ghosh']], 'the doctor sees it on the alert');
    // A dangerous home reading: clinicians only.
    const deskBefore = await count(deskUser);
    ok(await ctx.pat('POST', '/api/patient/readings', { bpSystolic: 192, bpDiastolic: 124 }), 201);
    const reading = await M.Alert.findOne({ practiceId: ctx.practiceId, patientId: ctx.patientId, kind: 'reading', severity: 'emergency', status: 'open' }).sort({ createdAt: -1 });
    assert.ok(reading);
    assert.equal(await count(deskUser), deskBefore, 'the front desk gets no clinical alert');
    assert.equal((await ctx.desk('POST', `/api/alerts/${reading._id}/desk-note`, {})).status, 403, 'not theirs to note (yet)');
    // Nobody acknowledged it in 15 minutes: the desk is asked to tell the doctor, once.
    await M.Alert.collection.updateOne({ _id: reading._id }, { $set: { createdAt: new Date(Date.now() - 16 * 60e3) } });
    await jobs.escalateEmergencies(new Date());
    await jobs.escalateEmergencies(new Date());
    const esc = await M.Notification.find({ userId: deskUser, type: 'emergency_escalation', 'params.alertId': reading._id });
    assert.equal(esc.length, 1, 'once');
    assert.match(esc[0].title, /Dr\. Sen hasn't seen an emergency for Priya Sharma yet/);
    assert.ok((await M.Alert.findById(reading._id)).escalatedAt);
    ok(await ctx.desk('POST', `/api/alerts/${reading._id}/desk-note`, { note: 'Told Dr. Sen in person' }));
    // The doctor resolves both: every notification about them is read (red dots clear), the desk gets a quiet "Resolved by".
    ok(await ctx.doc('POST', `/api/alerts/${u.alertId}/resolve`));
    ok(await ctx.doc('POST', `/api/alerts/${reading._id}/resolve`));
    assert.equal(await M.Notification.countDocuments({ 'params.alertId': { $in: [new mongoose.Types.ObjectId(u.alertId), reading._id] }, readAt: null }), 0, "everyone's are read");
    const resolved = await M.Notification.findOne({ userId: deskUser, type: 'alert_resolved' }).sort({ createdAt: -1 });
    assert.equal(resolved.title, 'Resolved by Dr. Sen');
    assert.ok(!resolved.channels.includes('push'), 'no buzz');
    const bell = ok(await ctx.desk('GET', `/api/notifications?limit=1&practiceId=${ctx.practiceId}`));
    assert.equal(bell.urgent, 0, 'no red dot once resolved');
    assert.equal(ok(await ctx.desk('GET', `/api/conversations/${u.conversationId}/messages`)).conversation.urgentAlert, null);
  });

  await step("notifications in each person's app language (Bengali / Hindi), every template covered", async () => {
    // Templates: known text translates, unknown stays; every notify() text in src/ has one.
    require('./test-notify-i18n').run();
    const { notify } = require('../src/services/notify');
    const [bn, hi, en] = await M.User.create([
      { phone: '9000071001', name: 'Bengali reader', language: 'bn' },
      { phone: '9000071002', name: 'Hindi reader', language: 'hi' },
      { phone: '9000071003', name: 'English reader' },
    ]);
    // Each phone is signed in (pushes go only to phones with an active session).
    const sessions = await M.AuthSession.create([bn, hi, en].map((u, i) => ({ userId: u._id, tokenHash: `lang-test-session-${i}`, platform: 'android', expiresAt: new Date(Date.now() + 864e5) })));
    await M.DeviceToken.create([bn, hi, en].map((u, i) => ({ userId: u._id, token: `lang-test-${i}`, platform: 'android', sessionId: sessions[i]._id })));
    // Pushes (FCM is off in tests: sendPush logs "[push:dev] n device(s): title").
    const pushed = [];
    const log = console.log;
    console.log = (...a) => (String(a[0]).startsWith('[push:dev]') ? pushed.push(String(a[0])) : log(...a));
    try {
      const params = { appointmentId: new mongoose.Types.ObjectId() };
      await notify([bn._id, hi._id, en._id], { type: 'refund_due', title: "Refund of ₹500 to Rajat Mondal didn't go through", body: 'Retry it from Fees, or hand it back at the desk.', screen: 'Report-Fees', params });
      await notify([bn._id, hi._id, en._id], { type: 'support', title: 'Something new from the clinic', body: 'Free text stays as it is' });
      for (let i = 0; i < 50 && pushed.length < 4; i += 1) await new Promise((r) => setTimeout(r, 40));
      const of = async (u, type) => M.Notification.findOne({ userId: u._id, type }).lean();
      const [b, h, e] = await Promise.all([of(bn, 'refund_due'), of(hi, 'refund_due'), of(en, 'refund_due')]);
      assert.equal(b.title, 'Rajat Mondal-কে ₹500 ফেরত দেওয়া যায়নি');
      assert.equal(b.body, 'ফি থেকে আবার চেষ্টা করুন, অথবা রিসেপশনে টাকা ফেরত দিন।');
      assert.equal(h.title, 'Rajat Mondal को ₹500 का रिफ़ंड नहीं हो पाया');
      assert.equal(e.title, "Refund of ₹500 to Rajat Mondal didn't go through", 'English unchanged');
      for (const n of [b, h, e]) assert.deepEqual([n.type, n.screen, String(n.params.appointmentId)], ['refund_due', 'Report-Fees', String(params.appointmentId)], 'same type, screen and params');
      for (const u of [bn, hi, en]) assert.equal((await of(u, 'support')).title, 'Something new from the clinic', 'unknown text unchanged');
      assert.ok(pushed.some((p) => p.endsWith(': Rajat Mondal-কে ₹500 ফেরত দেওয়া যায়নি')), 'Bengali push');
      assert.ok(pushed.some((p) => p.endsWith(': Rajat Mondal को ₹500 का रिफ़ंड नहीं हो पाया')), 'Hindi push');
      assert.ok(pushed.some((p) => p.endsWith(": Refund of ₹500 to Rajat Mondal didn't go through")), 'English push');
    } finally {
      console.log = log;
    }
    // Changing the app language (Profile → Language) changes what the server writes.
    const desk = await M.User.findOne({ phone: '9749681391' });
    const before = desk.language;
    ok(await ctx.desk('PATCH', '/api/me', { language: 'bn' }));
    assert.equal((await M.User.findById(desk._id)).language, 'bn');
    await notify([desk._id], { type: 'lang_check', title: 'Visit confirmed', push: false });
    assert.equal((await M.Notification.findOne({ userId: desk._id, type: 'lang_check' })).title, 'ভিজিট নিশ্চিত');
    ok(await ctx.desk('PATCH', '/api/me', { language: before || 'en' }));
  });

  await step('chat notices by role: doctors not buzzed per message, desk one notice per chat, settled on reply; history; payment links reused', async () => {
    const deskUser = String(ok(await ctx.desk('GET', '/api/me')).user.id);
    const convo = ctx.convoId;
    const notices = (uid) => M.Notification.find({ userId: uid, type: 'message', 'params.conversationId': new mongoose.Types.ObjectId(String(convo)), readAt: null });
    const settle = () => new Promise((r) => setTimeout(r, 400));
    await M.Notification.deleteMany({ type: 'message' });
    // The doctor hasn't written here for 2 h: a routine message is no notice for them at all.
    await M.Message.collection.updateMany({ conversationId: new mongoose.Types.ObjectId(String(convo)), senderId: new mongoose.Types.ObjectId(String(ctx.doctorUserId)) }, { $set: { createdAt: new Date(Date.now() - 3 * 3600e3) } });
    ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'When should I come for the sugar test?' }), 201);
    await settle();
    assert.equal((await notices(ctx.doctorUserId)).length, 0, 'no notice for the doctor on a routine message');
    assert.equal((await notices(deskUser)).length, 1, 'the desk gets one');
    // A second message soon after: still one notice for the desk, with the latest text.
    ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'Fasting or not?' }), 201);
    await settle();
    const deskNotices = await notices(deskUser);
    assert.equal(deskNotices.length, 1, 'one notice per chat');
    assert.equal(deskNotices[0].body, 'Fasting or not?');
    // The doctor answers (now in the conversation) → the desk's notice is settled …
    ok(await ctx.doc('POST', `/api/conversations/${convo}/messages`, { text: 'Fasting, please.' }), 201);
    await settle();
    assert.equal((await notices(deskUser)).length, 0, "someone answered: the desk's notice is read");
    // … and the patient's reply now reaches the doctor (they're in the middle of it).
    ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'Okay, thank you doctor.' }), 201);
    await settle();
    assert.equal((await notices(ctx.doctorUserId)).length, 1, 'a reply in an active conversation reaches the doctor');
    // A doctor without a front desk gets a summary at most every 2 h in reply hours, not a buzz per message.
    const jobs = require('../src/services/jobs');
    await jobs.chatRollup(new Date(new Date().setMinutes(0, 0, 0)));
    // (With a desk at this clinic there's no summary.)
    assert.equal(await M.Notification.countDocuments({ userId: ctx.doctorUserId, type: 'message_digest' }), 0, 'clinic with a desk: no summary');

    // History lists direct consultations too (no appointment) without failing.
    const hist = await ctx.doc('GET', '/api/history?period=last_3_months');
    assert.equal(hist.status, 200, `history: ${hist.status}`);

    // A payment link asked for twice is the same link (one per fee), re-sent.
    // A fee to collect from the app patient (so the chat card can be checked end to end).
    await M.Payment.create({ practiceId: ctx.practiceId, patientId: ctx.patientId, locationId: ctx.locationId, amount: 450, status: 'pending', purpose: 'consultation' }).catch(() => null);
    const due = ok(await ctx.doc('GET', '/api/payments?status=pending')).find((p) => p.amount === 450) || ok(await ctx.doc('GET', '/api/payments?status=pending')).find((p) => p.amount > 0);
    if (due) {
      const a = ok(await ctx.desk('POST', `/api/payments/${due.id}/link`));
      const b = ok(await ctx.desk('POST', `/api/payments/${due.id}/link`));
      assert.equal(a.paymentLinkUrl, b.paymentLinkUrl, 'same link re-sent');
      assert.ok(['app', 'sms'].includes(b.sentTo));
      // In the clinic chat once (a Pay card), not a new card per tap; one notice per fee.
      const cards = await M.Message.find({ 'meta.event': 'payment_request', 'meta.paymentId': String(due.id) });
      assert.equal(cards.length, 1, 'one payment card in the chat');
      const pt = await M.Patient.findById(due.patientId?.id || due.patientId?._id || due.patientId, 'userId');
      if (pt?.userId) {
        assert.equal(await M.Notification.countDocuments({ userId: pt.userId, type: 'payment_link', 'params.paymentId': String(due.id) }), 1, 'one notice per fee');
        const thread = ok(await ctx.doc('GET', `/api/conversations/${cards[0].conversationId}/messages`)).items.find((m) => m.id === String(cards[0]._id));
        assert.equal(thread.payment.status, 'pending', 'the card shows it is not paid yet');
        ok(await ctx.desk('POST', `/api/payments/${due.id}/mark-paid`, { method: 'cash' }));
        const after = ok(await ctx.doc('GET', `/api/conversations/${cards[0].conversationId}/messages`)).items.find((m) => m.id === String(cards[0]._id));
        assert.equal(after.payment.status, 'paid', 'and turns Paid once collected');
        console.log('    · payment card in chat checked');
      }
    }
  });

  await step('signed out = no more pushes, even when the phone never named its token', async () => {
    const { liveTokens } = require('../src/lib/devicetokens');
    const sec = require('../src/lib/security');
    const user = await M.User.findOne({ phone: '9230592842' });
    // A phone signed in to the patient account (a session as the OTP sign-in makes one).
    const signIn = async () => {
      const refreshToken = sec.randomToken();
      const s = await M.AuthSession.create({ userId: user._id, tokenHash: sec.sha256(refreshToken), platform: 'android', expiresAt: new Date(Date.now() + 864e5) });
      return { refreshToken, sessionId: s._id, call: api(sec.signAccess(user, s._id)) };
    };
    const a = await signIn();
    ok(await a.call('POST', '/api/me/devices', { token: 'phone-to-sign-out', platform: 'android' }));
    const row = await M.DeviceToken.findOne({ token: 'phone-to-sign-out' });
    assert.equal(String(row.sessionId), String(a.sessionId), 'the token remembers its sign-in session');
    assert.ok((await liveTokens({ userId: user._id })).includes('phone-to-sign-out'), 'signed-in phone is live');
    // Sign out without the token (offline / the app didn't know it): that session's phones are dropped.
    ok(await api()('POST', '/api/auth/logout', { refreshToken: a.refreshToken }));
    assert.equal(await M.DeviceToken.exists({ token: 'phone-to-sign-out' }), null);
    assert.ok(!(await liveTokens({ userId: user._id })).includes('phone-to-sign-out'));
    // A session that ended another way (expired): skipped and removed when sending.
    const b = await signIn();
    ok(await b.call('POST', '/api/me/devices', { token: 'phone-expired', platform: 'android' }));
    await M.AuthSession.updateOne({ _id: b.sessionId }, { expiresAt: new Date(Date.now() - 1000) });
    assert.ok(!(await liveTokens({ userId: user._id })).includes('phone-expired'), 'expired session dropped');
    assert.equal(await M.DeviceToken.exists({ token: 'phone-expired' }), null);
    // Another phone that stays signed in keeps getting pushes.
    const d = await signIn();
    ok(await d.call('POST', '/api/me/devices', { token: 'phone-still-in', platform: 'android' }));
    // An old-style row (no session recorded) stops once its user signs out after it was last seen.
    await M.DeviceToken.create({ userId: user._id, token: 'phone-legacy', platform: 'android', lastSeenAt: new Date(Date.now() - 60000) });
    const c = await signIn();
    ok(await api()('POST', '/api/auth/logout', { refreshToken: c.refreshToken }));
    const live = await liveTokens({ userId: user._id });
    assert.ok(!live.includes('phone-legacy'), 'old-style row dropped after a later sign-out');
    assert.ok(live.includes('phone-still-in'), 'a phone still signed in keeps its pushes');
  });

  await step('chat photos: shown as photos, read by MedPin AI; AI quiet while the doctor has the thread open', async () => {
    const convo = ctx.convoId;
    await M.Conversation.updateOne({ _id: convo }, { aiEnabled: true, aiPausedAt: null, staffViewingAt: null });
    // A photo of a medicine strip: its link stays the same between refreshes (the phone caches it).
    const photo = ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, undefined, { form: fileForm('file', tinyPng(), 'strip.png', 'image/png') }), 201);
    assert.equal(photo.message.kind, 'attachment');
    const urlOf = async () => ok(await ctx.pat('GET', `/api/conversations/${convo}/messages`)).items.find((m) => m.id === photo.message.id).attachment.url;
    assert.equal(await urlOf(), await urlOf(), 'a photo keeps its link across refreshes');
    // MedPin AI answers the question about it with the photo attached (AI stubbed: nothing is sent anywhere).
    const aiMod = require('../src/services/ai');
    const saved = { enabled: aiMod.enabled, completeJson: aiMod.completeJson };
    let seen = null;
    aiMod.enabled = () => true;
    aiMod.completeJson = async ({ messages, vision }) => {
      seen = { messages, vision };
      return { model: 'stub', data: { reply: 'The strip reads Telmisartan 40 mg — on your list from Dr. Sen: 1 in the morning after food.', urgency: 'none', needs_doctor: false, reason: 'none', cited_entry_ids: [] } };
    };
    try {
      const ask = ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'Give me details about this medicine' }), 201);
      assert.equal(ask.aiPending, true, 'nobody from the clinic is in the thread: MedPin AI answers');
      for (let i = 0; i < 30 && !seen; i += 1) await new Promise((r) => setTimeout(r, 100));
      assert.ok(seen, 'MedPin AI was asked');
      assert.equal(seen.vision, true, 'with vision');
      const last = seen.messages[seen.messages.length - 1];
      assert.ok(Array.isArray(last.content) && last.content.some((b) => b.type === 'image' && b.source.media_type === 'image/jpeg'), 'the photo goes with the question');
      assert.match(last.content[0].text, /\[photo\][\s\S]*Give me details about this medicine/);
      // The doctor opens the thread: MedPin AI stays quiet while they are there.
      seen = null;
      const opened = ok(await ctx.doc('GET', `/api/conversations/${convo}/messages`));
      assert.equal(opened.conversation.aiPaused, true, 'the banner tells the truth');
      const again = ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'And is it safe with my sugar tablet?' }), 201);
      assert.equal(again.aiPending, false, 'AI does not answer while the doctor is in the thread');
      await new Promise((r) => setTimeout(r, 300));
      assert.equal(seen, null, 'MedPin AI was not asked');
      // Two minutes after the doctor left, MedPin AI answers again.
      await M.Conversation.updateOne({ _id: convo }, { staffViewingAt: new Date(Date.now() - 3 * 60e3), aiPausedAt: null });
      const later = ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'Thank you' }), 201);
      assert.equal(later.aiPending, true);
    } finally {
      Object.assign(aiMod, saved);
      await new Promise((r) => setTimeout(r, 300));
    }
  });

  await step('chat round 1: ticks per side, delivered, bell clears on read, colleague messages, deletes, access, urgent', async () => {
    const convo = ctx.convoId;
    const convoOid = new (require('mongoose').Types.ObjectId)(String(convo));
    const me = async (call) => ok(await call('GET', '/api/me')).user?.id || ok(await call('GET', '/api/me')).id;
    const deskId = String((await M.Member.findOne({ practiceId: ctx.practiceId, role: 'front_desk', status: 'active' })).userId);
    const patUser = String((await M.Patient.findById(ctx.patientId)).userId);
    await M.Conversation.updateOne({ _id: convo }, { aiEnabled: false });

    // "Seen" belongs to the other side: the desk opening the thread doesn't mark the doctor's reply seen.
    const reply = ok(await ctx.doc('POST', `/api/conversations/${convo}/messages`, { text: 'Please come fasting tomorrow.' }), 201);
    ok(await ctx.desk('POST', `/api/conversations/${convo}/read`));
    assert.notEqual((await M.Message.findById(reply.message.id)).deliveryStatus, 'seen', "a colleague reading isn't the patient seeing it");
    // The patient's app polls its badges: the reply is delivered; reading it makes it seen.
    // (The badge poll does this at most once a minute; earlier steps already polled, so call it here.)
    ok(await ctx.pat('GET', '/api/notifications?limit=1'));
    await require('../src/services/care').markDelivered(patUser);
    assert.equal((await M.Message.findById(reply.message.id)).deliveryStatus, 'delivered');
    assert.ok(await M.Notification.exists({ userId: patUser, readAt: null, 'params.conversationId': convoOid }), 'the patient has a new-message notice');
    ok(await ctx.pat('POST', `/api/conversations/${convo}/read`));
    assert.equal((await M.Message.findById(reply.message.id)).deliveryStatus, 'seen');
    assert.equal(await M.Notification.exists({ userId: patUser, readAt: null, type: 'message', 'params.conversationId': convoOid }), null, 'reading the chat clears its bell notice');
    // The patient's message: seen once the clinic reads it.
    const q = ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'OK, what time?' }), 201);
    ok(await ctx.desk('POST', `/api/conversations/${convo}/read`));
    assert.equal((await M.Message.findById(q.message.id)).deliveryStatus, 'seen');
    // The patient's app sees no review flags or staff unread counts.
    const pv = ok(await ctx.pat('GET', `/api/conversations/${convo}/messages`));
    assert.equal(pv.conversation.participants, undefined, 'no staff list for the patient');
    assert.equal(pv.conversation.triage, undefined);

    // Staff only ever mark their own messages urgent: never.
    const staffUrgent = ok(await ctx.doc('POST', `/api/conversations/${convo}/messages`, { text: 'Calling you now', isUrgent: true }), 201);
    assert.equal(staffUrgent.message.isUrgent, false);
    // A patient's urgent message always has an emergency behind it, raised once.
    await M.Alert.updateMany({ conversationId: convo, kind: 'urgent_chat' }, { status: 'resolved' });
    ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'Feeling very dizzy', isUrgent: true }), 201);
    ok(await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'Still dizzy', isUrgent: true }), 201);
    assert.equal(await M.Alert.countDocuments({ conversationId: convo, kind: 'urgent_chat', status: { $in: ['open', 'acknowledged'] } }), 1, 'one open emergency, not one per message');
    await M.Alert.updateMany({ conversationId: convo, kind: 'urgent_chat' }, { status: 'resolved' });
    await M.Conversation.updateOne({ _id: convo }, { isUrgent: false });

    // Deleting: once only; the voice note and the bell text go too.
    const m4a = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypM4A '), Buffer.alloc(24)]);
    const vn = ok(await ctx.doc('POST', `/api/conversations/${convo}/messages`, undefined, { form: fileForm('file', m4a, 'note.m4a', 'audio/mp4', { durationSec: '99999' }) }), 201);
    assert.equal(vn.message.voice.durationSec, 3600, 'voice length is bounded');
    const urlA = ok(await ctx.pat('GET', `/api/conversations/${convo}/messages`)).items.find((m) => m.id === vn.message.id).voice.file.url;
    const urlB = ok(await ctx.pat('GET', `/api/conversations/${convo}/messages`)).items.find((m) => m.id === vn.message.id).voice.file.url;
    assert.equal(urlA, urlB, 'a voice note keeps its link (playback is not reset by the refresh)');
    const before = (await M.Conversation.findById(convo)).participants.find((p) => String(p.userId) === patUser).unreadCount;
    ok(await ctx.doc('DELETE', `/api/conversations/${convo}/messages/${vn.message.id}`));
    ok(await ctx.doc('DELETE', `/api/conversations/${convo}/messages/${vn.message.id}`));
    const after = (await M.Conversation.findById(convo)).participants.find((p) => String(p.userId) === patUser).unreadCount;
    assert.equal(after, Math.max(0, before - 1), 'deleting twice lowers the unread once');
    const gone = ok(await ctx.pat('GET', `/api/conversations/${convo}/messages`)).items.find((m) => m.id === vn.message.id);
    assert.equal(gone.deleted, true);
    assert.equal(gone.voice, undefined, 'a deleted voice note no longer plays');
    // A reply must quote a message of this chat.
    assert.equal((await ctx.pat('POST', `/api/conversations/${convo}/messages`, { text: 'hm', replyToId: '000000000000000000000000' })).status, 400);
    // Patients can't change the clinic's pinned message.
    assert.equal((await ctx.pat('POST', `/api/conversations/${convo}/pin`, { messageId: reply.message.id })).status, 403);

    // A colleague's message tells the other person at once.
    const direct = ok(await ctx.doc('POST', '/api/inbox', { userId: deskId }), 201);
    ok(await ctx.doc('POST', `/api/conversations/${direct._id || direct.id}/messages`, { text: 'Please call Mrs Sharma about tomorrow.' }), 201);
    assert.ok(await M.Notification.exists({ userId: deskId, type: 'message', 'params.conversationId': new (require('mongoose').Types.ObjectId)(String(direct._id || direct.id)) }), 'the colleague is notified');

    // Nutrition chats are the dietician's and doctors': the front desk can't open them.
    const nutrition = await require('../src/services/care').careConversation(ctx.patientId, ctx.practiceId, 'nutrition');
    assert.equal((await ctx.desk('GET', `/api/conversations/${nutrition._id}/messages`)).status, 404);
    // Someone who left the clinic loses its chats.
    const deskMember = await M.Member.findOne({ practiceId: ctx.practiceId, userId: deskId });
    await M.Member.updateOne({ _id: deskMember._id }, { status: 'suspended' });
    assert.equal((await ctx.desk('GET', `/api/conversations/${convo}/messages`)).status === 200, false, 'no access after leaving the clinic');
    await M.Member.updateOne({ _id: deskMember._id }, { status: 'active' });
    void me;
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

// Consult-Pick, Consult-Page, Consult-Blank, Consult-Vitals, Consult-Diagnosis,
// Consult-Dosage, Consult-Advice, Prescriptions.
const { Router } = require('express');
const M = require('../models');
const T = require('../lib/time');
const { requireAuth, staff, patientInPractice, ownPractice } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, escapeRegex } = require('../lib/http');
const storage = require('../services/storage');
const { checkItems, patientSummary, issueConsultation } = require('../services/clinical');
const { careConversation, postMessage } = require('../services/care');
const { transition } = require('../services/scheduling');
const { notify } = require('../services/notify');

const r = Router();
r.use(requireAuth, staff());

const getConsult = async (req) => {
  const c = ownPractice(req, await M.Consultation.findById(req.params.id), 'Consultation');
  return c;
};

// Consult-Pick: waiting now + recent patients + search.
r.get('/consultations/pick', async (req, res) => {
  const today = T.dayStart();
  const text = String(req.query.q || '').trim();
  const ids = await M.PatientEnrolment.find({ practiceId: req.practiceId, status: 'linked' }).distinct('patientId');
  let matches = [];
  if (text) {
    const digits = text.replace(/\D/g, '');
    const or = [{ name: new RegExp(escapeRegex(text), 'i') }];
    if (digits.length >= 3) or.push({ phone: new RegExp(escapeRegex(digits.replace(/^91(?=\d{10}$)/, ''))) });
    matches = await M.Patient.find({ _id: { $in: ids }, $or: or }).limit(20);
  }
  const waiting = await M.Appointment.find({ practiceId: req.practiceId, date: today, status: 'waiting', ...(req.query.locationId ? { locationId: req.query.locationId } : {}) })
    .sort({ tokenNo: 1 }).populate('patientId', 'name gender ageYears ageRecordedAt phone');
  const recentIds = await M.Consultation.find({ practiceId: req.practiceId, doctorId: req.user._id }).sort({ startedAt: -1 }).limit(30).distinct('patientId');
  const recent = await M.Patient.find({ _id: { $in: recentIds.slice(0, 10) } });
  const row = (p) => ({ id: p._id, name: p.name, age: T.ageFrom(p), gender: p.gender, phone: p.phone });
  res.json({
    matches: matches.map(row),
    waiting: waiting.map((a) => ({ appointmentId: a._id, token: String(a.tokenNo).padStart(2, '0'), waitingMin: a.arrivedAt ? Math.round((Date.now() - a.arrivedAt) / 60000) : null, patient: row(a.patientId) })),
    recent: recent.map(row),
  });
});

// Start (or resume) a consultation.
r.post('/consultations', staff({ perm: 'prescribe' }), async (req, res) => {
  const { patientId, appointmentId } = req.body;
  let appt = null;
  if (appointmentId) {
    appt = ownPractice(req, await M.Appointment.findById(appointmentId), 'Appointment');
    const existing = await M.Consultation.findOne({ appointmentId, status: 'draft' });
    if (existing) return res.json(existing);
    if (['booked', 'confirmed'].includes(appt.status)) await transition(appt, 'waiting', { by: req.user._id });
    if (appt.status === 'waiting') await transition(appt, 'in_consultation', { by: req.user._id });
  }
  const pid = appt ? appt.patientId : patientId;
  await patientInPractice(req, pid);
  // The treating doctor joins the patient's care team (the patient can change access later).
  const hasPrimary = await M.CareTeamAccess.exists({ patientId: pid, isPrimary: true });
  await M.CareTeamAccess.updateOne(
    { patientId: pid, userId: req.user._id },
    { $setOnInsert: { practiceId: req.practiceId, role: 'doctor', accessLevel: 'full_record', since: new Date(), isPrimary: !hasPrimary } },
    { upsert: true },
  );
  const consult = await M.Consultation.create({
    practiceId: req.practiceId, locationId: appt?.locationId || req.body.locationId || req.user.activeLocationId,
    doctorId: req.user._id, patientId: pid, appointmentId: appt?._id,
    vitalsId: appt ? (await M.Vitals.findOne({ appointmentId: appt._id }).sort({ recordedAt: -1 }))?._id : undefined,
  });
  return res.status(201).json(consult);
});

r.get('/consultations/:id', async (req, res) => {
  const c = await getConsult(req);
  const patient = await M.Patient.findById(c.patientId);
  const [summary, vitals, previous] = await Promise.all([
    patientSummary(patient, req.practiceId),
    c.vitalsId ? M.Vitals.findById(c.vitalsId) : null,
    M.Consultation.findOne({ patientId: c.patientId, status: { $ne: 'draft' }, _id: { $ne: c._id } }).sort({ startedAt: -1 }),
  ]);
  res.json({ consultation: c, vitals, summary, previousDiagnoses: previous?.diagnoses || [], previousVisitAt: previous?.startedAt || null });
});

const RX_ITEM_FIELDS = ['medicineId', 'name', 'strength', 'form', 'dose', 'frequency', 'weekday', 'foodRelation', 'instructions', 'duration', 'quantity', 'change', 'caution', 'entrySource'];
r.patch('/consultations/:id', async (req, res) => {
  const c = await getConsult(req);
  if (c.status !== 'draft') throw conflict('This prescription was already generated', 'ALREADY_ISSUED');
  const body = pick(req.body, ['chiefComplaint', 'complaintLanguage', 'printVitalsOnRx', 'diagnoses', 'labOrders', 'advice', 'validity', 'followUp', 'locationId']);
  if (body.diagnoses) body.diagnoses = body.diagnoses.map((d) => ({ ...d, name: d.source === 'custom' && d.name ? d.name[0].toUpperCase() + d.name.slice(1) : d.name }));
  if (body.labOrders) {
    const seen = new Set();
    body.labOrders = body.labOrders.filter((t) => t.testName && !seen.has(t.testName.toLowerCase()) && seen.add(t.testName.toLowerCase()));
  }
  if (req.body.medications) {
    const items = req.body.medications.map((m) => pick(m, RX_ITEM_FIELDS));
    for (const m of items) {
      const d = m.dose || {};
      if (m.frequency !== 'weekly' && m.frequency !== 'as_needed' && !((d.morning || 0) + (d.afternoon || 0) + (d.night || 0))) {
        throw badRequest(`${m.name}: choose at least one dose a day`, 'DOSE_REQUIRED');
      }
    }
    const patient = await M.Patient.findById(c.patientId);
    const checks = await checkItems(patient, items);
    items.forEach((m, i) => {
      const allergy = checks[i].warnings.find((w) => w.type === 'allergy');
      if (allergy && !m.caution) m.caution = allergy.text;
      if (!m.medicineId && checks[i].medicineId) m.medicineId = checks[i].medicineId;
    });
    body.medications = items;
  }
  Object.assign(c, body);
  c.draftSavedAt = new Date();
  await c.save();
  res.json(c);
});

// Allergy clashes and catalog strength warnings for the draft medicines.
r.get('/consultations/:id/checks', async (req, res) => {
  const c = await getConsult(req);
  const patient = await M.Patient.findById(c.patientId);
  res.json(await checkItems(patient, c.medications));
});

// "From your past prescriptions" and "Suggested for this diagnosis".
r.get('/consultations/:id/suggestions', async (req, res) => {
  const c = await getConsult(req);
  const past = await M.Prescription.find({ patientId: c.patientId, doctorId: req.user._id }).sort({ issuedAt: -1 }).limit(3);
  const pastItems = [...new Map(past.flatMap((p) => p.items).map((i) => [`${i.name} ${i.strength}`, i])).values()];
  const dx = c.diagnoses.map((d) => d.name);
  let forDiagnosis = [];
  if (dx.length) {
    const others = await M.Consultation.aggregate([
      { $match: { practiceId: req.practiceId, status: { $ne: 'draft' }, 'diagnoses.name': { $in: dx } } },
      { $unwind: '$medications' },
      { $group: { _id: { name: '$medications.name', strength: '$medications.strength' }, n: { $sum: 1 }, item: { $first: '$medications' } } },
      { $sort: { n: -1 } },
      { $limit: 5 },
    ]);
    forDiagnosis = others.map((o) => ({ ...o.item, reason: `Prescribed ${o.n} times for ${dx[0]}` }));
  }
  const tests = await M.LabTest.find(dx.some((d) => /diabet/i.test(d)) ? { panel: 'Diabetes panel' } : dx.some((d) => /thyroid/i.test(d)) ? { panel: 'Thyroid panel' } : { _id: null });
  res.json({ fromPastPrescriptions: pastItems, forDiagnosis, tests: tests.map((t) => ({ testName: t.name, panel: t.panel, source: 'ai' })) });
});

r.post('/consultations/:id/vitals', async (req, res) => {
  const c = await getConsult(req);
  const v = pick(req.body, ['bpSystolic', 'bpDiastolic', 'pulse', 'spo2', 'temperatureF', 'weightKg', 'heightCm', 'bloodSugar', 'sugarType', 'note']);
  const patient = await M.Patient.findById(c.patientId);
  const h = v.heightCm || patient.heightCm;
  const vitals = await M.Vitals.create({
    ...v, patientId: c.patientId, practiceId: req.practiceId, appointmentId: c.appointmentId, consultationId: c._id,
    recordedBy: req.user._id, recordedByRole: req.member.role, source: 'clinic', bmi: h && v.weightKg ? +(v.weightKg / (h / 100) ** 2).toFixed(1) : undefined,
  });
  c.vitalsId = vitals._id;
  await c.save();
  if (v.heightCm || v.weightKg) await M.Patient.updateOne({ _id: c.patientId }, pick(v, ['heightCm', 'weightKg']));
  res.status(201).json(vitals);
});

// "Generate prescription"
r.post('/consultations/:id/issue', staff({ perm: 'prescribe' }), async (req, res) => {
  const c = await getConsult(req);
  if (String(c.doctorId) !== String(req.user._id)) throw conflict('Only the doctor who started this consultation can issue it', 'NOT_YOUR_CONSULTATION');
  const rx = await issueConsultation(c, req.user);
  if (c.appointmentId) {
    const appt = await M.Appointment.findById(c.appointmentId);
    if (appt && appt.status === 'in_consultation') await transition(appt, 'completed', { by: req.user._id });
  }
  res.json({ consultation: c, prescription: { ...rx.toJSON(), file: storage.withUrl(rx.file) } });
});

// "Send prescription" — needs the doctor's digital signature.
r.post('/prescriptions/:id/send', staff({ perm: 'prescribe' }), async (req, res) => {
  const rx = ownPractice(req, await M.Prescription.findById(req.params.id), 'Prescription');
  const profile = await M.DoctorProfile.findOne({ userId: rx.doctorId }, 'signature');
  if (!profile?.signature?.key) throw conflict("Add your digital signature first — prescriptions can't be sent without it", 'SIGNATURE_REQUIRED');
  const convo = await careConversation(rx.patientId, req.practiceId);
  await postMessage(convo, {
    sender: req.user, senderType: 'doctor', kind: 'record', prescriptionId: rx._id,
    text: `Prescription · ${T.dayKey(rx.issuedAt)} · ${rx.items.length} medicines${rx.tests.length ? ` · ${rx.tests.length} tests` : ''}`,
  });
  rx.sentAt = new Date();
  await rx.save();
  await M.Consultation.updateOne({ prescriptionId: rx._id }, { status: 'sent' });
  const patient = await M.Patient.findById(rx.patientId, 'userId name');
  if (patient.userId) await notify([patient.userId], { type: 'prescription', practiceId: req.practiceId, title: 'Your prescription is ready', screen: 'Patient-Records', whatsapp: true });
  res.json({ ...rx.toJSON(), file: storage.withUrl(rx.file) });
});

r.get('/prescriptions/:id', async (req, res) => {
  const rx = await M.Prescription.findById(req.params.id);
  if (!rx) throw notFound('Prescription');
  await patientInPractice(req, rx.patientId);
  res.json({ ...rx.toJSON(), file: storage.withUrl(rx.file) });
});

module.exports = r;

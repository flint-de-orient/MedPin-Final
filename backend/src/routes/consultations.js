// Consult-Pick, Consult-Page, Consult-Blank, Consult-Vitals, Consult-Diagnosis,
// Consult-Dosage, Consult-Advice, Prescriptions.
const { Router } = require('express');
const M = require('../models');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice, ownPractice } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, escapeRegex, forbidden } = require('../lib/http');
const storage = require('../services/storage');
const { checkItems, patientSummary, issueConsultation, ensurePrescriptionPdf } = require('../services/clinical');
const { careConversation, postMessage } = require('../services/care');
const { transition } = require('../services/scheduling');
const { notify } = require('../services/notify');

const { accessFor } = require('../services/access');
const r = Router();
r.use(requireAuth, staff());

/** The consultation; with [mine], only for the doctor treating (colleagues may read it). */
const getConsult = async (req, { mine = false } = {}) => {
  const c = ownPractice(req, await M.Consultation.findById(req.params.id), 'Consultation');
  if (mine && String(c.doctorId) !== String(req.user._id)) throw forbidden("This is another doctor's consultation. Only they can change it.", 'NOT_YOUR_CONSULTATION');
  return c;
};

// Consult-Pick: waiting now + recent patients + search.
r.get('/consultations/pick', need('prescribe'), async (req, res) => {
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
  const waiting = await M.Appointment.find({ practiceId: req.practiceId, doctorId: req.user._id, date: today, status: 'waiting', ...(req.query.locationId ? { locationId: req.query.locationId } : {}) })
    .sort({ startAt: 1, tokenNo: 1 }).populate('patientId', 'name gender ageYears ageRecordedAt phone');
  // The patients this doctor saw last, most recent first (distinct() would ignore the order).
  const recentIds = (await M.Consultation.aggregate([
    { $match: { practiceId: req.practiceId, doctorId: req.user._id } },
    { $sort: { startedAt: -1 } },
    { $group: { _id: '$patientId', at: { $first: '$startedAt' } } },
    { $sort: { at: -1 } },
    { $limit: 10 },
  ])).map((x) => String(x._id));
  const found = await M.Patient.find({ _id: { $in: recentIds } });
  const recent = recentIds.map((id) => found.find((p) => String(p._id) === id)).filter(Boolean);
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
    if (String(appt.doctorId) !== String(req.user._id)) {
      const doc = await M.User.findById(appt.doctorId, 'name');
      throw forbidden(`This visit is with ${doc?.name || 'another doctor'}. Ask the front desk to move it to you first.`, 'NOT_YOUR_VISIT');
    }
    if (['completed', 'cancelled', 'rescheduled', 'missed'].includes(appt.status)) throw conflict('This visit is closed. Start a consultation from the patient instead.', 'VISIT_CLOSED');
    const existing = await M.Consultation.findOne({ appointmentId, doctorId: req.user._id, status: 'draft' });
    if (existing) return res.json(existing);
    if (['booked', 'confirmed'].includes(appt.status)) await transition(appt, 'waiting', { by: req.user._id });
    if (appt.status === 'waiting') await transition(appt, 'in_consultation', { by: req.user._id });
  }
  const pid = appt ? appt.patientId : patientId;
  await patientInPractice(req, pid);
  if (!appt) {
    // One open consultation per doctor and patient: reopen the draft instead of adding another.
    const draft = await M.Consultation.findOne({ practiceId: req.practiceId, doctorId: req.user._id, patientId: pid, status: 'draft' }).sort({ startedAt: -1 });
    if (draft) return res.json(draft);
  }
  // The treating doctor joins the patient's care team (the patient can change access later).
  const hasPrimary = await M.CareTeamAccess.exists({ patientId: pid, isPrimary: true });
  await M.CareTeamAccess.updateOne(
    { patientId: pid, userId: req.user._id },
    { $setOnInsert: { practiceId: req.practiceId, role: 'doctor', accessLevel: 'full_record', since: new Date(), isPrimary: !hasPrimary } },
    { upsert: true },
  );
  // Where it happens (prints that location's letterhead): the visit's, the one chosen, else the doctor's first location here.
  const locationId = appt?.locationId || req.body.locationId || req.user.activeLocationId
    || (await M.DoctorLocation.findOne({ doctorId: req.user._id, practiceId: req.practiceId }, 'locationId').sort({ createdAt: 1 }))?.locationId;
  const consult = await M.Consultation.create({
    practiceId: req.practiceId, locationId,
    doctorId: req.user._id, patientId: pid, appointmentId: appt?._id,
    vitalsId: appt ? (await M.Vitals.findOne({ appointmentId: appt._id }).sort({ recordedAt: -1 }))?._id : undefined,
  });
  return res.status(201).json(consult);
});

// Leaving a consultation that was never filled in: the empty draft is removed.
r.delete('/consultations/:id', need('prescribe'), async (req, res) => {
  const c = ownPractice(req, await M.Consultation.findById(req.params.id), 'Consultation');
  if (String(c.doctorId) !== String(req.user._id)) throw Object.assign(new Error('Only the treating doctor can discard this draft'), { status: 403, code: 'NOT_YOURS' });
  const empty = c.status === 'draft' && !c.chiefComplaint && !c.diagnoses?.length && !c.medications?.length && !c.labOrders?.length && !c.advice?.items?.length && !c.advice?.freeText;
  if (!empty) return res.json({ ok: true, kept: true });
  await c.deleteOne();
  // Opened from the waiting list and left without writing anything: the patient goes back
  // to waiting (not stuck "with the doctor").
  if (c.appointmentId) {
    const appt = await M.Appointment.findById(c.appointmentId);
    if (appt?.status === 'in_consultation' && !(await M.Consultation.exists({ appointmentId: appt._id }))) {
      appt.consultStartedAt = undefined;
      await transition(appt, 'waiting', { by: req.user._id }).catch((err) => console.warn('[back to waiting]', err.message));
    }
  }
  res.json({ ok: true, deleted: true, backToWaiting: Boolean(c.appointmentId) });
});

r.get('/consultations/:id', need('clinical'), async (req, res) => {
  const c = await getConsult(req);
  const patient = await M.Patient.findById(c.patientId);
  const [summary, vitals, previous] = await Promise.all([
    accessFor({ userId: req.user._id, practiceId: req.practiceId }, patient).then((acc) => patientSummary(patient, req.practiceId, acc)),
    c.vitalsId ? M.Vitals.findById(c.vitalsId) : null,
    accessFor({ userId: req.user._id, practiceId: req.practiceId }, patient).then((acc) =>
      M.Consultation.findOne({ patientId: c.patientId, ...acc.consultationFilter(), status: { $ne: 'draft' }, _id: { $ne: c._id } }).sort({ startedAt: -1 })),
  ]);
  res.json({ consultation: c, vitals, summary, previousDiagnoses: previous?.diagnoses || [], previousVisitAt: previous?.startedAt || null });
});

const RX_ITEM_FIELDS = ['medicineId', 'name', 'strength', 'form', 'dose', 'frequency', 'weekday', 'foodRelation', 'instructions', 'duration', 'quantity', 'change', 'caution', 'entrySource'];
r.patch('/consultations/:id', need('prescribe'), async (req, res) => {
  const c = await getConsult(req, { mine: true });
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
r.get('/consultations/:id/checks', need('prescribe'), async (req, res) => {
  const c = await getConsult(req);
  const patient = await M.Patient.findById(c.patientId);
  res.json(await checkItems(patient, c.medications));
});

// "Preview": the draft as its prescription PDF, before Generate (nothing is issued).
r.get('/consultations/:id/preview', need('prescribe'), async (req, res) => {
  const c = await getConsult(req, { mine: true });
  const file = await require('../services/clinical').previewPrescriptionPdf(c, req.user);
  res.json(storage.withUrl(file));
});

// MedPin AI: possible diagnoses, tests and medicine options for the doctor to pick from.
r.post('/consultations/:id/ai-suggestions', need('prescribe'), async (req, res) => {
  const c = await getConsult(req, { mine: true });
  const acc = await accessFor({ userId: req.user._id, practiceId: req.practiceId }, await M.Patient.findById(c.patientId));
  res.json(await require('../services/consultai').suggest(c, { force: req.body?.refresh === true, acc }));
});

// "From your past prescriptions" and "Suggested for this diagnosis".
r.get('/consultations/:id/suggestions', need('prescribe'), async (req, res) => {
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
  res.json({ fromPastPrescriptions: pastItems, forDiagnosis, tests: tests.map((t) => ({ testName: t.name, panel: t.panel, source: 'panel' })) });
});

r.post('/consultations/:id/vitals', need('vitals'), async (req, res) => {
  const c = await getConsult(req, { mine: req.member.role === 'doctor' });
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
  if (String(rx.doctorId) !== String(req.user._id)) throw forbidden('Only the doctor who wrote this prescription can send it', 'NOT_YOUR_PRESCRIPTION');
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
  if (patient.userId) await notify([patient.userId], { forPatientId: patient._id, type: 'prescription', practiceId: req.practiceId, title: 'Your prescription is ready', screen: 'Patient-Records', whatsapp: true });
  res.json({ ...rx.toJSON(), file: storage.withUrl(rx.file) });
});

// ── Correcting, cancelling and repeating an issued prescription ──
/** The doctor's own issued prescription, with the consultation it came from. */
async function ownIssued(req) {
  const rx = ownPractice(req, await M.Prescription.findById(req.params.id), 'Prescription');
  if (String(rx.doctorId) !== String(req.user._id)) throw forbidden('Only the doctor who wrote this prescription can change it', 'NOT_YOUR_PRESCRIPTION');
  return rx;
}

/** A new draft for the patient copied from [rx]'s consultation (a correction or a repeat). */
async function draftFrom(req, rx, { amend }) {
  const from = rx.consultationId ? await M.Consultation.findById(rx.consultationId).lean() : null;
  const meds = (from?.medications?.length ? from.medications : rx.items || []).map((m) => {
    const { _id, ...rest } = m.toObject ? m.toObject() : m;
    return { ...rest, change: amend ? rest.change : 'continued' };
  });
  return M.Consultation.create({
    practiceId: req.practiceId, locationId: rx.locationId || from?.locationId, doctorId: req.user._id, patientId: rx.patientId,
    chiefComplaint: from?.chiefComplaint || (amend ? undefined : 'Repeat prescription'), complaintLanguage: from?.complaintLanguage,
    diagnoses: from?.diagnoses || [], medications: meds, labOrders: amend ? from?.labOrders || [] : [],
    advice: from?.advice || { items: [], freeText: rx.advice || '' }, validity: from?.validity, followUp: amend ? from?.followUp : { enabled: false },
    ...(amend ? { amendsRxId: rx._id } : {}),
  });
}

// "Correct this prescription": a draft to fix and issue; issuing it replaces this one.
r.post('/prescriptions/:id/amend', staff({ perm: 'prescribe' }), async (req, res) => {
  const rx = await ownIssued(req);
  if (rx.status !== 'issued') throw conflict('This prescription was already replaced or cancelled', 'NOT_ISSUED');
  const open = await M.Consultation.findOne({ amendsRxId: rx._id, status: 'draft', doctorId: req.user._id });
  res.status(201).json(open || (await draftFrom(req, rx, { amend: true })));
});

// "Repeat": the same medicines (continued) in a new draft for today.
r.post('/prescriptions/:id/repeat', staff({ perm: 'prescribe' }), async (req, res) => {
  const rx = ownPractice(req, await M.Prescription.findById(req.params.id), 'Prescription');
  await patientInPractice(req, rx.patientId);
  res.status(201).json(await draftFrom(req, rx, { amend: false }));
});

// "Cancel prescription" (written by mistake, wrong patient): its medicines stop and the patient
// is told not to take them. It stays in the record, marked cancelled, with why.
r.post('/prescriptions/:id/cancel', staff({ perm: 'prescribe' }), async (req, res) => {
  const rx = await ownIssued(req);
  const reason = String(req.body.reason || '').trim().slice(0, 300);
  if (!reason) throw badRequest('Say why it is cancelled', 'REASON_REQUIRED');
  const done = await M.Prescription.findOneAndUpdate({ _id: rx._id, status: 'issued' }, { status: 'cancelled', cancelledAt: new Date(), cancelReason: reason, cancelledBy: req.user._id }, { new: true });
  if (!done) throw conflict('This prescription was already replaced or cancelled', 'NOT_ISSUED');
  const now = new Date();
  await M.MedicationCourse.updateMany({ prescriptionId: rx._id, status: 'active' }, { status: 'stopped', stoppedAt: now, stoppedReason: 'Prescription cancelled by the doctor' });
  await M.DoseLog.deleteMany({ courseId: { $in: await M.MedicationCourse.find({ prescriptionId: rx._id }).distinct('_id') }, status: 'due', scheduledAt: { $gt: now } });
  if (rx.consultationId) await M.FollowUp.updateMany({ consultationId: rx.consultationId, status: { $in: ['not_booked', 'no_reply'] } }, { status: 'cancelled' });
  await M.MedicalRecord.updateMany({ prescriptionId: rx._id }, { flagLabel: 'Cancelled', flagTone: 'muted' });
  require('../services/reminders').remindersChanged(rx.patientId);
  const patient = await M.Patient.findById(rx.patientId, 'userId');
  if (patient?.userId) {
    await notify([patient.userId], {
      forPatientId: patient._id, type: 'prescription_cancelled', practiceId: req.practiceId, whatsapp: true,
      title: `${req.user.name || 'Your doctor'} cancelled a prescription`, body: `Stop the medicines from the prescription of ${T.dayKey(rx.issuedAt)}. ${reason}`,
      screen: 'Patient-Records',
    }).catch(() => {});
  }
  res.json({ ...done.toJSON(), file: storage.withUrl(done.file) });
});

/** A prescription this person may open: their clinic's, or another clinic's the patient shares here. */
async function visibleRx(req) {
  const rx = await M.Prescription.findById(req.params.id);
  if (!rx) throw notFound('Prescription');
  const patient = await patientInPractice(req, rx.patientId);
  if (String(rx.practiceId) !== String(req.practiceId)) {
    const acc = await accessFor({ userId: req.user._id, practiceId: req.practiceId }, patient);
    if (!acc.allows('prescriptions_and_tests')) throw notFound('Prescription');
  }
  return rx;
}

r.get('/prescriptions/:id', async (req, res) => {
  const rx = await visibleRx(req);
  res.json({ ...rx.toJSON(), file: storage.withUrl(rx.file) });
});

// View / Download: a fresh link to the PDF (drawn again if it predates the current layout).
r.get('/prescriptions/:id/pdf', async (req, res) => {
  const rx = await visibleRx(req);
  await ensurePrescriptionPdf(rx);
  if (!rx.file?.key) throw notFound('Prescription PDF');
  res.json(storage.withUrl(rx.file));
});

module.exports = r;

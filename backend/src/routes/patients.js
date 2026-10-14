// Doctor-Patients, Doctor-Patients-Search, Add-Patient, Add-Patient-Existing,
// Consult-QuickAdd, Patient-Profile, PP-Summary, PP-Tests, PP-Prescriptions, PP-Treatment.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, staff, need, patientInPractice } = require('../middleware/auth');
const { pick, badRequest, conflict, notFound, normalizePhone, escapeRegex, paging, forbidden } = require('../lib/http');
const { hmac, safeEqual } = require('../lib/security');
const storage = require('../services/storage');
const { patientSummary } = require('../services/clinical');
const { adherence, checkReading } = require('../services/care');
const { notify } = require('../services/notify');
const { extractLabReport } = require('../services/assistant');
const { issueOtp, checkOtp } = require('./auth');

const { uploader } = require('../lib/uploads');
const upload = uploader({ kinds: ['image', 'pdf'], maxMb: 10, maxFiles: 10 });
const { accessFor } = require('../services/access');
const r = Router();
r.use(requireAuth, staff({ perm: 'viewPatients' }));
const canEdit = (req) => {
  if (!req.perms.editRecords) throw forbidden("Your role can't edit patient records", 'PERMISSION_REQUIRED');
};

/**
 * Which branch each patient goes to, from their visits here: usual (most
 * completed visits; else where they were registered), last (branch and date of
 * the last visit) and every branch they've been seen at. One record per
 * patient — the branch only says where things happened.
 */
async function branchesOf(practiceId, patientIds) {
  const [visits, enrolments, locations] = await Promise.all([
    M.Appointment.aggregate([
      { $match: { practiceId, patientId: { $in: patientIds }, status: { $nin: ['cancelled', 'rescheduled'] }, locationId: { $ne: null } } },
      { $group: { _id: { p: '$patientId', l: '$locationId' }, done: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } }, any: { $sum: 1 }, lastDone: { $max: { $cond: [{ $eq: ['$status', 'completed'] }, '$completedAt', null] } } } },
    ]),
    M.PatientEnrolment.find({ practiceId, patientId: { $in: patientIds } }, 'patientId homeLocationId').lean(),
    M.Location.find({ practiceId }, 'name shortName').lean(),
  ]);
  const loc = new Map(locations.map((l) => [String(l._id), { id: l._id, name: l.shortName || l.name }]));
  const home = new Map(enrolments.map((e) => [String(e.patientId), e.homeLocationId && String(e.homeLocationId)]));
  const out = new Map();
  for (const id of patientIds.map(String)) {
    const mine = visits.filter((v) => String(v._id.p) === id);
    const byDone = [...mine].sort((a, b) => b.done - a.done || b.any - a.any);
    const last = [...mine].filter((v) => v.lastDone).sort((a, b) => b.lastDone - a.lastDone)[0];
    const usualId = byDone[0]?.done ? String(byDone[0]._id.l) : home.get(id) || (byDone[0] ? String(byDone[0]._id.l) : null);
    out.set(id, {
      usual: usualId ? loc.get(usualId) || null : null,
      last: last ? { ...loc.get(String(last._id.l)), at: last.lastDone } : null,
      seenAt: [...new Set([...mine.map((v) => String(v._id.l)), home.get(id)].filter(Boolean))],
    });
  }
  return out;
}

/** Where a new patient is registered: the branch given, the user's current one, or their only one. */
async function registrationBranch(req) {
  const valid = (id) => id && /^[0-9a-f]{24}$/i.test(String(id));
  if (valid(req.body.locationId)) return req.body.locationId;
  if (req.member.locationIds?.length === 1) return req.member.locationIds[0];
  if (req.user.activeLocationId) return req.user.activeLocationId;
  const locs = await M.Location.find({ practiceId: req.practiceId, status: { $ne: 'inactive' } }, '_id').limit(2);
  return locs.length === 1 ? locs[0]._id : undefined;
}

const listRow = (p, extra = {}) => ({
  id: p._id, name: p.name, phone: p.phone, gender: p.gender, age: T.ageFrom(p),
  conditions: p.conditions.map((c) => c.name), allergies: p.allergies.map((a) => a.allergen), riskLevel: p.riskLevel, hasApp: Boolean(p.userId), ...extra,
});

// List with filters: all | today | follow_up_due | abnormal; sort: recent | name.
r.get('/patients', async (req, res) => {
  const { limit, skip } = paging(req.query);
  const ids = await M.PatientEnrolment.find({ practiceId: req.practiceId, status: 'linked' }).distinct('patientId');
  const q = { _id: { $in: ids } };
  const text = String(req.query.q || '').trim();
  if (text) {
    const digits = text.replace(/\D/g, '').replace(/^91(?=\d{10}$)/, '');
    q.$or = [{ name: new RegExp(escapeRegex(text), 'i') }, ...(digits.length >= 3 ? [{ phone: new RegExp(escapeRegex(digits)) }] : [])];
  }
  const today = T.dayStart();
  const [todayIds, dueIds, abnormalIds] = await Promise.all([
    M.Appointment.find({ practiceId: req.practiceId, date: today, status: { $nin: ['cancelled', 'rescheduled'] } }).distinct('patientId'),
    M.FollowUp.find({ practiceId: req.practiceId, status: { $in: ['not_booked', 'no_reply'] }, dueDate: { $lte: T.addDays(today, 7) } }).distinct('patientId'),
    M.LabResult.find({ patientId: { $in: ids }, abnormalCount: { $gt: 0 }, collectedAt: { $gte: T.addDays(today, -90) }, 'reviewed.at': null }).distinct('patientId'),
  ]);
  const filter = req.query.filter || 'all';
  const restrict = { today: todayIds, follow_up_due: dueIds, abnormal: abnormalIds }[filter];
  if (restrict) q._id = { $in: restrict.filter((id) => ids.some((x) => String(x) === String(id))) };

  const lastVisits = await M.Appointment.aggregate([
    { $match: { practiceId: req.practiceId, status: 'completed' } },
    { $group: { _id: '$patientId', at: { $max: '$completedAt' } } },
  ]);
  const lv = new Map(lastVisits.map((x) => [String(x._id), x.at]));
  let patients = await M.Patient.find(q);
  const branch = await branchesOf(req.practiceId, patients.map((p) => p._id));
  // ?locationId=: patients seen at (or registered at) that branch; one seen at both shows under both.
  const at = String(req.query.locationId || '');
  if (/^[0-9a-f]{24}$/i.test(at)) patients = patients.filter((p) => branch.get(String(p._id))?.seenAt.includes(at));
  const rows = patients.map((p) => listRow(p, { lastVisitAt: lv.get(String(p._id)) || null, branch: branch.get(String(p._id)) }));
  if (req.query.sort === 'name') rows.sort((a, b) => a.name.localeCompare(b.name));
  else rows.sort((a, b) => new Date(b.lastVisitAt || 0) - new Date(a.lastVisitAt || 0));
  res.json({
    counts: { all: ids.length, today: todayIds.length, followUpDue: dueIds.length, abnormal: abnormalIds.length },
    locations: (await M.Location.find({ practiceId: req.practiceId, status: { $ne: 'inactive' } }, 'name shortName').sort({ createdAt: 1 }).lean()).map((l) => ({ id: l._id, name: l.shortName || l.name })),
    total: rows.length,
    items: rows.slice(skip, skip + limit),
  });
});

// Add-Patient: does this phone already have a MedPin record?
r.get('/patients/lookup', async (req, res) => {
  const phone = normalizePhone(req.query.phone);
  const patient = await M.Patient.findOne({ phone });
  if (!patient) return res.json({ exists: false });
  const linked = await M.PatientEnrolment.exists({ patientId: patient._id, practiceId: req.practiceId, status: 'linked' });
  // Details only once the patient is linked to this practice.
  return res.json({ exists: true, linked: Boolean(linked), hasApp: Boolean(patient.userId), ...(linked ? { patient: listRow(patient) } : {}) });
});

r.post('/patients/phone-otp', async (req, res) => {
  res.json(await issueOtp(normalizePhone(req.body.phone), 'verify_patient_phone'));
});

r.post('/patients', async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  const { name, gender, ageYears, dateOfBirth, address, otpCode, vitals } = req.body;
  if (!name || !String(name).trim()) throw badRequest('Enter the patient name', 'NAME_REQUIRED');
  if (!E.GENDERS.includes(gender)) throw badRequest('Choose a gender', 'GENDER_REQUIRED');
  if (ageYears == null && !dateOfBirth) throw badRequest('Enter the age', 'AGE_REQUIRED');
  if (await M.Patient.exists({ phone })) {
    throw conflict("This number already has a MedPin record. Ask the patient for their consent code.", 'PATIENT_EXISTS');
  }
  // Consent: the patient confirms the number with the code sent to it. Without
  // this a clinic could create a record that is auto-linked at the patient's first sign-in.
  if (!otpCode) throw badRequest("Verify the patient's mobile number with the code sent to it", 'OTP_REQUIRED');
  await checkOtp(phone, 'verify_patient_phone', otpCode);
  const user = await M.User.findOne({ phone });
  const patient = await M.Patient.create({
    name: String(name).trim(), phone, gender, ageYears, ageRecordedAt: ageYears != null ? new Date() : undefined,
    dateOfBirth, userId: user?._id, phoneVerifiedAt: new Date(),
    addresses: address ? [{ line: address, isDefault: true }] : [], createdByPracticeId: req.practiceId, createdBy: req.user._id,
  });
  await M.PatientEnrolment.create({ patientId: patient._id, practiceId: req.practiceId, status: 'linked', linkedBy: req.user._id, linkedAt: new Date(), homeLocationId: await registrationBranch(req) });
  if (req.member.role === 'doctor') {
    await M.CareTeamAccess.create({ patientId: patient._id, userId: req.user._id, practiceId: req.practiceId, role: 'doctor', isPrimary: true });
  }
  if (vitals && Object.keys(vitals).length) {
    await M.Vitals.create({ ...vitals, patientId: patient._id, practiceId: req.practiceId, recordedBy: req.user._id, recordedByRole: req.member.role, source: 'clinic' });
  }
  res.status(201).json(listRow(patient));
});

// Add-Patient-Existing: link with the 6-digit code from the patient's app.
r.post('/patients/link', async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  const code = String(req.body.consentCode || '').replace(/\s/g, '');
  if (!/^\d{6}$/.test(code)) throw badRequest('Enter the 6-digit consent code', 'INVALID_CODE');
  const patient = await M.Patient.findOne({ phone });
  if (!patient) throw notFound('Patient');
  const consent = await M.ConsentCode.findOne({ patientId: patient._id, usedAt: null, expiresAt: { $gt: new Date() } }).sort({ createdAt: -1 });
  if (!consent || !safeEqual(consent.codeHash, hmac(`consent:${patient._id}:${code}`))) {
    // Guessing: after 5 wrong tries the code stops working and the patient shows a new one.
    if (consent && ++consent.wrongTries >= 5) {
      consent.expiresAt = new Date();
      await consent.save();
      throw badRequest('Too many wrong tries. Ask the patient to show a new code.', 'WRONG_CODE');
    }
    if (consent) await consent.save();
    throw badRequest("That code isn't right or has expired. Ask the patient for the new code.", 'WRONG_CODE');
  }
  consent.usedAt = new Date();
  consent.usedByPracticeId = req.practiceId;
  await consent.save();
  await M.PatientEnrolment.findOneAndUpdate(
    { patientId: patient._id, practiceId: req.practiceId },
    { status: 'linked', linkedBy: req.user._id, linkedAt: new Date(), revokedAt: null, $setOnInsert: { homeLocationId: await registrationBranch(req) } },
    { upsert: true },
  );
  if (req.member.role === 'doctor') {
    await M.CareTeamAccess.findOneAndUpdate(
      { patientId: patient._id, userId: req.user._id },
      { $setOnInsert: { practiceId: req.practiceId, role: 'doctor', accessLevel: 'full_record', since: new Date() } },
      { upsert: true },
    );
  }
  const practice = await M.Practice.findById(req.practiceId, 'name');
  if (patient.userId) await notify([patient.userId], { type: 'record_linked', title: `${practice.name} can now see your record`, body: 'You can change this any time in Profile.', screen: 'Patient-Me' });
  res.json(listRow(patient));
});

/** What this staff member may see of [patient] (services/access.js). */
const viewer = (req, patient) => accessFor({ userId: req.user._id, practiceId: req.practiceId }, patient);

r.get('/patients/:id', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const acc = await viewer(req, patient);
  const [summary, adh, careTeam, plan, enrolment] = await Promise.all([
    patientSummary(patient, req.practiceId, acc),
    adherence(patient, 30, acc),
    M.CareTeamAccess.find({ patientId: patient._id, accessLevel: { $ne: 'not_shared' } }).populate('userId', 'name'),
    M.TreatmentPlan.findOne({ patientId: patient._id, practiceId: req.practiceId }).sort({ updatedAt: -1 }),
    M.PatientEnrolment.findOne({ patientId: patient._id, practiceId: req.practiceId }),
  ]);
  res.json({
    ...summary,
    accessLevel: acc.level,
    adherence: adh,
    careTeam: careTeam.map((c) => ({ userId: c.userId?._id, name: c.userId?.name, role: c.role, accessLevel: c.accessLevel, since: c.since })),
    treatmentPlan: plan,
    shareScope: enrolment?.shareScope,
    branch: (await branchesOf(req.practiceId, [patient._id])).get(String(patient._id)),
    addresses: patient.addresses,
    emergencyContact: patient.emergencyContact,
    alertLimits: patient.alertLimits,
    targets: patient.targets,
  });
});

r.patch('/patients/:id', async (req, res) => {
  canEdit(req);
  const patient = await patientInPractice(req, req.params.id);
  const body = pick(req.body, ['name', 'gender', 'dateOfBirth', 'ageYears', 'bloodGroup', 'heightCm', 'weightKg', 'riskLevel', 'alertLimits', 'targets', 'emergencyContact']);
  if (body.ageYears != null) body.ageRecordedAt = new Date();
  Object.assign(patient, body);
  if (req.body.address) patient.addresses = [{ line: req.body.address, isDefault: true }, ...patient.addresses.filter((a) => !a.isDefault)];
  await patient.save();
  res.json(listRow(patient));
});

r.post('/patients/:id/conditions', async (req, res) => {
  canEdit(req);
  const patient = await patientInPractice(req, req.params.id);
  if (!req.body.name) throw badRequest('Enter the condition');
  if (!patient.conditions.some((c) => c.name.toLowerCase() === String(req.body.name).toLowerCase())) {
    patient.conditions.push({ ...pick(req.body, ['name', 'icdCode', 'since']), addedBy: req.user._id });
    await patient.save();
  }
  res.status(201).json(patient.conditions);
});

r.delete('/patients/:id/conditions/:cid', async (req, res) => {
  canEdit(req);
  const patient = await patientInPractice(req, req.params.id);
  patient.conditions.pull(req.params.cid);
  await patient.save();
  res.json(patient.conditions);
});

// "Penicillin, peanuts" → two allergies (trimmed, de-duplicated).
r.post('/patients/:id/allergies', async (req, res) => {
  canEdit(req);
  const patient = await patientInPractice(req, req.params.id);
  const names = String(req.body.allergens || req.body.allergen || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!names.length) throw badRequest('Enter at least one allergy');
  for (const allergen of names) {
    if (!patient.allergies.some((a) => a.allergen.toLowerCase() === allergen.toLowerCase())) patient.allergies.push({ allergen, addedBy: req.user._id });
  }
  await patient.save();
  res.status(201).json(patient.allergies);
});

r.delete('/patients/:id/allergies/:aid', async (req, res) => {
  canEdit(req);
  const patient = await patientInPractice(req, req.params.id);
  patient.allergies.pull(req.params.aid);
  await patient.save();
  res.json(patient.allergies);
});

// ── Vitals (front desk can record them too) ──
r.get('/patients/:id/vitals', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const since = T.addDays(new Date(), -(Number(req.query.days) || 90));
  const acc = await viewer(req, patient);
  res.json(await M.Vitals.find({ patientId: patient._id, ...acc.vitalsFilter(), recordedAt: { $gte: since } }).sort({ recordedAt: -1 }).limit(200));
});

const VITAL_FIELDS = ['bpSystolic', 'bpDiastolic', 'pulse', 'spo2', 'temperatureF', 'weightKg', 'heightCm', 'bloodSugar', 'sugarType', 'note', 'appointmentId', 'consultationId'];
const bmiOf = (v, patient) => {
  const h = v.heightCm || patient.heightCm;
  const w = v.weightKg;
  return h && w ? +(w / (h / 100) ** 2).toFixed(1) : undefined;
};

async function recordVitals(req, patient, body) {
  const v = pick(body, VITAL_FIELDS);
  if (!Object.keys(v).some((k) => !['note', 'appointmentId', 'consultationId'].includes(k))) throw badRequest('Enter at least one vital');
  const vitals = await M.Vitals.create({
    ...v, patientId: patient._id, practiceId: req.practiceId, recordedBy: req.user._id, recordedByRole: req.member.role, source: 'clinic', bmi: bmiOf(v, patient),
  });
  if (v.heightCm) patient.heightCm = v.heightCm;
  if (v.weightKg) patient.weightKg = v.weightKg;
  await patient.save();
  return vitals;
}

r.post('/patients/:id/vitals', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const vitals = await recordVitals(req, patient, req.body);
  await checkReading(vitals, patient).catch(() => {});
  res.status(201).json(vitals);
});

// ── Records & tests ──
r.get('/patients/:id/records', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const acc = await viewer(req, patient);
  const q = { patientId: patient._id, deletedAt: null, ...(await acc.recordFilter()) };
  if (req.query.kind) q.kind = String(req.query.kind);
  if (req.query.origin) q.origin = String(req.query.origin);
  const records = await M.MedicalRecord.find(q).sort({ recordDate: -1 }).limit(200);
  res.json(records.map((x) => ({ ...x.toJSON(), files: x.files.map(storage.withUrl) })));
});

// Front desk "Upload report for today's visit".
r.post('/patients/:id/records', upload.array('files', 10), async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  if (!req.files?.length) throw badRequest('Choose a file');
  const kind = E.RECORD_KINDS.includes(req.body.kind) ? req.body.kind : 'test_result';
  const files = [];
  for (const f of req.files) files.push(await storage.save(f.buffer, { folder: 'records', name: f.originalname, mimeType: f.mimetype }));
  const record = await M.MedicalRecord.create({
    patientId: patient._id, kind, title: req.body.title || (kind === 'prescription' ? 'Prescription' : 'Test report'),
    recordDate: req.body.recordDate ? T.parseDay(req.body.recordDate) : new Date(), origin: 'from_doctor',
    sourceName: req.body.sourceName, practiceId: req.practiceId, doctorId: req.member.role === 'doctor' ? req.user._id : undefined,
    uploadSource: req.body.uploadSource, files, uploadedBy: req.user._id, flagLabel: 'New', flagTone: 'new',
  });
  if (kind === 'prescription' && req.body.scanned === 'true') {
    // A paper prescription belongs to the doctor who wrote it, not to whoever scanned it:
    // the uploading doctor, the doctor of the visit, or the patient's doctor here.
    let doctorId = req.member.role === 'doctor' ? req.user._id : undefined;
    if (!doctorId && req.body.appointmentId) doctorId = (await M.Appointment.findOne({ _id: req.body.appointmentId, practiceId: req.practiceId }, 'doctorId'))?.doctorId;
    if (!doctorId) {
      const doctors = await M.Member.find({ practiceId: req.practiceId, role: 'doctor', status: 'active' }).distinct('userId');
      doctorId = (await M.CareTeamAccess.findOne({ patientId: patient._id, userId: { $in: doctors } }).sort({ isPrimary: -1 }))?.userId;
    }
    const doctor = doctorId ? await M.User.findById(doctorId, 'name') : null;
    await M.Prescription.create({
      practiceId: req.practiceId, patientId: patient._id, doctorId, doctorName: doctor?.name || req.body.sourceName, kind: 'scanned', source: 'this_clinic',
      uploadedBy: req.user._id, file: files[0], issuedAt: record.recordDate,
    });
  }
  let extracted = null;
  if (kind === 'test_result') extracted = await extractLabReport(req.files[0].buffer, req.files[0].mimetype).catch(() => null);
  res.status(201).json({ record: { ...record.toJSON(), files: record.files.map(storage.withUrl) }, extracted });
});

r.get('/patients/:id/lab-results', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const acc = await viewer(req, patient);
  const q = { patientId: patient._id, ...(await acc.labFilter()) };
  if (req.query.filter === 'abnormal') q.abnormalCount = { $gt: 0 };
  if (req.query.filter === 'normal') q.abnormalCount = 0;
  const results = await M.LabResult.find(q).sort({ collectedAt: -1 }).limit(200);
  const abnormal = results.reduce((n, x) => n + x.abnormalCount, 0);
  // One report per uploaded record; results entered without a file count on their own.
  const reports = new Set(results.map((x) => (x.recordId ? `r${x.recordId}` : `l${x._id}`))).size;
  res.json({ abnormalFindings: abnormal, reports, items: results });
});

// HbA1c / LDL trends: one analyte over time.
r.get('/patients/:id/trends/:analyte', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const name = new RegExp(`^${escapeRegex(req.params.analyte)}$`, 'i');
  const acc = await viewer(req, patient);
  const rows = await M.LabResult.aggregate([
    { $match: { patientId: patient._id, ...(await acc.labFilter()) } },
    { $unwind: '$values' },
    { $match: { 'values.analyte': name } },
    { $sort: { collectedAt: 1 } },
    { $project: { _id: 0, at: '$collectedAt', value: '$values.value', unit: '$values.unit', flag: '$values.flag' } },
  ]);
  res.json(rows);
});

const ANALYTE_FIELDS = ['analyte', 'value', 'valueText', 'unit', 'refLow', 'refHigh', 'refText', 'flag'];
r.post('/patients/:id/lab-results', need('labs'), async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const values = (req.body.values || []).map((v) => pick(v, ANALYTE_FIELDS));
  const result = await M.LabResult.create({
    patientId: patient._id, recordId: req.body.recordId, practiceId: req.practiceId, testName: req.body.testName,
    panel: req.body.panel, labName: req.body.labName, collectedAt: T.parseDay(req.body.collectedAt),
    values, abnormalCount: values.filter((v) => v.flag && v.flag !== 'normal').length, hasCritical: values.some((v) => v.flag === 'critical'),
    ecgInterpretation: req.body.ecgInterpretation, ecgNote: req.body.ecgNote,
  });
  // Results typed in at the clinic (no uploaded file) still show in the patient's Records.
  if (!result.recordId) {
    const n = result.abnormalCount;
    const low = result.values.some((v) => v.flag === 'low') && !result.values.some((v) => ['high', 'critical'].includes(v.flag));
    const rec = await M.MedicalRecord.create({
      patientId: patient._id, kind: 'test_result', title: result.testName || 'Test result', recordDate: result.collectedAt || new Date(),
      origin: 'from_doctor', sourceName: result.labName || undefined, practiceId: req.practiceId,
      doctorId: req.member.role === 'doctor' ? req.user._id : undefined, uploadedBy: req.user._id,
      flagLabel: n ? `${n} ${low ? 'low' : 'high'}` : 'Normal', flagTone: n ? 'high' : 'ok',
    });
    result.recordId = rec._id;
    await result.save();
  }
  if (result.hasCritical) {
    const { raiseAlert } = require('../services/care');
    await raiseAlert({ practiceId: req.practiceId, patientId: patient._id, severity: 'urgent', kind: 'lab', detail: `Critical result in ${result.testName}`, sourceModel: 'LabResult', sourceId: result._id });
  }
  res.status(201).json(result);
});

// Lab-Report: one result with its file and each value's previous reading.
r.get('/lab-results/:id', async (req, res) => {
  const result = await M.LabResult.findById(req.params.id).populate('reviewed.by', 'name');
  if (!result) throw notFound('Result');
  const patient = await patientInPractice(req, result.patientId);
  const acc = await viewer(req, patient);
  const labQ = await acc.labFilter();
  if (!(await M.LabResult.exists({ _id: result._id, ...labQ }))) throw notFound('Result');
  const record = result.recordId ? await M.MedicalRecord.findOne({ _id: result.recordId, ...(await acc.recordFilter()) }) : null;
  const earlier = await M.LabResult.find({ patientId: patient._id, ...labQ, _id: { $ne: result._id }, collectedAt: { $lt: result.collectedAt } }).sort({ collectedAt: -1 }).limit(20);
  const previous = (analyte) => {
    for (const e of earlier) {
      const v = e.values.find((x) => x.analyte.toLowerCase() === analyte.toLowerCase());
      if (v) return { value: v.value ?? v.valueText, unit: v.unit, flag: v.flag, collectedAt: e.collectedAt };
    }
    return null;
  };
  res.json({
    ...result.toJSON(),
    patient: { id: patient._id, name: patient.name, age: T.ageFrom(patient), gender: patient.gender },
    values: result.values.map((v) => ({ ...v.toJSON(), previous: previous(v.analyte) })),
    record: record && { id: record._id, title: record.title, origin: record.origin, sourceName: record.sourceName, aiSummary: record.aiSummary, pageFrom: record.pageFrom, pageTo: record.pageTo, files: record.files.map(storage.withUrl) },
  });
});

r.post('/lab-results/:id/reviewed', need('labReview'), async (req, res) => {
  const result = await M.LabResult.findById(req.params.id);
  if (!result) throw notFound('Result');
  await patientInPractice(req, result.patientId);
  result.reviewed = { by: req.user._id, at: new Date() };
  await result.save();
  res.json(result);
});

r.get('/patients/:id/prescriptions', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const acc = await viewer(req, patient);
  const all = await M.Prescription.find({ patientId: patient._id, ...acc.rxFilter() }).sort({ issuedAt: -1 });
  const filter = req.query.filter || 'all';
  const items = all.filter((x) => filter === 'all' || (filter === 'this_clinic' ? String(x.practiceId) === String(req.practiceId) : String(x.practiceId) !== String(req.practiceId) || x.source !== 'this_clinic'));
  res.json({
    counts: { all: all.length, thisClinic: all.filter((x) => String(x.practiceId) === String(req.practiceId)).length, shared: all.filter((x) => String(x.practiceId) !== String(req.practiceId)).length },
    items: items.map((x, i) => ({ ...x.toJSON(), file: storage.withUrl(x.file), latest: i === 0 })),
  });
});

r.get('/patients/:id/adherence', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const days = Math.min(Number(req.query.days) || 30, 180);
  const acc = await viewer(req, patient);
  const visible = (await M.MedicationCourse.find({ patientId: patient._id }, 'doctorId')).filter((c) => acc.courseVisible(c)).map((c) => c._id);
  const now = adherence(patient, days, acc);
  const prev = await M.DoseLog.find({ patientId: patient._id, courseId: { $in: visible }, scheduledAt: { $gte: T.addDays(new Date(), -2 * days), $lt: T.addDays(new Date(), -days) } });
  const prevPct = prev.length ? Math.round((prev.filter((d) => d.status === 'taken').length / prev.length) * 100) : null;
  const week = await M.DoseLog.find({ patientId: patient._id, courseId: { $in: visible }, scheduledAt: { $gte: T.addDays(T.dayStart(), -6) } }).sort({ scheduledAt: 1 });
  const { effectiveStatus } = require('../services/care');
  res.json({ ...(await now), previousPct: prevPct, week: week.map((d) => ({ at: d.scheduledAt, slot: d.slot, courseId: d.courseId, status: effectiveStatus(d) })) });
});

r.get('/patients/:id/health-logs', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const logs = await M.HealthLog.find({ patientId: patient._id, sharedWith: req.user._id }).sort({ loggedAt: -1 }).limit(100);
  res.json(logs.map((l) => ({ ...l.toJSON(), photo: storage.withUrl(l.photo) })));
});

// Dietician review of a food log entry.
r.post('/health-logs/:id/review', async (req, res) => {
  const log = await M.HealthLog.findById(req.params.id);
  if (!log || !log.sharedWith.some((u) => String(u) === String(req.user._id))) throw notFound('Log');
  log.review = { ...(log.review?.toObject?.() || {}), by: req.user._id, at: new Date(), comment: req.body.comment };
  await log.save();
  res.json(log);
});

r.get('/patients/:id/visits', async (req, res) => {
  const patient = await patientInPractice(req, req.params.id);
  const consults = await M.Consultation.find({ patientId: patient._id, practiceId: req.practiceId, status: { $ne: 'draft' } }).sort({ startedAt: -1 }).limit(50).populate('vitalsId').populate('locationId', 'name shortName');
  // Each visit says which branch it was at.
  res.json(consults.map((c) => ({ ...c.toJSON(), location: c.locationId ? { id: c.locationId._id, name: c.locationId.shortName || c.locationId.name } : null, locationId: c.locationId?._id || null })));
});

r.put('/patients/:id/treatment-plan', async (req, res) => {
  canEdit(req);
  const patient = await patientInPractice(req, req.params.id);
  const body = pick(req.body, ['sections', 'nextVisitAt', 'nutritionBy', 'healthSummary', 'focusItems', 'consultationId']);
  const plan = await M.TreatmentPlan.findOneAndUpdate(
    { patientId: patient._id, doctorId: req.user._id },
    { ...body, practiceId: req.practiceId },
    { upsert: true, new: true, runValidators: true },
  );
  res.json(plan);
});

module.exports = r;

// Patient app: Patient-Home, Hero-Carousel, Patient-Me, Patient-FindDoctor, Patient-Doctors,
// Patient-DoctorDetail, Patient-DoctorChat, Patient-Chat, Patient-Emergency, Patient-AskAI,
// Patient-Medicines, Patient-Adherence, Patient-Log, Patient-Track, Patient-Records,
// Records-Add, Records-Review, Med-AddToCart, Med-Cart, Med-Pharmacy.
const { Router } = require('express');
const M = require('../models');
const E = require('../models/enums');
const T = require('../lib/time');
const { requireAuth, patientOnly } = require('../middleware/auth');
const { pick, badRequest, notFound, conflict, escapeRegex, list, isId } = require('../lib/http');
const { hmac, randomDigits } = require('../lib/security');
const storage = require('../services/storage');
const S = require('../services/scheduling');
const care = require('../services/care');
const assistant = require('../services/assistant');
const { notify, practiceStaff } = require('../services/notify');
const { patientSummary, doseText, dosesPerDay } = require('../services/clinical');

const { uploader } = require('../lib/uploads');
const upload = uploader({ kinds: ['image', 'pdf'], maxMb: 10, maxFiles: 10 });
const photoUpload = uploader({ kinds: ['image'], maxMb: 10, maxFiles: 1 });
const r = Router();
r.use(requireAuth);

// Sign-up for someone with no record yet (a clinic may have created one already).
r.post('/register', async (req, res) => {
  if (await M.Patient.exists({ userId: req.user._id })) throw conflict('You already have a profile', 'ALREADY_REGISTERED');
  const { name, gender, ageYears, dateOfBirth } = req.body;
  if (!name || !E.GENDERS.includes(gender)) throw badRequest('Enter your name and gender');
  if (req.body.termsAccepted) await M.User.updateOne({ _id: req.user._id }, { termsAcceptedAt: new Date() });
  const existing = await M.Patient.findOne({ phone: req.user.phone });
  if (existing) {
    existing.userId = req.user._id;
    await existing.save();
    return res.json(existing);
  }
  const p = await M.Patient.create({ userId: req.user._id, name, gender, ageYears, ageRecordedAt: ageYears != null ? new Date() : undefined, dateOfBirth, phone: req.user.phone, phoneVerifiedAt: req.user.phoneVerifiedAt });
  if (!req.user.name) await M.User.updateOne({ _id: req.user._id }, { name });
  return res.status(201).json(p);
});

r.use(patientOnly);

// ── Profile (Patient-Me) ──
const meView = (p, user) => ({
  ...p.toJSON(),
  age: T.ageFrom(p),
  bmi: p.heightCm && p.weightKg ? +(p.weightKg / (p.heightCm / 100) ** 2).toFixed(1) : null,
  language: user.language,
  appLock: user.appLock,
});

r.get('/me', async (req, res) => {
  const p = req.patient;
  // Height / weight not on the profile yet: the newest reading fills them in.
  if (p.weightKg == null || p.heightCm == null) {
    const [w, h] = await Promise.all([
      p.weightKg == null ? M.Vitals.findOne({ patientId: p._id, weightKg: { $ne: null } }).sort({ recordedAt: -1 }) : null,
      p.heightCm == null ? M.Vitals.findOne({ patientId: p._id, heightCm: { $ne: null } }).sort({ recordedAt: -1 }) : null,
    ]);
    if (w || h) {
      if (w) p.weightKg = w.weightKg;
      if (h) p.heightCm = h.heightCm;
      p.bodyMeasuredAt = p.bodyMeasuredAt || (w || h).recordedAt;
      await p.save();
    }
  }
  res.json(meView(p, req.user));
});

r.patch('/me', async (req, res) => {
  const p = req.patient;
  const body = pick(req.body, ['name', 'gender', 'ageYears', 'dateOfBirth', 'bloodGroup', 'heightCm', 'weightKg', 'emergencyContact', 'trackedMeasures', 'area']);
  if (body.name !== undefined && !String(body.name).trim()) delete body.name; // empty edit keeps the old name
  if (body.heightCm != null) body.heightCm = Math.min(250, Math.max(50, Number(body.heightCm)));
  if (body.weightKg != null) body.weightKg = Math.min(400, Math.max(2, Number(body.weightKg)));
  if (body.ageYears != null) p.ageRecordedAt = new Date();
  // A new weight / height from the profile is also a reading (Home → What you track shows it).
  const bodyChanged = (body.weightKg != null && body.weightKg !== p.weightKg) || (body.heightCm != null && body.heightCm !== p.heightCm);
  if (body.emergencyContact && !body.emergencyContact.name) body.emergencyContact = { name: undefined, phone: undefined };
  Object.assign(p, body);
  // Daily goals the patient sets (Daily log → Goals).
  if (req.body.goals) {
    const g = req.body.goals;
    const steps = Number(g.stepsPerDay);
    const ex = Number(g.exerciseMinPerDay);
    if (g.stepsPerDay !== undefined && !(steps >= 1000 && steps <= 30000)) throw badRequest('Choose a step goal between 1,000 and 30,000');
    if (g.exerciseMinPerDay !== undefined && !(ex >= 5 && ex <= 240)) throw badRequest('Choose 5 to 240 minutes of exercise a day');
    p.targets = { ...(p.targets?.toObject?.() || p.targets || {}), ...(g.stepsPerDay !== undefined ? { stepsPerDay: Math.round(steps) } : {}), ...(g.exerciseMinPerDay !== undefined ? { exerciseMinPerDay: Math.round(ex) } : {}) };
  }
  if (req.body.settings) {
    const s = req.body.settings;
    const hhmm = (v) => typeof v === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(v);
    const next = p.settings.toObject();
    for (const k of ['medReminders', 'dailyLogReminder', 'visitReminders']) if (typeof s[k] === 'boolean') next[k] = s[k];
    if (s.dailyLogReminderAt !== undefined) {
      if (!hhmm(s.dailyLogReminderAt)) throw badRequest('Choose a time like 20:00');
      next.dailyLogReminderAt = s.dailyLogReminderAt;
    }
    if (s.bedAt !== undefined) {
      if (!hhmm(s.bedAt)) throw badRequest('Choose a time like 22:30');
      next.bedAt = s.bedAt;
    }
    for (const [slot, v] of Object.entries(s.reminderTimes || {})) {
      if (!['morning', 'afternoon', 'night'].includes(slot)) continue;
      if (!hhmm(v)) throw badRequest('Choose a time like 07:30');
      next.reminderTimes = { ...next.reminderTimes, [slot]: v };
    }
    p.settings = next;
  }
  if (req.body.conditions) p.conditions = req.body.conditions.map((c) => (typeof c === 'string' ? { name: c } : c));
  if (req.body.allergies) p.allergies = req.body.allergies.map((a) => (typeof a === 'string' ? { allergen: a } : a));
  const here = require('../lib/geo').pointFrom(req.body.lat, req.body.lng);
  if (here) p.geo = here;
  if (bodyChanged) p.bodyMeasuredAt = new Date();
  await p.save();
  if (bodyChanged) {
    await M.Vitals.create({
      patientId: p._id, recordedBy: req.user._id, recordedByRole: 'patient', source: 'home', recordedAt: p.bodyMeasuredAt,
      ...(body.weightKg != null ? { weightKg: body.weightKg } : {}), ...(body.heightCm != null ? { heightCm: body.heightCm } : {}),
    });
  }
  const userBody = pick(req.body, ['language', 'appLock']);
  if (Object.keys(userBody).length || body.name) {
    Object.assign(req.user, userBody, body.name ? { name: body.name } : {});
    await req.user.save();
  }
  res.json(meView(p, req.user));
});

// The patient's own prescription PDF (View / Download in Records), in English or
// their language: ?lang=bn | hi (labels and the doctor's words translated; medicine names stay English).
r.get('/prescriptions/:id/pdf', async (req, res) => {
  const rx = isId(req.params.id) ? await M.Prescription.findOne({ _id: req.params.id, patientId: req.patient._id }) : null;
  if (!rx) throw notFound('Prescription');
  const lang = ['bn', 'hi'].includes(req.query.lang) ? req.query.lang : 'en';
  const file = await require('../services/clinical').localizedPrescriptionPdf(rx, lang);
  if (!file?.key) throw notFound('Prescription PDF');
  res.json({ ...storage.withUrl(file), lang });
});

r.post('/addresses', async (req, res) => {
  if (!req.body.line) throw badRequest('Enter the address');
  if (req.body.isDefault) req.patient.addresses.forEach((a) => { a.isDefault = false; });
  req.patient.addresses.push(pick(req.body, ['label', 'line', 'area', 'city', 'pincode', 'isDefault']));
  await req.patient.save();
  res.status(201).json(req.patient.addresses);
});

// 6-digit consent code, made only when the patient taps "Show my code"; valid
// 5 minutes and once. A new one cancels the old. A clinic enters it to link the record.
const CONSENT_MINUTES = 5;
r.post('/consent-code', async (req, res) => {
  await M.ConsentCode.updateMany({ patientId: req.patient._id, usedAt: null, expiresAt: { $gt: new Date() } }, { expiresAt: new Date() });
  const code = randomDigits(6);
  const expiresAt = new Date(Date.now() + CONSENT_MINUTES * 60 * 1000);
  const c = await M.ConsentCode.create({ patientId: req.patient._id, codeHash: hmac(`consent:${req.patient._id}:${code}`), expiresAt });
  res.json({ id: c._id, code, display: `${code.slice(0, 3)} ${code.slice(3)}`, expiresAt, minutes: CONSENT_MINUTES });
});

// What happened to a code the app is showing: still open, used by a clinic, or expired.
r.get('/consent-code/:id', async (req, res) => {
  if (!isId(req.params.id)) throw notFound('Code');
  const c = await M.ConsentCode.findOne({ _id: req.params.id, patientId: req.patient._id }).populate('usedByPracticeId', 'name');
  if (!c) return res.json({ status: 'expired' });
  const status = c.usedAt ? 'used' : c.expiresAt > new Date() ? 'active' : 'expired';
  res.json({ status, expiresAt: c.expiresAt, usedAt: c.usedAt, practice: c.usedByPracticeId?.name || null });
});

// ── Who can see my record ──
r.get('/care-team', async (req, res) => {
  const rows = await M.CareTeamAccess.find({ patientId: req.patient._id }).populate('userId', 'name').populate('practiceId', 'name');
  // Patient-Me shows "Diabetes · City Care Clinic" under each name.
  const profiles = await M.DoctorProfile.find({ userId: { $in: rows.map((c) => c.userId?._id).filter(Boolean) } }, 'userId displayName headline specialtyKeys');
  const specs = new Map((await M.Specialty.find({ key: { $in: profiles.flatMap((p) => p.specialtyKeys) } }, 'key label')).map((s) => [s.key, s.label]));
  res.json(rows.map((c) => {
    const prof = profiles.find((p) => String(p.userId) === String(c.userId?._id));
    return {
      userId: c.userId?._id, name: prof?.displayName || c.userId?.name, role: c.role, practiceId: c.practiceId?._id, practice: c.practiceId?.name,
      accessLevel: c.accessLevel, since: c.since, headline: prof?.headline, specialty: specs.get(prof?.specialtyKeys?.[0]) || null,
    };
  }));
});

r.patch('/care-team/:userId', async (req, res) => {
  if (!E.ACCESS_LEVELS.includes(req.body.accessLevel)) throw badRequest('Choose what they can see');
  const c = await M.CareTeamAccess.findOne({ patientId: req.patient._id, userId: req.params.userId });
  if (!c) throw notFound('Care team member');
  c.accessLevel = req.body.accessLevel;
  c.changedAt = new Date();
  c.viewerNotifiedAt = new Date();
  await c.save();
  await notify([c.userId], { type: 'access_changed', title: `${req.patient.name} changed what you can see`, body: req.body.accessLevel.replace(/_/g, ' '), screen: 'Patient-Profile', params: { patientId: req.patient._id } });
  res.json(c);
});

// Stop sharing with a whole clinic.
r.post('/clinics/:practiceId/revoke', async (req, res) => {
  const e = await M.PatientEnrolment.findOneAndUpdate({ patientId: req.patient._id, practiceId: req.params.practiceId }, { status: 'revoked', revokedAt: new Date() }, { new: true });
  if (!e) throw notFound('Clinic');
  await M.CareTeamAccess.updateMany({ patientId: req.patient._id, practiceId: req.params.practiceId }, { accessLevel: 'not_shared', changedAt: new Date() });
  res.json(e);
});

// ── Home ──
r.get('/home', async (req, res) => {
  const p = req.patient;
  const now = new Date();
  const today = T.dayStart();
  await care.ensureDoses(p, today);
  await require('../services/health').currentScore(p).catch((err) => console.warn('[score]', err.message));
  const [doses, nextVisit, newReport, courses, steps, logs, summary, plan] = await Promise.all([
    M.DoseLog.find({ patientId: p._id, scheduledAt: { $gte: today, $lt: T.addDays(today, 1) } }).sort({ scheduledAt: 1 }).populate('courseId', 'name strength foodRelation'),
    M.Appointment.findOne({ patientId: p._id, startAt: { $gte: today }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } }).sort({ startAt: 1 }).populate('doctorId', 'name').populate('locationId', 'name shortName'),
    M.LabResult.findOne({ patientId: p._id, createdAt: { $gte: T.addDays(today, -3) } }).sort({ createdAt: -1 }),
    M.MedicationCourse.find({ patientId: p._id, status: 'active' }),
    stepsToday(p._id, today),
    M.HealthLog.find({ patientId: p._id, loggedAt: { $gte: today } }),
    M.AiSummary.findOne({ patientId: p._id, audience: 'patient' }).sort({ generatedAt: -1 }),
    M.TreatmentPlan.findOne({ patientId: p._id }).sort({ updatedAt: -1 }),
  ]);
  const refills = courses
    .filter((c) => c.stockUnits != null && dosesPerDay(c.dose) > 0)
    .map((c) => ({ courseId: c._id, name: `${c.name} ${c.strength || ''}`.trim(), tabletsLeft: c.stockUnits, daysLeft: Math.floor(c.stockUnits / dosesPerDay(c.dose)) }))
    .filter((x) => x.daysLeft <= 5)
    .sort((a, b) => a.daysLeft - b.daysLeft);
  const tasks = doses.map((d) => ({
    kind: 'dose', id: d._id, title: `${d.courseId?.name} ${d.courseId?.strength || ''}`.trim(), slot: d.slot, at: d.scheduledAt, foodRelation: d.courseId?.foodRelation,
    status: care.effectiveStatus(d, now), done: d.status === 'taken', doneLabel: 'Taken',
  }));
  const mealsLogged = logs.filter((l) => l.type === 'meal').map((l) => l.mealType);
  const dailyLog = await dailyLogUsed(p);
  if (dailyLog) tasks.push({ kind: 'log', id: 'meal-log', title: 'Log your meals', done: mealsLogged.length >= 2, doneLabel: 'Logged', detail: mealsLogged });
  if (nextVisit && T.dayKey(nextVisit.startAt) === T.dayKey(now)) {
    for (const t of nextVisit.todos.filter((x) => !x.done)) tasks.push({ kind: 'visit_todo', id: t._id, appointmentId: nextVisit._id, title: t.text, done: false });
  }
  const slides = [];
  if (nextVisit) slides.push({ kind: 'visit', title: `Visit ${T.dayKey(nextVisit.startAt) === T.dayKey(now) ? 'today' : T.dayKey(nextVisit.startAt)}, ${T.fmtTime(T.minuteOfDay(nextVisit.startAt))}`, sub: `${nextVisit.doctorId?.name} · Token ${String(nextVisit.tokenNo).padStart(2, '0')}`, screen: 'Patient-DoctorDetail', params: { appointmentId: nextVisit._id } });
  if (newReport) slides.push({ kind: 'report', title: `Your ${newReport.testName} is in`, sub: newReport.abnormalCount ? `${newReport.abnormalCount} value(s) outside the range` : 'All values in range', screen: 'Patient-Records',
    recordId: newReport.recordId, testName: newReport.testName, abnormalCount: newReport.abnormalCount || 0,
    abnormal: newReport.values.filter((v) => v.flag !== 'normal').map((v) => v.analyte),
    abnormalDirection: newReport.values.some((v) => v.flag === 'high' || v.flag === 'critical') ? 'high' : 'low' });
  if (refills[0]) slides.push({ kind: 'refill', title: `${refills[0].name} runs out in ${refills[0].daysLeft} days`, sub: `${refills[0].tabletsLeft} tablets left`, screen: 'Med-Cart' });
  if (p.healthScore?.value != null) slides.push({ kind: 'score', title: `Health score ${p.healthScore.value}`, sub: p.healthScore.weeklyDelta ? `${p.healthScore.weeklyDelta > 0 ? '+' : ''}${p.healthScore.weeklyDelta} this week` : '', screen: 'Patient-Home' });
  const unread = await M.Conversation.aggregate([{ $match: { patientId: p._id } }, { $unwind: '$participants' }, { $match: { 'participants.userId': req.user._id } }, { $group: { _id: null, n: { $sum: '$participants.unreadCount' } } }]);

  // Cards further down the home screen.
  const [rx, lab, advised] = await Promise.all([
    M.Prescription.findOne({ patientId: p._id }).sort({ issuedAt: -1 }),
    M.LabResult.findOne({ patientId: p._id }).sort({ collectedAt: -1 }),
    require('../services/advisedtests').advisedTests(p).catch((err) => { console.warn('[advised tests]', err.message); return []; }),
  ]);
  // "Lab tests" card: tests the doctor asked for with no result yet, soonest
  // "bring by" first (then the newest ask); Home shows a few, Records has them all.
  const dueTests = advised
    // A report uploaded for it that was the wrong test or couldn't be read is still to do.
    .filter((t) => ['todo', 'wrong', 'unreadable'].includes(t.status))
    .sort((a, b) => (a.bringBy ? +a.bringBy : Infinity) - (b.bringBy ? +b.bringBy : Infinity) || b.askedAt - a.askedAt);
  // "Latest prescription": the newest one, issued in MedPin or uploaded by the patient.
  const upRx = await M.MedicalRecord.findOne({ patientId: p._id, kind: 'prescription', deletedAt: null, prescriptionId: null }).sort({ recordDate: -1 });
  const useUpload = upRx && (!rx || upRx.recordDate > rx.issuedAt);
  const [plans, team, adh, readings] = await Promise.all([
    M.ActivityPlan.find({ patientId: p._id, active: true }).limit(1),
    logShareTeam(p),
    care.adherence(p, 30),
    M.Vitals.find({ patientId: p._id, recordedAt: { $gte: T.addDays(today, -30) } }).sort({ recordedAt: 1 }),
  ]);
  const weekStart = T.addDays(today, -((new Date(now.getTime() + T.IST_MS).getUTCDay() + 6) % 7));
  const activity = plans[0];
  const series = (pickFn) => readings.map((v) => ({ at: v.recordedAt, ...pickFn(v) })).filter((x) => x.value != null).slice(-7);
  const tracked = {
    blood_sugar: series((v) => ({ value: v.sugarType === 'fasting' ? v.bloodSugar : null })),
    blood_pressure: series((v) => ({ value: v.bpSystolic, value2: v.bpDiastolic })),
    weight: series((v) => ({ value: v.weightKg })),
    heart_rate: series((v) => ({ value: v.pulse })),
    spo2: series((v) => ({ value: v.spo2 })),
    // HbA1c comes from lab reports (the last 7 results).
    hba1c: (await M.LabResult.find({ patientId: p._id, 'values.analyte': /hba1c|glycated|a1c/i }, 'collectedAt values').sort({ collectedAt: 1 }))
      .map((r) => {
        const x = r.values.find((v) => /hba1c|glycated|a1c/i.test(v.analyte || ''));
        return { at: r.collectedAt, value: x?.value ?? (Number.isFinite(parseFloat(x?.valueText)) ? parseFloat(x.valueText) : null) };
      })
      .filter((x) => x.value != null)
      .slice(-7),
  };
  res.json({
    latestPrescription: useUpload
      ? {
        id: upRx._id, recordId: upRx._id, uploaded: true, issuedAt: upRx.recordDate, doctorName: upRx.extractedDoctor || upRx.sourceName,
        medicines: upRx.extractedMedicines?.length || 0, url: storage.signedUrl(upRx.files?.[0]?.key),
      }
      : rx && {
        id: rx._id, issuedAt: rx.issuedAt, doctorName: rx.doctorName, medicines: rx.items.length, validUntil: rx.validUntil, url: storage.signedUrl(rx.file?.key),
      },
    latestLab: lab && {
      id: lab._id, recordId: lab.recordId, testName: lab.testName, collectedAt: lab.collectedAt, abnormalCount: lab.abnormalCount,
      abnormal: lab.values.filter((v) => v.flag !== 'normal').map((v) => v.analyte),
      abnormalDirection: lab.values.some((v) => v.flag === 'high' || v.flag === 'critical') ? 'high' : 'low',
    },
    pendingTests: {
      total: dueTests.length,
      items: dueTests.slice(0, 3).map((t) => ({
        name: t.name, checks: t.checks, prep: t.prep, fasting: /^fast/i.test(t.prep || ''),
        askedAt: t.askedAt, bringBy: t.bringBy, doctorName: t.doctorName, doctorId: t.doctorId, prescriptionId: t.prescriptionId,
        status: t.status, lastUpload: t.lastUpload,
      })),
    },
    activityPlan: activity && {
      id: activity._id, name: activity.name, durationMin: activity.durationMin, plannedTime: activity.plannedTime, daysPerWeek: activity.daysPerWeek,
      doneThisWeek: activity.completions.filter((d) => d >= weekStart).length, doneToday: activity.completions.some((d) => T.dayKey(d) === T.dayKey(now)),
    },
    mealsLogged,
    dailyLog, // false: no one on the care team uses a meal log, so Home doesn't ask for one
    logSharedWith: team.map((c) => ({ userId: c.userId?._id, name: c.userId?.name, role: c.role })),
    adherence: { pct: adh.overallPct, doctors: adh.perDoctor.length },
    trackedMeasures: p.trackedMeasures,
    tracked,
    targets: p.targets,
    greetingName: p.name.split(' ')[0],
    date: today,
    slides,
    tasks,
    tasksDone: tasks.filter((t) => t.done).length,
    steps: { today: steps.today, goal: p.targets?.stepsPerDay || 8000, source: steps.source, app: stepApp(p, steps.source) },
    // Today's exercise (it starts again at 0 each day) against the patient's goal.
    exercise: (() => {
      const ex = logs.filter((l) => l.type === 'exercise');
      return { minutes: ex.reduce((s, l) => s + (l.durationMin || 0), 0), sessions: ex.length, goal: p.targets?.exerciseMinPerDay || 30 };
    })(),
    refills,
    nextVisit,
    aiSummary: summary || (plan?.healthSummary ? { body: plan.healthSummary, focusItems: plan.focusItems, generatedAt: plan.updatedAt } : null),
    healthScore: p.healthScore,
    deviceSync: p.deviceSync?.at ? p.deviceSync : null,
    unreadMessages: unread[0]?.n || 0,
    unreadNotifications: await M.Notification.countDocuments({ userId: req.user._id, readAt: null }),
  });
});

/**
 * Today's steps: the phone / watch count and the patient's own entry measure
 * the same walking, so the higher one counts (never the two added up).
 */
async function stepsToday(patientId, since) {
  const logs = await M.HealthLog.find({ patientId, type: 'steps', loggedAt: { $gte: since } }, 'steps fromDevice stepSource');
  const sum = (xs) => xs.reduce((a, x) => a + (x.steps || 0), 0);
  const device = logs.filter((l) => l.fromDevice);
  const manual = Math.max(0, ...logs.filter((l) => !l.fromDevice).map((l) => l.steps || 0));
  const auto = sum(device);
  if (!logs.length) return { today: 0, source: null };
  if (manual > auto) return { today: manual, source: 'manual' };
  return { today: auto, source: device.some((l) => l.stepSource === 'phone') && !device.some((l) => l.stepSource === 'watch') ? 'phone' : 'watch' };
}

/**
 * Is "Log your meals" a task for this patient? Only once their dietician (or
 * doctor) has asked for it — "Ask to log meals" on the treatment plan, which
 * names who reviews the logs. Until then nobody reads them, so it isn't asked
 * (the patient can still keep a log from the Log screen if they want to).
 */
async function dailyLogUsed(p) {
  return Boolean(await M.TreatmentPlan.exists({ patientId: p._id, nutritionBy: { $ne: null } }));
}

/** The care team the daily log goes to (the patient's choice, else access levels). */
async function logShareTeam(p) {
  const [team, plan] = await Promise.all([
    M.CareTeamAccess.find({ patientId: p._id, accessLevel: { $ne: 'not_shared' } }).populate('userId', 'name'),
    M.TreatmentPlan.findOne({ patientId: p._id, nutritionBy: { $ne: null } }, 'nutritionBy'),
  ]);
  const chosen = Array.isArray(p.logShareWith) ? new Set(p.logShareWith.map(String)) : null;
  // Whoever asked for the meal log reviews it (unless the patient chose otherwise).
  const reviewer = plan?.nutritionBy ? String(plan.nutritionBy) : null;
  return team.filter((c) => c.userId && (chosen ? chosen.has(String(c.userId._id)) : ['full_with_logs', 'daily_log_only'].includes(c.accessLevel) || String(c.userId._id) === reviewer));
}

// ── Find a doctor ──
const haversineKm = (a, b) => {
  if (!a || !b) return null;
  const [lng1, lat1] = a;
  const [lng2, lat2] = b;
  const rad = (x) => (x * Math.PI) / 180;
  const h = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return +(12742 * Math.asin(Math.sqrt(h))).toFixed(2);
};

/** Where distances are measured from: the phone's location (?lat&lng), else the saved one. */
const originOf = (req) => require('../lib/geo').pointFrom(req.query.lat, req.query.lng)?.coordinates || req.patient.geo?.coordinates || null;

async function doctorCards(req, profiles, origin) {
  const myDoctors = new Set((await M.CareTeamAccess.find({ patientId: req.patient._id, accessLevel: { $ne: 'not_shared' } }).distinct('userId')).map(String));
  const dls = await M.DoctorLocation.find({ doctorId: { $in: profiles.map((p) => p.userId) }, status: 'active' }).populate('locationId').populate('practiceId', 'name');
  const out = [];
  for (const prof of profiles) {
    const places = dls.filter((d) => String(d.doctorId) === String(prof.userId) && d.locationId?.status === 'active');
    if (!places.length) continue;
    let best = null;
    for (const d of places) {
      const km = haversineKm(origin, d.locationId.geo?.coordinates);
      const next = await S.nextFreeSlot({ doctorId: prof.userId, locationId: d.locationId._id });
      const fee = (d.services.find((s) => s.visitType === 'new') || d.services[0])?.fee ?? null;
      const cand = { place: d, km, next, fee };
      if (!best || (km ?? 1e9) < (best.km ?? 1e9)) best = cand;
    }
    out.push({
      doctorId: prof.userId, name: prof.displayName, initials: prof.displayName.replace(/^Dr\.?\s*/i, '').split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase(),
      photo: storage.withUrl(prof.photo), headline: prof.headline, specialtyKeys: prof.specialtyKeys, degrees: prof.degreesSummary,
      years: prof.practisingSince ? new Date().getFullYear() - prof.practisingSince : null, languages: prof.languagesSpoken,
      // "Video visit" only when the doctor offers video and has a video consultation service.
      gender: prof.gender, video: Boolean(prof.offersVideo && places.some((d) => d.services.some((s) => s.mode === 'video'))),
      verified: prof.verifiedNow(), ...(await require('../services/presence').presenceOf(prof)),
      clinic: best.place.practiceId?.name, location: { id: best.place.locationId._id, name: best.place.locationId.name, area: best.place.locationId.area },
      km: best.km, fee: best.fee, nextSlot: best.next && { startAt: best.next.startAt, time: best.next.time },
      availableToday: Boolean(best.next && T.dayKey(best.next.startAt) === T.dayKey(new Date())), mine: myDoctors.has(String(prof.userId)),
    });
  }
  return out;
}

r.get('/doctors/search', async (req, res) => {
  const q = { acceptingBookings: true };
  if (req.query.specialty) q.specialtyKeys = { $in: list(req.query.specialty) };
  if (req.query.female === 'true') q.gender = 'female';
  if (req.query.video === 'true') q.offersVideo = true;
  if (req.query.language) q.languagesSpoken = req.query.language;
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    q.$or = [{ displayName: re }, { specialisations: re }, { conditionsTreated: re }, { headline: re }];
  }
  const profiles = await M.DoctorProfile.find(q).limit(100);
  const live = require('../lib/geo').pointFrom(req.query.lat, req.query.lng)?.coordinates;
  const origin = originOf(req);
  let cards = await doctorCards(req, profiles, origin);
  if (req.query.video === 'true') cards = cards.filter((c) => c.video);
  if (req.query.today === 'true') cards = cards.filter((c) => c.availableToday);
  if (req.query.withinKm) cards = cards.filter((c) => c.km != null && c.km <= Number(req.query.withinKm));
  if (req.query.area) cards = cards.filter((c) => new RegExp(escapeRegex(req.query.area), 'i').test(c.location.area || ''));
  if (req.query.sort === 'soonest') cards.sort((a, b) => new Date(a.nextSlot?.startAt || 8.64e15) - new Date(b.nextSlot?.startAt || 8.64e15));
  else cards.sort((a, b) => (a.km ?? 1e9) - (b.km ?? 1e9) || Number(b.mine) - Number(a.mine));
  // "near Salt Lake": the area the phone is in now, else the saved address.
  let area = req.patient.area || req.patient.addresses.find((a) => a.isDefault)?.area || null;
  if (live) {
    // The name people use: a clinic's area within 3 km ("Salt Lake"), else the map's name for the spot.
    const near = cards.filter((c) => c.km != null && c.km <= 3 && c.location.area).sort((a, b) => a.km - b.km)[0];
    if (near) area = near.location.area;
    else {
      const here = await require('../services/places').reverse(+live[1].toFixed(3), +live[0].toFixed(3)).catch(() => null);
      area = here?.area || here?.city || area;
    }
  }
  res.json({
    total: cards.length, emergency: req.query.q ? assistant.isEmergencyText(req.query.q) : false,
    area, from: live ? 'here' : origin ? 'saved' : null, items: cards,
  });
});

r.get('/doctors/:doctorId', async (req, res) => {
  const prof = await M.DoctorProfile.findOne({ userId: req.params.doctorId });
  if (!prof) throw notFound('Doctor');
  const origin = originOf(req);
  const [card] = await doctorCards(req, [prof], origin);
  const places = await M.DoctorLocation.find({ doctorId: prof.userId, status: 'active' }).populate('locationId', 'name address area googleMapsUrl geo');
  const access = await M.CareTeamAccess.findOne({ patientId: req.patient._id, userId: prof.userId });
  const [nextVisit, lastVisit, records, history, courses] = await Promise.all([
    M.Appointment.findOne({ patientId: req.patient._id, doctorId: prof.userId, startAt: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } }).sort({ startAt: 1 }).populate('locationId', 'name shortName googleMapsUrl'),
    M.Consultation.findOne({ patientId: req.patient._id, doctorId: prof.userId, status: { $ne: 'draft' } }).sort({ startedAt: -1 }).populate('vitalsId').populate('prescriptionId', 'items tests advice file'),
    M.MedicalRecord.find({ patientId: req.patient._id, deletedAt: null, $or: [{ doctorId: prof.userId }, { 'sharedWith.userId': prof.userId }] }).sort({ recordDate: -1 }).limit(50),
    M.Consultation.find({ patientId: req.patient._id, doctorId: prof.userId, status: { $ne: 'draft' } }).sort({ startedAt: -1 }).limit(10),
    M.MedicationCourse.find({ patientId: req.patient._id, doctorId: prof.userId, status: 'active' }),
  ]);
  // Patient-DoctorDetail extras: specialty label, plan adherence, the chat with this doctor's clinic.
  const [spec, adh, convo] = await Promise.all([
    M.Specialty.findOne({ key: prof.specialtyKeys[0] }, 'label'),
    care.adherence(req.patient, 30),
    access?.practiceId ? M.Conversation.findOne({ patientId: req.patient._id, practiceId: access.practiceId, type: 'care' }) : null,
  ]);
  const fromDoctor = convo ? await M.Message.findOne({ conversationId: convo._id, senderId: prof.userId, deletedForEveryoneAt: null, hiddenFor: { $ne: req.user._id } }).sort({ createdAt: -1 }) : null;
  // The chat's newest message still there (deleted ones and ones hidden for me skipped), from either side.
  const latestMsg = convo ? await M.Message.findOne({ conversationId: convo._id, deletedForEveryoneAt: null, hiddenFor: { $ne: req.user._id }, senderType: { $ne: 'system' } }).sort({ createdAt: -1 }).populate('senderId', 'name') : null;
  const rxFiles = new Map((await M.Prescription.find({ _id: { $in: records.map((x) => x.prescriptionId).filter(Boolean) } }, 'file')).map((x) => [String(x._id), x.file?.key]));
  const lastFileUrl = (x) => storage.signedUrl(x.files?.[0]?.key || rxFiles.get(String(x.prescriptionId)));
  res.json({
    ...(card || { doctorId: prof.userId, name: prof.displayName }),
    bio: prof.bio,
    specialty: spec?.label || null,
    qualifications: prof.qualifications.map((q) => ({ name: q.name, institution: q.institution, year: q.year })),
    places: places.map((d) => ({ locationId: d.locationId._id, name: d.locationId.name, address: d.locationId.address, area: d.locationId.area, mapUrl: d.locationId.googleMapsUrl, lat: d.locationId.geo?.coordinates?.[1] ?? null, lng: d.locationId.geo?.coordinates?.[0] ?? null, km: haversineKm(origin, d.locationId.geo?.coordinates), services: d.services })),
    access: access && { level: access.accessLevel, since: access.since },
    nextVisit,
    lastVisit: lastVisit && {
      date: lastVisit.startedAt, diagnoses: lastVisit.diagnoses.map((d) => d.name), vitals: lastVisit.vitalsId, prescriptionId: lastVisit.prescriptionId?._id, advice: lastVisit.prescriptionId?.advice,
      chiefComplaint: lastVisit.chiefComplaint, prescriptionUrl: storage.signedUrl(lastVisit.prescriptionId?.file?.key),
    },
    adherencePct: adh.perDoctor.find((d) => d.doctor === String(prof.userId))?.pct ?? null,
    medicines: courses.map((c) => {
      const a = adh.perMedicine.find((m) => String(m.courseId) === String(c._id));
      return { id: c._id, name: c.name, strength: c.strength, pattern: c.frequency === 'weekly' ? `Once a week${c.weekday ? ` · ${c.weekday}` : ''}` : doseText(c.dose), foodRelation: c.foodRelation, tracked: c.trackingEnabled, adherencePct: a?.pct ?? null, isNew: a ? a.isNew : true };
    }),
    records: records.map((x) => ({ id: x._id, kind: x.kind, title: x.title, date: x.recordDate, origin: x.origin, sourceName: x.sourceName, flagLabel: x.flagLabel, flagTone: x.flagTone, url: lastFileUrl(x) })),
    timeline: history.map((h) => ({ date: h.startedAt, text: h.diagnoses.map((d) => d.name).join(', ') || h.chiefComplaint })),
    conversation: convo && {
      id: convo._id,
      unread: convo.participants.find((p) => String(p.userId) === String(req.user._id))?.unreadCount || 0,
      latestFromDoctor: fromDoctor && { text: fromDoctor.text, kind: fromDoctor.kind, at: fromDoctor.createdAt },
      latest: latestMsg && {
        text: latestMsg.text, kind: latestMsg.kind, at: latestMsg.createdAt,
        from: String(latestMsg.senderId?._id || latestMsg.senderId) === String(req.user._id) ? 'you' : latestMsg.senderType === 'ai' ? 'ai' : String(latestMsg.senderId?._id) === String(prof.userId) ? 'doctor' : 'clinic',
        name: latestMsg.senderId?.name || null,
      },
    },
  });
});

// Booking sheet (Find doctor → Request visit): where the doctor sees patients,
// the coming days at the chosen place with how many times are free on each, and
// the free times of the chosen day. ?locationId= &date=YYYY-MM-DD (both optional).
r.get('/doctors/:doctorId/booking', async (req, res) => {
  if (!isId(req.params.doctorId)) throw notFound('Doctor');
  const dls = await M.DoctorLocation.find({ doctorId: req.params.doctorId, status: 'active' }).populate('locationId', 'name shortName address area geo status');
  const origin = originOf(req);
  const mine = await M.CareTeamAccess.exists({ patientId: req.patient._id, userId: req.params.doctorId, accessLevel: { $ne: 'not_shared' } });
  const places = [];
  for (const dl of dls) {
    if (!dl.locationId || dl.locationId.status === 'inactive') continue;
    const { fee } = await S.feeFor(dl, { visitType: mine ? 'follow_up' : 'new', mode: 'in_clinic', patientId: req.patient._id });
    places.push({
      dl, locationId: String(dl.locationId._id), name: dl.locationId.name, area: dl.locationId.area || null, address: dl.locationId.address || null,
      km: haversineKm(origin, dl.locationId.geo?.coordinates), fee, online: dl.schedule?.onlineBooking !== false,
      // Today plus the doctor's booking window (as visit-requests allows).
      windowDays: Math.min(dl.schedule?.bookingWindowDays || 7, 30) + 1,
    });
  }
  if (!places.length) throw notFound('Doctor');
  // The asked place; else the nearest that takes online bookings.
  const byKm = [...places].sort((a, b) => (a.km ?? 1e9) - (b.km ?? 1e9));
  const place = places.find((p) => p.locationId === String(req.query.locationId)) || byKm.find((p) => p.online) || byKm[0];
  const today = T.dayStart();
  const days = [];
  if (place.online) {
    for (let i = 0; i < place.windowDays; i += 1) {
      const day = T.addDays(today, i);
      const out = await S.slotsFor({ doctorId: req.params.doctorId, locationId: place.locationId, day });
      const free = out.slots.filter((s) => s.available && !s.walkIn);
      days.push({ date: T.dayKey(day), free: free.length, reason: out.open ? (free.length ? null : 'full') : out.reason, slots: free.map((s) => ({ startAt: s.startAt, time: s.time })) });
    }
  }
  // The asked day; else the first with a free time.
  const day = days.find((d) => d.date === req.query.date) || days.find((d) => d.free > 0) || days[0] || null;
  res.json({
    places: places.map(({ dl, ...p }) => p),
    locationId: place.locationId,
    online: place.online,
    days: days.map(({ slots, ...d }) => d),
    date: day?.date || null,
    slots: day?.slots || [],
  });
});

r.get('/doctors/:doctorId/slots', async (req, res) => {
  if (!req.query.locationId) throw badRequest('locationId is required');
  // ?next=3: the next free online times over the coming two weeks (Find doctor "Pick a time").
  if (req.query.next) {
    const want = Math.min(Math.max(Number(req.query.next) || 3, 1), 12);
    const found = [];
    const dlr = await M.DoctorLocation.findOne({ doctorId: req.params.doctorId, locationId: req.query.locationId, status: 'active' }, 'schedule');
    if (dlr?.schedule?.onlineBooking === false) return res.json({ open: false, reason: 'online_booking_off', slots: [] });
    const windowDays = Math.min(dlr?.schedule?.bookingWindowDays || 7, 60) + 1;
    for (let i = 0; i < windowDays && found.length < want; i += 1) {
      const day = T.addDays(T.dayStart(req.query.date ? T.parseDay(req.query.date) : new Date()), i);
      const { slots } = await S.slotsFor({ doctorId: req.params.doctorId, locationId: req.query.locationId, day });
      for (const s of slots) if (s.available && !s.walkIn && found.length < want) found.push(s);
    }
    return res.json({ open: found.length > 0, slots: found });
  }
  const out = await S.slotsFor({ doctorId: req.params.doctorId, locationId: req.query.locationId, day: T.parseDay(req.query.date) });
  res.json({ ...out, slots: out.slots.filter((s) => !s.walkIn) });
});

// My doctors (Doctors tab).
r.get('/my-doctors', async (req, res) => {
  const team = await M.CareTeamAccess.find({ patientId: req.patient._id, accessLevel: { $ne: 'not_shared' } }).populate('userId', 'name').populate('practiceId', 'name');
  const adh = await care.adherence(req.patient, 30);
  const out = [];
  for (const c of team) {
    const [prof, next, last, convo, fu, meds] = await Promise.all([
      M.DoctorProfile.findOne({ userId: c.userId._id }, 'displayName headline presence avgReplyMinutes specialtyKeys'),
      M.Appointment.findOne({ patientId: req.patient._id, doctorId: c.userId._id, startAt: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting'] } }).sort({ startAt: 1 }),
      M.Appointment.findOne({ patientId: req.patient._id, doctorId: c.userId._id, status: 'completed' }).sort({ completedAt: -1 }),
      M.Conversation.findOne({ patientId: req.patient._id, practiceId: c.practiceId?._id, type: 'care' }),
      M.FollowUp.findOne({ patientId: req.patient._id, doctorId: c.userId._id, status: { $in: ['not_booked', 'no_reply'] } }).sort({ dueDate: 1 }),
      M.MedicationCourse.countDocuments({ patientId: req.patient._id, doctorId: c.userId._id, status: 'active' }),
    ]);
    const docAdh = adh.perDoctor.find((d) => d.doctor === String(c.userId._id));
    // "Diabetes · City Care, Salt Lake" on the Doctor tab.
    const [spec, place] = await Promise.all([
      prof?.specialtyKeys?.[0] ? M.Specialty.findOne({ key: prof.specialtyKeys[0] }, 'label') : null,
      M.DoctorLocation.findOne({ doctorId: c.userId._id, status: 'active', ...(c.practiceId ? { practiceId: c.practiceId._id } : {}) }).populate('locationId', 'name shortName area'),
    ]);
    out.push({
      specialty: spec?.label || null, practiceId: c.practiceId?._id, area: place?.locationId?.area || place?.locationId?.shortName || null, locationId: place?.locationId?._id || null,
      doctorId: c.userId._id, name: prof?.displayName || c.userId.name, role: c.role, headline: prof?.headline, clinic: c.practiceId?.name,
      ...(await require('../services/presence').presenceOf(c.userId._id)), nextVisit: next && { id: next._id, startAt: next.startAt, token: String(next.tokenNo).padStart(2, '0') },
      lastSeenAt: last?.completedAt, followUpDue: fu?.dueDate, medicines: meds, adherencePct: docAdh?.pct ?? null,
      conversationId: convo?._id, unread: convo?.participants.find((p) => String(p.userId) === String(req.user._id))?.unreadCount || 0,
    });
  }
  res.json(out);
});

// ── Visits ──
r.post('/visit-requests', async (req, res) => {
  const { doctorId, locationId, visitType = 'new', mode = 'in_clinic', reason, preferredTime, slot } = req.body;
  if (!isId(doctorId)) throw badRequest('Choose a doctor');
  const dl = await M.DoctorLocation.findOne({ doctorId, status: 'active', ...(locationId ? { locationId } : {}) });
  if (!dl) throw notFound('Doctor');
  // Booking rules (Profile → Booking rules).
  if (dl.schedule?.onlineBooking === false) throw conflict("This doctor isn't taking online bookings. Please call the clinic.", 'ONLINE_BOOKING_OFF');
  if (slot) {
    const lastDay = T.addDays(T.dayStart(), (dl.schedule?.bookingWindowDays || 7) + 1);
    if (new Date(slot) >= lastDay) throw badRequest(`You can book up to ${dl.schedule?.bookingWindowDays || 7} days ahead`, 'OUTSIDE_BOOKING_WINDOW');
  }
  await M.PatientEnrolment.findOneAndUpdate(
    { patientId: req.patient._id, practiceId: dl.practiceId },
    { $setOnInsert: { status: 'linked', shareScope: 'partial', linkedAt: new Date() } },
    { upsert: true },
  );
  await M.CareTeamAccess.findOneAndUpdate(
    { patientId: req.patient._id, userId: doctorId },
    { $setOnInsert: { practiceId: dl.practiceId, role: 'doctor', accessLevel: 'prescriptions_and_tests', since: new Date() } },
    { upsert: true },
  );
  const request = await M.AppointmentRequest.create({
    practiceId: dl.practiceId, patientId: req.patient._id, doctorId, locationId: dl.locationId, visitType, mode, reason, preferredTime,
    preferredSlots: slot ? [new Date(slot)] : [], channel: 'app',
  });
  // Instant booking when the doctor doesn't require approval and a slot was picked.
  let appointment = null;
  if (slot && !dl.schedule.requireApproval) {
    appointment = await S.book({ practiceId: dl.practiceId, locationId: dl.locationId, doctorId, patientId: req.patient._id, startAt: slot, visitType, mode, reason, channel: 'app', bookedBy: req.user._id, requestId: request._id });
    Object.assign(request, { status: 'scheduled', appointmentId: appointment._id, handledAt: new Date() });
    await request.save();
    const desk = await practiceStaff(dl.practiceId, { roles: ['front_desk', 'practice_manager'], locationId: dl.locationId });
    await notify([...desk, doctorId], {
      type: 'appointment_booked', practiceId: dl.practiceId, title: `${req.patient.name} booked a visit`,
      body: `${T.dayKey(appointment.startAt)} · ${T.fmtTime(T.minuteOfDay(appointment.startAt))}`, screen: 'Appointments',
    });
  } else {
    const desk = await practiceStaff(dl.practiceId, { roles: ['front_desk', 'practice_manager'], locationId: dl.locationId });
    await notify(desk, { type: 'visit_request', practiceId: dl.practiceId, title: `${req.patient.name} asked for a visit`, body: preferredTime || reason, screen: 'Appointments' });
  }
  res.status(201).json({ request, appointment });
});

r.get('/appointments', async (req, res) => {
  const upcoming = req.query.view !== 'past';
  const q = { patientId: req.patient._id, ...(upcoming ? { startAt: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } } : { $or: [{ startAt: { $lt: T.dayStart() } }, { status: { $in: ['completed', 'missed', 'cancelled'] } }] }) };
  const items = await M.Appointment.find(q).sort({ startAt: upcoming ? 1 : -1 }).limit(100).populate('doctorId', 'name').populate('locationId', 'name shortName googleMapsUrl');
  const requests = upcoming ? await M.AppointmentRequest.find({ patientId: req.patient._id, status: 'pending' }).populate('doctorId', 'name') : [];
  res.json({ items: items.map((a) => ({ ...a.toJSON(), token: a.tokenNo ? String(a.tokenNo).padStart(2, '0') : null })), pendingRequests: requests });
});

const myAppointment = async (req) => {
  const a = await M.Appointment.findOne({ _id: req.params.id, patientId: req.patient._id });
  if (!a) throw notFound('Visit');
  return a;
};

r.post('/appointments/:id/todos/:todoId', async (req, res) => {
  const a = await myAppointment(req);
  const t = a.todos.id(req.params.todoId);
  if (!t) throw notFound('To-do');
  t.done = req.body.done !== undefined ? Boolean(req.body.done) : !t.done;
  t.doneAt = t.done ? new Date() : undefined;
  await a.save();
  res.json(a.todos);
});

// In-app payment (Razorpay Checkout): start → the app opens Checkout → confirm
// with Razorpay's signed result. kind: 'fee' (id = appointment) or 'order'.
r.post('/checkout', async (req, res) => {
  res.json(await require('../services/checkout').start({ kind: req.body.kind, id: req.body.id, patient: req.patient }));
});
r.post('/checkout/confirm', async (req, res) => {
  const { kind, id, orderId, paymentId, signature } = req.body;
  res.json(await require('../services/checkout').confirm({ kind, id, orderId, paymentId, signature, patient: req.patient }));
});

// "Pay online" for a visit fee still pending (a Razorpay link the app opens).
r.post('/appointments/:id/pay', async (req, res) => {
  const appt = await M.Appointment.findOne({ _id: req.params.id, patientId: req.patient._id });
  if (!appt) throw notFound('Appointment');
  const p = await M.Payment.findOne({ appointmentId: appt._id, status: 'pending' });
  if (!p) throw conflict(appt.feeStatus === 'paid' ? 'This visit is already paid' : 'Nothing to pay for this visit', 'NOT_PENDING');
  const loc = await M.Location.findById(appt.locationId, 'paymentMethods');
  if (loc?.paymentMethods?.length && loc.paymentMethods.every((m) => m === 'cash')) throw conflict('This clinic takes the fee at the visit', 'ONLINE_PAY_OFF');
  const url = await require('../services/payments').feeLink(p, req.patient);
  res.json({ url, amount: p.amount });
});

r.post('/appointments/:id/cancel', async (req, res) => {
  const a = await myAppointment(req);
  const dl = await M.DoctorLocation.findOne({ doctorId: a.doctorId, locationId: a.locationId });
  const cutoff = (dl?.schedule.cancelCutoffHours || 2) * 3600e3;
  if (a.startAt - Date.now() < cutoff) throw conflict(`Visits can be cancelled up to ${dl?.schedule.cancelCutoffHours || 2} hours before. Please call the clinic.`, 'TOO_LATE');
  await S.transition(a, 'cancelled', { cancelledBy: 'patient', reason: req.body.reason });
  res.json(a);
});

r.post('/appointments/:id/reschedule', async (req, res) => {
  const a = await myAppointment(req);
  const next = await S.reschedule(a, req.body.startAt, req.user._id);
  res.json(next);
});

// ── Medicines ──
r.get('/medicines', async (req, res) => {
  const past = req.query.status === 'past';
  const courses = past
    ? await M.MedicationCourse.find({ patientId: req.patient._id, status: { $in: ['completed', 'stopped'] } }).sort({ updatedAt: -1 }).limit(100)
    : await M.MedicationCourse.find({ patientId: req.patient._id, status: 'active' });
  const adh = await care.adherence(req.patient, 30);
  const today = T.dayStart();
  const items = courses.map((c) => {
    const perDay = c.frequency === 'weekly' ? (dosesPerDay(c.dose) || 1) / 7 : dosesPerDay(c.dose);
    const day = Math.floor((today - T.dayStart(c.startDate)) / T.DAY_MS) + 1;
    const totalDays = c.endDate ? Math.floor((T.dayStart(c.endDate) - T.dayStart(c.startDate)) / T.DAY_MS) + 1 : null;
    const a = adh.perMedicine.find((m) => String(m.courseId) === String(c._id));
    return {
      id: c._id, name: c.name, strength: c.strength, pattern: c.frequency === 'weekly' ? `Once a week${c.weekday ? ` · ${c.weekday}` : ''}` : doseText(c.dose),
      foodRelation: c.foodRelation, instructions: c.instructions, prescriber: c.prescriberName, doctorId: c.doctorId, startDate: c.startDate, endDate: c.endDate,
      course: { day, totalDays }, tracked: c.trackingEnabled, adherencePct: a?.pct ?? null,
      stock: c.stockUnits != null ? { units: c.stockUnits, daysLeft: perDay ? Math.floor(c.stockUnits / perDay) : null } : null,
      // Med-AddToCart works out pack sizes from these; self-added medicines can be edited.
      dose: c.dose, frequency: c.frequency, weekday: c.weekday, perDay, unitsPerStrip: c.unitsPerStrip || 10,
      prescriptionId: c.prescriptionId, selfAdded: !c.doctorId && !c.prescriptionId, status: c.status, stoppedAt: c.stoppedAt,
    };
  });
  if (past) return res.json({ items });
  items.sort((a, b) => (a.stock?.daysLeft ?? 1e9) - (b.stock?.daysLeft ?? 1e9));
  const doctors = new Set(courses.map((c) => String(c.doctorId || c.prescriberName)));
  const allergies = req.patient.allergies.map((x) => x.allergen);
  // Safety card: allergy clashes against the medicine catalog.
  const { checkItems } = require('../services/clinical');
  const checks = await checkItems(req.patient, courses.map((c) => ({ name: c.name, strength: c.strength })));
  const warnings = checks.flatMap((c) => c.warnings.filter((w) => w.type === 'allergy').map((w) => ({ medicine: c.name, text: w.text })));
  const [nextVisit, pastCount] = await Promise.all([
    M.Appointment.findOne({ patientId: req.patient._id, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] } }).sort({ startAt: 1 }),
    M.MedicationCourse.countDocuments({ patientId: req.patient._id, status: { $in: ['completed', 'stopped'] } }),
  ]);
  res.json({
    running: items.length, fromDoctors: doctors.size, adherence30d: adh.overallPct, allergies, items,
    safety: { checked: items.length, warnings }, nextVisitAt: nextVisit?.startAt || null, pastCount,
    reminderTimes: req.patient.settings?.reminderTimes || null,
    bedAt: req.patient.settings?.bedAt || '22:30',
    // Medicines read from prescriptions the patient uploaded, not added yet.
    fromUploads: (await M.MedicalRecord.find({ patientId: req.patient._id, kind: 'prescription', deletedAt: null, medicinesAddedAt: null, 'extractedMedicines.0': { $exists: true }, createdAt: { $gte: T.addDays(new Date(), -60) } }).sort({ createdAt: -1 }).limit(5))
      .map((r) => ({ recordId: r._id, title: r.title, date: r.recordDate, doctor: r.extractedDoctor || r.sourceName, medicines: r.extractedMedicines })),
  });
});

// Uploaded prescription → "Add these to my medicines" (the patient picks which).
r.post('/records/:id/add-medicines', async (req, res) => {
  const record = await M.MedicalRecord.findOne({ _id: req.params.id, patientId: req.patient._id, deletedAt: null });
  if (!record) throw notFound('Prescription');
  const all = record.extractedMedicines || [];
  if (!all.length) throw badRequest('No medicines were found on this prescription', 'NO_MEDICINES');
  const pickIdx = Array.isArray(req.body.indices) ? req.body.indices.filter((i) => Number.isInteger(i) && i >= 0 && i < all.length) : all.map((_, i) => i);
  const created = [];
  for (const i of pickIdx) {
    const m = all[i];
    const dose = { morning: Number(m.morning) || 0, afternoon: Number(m.afternoon) || 0, night: Number(m.night) || 0 };
    if (!dose.morning && !dose.afternoon && !dose.night) dose.morning = 1;
    const days = Number(m.duration_days) || 0;
    created.push(await M.MedicationCourse.create({
      patientId: req.patient._id, name: String(m.name).slice(0, 80), strength: m.strength || undefined, dose,
      foodRelation: ['before_food', 'after_food', 'with_food', 'empty_stomach'].includes(m.food) ? m.food : undefined,
      instructions: m.instructions || undefined, prescriberName: record.extractedDoctor || record.sourceName || undefined,
      startDate: T.dayStart(), endDate: days ? T.addDays(T.dayStart(), days) : undefined,
    }));
  }
  record.medicinesAddedAt = new Date();
  await record.save();
  res.status(201).json({ added: created.length, items: created });
});

r.post('/medicines', async (req, res) => {
  const body = pick(req.body, ['name', 'strength', 'dose', 'frequency', 'weekday', 'foodRelation', 'instructions', 'prescriberName', 'stockUnits', 'endDate']);
  if (!body.name) throw badRequest('Enter the medicine name');
  const c = await M.MedicationCourse.create({ ...body, patientId: req.patient._id, startDate: req.body.startDate ? T.parseDay(req.body.startDate) : T.dayStart() });
  res.status(201).json(c);
});

r.patch('/medicines/:id', async (req, res) => {
  const c = await M.MedicationCourse.findOne({ _id: req.params.id, patientId: req.patient._id });
  if (!c) throw notFound('Medicine');
  Object.assign(c, pick(req.body, ['trackingEnabled', 'stockUnits']));
  if (req.body.stockUnits != null) c.stockUpdatedAt = new Date();
  // Medicines the patient added themselves can be edited in full.
  if (!c.doctorId && !c.prescriptionId) {
    const edit = pick(req.body, ['name', 'strength', 'dose', 'frequency', 'weekday', 'foodRelation', 'instructions', 'prescriberName', 'endDate']);
    if (edit.name !== undefined && !String(edit.name).trim()) throw badRequest('Enter the medicine name');
    Object.assign(c, edit);
  }
  if (req.body.stop) { c.status = 'stopped'; c.stoppedAt = new Date(); }
  await c.save();
  res.json(c);
});

// Patient-Medicines "Share medicine list": PDF of the medicines taken now.
r.post('/medicines/share-pdf', async (req, res) => {
  const { renderMedicineList } = require('../services/medlist');
  const courses = await M.MedicationCourse.find({ patientId: req.patient._id, status: 'active' }).sort({ startDate: 1 });
  const pdf = await renderMedicineList({ patient: req.patient, courses });
  const file = await storage.save(pdf, { folder: 'exports', name: 'Medicine list.pdf', mimeType: 'application/pdf' });
  res.status(201).json({ ...storage.withUrl(file), count: courses.length });
});

r.get('/doses', async (req, res) => {
  const day = T.parseDay(req.query.date);
  await care.ensureDoses(req.patient, day);
  const doses = await M.DoseLog.find({ patientId: req.patient._id, scheduledAt: { $gte: day, $lt: T.addDays(day, 1) } }).sort({ scheduledAt: 1 }).populate('courseId', 'name strength foodRelation instructions');
  const items = doses.map((d) => ({ id: d._id, slot: d.slot, at: d.scheduledAt, status: care.effectiveStatus(d), takenAt: d.takenAt, medicine: d.courseId && { id: d.courseId._id, name: d.courseId.name, strength: d.courseId.strength, foodRelation: d.courseId.foodRelation } }));
  res.json({ date: day, taken: items.filter((d) => d.status === 'taken').length, total: items.length, items });
});

// Taken / Skip / undo (back to due).
r.post('/doses/:id', async (req, res) => {
  const d = await M.DoseLog.findOne({ _id: req.params.id, patientId: req.patient._id });
  if (!d) throw notFound('Dose');
  const status = req.body.status;
  if (!['taken', 'skipped', 'due'].includes(status)) throw badRequest('status must be taken, skipped or due');
  const was = d.status;
  d.status = status;
  d.takenAt = status === 'taken' ? new Date() : undefined;
  await d.save();
  // Stock goes down when a dose is taken (and back up on undo).
  const course = await M.MedicationCourse.findById(d.courseId);
  const units = course?.dose?.[d.slot] || 1;
  if (course?.stockUnits != null) {
    if (status === 'taken' && was !== 'taken') course.stockUnits = Math.max(0, course.stockUnits - units);
    if (was === 'taken' && status !== 'taken') course.stockUnits += units;
    await course.save();
  }
  res.json(d);
});

r.get('/adherence', async (req, res) => {
  const out = await care.adherence(req.patient, Math.min(Number(req.query.days) || 30, 180));
  const doctorIds = out.perDoctor.map((d) => d.doctor).filter(isId);
  const names = new Map((await M.User.find({ _id: { $in: doctorIds } }, 'name')).map((u) => [String(u._id), u.name]));
  // Patient-Adherence: one card per doctor with their medicines (untracked ones too).
  const [profiles, team, courses] = await Promise.all([
    M.DoctorProfile.find({ userId: { $in: doctorIds } }, 'userId specialtyKeys'),
    M.CareTeamAccess.find({ patientId: req.patient._id, userId: { $in: doctorIds } }).populate('practiceId', 'name'),
    M.MedicationCourse.find({ patientId: req.patient._id, status: 'active' }, 'startDate'),
  ]);
  const labels = new Map((await M.Specialty.find({ key: { $in: profiles.flatMap((p) => p.specialtyKeys) } }, 'key label')).map((s) => [s.key, s.label]));
  const started = new Map(courses.map((c) => [String(c._id), c.startDate]));
  const groups = new Map();
  const groupOf = (key, fallbackName) => {
    if (!groups.has(key)) {
      const prof = profiles.find((p) => String(p.userId) === key);
      const access = team.find((c) => String(c.userId) === key);
      const perDoc = out.perDoctor.find((d) => d.doctor === key);
      groups.set(key, {
        id: key, name: names.get(key) || fallbackName || (key === 'self' ? 'Added by you' : key),
        specialty: prof ? labels.get(prof.specialtyKeys[0]) || null : null, clinic: access?.practiceId?.name || null,
        pct: perDoc?.pct ?? null, medicines: [],
      });
    }
    return groups.get(key);
  };
  for (const d of out.perDoctor) groupOf(d.doctor);
  for (const m of out.perMedicine) {
    const key = m.doctorId ? String(m.doctorId) : m.prescriber || 'self';
    groupOf(key, m.prescriber).medicines.push({ courseId: m.courseId, name: m.name, strength: m.strength, tracked: m.tracked, pct: m.pct, isNew: m.isNew, startDate: started.get(String(m.courseId)) || null });
  }
  const doctors = [...groups.values()].map((g) => ({ ...g, tracked: g.medicines.length ? g.medicines.some((m) => m.tracked) : g.pct != null }));
  doctors.sort((a, b) => Number(b.tracked) - Number(a.tracked) || (b.medicines.length - a.medicines.length));
  res.json({
    ...out,
    perDoctor: out.perDoctor.map((d) => ({ ...d, name: names.get(d.doctor) || d.doctor })),
    doctors,
    medReminders: req.patient.toObject().settings?.medReminders !== false,
    reminderTimes: req.patient.toObject().settings?.reminderTimes || null,
    bedAt: req.patient.settings?.bedAt || '22:30',
  });
});

// ── Health log (meal / exercise / steps) and activity plans ──
r.get('/logs', async (req, res) => {
  const day = T.parseDay(req.query.date);
  const logs = await M.HealthLog.find({ patientId: req.patient._id, loggedAt: { $gte: day, $lt: T.addDays(day, 1) } }).sort({ loggedAt: 1 });
  res.json(logs.map((l) => ({ ...l.toJSON(), photo: storage.withUrl(l.photo) })));
});

/** Which app the counted steps came from ("Mi Fitness"), when a watch app wrote them. */
function stepApp(p, source) {
  if (source !== 'watch') return null;
  return p.deviceSync?.devices?.watch?.apps?.join(', ') || p.deviceSync?.devices?.ring?.apps?.join(', ') || null;
}

// Daily log history: each day's meals, exercise and steps — what, how much, when
// and where it came from (you, the phone's step counter, a watch app via Health Connect).
r.get('/logs/history', async (req, res) => {
  const p = req.patient;
  const days = Math.min(60, Math.max(1, Number(req.query.days) || 14));
  const today = T.dayStart();
  const from = T.addDays(today, -(days - 1));
  const logs = await M.HealthLog.find({ patientId: p._id, loggedAt: { $gte: from, $lt: T.addDays(today, 1) } }).sort({ loggedAt: 1 });
  const team = await logShareTeam(p);
  const goal = { steps: p.targets?.stepsPerDay || 8000, exerciseMin: p.targets?.exerciseMinPerDay || 30 };
  const out = [];
  for (let d = today; d >= from; d = T.addDays(d, -1)) {
    const key = T.dayKey(d);
    const mine = logs.filter((l) => T.dayKey(l.loggedAt) === key);
    const meals = mine.filter((l) => l.type === 'meal').map((l) => ({
      id: l._id, mealType: l.mealType, at: l.loggedAt, note: l.note || '', photo: l.photo?.key ? storage.withUrl(l.photo) : null, source: 'You',
      reviewed: l.review?.at ? { at: l.review.at, comment: l.review.comment || '' } : null,
    }));
    const exercise = mine.filter((l) => l.type === 'exercise').map((l) => ({
      id: l._id, exerciseType: l.exerciseType, durationMin: l.durationMin || 0, at: l.loggedAt, note: l.note || '', source: l.fromDevice ? 'Health Connect' : 'You',
    }));
    // Steps: the counted total and the typed one measure the same walking, so the higher counts.
    const stepLogs = mine.filter((l) => l.type === 'steps');
    const counted = stepLogs.filter((l) => l.fromDevice).reduce((s, l) => s + (l.steps || 0), 0);
    const typed = Math.max(0, ...stepLogs.filter((l) => !l.fromDevice).map((l) => l.steps || 0));
    const fromPhone = stepLogs.some((l) => l.fromDevice && l.stepSource === 'phone') && !stepLogs.some((l) => l.fromDevice && l.stepSource === 'watch');
    const stepSource = !stepLogs.length ? null : typed > counted ? 'manual' : fromPhone ? 'phone' : 'watch';
    const sourceLabel = { manual: 'Entered by you', phone: "Your phone's step counter", watch: `Health Connect${stepApp(p, 'watch') ? ` · ${stepApp(p, 'watch')}` : ''}` }[stepSource] || null;
    out.push({
      date: d, day: key,
      meals,
      exercise: { minutes: exercise.reduce((s, x) => s + x.durationMin, 0), goal: goal.exerciseMin, items: exercise },
      steps: { total: Math.max(counted, typed), goal: goal.steps, source: stepSource, sourceLabel, manualId: stepLogs.find((l) => !l.fromDevice)?._id || null },
    });
  }
  res.json({ days: out, goals: goal, sharedWith: team.map((c) => ({ userId: c.userId?._id, name: c.userId?.name, role: c.role })) });
});

// Patient-Log: who the entry can be shared with, and today's steps for the Steps tab.
r.get('/logs/options', async (req, res) => {
  const p = req.patient;
  const today = T.dayStart();
  const [team, steps, enrolment] = await Promise.all([
    M.CareTeamAccess.find({ patientId: p._id, accessLevel: { $ne: 'not_shared' } }).populate('userId', 'name'),
    stepsToday(p._id, today),
    M.PatientEnrolment.findOne({ patientId: p._id, status: 'linked' }).populate('practiceId', 'foodLogReviewCadence'),
  ]);
  const profiles = await M.DoctorProfile.find({ userId: { $in: team.map((c) => c.userId?._id) } }, 'userId specialtyKeys');
  const labels = new Map((await M.Specialty.find({ key: { $in: profiles.flatMap((x) => x.specialtyKeys) } }, 'key label')).map((s) => [s.key, s.label]));
  const cadence = enrolment?.practiceId?.foodLogReviewCadence || 'every_3_days';
  const reviews = { daily: 'reviews every day', every_3_days: 'reviews every 3 days', weekly: 'reviews every week' }[cadence];
  const shareWith = team.filter((c) => c.userId).map((c) => {
    const prof = profiles.find((x) => String(x.userId) === String(c.userId._id));
    const specialty = prof ? labels.get(prof.specialtyKeys[0]) : null;
    const label = c.role === 'dietician' ? `Dietician · ${reviews}` : specialty || c.role.replace(/_/g, ' ').replace(/^./, (x) => x.toUpperCase());
    const seesLogs = ['full_with_logs', 'daily_log_only'].includes(c.accessLevel);
    const selected = Array.isArray(p.logShareWith) ? p.logShareWith.some((id) => String(id) === String(c.userId._id)) : seesLogs;
    return { userId: c.userId._id, name: c.userId.name, role: c.role, label, seesLogs, selected };
  });
  // Dieticians first (they review food logs), then doctors who already see the log.
  shareWith.sort((a, b) => Number(b.role === 'dietician') - Number(a.role === 'dietician') || Number(b.seesLogs) - Number(a.seesLogs));
  const plans = await M.ActivityPlan.find({ patientId: p._id, active: true }, 'name exerciseType durationMin');
  res.json({ shareWith, steps: { today: steps.today, goal: p.targets?.stepsPerDay || 8000, source: steps.source }, activityPlans: plans });
});

// "Share your daily log": who sees new meals, exercise and steps.
r.put('/log-sharing', async (req, res) => {
  const ids = list(req.body.userIds).filter(isId);
  const team = await M.CareTeamAccess.find({ patientId: req.patient._id, userId: { $in: ids }, accessLevel: { $ne: 'not_shared' } }).distinct('userId');
  req.patient.logShareWith = team;
  await req.patient.save();
  res.json({ userIds: team });
});

r.post('/logs', photoUpload.single('photo'), async (req, res) => {
  const b = req.body;
  if (!E.LOG_TYPES.includes(b.type)) throw badRequest('Choose meal, exercise or steps');
  if (b.type === 'steps' && !(Number.isInteger(Number(b.steps)) && Number(b.steps) >= 0 && Number(b.steps) <= 200000)) throw badRequest('Enter the steps (0–200,000)');
  const sharedWith = list(b.sharedWith).filter(isId);
  // The ticks become the patient's sharing choice for the next entries too.
  if (b.sharedWith !== undefined) {
    const allowed = await M.CareTeamAccess.find({ patientId: req.patient._id, userId: { $in: sharedWith }, accessLevel: { $ne: 'not_shared' } }).distinct('userId');
    req.patient.logShareWith = allowed;
    await req.patient.save();
  }
  const practice = (await M.PatientEnrolment.findOne({ patientId: req.patient._id, status: 'linked' }).populate('practiceId', 'foodLogReviewCadence'))?.practiceId;
  const cadence = { daily: 1, every_3_days: 3, weekly: 7 }[practice?.foodLogReviewCadence || 'every_3_days'];
  if (b.type === 'steps') {
    // "Steps today" is the day's total: saving again replaces it.
    const day = T.dayStart(b.loggedAt ? new Date(b.loggedAt) : new Date());
    const log = await M.HealthLog.findOneAndUpdate(
      { patientId: req.patient._id, type: 'steps', fromDevice: { $ne: true }, loggedAt: { $gte: day, $lt: T.addDays(day, 1) } },
      { $set: { steps: Number(b.steps), sharedWith, inputMode: b.inputMode, note: b.note }, $setOnInsert: { patientId: req.patient._id, type: 'steps', loggedAt: new Date() } },
      { upsert: true, new: true },
    );
    return res.status(201).json(log);
  }
  const log = await M.HealthLog.create({
    patientId: req.patient._id, type: b.type, mealType: b.mealType, exerciseType: b.exerciseType, durationMin: b.durationMin, steps: b.steps, note: b.note,
    inputMode: b.inputMode, loggedAt: b.loggedAt ? new Date(b.loggedAt) : new Date(), sharedWith, activityPlanId: b.activityPlanId,
    photo: req.file ? await storage.save(req.file.buffer, { folder: 'logs', name: req.file.originalname, mimeType: req.file.mimetype }) : undefined,
    review: b.type === 'meal' && sharedWith.length ? { dueAt: T.addDays(T.dayStart(), cadence) } : undefined,
  });
  res.status(201).json(log);
});

r.delete('/logs/:id', async (req, res) => {
  await M.HealthLog.deleteOne({ _id: req.params.id, patientId: req.patient._id });
  res.json({ ok: true });
});

r.get('/activity-plans', async (req, res) => {
  const plans = await M.ActivityPlan.find({ patientId: req.patient._id, active: true });
  const weekStart = T.addDays(T.dayStart(), -((new Date(Date.now() + T.IST_MS).getUTCDay() + 6) % 7));
  res.json(plans.map((p) => ({ ...p.toJSON(), doneThisWeek: p.completions.filter((d) => d >= weekStart).length })));
});

r.post('/activity-plans', async (req, res) => {
  if (!req.body.name) throw badRequest('Name the activity');
  res.status(201).json(await M.ActivityPlan.create({ ...pick(req.body, ['name', 'exerciseType', 'durationMin', 'plannedTime', 'daysPerWeek']), patientId: req.patient._id, setBy: req.user._id }));
});

r.post('/activity-plans/:id/done', async (req, res) => {
  const p = await M.ActivityPlan.findOne({ _id: req.params.id, patientId: req.patient._id });
  if (!p) throw notFound('Plan');
  const today = T.dayKey(new Date());
  if (!p.completions.some((d) => T.dayKey(d) === today)) p.completions.push(new Date());
  await p.save();
  res.json(p);
});

// ── Home readings (BP, sugar, weight…) ──
r.post('/readings', async (req, res) => {
  const v = pick(req.body, ['bpSystolic', 'bpDiastolic', 'pulse', 'spo2', 'temperatureF', 'weightKg', 'bloodSugar', 'sugarType', 'note']);
  if (!Object.keys(v).filter((k) => k !== 'note').length) throw badRequest('Enter a reading');
  const p = req.patient;
  const vitals = await M.Vitals.create({
    ...v, patientId: p._id, recordedBy: req.user._id, recordedByRole: 'patient', source: req.body.source === 'device' ? 'device' : 'home',
    recordedAt: req.body.recordedAt ? new Date(req.body.recordedAt) : new Date(),
    bmi: p.heightCm && v.weightKg ? +(v.weightKg / (p.heightCm / 100) ** 2).toFixed(1) : undefined,
  });
  if (v.weightKg) { p.weightKg = v.weightKg; await p.save(); }
  const alerts = await care.checkReading(vitals, p);
  res.status(201).json({ reading: vitals, alerted: alerts.length > 0 });
});

// Watch / phone sync (Health Connect, Apple Health): daily steps and readings.
// Sent again and again; the same day / reading is never counted twice.
r.post('/device-sync', async (req, res) => {
  const p = req.patient;
  const days = (Array.isArray(req.body.days) ? req.body.days : []).slice(0, 31);
  const readings = (Array.isArray(req.body.readings) ? req.body.readings : []).slice(0, 300);
  let steps = 0;
  for (const d of days) {
    const day = T.parseDay(d.date);
    const n = Math.round(Number(d.steps));
    if (!day || !Number.isFinite(n) || n < 0 || n > 200000) continue;
    await M.HealthLog.findOneAndUpdate(
      { patientId: p._id, type: 'steps', fromDevice: true, loggedAt: { $gte: day, $lt: T.addDays(day, 1) } },
      { $set: { steps: n, stepSource: d.source === 'phone' ? 'phone' : 'watch' }, $setOnInsert: { patientId: p._id, type: 'steps', fromDevice: true, loggedAt: T.addMinutes(day, 12 * 60) } },
      { upsert: true },
    );
    steps += 1;
  }
  const FIELDS = { pulse: 'pulse', spo2: 'spo2', weight: 'weightKg', sugar: 'bloodSugar', bp: 'bpSystolic' };
  let added = 0;
  let alerted = false;
  for (const x of readings) {
    const field = FIELDS[x.kind];
    const at = new Date(x.at);
    const value = Number(x.value);
    if (!field || Number.isNaN(at.getTime()) || at > new Date(Date.now() + 5 * 60e3) || !Number.isFinite(value)) continue;
    if (await M.Vitals.exists({ patientId: p._id, source: 'device', recordedAt: at, [field]: { $ne: null } })) continue;
    const v = { [field]: value };
    if (x.kind === 'bp') v.bpDiastolic = Number(x.value2);
    if (x.kind === 'sugar') v.sugarType = ['fasting', 'random', 'post_meal'].includes(x.sugarType) ? x.sugarType : 'random';
    try {
      const vitals = await M.Vitals.create({ ...v, patientId: p._id, recordedBy: req.user._id, recordedByRole: 'patient', source: 'device', recordedAt: at });
      added += 1;
      // Only fresh readings can raise an alert (not last month's history).
      if (at > T.addDays(new Date(), -1)) alerted = (await care.checkReading(vitals, p)).length > 0 || alerted;
    } catch (err) {
      if (err.name !== 'ValidationError') throw err; // out-of-range values are skipped
    }
  }
  const source = String(req.body.source || 'device').slice(0, 40);
  // What the last sync brought in, and which watch / ring apps the data came from.
  const { classifyOrigins } = require('../services/devices');
  const found = classifyOrigins(Array.isArray(req.body.origins) ? req.body.origins.slice(0, 50).map(String) : []);
  const prev = p.deviceSync || {};
  const now = new Date();
  const devices = {
    watch: found.watch.length ? { at: now, apps: found.watch } : prev.devices?.watch,
    ring: found.ring.length ? { at: now, apps: found.ring } : prev.devices?.ring,
  };
  await M.Patient.updateOne({ _id: p._id }, { deviceSync: { at: now, source, readings: added, stepDays: steps, devices } });
  res.json({ days: steps, readings: added, alerted, at: new Date(), source });
});

r.get('/readings', async (req, res) => {
  const days = Math.min(Number(req.query.days) || 30, 365);
  const field = { blood_sugar: 'bloodSugar', blood_pressure: 'bpSystolic', weight: 'weightKg', heart_rate: 'pulse', spo2: 'spo2' }[req.query.measure];
  const q = { patientId: req.patient._id, recordedAt: { $gte: T.addDays(new Date(), -days) }, ...(field ? { [field]: { $ne: null } } : {}) };
  res.json(await M.Vitals.find(q).sort({ recordedAt: 1 }).limit(1000));
});

// ── Records ──
r.get('/records', async (req, res) => {
  // Results a clinic typed in before they were filed as records: file them now (once).
  for (const lab of await M.LabResult.find({ patientId: req.patient._id, recordId: null }).limit(50)) {
    const n = lab.abnormalCount || 0;
    const rec = await M.MedicalRecord.create({
      patientId: lab.patientId, kind: 'test_result', title: lab.testName || 'Test result', recordDate: lab.collectedAt || lab.createdAt,
      origin: 'from_doctor', sourceName: lab.labName || undefined, practiceId: lab.practiceId, flagLabel: n ? `${n} abnormal` : 'Normal', flagTone: n ? 'high' : 'ok',
    });
    await M.LabResult.updateOne({ _id: lab._id, recordId: null }, { recordId: rec._id });
  }
  const q = { patientId: req.patient._id, deletedAt: null };
  if (req.query.kind) q.kind = req.query.kind;
  let items = await M.MedicalRecord.find(q).sort({ recordDate: -1 }).limit(300);
  if (req.query.q) {
    const re = new RegExp(escapeRegex(req.query.q), 'i');
    items = items.filter((x) => re.test(x.title) || re.test(x.kind) || re.test(x.sourceName || '') || re.test(x.aiSummary || ''));
  }
  const all = await M.MedicalRecord.aggregate([{ $match: { patientId: req.patient._id, deletedAt: null } }, { $group: { _id: '$kind', n: { $sum: 1 } } }]);
  const counts = Object.fromEntries(all.map((x) => [x._id, x.n]));
  res.json({
    counts: { all: Object.values(counts).reduce((a, b) => a + b, 0), ...counts },
    items: items.map((x) => ({ ...x.toJSON(), files: x.files.map(storage.withUrl) })),
    // Tests the doctor asked for, what each checks, how to prepare, and whether a result came in.
    advisedTests: await require('../services/advisedtests').advisedTests(req.patient).catch((err) => { console.warn('[advised tests]', err.message); return []; }),
  });
});

r.get('/records/:id', async (req, res) => {
  const rec = await M.MedicalRecord.findOne({ _id: req.params.id, patientId: req.patient._id, deletedAt: null });
  if (!rec) throw notFound('Record');
  const results = await M.LabResult.find({ recordId: rec._id });
  const rx = rec.prescriptionId ? await M.Prescription.findById(rec.prescriptionId) : null;
  res.json({ ...rec.toJSON(), files: rec.files.map(storage.withUrl), results, prescription: rx && { ...rx.toJSON(), file: storage.withUrl(rx.file) } });
});

// Records-Add: upload. For a test report the AI proposes the tests it found (Records-Review).
r.post('/records', upload.array('files', 10), async (req, res) => {
  if (!req.files?.length) throw badRequest('Choose a file');
  const kind = req.body.kind === 'prescription' ? 'prescription' : 'test_result';
  const files = [];
  for (const f of req.files) files.push(await storage.save(f.buffer, { folder: 'records', name: f.originalname, mimeType: f.mimetype }));
  const sharedWith = list(req.body.shareWith).filter(isId).map((userId) => ({ userId }));
  const record = await M.MedicalRecord.create({
    patientId: req.patient._id, kind, title: req.body.title || (kind === 'prescription' ? 'Prescription' : 'Test report'),
    recordDate: req.body.recordDate ? T.parseDay(req.body.recordDate) : new Date(), origin: 'shared_by_patient', sourceName: req.body.sourceName || 'uploaded by you',
    uploadSource: E.UPLOAD_SOURCES.includes(req.body.uploadSource) ? req.body.uploadSource : undefined, files, sharedWith,
    status: kind === 'test_result' ? 'processing' : 'ready', uploadedBy: req.user._id, flagLabel: 'New', flagTone: 'new',
  });
  let extracted = null;
  if (kind === 'prescription') {
    const rx = await assistant.extractPrescription(req.files[0].buffer, req.files[0].mimetype).catch((err) => { console.warn('[extract-rx]', err.message); return null; });
    if (rx?.medicines?.length) {
      record.extractedMedicines = rx.medicines.filter((m) => m.name);
      record.extractedDoctor = rx.doctor_name || undefined;
      await record.save();
    }
  }
  if (kind === 'test_result') {
    extracted = await assistant.extractLabReport(req.files[0].buffer, req.files[0].mimetype).catch((err) => { console.warn('[extract]', err.message); return null; });
    // Which of the doctor's tests the report really contains (its content, not the file name).
    await applyTestCheck(req.patient, record, list(req.body.forTests).map((s) => String(s).trim()).filter(Boolean).slice(0, 1), extracted);
    if (!extracted || !extracted.tests?.length) record.status = 'ready';
    await record.save();
  }
  if (sharedWith.length) {
    await notify(sharedWith.map((s) => s.userId), { type: 'record_shared', title: `${req.patient.name} shared a ${kind === 'prescription' ? 'prescription' : 'report'}`, screen: 'Patient-Profile', params: { patientId: req.patient._id } });
  }
  res.status(201).json({ record: { ...record.toJSON(), files: record.files.map(storage.withUrl) }, extracted, testCheck: record.testCheck || null, medicines: record.extractedMedicines || [] });
});

/**
 * Checks an uploaded report's content against the doctor's tests: the one it
 * was uploaded for (Upload on a test), or else every test still to do (Add
 * record), so a report counts for what it really contains. Sets forTests to
 * the tests found and testCheck to the whole result; names the record after
 * the tests read from it.
 */
async function applyTestCheck(patient, record, asked, extracted) {
  if (record.kind !== 'test_result') return;
  const AT = require('../services/advisedtests');
  const auto = !asked.length;
  const names = auto ? (await AT.advisedTests(patient)).filter((x) => x.status !== 'done').map((x) => x.name) : asked;
  if (!names.length && auto) return;
  record.testCheck = AT.checkReport(names, extracted, { auto });
  record.forTests = record.testCheck.found;
  const read = record.testCheck.detected;
  if (read.length && (!record.title || record.title === 'Test report')) record.title = read.length > 3 ? `${read.slice(0, 3).join(', ')} and ${read.length - 3} more` : read.join(', ');
}

// Records-Review reopened for a report still waiting to be checked: read it again.
r.post('/records/:id/extract', async (req, res) => {
  const rec = await M.MedicalRecord.findOne({ _id: req.params.id, patientId: req.patient._id, deletedAt: null });
  if (!rec) throw notFound('Record');
  const file = rec.files[0];
  if (rec.kind !== 'test_result' || !file?.key) throw badRequest('This record has no report to read', 'NOT_A_REPORT');
  const buffer = await storage.read(file.key).catch(() => null);
  const extracted = buffer ? await assistant.extractLabReport(buffer, file.mimeType || 'application/pdf').catch((err) => { console.warn('[extract]', err.message); return null; }) : null;
  // Read again: check it again against what it was uploaded for.
  if (extracted) await applyTestCheck(req.patient, rec, rec.testCheck && !rec.testCheck.auto ? rec.testCheck.asked || [] : [], extracted);
  if (!extracted && rec.status === 'processing') rec.status = 'ready';
  await rec.save();
  res.json({ record: { ...rec.toJSON(), files: rec.files.map(storage.withUrl) }, extracted, testCheck: rec.testCheck || null });
});

// Records-Review: save the tests the patient kept; each test becomes its own record.
r.post('/records/:id/split', async (req, res) => {
  const parent = await M.MedicalRecord.findOne({ _id: req.params.id, patientId: req.patient._id, deletedAt: null });
  if (!parent) throw notFound('Record');
  const tests = req.body.tests || [];
  if (!tests.length) throw badRequest('Pick at least one test to save', 'TEST_REQUIRED');
  const collectedAt = req.body.collectedAt ? T.parseDay(req.body.collectedAt) : parent.recordDate;
  const labName = req.body.labName || parent.sourceName;
  // "Share all N tests with" on Records-Review (else keep who the upload was shared with).
  const sharedWith = req.body.shareWith !== undefined ? list(req.body.shareWith).filter(isId).map((userId) => ({ userId })) : parent.sharedWith;
  const created = [];
  const { inReport } = require('../services/advisedtests');
  for (const t of tests) {
    // The doctor's tests the upload was checked to contain: each saved test keeps the ones its own content shows.
    const name = t.testName || t.test_name;
    const forTests = (parent.forTests || []).filter((x) => inReport(x, [name, ...(t.values || []).map((v) => v.analyte)]));
    const values = (t.values || []).map((v) => ({
      analyte: v.analyte, value: Number.isFinite(parseFloat(v.value)) ? parseFloat(v.value) : undefined, valueText: Number.isFinite(parseFloat(v.value)) ? undefined : v.value,
      unit: v.unit, refText: v.refText || v.ref_text, refLow: v.refLow, refHigh: v.refHigh, flag: E.RESULT_FLAGS.includes(v.flag) ? v.flag : 'normal',
    }));
    const abnormal = values.filter((v) => v.flag !== 'normal').length;
    const rec = await M.MedicalRecord.create({
      patientId: req.patient._id, kind: 'test_result', title: name, forTests, recordDate: collectedAt, origin: 'shared_by_patient', sourceName: labName,
      files: parent.files, pageFrom: t.pageFrom ?? t.page_from, pageTo: t.pageTo ?? t.page_to, batchId: parent._id, aiSummary: t.summary,
      flagLabel: abnormal ? `${abnormal} ${values.some((v) => v.flag === 'low') && !values.some((v) => v.flag === 'high') ? 'low' : 'high'}` : 'Normal', flagTone: abnormal ? 'high' : 'ok',
      sharedWith, uploadedBy: req.user._id,
    });
    await M.LabResult.create({ patientId: req.patient._id, recordId: rec._id, testName: rec.title, labName, collectedAt, values, abnormalCount: abnormal, hasCritical: values.some((v) => v.flag === 'critical') });
    created.push(rec);
  }
  parent.deletedAt = new Date(); // replaced by the per-test records
  await parent.save();
  const fresh = sharedWith.filter((s) => !parent.sharedWith.some((p) => String(p.userId) === String(s.userId)));
  if (fresh.length) {
    await notify(fresh.map((s) => s.userId), { type: 'record_shared', title: `${req.patient.name} shared ${created.length === 1 ? 'a report' : `${created.length} reports`}`, screen: 'Patient-Profile', params: { patientId: req.patient._id } });
  }
  res.status(201).json(created);
});

r.post('/records/:id/share', async (req, res) => {
  const rec = await M.MedicalRecord.findOne({ _id: req.params.id, patientId: req.patient._id, deletedAt: null });
  if (!rec) throw notFound('Record');
  const ids = list(req.body.userIds).filter(isId);
  const fresh = ids.filter((id) => !rec.sharedWith.some((s) => String(s.userId) === id));
  rec.sharedWith = ids.map((userId) => rec.sharedWith.find((s) => String(s.userId) === userId) || { userId });
  await rec.save();
  if (fresh.length) {
    await notify(fresh, { type: 'record_shared', title: `${req.patient.name} shared ${rec.kind === 'prescription' ? 'a prescription' : 'a report'}`, screen: 'Patient-Profile', params: { patientId: req.patient._id } });
  }
  res.json(rec);
});

r.delete('/records/:id', async (req, res) => {
  await M.MedicalRecord.updateOne({ _id: req.params.id, patientId: req.patient._id }, { deletedAt: new Date() });
  res.json({ ok: true });
});

// ── Pharmacy ──
const cartOf = async (patientId) => (await M.Cart.findOne({ patientId })) || M.Cart.create({ patientId, items: [] });

async function cartView(cart, patient) {
  const courses = await M.MedicationCourse.find({ _id: { $in: cart.items.map((i) => i.courseId).filter(Boolean) } });
  const today = T.dayStart();
  // "Prescriptions attached": what can go with the order, and which cart medicines each one covers.
  const { prescriptions, uncovered } = await cartPrescriptions(patient, cart);
  return {
    prescriptions, uncovered,
    addresses: patient.addresses,
    ...cart.toJSON(),
    items: cart.items.map((i) => {
      const c = courses.find((x) => String(x._id) === String(i.courseId));
      const perDay = c ? (c.frequency === 'weekly' ? (dosesPerDay(c.dose) || 1) / 7 : dosesPerDay(c.dose)) : 0;
      const units = (c?.stockUnits || 0) + i.strips * (i.unitsPerStrip || 10);
      return { ...i.toJSON(), lastsTill: perDay ? T.addDays(today, Math.floor(units / perDay) - 1) : null };
    }),
    count: cart.items.length,
    patientAddress: patient.addresses.find((a) => a.isDefault) || patient.addresses[0] || null,
  };
}

r.get('/cart', async (req, res) => res.json(await cartView(await cartOf(req.patient._id), req.patient)));

// Med-AddToCart: pack option or a strip count.
r.post('/cart/items', async (req, res) => {
  const cart = await cartOf(req.patient._id);
  const course = req.body.courseId ? await M.MedicationCourse.findOne({ _id: req.body.courseId, patientId: req.patient._id }) : null;
  if (req.body.courseId && !course) throw notFound('Medicine');
  const name = course ? `${course.name}${course.strength ? ` ${course.strength}` : ''}` : req.body.name;
  if (!name) throw badRequest('Choose a medicine');
  let strips = Number(req.body.strips) || 1;
  const per = course ? (course.frequency === 'weekly' ? (dosesPerDay(course.dose) || 1) / 7 : dosesPerDay(course.dose) || 1) : 1;
  if (req.body.packOption === '1_month') strips = Math.ceil((30 * per) / 10);
  if (req.body.packOption === '3_months') strips = Math.ceil((90 * per) / 10);
  if (req.body.packOption === 'till_next_visit') {
    const next = await M.Appointment.findOne({ patientId: req.patient._id, startAt: { $gte: new Date() }, status: { $in: ['booked', 'confirmed'] } }).sort({ startAt: 1 });
    const days = next ? Math.ceil((next.startAt - Date.now()) / T.DAY_MS) + 3 : 30;
    strips = Math.max(1, Math.ceil((days * per - (course?.stockUnits || 0)) / 10));
  }
  strips = Math.min(99, Math.max(1, strips));
  const existing = cart.items.find((i) => (course && String(i.courseId) === String(course._id)) || i.name === name);
  if (existing) Object.assign(existing, { strips, packOption: req.body.packOption || 'custom' });
  else cart.items.push({ courseId: course?._id, medicineId: course?.medicineId, name, strength: course?.strength, prescriberName: course?.prescriberName, strips, packOption: req.body.packOption || 'custom' });
  await cart.save();
  res.status(201).json(await cartView(cart, req.patient));
});

r.patch('/cart/items/:itemId', async (req, res) => {
  const cart = await cartOf(req.patient._id);
  const item = cart.items.id(req.params.itemId);
  if (!item) throw notFound('Cart item');
  item.strips = Math.min(99, Math.max(1, Number(req.body.strips) || item.strips));
  await cart.save();
  res.json(await cartView(cart, req.patient));
});

r.delete('/cart/items/:itemId', async (req, res) => {
  const cart = await cartOf(req.patient._id);
  cart.items.pull(req.params.itemId);
  await cart.save();
  res.json(await cartView(cart, req.patient));
});

async function quote(cart, pharmacy) {
  const meds = await M.Medicine.find({ _id: { $in: cart.items.map((i) => i.medicineId).filter(Boolean) } });
  // Items without a catalog link (medicines the patient typed in): match by generic name.
  const byName = await M.Medicine.find({ genericName: { $in: cart.items.filter((i) => !i.medicineId).map((i) => new RegExp(`^${escapeRegex(String(i.name).replace(/\s+\d.*$/, '').trim())}$`, 'i')) } });
  let subtotal = 0;
  const lines = cart.items.map((i) => {
    const m = meds.find((x) => String(x._id) === String(i.medicineId))
      || (!i.medicineId && byName.find((x) => String(i.name).toLowerCase().startsWith(x.genericName.toLowerCase()))) || null;
    const mrp = m?.mrpPerStrip ?? null;
    const unitPrice = mrp != null ? Math.round(mrp * (1 - (pharmacy.discountPct || 0) / 100)) : null;
    const lineTotal = unitPrice != null ? unitPrice * i.strips : null;
    subtotal += lineTotal || 0;
    return { name: i.name, strength: i.strength, strips: i.strips, unitPrice, lineTotal, inStock: true };
  });
  const deliveryFee = pharmacy.type === 'online' && !(pharmacy.freeDeliveryAbove && subtotal >= pharmacy.freeDeliveryAbove) ? pharmacy.deliveryFee || 0 : 0;
  return { lines, subtotal, deliveryFee, total: subtotal + deliveryFee, priced: lines.every((l) => l.unitPrice != null) };
}

r.get('/pharmacies/quotes', async (req, res) => {
  const cart = await cartOf(req.patient._id);
  if (!cart.items.length) throw badRequest('Your cart is empty', 'CART_EMPTY');
  const mode = req.query.mode === 'pickup' ? 'pickup' : 'delivery';
  const pharmacies = await M.Pharmacy.find({ active: true, type: mode === 'delivery' ? 'online' : { $in: ['nearby', 'clinic'] } });
  const origin = req.patient.geo?.coordinates;
  const out = [];
  for (const ph of pharmacies) {
    out.push({ pharmacy: { id: ph._id, name: ph.name, type: ph.type, etaText: ph.deliveryEtaText, pickupEtaMin: ph.pickupEtaMin, km: haversineKm(origin, ph.geo?.coordinates) }, ...(await quote(cart, ph)) });
  }
  out.sort((a, b) => a.total - b.total);
  res.json({ mode, items: out, note: 'Final price depends on the pharmacy' });
});

/**
 * Prescriptions that can go with a medicine order: valid digital ones and
 * prescription photos uploaded in the last 6 months. covers: the cart
 * medicines each one lists. uncovered: cart medicines none of them list.
 */
async function cartPrescriptions(patient, cart) {
  const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const cartNames = cart.items.map((i) => i.name);
  const covers = (names) => cartNames.filter((c) => names.some((n) => {
    const a = norm(c).split(' ')[0];
    return a && norm(n).split(' ').includes(a);
  }));
  const [digital, uploaded] = await Promise.all([
    M.Prescription.find({ patientId: patient._id, validUntil: { $gte: new Date() } }, 'doctorName issuedAt items rxNumber').sort({ issuedAt: -1 }).limit(10),
    M.MedicalRecord.find({ patientId: patient._id, kind: 'prescription', deletedAt: null, origin: { $ne: 'from_doctor' }, recordDate: { $gte: T.addDays(new Date(), -183) } }, 'title sourceName extractedDoctor recordDate extractedMedicines files')
      .sort({ recordDate: -1 }).limit(10),
  ]);
  const prescriptions = [
    ...digital.map((p) => ({ id: p._id, kind: 'digital', doctorName: p.doctorName, issuedAt: p.issuedAt, covers: covers(p.items.map((i) => i.name)) })),
    ...uploaded.filter((r) => r.files?.length).map((r) => ({
      id: r._id, kind: 'uploaded', doctorName: r.extractedDoctor || r.sourceName || null, issuedAt: r.recordDate, title: r.title,
      covers: covers((r.extractedMedicines || []).map((m) => m.name)),
    })),
  ];
  const covered = new Set(prescriptions.flatMap((p) => p.covers));
  return { prescriptions, uncovered: cartNames.filter((n) => !covered.has(n)) };
}

r.post('/orders', async (req, res) => {
  const cart = await cartOf(req.patient._id);
  if (!cart.items.length) throw badRequest('Your cart is empty', 'CART_EMPTY');
  const pharmacy = await M.Pharmacy.findOne({ _id: req.body.pharmacyId, active: true });
  if (!pharmacy) throw notFound('Pharmacy');
  const mode = req.body.mode === 'pickup' ? 'pickup' : 'delivery';
  const q = await quote(cart, pharmacy);
  const address = req.patient.addresses.id(req.body.addressId) || req.patient.addresses.find((a) => a.isDefault) || req.patient.addresses[0];
  if (mode === 'delivery' && !address) throw badRequest('Add a delivery address first', 'ADDRESS_REQUIRED');
  // The prescriptions the patient kept ticked in the cart (all valid ones when the app doesn't say).
  const offered = (await cartPrescriptions(req.patient, cart)).prescriptions;
  const chosen = Array.isArray(req.body.attach) ? new Set(req.body.attach.map(String)) : null;
  const keep = offered.filter((p) => !chosen || chosen.has(String(p.id)));
  const prescriptionIds = keep.filter((p) => p.kind === 'digital').map((p) => p.id);
  const prescriptionRecordIds = keep.filter((p) => p.kind === 'uploaded').map((p) => p.id);
  const byName = new Map(cart.items.map((i) => [`${i.name}|${i.strength || ''}`, i]));
  const { randomToken, sha256 } = require('../lib/security');
  const pharmacyToken = randomToken(24);
  const order = await M.Order.create({
    pharmacyTokenHash: sha256(pharmacyToken),
    patientId: req.patient._id, pharmacyId: pharmacy._id, mode,
    items: q.lines.map((l) => {
      const c = byName.get(`${l.name}|${l.strength || ''}`);
      return { ...l, courseId: c?.courseId, unitsPerStrip: c?.unitsPerStrip || 10, unitPrice: l.unitPrice ?? undefined, lineTotal: l.lineTotal ?? undefined };
    }),
    prescriptionIds, prescriptionRecordIds, deliveryAddress: mode === 'delivery' ? pick(address, ['line', 'area', 'city', 'pincode']) : undefined,
    subtotal: q.subtotal, deliveryFee: q.deliveryFee, total: q.total, statusHistory: [{ status: 'placed', at: new Date() }],
    etaText: mode === 'delivery' ? pharmacy.deliveryEtaText : pharmacy.pickupEtaMin ? `Ready in ${pharmacy.pickupEtaMin} min` : undefined,
  });
  cart.items = [];
  await cart.save();
  // "Pay online now": the app opens Razorpay Checkout for it (POST /checkout);
  // otherwise cash on delivery / at the counter.
  const online = req.body.payOnline === true || req.body.payOnline === 'true';
  if (online) {
    order.pay = { ...(order.pay?.toObject?.() || {}), method: 'online', status: 'due' };
    await order.save();
  }
  const payUrl = null;
  await require('../services/orders').notifyPharmacy(order, pharmacy, req.patient, pharmacyToken).catch((err) => console.warn('[order]', err.message));
  res.status(201).json({
    ...order.toJSON(), pharmacyName: pharmacy.name, payUrl,
    payment: online ? 'online' : mode === 'delivery' ? 'cash_on_delivery' : 'pay_at_pharmacy',
  });
});

// Pay an order online later (or again, if the first link wasn't used).
r.post('/orders/:id/pay', async (req, res) => {
  const order = await M.Order.findOne({ _id: req.params.id, patientId: req.patient._id }).populate('pharmacyId', 'name');
  if (!order) throw notFound('Order');
  if (['delivered', 'picked_up'].includes(order.status) && order.pay?.method !== 'online') throw conflict('This order was already paid at the pharmacy', 'ALREADY_PAID');
  const url = await require('../services/payments').orderLink(order, req.patient, order.pharmacyId?.name);
  res.json({ url, amount: order.total });
});

r.post('/orders/:id/cancel', async (req, res) => {
  const order = await M.Order.findOne({ _id: req.params.id, patientId: req.patient._id });
  if (!order) throw notFound('Order');
  if (!['placed', 'confirmed'].includes(order.status)) throw conflict('This order is already being packed. Call the pharmacy to cancel it.', 'TOO_LATE');
  await require('../services/orders').setStatus(order, 'cancelled', { by: 'patient' });
  res.json(order);
});

r.get('/orders', async (req, res) => {
  res.json(await M.Order.find({ patientId: req.patient._id }).sort({ createdAt: -1 }).limit(50).populate('pharmacyId', 'name type'));
});

// ── Chat ──
r.get('/conversations', async (req, res) => {
  const convos = await M.Conversation.find({ patientId: req.patient._id, 'participants.userId': req.user._id }).sort({ 'lastMessage.at': -1 }).populate('practiceId', 'name');
  res.json(convos.map((c) => ({ id: c._id, type: c.type, practice: c.practiceId?.name, isUrgent: c.isUrgent, lastMessage: c.lastMessage, unread: c.participants.find((p) => String(p.userId) === String(req.user._id))?.unreadCount || 0 })));
});

// Open the chat with a doctor's clinic ("You can chat with the doctor once the visit is booked").
r.post('/conversations', async (req, res) => {
  const access = await M.CareTeamAccess.findOne({ patientId: req.patient._id, userId: req.body.doctorId, accessLevel: { $ne: 'not_shared' } });
  const prof = await M.DoctorProfile.findOne({ userId: req.body.doctorId }, 'chatSettings displayName');
  const who = prof?.chatSettings?.whoCanMessage || 'booked';
  if (who === 'nobody') throw conflict(`${prof?.displayName || 'This doctor'} isn't taking chat messages. Please call the clinic.`, 'CHAT_OFF');
  const booked = await M.Appointment.exists({ patientId: req.patient._id, doctorId: req.body.doctorId, status: { $nin: ['cancelled', 'rescheduled'] } });
  if (!access || (who === 'booked' && !booked)) throw conflict('You can chat with the doctor once a visit is booked', 'NO_VISIT');
  const dl = await M.DoctorLocation.findOne({ doctorId: req.body.doctorId, status: 'active' });
  const convo = await care.careConversation(req.patient._id, access.practiceId || dl.practiceId);
  await care.ensureParticipant(convo, req.user._id, 'patient');
  res.json(convo);
});

// Patient-Emergency: the doctors who can get an urgent message, with presence and clinic phone.
r.get('/urgent/doctors', async (req, res) => {
  const team = await M.CareTeamAccess.find({ patientId: req.patient._id, role: 'doctor', accessLevel: { $ne: 'not_shared' }, practiceId: { $ne: null } })
    .populate('userId', 'name').populate('practiceId', 'name');
  const ids = team.filter((c) => c.userId).map((c) => c.userId._id);
  const [profiles, places] = await Promise.all([
    M.DoctorProfile.find({ userId: { $in: ids } }, 'userId displayName gender specialtyKeys presence avgReplyMinutes'),
    M.DoctorLocation.find({ doctorId: { $in: ids }, status: 'active' }).populate('locationId', 'phone'),
  ]);
  const labels = new Map((await M.Specialty.find({ key: { $in: profiles.flatMap((x) => x.specialtyKeys) } }, 'key label')).map((s) => [s.key, s.label]));
  const order = { available: 0, in_clinic: 1, away: 2 };
  const items = await Promise.all(team.filter((c) => c.userId).map(async (c) => {
    const prof = profiles.find((x) => String(x.userId) === String(c.userId._id));
    const place = places.find((d) => String(d.doctorId) === String(c.userId._id) && String(d.practiceId) === String(c.practiceId?._id) && d.locationId?.phone)
      || places.find((d) => String(d.doctorId) === String(c.userId._id) && d.locationId?.phone);
    return {
      doctorId: c.userId._id, name: prof?.displayName || c.userId.name, gender: prof?.gender || null,
      specialty: prof ? labels.get(prof.specialtyKeys[0]) || null : null, clinic: c.practiceId?.name || null,
      ...(await require('../services/presence').presenceOf(c.userId._id)), clinicPhone: place?.locationId?.phone || null,
    };
  }));
  items.sort((a, b) => order[a.presence] - order[b.presence]);
  res.json({ items, call: '108' });
});

// Patient-Emergency: urgent chat with the chosen doctor.
r.post('/urgent', async (req, res) => {
  const access = await M.CareTeamAccess.findOne({ patientId: req.patient._id, userId: req.body.doctorId });
  if (!access?.practiceId) throw notFound('Doctor');
  const text = String(req.body.text || 'I need help urgently.').trim();
  const convo = await care.careConversation(req.patient._id, access.practiceId);
  await care.ensureParticipant(convo, req.user._id, 'patient');
  const msg = await care.postMessage(convo, { sender: req.user, senderType: 'patient', text, isUrgent: true });
  const alert = await care.raiseAlert({ practiceId: access.practiceId, patientId: req.patient._id, doctorId: access.userId, severity: 'emergency', kind: 'urgent_chat', detail: text, sourceModel: 'Message', sourceId: msg._id, conversationId: convo._id });
  res.status(201).json({ conversationId: convo._id, messageId: msg._id, alertId: alert._id, call: '108' });
});

// ── Ask MedPin AI ──
r.get('/ai/session', async (req, res) => {
  let s = await M.AiSession.findOne({ userId: req.user._id, ownerType: 'patient' }).sort({ lastAt: -1 });
  if (!s) s = await M.AiSession.create({ ownerType: 'patient', userId: req.user._id, patientId: req.patient._id, lastAt: new Date() });
  res.json({ session: s, messages: await M.AiMessage.find({ sessionId: s._id }).sort({ createdAt: 1 }).limit(100) });
});

r.post('/ai/ask', async (req, res) => {
  const text = String(req.body.text || '').trim();
  if (!text) throw badRequest('Ask a question', 'EMPTY_MESSAGE');
  let s = await M.AiSession.findOne({ userId: req.user._id, ownerType: 'patient' }).sort({ lastAt: -1 });
  if (!s) s = await M.AiSession.create({ ownerType: 'patient', userId: req.user._id, patientId: req.patient._id });
  const question = await M.AiMessage.create({ sessionId: s._id, role: 'user', text, inputMode: req.body.inputMode, voiceLanguage: req.body.voiceLanguage });
  const out = await assistant.patientAnswer(s, text, req.patient, { excludeId: question._id }).catch((err) => {
    console.warn('[ai]', err.message);
    return { text: "MedPin AI couldn't answer just now. Please try again, or message your doctor from the Doctors tab.", scripted: true };
  });
  const answer = await M.AiMessage.create({ sessionId: s._id, role: 'assistant', text: out.text, aiModel: out.model, latencyMs: out.latencyMs, payload: out.scripted ? { scripted: true } : undefined });
  s.lastAt = new Date();
  await s.save();
  // Emergency words always flag the answer, even when the AI is off.
  res.status(201).json({ question, answer, emergency: Boolean(out.emergency || assistant.isEmergencyText(text)), specialistKey: out.specialistKey || null });
});

// ── Feedback ──
r.post('/feedback', async (req, res) => {
  const rating = Number(req.body.rating);
  if (!(rating >= 1 && rating <= 5)) throw badRequest('Choose 1 to 5 stars');
  const link = await M.PatientEnrolment.findOne({ patientId: req.patient._id, practiceId: req.body.practiceId, status: 'linked' });
  if (!link) throw notFound('Clinic');
  const f = await M.Feedback.create({ practiceId: link.practiceId, patientId: req.patient._id, doctorId: req.body.doctorId, appointmentId: req.body.appointmentId, rating, category: req.body.category === 'app' ? 'app' : 'care', comment: req.body.comment });
  res.status(201).json(f);
});

// The patient's own summary (also what the AI sees).
r.get('/summary', async (req, res) => res.json(await patientSummary(req.patient)));

// Health score details: the parts it is made of, from the patient's own data.
r.get('/health-score', async (req, res) => {
  const out = await require('../services/health').refreshScore(req.patient);
  res.json({ value: out.value, weeklyDelta: out.weeklyDelta, parts: out.parts, note: 'Based on your medicines, readings, activity and reports. It is a guide, not a diagnosis.' });
});

// The full health summary in simple words (made once a day; ?fresh=true makes a new one).
r.get('/health-summary', async (req, res) => {
  const s = await require('../services/health').patientSummaryFor(req.patient, { fresh: req.query.fresh === 'true' });
  res.json({ body: s.body, focusItems: s.focusItems, generatedAt: s.generatedAt, byAi: Boolean(s.aiModel) });
});

module.exports = r;
module.exports.dailyLogUsed = dailyLogUsed;

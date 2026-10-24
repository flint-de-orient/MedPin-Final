// Patient summaries, medicine safety checks, issuing prescriptions and PDFs.
const rxpdf = require('./rxpdf');
const M = require('../models');
const T = require('../lib/time');
const { conflict, badRequest } = require('../lib/http');
const storage = require('./storage');

const ALLERGY_CLASSES = {
  sulfa: ['sulfonylurea', 'sulfonamide'],
  penicillin: ['penicillin', 'beta-lactam'],
  aspirin: ['nsaid', 'salicylate'],
  nsaid: ['nsaid'],
  statin: ['statin'],
};

// "1-0-1", with halves as printed on Indian prescriptions: "½-0-1", "1½-0-0".
const half = (n = 0) => { const w = Math.floor(n); return n - w >= 0.5 ? (w ? `${w}½` : '½') : `${w}`; };
const doseText = (d = {}) => `${half(d.morning || 0)}-${half(d.afternoon || 0)}-${half(d.night || 0)}`;
const dosesPerDay = (d = {}) => (d.morning || 0) + (d.afternoon || 0) + (d.night || 0);
/**
 * Tablets used per day, for "runs out in N days": weekly = a seventh of a dose day; "when
 * needed" has no daily use (no run-out date, no refill nag).
 */
const stockPerDay = (c) => (c.frequency === 'as_needed' ? 0 : c.frequency === 'weekly' ? (dosesPerDay(c.dose) || 1) / 7 : dosesPerDay(c.dose));
const durationDays = ({ value, unit } = {}) => {
  if (!value || unit === 'ongoing') return null;
  return value * ({ days: 1, weeks: 7, months: 30 }[unit] || 1);
};

/** Quantity for a prescription line: doses per day × days (weekly = once per week). */
function quantityFor(item) {
  const days = durationDays(item.duration);
  if (!days) return undefined;
  if (item.frequency === 'weekly') return Math.ceil(days / 7);
  return dosesPerDay(item.dose) * days;
}

/** Allergy clashes and strengths that aren't in the catalog. */
async function checkItems(patient, items) {
  const names = [...new Set(items.map((i) => i.name))];
  const meds = await M.Medicine.find({ genericName: { $in: names.map((n) => new RegExp(`^${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i')) } });
  const byName = new Map(meds.map((m) => [m.genericName.toLowerCase(), m]));
  return items.map((item) => {
    const med = byName.get(String(item.name).toLowerCase());
    const warnings = [];
    if (med) {
      for (const allergy of patient.allergies || []) {
        const key = Object.keys(ALLERGY_CLASSES).find((k) => allergy.allergen.toLowerCase().includes(k));
        const classes = [...(key ? ALLERGY_CLASSES[key] : []), allergy.drugClass].filter(Boolean).map((c) => c.toLowerCase());
        if (med.drugClass && classes.includes(med.drugClass.toLowerCase())) {
          warnings.push({ type: 'allergy', text: `${allergy.allergen} allergy · ${med.drugClass}` });
        }
      }
      const strength = parseFloat(item.strength);
      if (!Number.isNaN(strength) && med.strengths.length && !med.strengths.some((s) => s.value === strength)) {
        warnings.push({
          type: 'strength',
          text: `Catalog strengths for ${med.genericName}: ${med.strengths.map((s) => s.value).join(', ')} ${med.strengths[0].unit}. Check the strength.`,
        });
      }
    }
    return { name: item.name, strength: item.strength, medicineId: med?._id, warnings };
  });
}

/**
 * Everything a doctor sees at the top of a patient's profile / consultation.
 * With [acc] (services/access.js) only what that viewer may see is included;
 * without it (the patient's own app) everything is.
 */
async function patientSummary(patient, practiceId, acc) {
  const inPractice = practiceId ? { practiceId } : {};
  const since = T.addDays(new Date(), -180);
  const [vitalsQ, labQ] = acc ? [acc.vitalsFilter(), await acc.labFilter()] : [{}, {}];
  const [vitals, allCourses, labs, nextVisit, lastVisit, openAlerts, ai] = await Promise.all([
    M.Vitals.findOne({ patientId: patient._id, ...vitalsQ }).sort({ recordedAt: -1 }),
    M.MedicationCourse.find({ patientId: patient._id, status: 'active' }).sort({ startDate: -1 }),
    M.LabResult.find({ patientId: patient._id, ...labQ, collectedAt: { $gte: since }, abnormalCount: { $gt: 0 } }).sort({ collectedAt: -1 }).limit(10),
    M.Appointment.findOne({ patientId: patient._id, ...inPractice, startAt: { $gte: T.dayStart() }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } }).sort({ startAt: 1 }),
    M.Appointment.findOne({ patientId: patient._id, ...inPractice, status: 'completed' }).sort({ completedAt: -1 }),
    M.Alert.countDocuments({ patientId: patient._id, ...inPractice, status: { $ne: 'resolved' } }),
    M.AiSummary.findOne({ patientId: patient._id, audience: 'doctor', ...inPractice }).sort({ generatedAt: -1 }),
  ]);
  // A course past its end date is finished (the daily job marks it; until then it isn't "current").
  const today = T.dayStart();
  const running = allCourses.filter((c) => !c.endDate || c.endDate >= today);
  const courses = acc ? running.filter((c) => acc.courseVisible(c)) : running;
  const bmi = patient.heightCm && patient.weightKg ? +(patient.weightKg / (patient.heightCm / 100) ** 2).toFixed(1) : null;
  return {
    patient: {
      id: patient._id, name: patient.name, phone: patient.phone, gender: patient.gender, age: T.ageFrom(patient),
      bloodGroup: patient.bloodGroup, heightCm: patient.heightCm, weightKg: patient.weightKg, bmi,
      riskLevel: patient.riskLevel, healthScore: await require('./health').currentScore(patient).catch(() => patient.healthScore), hasApp: Boolean(patient.userId),
      photo: patient.userId ? (await require('./photos').photosFor([patient.userId])).get(String(patient.userId)) || null : null,
    },
    conditions: patient.conditions,
    allergies: patient.allergies,
    latestVitals: vitals,
    currentMedicines: courses.map((c) => ({
      id: c._id, name: c.name, strength: c.strength, pattern: doseText(c.dose), frequency: c.frequency,
      prescriber: c.prescriberName, doctorId: c.doctorId, since: c.startDate, endDate: c.endDate,
    })),
    abnormalResults: labs.flatMap((l) =>
      l.values.filter((v) => v.flag !== 'normal').map((v) => ({
        test: l.testName, analyte: v.analyte, value: v.value ?? v.valueText, unit: v.unit, flag: v.flag, collectedAt: l.collectedAt, labResultId: l._id,
      })),
    ),
    nextVisit,
    lastVisitAt: lastVisit?.completedAt || null,
    openAlerts,
    aiSummary: ai ? { body: ai.body, contextNote: ai.contextNote, generatedAt: ai.generatedAt } : null,
  };
}

const VALIDITY_DAYS = { '15_days': 15, '1_month': 30, '3_months': 90 };
const FOLLOW_UP_DAYS = { '1_week': 7, '2_weeks': 14, '1_month': 28, '3_months': 91 };

/** Turns a draft consultation into an issued prescription, medicine courses and a follow-up. */
/** What a consultation's prescription holds (shared by Generate and Preview, so they match). */
function prescriptionFields(consult, now = new Date()) {
  const validDays = VALIDITY_DAYS[consult.validity?.preset] || 30;
  const validUntil = consult.validity?.validUntil || T.addDays(T.dayStart(now), validDays);
  let followUpDate = null;
  if (consult.followUp?.enabled) {
    followUpDate = consult.followUp.date || T.addDays(T.dayStart(now), FOLLOW_UP_DAYS[consult.followUp.preset] || 14);
  }
  const items = consult.medications.map((m) => {
    const plain = m.toObject ? m.toObject() : m;
    return { ...plain, quantity: plain.quantity ?? quantityFor(plain) };
  });
  return {
    practiceId: consult.practiceId,
    locationId: consult.locationId,
    doctorId: consult.doctorId,
    patientId: consult.patientId,
    consultationId: consult._id,
    issuedAt: now,
    validUntil,
    diagnosisSummary: consult.diagnoses.map((d) => d.name).join(', '),
    items,
    tests: consult.labOrders.filter((t) => t.selected).map((t) => t.testName),
    advice: [
      ...consult.advice.items.filter((a) => a.included).map((a) => a.text),
      consult.advice.freeText,
    ].filter(Boolean).join('\n'),
    followUpDate,
  };
}

/** Same medicine, whatever the case or spacing ("Metformin" = "metformin "). */
const sameName = (names) => ({ $in: names.map((n) => new RegExp(`^\\s*${String(n).trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'i')) });

async function issueConsultation(consult, doctorUser) {
  if (consult.status !== 'draft') throw conflict('This prescription was already generated', 'ALREADY_ISSUED');
  if (!consult.chiefComplaint && !consult.diagnoses.length) throw badRequest('Add a complaint or diagnosis first', 'EMPTY_CONSULTATION');
  const doctor = await M.DoctorProfile.findOne({ userId: consult.doctorId });
  if (!doctor?.signature?.key) {
    throw conflict('Add your digital signature first — it is printed on every prescription', 'SIGNATURE_REQUIRED');
  }
  // Generated once: a second tap (or a second device) while this one runs is refused, so
  // the patient never gets two prescriptions and two sets of alarms. A Generate that
  // crashed half-way frees the draft after 2 minutes.
  const claimed = await M.Consultation.updateOne(
    { _id: consult._id, status: 'draft', $or: [{ issuingAt: null }, { issuingAt: { $lt: new Date(Date.now() - 120e3) } }] },
    { issuingAt: new Date() },
  );
  if (!claimed.modifiedCount) throw conflict('This prescription is already being generated', 'ALREADY_ISSUED');
  try {
    return await issueClaimed(consult, doctorUser, doctor);
  } catch (err) {
    await M.Consultation.updateOne({ _id: consult._id, status: 'draft' }, { $unset: { issuingAt: 1 } });
    throw err;
  }
}

async function issueClaimed(consult, doctorUser, doctor) {
  const patient = await M.Patient.findById(consult.patientId);
  const now = new Date();
  const fields = prescriptionFields(consult, now);
  const { followUpDate } = fields;

  const rx = await M.Prescription.create({
    ...fields,
    doctorName: doctor?.displayName || doctorUser.name,
    rxNumber: await M.Counter.next(`rx:${consult.practiceId}`),
  });

  // A line marked "stopped" tells the patient to stop that medicine: no new course for it.
  const taking = rx.items.filter((item) => item.change !== 'stopped');
  const created = await M.MedicationCourse.insertMany(
    taking.map((item) => ({
      patientId: consult.patientId,
      prescriptionId: rx._id,
      rxItemId: item._id,
      doctorId: consult.doctorId,
      prescriberName: rx.doctorName,
      medicineId: item.medicineId,
      name: item.name,
      strength: item.strength,
      dose: item.dose,
      frequency: item.frequency,
      weekday: item.weekday,
      foodRelation: item.foodRelation,
      instructions: item.instructions,
      startDate: T.dayStart(now),
      endDate: durationDays(item.duration) ? T.addDays(T.dayStart(now), durationDays(item.duration) - 1) : null,
    })),
  );
  // A new, changed or continued medicine replaces the same running medicine — from this
  // doctor or another (taking both would double the dose). The other doctor is told.
  const byName = new Map(created.map((c) => [c.name.trim().toLowerCase(), c]));
  const replaced = taking.length
    ? await M.MedicationCourse.find({ patientId: consult.patientId, name: sameName(taking.map((i) => i.name)), status: 'active', prescriptionId: { $ne: rx._id } })
    : [];
  for (const old of replaced) {
    const by = byName.get(old.name.trim().toLowerCase());
    await M.MedicationCourse.updateOne({ _id: old._id }, {
      status: 'stopped', stoppedAt: now, replacedById: by?._id,
      stoppedReason: String(old.doctorId) === String(consult.doctorId) ? 'Replaced by a new prescription' : `Replaced by ${rx.doctorName}'s prescription`,
    });
  }
  const stopped = consult.medications.filter((m) => m.change === 'stopped').map((m) => m.name);
  if (stopped.length) {
    await M.MedicationCourse.updateMany(
      { patientId: consult.patientId, name: sameName(stopped), status: 'active', prescriptionId: { $ne: rx._id } },
      { status: 'stopped', stoppedAt: now, stoppedReason: `Stopped by ${rx.doctorName}` },
    );
  }
  const otherDoctors = new Map();
  for (const old of replaced.filter((o) => o.doctorId && String(o.doctorId) !== String(consult.doctorId))) {
    otherDoctors.set(String(old.doctorId), [...(otherDoctors.get(String(old.doctorId)) || []), old.name]);
  }
  for (const [doctorId, meds] of otherDoctors) {
    await require('./notify').notify([doctorId], {
      type: 'medicine_replaced', push: false, practiceId: consult.practiceId,
      title: `${rx.doctorName} changed ${patient?.name || 'a patient'}'s ${meds.join(', ')}`,
      body: 'Their new prescription replaces yours for this medicine.', screen: 'PP-Summary', params: { patientId: consult.patientId },
    }).catch((err) => console.warn('[replaced notice]', err.message));
  }

  if (followUpDate) {
    await M.FollowUp.create({
      practiceId: consult.practiceId, patientId: consult.patientId, doctorId: consult.doctorId,
      locationId: consult.locationId, consultationId: consult._id, advisedOn: now,
      adviceText: consult.advice.freeText, dueDate: followUpDate, remindPatient: consult.followUp.remindPatient,
    });
  }
  await M.MedicalRecord.create({
    patientId: consult.patientId, kind: 'prescription', title: rx.diagnosisSummary || 'Prescription',
    recordDate: now, origin: 'from_doctor', sourceName: rx.doctorName, practiceId: consult.practiceId,
    doctorId: consult.doctorId, prescriptionId: rx._id, flagLabel: 'New', flagTone: 'new',
  });

  // What it prints is fixed now (a later redraw prints the same signature, letterhead and address).
  const [loc, practice] = await Promise.all([rxLocation(rx, consult), M.Practice.findById(rx.practiceId, 'logo name')]);
  rx.printed = printedSnapshot({ doctor, location: loc, practice });
  rx.markModified('printed');
  // PDF is generated now so it can be downloaded or sent straight away.
  await buildPrescriptionPdf(rx, { consult, patient, doctor });

  consult.status = 'issued';
  consult.prescriptionId = rx._id;
  consult.completedAt = now;
  consult.durationSec = Math.round((now - consult.startedAt) / 1000);
  consult.issuingAt = undefined;
  await consult.save();
  // Today's doses exist at once (Home shows them), and the patient's phone re-schedules
  // its alarms now (bulk writes don't run the course's save hook).
  if (patient) await require('./care').ensureDoses(patient, now, T.addDays(now, 1)).catch((err) => console.warn('[doses]', err.message));
  require('./reminders').remindersChanged(consult.patientId);
  return rx;
}

/**
 * The clinic details printed on a prescription (logo, signature, letterhead,
 * doctor's name and registration, clinic address and hours). When any of
 * them changes, prescriptions are drawn again the next time they're opened.
 */
/**
 * Where a prescription was written (its letterhead and logo): the prescription's
 * location, else the consultation's or visit's, else the doctor's clinic location
 * (one with a letterhead logo first) — so a consult started without a visit
 * still prints the clinic's logo.
 */
async function rxLocation(rx, consult) {
  if (rx.locationId) return M.Location.findById(rx.locationId);
  consult = consult !== undefined ? consult : rx.consultationId ? await M.Consultation.findById(rx.consultationId, 'locationId appointmentId') : null;
  let id = consult?.locationId;
  if (!id && consult?.appointmentId) id = (await M.Appointment.findById(consult.appointmentId, 'locationId'))?.locationId;
  if (id) return M.Location.findById(id);
  const mine = await M.DoctorLocation.find({ doctorId: rx.doctorId, practiceId: rx.practiceId }).distinct('locationId');
  const options = await M.Location.find({ practiceId: rx.practiceId, ...(mine.length ? { _id: { $in: mine } } : {}), status: { $ne: 'inactive' } }).sort({ createdAt: 1 });
  return options.find((l) => l.letterhead?.logo?.key) || options[0] || null;
}

const plain = (x) => (x?.toObject ? x.toObject() : x || null);

/** What an issued prescription prints, fixed at issue (see Prescription.printed). */
function printedSnapshot({ doctor, location, practice }) {
  const d = plain(doctor) || {};
  const l = plain(location);
  return {
    signatureKey: d.signature?.key || null,
    logoKey: l?.letterhead?.logo?.key || practice?.logo?.key || null,
    practiceName: practice?.name || null,
    doctor: {
      displayName: d.displayName, degreesSummary: d.degreesSummary, headline: d.headline, hprId: d.hprId,
      qualifications: (d.qualifications || []).map((q) => ({ name: q.name, institution: q.institution, year: q.year })),
      registration: d.registration ? { number: d.registration.number, council: d.registration.council, councilShort: d.registration.councilShort } : null,
    },
    location: l ? {
      _id: l._id, name: l.name, address: l.address, area: l.area, city: l.city, pincode: l.pincode, phone: l.phone, patientPhone: l.patientPhone,
      hfrId: l.hfrId, weeklyHours: l.weeklyHours, letterhead: l.letterhead ? { tagline: l.letterhead.tagline, doctorNamePrinted: l.letterhead.doctorNamePrinted, registrationNo: l.letterhead.registrationNo } : null,
    } : null,
  };
}

/** The doctor, location and images to print: the issue-time snapshot when there is one. */
function fromSnapshot(rx, { doctor, location, practice }) {
  const p = rx.printed;
  if (!p) return { doctor, location, practice, signatureKey: doctor?.signature?.key, logoKey: location?.letterhead?.logo?.key || practice?.logo?.key };
  return {
    doctor: { ...p.doctor, signature: p.signatureKey ? { key: p.signatureKey } : null },
    location: p.location,
    practice: { name: p.practiceName },
    signatureKey: p.signatureKey,
    logoKey: p.logoKey,
  };
}

async function pdfInputs(rx, { doctor, location, practice } = {}) {
  // Issued with a snapshot: drawn from it, so nothing changed later redraws it.
  if (rx.printed) return require('crypto').createHash('sha1').update(JSON.stringify(rx.printed)).digest('hex');
  doctor = doctor || (await M.DoctorProfile.findOne({ userId: rx.doctorId }, 'signature displayName qualifications degreesSummary registration hprId headline'));
  location = location !== undefined ? location : await rxLocation(rx);
  practice = practice || (await M.Practice.findById(rx.practiceId, 'logo name'));
  const lh = location?.letterhead || {};
  const key = JSON.stringify([
    doctor?.signature?.key, lh.logo?.key || practice?.logo?.key, lh.tagline, lh.doctorNamePrinted, lh.registrationNo,
    doctor?.displayName, doctor?.degreesSummary, (doctor?.qualifications || []).map((q) => q.name), doctor?.registration?.number,
    doctor?.registration?.council, doctor?.hprId, doctor?.headline, location?.name, location?.address, location?.area, location?.city,
    location?.pincode, location?.phone, location?.hfrId, JSON.stringify(location?.weeklyHours || []), practice?.name,
  ]);
  return require('crypto').createHash('sha1').update(key).digest('hex');
}

/**
 * Draws the prescription PDF (services/rxpdf.js) from the consultation and
 * saves it on [rx]. Already-loaded records can be passed in.
 */
async function buildPrescriptionPdf(rx, { consult, patient, doctor, lang = 'en', tr = null } = {}) {
  consult = consult || (rx.consultationId ? await M.Consultation.findById(rx.consultationId) : null);
  patient = patient || (await M.Patient.findById(rx.patientId));
  doctor = doctor || (await M.DoctorProfile.findOne({ userId: rx.doctorId }));
  const vitals = consult?.printVitalsOnRx && consult.vitalsId ? await M.Vitals.findById(consult.vitalsId) : null;
  const live = rx.printed ? {} : { location: await rxLocation(rx, consult), practice: await M.Practice.findById(rx.practiceId, 'logo name') };
  // An issued prescription prints what it was issued with (its snapshot), not today's details.
  const use = fromSnapshot(rx, { doctor, ...live });
  const location = use.location;
  const practice = use.practice;
  const appt = consult?.appointmentId ? await M.Appointment.findById(consult.appointmentId, 'mode') : null;
  const image = async (key) => (key ? storage.read(key).catch(() => null) : null);
  const [signature, logo] = await Promise.all([image(use.signatureKey), image(use.logoKey)]);
  const { buffer, pages } = await rxpdf.renderPrescription({
    rx, patient, doctor: use.doctor, location, vitals, complaint: consult?.chiefComplaint, signature, logo, practiceName: practice?.name, mode: appt?.mode, lang, tr,
  });
  const suffix = { bn: ' (বাংলা)', hi: ' (हिन्दी)' }[lang] || '';
  const name = `Prescription ${rxpdf.rxNo(rx)} · ${patient?.name || 'Patient'} · ${rxpdf.fmtDate(rx.issuedAt)}${suffix}.pdf`.replace(/[\/:*?"<>|]/g, '');
  const file = await storage.save(buffer, { folder: 'prescriptions', name, mimeType: 'application/pdf', pages });
  if (lang !== 'en') {
    rx.localized = { ...(rx.localized || {}), [lang]: { file, version: rxpdf.PDF_VERSION, inputs: await pdfInputs(rx, { doctor, location: live.location ?? location, practice: live.practice ?? practice }), text: tr } };
    rx.markModified('localized');
    await rx.save();
    return rx;
  }
  rx.file = file;
  rx.pdfVersion = rxpdf.PDF_VERSION;
  rx.pdfInputs = await pdfInputs(rx, { doctor, location: live.location ?? location, practice: live.practice ?? practice });
  await rx.save();
  return rx;
}

/**
 * Draws a digital prescription again when its layout is older or the clinic
 * changed what's printed on it (a new logo, signature or letterhead).
 */
async function ensurePrescriptionPdf(rx) {
  if (rx.kind !== 'digital' || !rx.consultationId) return rx;
  // Issued before snapshots were kept: its PDF is the record of what was issued — never redrawn
  // with today's signature or address (only drawn again if the file is missing).
  if (!rx.printed && rx.file?.key) return rx;
  const fresh = rx.file?.key && (rx.pdfVersion || 1) >= rxpdf.PDF_VERSION && rx.pdfInputs === (await pdfInputs(rx));
  if (fresh) return rx;
  return buildPrescriptionPdf(rx);
}

/**
 * "Preview": the draft as the prescription PDF Generate would make — same
 * layout, letterhead, logo and signature — marked "Draft" and watermarked
 * PREVIEW · NOT ISSUED, with no verification QR. Nothing is issued or numbered.
 * Returns the stored file (a fresh one each time).
 */
async function previewPrescriptionPdf(consult, doctorUser) {
  const rx = { ...prescriptionFields(consult), _id: null, rxNumber: null, kind: 'digital' };
  const [patient, doctor] = await Promise.all([M.Patient.findById(consult.patientId), M.DoctorProfile.findOne({ userId: consult.doctorId })]);
  rx.doctorName = doctor?.displayName || doctorUser?.name;
  const vitals = consult.printVitalsOnRx && consult.vitalsId ? await M.Vitals.findById(consult.vitalsId) : null;
  const location = await rxLocation(rx, consult);
  const practice = await M.Practice.findById(consult.practiceId, 'logo name');
  const appt = consult.appointmentId ? await M.Appointment.findById(consult.appointmentId, 'mode') : null;
  const image = async (file) => (file?.key ? storage.read(file.key).catch(() => null) : null);
  const [signature, logo] = await Promise.all([image(doctor?.signature), image(location?.letterhead?.logo || practice?.logo)]);
  const { buffer, pages } = await rxpdf.renderPrescription({
    rx, patient, doctor, location, vitals, complaint: consult.chiefComplaint, signature, logo, practiceName: practice?.name, mode: appt?.mode, preview: true,
  });
  const name = `Prescription preview · ${patient?.name || 'Patient'}.pdf`.replace(/[\/:*?"<>|]/g, '');
  return storage.save(buffer, { folder: 'previews', name, mimeType: 'application/pdf', pages });
}

/**
 * The patient's copy in [lang] ('bn' / 'hi'; 'en' = the usual PDF). Returns the
 * file. Drawn again when the layout, the clinic's details or the doctor's
 * wording change; the translation is reused while the wording is the same.
 */
async function localizedPrescriptionPdf(rx, lang) {
  if (!['bn', 'hi'].includes(lang)) return (await ensurePrescriptionPdf(rx)).file;
  if (rx.kind !== 'digital' || !rx.consultationId) return (await ensurePrescriptionPdf(rx)).file;
  const consult = await M.Consultation.findById(rx.consultationId);
  const tr = await require('./rxlang').freeText(rx, consult?.chiefComplaint, lang);
  const have = rx.localized?.[lang];
  const fresh = have?.file?.key && have.version === rxpdf.PDF_VERSION && have.inputs === (await pdfInputs(rx))
    && have.text?.hash === tr.hash && Boolean(have.text?.translated) === Boolean(tr.translated);
  if (fresh) return have.file;
  await buildPrescriptionPdf(rx, { consult, lang, tr });
  return rx.localized[lang].file;
}

module.exports = { stockPerDay, checkItems, patientSummary, issueConsultation, buildPrescriptionPdf, ensurePrescriptionPdf, localizedPrescriptionPdf, previewPrescriptionPdf, doseText, dosesPerDay, durationDays, quantityFor };

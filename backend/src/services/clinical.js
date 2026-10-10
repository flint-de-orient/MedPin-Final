// Patient summaries, medicine safety checks, issuing prescriptions and PDFs.
const PDFDocument = require('pdfkit');
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

const doseText = (d = {}) => `${d.morning || 0}-${d.afternoon || 0}-${d.night || 0}`;
const dosesPerDay = (d = {}) => (d.morning || 0) + (d.afternoon || 0) + (d.night || 0);
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
  const courses = acc ? allCourses.filter((c) => acc.courseVisible(c)) : allCourses;
  const bmi = patient.heightCm && patient.weightKg ? +(patient.weightKg / (patient.heightCm / 100) ** 2).toFixed(1) : null;
  return {
    patient: {
      id: patient._id, name: patient.name, phone: patient.phone, gender: patient.gender, age: T.ageFrom(patient),
      bloodGroup: patient.bloodGroup, heightCm: patient.heightCm, weightKg: patient.weightKg, bmi,
      riskLevel: patient.riskLevel, healthScore: patient.healthScore, hasApp: Boolean(patient.userId),
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
async function issueConsultation(consult, doctorUser) {
  if (consult.status !== 'draft') throw conflict('This prescription was already generated', 'ALREADY_ISSUED');
  if (!consult.chiefComplaint && !consult.diagnoses.length) throw badRequest('Add a complaint or diagnosis first', 'EMPTY_CONSULTATION');
  const patient = await M.Patient.findById(consult.patientId);
  const now = new Date();
  const validDays = VALIDITY_DAYS[consult.validity?.preset] || 30;
  const validUntil = consult.validity?.validUntil || T.addDays(T.dayStart(now), validDays);

  let followUpDate = null;
  if (consult.followUp?.enabled) {
    followUpDate = consult.followUp.date || T.addDays(T.dayStart(now), FOLLOW_UP_DAYS[consult.followUp.preset] || 14);
  }
  const items = consult.medications.map((m) => {
    const plain = m.toObject();
    return { ...plain, quantity: plain.quantity ?? quantityFor(plain) };
  });
  const doctor = await M.DoctorProfile.findOne({ userId: consult.doctorId });

  const rx = await M.Prescription.create({
    practiceId: consult.practiceId,
    locationId: consult.locationId,
    doctorId: consult.doctorId,
    doctorName: doctor?.displayName || doctorUser.name,
    patientId: consult.patientId,
    consultationId: consult._id,
    rxNumber: await M.Counter.next(`rx:${consult.practiceId}`),
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
  });

  await M.MedicationCourse.insertMany(
    rx.items.map((item) => ({
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
  // A changed/continued medicine replaces the same running medicine from this doctor.
  const names = rx.items.map((i) => i.name);
  await M.MedicationCourse.updateMany(
    { patientId: consult.patientId, doctorId: consult.doctorId, name: { $in: names }, status: 'active', prescriptionId: { $ne: rx._id } },
    { status: 'stopped', stoppedAt: now },
  );
  const stopped = consult.medications.filter((m) => m.change === 'stopped').map((m) => m.name);
  if (stopped.length) {
    await M.MedicationCourse.updateMany({ patientId: consult.patientId, name: { $in: stopped }, status: 'active' }, { status: 'stopped', stoppedAt: now });
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

  // PDF is generated now so it can be downloaded or sent straight away.
  const vitals = consult.printVitalsOnRx && consult.vitalsId ? await M.Vitals.findById(consult.vitalsId) : null;
  const location = consult.locationId ? await M.Location.findById(consult.locationId) : null;
  const pdf = await renderPrescriptionPdf({ rx, patient, doctor, location, vitals, complaint: consult.chiefComplaint });
  rx.file = await storage.save(pdf, { folder: 'prescriptions', name: `Rx-${String(rx.rxNumber).padStart(4, '0')}.pdf`, mimeType: 'application/pdf', pages: 1 });
  await rx.save();

  consult.status = 'issued';
  consult.prescriptionId = rx._id;
  consult.completedAt = now;
  consult.durationSec = Math.round((now - consult.startedAt) / 1000);
  await consult.save();
  return rx;
}

function renderPrescriptionPdf({ rx, patient, doctor, location, vitals, complaint }) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 48 });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const lh = location?.letterhead || {};
    doc.fontSize(18).text(lh.doctorNamePrinted || rx.doctorName || 'Doctor');
    if (lh.tagline) doc.fontSize(10).fillColor('#555').text(lh.tagline);
    const reg = lh.registrationNo || (doctor?.registration?.number && `${doctor.registration.councilShort || ''} ${doctor.registration.number}`);
    if (reg) doc.fontSize(10).text(`Reg. ${reg}`);
    if (location) doc.text(`${location.name}${location.address ? ` · ${location.address}` : ''}`);
    doc.fillColor('#000').moveDown();
    doc.fontSize(11).text(`Rx ${String(rx.rxNumber).padStart(4, '0')}   ·   ${T.dayKey(rx.issuedAt)}`);
    doc.text(`Patient: ${patient.name}   ${T.ageFrom(patient) ?? ''}${patient.gender ? ` ${patient.gender[0].toUpperCase()}` : ''}   ·   +91 ${patient.phone}`);
    doc.moveDown(0.5);
    if (complaint) doc.text(`Complaint: ${complaint}`);
    if (vitals) {
      const parts = [
        vitals.bpSystolic && `BP ${vitals.bpSystolic}/${vitals.bpDiastolic} mmHg`,
        vitals.pulse && `Pulse ${vitals.pulse}`,
        vitals.spo2 && `SpO2 ${vitals.spo2}%`,
        vitals.weightKg && `Weight ${vitals.weightKg} kg`,
        vitals.bloodSugar && `Sugar ${vitals.bloodSugar} mg/dL`,
      ].filter(Boolean);
      if (parts.length) doc.text(`Vitals: ${parts.join(' · ')}`);
    }
    if (rx.diagnosisSummary) doc.text(`Diagnosis: ${rx.diagnosisSummary}`);
    doc.moveDown().fontSize(13).text('Medicines');
    doc.fontSize(11);
    rx.items.forEach((item, i) => {
      const when = item.frequency === 'weekly' ? `Once a week${item.weekday ? ` · ${item.weekday}` : ''}` : doseText(item.dose);
      const food = item.foodRelation ? ` · ${item.foodRelation.replace('_', ' ')}` : '';
      const dur = item.duration?.value ? ` · ${item.duration.value} ${item.duration.unit}` : item.duration?.unit === 'ongoing' ? ' · ongoing' : '';
      doc.text(`${i + 1}. ${item.name} ${item.strength || ''} — ${when}${food}${dur}${item.quantity ? ` (${item.quantity})` : ''}`);
    });
    if (rx.tests.length) doc.moveDown().fontSize(13).text('Tests').fontSize(11).text(rx.tests.join(', '));
    if (rx.advice) doc.moveDown().fontSize(13).text('Advice').fontSize(11).text(rx.advice);
    if (rx.followUpDate) doc.moveDown().text(`Follow-up: ${T.dayKey(rx.followUpDate)}`);
    doc.moveDown().text(`Valid till ${T.dayKey(rx.validUntil)}`);
    doc.moveDown(2).fontSize(9).fillColor('#777').text('Generated by MedPin. Digitally signed by the doctor.');
    doc.end();
  });
}

module.exports = { checkItems, patientSummary, issueConsultation, renderPrescriptionPdf, doseText, dosesPerDay, durationDays, quantityFor };

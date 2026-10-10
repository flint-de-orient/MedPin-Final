// The patient's health score (0–100) and their plain-language health summary.
//
// The score is a weighted mix of what MedPin knows, using only the parts that
// have data: medicines taken (14 days), blood pressure and fasting sugar
// (latest reading), activity and logging (7 days), and lab results (90 days).
// It is a habit-and-control indicator for the patient, not a diagnosis.
const M = require('../models');
const T = require('../lib/time');

const clamp = (x) => Math.max(0, Math.min(100, Math.round(x)));

function bpScore(sys, dia) {
  if (sys == null || dia == null) return null;
  if (sys < 90 || dia < 60) return 60;
  if (sys < 130 && dia < 85) return 100;
  if (sys < 140 && dia < 90) return 80;
  if (sys < 160 && dia < 100) return 55;
  return 25;
}

function sugarScore(fasting) {
  if (fasting == null) return null;
  if (fasting < 70) return 50;
  if (fasting <= 110) return 100;
  if (fasting <= 130) return 80;
  if (fasting <= 180) return 55;
  return 25;
}

/** The score as of [at] with its parts (each 0–100, with a weight and a line for the patient). */
async function scoreAt(patient, at = new Date()) {
  const day = T.dayStart(at);
  const d14 = T.addDays(day, -13);
  const d7 = T.addDays(day, -6);
  const d90 = T.addDays(day, -89);
  const [doses, vitals, sugar, logs, labs] = await Promise.all([
    M.DoseLog.find({ patientId: patient._id, scheduledAt: { $gte: d14, $lte: at } }, 'status scheduledAt'),
    M.Vitals.findOne({ patientId: patient._id, recordedAt: { $lte: at }, bpSystolic: { $ne: null } }).sort({ recordedAt: -1 }),
    M.Vitals.findOne({ patientId: patient._id, recordedAt: { $lte: at }, sugarType: 'fasting', bloodSugar: { $ne: null } }).sort({ recordedAt: -1 }),
    M.HealthLog.find({ patientId: patient._id, loggedAt: { $gte: d7, $lte: at } }, 'type steps durationMin loggedAt'),
    M.LabResult.find({ patientId: patient._id, collectedAt: { $gte: d90, $lte: at } }, 'abnormalCount hasCritical values'),
  ]);
  const parts = [];
  // Medicines: doses taken of those due (a dose still due today doesn't count against).
  const counted = doses.filter((d) => d.status !== 'due' || d.scheduledAt < T.addMinutes(at, -120));
  if (counted.length >= 3) {
    const taken = counted.filter((d) => d.status === 'taken').length;
    parts.push({ key: 'medicines', label: 'Medicines taken', weight: 35, score: clamp((taken / counted.length) * 100), detail: `${taken} of ${counted.length} doses in the last 14 days` });
  }
  const bp = bpScore(vitals?.bpSystolic, vitals?.bpDiastolic);
  if (bp != null && vitals.recordedAt >= d90) parts.push({ key: 'bp', label: 'Blood pressure', weight: 15, score: bp, detail: `${vitals.bpSystolic}/${vitals.bpDiastolic} mmHg on ${T.dayKey(vitals.recordedAt)}` });
  const sg = sugarScore(sugar?.bloodSugar);
  if (sg != null && sugar.recordedAt >= d90) parts.push({ key: 'sugar', label: 'Fasting sugar', weight: 15, score: sg, detail: `${sugar.bloodSugar} mg/dL on ${T.dayKey(sugar.recordedAt)}` });
  const activeDays = new Set(logs.filter((l) => (l.type === 'steps' && l.steps >= 4000) || (l.type === 'exercise' && (l.durationMin || 0) >= 15)).map((l) => T.dayKey(l.loggedAt))).size;
  const loggedDays = new Set(logs.map((l) => T.dayKey(l.loggedAt))).size;
  if (logs.length) {
    parts.push({ key: 'activity', label: 'Active days', weight: 15, score: clamp((activeDays / 5) * 100), detail: `${activeDays} of the last 7 days (goal 5)` });
    parts.push({ key: 'logging', label: 'Days logged', weight: 10, score: clamp((loggedDays / 7) * 100), detail: `${loggedDays} of the last 7 days` });
  }
  if (labs.length) {
    const tests = labs.reduce((n, l) => n + (l.values?.length || 0), 0) || labs.length;
    const abnormal = labs.reduce((n, l) => n + (l.abnormalCount || 0), 0);
    const critical = labs.some((l) => l.hasCritical);
    parts.push({ key: 'labs', label: 'Lab results in range', weight: 10, score: critical ? 20 : clamp(100 - (abnormal / tests) * 100), detail: `${tests - abnormal} of ${tests} values in range (90 days)` });
  }
  const weight = parts.reduce((n, p) => n + p.weight, 0);
  // Too little to say anything fair: no score yet.
  if (weight < 30) return { value: null, parts };
  return { value: clamp(parts.reduce((n, p) => n + p.score * p.weight, 0) / weight), parts };
}

/** Recomputes and saves the score (with the change from a week ago). */
async function refreshScore(patient) {
  const [now, before] = await Promise.all([scoreAt(patient), scoreAt(patient, T.addDays(new Date(), -7))]);
  patient.healthScore = now.value == null
    ? { value: undefined, weeklyDelta: undefined, computedAt: new Date() }
    : { value: now.value, weeklyDelta: before.value == null ? undefined : now.value - before.value, computedAt: new Date() };
  await M.Patient.updateOne({ _id: patient._id }, { healthScore: patient.healthScore });
  return { ...now, weeklyDelta: patient.healthScore.weeklyDelta ?? null };
}

/** Score for the home screen: recomputed at most every 6 hours. */
async function currentScore(patient) {
  const at = patient.healthScore?.computedAt;
  if (!at || Date.now() - new Date(at).getTime() > 6 * 3600e3) await refreshScore(patient);
  return patient.healthScore;
}

/**
 * The patient's own health summary (once a day): AI when available, else a
 * plain summary from the record. Never advice to change medicines.
 */
async function patientSummaryFor(patient, { fresh = false } = {}) {
  const existing = await M.AiSummary.findOne({ patientId: patient._id, audience: 'patient' }).sort({ generatedAt: -1 });
  if (existing && !fresh && T.dayKey(existing.generatedAt) === T.dayKey(new Date())) return existing;
  const { patientSummary } = require('./clinical');
  const { adherence } = require('./care');
  const [record, adh, score] = await Promise.all([patientSummary(patient, null), adherence(patient, 30), scoreAt(patient)]);
  const facts = {
    conditions: (record.conditions || []).map((c) => c.name),
    allergies: (record.allergies || []).map((a) => a.allergen),
    medicines: record.currentMedicines.map((m) => `${m.name} ${m.strength || ''} ${m.pattern || ''}`.trim()),
    medicines_taken_last_30_days_percent: adh?.overallPct ?? null,
    latest_vitals: record.latestVitals && {
      date: T.dayKey(record.latestVitals.recordedAt), bp: record.latestVitals.bpSystolic ? `${record.latestVitals.bpSystolic}/${record.latestVitals.bpDiastolic}` : null,
      sugar: record.latestVitals.bloodSugar ?? null, sugar_type: record.latestVitals.sugarType, weight_kg: record.latestVitals.weightKg ?? null,
    },
    results_outside_range: record.abnormalResults.slice(0, 8).map((r) => `${r.analyte} ${r.value ?? ''} ${r.unit || ''} (${r.flag}, ${T.dayKey(r.collectedAt)})`),
    next_visit: record.nextVisit ? T.dayKey(record.nextVisit.startAt) : null,
    health_score: score.value,
  };
  const aiSvc = require('./ai');
  let body = null;
  let focus = [];
  let model;
  if (aiSvc.enabled()) {
    const out = await aiSvc.completeJson({
      system: 'Write a short health summary for the patient, in simple words, from their own record (JSON). 3-4 sentences: how things look now, what is going well, and what to watch. Quote values with dates. Never suggest changing or stopping a medicine; for anything worrying say to talk to their doctor. Then up to 3 short focus items for this week.',
      messages: [{ role: 'user', content: JSON.stringify(facts) }],
      schema: { type: 'object', properties: { summary: { type: 'string' }, focus: { type: 'array', items: { type: 'string' } } }, required: ['summary', 'focus'], additionalProperties: false },
      effort: 'low',
    }).catch((err) => { console.warn('[patient summary]', err.message); return null; });
    if (out?.data?.summary) {
      body = out.data.summary;
      focus = (out.data.focus || []).slice(0, 3);
      model = out.model;
    }
  }
  if (!body) {
    // Plain summary without AI.
    const bits = [];
    if (facts.conditions.length) bits.push(`You are being treated for ${facts.conditions.join(', ')}.`);
    if (facts.medicines.length) bits.push(`You take ${facts.medicines.length} medicine${facts.medicines.length === 1 ? '' : 's'}${facts.medicines_taken_last_30_days_percent != null ? ` and took ${facts.medicines_taken_last_30_days_percent}% of doses in the last 30 days` : ''}.`);
    if (facts.latest_vitals?.bp) bits.push(`Your last blood pressure was ${facts.latest_vitals.bp} on ${facts.latest_vitals.date}.`);
    if (facts.results_outside_range.length) bits.push(`${facts.results_outside_range.length} recent result${facts.results_outside_range.length === 1 ? ' is' : 's are'} outside the normal range — talk to your doctor about ${facts.results_outside_range.length === 1 ? 'it' : 'them'}.`);
    if (facts.next_visit) bits.push(`Your next visit is on ${facts.next_visit}.`);
    body = bits.join(' ') || 'There is not enough in your record yet for a summary. Add your readings and reports to see one here.';
    if (facts.medicines_taken_last_30_days_percent != null && facts.medicines_taken_last_30_days_percent < 80) focus.push('Take every dose on time');
    if (!facts.latest_vitals) focus.push('Add a blood pressure or sugar reading');
  }
  return M.AiSummary.create({
    patientId: patient._id, audience: 'patient', body, focusItems: focus, aiModel: model,
    sources: { labReports: record.abnormalResults.length, prescriptions: record.currentMedicines.length, medicineLog: adh?.overallPct != null },
  });
}

module.exports = { scoreAt, refreshScore, currentScore, patientSummaryFor };

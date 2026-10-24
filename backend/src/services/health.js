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

/** HbA1c (%): the 3-month sugar average — the measure that matters most in diabetes. */
function hba1cScore(x) {
  if (x == null) return null;
  if (x < 5.7) return 100;
  if (x < 6.5) return 90;
  if (x < 7) return 80;
  if (x < 8) return 60;
  if (x < 9) return 40;
  return 20;
}

const hba1cOf = (lab) => {
  const v = (lab?.values || []).find((x) => /hba1c|glycated|glycosylated|a1c/i.test(x.analyte || ''));
  const n = v ? (typeof v.value === 'number' ? v.value : require('../lib/numbers').labNumber(v.valueText)) : null;
  return Number.isFinite(n) && n > 2 && n < 20 ? n : null;
};

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
  const d120 = T.addDays(day, -119);
  const [doses, vitals, sugar, logs, labs, a1cLab] = await Promise.all([
    M.DoseLog.find({ patientId: patient._id, scheduledAt: { $gte: d14, $lte: at } }, 'status scheduledAt'),
    M.Vitals.findOne({ patientId: patient._id, recordedAt: { $lte: at }, bpSystolic: { $ne: null } }).sort({ recordedAt: -1 }),
    M.Vitals.findOne({ patientId: patient._id, recordedAt: { $lte: at }, sugarType: 'fasting', bloodSugar: { $ne: null } }).sort({ recordedAt: -1 }),
    M.HealthLog.find({ patientId: patient._id, loggedAt: { $gte: d7, $lte: at } }, 'type steps durationMin loggedAt'),
    M.LabResult.find({ patientId: patient._id, collectedAt: { $gte: d90, $lte: at } }, 'abnormalCount hasCritical values'),
    M.LabResult.findOne({ patientId: patient._id, collectedAt: { $gte: d120, $lte: at }, 'values.analyte': /hba1c|glycated|glycosylated|a1c/i }, 'collectedAt values').sort({ collectedAt: -1 }),
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
  // Sugar: the newest fasting sugar (a home reading or a lab report) and the latest HbA1c (4 months).
  const sg = sugar && sugar.recordedAt >= d90 ? sugarScore(sugar.bloodSugar) : null;
  const a1c = hba1cOf(a1cLab);
  const a1cS = hba1cScore(a1c);
  if (sg != null || a1cS != null) {
    const score = sg != null && a1cS != null ? a1cS * 0.6 + sg * 0.4 : (a1cS ?? sg);
    const detail = [
      a1cS != null && `HbA1c ${a1c}% on ${T.dayKey(a1cLab.collectedAt)}`,
      sg != null && `fasting ${sugar.bloodSugar} mg/dL on ${T.dayKey(sugar.recordedAt)}${sugar.source === 'lab' ? ' (lab)' : ''}`,
    ].filter(Boolean).join(' · ');
    parts.push({ key: 'sugar', label: a1cS != null ? 'Sugar control' : 'Fasting sugar', weight: 15, score: clamp(score), detail });
  }
  const activeDays = new Set(logs.filter((l) => (l.type === 'steps' && l.steps >= 4000) || (l.type === 'exercise' && (l.durationMin || 0) >= 15)).map((l) => T.dayKey(l.loggedAt))).size;
  const loggedDays = new Set(logs.map((l) => T.dayKey(l.loggedAt))).size;
  if (logs.length) {
    parts.push({ key: 'activity', label: 'Active days', weight: 15, score: clamp((activeDays / 5) * 100), detail: `${activeDays} of the last 7 days (goal 5)` });
    parts.push({ key: 'logging', label: 'Days logged', weight: 10, score: clamp((loggedDays / 7) * 100), detail: `${loggedDays} of the last 7 days` });
  }
  if (labs.length) {
    // Values about the patient's own conditions (HbA1c, LDL for a diabetic) count twice
    // as much as others (a slightly high blood-count value).
    const { isRelated } = require('./advisedtests');
    const conditions = (patient.conditions || []).map((c) => c.name);
    let all = 0;
    let off = 0;
    let n = 0;
    let nOff = 0;
    for (const l of labs) {
      for (const v of l.values || []) {
        const w = isRelated(v.analyte, conditions) ? 2 : 1;
        all += w;
        n += 1;
        if (v.flag && v.flag !== 'normal') {
          off += w;
          nOff += 1;
        }
      }
    }
    const critical = labs.some((l) => l.hasCritical);
    if (all) parts.push({ key: 'labs', label: 'Lab results in range', weight: 10, score: critical ? 20 : clamp(100 - (off / all) * 100), detail: `${n - nOff} of ${n} values in range (90 days)` });
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

/**
 * The score as it is now (Home, the doctor's view): recomputed when anything it
 * uses changed since it was worked out — a reading or lab report, a dose
 * marked, a log — and at least every 6 hours (doses become missed with time).
 */
async function currentScore(patient) {
  const at = patient.healthScore?.computedAt;
  let stale = !at || Date.now() - new Date(at).getTime() > 6 * 3600e3;
  if (!stale) {
    const since = { patientId: patient._id, updatedAt: { $gt: new Date(at) } };
    const changed = await Promise.all([M.Vitals.exists(since), M.LabResult.exists(since), M.DoseLog.exists(since), M.HealthLog.exists(since)]);
    stale = changed.some(Boolean);
  }
  if (stale) await refreshScore(patient);
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

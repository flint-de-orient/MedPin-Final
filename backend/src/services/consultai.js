// MedPin AI suggestions during a consultation: possible diagnoses (with ICD-10
// codes), tests to order and medicine options, each with a short reason, from
// the complaint, vitals and the patient's record. They are suggestions for the
// doctor only — nothing is added to the consultation unless the doctor taps it.
//
// Safety: medicines are checked against the patient's allergies and running
// medicines (the AI is told about both, and the catalog check in
// clinical.checkItems runs on every suggestion); ICD codes and test names are
// matched to the clinic's catalogs. Results are cached on the consultation
// until what they were made from changes.
const crypto = require('crypto');
const M = require('../models');
const T = require('../lib/time');
const ai = require('./ai');

const SCHEMA = {
  type: 'object',
  properties: {
    diagnoses: {
      type: 'array',
      items: {
        type: 'object',
        properties: { name: { type: 'string' }, icdCode: { type: 'string' }, likelihood: { type: 'string', enum: ['likely', 'possible', 'rule_out'] }, reason: { type: 'string' } },
        required: ['name', 'icdCode', 'likelihood', 'reason'], additionalProperties: false,
      },
    },
    tests: {
      type: 'array',
      items: { type: 'object', properties: { name: { type: 'string' }, reason: { type: 'string' } }, required: ['name', 'reason'], additionalProperties: false },
    },
    medicines: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' }, strength: { type: 'string' }, form: { type: 'string' },
          morning: { type: 'number' }, afternoon: { type: 'number' }, night: { type: 'number' },
          frequency: { type: 'string', enum: ['daily', 'weekly', 'as_needed'] },
          foodRelation: { type: 'string', enum: ['before_food', 'after_food', 'with_food', 'empty_stomach', 'bedtime', 'none'] },
          durationValue: { type: 'number' }, durationUnit: { type: 'string', enum: ['days', 'weeks', 'months', 'ongoing'] },
          reason: { type: 'string' }, caution: { type: 'string' },
        },
        required: ['name', 'strength', 'form', 'morning', 'afternoon', 'night', 'frequency', 'foodRelation', 'durationValue', 'durationUnit', 'reason', 'caution'],
        additionalProperties: false,
      },
    },
    redFlags: { type: 'array', items: { type: 'string' } },
  },
  required: ['diagnoses', 'tests', 'medicines', 'redFlags'],
  additionalProperties: false,
};

const SYSTEM = [
  'You are a clinical decision-support assistant for a registered medical practitioner in an Indian outpatient clinic.',
  'From the consultation details, suggest: up to 4 possible diagnoses (most likely first, ICD-10 code for each), up to 5 investigations, and up to 4 medicine options in line with standard Indian practice guidelines.',
  'Each item gets one short, specific reason that refers to the findings (e.g. "BP 152/96 on two visits", "HbA1c 8.4% in July").',
  'Medicines: generic names, adult doses unless the patient is a child, a usual strength available in India, dose as morning/afternoon/night tablet counts, food timing and duration.',
  'Never suggest a medicine the patient is allergic to or one from the same drug class; avoid clear interactions with their current medicines and say so in "caution" when relevant (e.g. kidney function, pregnancy, elderly).',
  'Do not repeat diagnoses, medicines or tests already in the consultation. If the patient already takes a suitable medicine, prefer adjusting it over adding another.',
  'List red flags that need urgent referral or emergency care, if any. If there is too little information, return fewer items rather than guessing.',
  'These are suggestions for the doctor to judge; keep wording clinical and brief.',
].join('\n');

const sha = (x) => crypto.createHash('sha1').update(JSON.stringify(x)).digest('hex');

/** The consultation as the AI sees it (no names or phone numbers). */
async function context(consult) {
  const patient = await M.Patient.findById(consult.patientId);
  const [vitals, courses, labs, past] = await Promise.all([
    consult.vitalsId ? M.Vitals.findById(consult.vitalsId).lean() : M.Vitals.findOne({ patientId: consult.patientId }).sort({ recordedAt: -1 }).lean(),
    M.MedicationCourse.find({ patientId: consult.patientId, status: 'active' }, 'name strength dose frequency').lean(),
    M.LabResult.find({ patientId: consult.patientId, collectedAt: { $gte: T.addDays(new Date(), -365) } }, 'collectedAt values').sort({ collectedAt: -1 }).limit(6).lean(),
    M.Consultation.find({ patientId: consult.patientId, _id: { $ne: consult._id }, status: { $ne: 'draft' } }, 'startedAt diagnoses').sort({ startedAt: -1 }).limit(3).lean(),
  ]);
  const v = vitals || {};
  return {
    patient,
    facts: {
      age: T.ageFrom(patient), sex: patient.gender, weightKg: v.weightKg || patient.weightKg, heightCm: patient.heightCm,
      conditions: (patient.conditions || []).map((c) => c.name),
      allergies: (patient.allergies || []).map((a) => [a.allergen, a.drugClass].filter(Boolean).join(' / ')),
      currentMedicines: courses.map((c) => `${c.name} ${c.strength || ''} ${c.dose ? `${c.dose.morning || 0}-${c.dose.afternoon || 0}-${c.dose.night || 0}` : ''}`.replace(/\s+/g, ' ').trim()),
      vitals: [v.bpSystolic && `BP ${v.bpSystolic}/${v.bpDiastolic}`, v.pulse && `pulse ${v.pulse}`, v.spo2 && `SpO2 ${v.spo2}%`, v.temperatureF && `temp ${v.temperatureF}°F`, v.bloodSugar && `sugar ${v.bloodSugar} mg/dL (${v.sugarType || 'random'})`].filter(Boolean),
      recentTests: labs.flatMap((l) => (l.values || []).filter((x) => x.flag && x.flag !== 'normal').map((x) => `${x.analyte} ${x.value ?? x.valueText}${x.unit ? ` ${x.unit}` : ''} (${x.flag}, ${T.dayKey(l.collectedAt)})`)).slice(0, 15),
      pastDiagnoses: [...new Set(past.flatMap((c) => c.diagnoses.map((d) => d.name)))],
      complaint: consult.chiefComplaint || '',
      findings: consult.findings || consult.examination || '',
      alreadyInThisConsultation: {
        diagnoses: consult.diagnoses.map((d) => d.name),
        medicines: consult.medications.map((m) => `${m.name} ${m.strength || ''}`.trim()),
        tests: (consult.labOrders || []).filter((t) => t.selected !== false).map((t) => t.testName),
      },
    },
  };
}

const FOOD = ['before_food', 'after_food', 'with_food', 'empty_stomach', 'bedtime'];

/** Suggestions for [consult] (cached until the inputs change). */
async function suggest(consult, { force = false } = {}) {
  if (!ai.enabled()) return { available: false, message: 'MedPin AI is off on this server.' };
  const { patient, facts } = await context(consult);
  if (!facts.complaint.trim() && !facts.vitals.length) return { available: true, needsComplaint: true, diagnoses: [], tests: [], medicines: [], redFlags: [] };
  const hash = sha(facts);
  if (!force && consult.aiSuggestions?.hash === hash) return { ...consult.aiSuggestions.data, cached: true };

  const out = await ai.completeJson({
    effort: 'medium',
    maxTokens: 3000,
    schema: SCHEMA,
    system: SYSTEM,
    messages: [{ role: 'user', content: JSON.stringify(facts) }],
  });
  if (!out?.data) return { available: true, failed: true, message: "MedPin AI couldn't make suggestions this time. Try again.", diagnoses: [], tests: [], medicines: [], redFlags: [] };
  const d = out.data;

  // Diagnoses: the catalog's name and code where it knows them.
  const icd = await M.IcdCode.find({ $or: [{ code: { $in: d.diagnoses.map((x) => x.icdCode).filter(Boolean) } }, { name: { $in: d.diagnoses.map((x) => x.name) } }] }).lean();
  const diagnoses = d.diagnoses.slice(0, 4).map((x) => {
    const hit = icd.find((c) => c.code === x.icdCode) || icd.find((c) => c.name.toLowerCase() === x.name.toLowerCase());
    return { name: hit?.name || x.name, icdCode: hit?.code || (/^[A-Z]\d{2}(\.\d{1,2})?$/.test(x.icdCode) ? x.icdCode : undefined), likelihood: x.likelihood, reason: x.reason, source: 'ai' };
  });

  // Tests: the catalog's name where there's a match.
  const catalog = await M.LabTest.find({}, 'name panel').lean();
  const norm = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
  const tests = d.tests.slice(0, 5).map((x) => {
    const hit = catalog.find((c) => norm(c.name) === norm(x.name)) || catalog.find((c) => norm(x.name).includes(norm(c.name)) && norm(c.name).length > 2);
    return { name: hit?.name || x.name, panel: hit?.panel, reason: x.reason, inCatalog: Boolean(hit) };
  });

  // Medicines: as consultation lines, then the catalog allergy / strength check.
  const items = d.medicines.slice(0, 4).map((x) => ({
    name: x.name, strength: x.strength || undefined, form: x.form || undefined,
    dose: { morning: Math.max(0, x.morning || 0), afternoon: Math.max(0, x.afternoon || 0), night: Math.max(0, x.night || 0) },
    frequency: x.frequency || 'daily', foodRelation: FOOD.includes(x.foodRelation) ? x.foodRelation : undefined,
    duration: x.durationUnit === 'ongoing' ? { unit: 'ongoing' } : { value: x.durationValue || undefined, unit: x.durationUnit || 'days' },
    entrySource: 'suggestion',
  }));
  const checks = await require('./clinical').checkItems(patient, items);
  const allergyWords = (patient.allergies || []).map((a) => a.allergen.toLowerCase());
  const medicines = items
    .map((item, i) => ({
      item: { ...item, ...(checks[i]?.medicineId ? { medicineId: checks[i].medicineId } : {}) },
      reason: d.medicines[i].reason,
      caution: d.medicines[i].caution || undefined,
      warnings: checks[i]?.warnings || [],
    }))
    // Belt and braces: a suggestion naming an allergen is dropped.
    .filter((m) => !allergyWords.some((a) => a && m.item.name.toLowerCase().includes(a)) && !m.warnings.some((w) => w.type === 'allergy'));

  const data = { available: true, diagnoses, tests, medicines, redFlags: d.redFlags.slice(0, 4), madeAt: new Date(), model: out.model };
  consult.aiSuggestions = { hash, data };
  consult.markModified('aiSuggestions');
  await consult.save();
  return data;
}

module.exports = { suggest, context };

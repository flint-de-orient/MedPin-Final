// "Tests your doctor asked for" (Patient-Records): every test written on the
// patient's recent prescriptions, with what it checks, how to get ready for
// it, and whether a result has come in since — a report the patient linked to
// it, or one whose name / values match it (FBS ↔ "Fasting blood sugar").
const M = require('../models');
const T = require('../lib/time');
const storage = require('./storage');

// Common Indian lab tests: names they go by, what they check, how to prepare.
// Preparation follows usual lab instructions (fasting for sugar / lipids, a
// morning sample for thyroid and urine); the lab's own instructions come first.
const CATALOG = [
  { key: 'fbs', names: ['fbs', 'fasting blood sugar', 'fasting sugar', 'fasting glucose', 'fasting plasma glucose', 'fpg', 'glucose fasting', 'blood sugar fasting'], checks: 'Your sugar level after not eating overnight', prep: 'Fast 8–10 hours (water is fine). Take the test before your morning diabetes medicine unless your doctor said otherwise.' },
  { key: 'ppbs', names: ['ppbs', 'pp sugar', 'post prandial', 'postprandial', 'post meal sugar', 'blood sugar pp', 'glucose pp', '2 hr glucose', 'pp blood sugar'], checks: 'Your sugar level after a meal', prep: 'Eat your usual meal and take your medicines as usual; give the sample exactly 2 hours after you start eating.' },
  { key: 'rbs', names: ['rbs', 'random blood sugar', 'random glucose'], checks: 'Your sugar level at any time of day', prep: 'No preparation needed.' },
  { key: 'hba1c', names: ['hba1c', 'glycated', 'glycosylated', 'a1c'], checks: 'Your average sugar over the last 3 months', prep: 'No fasting needed. Any time of day.' },
  { key: 'lipid', names: ['lipid', 'cholesterol', 'triglyceride', 'ldl', 'hdl'], checks: 'Cholesterol and fats in the blood (heart health)', prep: 'Fast 10–12 hours (water is fine). Avoid alcohol and fatty food the day before.' },
  { key: 'thyroid', names: ['tsh', 'thyroid', 't3', 't4', 'ft4', 'ft3'], checks: 'How your thyroid gland is working', prep: 'Morning sample is best. If you take a thyroid tablet, give the sample before taking it.' },
  { key: 'cbc', names: ['cbc', 'complete blood count', 'hemogram', 'haemogram', 'hb', 'hemoglobin', 'haemoglobin', 'blood count'], checks: 'Haemoglobin, blood cells and infection signs', prep: 'No fasting needed.' },
  { key: 'kft', names: ['kft', 'rft', 'kidney function', 'renal function', 'creatinine', 'urea', 'egfr', 'bun'], checks: 'How well your kidneys are working', prep: 'No fasting usually needed. Drink water normally.' },
  { key: 'lft', names: ['lft', 'liver function', 'sgpt', 'sgot', 'alt', 'ast', 'bilirubin'], checks: 'How well your liver is working', prep: 'Fasting 8–10 hours is often asked; check with the lab. Avoid alcohol for 24 hours.' },
  { key: 'urine', names: ['urine', 'urine routine', 'urine r/m', 'urine re', 'microalbumin', 'uacr', 'acr'], checks: 'Infection, sugar or protein in the urine (kidney health)', prep: 'Collect the first urine of the morning, mid-stream, in the lab’s clean container.' },
  { key: 'vitd', names: ['vitamin d', 'vit d', '25 oh', '25-oh', 'cholecalciferol'], checks: 'Vitamin D level (bones and muscles)', prep: 'No fasting needed.' },
  { key: 'b12', names: ['b12', 'vitamin b12', 'cobalamin'], checks: 'Vitamin B12 level (nerves and blood)', prep: 'Fasting 6–8 hours is often asked; check with the lab.' },
  { key: 'electrolytes', names: ['electrolyte', 'sodium', 'potassium', 'serum na', 'serum k'], checks: 'Salt and mineral balance in the blood', prep: 'No fasting needed.' },
  { key: 'uricacid', names: ['uric acid'], checks: 'Uric acid (gout and kidney stones)', prep: 'Fasting 4 hours is often asked; check with the lab.' },
  { key: 'ecg', names: ['ecg', 'ekg', 'electrocardiogram'], checks: 'Your heart rhythm', prep: 'Wear a loose shirt. Takes a few minutes; no fasting.' },
  { key: 'echo', names: ['echo', '2d echo', 'echocardiogram'], checks: 'How your heart pumps (ultrasound of the heart)', prep: 'No preparation needed.' },
  { key: 'tmt', names: ['tmt', 'treadmill', 'stress test'], checks: 'How your heart copes with exercise', prep: 'Light meal 2–3 hours before; wear walking shoes. Ask your doctor about your heart medicines that day.' },
  { key: 'usg', names: ['usg', 'ultrasound', 'sonography', 'whole abdomen'], checks: 'Pictures of organs inside the abdomen', prep: 'Abdomen scans: usually fast 6 hours and come with a full bladder; follow the centre’s instructions.' },
  { key: 'xray', names: ['x-ray', 'xray', 'x ray', 'cxr'], checks: 'An X-ray picture', prep: 'No preparation needed. Remove metal items.' },
  { key: 'psg', names: ['sleep study', 'polysomnography', 'psg'], checks: 'Breathing and oxygen while you sleep (sleep apnoea)', prep: 'Avoid caffeine and daytime naps that day; bring your night clothes and usual medicines.' },
  { key: 'crp', names: ['crp', 'c-reactive', 'esr'], checks: 'Signs of inflammation or infection', prep: 'No fasting needed.' },
];

const norm = (s) => ` ${String(s || '').toLowerCase().replace(/[^a-z0-9/]+/g, ' ').trim()} `;
const hasName = (text, name) => norm(text).includes(norm(name));

/** The catalog entry a test name belongs to ("Fasting blood sugar" → fbs), or null. */
function lookup(name) {
  const n = norm(name);
  // Longest matching name wins ("lipid profile" before "hdl").
  let best = null;
  for (const c of CATALOG) {
    for (const x of c.names) if (n.includes(norm(x)) && (!best || x.length > best.len)) best = { c, len: x.length };
  }
  return best?.c || null;
}

/** Does this test-result record (and its lab values) answer the advised test? */
function answers(name, rec, lab) {
  if ((rec.forTests || []).some((t) => norm(t) === norm(name))) return true;
  const c = lookup(name);
  const texts = [rec.title, lab?.testName, ...(lab?.values || []).map((v) => v.analyte), ...(rec.extractedTests || []).map((t) => t?.name || t)].filter(Boolean);
  if (!c) return texts.some((t) => hasName(t, name) || hasName(name, t));
  return texts.some((t) => lookup(t)?.key === c.key);
}

/**
 * Tests on the patient's prescriptions from the last 6 months, newest first,
 * one row per test (asked again later → the later ask).
 */
async function advisedTests(patient) {
  const since = T.addDays(T.dayStart(), -180);
  const rxs = await M.Prescription.find({ patientId: patient._id, issuedAt: { $gte: since }, 'tests.0': { $exists: true } }, 'tests issuedAt doctorName doctorId diagnosisSummary followUpDate')
    .sort({ issuedAt: -1 }).populate('doctorId', 'name');
  if (!rxs.length) return [];
  const recs = await M.MedicalRecord.find({ patientId: patient._id, kind: 'test_result', deletedAt: null, $or: [{ recordDate: { $gte: T.addDays(since, -1) } }, { 'forTests.0': { $exists: true } }] }).sort({ recordDate: -1 });
  const labs = recs.length ? await M.LabResult.find({ recordId: { $in: recs.map((r) => r._id) } }, 'recordId testName values.analyte') : [];
  const labOf = new Map(labs.map((l) => [String(l.recordId), l]));
  const seen = new Set();
  const out = [];
  for (const rx of rxs) {
    for (const raw of rx.tests) {
      const name = String(raw || '').trim();
      const c = lookup(name);
      const key = c?.key || norm(name);
      if (!name || seen.has(key)) continue;
      seen.add(key);
      // A result on or after the day it was asked for.
      const askedDay = T.dayStart(rx.issuedAt);
      // (a report the patient linked to this test counts whatever its date).
      const linked = (r) => (r.forTests || []).some((x) => norm(x) === norm(name));
      const hit = recs.find((r) => linked(r)) || recs.find((r) => r.recordDate >= askedDay && answers(name, r, labOf.get(String(r._id))));
      out.push({
        name,
        checks: c?.checks || null,
        prep: c?.prep || null,
        askedAt: rx.issuedAt,
        doctorName: rx.doctorId?.name || rx.doctorName || null,
        doctorId: rx.doctorId?._id || null,
        prescriptionId: rx._id,
        forWhat: rx.diagnosisSummary || null,
        bringBy: rx.followUpDate || null,
        status: hit ? 'done' : 'todo',
        result: hit ? { recordId: hit._id, date: hit.recordDate, flagLabel: hit.flagLabel || null, url: storage.signedUrl(hit.files?.[0]?.key) } : null,
      });
    }
  }
  // To do first (soonest visit first), then the done ones.
  return out.sort((a, b) => (a.status === b.status ? 0 : a.status === 'todo' ? -1 : 1));
}

module.exports = { advisedTests, lookup, CATALOG };

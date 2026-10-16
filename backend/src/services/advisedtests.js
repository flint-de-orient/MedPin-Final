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
  { key: 'hba1c', names: ['hba1c', 'glycated', 'glycosylated', 'a1c', 'glycated hemoglobin', 'glycated haemoglobin', 'glycosylated hemoglobin', 'glycosylated haemoglobin'], checks: 'Your average sugar over the last 3 months', prep: 'No fasting needed. Any time of day.' },
  { key: 'lipid', names: ['lipid', 'cholesterol', 'triglyceride', 'ldl', 'hdl'], checks: 'Cholesterol and fats in the blood (heart health)', prep: 'Fast 10–12 hours (water is fine). Avoid alcohol and fatty food the day before.' },
  { key: 'thyroid', names: ['tsh', 'thyroid', 't3', 't4', 'ft4', 'ft3'], checks: 'How your thyroid gland is working', prep: 'Morning sample is best. If you take a thyroid tablet, give the sample before taking it.' },
  { key: 'cbc', names: ['cbc', 'complete blood count', 'hemogram', 'haemogram', 'hb', 'hemoglobin', 'haemoglobin', 'blood count'], checks: 'Haemoglobin, blood cells and infection signs', prep: 'No fasting needed.' },
  { key: 'kft', names: ['kft', 'rft', 'kidney function', 'renal function', 'creatinine', 'urea', 'egfr', 'bun'], checks: 'How well your kidneys are working', prep: 'No fasting usually needed. Drink water normally.' },
  { key: 'lft', names: ['lft', 'liver function', 'sgpt', 'sgot', 'alt', 'ast', 'bilirubin'], checks: 'How well your liver is working', prep: 'Fasting 8–10 hours is often asked; check with the lab. Avoid alcohol for 24 hours.' },
  { key: 'urine', names: ['urine', 'urine routine', 'urine r/m', 'urine re', 'microalbumin', 'uacr', 'acr'], checks: 'Infection, sugar or protein in the urine (kidney health)', prep: 'Collect the first urine of the morning, mid-stream, in the lab’s clean container.' },
  { key: 'vitd', names: ['vitamin d', 'vit d', '25 oh', '25-oh', 'cholecalciferol'], checks: 'Vitamin D level (bones and muscles)', prep: 'No fasting needed.' },
  { key: 'b12', names: ['b12', 'vitamin b12', 'cobalamin'], checks: 'Vitamin B12 level (nerves and blood)', prep: 'Fasting 6–8 hours is often asked; check with the lab.' },
  { key: 'electrolytes', names: ['electrolyte', 'electrolytes', 'sodium', 'potassium', 'serum na', 'serum k'], checks: 'Salt and mineral balance in the blood', prep: 'No fasting needed.' },
  { key: 'uricacid', names: ['uric acid'], checks: 'Uric acid (gout and kidney stones)', prep: 'Fasting 4 hours is often asked; check with the lab.' },
  { key: 'ecg', names: ['ecg', 'ekg', 'electrocardiogram'], checks: 'Your heart rhythm', prep: 'Wear a loose shirt. Takes a few minutes; no fasting.' },
  { key: 'echo', names: ['echo', '2d echo', 'echocardiogram'], checks: 'How your heart pumps (ultrasound of the heart)', prep: 'No preparation needed.' },
  { key: 'tmt', names: ['tmt', 'treadmill', 'stress test'], checks: 'How your heart copes with exercise', prep: 'Light meal 2–3 hours before; wear walking shoes. Ask your doctor about your heart medicines that day.' },
  { key: 'usg', names: ['usg', 'ultrasound', 'sonography', 'whole abdomen'], checks: 'Pictures of organs inside the abdomen', prep: 'Abdomen scans: usually fast 6 hours and come with a full bladder; follow the centre’s instructions.' },
  { key: 'xray', names: ['x-ray', 'xray', 'x ray', 'cxr'], checks: 'An X-ray picture', prep: 'No preparation needed. Remove metal items.' },
  { key: 'psg', names: ['sleep study', 'polysomnography', 'psg'], checks: 'Breathing and oxygen while you sleep (sleep apnoea)', prep: 'Avoid caffeine and daytime naps that day; bring your night clothes and usual medicines.' },
  { key: 'hbpm', names: ['home blood pressure', 'hbpm', 'bp log', 'bp chart', 'bp diary', 'blood pressure log', 'blood pressure monitoring', 'blood pressure chart', 'ambulatory blood pressure', 'abpm'], checks: 'Your blood pressure at home over several days', prep: 'For 7 days, measure twice in the morning and twice in the evening — seated, rested 5 minutes, no tea or smoking 30 minutes before. Write the readings down or photograph the BP machine screen.' },
  { key: 'fundus', names: ['fundoscopy', 'fundus', 'ophthalmoscopy', 'retina', 'retinal', 'dilated eye'], checks: 'The back of your eyes (diabetes and BP can affect it)', prep: 'Eye drops widen your pupils; your vision is blurry for 4–6 hours, so don’t drive yourself back.' },
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

/**
 * Every catalog group a name belongs to: "Serum Creatinine and Electrolytes" →
 * {kft, electrolytes}. A name inside a longer one doesn't count on its own
 * ("hemoglobin" in "glycated hemoglobin" is HbA1c, not a blood count).
 */
function keysOf(name) {
  const n = norm(name);
  const hits = [];
  for (const c of CATALOG) {
    for (const x of c.names) {
      const at = n.indexOf(norm(x));
      if (at >= 0) hits.push({ key: c.key, from: at, to: at + norm(x).length });
    }
  }
  return new Set(hits.filter((h) => !hits.some((o) => o !== h && o.to - o.from > h.to - h.from && o.from <= h.from && o.to >= h.to)).map((h) => h.key));
}

// Words too common to identify a test on their own.
const COMMON = new Set(['test', 'tests', 'report', 'serum', 'blood', 'level', 'levels', 'profile', 'panel', 'routine', 'total', 'including', 'with', 'home', 'lead', 'function', 'count']);

/** Is the advised test [name] among these test / value names read from a report? */
function inReport(name, texts) {
  const want = keysOf(name);
  if (want.size) return texts.some((t) => [...keysOf(t)].some((k) => want.has(k)));
  // Not in the catalog ("Fundus photo"): its own distinctive words.
  const words = norm(name).trim().split(' ').filter((w) => w.length >= 4 && !COMMON.has(w));
  return texts.some((t) => hasName(t, name) || hasName(name, t) || words.some((w) => norm(t).includes(` ${w} `)));
}

/** The test and value names a report was read into. */
const namesIn = (extracted) => (extracted?.tests || []).flatMap((t) => [t.test_name, ...(t.values || []).map((v) => v.analyte)]).filter(Boolean);

/**
 * What an uploaded report really contains, against the tests it was uploaded
 * for: { asked, found, missing, detected, readable, documentType }. A test
 * counts only when the report's content shows it — not the file name.
 */
function checkReport(asked, extracted, { auto = false } = {}) {
  const texts = namesIn(extracted);
  const found = asked.filter((a) => inReport(a, texts));
  return {
    asked, found, missing: asked.filter((a) => !found.includes(a)), auto,
    // false: the report couldn't be read by MedPin AI (off or failed) — not checked, not wrong.
    checked: extracted != null,
    detected: [...new Set((extracted?.tests || []).map((t) => t.test_name).filter(Boolean))].slice(0, 8),
    readable: texts.length > 0,
    documentType: extracted?.document_type || null,
    at: new Date(),
  };
}

/** Why a report uploaded for a test doesn't count (yet). */
function uploadStatus(check) {
  if (check.checked === false) return 'unchecked';
  if (check.readable) return 'wrong';
  return ['prescription', 'not_medical'].includes(check.documentType) ? 'wrong' : 'unreadable';
}

/** Does this test-result record answer the advised test? Only by what it contains. */
function answers(name, rec, lab) {
  // Checked at upload: its content showed this test (older uploads weren't checked, so they don't count this way).
  if (rec.testCheck && (rec.forTests || []).some((t) => norm(t) === norm(name))) return true;
  return lab ? inReport(name, [lab.testName, ...(lab.values || []).map((v) => v.analyte)]) : false;
}

// Which of the visit's diagnoses each kind of test is about ("for Type 2 Diabetes").
const RELATED = {
  fbs: /diabet|glucose|sugar|metabolic|insulin/i, ppbs: /diabet|glucose|sugar|metabolic|insulin/i, rbs: /diabet|glucose|sugar|metabolic|insulin/i,
  hba1c: /diabet|glucose|sugar|metabolic|insulin/i,
  lipid: /lipid|cholesterol|hypertension|metabolic|coronary|heart|cardiac|stroke|diabet/i,
  thyroid: /thyroid|goit|hypothyr|hyperthyr/i,
  cbc: /an(a)?emi|infection|fever|bleed/i,
  kft: /kidney|renal|ckd|nephro|hypertension|diabet/i,
  lft: /liver|hepat|fatty|alcohol|jaundice/i,
  urine: /urin|uti|kidney|renal|nephro|diabet/i,
  vitd: /vitamin d|bone|osteo/i, b12: /b12|neuropath|an(a)?emi/i,
  electrolytes: /kidney|renal|hypertension|dehydrat|vomit|diarrh/i,
  uricacid: /gout|uric|stone/i,
  ecg: /heart|cardiac|coronary|hypertension|chest|palpitat|arrhythm/i, echo: /heart|cardiac|coronary|hypertension|valv|murmur/i, tmt: /heart|cardiac|coronary|chest|angina/i,
  usg: /abdomen|liver|kidney|gall|fatty|pancrea/i, xray: /lung|chest|cough|fracture|bone/i,
  psg: /sleep|apn(o)?ea|snor/i, hbpm: /hypertension|blood pressure|\bbp\b/i, fundus: /diabet|hypertension|retin|vision|eye/i,
  crp: /infection|inflamm|arthrit|fever/i,
};

/** Is a test / value ("HbA1c", "LDL cholesterol") about any of these conditions? */
function isRelated(name, conditions) {
  const text = (conditions || []).join(', ');
  return Boolean(text) && [...keysOf(name)].some((k) => RELATED[k]?.test(text));
}

/** The diagnoses this test is for, from the prescription's list ("Type 2 Diabetes Mellitus"), or null. */
function relatedDiagnoses(name, summary) {
  const keys = [...keysOf(name)];
  if (!summary || !keys.length) return null;
  const hits = String(summary).split(/\s*[,;]\s*/).filter((d) => d && keys.some((k) => RELATED[k]?.test(d)));
  return hits.length ? hits.slice(0, 2).join(', ') : null;
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
      // A result on or after the day it was asked for (a report checked for this test counts whatever its date).
      const askedDay = T.dayStart(rx.issuedAt);
      const checkedFor = (r) => r.testCheck && (r.forTests || []).some((x) => norm(x) === norm(name));
      const hit = recs.find(checkedFor) || recs.find((r) => r.recordDate >= askedDay && answers(name, r, labOf.get(String(r._id))));
      // Not done yet, but a report was uploaded for it: why it doesn't count.
      const tried = hit ? null : recs.find((r) => r.testCheck && !r.testCheck.auto && (r.testCheck.asked || []).some((x) => norm(x) === norm(name)));
      out.push({
        name,
        checks: c?.checks || null,
        prep: c?.prep || null,
        askedAt: rx.issuedAt,
        doctorName: rx.doctorId?.name || rx.doctorName || null,
        doctorId: rx.doctorId?._id || null,
        prescriptionId: rx._id,
        forWhat: relatedDiagnoses(name, rx.diagnosisSummary),
        bringBy: rx.followUpDate || null,
        // done · todo · unchecked (uploaded; couldn't be checked automatically, the doctor will)
        // · unreadable (too blurred / cut off) · wrong (another test, a prescription, not a report)
        status: hit ? 'done' : tried ? uploadStatus(tried.testCheck) : 'todo',
        result: hit ? { recordId: hit._id, date: hit.recordDate, flagLabel: hit.flagLabel || null, url: storage.signedUrl(hit.files?.[0]?.key) } : null,
        lastUpload: tried ? { recordId: tried._id, date: tried.createdAt || tried.recordDate, detected: tried.testCheck.detected || [], documentType: tried.testCheck.documentType || null } : null,
      });
    }
  }
  // Still to do first (a wrong or unreadable upload counts as to do), then the uploaded ones.
  const settled = (x) => Number(x.status === 'done' || x.status === 'unchecked');
  return out.sort((a, b) => settled(a) - settled(b));
}

module.exports = { advisedTests, lookup, keysOf, inReport, checkReport, relatedDiagnoses, isRelated, CATALOG };

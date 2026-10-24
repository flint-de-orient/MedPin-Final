// Confirmed lab results that measure what the patient tracks become readings
// (Vitals, source "lab"), so Home's tiles, the health score and the doctor's
// view all show the newest value wherever it came from: fasting / after-food /
// random sugar from a lab report, and each reading of a home BP log. Only
// results that were saved (the patient checked them on "Check your report",
// or the clinic entered them) — never values MedPin AI read but nobody confirmed.
const { keysOf } = require('./advisedtests');

const num = (v) => {
  const x = require('../lib/numbers').labNumber(v);
  return Number.isFinite(x) ? x : null;
};

const SUGAR = { fbs: 'fasting', ppbs: 'post_meal', rbs: 'random' };

/** The readings a lab result holds: [{ bloodSugar, sugarType } | { bpSystolic, bpDiastolic, pulse? }]. */
function readingsOf(lab) {
  const testKeys = keysOf(lab.testName || '');
  const out = [];
  let sys = null;
  let dia = null;
  for (const v of lab.values || []) {
    const name = String(v.analyte || '');
    const keys = new Set([...keysOf(name), ...(keysOf(name).size ? [] : testKeys)]);
    const text = `${v.value ?? ''} ${v.valueText ?? ''}`;
    // Sugar: a glucose value in a sugar test (mmol/L converted to mg/dL).
    const sugarKey = ['fbs', 'ppbs', 'rbs'].find((k) => keys.has(k));
    if (sugarKey && /glucose|sugar|fbs|ppbs|rbs|fpg/i.test(`${name} ${lab.testName}`)) {
      let x = num(v.value ?? v.valueText);
      if (x != null && /mmol/i.test(v.unit || '')) x = Math.round(x * 18);
      if (x != null && x >= 10 && x <= 1000) out.push({ bloodSugar: x, sugarType: SUGAR[sugarKey] });
      continue;
    }
    // Blood pressure: "142/88" (a BP log has one per reading), or systolic + diastolic rows.
    const bp = text.match(/\b(\d{2,3})\s*\/\s*(\d{2,3})\b/);
    if (bp && (keys.has('hbpm') || /blood pressure|\bbp\b|reading/i.test(`${name} ${lab.testName}`))) {
      const s = Number(bp[1]);
      const d = Number(bp[2]);
      if (s >= 60 && s <= 300 && d >= 30 && d <= 200 && s > d) out.push({ bpSystolic: s, bpDiastolic: d });
      continue;
    }
    if (/systolic/i.test(name)) sys = num(v.value ?? v.valueText);
    if (/diastolic/i.test(name)) dia = num(v.value ?? v.valueText);
  }
  if (sys && dia && sys > dia && sys <= 300 && dia >= 30) out.push({ bpSystolic: sys, bpDiastolic: dia });
  return out.slice(0, 60);
}

/** Saves the readings of [lab] (replacing any made from it before). */
async function syncFromLab(lab) {
  const M = require('../models');
  await M.Vitals.deleteMany({ fromLabId: lab._id });
  const readings = readingsOf(lab);
  if (!readings.length) return 0;
  const at = new Date(lab.collectedAt || Date.now());
  // A log's readings keep their order (a minute apart) when the report has one date for all.
  await M.Vitals.insertMany(readings.map((r, i) => ({
    ...r, patientId: lab.patientId, practiceId: lab.practiceId, source: 'lab', recordedAt: new Date(at.getTime() + i * 60000), fromLabId: lab._id,
    note: lab.testName ? `From ${lab.testName}` : undefined,
  })));
  return readings.length;
}

module.exports = { readingsOf, syncFromLab };

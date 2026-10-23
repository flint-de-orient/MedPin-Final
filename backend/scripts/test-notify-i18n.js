// Notifications in Bengali / Hindi (src/lib/notify_i18n.js), no database needed:
//  1. known titles translate, English and unknown text stay as they are;
//  2. EVERY English title / body written in a notify() call (and the helpers that feed
//     it) in src/ is covered by a template — a new English-only notification fails here.
// Usage: node scripts/test-notify-i18n.js (also run as a step of npm run test:api).
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const { translate, LANGS } = require('../src/lib/notify_i18n');

const SRC = path.join(__dirname, '..', 'src');

// Words that may stay in Latin letters after translation: names, places, units, brands.
const KEEP = new Set(['Rajat', 'Mondal', 'Priya', 'Sharma', 'Ananya', 'Sen', 'Dr', 'Salt', 'Lake', 'New', 'Town', 'MedPin', 'AI', 'UPI', 'ID', 'mmHg', 'bpm', 'SpO', 'mg', 'dL', 'Metformin', 'Amlodipine', 'HbA', 'AM', 'PM', 'Complete', 'Blood', 'Count', 'MBBS', 'rajat', 'okaxis', 'Clinic']);
const leftover = (s) => (s.match(/[A-Za-z]{2,}/g) || []).filter((w) => !KEEP.has(w));
/** Translated in both languages, with no English word left over. */
const covered = (s) => LANGS.every((l) => {
  const t = translate(s, l);
  return t !== s && !leftover(t).length && !/[$%&~#@]\d/.test(t);
});

// ── 1. Unit checks ──
function unit() {
  assert.equal(translate('Visit confirmed', 'bn'), 'ভিজিট নিশ্চিত');
  assert.equal(translate('Visit confirmed', 'hi'), 'विज़िट पक्की');
  assert.equal(translate('Visit confirmed', 'en'), 'Visit confirmed', 'English unchanged');
  assert.equal(translate('Visit confirmed', undefined), 'Visit confirmed');
  assert.equal(translate('Visit confirmed — 9:00 AM, Mon 19 Oct', 'bn'), 'ভিজিট নিশ্চিত — 9:00 AM, সোম 19 অক্টো', 'weekday / month words translated, time kept');
  assert.equal(translate('Visit confirmed — 9:00 AM, Mon 19 Oct', 'hi'), 'विज़िट पक्की — 9:00 AM, सोम 19 अक्टू');
  assert.equal(translate('Urgent message from Rajat Mondal', 'bn'), 'Rajat Mondal জরুরি মেসেজ পাঠিয়েছেন');
  assert.equal(translate('Urgent message from Rajat Mondal', 'hi'), 'Rajat Mondal ने ज़रूरी मैसेज भेजा');
  assert.equal(translate("Refund of ₹500 to Rajat Mondal didn't go through", 'bn'), 'Rajat Mondal-কে ₹500 ফেরত দেওয়া যায়নি');
  assert.equal(translate("Refund of ₹500 to Rajat Mondal didn't go through", 'hi'), 'Rajat Mondal को ₹500 का रिफ़ंड नहीं हो पाया');
  assert.equal(translate("Refund of ₹500 to the patient didn't go through", 'bn'), 'রোগীকে ₹500 ফেরত দেওয়া যায়নি', 'fallback words translated');
  assert.equal(translate('A patient cancelled a visit', 'hi'), 'एक मरीज़ ने एक विज़िट रद्द की');
  assert.equal(translate('9:00 AM, 2026-10-19 · Token 05', 'bn'), '9:00 AM, 2026-10-19 · টোকেন 05', 'line parts translated one by one');
  assert.equal(translate('Emergency: Priya Sharma', 'hi'), 'आपात: Priya Sharma');
  assert.equal(translate('Please let the doctor know. Home BP reading 182/110 mmHg, above the alert limit.', 'bn'), 'ডাক্তারকে জানান। বাড়িতে রক্তচাপ 182/110 mmHg, সতর্কতার সীমার বেশি।', 'a detail inside a line');
  assert.equal(translate('2 reports shared (1 out of range) · 1 you asked for', 'hi'), '2 रिपोर्ट शेयर की गईं (1 सीमा से बाहर) · 1 आपने मांगी थीं');
  // Unknown text (a patient's own message, a free-text reason) is left alone.
  for (const s of ['My sugar is 240 since morning', 'Need to talk: about my report', 'Rajat Mondal', '', 'ok · fine']) {
    for (const l of ['bn', 'hi', 'en']) assert.equal(translate(s, l), s, `unchanged: ${s}`);
  }
  assert.equal(translate(undefined, 'bn'), undefined);
}

// ── 2. Coverage of the notification text in src/ ──

function skipString(src, i) {
  const q = src[i];
  if (q === '`') return parseTemplate(src, i).end;
  i += 1;
  while (i < src.length && src[i] !== q) i += src[i] === '\\' ? 2 : 1;
  return i + 1;
}
/** Index of [closer] at depth 0 from i (strings and nested brackets skipped). */
function balanced(src, i, closers) {
  let depth = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === '"' || c === "'" || c === '`') { i = skipString(src, i); continue; }
    if (c === '/' && src[i + 1] === '/') { i = src.indexOf('\n', i); if (i < 0) return src.length; continue; }
    if ('([{'.includes(c)) depth += 1;
    else if (')]}'.includes(c)) {
      if (depth === 0) return i;
      depth -= 1;
    } else if (depth === 0 && closers.includes(c)) return i;
    i += 1;
  }
  return src.length;
}
function parseTemplate(src, i) {
  i += 1;
  const quasis = [''];
  const exprs = [];
  while (i < src.length) {
    const c = src[i];
    if (c === '\\') { quasis[quasis.length - 1] += src[i + 1]; i += 2; continue; }
    if (c === '`') return { end: i + 1, quasis, exprs };
    if (c === '$' && src[i + 1] === '{') {
      const end = balanced(src, i + 2, '');
      exprs.push(src.slice(i + 2, end));
      quasis.push('');
      i = end + 1;
      continue;
    }
    quasis[quasis.length - 1] += c;
    i += 1;
  }
  throw new Error('unterminated template');
}
/** String literals in an expression (not the operands of === / !==). */
function literals(expr) {
  const out = [];
  let i = 0;
  while (i < expr.length) {
    const c = expr[i];
    if (c === '"' || c === "'" || c === '`') {
      const end = skipString(expr, i);
      const before = expr.slice(0, i).trimEnd();
      const after = expr.slice(end).trimStart();
      if (!/[!=]==?$/.test(before) && !/^[!=]==?/.test(after)) {
        out.push(c === '`' ? parseTemplate(expr, i) : { quasis: [expr.slice(i + 1, end - 1).replace(/\\'/g, "'")], exprs: [] });
      }
      i = end;
      continue;
    }
    i += 1;
  }
  return out;
}
// Values to try for a ${…} with no literal of its own.
const FREE = ['Rajat Mondal', '5', '2026-10-19'];
const HINTS = {
  how: ['online', 'at the clinic (cash)'],
  label: ['today', 'in 45 minutes'],
  days: ['2026-10-19 to 2026-10-21'],
  reason: ['Closed all day'],
  'SLOT_LABEL[g.slot]': ['Morning', 'Night'],
  'LABEL[status]': ['Placed'],
  what: ['a prescription', 'a report', '3 reports'],
  'doseText(c.dose)': ['1-0-1'],
};
const samplesOf = (lit, cap = 40) => {
  const groups = lit.exprs.map((e) => [...literals(e).map((l) => samplesOf(l, 6)), ...[]]);
  const all = lit.exprs.map((e, k) => [...new Set([...groups[k].flat(), ...(HINTS[e.trim()] || []), ...FREE])]);
  const out = [];
  const build = (vals) => lit.quasis.reduce((s, q, k) => s + q + (k < vals.length ? vals[k] : ''), '');
  const walk = (k, vals) => {
    if (out.length >= cap) return;
    if (k === all.length) { out.push(build(vals)); return; }
    for (const v of all[k]) walk(k + 1, [...vals, v]);
  };
  walk(0, []);
  return out;
};
/** Is this literal covered: some filling translates, and each literal alternative inside it can too. */
function literalCovered(lit) {
  const statics = lit.quasis.join('');
  if (!/[A-Za-z]{2,}/.test(statics)) return true; // only "${a} · ${b}": nothing to translate
  const groups = lit.exprs.map((e) => literals(e).map((l) => samplesOf(l, 6)));
  const all = lit.exprs.map((e, k) => [...new Set([...groups[k].flat(), ...(HINTS[e.trim()] || []), ...FREE])]);
  const build = (vals) => lit.quasis.reduce((s, q, k) => s + q + (k < vals.length ? vals[k] : ''), '');
  const search = (fixedAt, choices) => {
    let tries = 0;
    const walk = (k, vals) => {
      if (tries++ > 20000) return false;
      if (k === all.length) return covered(build(vals));
      for (const v of k === fixedAt ? choices : all[k]) if (walk(k + 1, [...vals, v])) return true;
      return false;
    };
    return walk(0, []);
  };
  if (!search(-1, [])) return false;
  // Each fixed alternative (today / tomorrow / "in N days", 'Emergency' / 'Urgent' / 'Watch'…).
  return groups.every((gs, k) => gs.every((g) => !/[A-Za-z]{2,}/.test(g.join('')) || search(k, g)));
}

const CALLS = /(?<!function )\b(notify|tellDesk|raiseAlert|tellAccessChanged)\(|\bout\.push\(\{ severity/g;
const KEYS = /(?<![\w.])(title|body|detail)\s*:/g;

function scan() {
  const found = [];
  const files = [];
  const walkDir = (d) => fs.readdirSync(d, { withFileTypes: true }).forEach((e) => (e.isDirectory() ? walkDir(path.join(d, e.name)) : e.name.endsWith('.js') && files.push(path.join(d, e.name))));
  walkDir(SRC);
  for (const file of files) {
    if (file.endsWith(path.join('services', 'notify.js')) || file.endsWith('notify_i18n.js')) continue;
    const src = fs.readFileSync(file, 'utf8');
    for (const m of src.matchAll(CALLS)) {
      const open = m.index + m[0].lastIndexOf('(');
      const end = balanced(src, open + 1, '');
      const args = src.slice(open + 1, end);
      const line = src.slice(0, m.index).split('\n').length;
      const where = `${path.relative(SRC, file)}:${line}`;
      if (m[1] === 'tellAccessChanged') {
        for (const lit of literals(args)) found.push({ where, lit });
        continue;
      }
      // title: / body: / detail: anywhere in the call (outside strings).
      let i = 0;
      while (i < args.length) {
        const c = args[i];
        if (c === '"' || c === "'" || c === '`') { i = skipString(args, i); continue; }
        KEYS.lastIndex = i;
        const k = KEYS.exec(args);
        if (k && k.index === i) {
          const from = i + k[0].length;
          const to = balanced(args, from, ',');
          for (const lit of literals(args.slice(from, to))) found.push({ where, lit });
          i = to;
          continue;
        }
        i += 1;
      }
    }
  }
  return found;
}

// Notification text that reaches notify() through a variable or a helper.
const INDIRECT = [
  'Your access changed', 'Your access is back on',
  'Doctor · All locations', 'Front desk · Salt Lake', "Doctor's assistant · Salt Lake, New Town", 'Practice manager · All locations', 'Dietician', 'Lab manager', 'Lab technician',
  'The pharmacy confirmed your order', 'Your medicines are packed', 'Your medicines are on the way', 'Your medicines are ready to pick up',
  'Your medicines were delivered', 'Order collected', 'Your order was cancelled', 'Order Placed',
  'Urgent message from Dr. Sen', 'New message from Clinic', 'New message from Rajat',
  '9:00 AM with Dr. Ananya Sen · Salt Lake · token 4', '9:00 AM with your doctor',
  'Salt Lake Clinic: your follow-up is due on 2026-10-30. Please book a visit in MedPin or reply to this message.',
  'Metformin 500 mg, Amlodipine 5 mg · Morning dose · after food / with food', 'Night dose · on an empty stomach', 'Afternoon dose · before food',
  'Home BP reading 182/110 mmHg, above the alert limit.', 'SpO₂ 86%, below 92%.', 'Heart rate 130 bpm, outside 45–120.', 'Fasting sugar 260 mg/dL.', 'Low blood sugar 50 mg/dL.',
  'Critical result in HbA1c (shared by the patient)', 'Critical result in Complete Blood Count',
  'Add your UPI ID or bank account in Payouts to receive this.', 'Payouts are being set up. Your balance is safe and will be paid.', 'Re-enter your bank account in Payouts so it can be verified.',
  'Please upload a clearer copy', 'Closed all day', 'Closed part of the day',
  'full with logs', 'full record', 'prescriptions and tests', 'daily log only', 'not shared',
  '3 seen · 1 missed · 2 follow-ups due in 3 days · 4 open alerts · 5 chats waiting',
  '2 reports shared (1 out of range) · 1 you asked for · 3 patients below 70% on medicines · 2 not logging meals', '1 report shared',
  'Resolved by the doctor', 'Priya Sharma: Home BP reading 182/110 mmHg, above the alert limit.',
  'Your patients since yesterday · Salt Lake Clinic', 'Your patients since yesterday · clinic',
  '2026-10-19 to 2026-10-21 · Closed all day. Please choose another time for your visit.',
  '2026-10-19 · 9:00 AM – 1:00 PM · your booked visit stands.',
  'Salt Lake is closed 2026-10-19 to 2026-10-21 · 9:00 AM – 1:00 PM',
  'Rajat Mondal paid ₹500 at the clinic (UPI)', 'Your visit with the doctor · reference 123456',
  '3 online fees · to rajat@okaxis',
];

function coverage() {
  const found = scan();
  assert.ok(found.length >= 60, `found the notification text in src/ (${found.length})`);
  const missing = found.filter(({ lit }) => !literalCovered(lit)).map(({ where, lit }) => `${where}  ${lit.quasis.join('${…}')}`);
  const indirect = INDIRECT.filter((s) => !covered(s)).map((s) => `${s}  →  ${translate(s, 'bn')}  |  ${translate(s, 'hi')}`);
  assert.deepEqual([...missing, ...indirect], [], `notification text with no Bengali / Hindi template (add one in src/lib/notify_i18n.js):\n${[...missing, ...indirect].join('\n')}`);
  return found.length + INDIRECT.length;
}

function run() {
  unit();
  return coverage();
}

if (require.main === module) {
  const n = run();
  console.log(`  ✓ notification text in Bengali / Hindi (${n} texts checked)`);
}

module.exports = { run };

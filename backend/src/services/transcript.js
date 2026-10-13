// Cleans up speech-to-text before it's used: phone speech recognition often
// mishears medicine names ("met for min", "glimi pride") and doses. Two steps:
//  1. medicine names: each word / word pair is matched against the medicine
//     catalog (generic and brand names) by spelling and sound;
//  2. MedPin AI (when on) fixes the remaining misheard medical words, using the
//     recogniser's other guesses — never adding, removing or translating.
// Anything unsure stays as spoken; with AI off only step 1 runs.
const M = require('../models');
const ai = require('./ai');

const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

/** Levenshtein distance (small strings). */
function distance(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  }
  return d[a.length][b.length];
}

/** A rough "sounds like" key: vowels and doubled letters don't matter much in misheard names. */
const sound = (s) => norm(s).replace(/ph/g, 'f').replace(/[ck]/g, 'k').replace(/z/g, 's').replace(/[aeiouyh]/g, '').replace(/(.)\1+/g, '$1');

/** Catalog names (cached a few minutes). */
let cache = { at: 0, names: [] };
async function catalogNames() {
  if (Date.now() - cache.at < 5 * 60e3) return cache.names;
  const meds = await M.Medicine.find({ active: { $ne: false } }, 'genericName brandNames').lean();
  const names = [...new Set(meds.flatMap((m) => [m.genericName, ...(m.brandNames || [])]).filter(Boolean))];
  cache = { at: Date.now(), names };
  return names;
}

/** Replaces words (or two / three words heard as one name) that are close to a catalog name. */
function fixNames(text, names) {
  const words = text.split(/(\s+)/); // keep spacing
  const idx = words.map((w, i) => (/\S/.test(w) ? i : -1)).filter((i) => i >= 0);
  const out = [...words];
  const used = new Set();
  for (let span = 3; span >= 1; span--) {
    for (let k = 0; k + span <= idx.length; k++) {
      const pos = idx.slice(k, k + span);
      if (pos.some((p) => used.has(p))) continue;
      // Names have no digits: "40", "500mg" are doses, never part of a name.
      if (pos.some((p) => /\d/.test(words[p]))) continue;
      const heard = pos.map((p) => words[p]).join('');
      const h = norm(heard);
      if (h.length < 4) continue;
      let best = null;
      for (const n of names) {
        const t = norm(n);
        if (Math.abs(t.length - h.length) > 3) continue;
        const score = 1 - distance(h, t) / Math.max(h.length, t.length);
        const sounds = sound(h) && sound(h) === sound(t);
        if ((score >= 0.8 || (sounds && score >= 0.6)) && (!best || score > best.score)) best = { n, score };
      }
      if (best && (span > 1 || h !== norm(best.n))) {
        out[pos[0]] = best.n;
        for (const p of pos.slice(1)) out[p] = '';
        // Remove the spaces between joined words.
        for (let p = pos[0] + 1; p <= pos[pos.length - 1]; p++) if (!/\S/.test(words[p])) out[p] = '';
        pos.forEach((p) => used.add(p));
      } else if (best) {
        pos.forEach((p) => used.add(p));
      }
    }
  }
  return out.join('').replace(/\s{2,}/g, ' ').trim();
}

const PURPOSE = {
  medicine: 'a doctor dictating a medicine order (name, strength, dose pattern like 1-0-1, food timing, duration)',
  question: 'a doctor asking a clinical question',
  symptoms: 'a patient describing what they need or their symptoms',
  note: 'a short clinical note',
};

/**
 * { text, alternates?, purpose?, language? } → { text, changed, source }.
 * Never throws: on any trouble the spoken text comes back unchanged.
 */
async function cleanTranscript({ text, alternates = [], purpose = 'note', language = 'en' }) {
  const spoken = String(text || '').trim().slice(0, 1000);
  if (!spoken) return { text: '', changed: false, source: 'none' };
  let fixed = spoken;
  let source = 'none';
  try {
    if (purpose === 'medicine' && /[a-z]/i.test(spoken)) {
      const names = await catalogNames();
      const byName = fixNames(spoken, names);
      if (byName !== spoken) {
        fixed = byName;
        source = 'catalog';
      }
    }
    if (ai.enabled()) {
      const names = purpose === 'medicine' ? (await catalogNames()).slice(0, 300) : [];
      const others = [...new Set(alternates.map((a) => String(a || '').trim()).filter((a) => a && a !== spoken))].slice(0, 4);
      const answer = await Promise.race([
        ai.completeJson({
          effort: 'low',
          maxTokens: 600,
          schema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false },
          system: [
            `You correct speech-recognition mistakes in ${PURPOSE[purpose] || PURPOSE.note} in India.`,
            'Fix only words that were clearly misheard: medicine names, strengths and units (mg, mcg, ml), dose patterns, medical terms, numbers.',
            'Do not add, remove, reorder, explain, translate or rephrase anything else. Keep the speaker\'s language and script (English, Bengali or Hindi).',
            'Use the other guesses from the recogniser when they show the right word. If unsure, keep the word as heard.',
            names.length ? `Medicines in this clinic's catalog: ${names.join(', ')}.` : '',
            'Reply with the corrected text only, in the "text" field.',
          ].filter(Boolean).join('\n'),
          messages: [{ role: 'user', content: `Heard: ${fixed}${others.length ? `\nOther guesses:\n${others.map((o) => `- ${o}`).join('\n')}` : ''}\nLanguage: ${language}` }],
        }),
        new Promise((resolve) => setTimeout(() => resolve(null), 7000)),
      ]);
      const t = String(answer?.data?.text || '').trim();
      // Guard: a correction is a fix, not a rewrite (similar length, not empty).
      if (t && t.length <= fixed.length * 1.6 + 20 && t.length >= fixed.length * 0.5) {
        if (t !== fixed) source = source === 'catalog' ? 'catalog+ai' : 'ai';
        fixed = t;
      }
    }
  } catch (err) {
    console.warn('[transcript]', err.message);
  }
  return { text: fixed, changed: fixed !== spoken, source };
}

module.exports = { cleanTranscript, fixNames, distance, sound };

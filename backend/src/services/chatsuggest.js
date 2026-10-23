// Quick replies under the patient's chat (Patient-DoctorChat): picked from the
// newest message the care team sent and the patient's own day — today's sugar
// and BP readings, today's doses, a visit today — so a tap sends something
// true ("My fasting sugar today is 132 mg/dL (8:10 AM)."), never a placeholder.
//
// Multilingual: the topic is recognised in English, Bengali and Hindi (and the
// clinic's English-letter Bengali / Hindi), and the text a tap sends is in the
// patient's app language. Labels stay English keys — the app translates them.
const M = require('../models');
const T = require('../lib/time');

const has = (text, re) => re.test(String(text || '').toLowerCase());

// What the clinic's message is about, in any of the three languages.
const TOPIC = {
  sugar: /sugar|glucose|fasting|hba1c|diabet|সুগার|শর্করা|ডায়াবেটিস|খালি পেটে|शुगर|मधुमेह|डायबिटीज|खाली पेट/,
  bp: /\bbp\b|pressure|প্রেশার|প্রেসার|রক্তচাপ|बीपी|ब्लड प्रेशर|रक्तचाप/,
  meds: /medicine|tablet|dose|pill|taking|insulin|ওষুধ|ট্যাবলেট|ডোজ|ইনসুলিন|दवा|दवाई|गोली|डोज|इंसुलिन/,
  report: /report|test|lab|scan|x-ray|result|রিপোর্ট|পরীক্ষা|টেস্ট|रिपोर्ट|टेस्ट|जांच|जाँच/,
  visit: /visit|appointment|come in|clinic|see you|follow.?up|ভিজিট|অ্যাপয়েন্টমেন্ট|আসুন|চলে আসুন|ক্লিনিক|विज़िट|विजिट|अपॉइंटमेंट|आइए|आइये|क्लिनिक/,
  feeling: /how are you|feeling|better|pain|symptom|কেমন আছেন|কেমন লাগছে|ব্যথা|ভালো আছেন|कैसे हैं|कैसा लग|कैसा महसूस|दर्द|बेहतर/,
  hello: /^(hi|hello|hey|namaste|namaskar|good (morning|afternoon|evening))\b|^(নমস্কার|হ্যালো|নমস্তে)|^(नमस्ते|नमस्कार|हैलो)/,
};

// What a tap sends, in the patient's language ({v} values: readings, times).
const SAY = {
  anyUpdate: { en: 'Any update on my message, doctor?', bn: 'আমার মেসেজের কোনো খবর আছে, ডাক্তারবাবু?', hi: 'मेरे संदेश पर कोई जवाब, डॉक्टर?' },
  sugar: {
    en: (v) => `My ${v.kind} today is ${v.value} mg/dL (${v.at}).`,
    bn: (v) => `আজ আমার ${v.kind} ${v.value} mg/dL (${v.at})।`,
    hi: (v) => `आज मेरी ${v.kind} ${v.value} mg/dL है (${v.at})।`,
  },
  sugarKind: {
    en: { fasting: 'fasting sugar', post_meal: 'sugar after food', random: 'sugar' },
    bn: { fasting: 'খালি পেটে সুগার', post_meal: 'খাওয়ার পরে সুগার', random: 'সুগার' },
    hi: { fasting: 'खाली पेट शुगर', post_meal: 'खाने के बाद शुगर', random: 'शुगर' },
  },
  bp: {
    en: (v) => `My BP today is ${v.bp}${v.pulse ? `, pulse ${v.pulse}` : ''} (${v.at}).`,
    bn: (v) => `আজ আমার বিপি ${v.bp}${v.pulse ? `, পালস ${v.pulse}` : ''} (${v.at})।`,
    hi: (v) => `आज मेरा बीपी ${v.bp}${v.pulse ? `, पल्स ${v.pulse}` : ''} है (${v.at})।`,
  },
  allTaken: { en: "I've taken all of today's medicines so far.", bn: 'আজকের সব ওষুধ এখন পর্যন্ত খেয়েছি।', hi: 'आज की सारी दवाइयाँ अब तक ले ली हैं।' },
  missed: {
    en: (v) => `I've missed ${v.n === 1 ? 'a dose' : `${v.n} doses`} today. What should I do?`,
    bn: (v) => `আজ ${v.n === 1 ? 'একটা' : `${v.n}টা`} ডোজ বাদ গেছে। কী করব?`,
    hi: (v) => `आज ${v.n === 1 ? 'एक' : v.n} खुराक छूट गई। क्या करूँ?`,
  },
  late: {
    en: (v) => `I'm running a little late for my ${v.at} visit.`,
    bn: (v) => `আমার ${v.at}-এর ভিজিটে একটু দেরি হচ্ছে।`,
    hi: (v) => `मुझे ${v.at} की विज़िट के लिए थोड़ी देर हो रही है।`,
  },
  helloQuestion: { en: 'Hello doctor, I have a question.', bn: 'নমস্কার ডাক্তারবাবু, আমার একটা প্রশ্ন আছে।', hi: 'नमस्ते डॉक्टर, मेरा एक सवाल है।' },
  aboutMeds: { en: 'I have a question about my medicines.', bn: 'আমার ওষুধ নিয়ে একটা প্রশ্ন আছে।', hi: 'मेरी दवाइयों के बारे में एक सवाल है।' },
  checkSugar: { en: "I haven't checked my sugar today. I'll check and share it.", bn: 'আজ সুগার মাপা হয়নি। মেপে জানাব।', hi: (v) => `आज शुगर नहीं जाँची। जाँचकर ${v.f ? 'बताऊँगी' : 'बताऊँगा'}।` },
  checkBp: { en: "I haven't checked my BP today. I'll check and share it.", bn: 'আজ বিপি মাপা হয়নি। মেপে জানাব।', hi: (v) => `आज बीपी नहीं जाँचा। जाँचकर ${v.f ? 'बताऊँगी' : 'बताऊँगा'}।` },
  onTime: { en: "Yes, I'm taking my medicines on time.", bn: 'হ্যাঁ, সময়মতো ওষুধ খাচ্ছি।', hi: (v) => `हाँ, समय पर दवाइयाँ ले ${v.f ? 'रही' : 'रहा'} हूँ।` },
  sideEffects: { en: 'Could these medicines have side effects?', bn: 'এই ওষুধগুলোর কি কোনো পার্শ্বপ্রতিক্রিয়া হতে পারে?', hi: 'क्या इन दवाइयों के कोई साइड इफ़ेक्ट हो सकते हैं?' },
  shareReport: { en: "I'll share the report here soon.", bn: 'রিপোর্টটা শিগগিরই এখানে পাঠাব।', hi: (v) => `रिपोर्ट जल्दी यहाँ ${v.f ? 'भेजूँगी' : 'भेजूँगा'}।` },
  beThere: { en: (v) => `I'll be there at ${v.at}.`, bn: (v) => `আমি ${v.at}-এ পৌঁছে যাব।`, hi: (v) => `मैं ${v.at} बजे पहुँच ${v.f ? 'जाऊँगी' : 'जाऊँगा'}।` },
  bookVisit: { en: 'Can I book a visit with you?', bn: 'আপনার সঙ্গে কি একটা ভিজিট বুক করতে পারি?', hi: (v) => `क्या मैं आपके साथ विज़िट बुक कर ${v.f ? 'सकती' : 'सकता'} हूँ?` },
  better: { en: "I'm feeling better, thank you.", bn: 'এখন ভালো লাগছে, ধন্যবাদ।', hi: (v) => `अब बेहतर महसूस कर ${v.f ? 'रही' : 'रहा'} हूँ, धन्यवाद।` },
  notWell: { en: "I'm still not feeling well.", bn: 'এখনও ভালো লাগছে না।', hi: 'अभी भी ठीक महसूस नहीं हो रहा।' },
  yes: { en: 'Yes.', bn: 'হ্যাঁ।', hi: 'हाँ।' },
  no: { en: 'No.', bn: 'না।', hi: 'नहीं।' },
  hello: { en: 'Hello doctor.', bn: 'নমস্কার ডাক্তারবাবু।', hi: 'नमस्ते डॉक्टर।' },
  question: { en: 'I have a question.', bn: 'আমার একটা প্রশ্ন আছে।', hi: 'मेरा एक सवाल है।' },
  thanks: { en: 'Thank you, doctor.', bn: 'ধন্যবাদ, ডাক্তারবাবু।', hi: 'धन्यवाद, डॉक्टर।' },
};

/**
 * @param convo  the care thread
 * @param items  its messages, oldest first (as shown to the patient)
 * @param lang   the patient's app language (en | bn | hi)
 * @returns [{ label, text }] — at most 3
 */
async function patientSuggestions(convo, items, lang) {
  if (!convo.patientId) return [];
  const p = await M.Patient.findById(convo.patientId, 'userId gender');
  if (!lang) lang = p?.userId ? (await M.User.findById(p.userId, 'language'))?.language : 'en';
  const L = ['bn', 'hi'].includes(lang) ? lang : 'en';
  // Hindi first-person verbs follow the speaker's gender ("बताऊँगा" / "बताऊँगी").
  const f = p?.gender === 'female';
  const say = (key, v = {}) => (typeof SAY[key][L] === 'function' ? SAY[key][L]({ ...v, f }) : SAY[key][L]);
  const visible = items.filter((m) => !m.deletedForEveryoneAt && !(m.senderType === 'system' && m.meta?.away));
  const last = visible[visible.length - 1];
  // Waiting on the clinic: nothing to suggest, except a nudge once a few hours have passed.
  if (last && last.senderType === 'patient') {
    return Date.now() - new Date(last.createdAt).getTime() > 3 * 3600e3 ? [{ label: 'Any update?', text: say('anyUpdate') }] : [];
  }
  const today = T.dayStart();
  const tomorrow = T.addDays(today, 1);
  const [sugar, bp, doses, visit] = await Promise.all([
    M.Vitals.findOne({ patientId: convo.patientId, bloodSugar: { $ne: null }, recordedAt: { $gte: today, $lt: tomorrow } }).sort({ recordedAt: -1 }),
    M.Vitals.findOne({ patientId: convo.patientId, bpSystolic: { $ne: null }, recordedAt: { $gte: today, $lt: tomorrow } }).sort({ recordedAt: -1 }),
    M.DoseLog.find({ patientId: convo.patientId, scheduledAt: { $gte: today, $lte: new Date() } }, 'status'),
    M.Appointment.findOne({ patientId: convo.patientId, practiceId: convo.practiceId, startAt: { $gte: new Date(Date.now() - 30 * 60e3), $lt: tomorrow }, status: { $in: ['booked', 'confirmed'] } }).sort({ startAt: 1 }),
  ]);
  const at = (d) => T.fmtTime(T.minuteOfDay(d));
  const sugarReply = sugar
    ? { label: "Share today's sugar", text: say('sugar', { kind: SAY.sugarKind[L][sugar.sugarType] || SAY.sugarKind[L].random, value: sugar.bloodSugar, at: at(sugar.recordedAt) }) }
    : null;
  const bpReply = bp ? { label: "Share today's BP", text: say('bp', { bp: `${bp.bpSystolic}/${bp.bpDiastolic}`, pulse: bp.pulse, at: at(bp.recordedAt) }) } : null;
  const due = doses.length;
  const taken = doses.filter((d) => d.status === 'taken').length;
  const medsReply = due
    ? taken === due ? { label: 'Taken my medicines', text: say('allTaken') } : { label: 'Missed a dose', text: say('missed', { n: due - taken }) }
    : null;
  // "Running late" only close to the visit (within 3 hours of it).
  const late = visit && new Date(visit.startAt).getTime() - Date.now() < 3 * 3600e3 ? { label: 'Running late', text: say('late', { at: at(visit.startAt) }) } : null;

  const t = last?.text || '';
  const out = [];
  const add = (...xs) => { for (const x of xs) if (x && out.length < 3 && !out.some((o) => o.label === x.label)) out.push(x); };
  if (!last) {
    add({ label: 'Hello doctor', text: say('helloQuestion') }, { label: 'About my medicines', text: say('aboutMeds') }, sugarReply || bpReply);
    return out;
  }
  // What the message is about comes first.
  if (has(t, TOPIC.sugar)) add(sugarReply || { label: "I'll check my sugar", text: say('checkSugar') });
  if (has(t, TOPIC.bp)) add(bpReply || { label: "I'll check my BP", text: say('checkBp') });
  if (has(t, TOPIC.meds)) add(medsReply || { label: 'Taking them on time', text: say('onTime') }, { label: 'Any side effects?', text: say('sideEffects') });
  if (has(t, TOPIC.report)) add({ label: "I'll share the report", text: say('shareReport') });
  if (has(t, TOPIC.visit)) add(late, visit ? { label: "I'll be there", text: say('beThere', { at: at(visit.startAt) }) } : { label: 'Book a visit', text: say('bookVisit') });
  if (has(t, TOPIC.feeling)) add({ label: 'Feeling better', text: say('better') }, { label: 'Still not well', text: say('notWell') });
  if (/[?？]\s*$/.test(t) && !out.length) add({ label: 'Yes', text: say('yes') }, { label: 'No', text: say('no') });
  if (has(t.trim(), TOPIC.hello)) add({ label: 'Hello doctor', text: say('hello') }, { label: 'I have a question', text: say('question') });
  // Then thanks, and what's true today.
  add({ label: 'Thank you', text: say('thanks') }, late, sugarReply, bpReply);
  return out;
}

module.exports = { patientSuggestions };

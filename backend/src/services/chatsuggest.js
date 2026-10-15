// Quick replies under the patient's chat (Patient-DoctorChat): picked from the
// newest message the care team sent and the patient's own day — today's sugar
// and BP readings, today's doses, a visit today — so a tap sends something
// true ("My fasting sugar today is 132 mg/dL (8:10 AM)."), never a placeholder.
const M = require('../models');
const T = require('../lib/time');

const has = (text, re) => re.test(String(text || '').toLowerCase());
const SUGAR_LABEL = { fasting: 'fasting sugar', post_meal: 'sugar after food', random: 'sugar' };

/**
 * @param convo  the care thread
 * @param items  its messages, oldest first (as shown to the patient)
 * @returns [{ label, text }] — at most 3
 */
async function patientSuggestions(convo, items) {
  if (!convo.patientId) return [];
  const visible = items.filter((m) => !m.deletedForEveryoneAt && !(m.senderType === 'system' && m.meta?.away));
  const last = visible[visible.length - 1];
  // Waiting on the clinic: nothing to suggest, except a nudge once a few hours have passed.
  if (last && last.senderType === 'patient') {
    return Date.now() - new Date(last.createdAt).getTime() > 3 * 3600e3 ? [{ label: 'Any update?', text: 'Any update on my message, doctor?' }] : [];
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
    ? { label: "Share today's sugar", text: `My ${SUGAR_LABEL[sugar.sugarType] || 'sugar'} today is ${sugar.bloodSugar} mg/dL (${at(sugar.recordedAt)}).` }
    : null;
  const bpReply = bp
    ? { label: "Share today's BP", text: `My BP today is ${bp.bpSystolic}/${bp.bpDiastolic}${bp.pulse ? `, pulse ${bp.pulse}` : ''} (${at(bp.recordedAt)}).` }
    : null;
  const due = doses.length;
  const taken = doses.filter((d) => d.status === 'taken').length;
  const medsReply = due
    ? taken === due
      ? { label: 'Taken my medicines', text: "I've taken all of today's medicines so far." }
      : { label: 'Missed a dose', text: `I've missed ${due - taken === 1 ? 'a dose' : `${due - taken} doses`} today. What should I do?` }
    : null;
  // "Running late" only close to the visit (within 3 hours of it).
  const late = visit && new Date(visit.startAt).getTime() - Date.now() < 3 * 3600e3 ? { label: 'Running late', text: `I'm running a little late for my ${at(visit.startAt)} visit.` } : null;

  const t = last?.text || '';
  const out = [];
  const add = (...xs) => { for (const x of xs) if (x && out.length < 3 && !out.some((o) => o.label === x.label)) out.push(x); };
  if (!last) {
    add({ label: 'Hello doctor', text: 'Hello doctor, I have a question.' }, { label: 'About my medicines', text: 'I have a question about my medicines.' }, sugarReply || bpReply);
    return out;
  }
  // What the message is about comes first.
  if (has(t, /sugar|glucose|fasting|hba1c|diabet/)) add(sugarReply || { label: "I'll check my sugar", text: "I haven't checked my sugar today. I'll check and share it." });
  if (has(t, /\bbp\b|pressure/)) add(bpReply || { label: "I'll check my BP", text: "I haven't checked my BP today. I'll check and share it." });
  if (has(t, /medicine|tablet|dose|pill|taking|insulin/)) add(medsReply || { label: 'Taking them on time', text: "Yes, I'm taking my medicines on time." }, { label: 'Any side effects?', text: 'Could these medicines have side effects?' });
  if (has(t, /report|test|lab|scan|x-ray|result/)) add({ label: "I'll share the report", text: "I'll share the report here soon." });
  if (has(t, /visit|appointment|come in|clinic|see you|follow.?up/)) add(late, visit ? { label: "I'll be there", text: `I'll be there at ${at(visit.startAt)}.` } : { label: 'Book a visit', text: 'Can I book a visit with you?' });
  if (has(t, /how are you|feeling|better|pain|symptom/)) add({ label: 'Feeling better', text: "I'm feeling better, thank you." }, { label: 'Still not well', text: "I'm still not feeling well." });
  if (has(t, /\?\s*$/) && !out.length) add({ label: 'Yes', text: 'Yes.' }, { label: 'No', text: 'No.' });
  if (has(t, /^(hi|hello|hey|namaste|good (morning|afternoon|evening))\b/)) add({ label: 'Hello doctor', text: 'Hello doctor.' }, { label: 'I have a question', text: 'I have a question.' });
  // Then thanks, and what's true today.
  add({ label: 'Thank you', text: 'Thank you, doctor.' }, late, sugarReply, bpReply);
  return out;
}

module.exports = { patientSuggestions };

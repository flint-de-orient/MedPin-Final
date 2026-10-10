// What the doctor's AI assistant knows about the practice beyond one patient:
// small lists drawn from this clinic's own records (abnormal results, medicines
// running out, missed doses, follow-ups, last week's numbers), and the patients
// a question mentions by name. Kept short (≤ 15 rows a list) so every question
// can carry it.
const M = require('../models');
const T = require('../lib/time');

const nameOf = (p) => p?.name || 'Patient';

async function practiceBrief(userId, practiceId) {
  const now = new Date();
  const today = T.dayStart(now);
  const weekAgo = T.addDays(today, -7);
  const inWeek = T.addDays(today, 8);
  const patientIds = await M.PatientEnrolment.find({ practiceId, status: 'linked' }).distinct('patientId');
  const doctorIds = await M.Member.find({ practiceId, role: 'doctor', status: 'active' }).distinct('userId');

  const [labs, ending, doses, followUps, seen, newPatients, paid] = await Promise.all([
    M.LabResult.find({ practiceId, collectedAt: { $gte: weekAgo }, abnormalCount: { $gt: 0 } }).sort({ collectedAt: -1 }).limit(15).populate('patientId', 'name'),
    M.MedicationCourse.find({ patientId: { $in: patientIds }, doctorId: { $in: doctorIds }, status: 'active', endDate: { $gte: today, $lt: inWeek } }).sort({ endDate: 1 }).limit(15).populate('patientId', 'name'),
    M.DoseLog.aggregate([
      { $match: { patientId: { $in: patientIds }, scheduledAt: { $gte: weekAgo, $lt: now } } },
      { $group: { _id: '$patientId', total: { $sum: 1 }, taken: { $sum: { $cond: [{ $eq: ['$status', 'taken'] }, 1, 0] } } } },
      { $match: { total: { $gte: 3 } } },
      { $project: { total: 1, taken: 1, pct: { $round: [{ $multiply: [{ $divide: ['$taken', '$total'] }, 100] }, 0] } } },
      { $sort: { pct: 1 } },
      { $limit: 10 },
    ]),
    M.FollowUp.find({ practiceId, doctorId: userId, status: 'not_booked', dueDate: { $gte: weekAgo, $lt: inWeek } }).sort({ dueDate: 1 }).limit(15).populate('patientId', 'name'),
    M.Appointment.countDocuments({ practiceId, doctorId: userId, status: 'completed', date: { $gte: weekAgo, $lt: today } }),
    M.PatientEnrolment.countDocuments({ practiceId, linkedAt: { $gte: weekAgo } }),
    M.Payment.aggregate([{ $match: { practiceId, status: 'paid', paidAt: { $gte: weekAgo, $lt: today } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
  ]);
  const adherencePatients = new Map((await M.Patient.find({ _id: { $in: doses.map((d) => d._id) } }, 'name')).map((p) => [String(p._id), p.name]));

  return {
    abnormal_results_last_7_days: labs.map((l) => ({
      patient: nameOf(l.patientId), test: l.testName, date: T.dayKey(l.collectedAt),
      values: l.values.filter((v) => v.flag && v.flag !== 'normal').map((v) => `${v.analyte} ${v.value ?? v.valueText ?? ''} ${v.unit || ''} (${v.flag})`.replace(/\s+/g, ' ').trim()),
    })),
    medicines_ending_next_7_days: ending.map((c) => ({ patient: nameOf(c.patientId), medicine: `${c.name} ${c.strength || ''}`.trim(), ends: T.dayKey(c.endDate) })),
    lowest_medicine_adherence_last_7_days: doses.map((d) => ({ patient: adherencePatients.get(String(d._id)) || 'Patient', taken: d.taken, of: d.total, percent: d.pct })),
    my_follow_ups_due: followUps.map((f) => ({ patient: nameOf(f.patientId), due: T.dayKey(f.dueDate), overdue: f.dueDate < today })),
    last_7_days: { my_completed_visits: seen, new_patients_in_clinic: newPatients, fees_collected_rupees: paid[0]?.total || 0 },
  };
}

/**
 * Patients of this practice the question names ("Priya", "Priya Sharma",
 * "@Rahul Das"): full-name matches first, else a unique first-name match.
 */
async function patientsMentioned(question, practiceId, limit = 2) {
  const q = ` ${String(question || '').toLowerCase().replace(/[^a-zঀ-৿ऀ-ॿ\s]/g, ' ')} `;
  if (q.trim().length < 3) return [];
  const ids = await M.PatientEnrolment.find({ practiceId, status: 'linked' }).distinct('patientId');
  const patients = await M.Patient.find({ _id: { $in: ids } }, 'name').limit(2000);
  const full = patients.filter((p) => p.name && q.includes(` ${p.name.toLowerCase()} `));
  const fullFirsts = new Set(full.map((p) => p.name.toLowerCase().split(/\s+/)[0]));
  const byFirst = new Map();
  for (const p of patients) {
    const first = String(p.name || '').toLowerCase().split(/\s+/)[0];
    if (first.length < 3 || fullFirsts.has(first) || !q.includes(` ${first} `)) continue;
    byFirst.set(first, [...(byFirst.get(first) || []), p]);
  }
  // A first name counts only when it means one patient here (otherwise it's ambiguous).
  const single = [...byFirst.values()].filter((list) => list.length === 1).map((list) => list[0]);
  return [...full, ...single].slice(0, limit);
}

module.exports = { practiceBrief, patientsMentioned };

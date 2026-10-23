// Who in a clinic may see which parts of a patient's record.
//
// A clinic always sees what it created itself (its visits, prescriptions,
// vitals, lab results and uploads). Everything else — other clinics' records
// and what the patient uploaded or logged at home — is visible only as far as
// the patient allows, per care-team member ("Who can see my records"), or
// when that item was shared directly with someone at this clinic.
//
//   not_shared              → only this clinic's own data
//   daily_log_only          → + home readings and daily logs
//   prescriptions_and_tests → + prescriptions, lab results, medicines from elsewhere
//   full_record             → + every record, clinic vitals and visits from elsewhere
//   full_with_logs          → everything
//
// Allergies and conditions are always visible to a linked clinic (safety).
const M = require('../models');

const RANK = { not_shared: 0, daily_log_only: 1, prescriptions_and_tests: 2, full_record: 3, full_with_logs: 4 };
const same = (a, b) => String(a) === String(b);

/**
 * The access a staff member (userId in practiceId) has to a patient.
 * Uses their own "Who can see my records" row; staff without one (front desk)
 * get the most the patient allows anyone at this clinic.
 */
async function accessFor({ userId, practiceId }, patient) {
  const members = await M.Member.find({ practiceId, status: 'active' }, 'userId role');
  const memberIds = members.map((m) => m.userId);
  const me = members.find((m) => same(m.userId, userId));
  // Clinical staff (doctors, their assistants, the dietician) share their clinic's view;
  // the front desk, practice manager and lab staff see only what is shared with them.
  const clinical = Boolean(me && M.ROLE_PERMISSIONS[me.role]?.clinical);
  const rows = await M.CareTeamAccess.find({ patientId: patient._id, userId: { $in: [...memberIds, userId] } });
  const mine = rows.find((r) => same(r.userId, userId));
  let level;
  if (mine) level = mine.accessLevel;
  else if (rows.length) level = rows.reduce((best, r) => (RANK[r.accessLevel] > RANK[best] ? r.accessLevel : best), 'not_shared');
  else {
    const enrolment = await M.PatientEnrolment.findOne({ patientId: patient._id, practiceId, status: 'linked' });
    level = enrolment?.shareScope === 'partial' ? 'prescriptions_and_tests' : 'full_record';
  }
  // Staff without their own row don't inherit a doctor's full access: at most prescriptions and tests.
  if (!mine && !clinical && RANK[level] > RANK.prescriptions_and_tests) level = 'prescriptions_and_tests';
  const allows = (min) => RANK[level] >= RANK[min];
  const memberSet = new Set(memberIds.map(String));
  const ownPractice = { practiceId };
  // Another clinic's records (follow the sharing level). The patient's own uploads (no clinic)
  // are NOT in here: those are seen only where the patient shared them.
  const elsewhere = { practiceId: { $nin: [practiceId, null] } };
  // "Shared with someone here": with this person; for clinical staff, with anyone at this clinic.
  const sharedHere = clinical ? { 'sharedWith.userId': { $in: memberIds } } : { 'sharedWith.userId': userId };

  return {
    level,
    allows,
    memberIds,
    isMember: (id) => id != null && memberSet.has(String(id)),

    /** Medical records (uploads): own, shared with someone here, or allowed by level. */
    async recordFilter() {
      const or = [ownPractice, sharedHere];
      if (allows('full_record')) or.push(elsewhere);
      else if (allows('prescriptions_and_tests')) or.push({ ...elsewhere, kind: { $in: ['prescription', 'test_result'] } });
      return { $or: or };
    },

    /** Lab results: own, from a record shared here, or allowed by level. */
    async labFilter() {
      const shared = await M.MedicalRecord.distinct('_id', { patientId: patient._id, deletedAt: null, ...sharedHere });
      const or = [ownPractice, { recordId: { $in: shared } }];
      if (allows('prescriptions_and_tests')) or.push(elsewhere);
      return { $or: or };
    },

    /** Prescriptions issued or filed elsewhere. */
    rxFilter() {
      return allows('prescriptions_and_tests') ? {} : ownPractice;
    },

    /** Vitals: clinic vitals from elsewhere need full_record; home readings need a logs level. */
    vitalsFilter() {
      const or = [ownPractice];
      if (allows('full_record')) or.push({ ...elsewhere, source: { $ne: 'home' } });
      // Readings taken from lab reports follow the lab results' rule ("prescriptions and tests").
      else if (allows('prescriptions_and_tests')) or.push({ ...elsewhere, source: 'lab' });
      // Home and watch readings have no clinic: they follow the "daily logs" levels.
      if (level === 'full_with_logs' || level === 'daily_log_only') or.push({ practiceId: { $ne: practiceId }, source: { $in: ['home', 'device'] } });
      return { $or: or };
    },

    /** Medicine courses prescribed by doctors outside this clinic (or added by the patient). */
    courseVisible(course) {
      return this.isMember(course.doctorId) || allows('prescriptions_and_tests');
    },

    /** Visits / diagnoses from other clinics. */
    consultationFilter() {
      return allows('full_record') ? {} : ownPractice;
    },
  };
}

module.exports = { accessFor, RANK };

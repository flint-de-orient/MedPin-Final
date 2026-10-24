// What the clinic's chat assistant may tell a patient as fact, read fresh for every reply:
// the time now in India and whether the branch is open; the doctor's sittings this week
// (leave, half days and closures taken out) and why a day is off; their fees; branch
// address and phone; the doctor running late today; this patient's upcoming visits (time,
// token, fee paid or not) and unpaid fees; and, for a family member, who is writing.
// Anything not listed here the assistant must not state (the desk confirms it).
const M = require('../models');
const T = require('../lib/time');

const WD = { mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat', sun: 'Sun' };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dayLabel = (d) => {
  const [, m, dd] = T.dayKey(d).split('-');
  return `${WD[T.weekday(d)]} ${Number(dd)} ${MON[Number(m) - 1]}`;
};
const at = (d) => `${dayLabel(d)}, ${T.fmtTime(T.minuteOfDay(d))}`;
const range = (s, e) => (+T.dayStart(s) === +T.dayStart(e) ? dayLabel(s) : `${dayLabel(s)} – ${dayLabel(e)}`);

async function clinicFacts({ practiceId, patient, doctorId, now = new Date() }) {
  const { patientPlace } = require('./notify');
  const { openNow } = require('./care');
  const { sessionsOn } = require('./presence');
  const place = await patientPlace(practiceId, patient._id);
  const facts = { now_in_india: at(now) };

  const branch = place.locationId ? await M.Location.findById(place.locationId, 'name address city pincode phone patientPhone weeklyHours') : null;
  if (branch) {
    facts.branch = { name: branch.name, address: [branch.address, branch.city, branch.pincode].filter(Boolean).join(', ') || null, phone: branch.patientPhone || branch.phone || null };
    facts.branch_open_now = await openNow(branch._id);
  }

  if (doctorId) {
    const [doctor, dls] = await Promise.all([
      M.User.findById(doctorId, 'name'),
      M.DoctorLocation.find({ doctorId, practiceId, status: 'active' }).populate('locationId', 'name shortName status weeklyHours'),
    ]);
    const week = [];
    for (let i = 0; i < 7; i += 1) {
      const day = T.addDays(T.dayStart(now), i);
      const s = await sessionsOn(doctorId, day, dls);
      week.push(`${dayLabel(day)}: ${s.length ? s.map((x) => `${T.fmtTime(x.startMin)}–${T.fmtTime(x.endMin)}${dls.length > 1 ? ` (${x.locationName})` : ''}`).join(', ') : 'not sitting'}`);
    }
    const until = T.addDays(T.dayStart(now), 21);
    const [leaves, closures] = await Promise.all([
      M.DoctorLeave.find({ doctorId, cancelledAt: null, endDate: { $gte: T.dayStart(now) }, startDate: { $lt: until } }).sort({ startDate: 1 }).limit(5),
      M.LocationClosure.find({ locationId: { $in: dls.map((d) => d.locationId?._id).filter(Boolean) }, endDate: { $gte: T.dayStart(now) }, startDate: { $lt: until } }).sort({ startDate: 1 }).limit(5),
    ]);
    facts.doctor = {
      name: doctor?.name,
      sittings_next_7_days: week,
      away: leaves.map((l) => `${l.fromMin == null ? 'On leave' : l.fromMin === 0 ? 'Morning off (until 1 PM)' : 'Afternoon off (from 1 PM)'} ${range(l.startDate, l.endDate)}`),
      fees: [...new Map(dls.flatMap((d) => (d.services || []).filter((s) => s.fee != null).map((s) => [s.name, `${s.name}: ₹${s.fee}`]))).values()].slice(0, 6),
    };
    const names = new Map(dls.map((d) => [String(d.locationId?._id), d.locationId?.shortName || d.locationId?.name]));
    if (closures.length) facts.clinic_closed = closures.map((c) => `${names.get(String(c.locationId)) || 'Clinic'} closed ${range(c.startDate, c.endDate)}${c.allDay === false && c.fromMin != null ? ` ${T.fmtTime(c.fromMin)}–${T.fmtTime(c.toMin)}` : ''} (${c.reason})`);
    // "Running late" told to patients today.
    const late = patient.userId && await M.Notification.findOne({ userId: patient.userId, type: 'running_late', createdAt: { $gte: T.dayStart(now) } }, 'title body createdAt').sort({ createdAt: -1 });
    if (late) facts.running_late_today = `${late.title}${late.body ? ` · ${late.body}` : ''} (told at ${T.fmtTime(T.minuteOfDay(late.createdAt))})`;
  }

  const visits = await M.Appointment.find({ practiceId, patientId: patient._id, startAt: { $gte: T.addMinutes(now, -180) }, status: { $in: ['booked', 'confirmed', 'waiting', 'in_consultation'] } })
    .sort({ startAt: 1 }).limit(3).populate('doctorId', 'name').populate('locationId', 'name shortName');
  facts.patient_upcoming_visits = visits.map((a) => ({
    when: at(a.startAt), doctor: a.doctorId?.name, branch: a.locationId?.shortName || a.locationId?.name,
    token: a.tokenNo ? String(a.tokenNo).padStart(2, '0') : undefined, status: a.status,
    fee: a.feeStatus === 'paid' ? 'paid' : a.feeStatus === 'pending' ? `not paid yet${a.payAt === 'clinic' ? ' (paying at the clinic)' : ' (can pay online in the app)'}` : a.feeStatus,
  }));
  const unpaid = await M.Payment.find({ practiceId, patientId: patient._id, status: 'pending' }, 'amount');
  if (unpaid.length) facts.unpaid_fees = { count: unpaid.length, total: `₹${unpaid.reduce((s, p) => s + (p.amount || 0), 0)}` };

  if (patient.familyOf) {
    const holder = await M.Patient.findById(patient.familyOf, 'name');
    facts.chat_is_about = `${patient.name}${patient.relation ? ` (${holder?.name || 'the account holder'}'s ${patient.relation})` : ''}; the messages are written by ${holder?.name || 'a family member'} on their phone`;
  }
  return facts;
}

module.exports = { clinicFacts };

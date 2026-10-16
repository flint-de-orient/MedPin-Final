// Slots, tokens, booking and appointment status transitions.
const M = require('../models');
const T = require('../lib/time');
const { badRequest, conflict, notFound } = require('../lib/http');
const { notify, practiceStaff } = require('./notify');

const ACTIVE = { $nin: ['cancelled', 'rescheduled'] };

/** Bookable slots for one doctor at one location on one day. */
async function slotsFor({ doctorId, locationId, day, now = new Date() }) {
  const d = T.dayStart(day);
  const dl = await M.DoctorLocation.findOne({ doctorId, locationId, status: 'active' });
  if (!dl) return { open: false, reason: 'not_practising_here', slots: [] };
  const location = await M.Location.findById(locationId);
  if (!location || location.status !== 'active') return { open: false, reason: 'location_inactive', slots: [] };
  const end = T.addDays(d, 1);
  // Closed all day, or for part of the day (those slots go; the rest stay bookable).
  const closures = await M.LocationClosure.find({ locationId, startDate: { $lt: end }, endDate: { $gte: d } });
  const closure = closures.find((c) => c.allDay !== false || c.fromMin == null || c.toMin == null);
  if (closure) return { open: false, reason: 'closed', note: closure.reason, slots: [] };
  const partClosed = (t, len) => closures.some((c) => t < c.toMin && t + len > c.fromMin);
  const leave = await M.DoctorLeave.findOne({
    doctorId, cancelledAt: null, startDate: { $lt: end }, endDate: { $gte: d },
    $or: [{ locationId: null }, { locationId }],
  });
  if (leave) return { open: false, reason: 'doctor_on_leave', note: leave.reason, slots: [] };

  const s = dl.schedule;
  const sessions = (s.week.find((w) => w.weekday === T.weekday(d)) || {}).sessions || [];
  if (!sessions.length) return { open: false, reason: 'no_session', slots: [] };
  const step = s.slotLengthMin + (s.breakBetweenMin || 0);
  // Only while the clinic is open that day (its weekly hours), when hours are set.
  const hours = (location.weeklyHours || []).find((h) => h.weekday === T.weekday(d));
  if (hours && hours.isOpen === false) return { open: false, reason: 'clinic_closed', slots: [] };
  const opens = hours?.opensAt ?? 0;
  const closes = hours?.closesAt ?? 24 * 60;
  const minutes = [];
  for (const { startMin, endMin } of sessions) {
    for (let t = Math.max(startMin, opens); t + s.slotLengthMin <= Math.min(endMin, closes); t += step) {
      if (!partClosed(t, s.slotLengthMin)) minutes.push(t);
    }
  }
  if (!minutes.length) return { open: false, reason: 'clinic_closed', slots: [] };
  const walkIns = new Set(minutes.slice(Math.max(0, minutes.length - (s.walkInPlaces || 0))));
  const booked = await M.Appointment.aggregate([
    { $match: { doctorId: dl.doctorId, locationId: dl.locationId, date: d, status: ACTIVE } },
    { $group: { _id: '$startAt', n: { $sum: 1 } } },
  ]);
  const count = new Map(booked.map((b) => [new Date(b._id).getTime(), b.n]));
  const slots = minutes.map((minute) => {
    const startAt = T.atMinute(d, minute);
    const n = count.get(startAt.getTime()) || 0;
    return {
      minute,
      time: T.fmtTime(minute),
      startAt,
      booked: n,
      walkIn: walkIns.has(minute),
      available: n < s.patientsPerSlot && startAt > now,
    };
  });
  return { open: true, slotLengthMin: s.slotLengthMin, patientsPerSlot: s.patientsPerSlot, slots };
}

/** First online-bookable slot within `days` days. */
async function nextFreeSlot({ doctorId, locationId, from = new Date(), days = 7 }) {
  for (let i = 0; i < days; i += 1) {
    const day = T.addDays(T.dayStart(from), i);
    const { slots } = await slotsFor({ doctorId, locationId, day, now: from });
    const free = slots.find((x) => x.available && !x.walkIn);
    if (free) return { day, ...free };
  }
  return null;
}

/** Next queue token for a location's day; never reuses a number already on the list. */
async function nextToken(locationId, day) {
  const key = `token:${locationId}:${T.dayKey(day)}`;
  const top = await M.Appointment.findOne({ locationId, date: T.dayStart(day), tokenNo: { $type: 'number' } }).sort({ tokenNo: -1 }).select('tokenNo');
  if (top) await M.Counter.updateOne({ _id: key }, { $max: { seq: top.tokenNo } }, { upsert: true });
  return M.Counter.next(key);
}

/** Fee for a visit from the doctor's services at that location. */
async function feeFor(dl, { visitType, mode, patientId }) {
  const services = dl.services || [];
  const svc =
    services.find((x) => x.visitType === visitType && (x.mode || 'in_clinic') === mode) ||
    services.find((x) => x.visitType === visitType) ||
    services.find((x) => (x.mode || 'in_clinic') === mode && x.visitType === 'new') ||
    services[0];
  if (!svc) return { fee: 0, serviceName: undefined };
  if (svc.freeWithinDays) {
    const since = T.addDays(new Date(), -svc.freeWithinDays);
    const recent = await M.Appointment.exists({
      patientId, doctorId: dl.doctorId, status: 'completed', completedAt: { $gte: since },
    });
    if (recent) return { fee: 0, serviceName: svc.name };
  }
  return { fee: svc.fee || 0, serviceName: svc.name };
}

/** Books an appointment (front desk, doctor, or patient request assignment). */
/** "Mon, 19 Oct · 11:30 AM with Dr. Arjun Sen at City Care — Salt Lake · token 01" for chat notes. */
async function visitLine(appt) {
  const [doctor, loc] = await Promise.all([M.User.findById(appt.doctorId, 'name'), M.Location.findById(appt.locationId, 'name shortName')]);
  const d = new Date(appt.startAt.getTime() + T.IST_MS);
  const day = `${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getUTCDay()]}, ${d.getUTCDate()} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.getUTCMonth()]}`;
  return `${day} · ${T.fmtTime(T.minuteOfDay(appt.startAt))}${doctor ? ` with ${doctor.name}` : ''}${loc ? ` at ${loc.name}` : ''}${appt.tokenNo ? ` · token ${String(appt.tokenNo).padStart(2, '0')}` : ''}`;
}

const note = (...args) => require('./care').chatNote(...args);

/**
 * A visit was booked, moved, cancelled or changed status: a silent push to the
 * doctor, the desk at that location and the patient, so every open list
 * (Appointments, Today, the queue, the patient's visit) refreshes at once.
 */
async function visitsChanged(appt) {
  try {
    const { signal, DESK_ROLES } = require('./notify');
    const [desk, patient] = await Promise.all([
      practiceStaff(appt.practiceId, { roles: DESK_ROLES, locationId: appt.locationId }),
      M.Patient.findById(appt.patientId, 'userId'),
    ]);
    await signal([appt.doctorId, ...desk, patient?.userId], { type: 'visits_changed', appointmentId: appt._id });
  } catch (err) {
    console.warn('[visits changed]', err.message);
  }
}

async function book(input) {
  const {
    practiceId, locationId, doctorId, patientId, visitType = 'follow_up', mode = 'in_clinic', reason,
    channel = 'desk', bookedBy, requestId, walkIn = false,
    confirmed = false, // the front desk agreed the time with the patient
    chat = true, // a "Visit booked" note in the patient's chat (a reschedule writes its own)
  } = input;
  const startAt = walkIn ? new Date(input.startAt || Date.now()) : new Date(input.startAt);
  if (Number.isNaN(startAt.getTime())) throw badRequest('Choose a time first', 'TIME_REQUIRED');
  const dl = await M.DoctorLocation.findOne({ doctorId, locationId, practiceId, status: 'active' });
  if (!dl) throw badRequest("The doctor doesn't practise at this location", 'NOT_PRACTISING_HERE');
  const day = T.dayStart(startAt);

  if (!walkIn) {
    const { open, reason: why, slots } = await slotsFor({ doctorId, locationId, day });
    if (!open) throw conflict(`No session that day (${why})`, 'NO_SESSION');
    const slot = slots.find((x) => x.startAt.getTime() === startAt.getTime());
    if (!slot) throw badRequest('That time is not a slot in the schedule', 'NOT_A_SLOT');
    if (!slot.available) throw conflict('That slot is already taken', 'SLOT_TAKEN');
    if (channel === 'app' && slot.walkIn) throw conflict('That slot is kept for walk-ins', 'WALK_IN_SLOT');
  }

  const { fee, serviceName } = await feeFor(dl, { visitType, mode, patientId });
  const appt = await M.Appointment.create({
    practiceId, locationId, doctorId, patientId, requestId,
    date: day, startAt, endAt: T.addMinutes(startAt, dl.schedule.slotLengthMin),
    tokenNo: await nextToken(locationId, day),
    isWalkIn: walkIn, visitType, mode, reason, serviceName, channel, bookedBy,
    status: walkIn ? 'waiting' : confirmed ? 'confirmed' : 'booked', arrivedAt: walkIn ? new Date() : undefined,
    fee, feeStatus: fee > 0 ? 'pending' : 'free',
  });
  if (fee > 0) {
    await M.Payment.create({ practiceId, locationId, patientId, appointmentId: appt._id, amount: fee, status: 'pending' });
  }
  if (visitType === 'follow_up') {
    await M.FollowUp.findOneAndUpdate(
      { practiceId, patientId, status: { $in: ['not_booked', 'no_reply'] } },
      { status: 'booked', appointmentId: appt._id },
      { sort: { dueDate: 1 } },
    );
  }
  const patient = await M.Patient.findById(patientId, 'userId name');
  if (patient?.userId && !walkIn) {
    await notify([patient.userId], {
      type: 'appointment_booked', practiceId,
      title: confirmed ? 'Visit confirmed' : 'Visit booked',
      body: `${T.fmtTime(T.minuteOfDay(startAt))}, ${T.dayKey(startAt)} · Token ${String(appt.tokenNo).padStart(2, '0')}`,
      screen: 'Patient-DoctorDetail', params: { appointmentId: appt._id }, whatsapp: true,
    });
  }
  if (chat && !walkIn) {
    const feeText = fee > 0 ? ` Fee ₹${fee} — pay online in the app or at the clinic.` : '';
    await note({ practiceId, patientId, locationId, doctorId, by: bookedBy }, `${confirmed ? 'Visit confirmed' : 'Visit booked'}: ${await visitLine(appt)}.${feeText}`, confirmed ? 'visit_confirmed' : 'visit_booked');
  }
  await visitsChanged(appt);
  return appt;
}

// Physical visits: booked → arrived (waiting) → with the doctor → done. "Done" can
// follow arrival directly (a paper prescription, a quick review); a check-in made
// by mistake goes back to booked; someone who left before being seen is "missed".
const TRANSITIONS = {
  booked: ['confirmed', 'waiting', 'missed', 'cancelled'],
  confirmed: ['waiting', 'missed', 'cancelled'],
  waiting: ['in_consultation', 'completed', 'missed', 'cancelled', 'booked'],
  in_consultation: ['completed', 'waiting'],
  completed: [],
  missed: ['waiting'],
  cancelled: [],
  rescheduled: [],
};

/** Moves an appointment along the queue. */
async function transition(appt, to, { by, cancelledBy, reason } = {}) {
  if (!(TRANSITIONS[appt.status] || []).includes(to)) {
    throw conflict(`Can't change a ${appt.status.replace('_', ' ')} appointment to ${to.replace('_', ' ')}`, 'BAD_TRANSITION');
  }
  const now = new Date();
  appt.status = to;
  if (to === 'confirmed') appt.confirmedAt = now;
  if (to === 'waiting') { appt.arrivedAt = appt.arrivedAt || now; appt.checkedInBy = by; }
  if (to === 'booked') { appt.arrivedAt = undefined; appt.checkedInBy = undefined; } // check-in undone
  if (to === 'in_consultation') appt.consultStartedAt = appt.consultStartedAt || now;
  if (to === 'missed') appt.missedAt = now;
  if (to === 'completed') appt.completedAt = now;
  if (to === 'cancelled') {
    appt.cancelledAt = now;
    appt.cancelledBy = cancelledBy || 'desk';
    appt.cancelReason = reason;
    if (by) appt.cancelledByUser = by;
    await M.Payment.updateMany({ appointmentId: appt._id, status: 'pending' }, { status: 'waived' });
    // Nothing to pay for a cancelled visit. Already paid: online → refunded at once;
    // at the desk → "refund due" until handed back (Fees / the visit's row).
    if (appt.feeStatus === 'pending') appt.feeStatus = 'waived';
  }
  await appt.save();
  // Signed by whoever did it (`by`), else the desk at that visit's branch (care.chatNote).
  const noteCtx = { practiceId: appt.practiceId, patientId: appt.patientId, locationId: appt.locationId, doctorId: appt.doctorId, by };
  if (to === 'confirmed') await note(noteCtx, `Visit confirmed: ${await visitLine(appt)}.`, 'visit_confirmed');
  if (to === 'missed') await note(noteCtx, `We missed you at your visit (${await visitLine(appt)}). Book a new time from your doctor's page whenever you're ready.`, 'visit_missed');
  if (to === 'cancelled') {
    await M.FollowUp.updateMany({ appointmentId: appt._id, status: 'booked' }, { status: 'not_booked', $unset: { appointmentId: 1 } });
    const who = appt.cancelledBy === 'patient' ? 'You cancelled' : 'The clinic cancelled';
    await note(noteCtx, `${who} your visit (${await visitLine(appt)})${appt.cancelReason ? ` — ${appt.cancelReason}` : ''}.`, 'visit_cancelled');
  }
  if (to === 'cancelled' && appt.feeStatus === 'paid') {
    const { refundFee } = require('./payments');
    for (const p of await M.Payment.find({ appointmentId: appt._id, status: 'paid' })) {
      await refundFee(p, { by }).catch((err) => console.warn('[refund]', err.message));
    }
  }

  if (to === 'completed' || to === 'missed') {
    let fu = await M.FollowUp.findOne({ appointmentId: appt._id });
    // Came back on an ordinary booking or as a walk-in: that is the follow-up visit too
    // (one due within the next 2 weeks, or overdue).
    if (!fu && to === 'completed') {
      fu = await M.FollowUp.findOne({
        practiceId: appt.practiceId, patientId: appt.patientId, status: { $in: ['not_booked', 'no_reply', 'booked'] },
        dueDate: { $lte: T.addDays(now, 14) },
        // Not the one this visit just asked for.
        createdAt: { $lt: appt.consultStartedAt || appt.arrivedAt || appt.startAt },
      }).sort({ dueDate: 1 });
      if (fu) fu.appointmentId = appt._id;
    }
    if (fu) {
      if (to === 'completed') {
        fu.status = 'completed';
        fu.cameBackAt = now;
        fu.outcome = now <= T.addDays(fu.dueDate, 3) ? 'on_time' : 'late';
      } else {
        fu.status = 'missed';
        fu.outcome = 'missed';
      }
      await fu.save();
    }
  }
  if (to === 'cancelled') {
    const patient = await M.Patient.findById(appt.patientId, 'userId');
    if (patient?.userId && appt.cancelledBy !== 'patient') {
      await notify([patient.userId], {
        type: 'appointment_cancelled', practiceId: appt.practiceId,
        title: 'Visit cancelled', body: reason || 'Please book another time', screen: 'Patient-Doctors', whatsapp: true,
      });
    }
    if (appt.cancelledBy === 'patient') {
      const desk = await require('./notify').deskFor(appt.practiceId, { locationId: appt.locationId, doctorId: appt.doctorId });
      const who = await M.Patient.findById(appt.patientId, 'name');
      await notify([...desk, appt.doctorId], {
        type: 'appointment_cancelled', practiceId: appt.practiceId, title: `${who?.name || 'A patient'} cancelled a visit`,
        body: `${T.dayKey(appt.startAt)} · ${T.fmtTime(T.minuteOfDay(appt.startAt))}`, screen: 'Appointments',
      });
    }
  }
  await visitsChanged(appt);
  return appt;
}

/** Moves a booking to a new time: the old one is kept as `rescheduled`. */
async function reschedule(appt, startAt, by, locationId) {
  if (!['booked', 'confirmed'].includes(appt.status)) throw conflict('Only upcoming visits can be rescheduled', 'BAD_TRANSITION');
  // Another branch of the same clinic may be chosen (book() checks the doctor has that slot there).
  const moved = locationId && String(locationId) !== String(appt.locationId);
  const next = await book({
    practiceId: appt.practiceId, locationId: moved ? locationId : appt.locationId, doctorId: appt.doctorId, patientId: appt.patientId,
    startAt, visitType: appt.visitType, mode: appt.mode, reason: appt.reason, channel: appt.channel, bookedBy: by, chat: false,
  });
  appt.status = 'rescheduled';
  appt.rescheduledToId = next._id;
  await appt.save();
  next.rescheduledFromId = appt._id;
  await next.save();
  // Already paid: the payment moves with the visit (it stays paid; nothing is asked again).
  // Same branch: keep the original fee record instead of the one book() just made.
  // Another branch: its own fee applies, so the old unpaid one is waived.
  const paid = await M.Payment.findOne({ appointmentId: appt._id, status: 'paid' });
  if (paid) {
    await M.Payment.deleteMany({ appointmentId: next._id, status: 'pending' });
    paid.appointmentId = next._id;
    await paid.save();
    next.feeStatus = 'paid';
    next.payAt = appt.payAt;
    await next.save();
  } else if (moved) {
    await M.Payment.updateMany({ appointmentId: appt._id, status: 'pending' }, { status: 'waived', note: 'Moved to another branch' });
  } else if (await M.Payment.exists({ appointmentId: appt._id })) {
    await M.Payment.deleteMany({ appointmentId: next._id });
    await M.Payment.updateMany({ appointmentId: appt._id, status: 'pending' }, { appointmentId: next._id });
    if (appt.payAt) {
      next.payAt = appt.payAt;
      await next.save();
    }
  }
  await M.FollowUp.updateMany({ appointmentId: appt._id }, { appointmentId: next._id });
  await note({ practiceId: next.practiceId, patientId: next.patientId, locationId: next.locationId, doctorId: next.doctorId, by }, `Visit moved to ${await visitLine(next)}${next.feeStatus === 'paid' ? '. Your payment moves with it.' : '.'}`, 'visit_rescheduled');
  await visitsChanged(next);
  return next;
}

async function getAppointment(id, practiceId) {
  const appt = await M.Appointment.findOne({ _id: id, practiceId });
  if (!appt) throw notFound('Appointment');
  return appt;
}

module.exports = { slotsFor, nextFreeSlot, nextToken, book, transition, reschedule, getAppointment, feeFor, visitsChanged, TRANSITIONS, ACTIVE };

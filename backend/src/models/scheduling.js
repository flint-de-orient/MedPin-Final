// Booking, queue, payments, follow-ups and referrals
// (Appointments, Appointments-Manage, Queue-*, Staff-Today, Doctor-History,
// Doctor-FollowUps, Report-Fees, Report-Referrals, patient visit request).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, rupees, enumOf, baseOptions } = require('./common');

// "Requests waiting for a time" — the patient asks, the clinic assigns a slot.
const appointmentRequestSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    doctorId: ref('User'),
    locationId: ref('Location'),
    visitType: enumOf(E.VISIT_TYPES, { default: 'new' }),
    mode: enumOf(E.VISIT_MODES, { default: 'in_clinic' }),
    reason: String, // "fever and body ache for 3 days"
    preferredTime: String, // "Thu or Fri, after 5 PM"
    preferredSlots: [Date], // slots offered in the patient app sheet
    channel: enumOf(E.REQUEST_CHANNELS, { default: 'app' }),
    status: enumOf(E.REQUEST_STATUSES, { default: 'pending' }),
    appointmentId: ref('Appointment'),
    declineReason: String, // "Asked for a home visit"
    handledBy: ref('User'),
    handledAt: Date,
  },
  baseOptions,
);
appointmentRequestSchema.index({ practiceId: 1, status: 1, createdAt: 1 });

const todoSchema = new Schema({
  text: { type: String, required: true }, // "Upload HbA1c report"
  done: { type: Boolean, default: false },
  doneAt: Date,
});

// One booking = one queue token for the day.
const appointmentSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    locationId: ref('Location', true),
    doctorId: ref('User', true),
    patientId: ref('Patient', true),
    requestId: ref('AppointmentRequest'),
    date: { type: Date, required: true }, // local day at 00:00 (IST)
    startAt: { type: Date, required: true },
    endAt: Date,
    tokenNo: { type: Number, min: 1 }, // shown zero-padded: "Token 04"
    isWalkIn: { type: Boolean, default: false },
    visitType: enumOf(E.VISIT_TYPES, { default: 'follow_up' }),
    mode: enumOf(E.VISIT_MODES, { default: 'in_clinic' }),
    serviceName: String,
    reason: String, // "Diabetes", "Fever, cough"
    status: enumOf(E.APPOINTMENT_STATUSES, { default: 'booked' }),
    confirmedAt: Date,
    arrivedAt: Date, // check-in; drives "Waiting 22 min"
    calledAt: Date, // "Call next": the patient was told it's their turn (again: the latest call)
    callCount: Number,
    checkedInBy: ref('User'),
    consultStartedAt: Date,
    completedAt: Date,
    missedAt: Date,
    cancelledAt: Date,
    cancelledBy: enumOf(E.CANCELLED_BY),
    cancelReason: String,
    cancelledByUser: ref('User'), // the doctor / desk member who cancelled it (Fees, the visit show the name)
    rescheduledFromId: ref('Appointment'),
    rescheduledToId: ref('Appointment'),
    bookedBy: ref('User'),
    channel: enumOf(E.REQUEST_CHANNELS, { default: 'desk' }),
    fee: { ...rupees, default: 0 },
    feeStatus: enumOf(E.FEE_STATUSES, { default: 'pending' }),
    // How the patient said they'll pay (Pay online / Pay at the clinic); paid → how it was paid.
    payAt: enumOf(['online', 'clinic']),
    todos: [todoSchema], // patient's before-visit checklist
    patientNotifiedAt: Date,
    reminderSentAt: Date,
    // The visit reminders sent (jobs.visitReminders): each once, and no visit looked at again.
    reminded24At: Date,
    reminded2At: Date,
    videoRoomUrl: String,
  },
  baseOptions,
);
appointmentSchema.index({ locationId: 1, date: 1, tokenNo: 1 }, {
  unique: true,
  partialFilterExpression: { tokenNo: { $type: 'number' } },
});
appointmentSchema.index({ doctorId: 1, startAt: 1 });
appointmentSchema.index({ practiceId: 1, date: 1, status: 1 });
appointmentSchema.index({ patientId: 1, startAt: -1 });

// Fees and collections (Report-Fees: "Mark as paid", "Send payment link").
const paymentSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    locationId: ref('Location'),
    patientId: ref('Patient', true),
    appointmentId: ref('Appointment'),
    amount: { ...rupees, required: true },
    method: enumOf(E.PAYMENT_METHODS),
    status: enumOf(E.FEE_STATUSES, { default: 'pending' }),
    paidAt: Date,
    markedPaidBy: ref('User'),
    paymentLinkUrl: String,
    paymentLinkSentAt: Date,
    paymentLinkExpiresAt: Date, // a link asked for again before this is the same link, re-sent
    paymentLinkAmount: Number,
    paymentLinkId: String, // Razorpay's id for that link: cancelled once the fee is settled another way
    razorpayOrderId: String,
    razorpayOrderAmount: Number, // the amount that Razorpay order was made for
    razorpayPaymentId: { type: String, sparse: true, unique: true },
    // Money given back (a cancelled visit): online through Razorpay, or handed back at the desk.
    refundedAt: Date,
    refundedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    refundId: String,
    refundDue: { type: Boolean, default: undefined }, // paid at the desk, visit cancelled: to hand back
    refundReason: String, // a refund of a visit that wasn't cancelled (goodwill, overcharge)
    waivedBy: ref('User'), // fee let go by the doctor / owner / practice manager
    waivedAt: Date,
    note: String,
    payoutId: ref('Payout'), // set once this online fee is paid out to the doctor
    // Refunded after it was paid out: taken back from the doctor's next payout (that payout's id).
    clawedBackIn: ref('Payout'),
    // A refund is being sent (so a second tap or a cancel at the same moment doesn't send another).
    refunding: { type: Boolean, default: undefined },
  },
  baseOptions,
);
paymentSchema.index({ practiceId: 1, status: 1, createdAt: -1 });
paymentSchema.index({ razorpayOrderId: 1 }, { sparse: true });

// Money that came in for something no longer payable (a link paid after the fee was taken in
// cash, a second payment, a cancelled visit or order): refunded at once, or flagged for the desk.
const strayPaymentSchema = new Schema(
  {
    razorpayPaymentId: { type: String, required: true, unique: true },
    kind: enumOf(['fee', 'order'], { required: true }),
    paymentId: ref('Payment'), // the visit fee it was meant for
    orderId: ref('Order'),
    practiceId: ref('Practice'),
    patientId: ref('Patient'),
    amount: rupees,
    status: enumOf(['refunding', 'refunded', 'refund_due'], { default: 'refunding' }),
    refundId: String,
    reason: String,
  },
  baseOptions,
);

// Online fees paid out to a doctor (weekly, through RazorpayX when set up).
const payoutSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    doctorId: ref('User', true), // who is paid
    amount: { ...rupees, required: true },
    count: Number, // online fees included
    periodFrom: Date,
    periodTo: Date,
    status: enumOf(['pending', 'on_hold', 'processing', 'paid', 'failed'], { default: 'pending' }),
    note: String, // why it is waiting / failed, in plain words
    method: enumOf(['upi', 'bank']),
    destination: String, // "arjun@okhdfc" / "HDFC ····6789"
    razorpayPayoutId: String,
    paidAt: Date,
    // Fees refunded after an earlier payout, taken off this one.
    deducted: rupees,
  },
  baseOptions,
);
payoutSchema.index({ doctorId: 1, createdAt: -1 });

// Advised follow-ups ("Come back in 2 weeks with fasting sugar.").
const followUpSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    doctorId: ref('User', true),
    locationId: ref('Location'),
    consultationId: ref('Consultation'),
    advisedOn: { type: Date, default: Date.now },
    adviceText: String,
    dueDate: { type: Date, required: true },
    status: enumOf(E.FOLLOW_UP_STATUSES, { default: 'not_booked' }),
    appointmentId: ref('Appointment'),
    remindPatient: { type: Boolean, default: true },
    remindersSent: { type: Number, default: 0 },
    lastRemindedAt: Date,
    outcome: enumOf(E.FOLLOW_UP_OUTCOMES), // set when the visit happens or is missed
    cameBackAt: Date,
  },
  baseOptions,
);
followUpSchema.index({ practiceId: 1, dueDate: 1, status: 1 });

const referralSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    patientId: ref('Patient', true),
    doctorId: ref('User', true), // our doctor
    direction: enumOf(E.REFERRAL_DIRECTIONS, { required: true }),
    counterpartName: { type: String, required: true }, // "Dr. Sourav Lahiri", "Eye clinic"
    counterpartUserId: ref('User'), // when the other doctor is on MedPin
    specialty: String, // Cardiology, Nephrology…
    reason: String, // "Rising creatinine"
    referredAt: { type: Date, default: Date.now },
    status: enumOf(E.REFERRAL_STATUSES, { default: 'awaiting' }),
    seenAt: Date,
    consultationId: ref('Consultation'),
    locationId: ref('Location'), // where the patient is seen (Reports location filter)
    cancelledAt: Date,
  },
  baseOptions,
);

// A visit booked, moved or cancelled: the patient's phone re-schedules its visit reminders.
appointmentSchema.post('save', function () {
  require('../services/reminders').remindersChanged(this.patientId);
});

module.exports = {
  AppointmentRequest: model('AppointmentRequest', appointmentRequestSchema),
  Appointment: model('Appointment', appointmentSchema),
  Payment: model('Payment', paymentSchema),
  Payout: model('Payout', payoutSchema),
  StrayPayment: model('StrayPayment', strayPaymentSchema),
  FollowUp: model('FollowUp', followUpSchema),
  Referral: model('Referral', referralSchema),
};

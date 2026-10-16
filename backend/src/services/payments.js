// Online payments through Razorpay payment links: visit fees (desk "Send
// link", patient "Pay online") and plan upgrades. Without Razorpay keys (dev
// only) the link is a local test page that marks the payment paid.
const env = require('../config/env');
const M = require('../models');
const T = require('../lib/time');
const { conflict } = require('../lib/http');
const { publicBase } = require('../lib/request-base');

const configured = () => Boolean(env.razorpay.keyId && env.razorpay.keySecret);

/** Creates a payment link; `notes` come back in the webhook. Returns the short URL. */
// Links stay payable for a week; asking again within that time re-sends the same link.
const LINK_DAYS = 7;

async function createLink({ amount, description, customer, notes, devPath, sms = Boolean(customer?.contact), expireAt }) {
  if (!configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet. Please pay at the clinic.', 'PAYMENTS_OFF'), { status: 503 });
    return `${publicBase()}/dev/pay/${devPath}`;
  }
  const call = () => fetch('https://api.razorpay.com/v1/payment_links', {
    method: 'POST',
    headers: { authorization: `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      amount: Math.round(amount * 100), currency: 'INR', description: String(description).slice(0, 2048),
      // Unique per link (a fee can be sent again), ≤ 40 chars.
      reference_id: `${String(notes.paymentId || notes.subscriptionId).slice(-16)}.${Date.now().toString(36)}`,
      // Razorpay texts the link only when we can't reach the person ourselves (no MedPin app).
      customer, notify: { sms: Boolean(sms && customer?.contact) }, notes,
      ...(expireAt ? { expire_by: Math.floor(expireAt.getTime() / 1000) } : {}),
    }),
  }).catch(() => null);
  let resp = await call();
  // Razorpay busy (rate limit / a hiccup): one more try a moment later.
  if (!resp || resp.status === 429 || resp.status >= 500) {
    await new Promise((r) => setTimeout(r, 1500));
    resp = await call();
  }
  const body = resp ? await resp.json().catch(() => ({})) : {};
  if (!resp?.ok) {
    console.warn('[razorpay link]', resp?.status, body.error?.description || '');
    const msg = !resp || resp.status === 429 || resp.status >= 500
      ? 'The payment service is busy right now. Try again in a minute, or collect the fee at the counter.'
      : resp.status === 401
        ? 'Online payment isn’t set up correctly for this clinic. Collect the fee at the counter for now.'
        : 'Couldn’t make the payment link. Check the patient’s phone number, or collect the fee at the counter.';
    throw Object.assign(conflict(msg, 'PAYMENT_LINK_FAILED'), { status: 503 });
  }
  return body.short_url;
}

/** Link for a pending visit fee (saved on the payment). */
async function feeLink(payment, patient) {
  if (payment.status !== 'pending') throw conflict('This fee is not pending', 'NOT_PENDING');
  const now = new Date();
  // The link sent earlier is still payable: send that one again (one link per fee, no duplicates).
  const reuse = payment.paymentLinkUrl && payment.paymentLinkExpiresAt && payment.paymentLinkExpiresAt > new Date(now.getTime() + 3600e3)
    && payment.paymentLinkAmount === payment.amount;
  if (reuse) {
    payment.paymentLinkSentAt = now;
    await payment.save();
    return payment.paymentLinkUrl;
  }
  const expireAt = new Date(now.getTime() + LINK_DAYS * 864e5);
  const url = await createLink({
    amount: payment.amount, description: 'Consultation fee',
    customer: patient ? { name: patient.name, contact: patient.phone ? `+91${patient.phone}` : undefined } : undefined,
    // With the MedPin app the patient gets it there (and on WhatsApp); without, Razorpay texts it.
    sms: !patient?.userId,
    notes: { kind: 'fee', paymentId: String(payment._id) }, devPath: String(payment._id), expireAt,
  });
  Object.assign(payment, { paymentLinkUrl: url, paymentLinkSentAt: now, paymentLinkExpiresAt: expireAt, paymentLinkAmount: payment.amount });
  await payment.save();
  return url;
}

/** A visit fee paid online (webhook or dev page); once only. */
async function feePaid(paymentId, razorpayPaymentId) {
  const p = await M.Payment.findOneAndUpdate(
    { _id: paymentId, status: 'pending' },
    { status: 'paid', method: 'online', paidAt: new Date(), ...(razorpayPaymentId ? { razorpayPaymentId } : {}) },
    { new: true },
  );
  if (p?.appointmentId) {
    await M.Appointment.updateOne({ _id: p.appointmentId }, { feeStatus: 'paid', payAt: 'online' });
    await feeReceipt(p).catch((err) => console.warn('[fee receipt]', err.message));
    // Paid from the link: the desk's Payments, Today and the doctor's queue / Fees update at once.
    const appt = await M.Appointment.findById(p.appointmentId, 'practiceId locationId doctorId patientId');
    if (appt) await require('./scheduling').visitsChanged(appt).catch(() => {});
  }
  return p;
}

/**
 * A visit fee paid (online, or collected at the desk): the patient gets a
 * receipt; the doctor and desk see it in the app (no push) — their queue and
 * reports already show it.
 */
async function feeReceipt(p) {
  const { notify, deskOrDoctors } = require('./notify');
  const a = await M.Appointment.findById(p.appointmentId).populate('patientId', 'userId name').populate('doctorId', 'name');
  if (!a) return;
  const how = p.method === 'online' ? 'online' : `at the clinic (${p.method === 'cash' ? 'cash' : p.method === 'upi' ? 'UPI' : p.method})`;
  if (a.patientId?.userId) {
    await notify([a.patientId.userId], {
      type: 'fee_paid', practiceId: a.practiceId, title: `Paid ₹${p.amount} ${p.method === 'online' ? 'online' : 'at the clinic'}`,
      body: `Your visit with ${a.doctorId?.name || 'the doctor'} · reference ${p.razorpayPaymentId || String(p._id).slice(-6)}`,
      screen: 'Patient-DoctorDetail', params: { doctorId: a.doctorId?._id || a.doctorId },
    });
  }
  // Signed by who took it at the desk; paid online, by the desk at that branch (or the doctor).
  await require('./care').chatNote(
    { practiceId: a.practiceId, patientId: a.patientId?._id || a.patientId, locationId: a.locationId, doctorId: a.doctorId?._id || a.doctorId, by: p.method === 'online' ? undefined : p.markedPaidBy },
    `Payment received: ₹${p.amount} ${p.method === 'online' ? 'online' : `at the clinic (${p.method === 'cash' ? 'cash' : p.method === 'upi' ? 'UPI' : p.method})`} · reference ${p.razorpayPaymentId || String(p._id).slice(-6)}.`,
    'fee_paid',
  );
  const staff = await deskOrDoctors(a.practiceId, { locationId: a.locationId, doctorId: a.doctorId?._id || a.doctorId });
  await notify([...new Set([...staff.map(String), String(a.doctorId?._id || a.doctorId)])], {
    type: 'fee_paid', push: false, practiceId: a.practiceId, title: `${a.patientId?.name || 'Patient'} paid ₹${p.amount} ${how}`, screen: 'Appointments',
  });
}

/** Link for a pharmacy order paid online (saved on the order). */
async function orderLink(order, patient, pharmacyName) {
  if (order.pay?.status === 'paid') throw conflict('This order is already paid', 'ALREADY_PAID');
  if (order.status === 'cancelled') throw conflict('This order was cancelled', 'CANCELLED');
  const url = await createLink({
    amount: order.total, description: `Medicines from ${pharmacyName || 'the pharmacy'}`,
    customer: patient ? { name: patient.name, contact: patient.phone ? `+91${patient.phone}` : undefined } : undefined,
    notes: { kind: 'order', orderId: String(order._id), paymentId: String(order._id) }, devPath: `order/${order._id}`,
  });
  order.pay = { ...(order.pay?.toObject?.() || {}), method: 'online', status: 'due', linkUrl: url };
  await order.save();
  return url;
}

/** A pharmacy order paid online (webhook or dev page); once only. Tells patient and pharmacy. */
async function orderPaid(orderId, razorpayPaymentId) {
  const order = await M.Order.findOneAndUpdate(
    { _id: orderId, 'pay.status': { $ne: 'paid' }, status: { $ne: 'cancelled' } },
    { 'pay.method': 'online', 'pay.status': 'paid', 'pay.paidAt': new Date(), ...(razorpayPaymentId ? { 'pay.razorpayPaymentId': razorpayPaymentId } : {}) },
    { new: true },
  );
  if (!order) return null;
  const patient = await M.Patient.findById(order.patientId, 'userId');
  if (patient?.userId) {
    await require('./notify').notify([patient.userId], { type: 'order_update', title: `Paid ₹${order.total} for your medicines`, body: 'The pharmacy can see it is paid.', screen: 'Patient-Medicines' }).catch(() => {});
  }
  return order;
}

/**
 * A visit fee given back (the visit was cancelled). Paid online: refunded
 * through Razorpay (in dev nothing was charged, so it's simply marked). Paid at
 * the desk: marked "refund due" until staff hand it back ([by] = who did).
 * The patient is told either way.
 */
async function refundFee(payment, { by, handedBack = false } = {}) {
  if (payment.status !== 'paid') return payment;
  // The desk hands it back or should know it went back: told in the app (not whoever did it).
  const tellDesk = async (n) => {
    const a = payment.appointmentId ? await M.Appointment.findById(payment.appointmentId, 'practiceId locationId doctorId patientId').populate('patientId', 'name') : null;
    if (!a) return;
    const { notify, deskOrDoctors } = require('./notify');
    const staff = (await deskOrDoctors(a.practiceId, { locationId: a.locationId, doctorId: a.doctorId })).map(String).filter((id) => id !== String(by || ''));
    await notify(staff, { practiceId: a.practiceId, screen: 'Report-Fees', params: { appointmentId: a._id }, ...n(a.patientId?.name || 'the patient') });
  };
  if (payment.method === 'online') {
    if (configured() && payment.razorpayPaymentId) {
      const resp = await fetch(`https://api.razorpay.com/v1/payments/${payment.razorpayPaymentId}/refund`, {
        method: 'POST',
        headers: { authorization: `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`, 'content-type': 'application/json' },
        body: JSON.stringify({ amount: Math.round(payment.amount * 100), notes: { paymentId: String(payment._id) } }),
      }).catch(() => null);
      const body = resp ? await resp.json().catch(() => ({})) : {};
      if (!resp?.ok) {
        payment.refundDue = true;
        payment.note = 'Refund failed at Razorpay — retry from Fees';
        await payment.save();
        await tellDesk((name) => ({ type: 'refund_due', title: `Refund of ₹${payment.amount} to ${name} didn't go through`, body: 'Retry it from Fees, or hand it back at the desk.' })).catch(() => {});
        return payment;
      }
      payment.refundId = body.id;
    } else if (env.isProd) {
      payment.refundDue = true;
      payment.note = 'Refund due: online payment, Razorpay not set up';
      await payment.save();
      return payment;
    }
  } else if (!handedBack) {
    // Cash / UPI at the desk: the desk hands it back, then marks it.
    payment.refundDue = true;
    payment.note = 'Refund due: visit cancelled';
    await payment.save();
    await tellDesk((name) => ({ type: 'refund_due', title: `Refund due: ₹${payment.amount} to ${name}`, body: 'The visit was cancelled. Hand it back, then mark it in Fees.' })).catch(() => {});
    return payment;
  }
  payment.status = 'refunded';
  payment.refundDue = undefined;
  payment.refundedAt = new Date();
  payment.refundedBy = by;
  await payment.save();
  if (payment.appointmentId) await M.Appointment.updateOne({ _id: payment.appointmentId }, { feeStatus: 'refunded' });
  const a = payment.appointmentId ? await M.Appointment.findById(payment.appointmentId).populate('patientId', 'userId') : null;
  if (a) {
    if (payment.method === 'online') {
      await tellDesk((name) => ({ type: 'fee_refunded', push: false, title: `₹${payment.amount} refunded online to ${name}` })).catch(() => {});
    }
    await require('./care').chatNote(
      { practiceId: a.practiceId, patientId: a.patientId?._id || a.patientId, locationId: a.locationId, doctorId: a.doctorId, by },
      payment.method === 'online' ? `Refund: ₹${payment.amount} is on its way back to how you paid (usually 5–7 working days).` : `Refund: ₹${payment.amount} handed back at the clinic.`,
      'fee_refunded',
    );
  }
  if (a?.patientId?.userId) {
    await require('./notify').notify([a.patientId.userId], {
      type: 'fee_refunded', practiceId: a.practiceId, title: `₹${payment.amount} refunded`,
      body: payment.method === 'online' ? 'Back to how you paid, usually in 5–7 working days.' : 'Handed back at the clinic.',
      screen: 'Patient-Doctors',
    });
  }
  return payment;
}

/** Money back for a paid order that is cancelled (Razorpay refund when set up). */
async function refundOrder(order) {
  if (order.pay?.status !== 'paid') return order;
  if (configured() && order.pay.razorpayPaymentId) {
    const resp = await fetch(`https://api.razorpay.com/v1/payments/${order.pay.razorpayPaymentId}/refund`, {
      method: 'POST',
      headers: { authorization: `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`, 'content-type': 'application/json' },
      body: JSON.stringify({ amount: Math.round(order.total * 100), notes: { orderId: String(order._id) } }),
    }).catch(() => null);
    order.pay.status = resp?.ok ? 'refunded' : 'refund_pending';
  } else {
    order.pay.status = env.isProd ? 'refund_pending' : 'refunded'; // dev: nothing was charged
  }
  if (order.pay.status === 'refunded') order.pay.refundedAt = new Date();
  await order.save();
  return order;
}

/** Link to pay for a plan upgrade now (the plan changes when it's paid). */
async function planLink(sub, plan, user) {
  return createLink({
    amount: plan.priceMonthly, description: `MedPin ${plan.name || plan.key} plan · 1 month`,
    customer: { name: user.name, contact: user.phone ? `+91${user.phone}` : undefined },
    notes: { kind: 'plan', subscriptionId: String(sub._id), planKey: plan.key }, devPath: `plan/${sub._id}/${plan.key}`,
  });
}

/** A plan upgrade paid: switch now, a month from today, with a paid invoice. */
async function planPaid(subscriptionId, planKey, razorpayPaymentId) {
  const [sub, plan] = await Promise.all([M.Subscription.findById(subscriptionId), M.Plan.findOne({ key: planKey })]);
  if (!sub || !plan) return null;
  if (razorpayPaymentId && (await M.Invoice.exists({ razorpayPaymentId }))) return sub; // webhook retried
  const start = new Date();
  Object.assign(sub, { planKey: plan.key, price: plan.priceMonthly, status: 'active', pendingPlanKey: undefined, pendingFrom: undefined, currentPeriodStart: start, currentPeriodEnd: T.addDays(start, 30) });
  await sub.save();
  await M.Invoice.create({ practiceId: sub.practiceId, issuedAt: start, description: `${plan.key} plan · monthly`, amount: plan.priceMonthly, status: 'paid', paidAt: start, periodStart: start, periodEnd: sub.currentPeriodEnd, razorpayPaymentId });
  return sub;
}

module.exports = { feeReceipt, refundFee, configured, createLink, feeLink, feePaid, planLink, planPaid, orderLink, orderPaid, refundOrder };

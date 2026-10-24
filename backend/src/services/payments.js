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

async function createLink({ amount, description, customer, notes, devPath, sms = Boolean(customer?.contact), expireAt, out }) {
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
  if (out) out.id = body.id;
  return body.short_url;
}

const rzpAuth = () => `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`;

/** A payment link that must not be paid any more (the fee or order was settled another way). */
async function cancelLink(linkId) {
  if (!linkId || !configured()) return;
  await fetch(`https://api.razorpay.com/v1/payment_links/${linkId}/cancel`, { method: 'POST', headers: { authorization: rzpAuth() } })
    .then((r) => { if (!r.ok && r.status !== 400) console.warn('[razorpay link cancel]', r.status); })
    .catch(() => {});
}

/** Refunds one Razorpay payment. True when Razorpay took the refund. */
async function refundRazorpay(razorpayPaymentId, amount, notes) {
  if (!configured()) return !env.isProd; // dev: nothing was charged
  const resp = await fetch(`https://api.razorpay.com/v1/payments/${razorpayPaymentId}/refund`, {
    method: 'POST',
    headers: { authorization: rzpAuth(), 'content-type': 'application/json' },
    body: JSON.stringify({ amount: Math.round(amount * 100), notes }),
  }).catch(() => null);
  const body = resp ? await resp.json().catch(() => ({})) : {};
  return resp?.ok ? body.id || true : false;
}

/**
 * Money that came in for something no longer payable: a link paid after the fee was
 * taken in cash or waived, a second payment (link and in-app), a cancelled visit or
 * order. It is refunded at once; if Razorpay can't, the desk is told to hand it back.
 * The patient is told either way. Once per Razorpay payment (webhook retries).
 */
async function strayPayment({ kind, payment, order, razorpayPaymentId, amountPaise }) {
  if (!razorpayPaymentId) return null;
  const amount = amountPaise ? amountPaise / 100 : kind === 'fee' ? payment?.amount : order?.total;
  let row;
  try {
    row = await M.StrayPayment.create({
      razorpayPaymentId, kind, amount, paymentId: payment?._id, orderId: order?._id,
      practiceId: payment?.practiceId, patientId: payment?.patientId || order?.patientId,
      reason: kind === 'fee' ? `Fee was already ${payment?.status}` : `Order was already ${order?.status === 'cancelled' ? 'cancelled' : 'paid'}`,
    });
  } catch (err) {
    if (err.code === 11000) return M.StrayPayment.findOne({ razorpayPaymentId }); // a webhook retry
    throw err;
  }
  const refundId = await refundRazorpay(razorpayPaymentId, amount, { stray: String(row._id) });
  row.status = refundId ? 'refunded' : 'refund_due';
  if (typeof refundId === 'string') row.refundId = refundId;
  await row.save();
  const { notify, deskOrDoctors } = require('./notify');
  const patient = row.patientId ? await M.Patient.findById(row.patientId, 'userId name') : null;
  if (patient?.userId) {
    await notify([patient.userId], { forPatientId: patient._id,
      type: 'fee_refunded', practiceId: row.practiceId,
      title: row.status === 'refunded' ? `₹${amount} refunded` : `₹${amount} will be given back`,
      body: row.status === 'refunded'
        ? 'This was already paid, so the extra payment goes back to how you paid (usually 5–7 working days).'
        : 'This was already paid. The clinic will give the extra payment back.',
      screen: kind === 'fee' ? 'Patient-Doctors' : 'Patient-Medicines',
    }).catch(() => {});
  }
  if (kind === 'fee' && payment) {
    const a = payment.appointmentId ? await M.Appointment.findById(payment.appointmentId, 'practiceId locationId doctorId') : null;
    if (a) {
      const staff = await deskOrDoctors(a.practiceId, { locationId: a.locationId, doctorId: a.doctorId });
      await notify(staff, {
        type: row.status === 'refunded' ? 'fee_refunded' : 'refund_due', practiceId: a.practiceId, push: row.status !== 'refunded',
        title: row.status === 'refunded'
          ? `₹${amount} paid twice by ${patient?.name || 'a patient'} — refunded online`
          : `Refund due: ₹${amount} paid twice by ${patient?.name || 'a patient'}`,
        body: row.status === 'refunded' ? undefined : "Razorpay couldn't refund it. Hand it back at the desk.",
        screen: 'Report-Fees', params: { appointmentId: a._id },
      }).catch(() => {});
    }
  }
  return row;
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
  const link = {};
  const url = await createLink({
    out: link,
    amount: payment.amount, description: 'Consultation fee',
    customer: patient ? { name: patient.name, contact: patient.phone ? `+91${patient.phone}` : undefined } : undefined,
    // With the MedPin app the patient gets it there (and on WhatsApp); without, Razorpay texts it.
    sms: !patient?.userId,
    notes: { kind: 'fee', paymentId: String(payment._id) }, devPath: String(payment._id), expireAt,
  });
  if (payment.paymentLinkId && payment.paymentLinkId !== link.id) await cancelLink(payment.paymentLinkId); // the older link
  Object.assign(payment, { paymentLinkUrl: url, paymentLinkId: link.id, paymentLinkSentAt: now, paymentLinkExpiresAt: expireAt, paymentLinkAmount: payment.amount });
  await payment.save();
  return url;
}

/** A visit fee paid online (webhook or dev page); once only. */
async function feePaid(paymentId, razorpayPaymentId, { amountPaise } = {}) {
  const p = await M.Payment.findOneAndUpdate(
    { _id: paymentId, status: 'pending' },
    { status: 'paid', method: 'online', paidAt: new Date(), ...(razorpayPaymentId ? { razorpayPaymentId } : {}) },
    { new: true },
  );
  if (!p) {
    // Not pending any more: the same payment again (a webhook retry, Checkout and webhook)
    // is fine; a different payment means the patient paid twice → refunded.
    const now = await M.Payment.findById(paymentId);
    if (now && razorpayPaymentId && now.razorpayPaymentId !== razorpayPaymentId) {
      await strayPayment({ kind: 'fee', payment: now, razorpayPaymentId, amountPaise });
    }
    return null;
  }
  // Paid: the other way to pay it (a link sent earlier) is closed.
  await cancelLink(p.paymentLinkId);
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
    await notify([a.patientId.userId], { forPatientId: a.patientId._id,
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
  if (order.priced === false || !(order.total > 0)) throw conflict('The pharmacy prices this order at the counter. Pay there.', 'NOT_PRICED');
  // The link made earlier is still the one to pay (one link per order).
  if (order.pay?.linkUrl && order.pay?.linkId) return order.pay.linkUrl;
  const link = {};
  const url = await createLink({
    out: link,
    amount: order.total, description: `Medicines from ${pharmacyName || 'the pharmacy'}`,
    customer: patient ? { name: patient.name, contact: patient.phone ? `+91${patient.phone}` : undefined } : undefined,
    notes: { kind: 'order', orderId: String(order._id), paymentId: String(order._id) }, devPath: `order/${order._id}`,
  });
  order.pay = { ...(order.pay?.toObject?.() || {}), method: 'online', status: 'due', linkUrl: url, linkId: link.id };
  await order.save();
  return url;
}

/** A pharmacy order paid online (webhook or dev page); once only. Tells patient and pharmacy. */
async function orderPaid(orderId, razorpayPaymentId, { amountPaise } = {}) {
  const order = await M.Order.findOneAndUpdate(
    { _id: orderId, 'pay.status': { $nin: ['paid', 'refunded', 'refund_pending'] }, status: { $ne: 'cancelled' } },
    { 'pay.method': 'online', 'pay.status': 'paid', 'pay.paidAt': new Date(), ...(razorpayPaymentId ? { 'pay.razorpayPaymentId': razorpayPaymentId } : {}) },
    { new: true },
  );
  if (!order) {
    // Already paid with this payment (a retry) is fine; otherwise (paid twice, or the order
    // was cancelled meanwhile) the money goes back.
    const now = await M.Order.findById(orderId);
    if (now && razorpayPaymentId && now.pay?.razorpayPaymentId !== razorpayPaymentId) {
      await strayPayment({ kind: 'order', order: now, razorpayPaymentId, amountPaise });
    }
    return null;
  }
  await cancelLink(order.pay?.linkId);
  const patient = await M.Patient.findById(order.patientId, 'userId');
  if (patient?.userId) {
    await require('./notify').notify([patient.userId], { forPatientId: patient._id, type: 'order_update', title: `Paid ₹${order.total} for your medicines`, body: 'The pharmacy can see it is paid.', screen: 'Patient-Medicines' }).catch(() => {});
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
  // Claim it: a second tap, or a cancel at the same moment, doesn't send a second refund.
  const claimed = await M.Payment.findOneAndUpdate({ _id: payment._id, status: 'paid', refunding: { $ne: true } }, { $set: { refunding: true } }, { new: true });
  if (!claimed) return (await M.Payment.findById(payment._id)) || payment;
  // What the caller set on its copy (why it is refunded) goes with it.
  if (payment.refundReason) claimed.refundReason = payment.refundReason;
  try {
    return await refundClaimed(claimed, { by, handedBack });
  } finally {
    await M.Payment.updateOne({ _id: payment._id }, { $unset: { refunding: 1 } });
  }
}

async function refundClaimed(payment, { by, handedBack }) {
  // An online payment whose refund failed, handed back in cash at the desk.
  const cashForOnline = payment.method === 'online' && handedBack && payment.refundDue === true;
  // The desk hands it back or should know it went back: told in the app (not whoever did it).
  const tellDesk = async (n) => {
    const a = payment.appointmentId ? await M.Appointment.findById(payment.appointmentId, 'practiceId locationId doctorId patientId').populate('patientId', 'name') : null;
    if (!a) return;
    const { notify, deskOrDoctors } = require('./notify');
    const staff = (await deskOrDoctors(a.practiceId, { locationId: a.locationId, doctorId: a.doctorId })).map(String).filter((id) => id !== String(by || ''));
    await notify(staff, { practiceId: a.practiceId, screen: 'Report-Fees', params: { appointmentId: a._id }, ...n(a.patientId?.name || 'the patient') });
  };
  // An online refund that didn't go through can be handed back at the desk instead.
  if (payment.method === 'online' && !(handedBack && payment.refundDue)) {
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
    if (payment.method === 'online' && !cashForOnline) {
      await tellDesk((name) => ({ type: 'fee_refunded', push: false, title: `₹${payment.amount} refunded online to ${name}` })).catch(() => {});
    }
    await require('./care').chatNote(
      { practiceId: a.practiceId, patientId: a.patientId?._id || a.patientId, locationId: a.locationId, doctorId: a.doctorId, by },
      payment.method === 'online' && !cashForOnline ? `Refund: ₹${payment.amount} is on its way back to how you paid (usually 5–7 working days).` : `Refund: ₹${payment.amount} handed back at the clinic.`,
      'fee_refunded',
    );
  }
  if (a?.patientId?.userId) {
    await require('./notify').notify([a.patientId.userId], { forPatientId: a.patientId._id,
      type: 'fee_refunded', practiceId: a.practiceId, title: `₹${payment.amount} refunded`,
      body: payment.method === 'online' && !cashForOnline ? 'Back to how you paid, usually in 5–7 working days.' : 'Handed back at the clinic.',
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

module.exports = { strayPayment, cancelLink, refundRazorpay, feeReceipt, refundFee, configured, createLink, feeLink, feePaid, planLink, planPaid, orderLink, orderPaid, refundOrder };

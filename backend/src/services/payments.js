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
async function createLink({ amount, description, customer, notes, devPath }) {
  if (!configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet. Please pay at the clinic.', 'PAYMENTS_OFF'), { status: 503 });
    return `${publicBase()}/dev/pay/${devPath}`;
  }
  const resp = await fetch('https://api.razorpay.com/v1/payment_links', {
    method: 'POST',
    headers: { authorization: `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      amount: Math.round(amount * 100), currency: 'INR', description: String(description).slice(0, 2048),
      // Unique per link (a fee can be sent again), ≤ 40 chars.
      reference_id: `${String(notes.paymentId || notes.subscriptionId).slice(-16)}.${Date.now().toString(36)}`,
      customer, notify: { sms: Boolean(customer?.contact) }, notes,
    }),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw conflict(`Razorpay: ${body.error?.description || resp.status}`, 'PAYMENT_LINK_FAILED');
  return body.short_url;
}

/** Link for a pending visit fee (saved on the payment). */
async function feeLink(payment, patient) {
  if (payment.status !== 'pending') throw conflict('This fee is not pending', 'NOT_PENDING');
  const url = await createLink({
    amount: payment.amount, description: 'Consultation fee',
    customer: patient ? { name: patient.name, contact: patient.phone ? `+91${patient.phone}` : undefined } : undefined,
    notes: { kind: 'fee', paymentId: String(payment._id) }, devPath: String(payment._id),
  });
  Object.assign(payment, { paymentLinkUrl: url, paymentLinkSentAt: new Date() });
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
  if (p?.appointmentId) await M.Appointment.updateOne({ _id: p.appointmentId }, { feeStatus: 'paid' });
  return p;
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

module.exports = { configured, createLink, feeLink, feePaid, planLink, planPaid, orderLink, orderPaid, refundOrder };

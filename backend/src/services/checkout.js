// In-app payments with Razorpay Checkout (UPI, cards, net banking, wallets,
// pay later, EMI — whatever the Razorpay account has switched on).
//
// 1. start(): a Razorpay Order for what is being paid (a visit fee or a
//    pharmacy order); the app opens Checkout with its id.
// 2. Checkout returns razorpay_payment_id, _order_id and _signature.
// 3. confirm(): the signature is HMAC-SHA256("order_id|payment_id", key
//    secret); only a matching one marks the fee or order paid. The
//    payment.captured / order.paid webhook does the same as a backup.
//
// Without Razorpay keys (development only) the app shows a test checkout and
// confirm() accepts it; in production that is refused.
const crypto = require('crypto');
const env = require('../config/env');
const M = require('../models');
const { conflict, notFound, badRequest } = require('../lib/http');
const pay = require('./payments');

const auth = () => `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`;

/** Replaced in tests so they never call Razorpay. */
let fetchImpl = (url, opts) => fetch(url, opts);

/** What is being paid: amount, labels and the record to mark paid. */
async function subject(kind, id, patient) {
  if (!/^[a-f\d]{24}$/i.test(String(id || ''))) throw badRequest('Nothing to pay', 'BAD_ID');
  if (kind === 'fee') {
    // id: the appointment.
    const appt = await M.Appointment.findOne({ _id: id, patientId: patient._id }).populate('doctorId', 'name').populate('locationId', 'name shortName paymentMethods');
    if (!appt) throw notFound('Appointment');
    const p = await M.Payment.findOne({ appointmentId: appt._id, status: 'pending' });
    if (!p) throw conflict(appt.feeStatus === 'paid' ? 'This visit is already paid' : 'Nothing to pay for this visit', 'NOT_PENDING');
    const methods = appt.locationId?.paymentMethods || [];
    if (methods.length && methods.every((m) => m === 'cash')) throw conflict('This clinic takes the fee at the visit', 'ONLINE_PAY_OFF');
    return {
      kind, record: p, amount: p.amount,
      title: 'Consultation fee',
      detail: [appt.doctorId?.name, appt.locationId?.shortName || appt.locationId?.name].filter(Boolean).join(' · '),
      when: appt.startAt,
    };
  }
  if (kind === 'order') {
    const order = await M.Order.findOne({ _id: id, patientId: patient._id }).populate('pharmacyId', 'name');
    if (!order) throw notFound('Order');
    if (order.pay?.status === 'paid') throw conflict('This order is already paid', 'ALREADY_PAID');
    if (order.status === 'cancelled') throw conflict('This order was cancelled', 'CANCELLED');
    if (['delivered', 'picked_up'].includes(order.status) && order.pay?.method !== 'online') throw conflict('This order was already paid at the pharmacy', 'ALREADY_PAID');
    // Some medicines are priced at the counter: paying part online would leave the rest unpaid.
    if (order.priced === false || !(order.total > 0)) throw conflict('The pharmacy prices this order at the counter. Pay there.', 'NOT_PRICED');
    // Paying at delivery / the counter: online only until it is packed (not while the cash is being collected).
    if (order.pay?.method !== 'online' && !['placed', 'confirmed'].includes(order.status)) throw conflict('Pay the pharmacy when you get your medicines.', 'PAY_AT_DELIVERY');
    return { kind, record: order, amount: order.total, title: 'Medicines', detail: order.pharmacyId?.name || 'Pharmacy' };
  }
  throw badRequest('Nothing to pay', 'BAD_KIND');
}

/** Creates (or reuses) the Razorpay Order and returns what Checkout needs. */
async function start({ kind, id, patient }) {
  const s = await subject(kind, id, patient);
  if (!(s.amount > 0)) throw conflict('Nothing to pay', 'NOTHING_DUE');
  const base = {
    kind, id: String(id), amount: s.amount, currency: 'INR', title: s.title, detail: s.detail, when: s.when || null,
    prefill: { name: patient.name, contact: patient.phone ? `+91${patient.phone}` : undefined },
  };
  if (!pay.configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet. Please pay at the clinic.', 'PAYMENTS_OFF'), { status: 503 });
    return { ...base, test: true, orderId: `order_test_${id}` };
  }
  // Reuse an unpaid Razorpay order for the same amount (the patient tried before).
  const saved = kind === 'fee' ? s.record.razorpayOrderId : s.record.pay?.razorpayOrderId;
  const savedAmount = kind === 'fee' ? s.record.razorpayOrderAmount : s.record.pay?.razorpayOrderAmount;
  let orderId = saved && savedAmount === s.amount ? saved : null;
  if (!orderId) {
    const resp = await fetchImpl('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: { authorization: auth(), 'content-type': 'application/json' },
      body: JSON.stringify({
        amount: Math.round(s.amount * 100), currency: 'INR', receipt: `${kind}_${String(id).slice(-12)}`.slice(0, 40),
        notes: { kind, id: String(id), ...(kind === 'fee' ? { paymentId: String(s.record._id) } : { orderId: String(id) }) },
      }),
      signal: AbortSignal.timeout(10000),
    });
    const d = await resp.json().catch(() => ({}));
    if (!resp.ok || !d.id) throw Object.assign(conflict(d.error?.description || 'Couldn’t start the payment. Please try again.', 'CHECKOUT_FAILED'), { status: 502 });
    orderId = d.id;
    if (kind === 'fee') Object.assign(s.record, { razorpayOrderId: orderId, razorpayOrderAmount: s.amount });
    else s.record.pay = { ...(s.record.pay?.toObject?.() || {}), method: 'online', razorpayOrderId: orderId, razorpayOrderAmount: s.amount };
    await s.record.save();
  }
  return { ...base, test: false, keyId: env.razorpay.keyId, orderId };
}

const safeEqual = (a, b) => {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

/** Checks Checkout's result and marks the fee / order paid (once). */
async function confirm({ kind, id, orderId, paymentId, signature, patient }) {
  if (!/^[a-f\d]{24}$/i.test(String(id || ''))) throw badRequest('Nothing to pay', 'BAD_ID');
  // The record this Razorpay order was made for — whatever its status is now (the fee may
  // have been settled at the desk meanwhile: then this payment is refunded, not lost).
  let record;
  let amount;
  if (kind === 'fee') {
    const appt = await M.Appointment.findOne({ _id: id, patientId: patient._id }, '_id');
    if (!appt) throw notFound('Appointment');
    record = pay.configured()
      ? await M.Payment.findOne({ appointmentId: appt._id, razorpayOrderId: orderId })
      : await M.Payment.findOne({ appointmentId: appt._id }).sort({ createdAt: -1 });
    amount = record?.razorpayOrderAmount ?? record?.amount;
  } else if (kind === 'order') {
    record = await M.Order.findOne({ _id: id, patientId: patient._id, ...(pay.configured() ? { 'pay.razorpayOrderId': orderId } : {}) });
    amount = record?.pay?.razorpayOrderAmount ?? record?.total;
  } else {
    throw badRequest('Nothing to pay', 'BAD_KIND');
  }
  if (!record) throw badRequest('This payment is for a different order', 'ORDER_MISMATCH');
  if (!pay.configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet', 'PAYMENTS_OFF'), { status: 503 });
    if (orderId !== `order_test_${id}`) throw badRequest('This payment could not be verified', 'BAD_SIGNATURE');
    // One test payment per test order (as Razorpay: confirming again carries the same payment).
    paymentId = `pay_test_${String(id).slice(-12)}${String(record.razorpayOrderId || record.pay?.razorpayOrderId || '').slice(-4)}`;
  } else {
    const want = crypto.createHmac('sha256', env.razorpay.keySecret).update(`${orderId}|${paymentId}`).digest('hex');
    if (!paymentId || !signature || !safeEqual(want, signature)) throw badRequest('This payment could not be verified', 'BAD_SIGNATURE');
  }
  const done = kind === 'fee' ? await pay.feePaid(record._id, paymentId) : await pay.orderPaid(record._id, paymentId);
  if (done) return { paid: true, paymentId, amount };
  // Not marked by this call: the same payment already counted (webhook first) → paid; a
  // different one → it was already settled, and this payment goes back.
  const already = kind === 'fee' ? (await M.Payment.findById(record._id))?.razorpayPaymentId : (await M.Order.findById(record._id))?.pay?.razorpayPaymentId;
  if (already === paymentId) return { paid: true, already: true, paymentId, amount };
  const stray = await M.StrayPayment.findOne({ razorpayPaymentId: paymentId });
  return {
    paid: false, refunded: true, amount,
    message: stray?.status === 'refund_due'
      ? `This was already paid. The clinic will give your ₹${amount} back.`
      : `This was already paid, so your ₹${amount} is being refunded (usually 5–7 working days).`,
  };
}

/** Webhook backup: payment.captured / order.paid carry the order's notes. */
async function onWebhook(event, payload) {
  if (!['payment.captured', 'order.paid'].includes(event)) return false;
  const payment = payload?.payment?.entity || {};
  const order = payload?.order?.entity || {};
  const paymentId = payment.id;
  const amountPaise = payment.amount;
  const orderId = payment.order_id || order.id;
  // A notes object that is empty comes as [] — use the first that has a kind.
  const notes = [payment.notes, order.notes].find((n) => n && !Array.isArray(n) && n.kind) || {};
  // 1. By the Razorpay order MedPin made (in-app Checkout).
  if (orderId) {
    const sub = await M.Subscription.findOne({ 'checkout.orderId': orderId });
    if (sub) {
      await pay.planPaid(sub._id, sub.checkout.planKey, paymentId, { renew: Boolean(sub.checkout.renew) });
      await M.Subscription.updateOne({ _id: sub._id, 'checkout.orderId': orderId }, { $unset: { checkout: 1 } });
      return true;
    }
    const fee = await M.Payment.findOne({ razorpayOrderId: orderId }, '_id');
    if (fee) return Boolean(await pay.feePaid(fee._id, paymentId, { amountPaise })) || true;
    const med = await M.Order.findOne({ 'pay.razorpayOrderId': orderId }, '_id');
    if (med) return Boolean(await pay.orderPaid(med._id, paymentId, { amountPaise })) || true;
  }
  // 2. By the notes (payment links carry them; handled by payment_link.paid too — same payment, once).
  if (notes.kind === 'fee' && /^[a-f\d]{24}$/i.test(notes.paymentId || '')) await pay.feePaid(notes.paymentId, paymentId, { amountPaise });
  else if (notes.kind === 'order' && /^[a-f\d]{24}$/i.test(notes.orderId || '')) await pay.orderPaid(notes.orderId, paymentId, { amountPaise });
  else if (notes.kind === 'plan' && /^[a-f\d]{24}$/i.test(notes.subscriptionId || '')) await pay.planPaid(notes.subscriptionId, notes.planKey, paymentId, { renew: notes.renew === '1' });
  else return false;
  return true;
}

// ── A clinic's MedPin plan (Plan & billing), paid in the app ──

/** What a plan payment buys: the next month (renew) or an upgrade now. Throws when not payable. */
async function planSubject(sub, planKey, renew) {
  const B = require('./billing');
  if (!sub) throw notFound('Subscription');
  await B.refreshStatus(sub);
  if (renew) {
    const next = await B.renewal(sub);
    if (!next?.canPay) throw conflict('Your plan is paid for now. You can pay for the next month from 7 days before it ends.', 'NOT_DUE_YET');
    const plan = await M.Plan.findOne({ key: next.planKey, active: true });
    if (!plan) throw badRequest('Choose a plan');
    return { plan, renew: true };
  }
  const plan = await M.Plan.findOne({ key: planKey, active: true });
  if (!plan) throw badRequest('Choose a plan');
  if (plan.key === sub.planKey) throw conflict('You are already on this plan');
  if (!((plan.priceMonthly || 0) > (sub.price || 0))) throw conflict('A smaller plan starts from your next month: no payment now', 'NO_PAYMENT_NEEDED');
  const seats = await M.Member.countDocuments({ practiceId: sub.practiceId, status: 'active' });
  if (seats > plan.seats) throw conflict(`Your team has ${seats} people, so ${seats - plan.seats} would need to be removed first`, 'TOO_MANY_SEATS');
  return { plan, renew: false };
}

/** Starts the in-app payment for a plan: a Razorpay Order, or a test one without keys (dev only). */
async function planStart({ sub, planKey, renew, user }) {
  const s = await planSubject(sub, planKey, renew);
  const amount = s.plan.priceMonthly;
  const base = {
    kind: 'plan', id: s.plan.key, renew: s.renew, amount, currency: 'INR',
    title: `MedPin ${s.plan.name} plan`, detail: s.renew ? 'The next month' : '1 month, starting today',
    prefill: { name: user.name, contact: user.phone ? `+91${user.phone}` : undefined },
  };
  if (!pay.configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet. Contact MedPin support to renew.', 'PAYMENTS_OFF'), { status: 503 });
    const orderId = `order_test_plan_${sub._id}`;
    sub.checkout = { orderId, planKey: s.plan.key, renew: s.renew, amount, startedAt: new Date() };
    await sub.save();
    return { ...base, test: true, orderId };
  }
  // The same unpaid order again (tried before, same plan and amount).
  const c = sub.checkout;
  let orderId = c?.orderId && c.planKey === s.plan.key && Boolean(c.renew) === s.renew && c.amount === amount && !String(c.orderId).startsWith('order_test') ? c.orderId : null;
  if (!orderId) {
    const resp = await fetchImpl('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: { authorization: auth(), 'content-type': 'application/json' },
      body: JSON.stringify({
        amount: Math.round(amount * 100), currency: 'INR', receipt: `plan_${String(sub._id).slice(-12)}`,
        notes: { kind: 'plan', subscriptionId: String(sub._id), planKey: s.plan.key, ...(s.renew ? { renew: '1' } : {}) },
      }),
      signal: AbortSignal.timeout(10000),
    });
    const d = await resp.json().catch(() => ({}));
    if (!resp.ok || !d.id) throw Object.assign(conflict(d.error?.description || 'Couldn’t start the payment. Please try again.', 'CHECKOUT_FAILED'), { status: 502 });
    orderId = d.id;
    sub.checkout = { orderId, planKey: s.plan.key, renew: s.renew, amount, startedAt: new Date() };
    await sub.save();
  }
  return { ...base, test: false, keyId: env.razorpay.keyId, orderId };
}

/** Checks Checkout's signed result and moves the plan on (once; the webhook may have done it). */
async function planConfirm({ sub, orderId, paymentId, signature }) {
  const c = sub?.checkout;
  if (!c?.orderId || c.orderId !== orderId) throw badRequest('This payment is for a different order', 'ORDER_MISMATCH');
  if (!pay.configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet', 'PAYMENTS_OFF'), { status: 503 });
    paymentId = `pay_test_plan_${String(sub._id).slice(-10)}${Date.now().toString(36)}`;
  } else {
    const want = crypto.createHmac('sha256', env.razorpay.keySecret).update(`${orderId}|${paymentId}`).digest('hex');
    if (!paymentId || !signature || !safeEqual(want, signature)) throw badRequest('This payment could not be verified', 'BAD_SIGNATURE');
  }
  await pay.planPaid(sub._id, c.planKey, paymentId, { renew: Boolean(c.renew) });
  await M.Subscription.updateOne({ _id: sub._id, 'checkout.orderId': orderId }, { $unset: { checkout: 1 } });
  return { paid: true, paymentId, amount: c.amount };
}

module.exports = {
  start, confirm, onWebhook, planStart, planConfirm,
  set fetchImpl(f) { fetchImpl = f; },
  get fetchImpl() { return fetchImpl; },
};

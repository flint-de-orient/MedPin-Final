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
  const s = await subject(kind, id, patient).catch((err) => {
    // Already paid (a webhook got there first) counts as success.
    if (err.code === 'NOT_PENDING' || err.code === 'ALREADY_PAID') return null;
    throw err;
  });
  if (!s) return { paid: true, already: true };
  if (!pay.configured()) {
    if (env.isProd) throw Object.assign(conflict('Online payment is not set up yet', 'PAYMENTS_OFF'), { status: 503 });
    if (orderId !== `order_test_${id}`) throw badRequest('This payment could not be verified', 'BAD_SIGNATURE');
    paymentId = `pay_test_${Date.now().toString(36)}`;
  } else {
    const expected = kind === 'fee' ? s.record.razorpayOrderId : s.record.pay?.razorpayOrderId;
    if (!orderId || orderId !== expected) throw badRequest('This payment is for a different order', 'ORDER_MISMATCH');
    const want = crypto.createHmac('sha256', env.razorpay.keySecret).update(`${orderId}|${paymentId}`).digest('hex');
    if (!paymentId || !signature || !safeEqual(want, signature)) throw badRequest('This payment could not be verified', 'BAD_SIGNATURE');
  }
  if (kind === 'fee') await pay.feePaid(s.record._id, paymentId);
  else await pay.orderPaid(s.record._id, paymentId);
  return { paid: true, paymentId, amount: s.amount };
}

/** Webhook backup: payment.captured / order.paid carry the order's notes. */
async function onWebhook(event, payload) {
  const entity = payload?.payment?.entity || payload?.order?.entity || {};
  const notes = entity.notes || payload?.order?.entity?.notes || {};
  const paymentId = payload?.payment?.entity?.id;
  if (!['payment.captured', 'order.paid'].includes(event)) return false;
  if (notes.kind === 'fee' && /^[a-f\d]{24}$/i.test(notes.paymentId || '')) await pay.feePaid(notes.paymentId, paymentId);
  else if (notes.kind === 'order' && /^[a-f\d]{24}$/i.test(notes.orderId || '')) await pay.orderPaid(notes.orderId, paymentId);
  else return false;
  return true;
}

module.exports = {
  start, confirm, onWebhook,
  set fetchImpl(f) { fetchImpl = f; },
  get fetchImpl() { return fetchImpl; },
};

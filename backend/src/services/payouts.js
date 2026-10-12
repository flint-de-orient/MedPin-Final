// Paying doctors their online consultation fees.
//
// Every fee a patient pays online through MedPin waits two days (refund
// window), then the weekly run (Mondays) bundles each doctor's fees into one
// payout. The fee goes to the doctor who saw the patient, or the clinic owner
// when that doctor has no payout details. With RazorpayX set up
// (RAZORPAYX_ACCOUNT_NUMBER + the Razorpay keys) the money is sent to the
// doctor's UPI ID or bank account; otherwise the payout waits as "pending".
const env = require('../config/env');
const M = require('../models');
const T = require('../lib/time');
const { notify } = require('./notify');

const configured = () => Boolean(env.razorpay.keyId && env.razorpay.keySecret && env.razorpay.payoutAccountNumber);
const HOLD_DAYS = 2;

async function rzp(path, body) {
  const resp = await fetch(`https://api.razorpay.com/v1/${path}`, {
    method: 'POST',
    headers: {
      authorization: `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`,
      'content-type': 'application/json',
      ...(path === 'payouts' ? { 'X-Payout-Idempotency': body.reference_id } : {}),
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(json.error?.description || `Razorpay ${resp.status}`);
  return json;
}

const hasDetails = (p) => Boolean(p?.payout?.upiId || (p?.payout?.bankAccountLast4 && p?.payout?.ifsc));

/**
 * Makes the RazorpayX contact and fund account for a doctor's payout details.
 * Bank accounts need the full number, so this runs when the doctor saves them
 * ([accountNumber]); MedPin itself only keeps the last 4 digits.
 */
async function linkPayoutAccount(profile, accountNumber) {
  if (!configured()) return profile;
  const po = profile.payout || {};
  const preferBank = po.preferred === 'bank' || (!po.upiId && po.bankAccountLast4);
  const target = preferBank ? `bank:${po.bankAccountLast4}` : po.upiId ? `upi:${po.upiId}` : null;
  if (!target || po.fundAccountFor === target) return profile;
  if (preferBank && !accountNumber) return profile; // can't make a bank fund account without the full number
  if (!po.razorpayContactId) {
    const c = await rzp('contacts', { name: po.accountHolder || profile.displayName, type: 'vendor', reference_id: String(profile.userId) });
    po.razorpayContactId = c.id;
  }
  const fa = await rzp('fund_accounts', preferBank
    ? { contact_id: po.razorpayContactId, account_type: 'bank_account', bank_account: { name: po.accountHolder || profile.displayName, ifsc: po.ifsc, account_number: accountNumber } }
    : { contact_id: po.razorpayContactId, account_type: 'vpa', vpa: { address: po.upiId } });
  po.razorpayFundAccountId = fa.id;
  po.fundAccountFor = target;
  profile.payout = po;
  return profile;
}

/** Who gets this fee: the appointment's doctor (with payout details) or the clinic owner. */
async function payeeFor(payment, cache) {
  const appt = payment.appointmentId ? await M.Appointment.findById(payment.appointmentId, 'doctorId') : null;
  const owner = async () => {
    if (!cache.has(`owner:${payment.practiceId}`)) cache.set(`owner:${payment.practiceId}`, (await M.Practice.findById(payment.practiceId, 'ownerUserId'))?.ownerUserId);
    return cache.get(`owner:${payment.practiceId}`);
  };
  if (appt?.doctorId) {
    const key = `prof:${appt.doctorId}`;
    if (!cache.has(key)) cache.set(key, await M.DoctorProfile.findOne({ userId: appt.doctorId }, 'payout'));
    if (hasDetails(cache.get(key))) return appt.doctorId;
  }
  return owner();
}

/** Sends one payout (or says why it waits). */
async function send(payout) {
  const prof = await M.DoctorProfile.findOne({ userId: payout.doctorId });
  const po = prof?.payout;
  if (!hasDetails(prof)) {
    Object.assign(payout, { status: 'on_hold', note: 'Add your UPI ID or bank account in Payouts to receive this.' });
    return payout.save();
  }
  const bank = po.preferred === 'bank' || !po.upiId;
  Object.assign(payout, { method: bank ? 'bank' : 'upi', destination: bank ? `${po.bankName || 'Bank'} ····${po.bankAccountLast4}` : po.upiId });
  if (!configured()) {
    Object.assign(payout, { status: 'pending', note: 'Payouts are being set up. Your balance is safe and will be paid.' });
    return payout.save();
  }
  try {
    if (!po.razorpayFundAccountId) await linkPayoutAccount(prof).then((p) => p.save());
    if (!prof.payout.razorpayFundAccountId) {
      Object.assign(payout, { status: 'on_hold', note: 'Re-enter your bank account in Payouts so it can be verified.' });
      return payout.save();
    }
    const p = await rzp('payouts', {
      account_number: env.razorpay.payoutAccountNumber, fund_account_id: prof.payout.razorpayFundAccountId,
      amount: Math.round(payout.amount * 100), currency: 'INR', mode: bank ? 'IMPS' : 'UPI', purpose: 'payout',
      queue_if_low_balance: true, reference_id: String(payout._id), narration: 'MedPin consultation fees',
    });
    Object.assign(payout, { status: 'processing', razorpayPayoutId: p.id, note: undefined });
  } catch (err) {
    Object.assign(payout, { status: 'failed', note: `Couldn't send: ${String(err.message).slice(0, 160)}. We'll try again.` });
  }
  return payout.save();
}

/** The weekly run: bundles fees older than the hold period into payouts and sends them. */
async function run(now = new Date()) {
  const cutoff = T.addDays(now, -HOLD_DAYS);
  const fees = await M.Payment.find({ status: 'paid', method: 'online', payoutId: null, paidAt: { $lte: cutoff } }).limit(5000);
  const cache = new Map();
  const groups = new Map();
  for (const f of fees) {
    const payee = await payeeFor(f, cache);
    if (!payee) continue;
    const key = `${f.practiceId}:${payee}`;
    if (!groups.has(key)) groups.set(key, { practiceId: f.practiceId, doctorId: payee, fees: [] });
    groups.get(key).fees.push(f);
  }
  const out = [];
  for (const g of groups.values()) {
    const amount = g.fees.reduce((n, f) => n + (f.amount || 0), 0);
    if (amount <= 0) continue;
    const dates = g.fees.map((f) => f.paidAt).sort((a, b) => a - b);
    const payout = await M.Payout.create({ practiceId: g.practiceId, doctorId: g.doctorId, amount, count: g.fees.length, periodFrom: dates[0], periodTo: dates[dates.length - 1] });
    await M.Payment.updateMany({ _id: { $in: g.fees.map((f) => f._id) }, payoutId: null }, { payoutId: payout._id });
    await send(payout);
    await notify([g.doctorId], {
      type: 'payout', practiceId: g.practiceId,
      title: payout.status === 'processing' ? `₹${amount} on its way to you` : `₹${amount} in online fees`,
      body: payout.status === 'processing' ? `${g.fees.length} online fees · to ${payout.destination}` : payout.note,
      screen: 'Profile-Payouts',
    }).catch(() => {});
    out.push(payout);
  }
  // Earlier payouts that waited or failed are tried again.
  for (const p of await M.Payout.find({ status: { $in: ['pending', 'on_hold', 'failed'] }, createdAt: { $lt: T.addDays(now, -1) } }).limit(200)) {
    await send(p);
  }
  return out;
}

/** Razorpay payout webhooks: processed / failed / reversed. */
async function onWebhook(event, entity) {
  const p = await M.Payout.findOne({ razorpayPayoutId: entity?.id });
  if (!p) return;
  if (event === 'payout.processed') Object.assign(p, { status: 'paid', paidAt: new Date(), note: undefined });
  if (event === 'payout.failed' || event === 'payout.reversed') Object.assign(p, { status: 'failed', note: entity.failure_reason || 'The bank returned the payout. Check your details in Payouts.' });
  await p.save();
  if (p.status === 'paid') await notify([p.doctorId], { type: 'payout', practiceId: p.practiceId, title: `₹${p.amount} paid to ${p.destination}`, screen: 'Profile-Payouts' }).catch(() => {});
}

/** What the doctor sees: money waiting, the next payout day, and past payouts. */
async function summary(userId) {
  const practices = await M.Practice.find({ ownerUserId: userId }).distinct('_id');
  const mine = await M.Appointment.find({ doctorId: userId }).distinct('_id');
  const waiting = await M.Payment.find({
    status: 'paid', method: 'online', payoutId: null,
    $or: [{ appointmentId: { $in: mine } }, { practiceId: { $in: practices } }],
  }, 'amount');
  const items = await M.Payout.find({ doctorId: userId }).sort({ createdAt: -1 }).limit(20);
  const today = T.dayStart();
  const next = T.addDays(today, ((8 - (new Date(today.getTime() + T.IST_MS).getUTCDay() || 7)) % 7) || 7);
  return {
    waiting: { amount: waiting.reduce((n, p) => n + (p.amount || 0), 0), count: waiting.length },
    nextPayoutOn: next,
    holdDays: HOLD_DAYS,
    live: configured(),
    items: items.map((p) => ({ id: p._id, amount: p.amount, count: p.count, status: p.status, note: p.note, destination: p.destination, createdAt: p.createdAt, paidAt: p.paidAt })),
  };
}

module.exports = { configured, linkPayoutAccount, run, send, onWebhook, summary };

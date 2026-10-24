// MedPin's own plans for clinics (Plan & billing): the plan catalogue, and the month a
// clinic has paid for. There is no card on file that is charged by itself: when the month
// (or the free trial) ends, the plan is "Payment due" and the owner pays for the next month
// in the app (a Razorpay link). Paid early (from 7 days before), the new month starts when
// the current one ends; paid late, from the day it is paid. Nothing is locked while due.
const M = require('../models');
const T = require('../lib/time');

const PLANS = [
  { key: 'starter', name: 'Starter', priceMonthly: 999, seats: 3, activePatients: 150, aiChatsPerMonth: 1000 },
  { key: 'clinic', name: 'Clinic', priceMonthly: 2499, seats: 8, activePatients: 500, aiChatsPerMonth: 3000 },
  { key: 'hospital', name: 'Hospital', priceMonthly: 7999, seats: 25, activePatients: 2000, aiChatsPerMonth: 12000 },
];

/** The plans exist (a server set up without the seed had none): missing ones are added, never changed. */
async function ensurePlans() {
  if ((await M.Plan.countDocuments({})) >= PLANS.length) return;
  await M.Plan.bulkWrite(PLANS.map((p) => ({ updateOne: { filter: { key: p.key }, update: { $setOnInsert: p }, upsert: true } })));
}

/** Days before the month ends when "Pay for next month" shows. */
const RENEW_FROM_DAYS = 7;

/** The month (or trial) ended without a payment: Payment due. Returns the subscription. */
async function refreshStatus(sub, now = new Date()) {
  if (!sub || !sub.currentPeriodEnd || sub.currentPeriodEnd > now) return sub;
  if (!['active', 'trialing'].includes(sub.status)) return sub;
  const updated = await M.Subscription.findOneAndUpdate(
    { _id: sub._id, status: { $in: ['active', 'trialing'] }, currentPeriodEnd: { $lte: now } },
    { status: 'past_due', ...(sub.status === 'trialing' ? { trialEndedAt: sub.currentPeriodEnd } : {}) },
    { new: true },
  );
  return updated || sub;
}

/** What paying now gets: the plan of the next month (a switch chosen for it), its price, whether it can be paid yet. */
async function renewal(sub, now = new Date()) {
  if (!sub) return null;
  const plan = await M.Plan.findOne({ key: sub.pendingPlanKey || sub.planKey });
  const end = sub.currentPeriodEnd;
  const due = sub.status === 'past_due';
  const soon = !due && end && end - now <= RENEW_FROM_DAYS * 864e5 && sub.status !== 'cancelled';
  return {
    due, canPay: Boolean(plan && (due || soon)), planKey: plan?.key, planName: plan?.name, amount: plan?.priceMonthly,
    dueSince: due ? end : null, trialEnded: due && Boolean(sub.trialEndedAt),
    from: due || !end ? null : end, // paid early: the new month starts then
  };
}

/**
 * "MP/26-27/0007": MedPin's invoice numbers, one unbroken series per financial year
 * (April to March), at most 16 characters (GST rules).
 */
async function invoiceNumber(at = new Date()) {
  const ist = new Date(at.getTime() + T.IST_MS);
  const start = ist.getUTCMonth() >= 3 ? ist.getUTCFullYear() : ist.getUTCFullYear() - 1;
  const fy = `${String(start).slice(-2)}-${String(start + 1).slice(-2)}`;
  const n = await M.Counter.next(`invoice:fy${fy}`);
  return `MP/${fy}/${String(n).padStart(4, '0')}`;
}

/** Owners and managers are told the plan needs paying (in the app; once per month that ended). */
async function remindDue(now = new Date()) {
  const ending = await M.Subscription.find({ status: { $in: ['active', 'trialing'] }, currentPeriodEnd: { $lte: now } }).limit(200);
  const { notify } = require('./notify');
  const { once } = require('./jobs');
  for (const s of ending) {
    const sub = await refreshStatus(s, now);
    if (sub.status !== 'past_due') continue;
    await once(`plan_due:${sub._id}:${T.dayKey(sub.currentPeriodEnd)}`, async () => {
      const members = await M.Member.find({ practiceId: sub.practiceId, status: 'active', $or: [{ isOwner: true }, { role: 'practice_manager' }] }, 'userId');
      await notify(members.map((m) => m.userId), {
        type: 'plan_due', practiceId: sub.practiceId,
        title: sub.trialEndedAt ? 'Your MedPin free trial has ended' : 'Your MedPin plan is due for renewal',
        body: 'Pay for the next month in Plan and billing',
        screen: 'Billing',
      });
    });
  }
}

/** Replaced in tests so they never call Razorpay. */
let fetchImpl = (url, opts) => fetch(url, opts);
const lastCheck = new Map(); // subscription id → when Razorpay was last asked (at most once a minute)

/**
 * A plan paid through a payment link while Razorpay's webhook didn't reach MedPin (not set up,
 * the server was down): MedPin asks Razorpay for this clinic's plan links that are paid and
 * applies each payment once. Run when Plan & billing opens and by the 15-minute job.
 * Returns how many payments were applied.
 */
async function reconcilePlanLinks(sub, { force = false } = {}) {
  const pay = require('./payments');
  if (!sub || !pay.configured()) return 0;
  const key = String(sub._id);
  if (!force && Date.now() - (lastCheck.get(key) || 0) < 60e3) return 0;
  lastCheck.set(key, Date.now());
  const env = require('../config/env');
  const auth = `Basic ${Buffer.from(`${env.razorpay.keyId}:${env.razorpay.keySecret}`).toString('base64')}`;
  let links = [];
  try {
    const r = await fetchImpl('https://api.razorpay.com/v1/payment_links', { headers: { authorization: auth }, signal: AbortSignal.timeout(10000) });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) return 0;
    links = d.payment_links || d.items || [];
  } catch (err) {
    console.warn('[plan links]', err.message);
    return 0;
  }
  let applied = 0;
  for (const l of links) {
    const n = l.notes && !Array.isArray(l.notes) ? l.notes : {};
    if (n.kind !== 'plan' || n.subscriptionId !== key || l.status !== 'paid') continue;
    let payments = Array.isArray(l.payments) ? l.payments : [];
    if (!payments.length) {
      const one = await fetchImpl(`https://api.razorpay.com/v1/payment_links/${l.id}`, { headers: { authorization: auth }, signal: AbortSignal.timeout(10000) }).then((x) => x.json()).catch(() => ({}));
      payments = Array.isArray(one.payments) ? one.payments : [];
    }
    for (const p of payments) {
      const id = p.payment_id || p.id;
      if (!id || (p.status && !['captured', 'authorized', 'paid'].includes(p.status))) continue;
      if (await M.Invoice.exists({ razorpayPaymentId: id })) continue;
      await pay.planPaid(sub._id, n.planKey, id, { renew: n.renew === '1' });
      applied += 1;
    }
  }
  if (applied) console.log(`[plan links] ${applied} plan payment(s) applied for ${key}`);
  return applied;
}

/** The 15-minute job: clinics with a plan link made in the last 10 days, or a plan due. */
async function reconcileAll(now = new Date()) {
  const subs = await M.Subscription.find({ $or: [{ planLinkAt: { $gte: T.addDays(now, -10) } }, { status: 'past_due' }] }).limit(100);
  for (const s of subs) await reconcilePlanLinks(s, { force: true }).catch((err) => console.warn('[plan links]', err.message));
}

module.exports = {
  PLANS, ensurePlans, refreshStatus, renewal, invoiceNumber, remindDue, RENEW_FROM_DAYS, reconcilePlanLinks, reconcileAll,
  set fetchImpl(f) { fetchImpl = f; },
  get fetchImpl() { return fetchImpl; },
};

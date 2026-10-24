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

/** "MP-2026-0007": MedPin's invoice numbers, one series a year. */
async function invoiceNumber(at = new Date()) {
  const year = new Date(at.getTime() + T.IST_MS).getUTCFullYear();
  const n = await M.Counter.next(`invoice:${year}`);
  return `MP-${year}-${String(n).padStart(4, '0')}`;
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

module.exports = { PLANS, ensurePlans, refreshStatus, renewal, invoiceNumber, remindDue, RENEW_FROM_DAYS };

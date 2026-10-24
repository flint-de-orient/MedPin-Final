// Subscription billing and the patient pharmacy flow
// (Billing, People seat banner, Med-AddToCart, Med-Cart, Med-Pharmacy).
const { Schema, model } = require('mongoose');
const E = require('./enums');
const { ref, rupees, enumOf, fileSchema, pointSchema, anyPhone, baseOptions } = require('./common');

// Starter ₹999 · 3 seats · 150 patients · 1,000 AI chats; Clinic; Hospital.
const planSchema = new Schema(
  {
    key: enumOf(E.PLAN_KEYS, { required: true, unique: true }),
    name: { type: String, required: true },
    priceMonthly: { ...rupees, required: true },
    seats: { type: Number, required: true },
    activePatients: { type: Number, required: true },
    aiChatsPerMonth: { type: Number, required: true },
    razorpayPlanId: String,
    active: { type: Boolean, default: true },
  },
  baseOptions,
);

const subscriptionSchema = new Schema(
  {
    practiceId: { ...ref('Practice', true), unique: true },
    planKey: enumOf(E.PLAN_KEYS, { required: true }),
    status: enumOf(E.SUBSCRIPTION_STATUSES, { default: 'active' }),
    interval: enumOf(E.BILLING_INTERVALS, { default: 'monthly' }),
    price: rupees,
    currentPeriodStart: Date,
    currentPeriodEnd: Date, // "Renews 14 Oct 2026" / usage "resets 14 Oct 2026"
    pendingPlanKey: enumOf(E.PLAN_KEYS), // switches from the next cycle
    pendingFrom: Date,
    trialEndedAt: Date, // the free trial ran out without a paid month ("Your free trial has ended")
    // The in-app payment started for a plan (Razorpay Checkout): its order and what it buys.
    checkout: {
      orderId: String,
      planKey: String,
      renew: Boolean,
      amount: Number,
      startedAt: Date,
      _id: false,
    },
    planLinkAt: Date, // a payment link for a plan was made: checked with Razorpay until paid
    razorpayCustomerId: String,
    razorpaySubscriptionId: String,
    cancelledAt: Date,
  },
  baseOptions,
);

const invoiceSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    number: { type: String, unique: true, sparse: true },
    issuedAt: { type: Date, required: true },
    description: String, // "Clinic plan · monthly"
    amount: { ...rupees, required: true },
    status: enumOf(E.INVOICE_STATUSES, { default: 'due' }),
    periodStart: Date,
    periodEnd: Date,
    file: fileSchema,
    razorpayInvoiceId: String,
    razorpayPaymentId: String,
    paidAt: Date,
  },
  baseOptions,
);
invoiceSchema.index({ practiceId: 1, issuedAt: -1 });

// Metered usage per billing cycle ("AI chats this month 1,860 / 3,000").
const usageCounterSchema = new Schema(
  {
    practiceId: ref('Practice', true),
    periodStart: { type: Date, required: true },
    aiChats: { type: Number, default: 0 },
  },
  baseOptions,
);
usageCounterSchema.index({ practiceId: 1, periodStart: 1 }, { unique: true });

const pharmacySchema = new Schema(
  {
    name: { type: String, required: true }, // "CarePlus Online"
    type: enumOf(E.PHARMACY_TYPES, { required: true }),
    practiceId: ref('Practice'), // clinic's own pharmacy
    locationId: ref('Location'),
    address: String,
    geo: pointSchema,
    phone: anyPhone,
    email: { type: String, trim: true, lowercase: true },
    deliveryFee: { ...rupees, default: 0 },
    freeDeliveryAbove: rupees,
    discountPct: { type: Number, min: 0, max: 50, default: 0 }, // off MRP
    deliveryEtaText: String, // "Delivers tomorrow by 11 AM"
    pickupEtaMin: Number, // "Ready in 30 min"
    active: { type: Boolean, default: true },
  },
  baseOptions,
);
pharmacySchema.index({ geo: '2dsphere' });

const cartItemSchema = new Schema({
  courseId: ref('MedicationCourse'),
  medicineId: ref('Medicine'),
  name: { type: String, required: true },
  strength: String,
  prescriberName: String,
  strips: { type: Number, min: 1, max: 99, default: 1 },
  unitsPerStrip: { type: Number, default: 10 },
  packOption: enumOf(['till_next_visit', '1_month', '3_months', 'custom']),
});

const cartSchema = new Schema(
  {
    patientId: { ...ref('Patient', true), unique: true },
    items: [cartItemSchema],
  },
  baseOptions,
);

const orderSchema = new Schema(
  {
    patientId: ref('Patient', true),
    pharmacyId: ref('Pharmacy', true),
    mode: enumOf(E.ORDER_MODES, { required: true }),
    items: [
      {
        name: { type: String, required: true },
        strength: String,
        courseId: { type: Schema.Types.ObjectId, ref: 'MedicationCourse' },
        unitsPerStrip: { type: Number, default: 10 },
        strips: { type: Number, min: 1 },
        unitPrice: rupees,
        lineTotal: rupees,
        inStock: { type: Boolean, default: true },
      },
    ],
    prescriptionIds: [{ type: Schema.Types.ObjectId, ref: 'Prescription' }],
    prescriptionRecordIds: [{ type: Schema.Types.ObjectId, ref: 'MedicalRecord' }], // prescription photos the patient uploaded
    deliveryAddress: { line: String, area: String, city: String, pincode: String },
    subtotal: rupees,
    // Every line has a price (false: some are priced by the pharmacy at the counter — no online pay).
    priced: { type: Boolean, default: true },
    deliveryFee: { ...rupees, default: 0 },
    total: { ...rupees, required: true },
    status: enumOf(E.ORDER_STATUSES, { default: 'placed' }),
    statusHistory: [{ status: enumOf(E.ORDER_STATUSES), at: Date, _id: false }],
    etaText: String,
    deliveredAt: Date,
    cancelledAt: Date,
    cancelledBy: enumOf(['patient', 'pharmacy']),
    paymentId: ref('Payment'),
    // How the patient pays: cash / at the counter, or online through MedPin (Razorpay).
    pay: {
      method: enumOf(['cash', 'online'], { default: 'cash' }),
      status: enumOf(['due', 'paid', 'refund_pending', 'refunded'], { default: 'due' }),
      linkUrl: String,
      linkId: String, // Razorpay's id for the link: cancelled when the order is paid, cancelled or delivered
      paidAt: Date,
      razorpayPaymentId: String,
      razorpayOrderId: String, // in-app Checkout (services/checkout.js)
      razorpayOrderAmount: Number,
      refundedAt: Date,
    },
    // The pharmacy confirms / packs / delivers through a private link (no account needed).
    pharmacyTokenHash: { type: String, select: false },
    pharmacyNotifiedAt: Date,
  },
  baseOptions,
);
orderSchema.index({ patientId: 1, createdAt: -1 });

module.exports = {
  Plan: model('Plan', planSchema),
  Subscription: model('Subscription', subscriptionSchema),
  Invoice: model('Invoice', invoiceSchema),
  UsageCounter: model('UsageCounter', usageCounterSchema),
  Pharmacy: model('Pharmacy', pharmacySchema),
  Cart: model('Cart', cartSchema),
  Order: model('Order', orderSchema),
};

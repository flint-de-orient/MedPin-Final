// Pharmacy orders: the pharmacy is told (WhatsApp / email with a private link),
// moves the order along on that page, and the patient hears about each step.
// When it's delivered or picked up, the medicines' stock goes up.
const M = require('../models');
const storage = require('./storage');
const { notify, practiceStaff } = require('./notify');
const { sendWhatsApp } = require('./push');
const { sendEmail } = require('./email');
const { publicBase } = require('../lib/request-base');

const NEXT = {
  delivery: { placed: ['confirmed', 'cancelled'], confirmed: ['packed', 'cancelled'], packed: ['out_for_delivery'], out_for_delivery: ['delivered'] },
  pickup: { placed: ['confirmed', 'cancelled'], confirmed: ['ready_for_pickup', 'cancelled'], ready_for_pickup: ['picked_up'] },
};
const LABEL = {
  placed: 'Placed', confirmed: 'Confirmed', packed: 'Packed', out_for_delivery: 'Out for delivery', ready_for_pickup: 'Ready for pick-up',
  delivered: 'Delivered', picked_up: 'Picked up', cancelled: 'Cancelled',
};
const PATIENT_TEXT = {
  confirmed: 'The pharmacy confirmed your order',
  packed: 'Your medicines are packed',
  out_for_delivery: 'Your medicines are on the way',
  ready_for_pickup: 'Your medicines are ready to pick up',
  delivered: 'Your medicines were delivered',
  picked_up: 'Order collected',
  cancelled: 'Your order was cancelled',
};

const linkFor = (order, token) => `${publicBase()}/pharmacy/orders/${order._id}?t=${token}`;

/** Sends the new order to the pharmacy (and the clinic's desk for a clinic pharmacy). */
async function notifyPharmacy(order, pharmacy, patient, token) {
  const link = linkFor(order, token);
  const lines = order.items.map((i) => `${i.name}${i.strength ? ` ${i.strength}` : ''} × ${i.strips} strip${i.strips === 1 ? '' : 's'}`).join(', ');
  const text = `New MedPin order from ${patient.name}: ${lines}. ${order.mode === 'delivery' ? 'Home delivery' : 'Pick-up'} · ₹${order.total}. Open: ${link}`;
  if (pharmacy.phone) await sendWhatsApp(pharmacy.phone, text, { template: 'pharmacy_order', params: [patient.name, lines, `₹${order.total}`, link] });
  if (pharmacy.email) await sendEmail({ to: pharmacy.email, subject: `New MedPin order · ${patient.name}`, text });
  if (pharmacy.practiceId) {
    const desk = await practiceStaff(pharmacy.practiceId, { roles: ['front_desk', 'practice_manager'] });
    await notify(desk, { type: 'pharmacy_order', practiceId: pharmacy.practiceId, title: `Pharmacy order from ${patient.name}`, body: lines });
  }
  order.pharmacyNotifiedAt = new Date();
  await order.save();
}

/** Moves the order to [status] if allowed; tells the patient; adds stock when it arrives. */
async function setStatus(order, status, { by } = {}) {
  const allowed = status === 'cancelled' && by === 'patient' ? ['placed', 'confirmed'] : Object.keys(NEXT[order.mode]).filter((s) => NEXT[order.mode][s].includes(status));
  if (!allowed.includes(order.status)) {
    throw Object.assign(new Error(`Can't change an order from "${LABEL[order.status]}" to "${LABEL[status] || status}"`), { status: 409, code: 'BAD_STATUS' });
  }
  order.status = status;
  order.statusHistory.push({ status, at: new Date() });
  if (status === 'cancelled') {
    order.cancelledAt = new Date();
    order.cancelledBy = by === 'patient' ? 'patient' : 'pharmacy';
  }
  if (status === 'delivered' || status === 'picked_up') {
    order.deliveredAt = new Date();
    // The medicines arrived: their stock goes up by what was bought.
    for (const item of order.items) {
      if (!item.courseId) continue;
      const course = await M.MedicationCourse.findOne({ _id: item.courseId, patientId: order.patientId });
      if (!course) continue;
      course.stockUnits = (course.stockUnits || 0) + (item.strips || 1) * (item.unitsPerStrip || 10);
      await course.save();
    }
  }
  await order.save();
  // A paid order that is cancelled is refunded.
  if (status === 'cancelled' && order.pay?.status === 'paid') await require('./payments').refundOrder(order);
  if (by !== 'patient') {
    const patient = await M.Patient.findById(order.patientId, 'userId');
    if (patient?.userId) {
      await notify([patient.userId], { type: 'order_update', title: PATIENT_TEXT[status] || `Order ${LABEL[status]}`, body: order.etaText || undefined, screen: 'Patient-Medicines', params: { orderId: order._id } });
    }
  }
  return order;
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/** The pharmacy's page for one order (opened from the WhatsApp / email link). */
async function pharmacyPage(order, token) {
  const [patient, pharmacy, prescriptions, photos] = await Promise.all([
    M.Patient.findById(order.patientId, 'name phone'),
    M.Pharmacy.findById(order.pharmacyId, 'name'),
    M.Prescription.find({ _id: { $in: order.prescriptionIds } }, 'rxNumber issuedAt doctorName file items'),
    M.MedicalRecord.find({ _id: { $in: order.prescriptionRecordIds || [] } }, 'title sourceName extractedDoctor recordDate files'),
  ]);
  const next = NEXT[order.mode][order.status] || [];
  const rows = order.items.map((i) => `<tr><td>${esc(i.name)} ${esc(i.strength || '')}</td><td>${i.strips} × ${i.unitsPerStrip || 10}</td><td>${i.lineTotal != null ? `₹${i.lineTotal}` : ''}</td></tr>`).join('');
  const rxItems = [
    ...prescriptions.map((p) => `<li><a href="${esc(storage.signedUrl(p.file?.key, 7 * 24 * 3600) || '#')}">Rx ${String(p.rxNumber || '').padStart(4, '0')}</a> · ${esc(p.doctorName || '')} · ${p.issuedAt ? p.issuedAt.toISOString().slice(0, 10) : ''}</li>`),
    ...photos.map((r) => `<li><a href="${esc(storage.signedUrl(r.files?.[0]?.key, 7 * 24 * 3600) || '#')}">Prescription photo</a> · ${esc(r.extractedDoctor || r.sourceName || '')} · ${r.recordDate ? r.recordDate.toISOString().slice(0, 10) : ''}</li>`),
  ];
  const rx = rxItems.length ? rxItems.join('') : '<li>No prescription attached — ask the patient before giving prescription-only medicines.</li>';
  const addr = order.deliveryAddress ? [order.deliveryAddress.line, order.deliveryAddress.area, order.deliveryAddress.city, order.deliveryAddress.pincode].filter(Boolean).join(', ') : '';
  const buttons = next.map((s) => `<button name="status" value="${s}" class="${s === 'cancelled' ? 'ghost' : ''}">${esc(LABEL[s])}</button>`).join(' ');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MedPin order</title>
<style>body{font-family:system-ui,sans-serif;margin:0;background:#F5F7FB;color:#1A2233}main{max-width:560px;margin:0 auto;padding:20px}h1{font-size:22px;margin:4px 0}
.card{background:#fff;border:1px solid #E5E9F0;border-radius:14px;padding:16px;margin:12px 0}table{width:100%;border-collapse:collapse}td{padding:6px 0;border-bottom:1px solid #EEF1F5}
.pill{display:inline-block;background:#EBF1FB;color:#003399;border-radius:99px;padding:3px 10px;font-weight:600;font-size:13px}
button{font:inherit;font-weight:600;background:#003399;color:#fff;border:0;border-radius:10px;padding:12px 16px;margin:4px 4px 0 0}button.ghost{background:#fff;color:#C62828;border:1px solid #F2C4C4}
.muted{color:#5A6474;font-size:14px}</style></head><body><main>
<p class="muted">${esc(pharmacy?.name || 'Pharmacy')} · MedPin</p><h1>Order for ${esc(patient?.name || 'patient')}</h1>
<p><span class="pill">${esc(LABEL[order.status])}</span> · ${order.mode === 'delivery' ? 'Home delivery' : 'Pick-up'} · ${order.pay?.status === 'paid' ? `<b style="color:#076B3C">Paid online ✓ ₹${order.total}</b> · don't collect money` : `Collect ${order.mode === 'delivery' ? 'on delivery' : 'at the counter'}: <b>₹${order.total}</b>`}</p>
<div class="card"><table>${rows}</table>${order.deliveryFee ? `<p class="muted">Delivery ₹${order.deliveryFee}</p>` : ''}</div>
<div class="card"><b>Prescriptions</b><ul>${rx}</ul></div>
<div class="card"><b>Patient</b><p>${esc(patient?.name || '')} · +91 ${esc(patient?.phone || '')}${addr ? `<br>${esc(addr)}` : ''}</p></div>
${buttons ? `<form method="post" action="/pharmacy/orders/${order._id}/status"><input type="hidden" name="t" value="${esc(token)}">${buttons}</form>` : '<p class="muted">Nothing more to do for this order.</p>'}
</main></body></html>`;
}

module.exports = { notifyPharmacy, setStatus, pharmacyPage, LABEL };

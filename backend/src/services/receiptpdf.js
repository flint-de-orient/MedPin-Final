// A fee receipt (A5), like the printed receipt a clinic desk hands over: the clinic's name,
// branch address and phone; the receipt number and date; who paid; the visit (doctor, date);
// what was charged (the consultation, then any extra charges) and the total; how it was paid
// (an online payment's reference, or who took it at the desk); a refund if the money went back.
// Same look as the prescription and the medicine list.
const PDFDocument = require('pdfkit');
const { setupFonts, write } = require('../lib/pdftext');
const T = require('../lib/time');
const M = require('../models');

const C = { primary: '#003399', ink: '#111827', ink2: '#3F4757', ink3: '#555E6F', line: '#E2E6EC', fill: '#F1F4F9', green: '#15803D', red: '#B91C1C' };
const PAGE_W = 419.53;
const PAGE_H = 595.28;
const M0 = 32;
const W = PAGE_W - 2 * M0;
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtDay = (d) => {
  if (!d) return '';
  const [y, m, dd] = T.dayKey(d).split('-');
  return `${Number(dd)} ${MON[Number(m) - 1]} ${y}`;
};
const fmtWhen = (d) => (d ? `${fmtDay(d)}, ${T.fmtTime(T.minuteOfDay(d))}` : '');
const rupees = (n) => `₹${Number(n || 0).toLocaleString('en-IN')}`;
const METHOD = { cash: 'Cash', upi: 'UPI', card: 'Card', net_banking: 'Net banking', online: 'Online (in the app)' };

/** "R-0042": the clinic's own running receipt number. */
const receiptLabel = (n) => (n ? `R-${String(n).padStart(4, '0')}` : '');

/** The receipt number for a paid fee, given once (the next in this clinic's series). */
async function ensureReceiptNo(p) {
  if (p.receiptNo) return p.receiptNo;
  const n = await M.Counter.next(`receipt:${p.practiceId}`);
  const saved = await M.Payment.findOneAndUpdate({ _id: p._id, receiptNo: null }, { receiptNo: n }, { new: true });
  p.receiptNo = saved?.receiptNo || (await M.Payment.findById(p._id, 'receiptNo'))?.receiptNo || n;
  return p.receiptNo;
}

/** What the visit fee was for: "Consultation", "Follow-up consultation", "Report review". */
const visitLabelOf = (a) => (a?.visitType === 'report_review' ? 'Report review'
  : `${a?.visitType === 'follow_up' ? 'Follow-up consultation' : 'Consultation'}${a?.mode === 'video' ? ' (video)' : a?.mode === 'phone' ? ' (phone)' : ''}`);

/**
 * Payments as a list (the patient's Payments, the desk's patient profile): newest first,
 * with what each was for, the receipt number once paid, and whether it can still be paid online.
 */
async function historyRows(q, { limit = 100 } = {}) {
  const rows = await M.Payment.find(q).sort({ createdAt: -1 }).limit(limit)
    .populate('locationId', 'name shortName paymentMethods')
    .populate({ path: 'appointmentId', select: 'startAt doctorId visitType mode status', populate: { path: 'doctorId', select: 'name' } });
  return rows.map((p) => {
    const a = p.appointmentId;
    const cashOnly = p.locationId?.paymentMethods?.length && p.locationId.paymentMethods.every((m) => m === 'cash');
    return {
      id: p.id, amount: p.amount, status: p.status, method: p.method, paidAt: p.paidAt, createdAt: p.createdAt,
      refundedAt: p.refundedAt, refundDue: p.refundDue === true,
      receiptNo: receiptLabel(p.receiptNo) || null, hasReceipt: ['paid', 'refunded'].includes(p.status),
      items: itemsOf(p, visitLabelOf(a)).map(([label, amount]) => ({ label, amount })),
      doctorName: a?.doctorId?.name || null, clinicName: p.locationId?.name || null,
      appointmentId: a?._id || null, visitAt: a?.startAt || null,
      canPayOnline: p.status === 'pending' && !!a && !['cancelled', 'rescheduled'].includes(a.status) && !cashOnly,
    };
  });
}

/** The lines on the receipt: the consultation (what isn't an extra charge), then each extra. */
function itemsOf(p, visitLabel) {
  const extras = (p.charges || []).filter((c) => c.amount > 0);
  const base = (p.amount || 0) - extras.reduce((a, c) => a + c.amount, 0);
  return [...(base > 0 ? [[visitLabel, base]] : []), ...extras.map((c) => [c.label, c.amount])];
}

async function renderReceipt(paymentId) {
  const p = await M.Payment.findById(paymentId)
    .populate('patientId', 'name phone')
    .populate('locationId', 'name address city pincode phone patientPhone')
    .populate('markedPaidBy', 'name')
    .populate({ path: 'appointmentId', select: 'startAt doctorId visitType mode', populate: { path: 'doctorId', select: 'name' } });
  if (!p || !['paid', 'refunded'].includes(p.status)) return null;
  await ensureReceiptNo(p);
  const practice = await M.Practice.findById(p.practiceId, 'name registrationNo');
  const a = p.appointmentId;
  const loc = p.locationId;
  const items = itemsOf(p, visitLabelOf(a));

  return new Promise((resolve, reject) => {
    const doc = setupFonts(new PDFDocument({ size: [PAGE_W, PAGE_H], margin: 0, info: { Title: `Receipt ${receiptLabel(p.receiptNo)}`, Author: practice?.name || 'MedPin', Creator: 'MedPin' } }));
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    // Letterhead: the clinic and the branch it was paid at.
    let y = M0;
    doc.fillColor(C.primary).fontSize(15);
    write(doc, practice?.name || loc?.name || 'Clinic', { x: M0, y, width: W - 120, weight: 'bold' });
    y = doc.y + 2;
    doc.fillColor(C.ink2).fontSize(8.5);
    const addr = [loc?.name && loc.name !== practice?.name ? loc.name : null, loc?.address, [loc?.city, loc?.pincode].filter(Boolean).join(' ')].filter(Boolean).join(', ');
    if (addr) { write(doc, addr, { x: M0, y, width: W - 120 }); y = doc.y + 1; }
    const phone = loc?.patientPhone || loc?.phone;
    const reg = practice?.registrationNo;
    if (phone || reg) { write(doc, [phone ? `Phone ${phone}` : null, reg ? `Reg. ${reg}` : null].filter(Boolean).join(' · '), { x: M0, y, width: W - 120 }); y = doc.y; }
    // Receipt number and date, top right.
    doc.fillColor(C.ink3).fontSize(8);
    write(doc, 'RECEIPT', { x: PAGE_W - M0 - 110, y: M0 + 1, width: 110, align: 'right', weight: 'semi', characterSpacing: 1 });
    doc.fillColor(C.ink).fontSize(12);
    write(doc, receiptLabel(p.receiptNo), { x: PAGE_W - M0 - 110, y: M0 + 13, width: 110, align: 'right', weight: 'bold' });
    doc.fillColor(C.ink2).fontSize(8.5);
    write(doc, fmtDay(p.paidAt || p.createdAt), { x: PAGE_W - M0 - 110, y: M0 + 30, width: 110, align: 'right' });
    y = Math.max(y, M0 + 44) + 12;
    doc.moveTo(M0, y).lineTo(PAGE_W - M0, y).lineWidth(1).strokeColor(C.primary).stroke();
    y += 14;

    // Who paid, for which visit.
    const field = (label, value, x, w) => {
      doc.fillColor(C.ink3).fontSize(7.5);
      write(doc, label.toUpperCase(), { x, y, width: w, characterSpacing: 0.6 });
      doc.fillColor(C.ink).fontSize(10);
      write(doc, value || '—', { x, y: y + 11, width: w, weight: 'semi' });
      return doc.y;
    };
    const half = (W - 16) / 2;
    const y1 = field('Received from', p.patientId?.name, M0, half);
    const y2 = field('Doctor', a?.doctorId?.name, M0 + half + 16, half);
    y = Math.max(y1, y2) + 10;
    const y3 = field('Visit', a?.startAt ? fmtWhen(a.startAt) : '', M0, half);
    const y4 = field('Mobile', p.patientId?.phone ? `+91 ${p.patientId.phone}` : '', M0 + half + 16, half);
    y = Math.max(y3, y4) + 16;

    // What was charged.
    doc.rect(M0, y, W, 20).fill(C.fill);
    doc.fillColor(C.ink3).fontSize(7.5);
    write(doc, 'DESCRIPTION', { x: M0 + 8, y: y + 7, width: W - 120, characterSpacing: 0.6 });
    write(doc, 'AMOUNT', { x: PAGE_W - M0 - 108, y: y + 7, width: 100, align: 'right', characterSpacing: 0.6 });
    y += 26;
    for (const [label, amount] of items) {
      doc.fillColor(C.ink).fontSize(10);
      write(doc, label, { x: M0 + 8, y, width: W - 130 });
      const h = doc.y;
      write(doc, rupees(amount), { x: PAGE_W - M0 - 108, y, width: 100, align: 'right' });
      y = Math.max(h, doc.y) + 6;
      doc.moveTo(M0, y).lineTo(PAGE_W - M0, y).lineWidth(0.5).strokeColor(C.line).stroke();
      y += 6;
    }
    doc.fillColor(C.ink).fontSize(11);
    write(doc, 'Total paid', { x: M0 + 8, y: y + 2, width: W - 130, weight: 'bold' });
    write(doc, rupees(p.amount), { x: PAGE_W - M0 - 108, y: y + 2, width: 100, align: 'right', weight: 'bold' });
    y = doc.y + 14;

    // How it was paid.
    doc.fillColor(C.ink2).fontSize(9);
    const how = [`Paid by ${METHOD[p.method] || p.method || '—'}`, p.paidAt ? `on ${fmtWhen(p.paidAt)}` : null].filter(Boolean).join(' ');
    write(doc, how, { x: M0, y, width: W });
    y = doc.y + 2;
    if (p.razorpayPaymentId) { write(doc, `Payment reference ${p.razorpayPaymentId}`, { x: M0, y, width: W }); y = doc.y + 2; }
    if (p.method !== 'online' && p.markedPaidBy?.name) { write(doc, `Received by ${p.markedPaidBy.name}`, { x: M0, y, width: W }); y = doc.y + 2; }
    if (p.status === 'refunded') {
      y += 8;
      doc.fillColor(C.red).fontSize(10);
      write(doc, `Refunded${p.refundedAt ? ` on ${fmtDay(p.refundedAt)}` : ''}: ${rupees(p.amount)} given back${p.method === 'online' ? ' to the account it was paid from' : ''}.`, { x: M0, y, width: W, weight: 'semi' });
      y = doc.y;
    }

    // Footer.
    doc.fillColor(C.ink3).fontSize(7.5);
    write(doc, 'A computer-generated receipt; no signature needed. Keep it for your records or insurance claims.', { x: M0, y: PAGE_H - M0 - 18, width: W, align: 'center' });
    write(doc, 'Made with MedPin', { x: M0, y: PAGE_H - M0 - 7, width: W, align: 'center' });
    doc.end();
  });
}

/** The receipt as a file to open or share: made each time (a refund later shows on it). */
async function receiptFile(paymentId) {
  const pdf = await renderReceipt(paymentId);
  if (!pdf) return null;
  const p = await M.Payment.findById(paymentId, 'receiptNo');
  const storage = require('./storage');
  const file = await storage.save(pdf, { folder: 'exports', name: `Receipt ${receiptLabel(p.receiptNo)}.pdf`, mimeType: 'application/pdf' });
  return storage.withUrl(file);
}

module.exports = { renderReceipt, receiptFile, historyRows, ensureReceiptNo, receiptLabel, itemsOf };

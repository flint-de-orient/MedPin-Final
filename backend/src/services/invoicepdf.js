// MedPin's invoice to a clinic for its plan (Plan & billing → Billing history), laid out as an
// Indian GST invoice (CGST Rules, rule 46):
//   · the supplier (MedPin's legal name, address, GSTIN, PAN) and the recipient (the clinic's
//     billing name, address, state and GSTIN when it has one);
//   · a serial number unique in the financial year, the invoice date, the period it covers,
//     the place of supply (state and its GST code);
//   · the line: description, SAC, quantity, rate, taxable value; CGST + SGST when the clinic is
//     in MedPin's state, IGST otherwise (18%); the total in figures and in words;
//   · how it was paid (date, Razorpay payment ID) with a PAID mark, or "Due" with the date;
//   · "computer-generated, no signature needed" and where to write for help.
// MedPin without a GSTIN set (BILLING_GSTIN) is not charging GST: the document is an
// "Invoice" with no tax lines, never a "Tax invoice".
const path = require('path');
const PDFDocument = require('pdfkit');
const { setupFonts, write } = require('../lib/pdftext');
const T = require('../lib/time');
const M = require('../models');
const env = require('../config/env');

const C = { primary: '#003399', primarySoft: '#EBF1FB', ink: '#111827', ink2: '#3F4757', ink3: '#555E6F', line: '#E2E6EC', fill: '#F4F6FA', green: '#15803D', greenSoft: '#E8F5EC', amber: '#B45309', red: '#B91C1C' };
const PAGE_W = 595.28;
const PAGE_H = 841.89;
const M0 = 44;
const W = PAGE_W - 2 * M0;
const LOGO = path.join(__dirname, '..', '..', 'assets', 'images', 'medpin_logo.png');

// GST state codes (the first two digits of a GSTIN).
const STATES = {
  '01': 'Jammu and Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi',
  '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur',
  '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha', '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra and Nagar Haveli and Daman and Diu', '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa',
  '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman and Nicobar Islands', '36': 'Telangana',
  '37': 'Andhra Pradesh', '38': 'Ladakh',
};
const GSTIN = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const codeOfState = (name) => Object.entries(STATES).find(([, n]) => n.toLowerCase() === String(name || '').trim().toLowerCase())?.[0] || null;
const stateOf = (gstin, name) => (gstin && GSTIN.test(gstin) && STATES[gstin.slice(0, 2)] ? { code: gstin.slice(0, 2), name: STATES[gstin.slice(0, 2)] } : codeOfState(name) ? { code: codeOfState(name), name: STATES[codeOfState(name)] } : null);

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtDay = (d) => {
  if (!d) return '';
  const [y, m, dd] = T.dayKey(d).split('-');
  return `${Number(dd)} ${MON[Number(m) - 1]} ${y}`;
};
const money = (n) => `₹${Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const round2 = (n) => Math.round(n * 100) / 100;

// "Two Thousand Four Hundred Ninety-Nine" (Indian grouping: lakh, crore).
const ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
function twoDigits(n) {
  return n < 20 ? ONES[n] : `${TENS[Math.floor(n / 10)]}${n % 10 ? `-${ONES[n % 10]}` : ''}`;
}
function threeDigits(n) {
  const h = Math.floor(n / 100);
  const r = n % 100;
  return [h ? `${ONES[h]} Hundred` : '', r ? twoDigits(r) : ''].filter(Boolean).join(' ');
}
function inWords(amount) {
  const rupees = Math.floor(amount);
  const paise = Math.round((amount - rupees) * 100);
  const parts = [];
  let n = rupees;
  const crore = Math.floor(n / 1e7); n %= 1e7;
  const lakh = Math.floor(n / 1e5); n %= 1e5;
  const thousand = Math.floor(n / 1e3); n %= 1e3;
  if (crore) parts.push(`${threeDigits(crore)} Crore`);
  if (lakh) parts.push(`${twoDigits(lakh)} Lakh`);
  if (thousand) parts.push(`${twoDigits(thousand)} Thousand`);
  if (n) parts.push(threeDigits(n));
  const words = parts.join(' ') || 'Zero';
  return `Rupees ${words}${paise ? ` and ${twoDigits(paise)} Paise` : ''} Only`;
}

/** MedPin as the supplier (server settings; GST only with a valid GSTIN). */
function supplier() {
  const b = env.billing || {};
  const gstin = GSTIN.test(String(b.gstin || '').toUpperCase()) ? String(b.gstin).toUpperCase() : null;
  return {
    name: b.legalName || 'MedPin', address: b.address || '', gstin, pan: b.pan || (gstin ? gstin.slice(2, 12) : null),
    state: stateOf(gstin, b.state), email: b.email || env.support?.email || null, phone: env.support?.phone || null,
    sac: b.sac || '997331', includesGst: b.pricesIncludeGst !== false,
  };
}

/** The tax on one amount: CGST + SGST in MedPin's state, IGST elsewhere; none without a GSTIN. */
function taxOf(amount, from, to) {
  if (!from.gstin) return { taxable: round2(amount), lines: [], total: round2(amount) };
  const taxable = from.includesGst ? round2(amount / 1.18) : round2(amount);
  const tax = from.includesGst ? round2(amount - taxable) : round2(amount * 0.18);
  const intra = !to || !from.state || to.code === from.state.code;
  const lines = intra
    ? [['CGST @ 9%', round2(tax / 2)], ['SGST @ 9%', round2(tax - round2(tax / 2))]]
    : [['IGST @ 18%', tax]];
  return { taxable, lines, total: round2(taxable + tax) };
}

async function renderInvoice(invoiceId) {
  const inv = await M.Invoice.findById(invoiceId);
  if (!inv) return null;
  const practice = await M.Practice.findById(inv.practiceId, 'name billing');
  const loc = await M.Location.findOne({ practiceId: inv.practiceId, status: 'active' }, 'name address city pincode').sort({ createdAt: 1 });
  const from = supplier();
  const bill = practice?.billing || {};
  const to = {
    name: bill.name || practice?.name || 'Clinic',
    address: bill.address || [loc?.address, loc?.city, loc?.pincode].filter(Boolean).join(', '),
    gstin: bill.gstin && GSTIN.test(bill.gstin) ? bill.gstin : null,
  };
  to.state = stateOf(to.gstin, bill.state);
  const tax = taxOf(inv.amount, from, to.state);
  const title = from.gstin ? 'TAX INVOICE' : 'INVOICE';
  const paid = inv.status === 'paid';

  return new Promise((resolve, reject) => {
    const doc = setupFonts(new PDFDocument({ size: 'A4', margin: 0, info: { Title: `Invoice ${inv.number || ''}`.trim(), Author: from.name, Creator: 'MedPin' } }));
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    // ── Supplier (left) · document title and number (right) ──
    let y = M0;
    try { doc.image(LOGO, M0, y, { height: 28 }); } catch { /* no logo file */ }
    y += 38;
    doc.fillColor(C.ink).fontSize(12);
    write(doc, from.name, { x: M0, y, width: W / 2, weight: 'bold' });
    doc.fillColor(C.ink2).fontSize(8.5);
    const fromLines = [from.address, from.state ? `State: ${from.state.name} (code ${from.state.code})` : null, from.gstin ? `GSTIN: ${from.gstin}` : null, from.pan ? `PAN: ${from.pan}` : null, from.email].filter(Boolean);
    for (const l of fromLines) write(doc, l, { x: M0, width: W / 2 });
    const leftEnd = doc.y;

    doc.fillColor(C.primary).fontSize(18);
    write(doc, title, { x: M0 + W / 2, y: M0, width: W / 2, align: 'right', weight: 'bold', characterSpacing: 1 });
    const meta = [
      ['Invoice no.', inv.number || String(inv._id).slice(-8).toUpperCase()],
      ['Invoice date', fmtDay(inv.issuedAt)],
      ...(inv.periodStart && inv.periodEnd ? [['Period', `${fmtDay(inv.periodStart)} – ${fmtDay(T.addDays(inv.periodEnd, -1))}`]] : []),
      ...(from.gstin ? [['Place of supply', to.state ? `${to.state.name} (${to.state.code})` : from.state ? `${from.state.name} (${from.state.code})` : '—']] : []),
      ...(from.gstin ? [['Reverse charge', 'No']] : []),
    ];
    let my = M0 + 30;
    for (const [k, v] of meta) {
      doc.fillColor(C.ink3).fontSize(8.5);
      write(doc, k, { x: M0 + W / 2, y: my, width: W / 2 - 130, align: 'right' });
      doc.fillColor(C.ink).fontSize(9);
      write(doc, v, { x: PAGE_W - M0 - 125, y: my, width: 125, align: 'right', weight: 'semi' });
      my += 15;
    }
    y = Math.max(leftEnd, my) + 16;
    doc.moveTo(M0, y).lineTo(PAGE_W - M0, y).lineWidth(1).strokeColor(C.primary).stroke();
    y += 14;

    // ── Bill to ──
    doc.fillColor(C.ink3).fontSize(7.5);
    write(doc, 'BILL TO', { x: M0, y, width: W, characterSpacing: 0.8 });
    doc.fillColor(C.ink).fontSize(11);
    write(doc, to.name, { x: M0, y: y + 12, width: W, weight: 'bold' });
    doc.fillColor(C.ink2).fontSize(8.5);
    for (const l of [to.address, to.state ? `State: ${to.state.name} (code ${to.state.code})` : null, to.gstin ? `GSTIN: ${to.gstin}` : (from.gstin ? 'GSTIN: not registered' : null)].filter(Boolean)) write(doc, l, { x: M0, width: W * 0.7 });
    y = doc.y + 18;

    // ── The line ──
    const cols = from.gstin
      ? [['#', 22, 'left'], ['Description', W - 22 - 60 - 36 - 80 - 90, 'left'], ['SAC', 60, 'left'], ['Qty', 36, 'right'], ['Rate', 80, 'right'], ['Taxable value', 90, 'right']]
      : [['#', 22, 'left'], ['Description', W - 22 - 36 - 90 - 90, 'left'], ['Qty', 36, 'right'], ['Rate', 90, 'right'], ['Amount', 90, 'right']];
    doc.rect(M0, y, W, 22).fill(C.fill);
    let x = M0;
    doc.fillColor(C.ink3).fontSize(7.5);
    for (const [h, w, a] of cols) {
      write(doc, h.toUpperCase(), { x: x + 6, y: y + 8, width: w - 12, align: a, characterSpacing: 0.5 });
      x += w;
    }
    y += 30;
    // "Clinic plan · next month" → "MedPin Clinic plan, 1 month".
    const plan = String(inv.description || 'MedPin plan').replace(/\s*·\s*(next month|monthly|1 month)\s*$/i, '').trim();
    const desc = `${/^medpin/i.test(plan) ? plan : `MedPin ${plan}`}, 1 month`;
    const sub = inv.periodStart && inv.periodEnd ? `Subscription, ${fmtDay(inv.periodStart)} to ${fmtDay(T.addDays(inv.periodEnd, -1))}` : 'Subscription';
    const cells = from.gstin
      ? ['1', null, from.sac, '1', money(tax.taxable), money(tax.taxable)]
      : ['1', null, '1', money(inv.amount), money(inv.amount)];
    x = M0;
    let rowEnd = y;
    cols.forEach(([, w, a], i) => {
      doc.fillColor(C.ink).fontSize(9.5);
      if (i === 1) {
        write(doc, desc, { x: x + 6, y, width: w - 12, weight: 'semi' });
        doc.fillColor(C.ink3).fontSize(8.5);
        write(doc, sub, { x: x + 6, width: w - 12 });
        rowEnd = Math.max(rowEnd, doc.y);
      } else {
        write(doc, cells[i], { x: x + 6, y, width: w - 12, align: a });
        rowEnd = Math.max(rowEnd, doc.y);
      }
      x += w;
    });
    y = rowEnd + 10;
    doc.moveTo(M0, y).lineTo(PAGE_W - M0, y).lineWidth(0.6).strokeColor(C.line).stroke();
    y += 10;

    // ── Totals ──
    const tx0 = PAGE_W - M0 - 240;
    const total = (label, value, strong = false) => {
      doc.fillColor(strong ? C.ink : C.ink2).fontSize(strong ? 11 : 9.5);
      write(doc, label, { x: tx0, y, width: 140, weight: strong ? 'bold' : undefined });
      write(doc, value, { x: tx0 + 140, y, width: 100, align: 'right', weight: strong ? 'bold' : 'semi' });
      y += strong ? 20 : 16;
    };
    if (from.gstin) {
      total('Taxable value', money(tax.taxable));
      for (const [l, v] of tax.lines) total(l, money(v));
    }
    if (from.gstin) {
      doc.moveTo(tx0, y).lineTo(PAGE_W - M0, y).lineWidth(0.6).strokeColor(C.line).stroke();
      y += 6;
    }
    total('Total', money(tax.total), true);
    doc.fillColor(C.ink2).fontSize(8.5);
    write(doc, `Amount in words: ${inWords(tax.total)}`, { x: M0, y: y + 2, width: W });
    y = doc.y + 18;

    // ── Payment ──
    doc.roundedRect(M0, y, W, 54, 10).fill(paid ? C.greenSoft : '#FDF3E7');
    doc.fillColor(paid ? C.green : C.amber).fontSize(12);
    write(doc, paid ? 'PAID' : inv.status === 'refunded' ? 'REFUNDED' : 'PAYMENT DUE', { x: M0 + 14, y: y + 10, width: 200, weight: 'bold', characterSpacing: 1 });
    doc.fillColor(C.ink2).fontSize(8.5);
    const payLine = paid
      ? [`Paid on ${fmtDay(inv.paidAt || inv.issuedAt)} online through Razorpay`, inv.razorpayPaymentId ? `Payment ID ${inv.razorpayPaymentId}` : null].filter(Boolean).join(' · ')
      : 'Pay in the MedPin app: Profile › Plan and billing';
    write(doc, payLine, { x: M0 + 14, y: y + 30, width: W - 28 });
    y += 74;

    if (from.gstin && from.includesGst) {
      doc.fillColor(C.ink3).fontSize(8);
      write(doc, 'The plan price includes GST.', { x: M0, y, width: W });
      y = doc.y + 4;
    }
    if (!from.gstin) {
      doc.fillColor(C.ink3).fontSize(8);
      write(doc, 'No GST is charged on this invoice.', { x: M0, y, width: W });
    }

    // ── Footer ──
    doc.fillColor(C.ink3).fontSize(7.5);
    write(doc, 'This is a computer-generated invoice and needs no signature.', { x: M0, y: PAGE_H - M0 - 22, width: W, align: 'center' });
    write(doc, [from.email ? `Questions about this invoice: ${from.email}` : null, from.phone].filter(Boolean).join(' · ') || from.name, { x: M0, y: PAGE_H - M0 - 10, width: W, align: 'center' });
    doc.end();
  });
}

/** The invoice as a file to open, save or share, named by its number. */
async function invoiceFile(invoiceId) {
  const inv = await M.Invoice.findById(invoiceId, 'number issuedAt');
  const pdf = await renderInvoice(invoiceId);
  if (!pdf) return null;
  const storage = require('./storage');
  const name = `MedPin-Invoice-${String(inv.number || T.dayKey(inv.issuedAt)).replace(/[^\w-]+/g, '-')}.pdf`;
  const file = await storage.save(pdf, { folder: 'invoices', name, mimeType: 'application/pdf' });
  return { ...storage.withUrl(file), name };
}

module.exports = { renderInvoice, invoiceFile, inWords, taxOf, supplier, stateOf, STATES, GSTIN };

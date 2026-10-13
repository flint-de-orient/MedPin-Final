// Report PDFs (registers, fees, follow-ups, referrals, history) in the same
// look as the prescription: the clinic's letterhead, the report's title and
// period, a summary strip, then a clean table — hairline row rules (no grid
// boxes), numbers right-aligned, the column header repeated on every page,
// one date style, plain words instead of codes, and "Page x of y" with a
// confidentiality note (the report holds patient information).
const PDFDocument = require('pdfkit');
const { setupFonts, write, heightOf } = require('../lib/pdftext');

const C = {
  primary: '#003399', primarySoft: '#EBF1FB', primaryLine: '#B8C6E3',
  ink: '#111827', ink2: '#3F4757', ink3: '#555E6F', line: '#E3E7EE', fill: '#F1F4F9', zebra: '#F8FAFD',
  green: '#15803D', amber: '#B45309', red: '#B91C1C', white: '#FFFFFF',
};
const PAGE_W = 841.89; // A4 landscape
const PAGE_H = 595.28;
const M = 36;
const W = PAGE_W - 2 * M;
const BOTTOM = PAGE_H - 44;

const TITLES = {
  consultations: 'Consultation register', prescriptions: 'Prescription register', fees: 'Fees and collections',
  follow_ups: 'Follow-up compliance', referrals: 'Referrals', daily: 'Daily appointments', appointments: 'Appointment history',
};

// Codes → words people read.
const WORDS = {
  follow_up: 'Follow-up', new: 'New', report_review: 'Report review', in_clinic: 'In clinic', video: 'Video', phone: 'Phone',
  paid: 'Paid', pending: 'Pending', free: 'Free', waived: 'Waived', refunded: 'Refunded',
  completed: 'Completed', missed: 'Missed', cancelled: 'Cancelled', booked: 'Booked', confirmed: 'Confirmed',
  waiting: 'Waiting', in_consultation: 'In consultation', rescheduled: 'Rescheduled',
  not_booked: 'Not booked', no_reply: 'No reply', reports_in: 'Reports in',
  sent: 'Sent', received: 'Received', awaiting: 'Awaiting', seen: 'Seen', on_time: 'Came back on time', late: 'Came back late',
  upi: 'UPI', cash: 'Cash', card: 'Card', net_banking: 'Net banking', online: 'Online',
};
const TONE = {
  paid: C.green, completed: C.green, seen: C.green, on_time: C.green, late: C.amber, free: C.ink3,
  pending: C.amber, awaiting: C.amber, booked: C.amber, not_booked: C.amber, no_reply: C.amber,
  missed: C.red, cancelled: C.red,
};

const MONEY = /^(fee|amount|billed|collected|pending)$/i;
const NUMBER = /^(age|token|reminders sent|rows|qty)$/i;
const STATUS = /status$/i;

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtDay = (s) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ''));
  return m ? `${Number(m[3])} ${MON[Number(m[2]) - 1]} ${m[1]}` : s;
};
/** Bold for the patient's name and status words. */
const weightOf = (header, code) => (/patient/i.test(header) || (STATUS.test(header) && TONE[code]) ? 'semi' : undefined);
const rupees = (n) => `₹${Number(n || 0).toLocaleString('en-IN')}`;
const isNum = (v) => v !== '' && v != null && Number.isFinite(Number(v));

/** One cell as printed: words for codes, dates as "15 Sep 2026", money as ₹. */
function cellText(header, v) {
  if (v == null || v === '') return MONEY.test(header) ? '—' : '';
  if (MONEY.test(header) && isNum(v)) return Number(v) === 0 ? '₹0' : rupees(v);
  if (/^rx$/i.test(header)) return `RX-${String(v).padStart(4, '0')}`;
  const s = String(v);
  if (WORDS[s]) return WORDS[s];
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return fmtDay(s);
  return s.replace(/; /g, ', ');
}

/** The summary strip: up to four totals that matter for this report. */
function summaryOf(type, header, rows) {
  const col = (re) => header.findIndex((h) => re.test(h));
  const fee = col(/^fee$/i);
  const st = col(/^(fee status|status)$/i);
  // Paid / pending come from the fee's status (the Fees report's "Status" is the fee's).
  const feeSt = header.some((h) => /^fee status$/i.test(h)) ? col(/^fee status$/i) : type === 'fees' ? st : -1;
  const sum = (pred) => rows.reduce((n, r) => n + (pred(r) && isNum(r[fee]) ? Number(r[fee]) : 0), 0);
  const count = (i, v) => rows.filter((r) => r[i] === v).length;
  const out = [];
  const label = { consultations: 'Consultations', prescriptions: 'Prescriptions', fees: 'Visits billed', follow_ups: 'Follow-ups due', referrals: 'Referrals', daily: 'Appointments', appointments: 'Appointments' }[type] || 'Rows';
  out.push([label, rows.length.toLocaleString('en-IN')]);
  if (type === 'prescriptions') {
    const med = col(/^medicines$/i);
    const tst = col(/^tests$/i);
    const n = (i) => rows.reduce((t, r) => t + String(r[i] || '').split(';').filter((x) => x.trim()).length, 0);
    if (med >= 0) out.push(['Medicines', n(med).toLocaleString('en-IN')]);
    if (tst >= 0) out.push(['Lab tests', n(tst).toLocaleString('en-IN')]);
  } else if (type === 'referrals') {
    const dir = col(/^direction$/i);
    out.push(['Sent', count(dir, 'sent')], ['Received', count(dir, 'received')], ['Awaiting', count(st, 'awaiting')]);
  } else if (type === 'follow_ups') {
    out.push(['Came back', count(st, 'on_time') + count(st, 'late') + count(st, 'completed')], ['Booked', count(st, 'booked')], ['Missed', count(st, 'missed')]);
  } else if (fee >= 0 && feeSt >= 0) {
    if (type === 'consultations') {
      const t = col(/^type$/i);
      if (t >= 0) out.push(['New patients', count(t, 'new')]);
    }
    out.push(['Billed', rupees(sum(() => true))]);
    out.push(['Collected', rupees(sum((r) => r[feeSt] === 'paid'))]);
    if (out.length < 4) out.push(['Pending', rupees(sum((r) => r[feeSt] === 'pending'))]);
  } else if (st >= 0) {
    out.push(['Completed', count(st, 'completed')], ['Missed', count(st, 'missed')], ['Cancelled', count(st, 'cancelled')]);
  }
  return out.slice(0, 4).map(([k, v]) => [k, String(v)]);
}

/**
 * Column widths: short columns (dates, mobile, mode, fee, status) fit their
 * longest value on one line; long text (diagnosis, medicines, location)
 * shares what's left and wraps.
 */
function widthsOf(doc, header, rows) {
  const sample = rows.slice(0, 300);
  const pad = 7 * 2 + 4;
  const want = header.map((h, i) => {
    const head = doc.font('semi').fontSize(7.5).widthOfString(h.toUpperCase()) + h.length * 0.5;
    const cells = sample.map((r) => {
      doc.font(weightOf(h, String(r[i] ?? '')) ? 'semi' : 'latin').fontSize(8.5);
      return doc.widthOfString(cellText(h, r[i]));
    });
    return Math.max(head, ...cells, 24) + pad;
  });
  const flex = want.map((w) => w > 150); // long text: may wrap
  const fixed = want.reduce((s, w, i) => s + (flex[i] ? 0 : w), 0);
  const flexWant = want.reduce((s, w, i) => s + (flex[i] ? w : 0), 0);
  const room = W - fixed;
  if (!flexWant || room < 120 * flex.filter(Boolean).length) {
    // Too many columns for one line each: everything shares the page.
    const total = want.reduce((a, b) => a + b, 0);
    return want.map((w) => w * (W / total));
  }
  // Long columns share what's left, in proportion to what they need.
  return want.map((w, i) => (flex[i] ? (w / flexWant) * room : w));
}

/**
 * Draws the report. meta: { type, title?, practiceName, place, period, locations,
 * generatedAt, generatedBy, logo (Buffer) }. sets: { key: { header, rows } }.
 */
function renderReport(sets, meta) {
  return new Promise((resolve, reject) => {
    const doc = setupFonts(new PDFDocument({ size: 'A4', layout: 'landscape', margin: M, bufferPages: true, info: { Title: meta.title, Author: meta.practiceName || 'MedPin', Creator: 'MedPin' } }));
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    // ── Letterhead ──
    const top = () => doc.rect(0, 0, PAGE_W, 4).fill(C.primary);
    top();
    let y = 26;
    const tile = 42;
    let drewLogo = false;
    if (meta.logo) {
      try {
        doc.image(meta.logo, M, y, { fit: [tile, tile], align: 'center', valign: 'center' });
        drewLogo = true;
      } catch {
        drewLogo = false;
      }
    }
    if (!drewLogo) {
      const ini = String(meta.practiceName || 'MedPin').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
      doc.roundedRect(M, y, tile, tile, 10).fill(C.primarySoft);
      doc.fillColor(C.primary).fontSize(15);
      write(doc, ini, { x: M, y: y + 12, width: tile, align: 'center', weight: 'bold' });
    }
    const tx = M + tile + 12;
    doc.fillColor(C.ink).fontSize(15);
    write(doc, meta.practiceName || 'MedPin', { x: tx, y: y + 3, width: 330, weight: 'bold', lineBreak: false, ellipsis: true });
    doc.fillColor(C.ink3).fontSize(8.5);
    write(doc, meta.place || 'Generated with MedPin', { x: tx, y: y + 24, width: 330, lineBreak: false, ellipsis: true });

    doc.fillColor(C.primary).fontSize(17);
    write(doc, meta.title, { x: M + 380, y: y + 1, width: W - 380, align: 'right', weight: 'bold' });
    doc.fillColor(C.ink2).fontSize(9.5);
    write(doc, [meta.period, meta.locations].filter(Boolean).join('  ·  '), { x: M + 380, y: y + 24, width: W - 380, align: 'right' });
    y += tile + 14;
    doc.moveTo(M, y).lineTo(M + W, y).lineWidth(1).strokeColor(C.primary).stroke();
    y += 12;

    const [first] = Object.values(sets);
    const header = first?.header || [];
    const rows = first?.rows || [];

    // ── Summary strip ──
    const tiles = summaryOf(meta.type, header, rows);
    const gap = 10;
    const tw = (W - gap * (tiles.length - 1)) / Math.max(tiles.length, 1);
    tiles.forEach(([k, v], i) => {
      const x = M + i * (tw + gap);
      doc.roundedRect(x, y, tw, 48, 10).fill(C.fill);
      doc.fillColor(C.ink3).fontSize(7.5);
      write(doc, k.toUpperCase(), { x: x + 14, y: y + 10, width: tw - 28, weight: 'semi', characterSpacing: 0.6, lineBreak: false });
      doc.fillColor(C.ink).fontSize(16);
      write(doc, v, { x: x + 14, y: y + 22, width: tw - 28, weight: 'bold', lineBreak: false });
    });
    y += 48 + 18;

    // ── Table ──
    const widths = widthsOf(doc, header, rows);
    const right = header.map((h) => MONEY.test(h) || NUMBER.test(h));
    const pad = 7;
    const drawHead = () => {
      doc.roundedRect(M, y, W, 22, 6).fill(C.primarySoft);
      let x = M;
      doc.fillColor(C.primary).fontSize(7.5);
      header.forEach((h, i) => {
        write(doc, h.toUpperCase(), { x: x + pad, y: y + 7.5, width: widths[i] - pad * 2, align: right[i] ? 'right' : 'left', weight: 'semi', characterSpacing: 0.5, lineBreak: false, ellipsis: true });
        x += widths[i];
      });
      y += 22;
    };
    const newPage = () => {
      doc.addPage();
      top();
      y = 26;
      doc.fillColor(C.ink3).fontSize(8.5);
      write(doc, `${meta.title} · ${meta.period} (continued)`, { x: M, y, width: W, weight: 'semi' });
      y += 18;
      drawHead();
    };
    if (!rows.length) {
      doc.roundedRect(M, y, W, 60, 10).fill(C.zebra);
      doc.fillColor(C.ink3).fontSize(10);
      write(doc, 'Nothing in this period.', { x: M, y: y + 24, width: W, align: 'center' });
      y += 60;
    } else {
      drawHead();
      rows.forEach((r, ri) => {
        const texts = header.map((h, i) => cellText(h, r[i]));
        doc.fontSize(8.5);
        const h = Math.max(20, ...texts.map((t, i) => heightOf(doc, t, { width: widths[i] - pad * 2, weight: weightOf(header[i], String(r[i] ?? '')) }) + 10));
        if (y + h > BOTTOM) newPage();
        if (ri % 2 === 1) doc.rect(M, y, W, h).fill(C.zebra);
        let x = M;
        texts.forEach((t, i) => {
          const hd = header[i];
          const code = String(r[i] ?? '');
          const tone = STATUS.test(hd) ? TONE[code] : null;
          doc.fillColor(tone || (i === 0 || /patient/i.test(hd) ? C.ink : C.ink2)).fontSize(8.5);
          write(doc, t, { x: x + pad, y: y + 5, width: widths[i] - pad * 2, align: right[i] ? 'right' : 'left', weight: weightOf(hd, code) });
          x += widths[i];
        });
        y += h;
        doc.moveTo(M, y).lineTo(M + W, y).lineWidth(0.5).strokeColor(C.line).stroke();
      });
    }

    // ── Footer on every page ──
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(range.start + i);
      doc.page.margins.bottom = 0; // the footer sits below the content area
      const fy = PAGE_H - 30;
      doc.moveTo(M, fy - 8).lineTo(M + W, fy - 8).lineWidth(0.5).strokeColor(C.line).stroke();
      doc.fillColor(C.ink3).fontSize(7.5);
      write(doc, `Confidential: contains patient health information. Generated ${meta.generatedAt}${meta.generatedBy ? ` by ${meta.generatedBy}` : ''} · MedPin`, { x: M, y: fy, width: W - 90, lineBreak: false, ellipsis: true });
      write(doc, `Page ${i + 1} of ${range.count}`, { x: M + W - 90, y: fy, width: 90, align: 'right', weight: 'semi', lineBreak: false });
    }
    doc.end();
  });
}

module.exports = { renderReport, cellText, summaryOf, fmtDay, TITLES };

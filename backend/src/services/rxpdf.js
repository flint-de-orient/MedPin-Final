// Prescription PDF (A4) in MedPin's look: a blue letterhead band, a meta
// strip, the patient card, clinical notes, a medicines table, advice,
// follow-up, the doctor's signature and a QR code anyone can scan to check
// the prescription is real.
//
// Content follows the IMC Regulations 2002 (registration number on the
// prescription, generic names in capitals), the Telemedicine Practice
// Guidelines 2020 sample format (doctor, patient, complaint, findings,
// diagnosis, investigations, Rx with strength / form / dose / frequency /
// duration, instructions, signature) and the Drugs Rules (date, total
// quantity, doctor and patient details).
const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');
const env = require('../config/env');
const T = require('../lib/time');
const { hmac } = require('../lib/security');
const { setupFonts, write, heightOf, runs } = require('../lib/pdftext');
const { translator } = require('./rxlang');

/** Bump when the layout changes; older PDFs are drawn again when opened. */
const PDF_VERSION = 5; // 3: print-friendly letterhead; 4: no box outlines; 5: Bengali / Hindi

// App tokens (lib/core/tokens.dart).
const C = {
  primary: '#003399', primaryDark: '#002470', primarySoft: '#EBF1FB', primaryLine: '#B8C6E3', primaryMid: '#7F99CC',
  ink: '#111827', ink2: '#3F4757', ink3: '#555E6F', line: '#C9D0DB', lineStrong: '#AEB7C4',
  fill: '#F1F4F9', bg: '#F7F9FC', amber: '#B45309', amberSoft: '#FEF6E7', red: '#B91C1C', redSoft: '#FDECEC', redLine: '#F3C4C4',
  green: '#15803D', white: '#FFFFFF',
};
const PAGE_W = 595.28;
const PAGE_H = 841.89;
const M = 40;
const W = PAGE_W - 2 * M;
const BOTTOM = PAGE_H - 58; // content stops above the footer

const FOOD = { before_food: 'Before food', after_food: 'After food', with_food: 'With food', empty_stomach: 'Empty stomach', bedtime: 'At bedtime' };
const DAYS = { mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat', sun: 'Sun' };
const CHANGE = { new: ['NEW', C.primary, C.primarySoft], continued: ['CONTINUED', C.ink2, C.fill], changed: ['DOSE CHANGED', C.amber, C.amberSoft], stopped: ['STOPPED', C.red, C.redSoft] };

const fmtDate = (d, weekday = false) => (d
  ? new Date(d).toLocaleDateString('en-GB', { ...(weekday ? { weekday: 'short' } : {}), day: '2-digit', month: 'short', year: 'numeric', timeZone: 'Asia/Kolkata' }).replace(',', '').replace('Sept', 'Sep')
  : '');
const rxNo = (rx) => `RX-${String(rx.rxNumber || 0).padStart(4, '0')}`;
const initials = (s) => String(s || 'M').replace(/^Dr\.?\s+/i, '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');

/** Token printed in the QR link so only real prescriptions verify. */
const verifyToken = (id) => hmac(`rx-verify:${id}`).slice(0, 20);
const verifyUrl = (id) => `${env.publicUrl}/rx/${id}/verify?t=${verifyToken(id)}`;

/** "Mon–Sat · 9:00 AM – 8:00 PM" when the open days share hours. */
function hoursLine(location) {
  const open = (location?.weeklyHours || []).filter((h) => h.isOpen && h.opensAt != null && h.closesAt != null);
  if (!open.length) return null;
  const same = open.every((h) => h.opensAt === open[0].opensAt && h.closesAt === open[0].closesAt);
  if (!same) return null;
  const order = Object.keys(DAYS);
  const days = open.map((h) => order.indexOf(h.weekday)).sort((a, b) => a - b);
  const run = days.every((d, i) => i === 0 || d === days[i - 1] + 1);
  const label = run && days.length > 2 ? `${DAYS[order[days[0]]]}–${DAYS[order[days.at(-1)]]}` : days.map((d) => DAYS[order[d]]).join(', ');
  return `${label} · ${T.fmtTime(open[0].opensAt)} – ${T.fmtTime(open[0].closesAt)}`;
}

function qualificationsOf(doctor, lh) {
  const q = (doctor?.qualifications || []).map((x) => x.name).filter(Boolean);
  return q.length ? q.join(', ') : doctor?.degreesSummary || lh?.tagline || '';
}

function registrationOf(doctor, lh) {
  const r = doctor?.registration || {};
  if (r.number) return `Reg. No. ${r.number}${r.council || r.councilShort ? ` · ${r.council || r.councilShort}` : ''}`;
  return lh?.registrationNo ? `Reg. No. ${lh.registrationNo}` : '';
}

function doseCell(item, t = (s) => s) {
  if (item.frequency === 'weekly') return [t('1 / week'), item.weekday ? t(DAYS[item.weekday] || item.weekday) : t('Once a week')];
  if (item.frequency === 'sos' || item.frequency === 'as_needed') return [t('When needed'), ''];
  const d = item.dose || {};
  return [`${d.morning || 0} – ${d.afternoon || 0} – ${d.night || 0}`, t('Morn – Aft – Night')];
}

function durationCell(item, t = (s) => s) {
  const d = item.duration || {};
  if (d.unit === 'ongoing') return t('Ongoing');
  if (!d.value) return '—';
  const unit = d.value === 1 ? String(d.unit || 'days').replace(/s$/, '') : d.unit || 'days';
  return `${d.value} ${t(unit)}`;
}

/**
 * Draws the prescription. Input: { rx, patient, doctor, location, vitals,
 * complaint, signature, logo, practiceName, mode }. Resolves to
 * { buffer, pages }.
 */
async function renderPrescription({ rx, patient, doctor, location, vitals, complaint, signature, logo, practiceName, mode, lang = 'en', tr = null }) {
  // lang: the patient's copy in Bengali / Hindi (labels + the doctor's words in [tr]);
  // medicine names, strengths, tests and the diagnosis stay in English.
  const t = translator(lang);
  const local = lang !== 'en';
  const qr = rx._id ? await QRCode.toBuffer(verifyUrl(rx._id), { margin: 0, width: 192, color: { dark: C.primaryDark, light: '#FFFFFF' } }).catch(() => null) : null;
  return new Promise((resolve, reject) => {
    const doc = setupFonts(new PDFDocument({ size: 'A4', margin: 0, bufferPages: true, info: { Title: `Prescription ${rxNo(rx)}`, Author: rx.doctorName || 'MedPin', Creator: 'MedPin' } }));
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve({ buffer: Buffer.concat(chunks), pages: pageCount }));
    doc.on('error', reject);
    let pageCount = 1;

    const lh = location?.letterhead || {};
    const doctorName = lh.doctorNamePrinted || rx.doctorName || 'Doctor';
    const quals = qualificationsOf(doctor, lh);
    const reg = registrationOf(doctor, lh);
    const clinic = location?.name || practiceName || '';
    const video = mode === 'video';

    const img = (buf, x, y, opts) => {
      if (!buf) return false;
      try {
        doc.image(buf, x, y, opts);
        return true;
      } catch {
        return false; // unsupported image: the PDF is still produced
      }
    };
    const text = (str, x, y, { size = 10, color = C.ink, weight, width, align, lineGap = 1.5, spacing } = {}) => {
      doc.fontSize(size).fillColor(color);
      write(doc, str, { x, y, width, align, lineGap, weight, characterSpacing: spacing });
      return doc.y;
    };
    // Capitals and letter-spacing are for Latin; Bengali / Hindi shapes need neither.
    const label = (str, x, y, color = C.primary) => (local ? text(str, x, y, { size: 8, weight: 'bold', color }) : text(str.toUpperCase(), x, y, { size: 7.5, weight: 'bold', color, spacing: 0.8 }));
    /** Width of mixed-script text (each run in its own font). */
    const widthOf = (str, size, weight) => {
      doc.fontSize(size);
      const w = runs(str).reduce((s, r) => s + doc.font(r.font === 'latin' ? (weight === 'bold' ? 'bold' : weight === 'semi' ? 'semi' : 'latin') : r.font).widthOfString(r.text), 0);
      doc.font('latin');
      return w;
    };

    // ── Letterhead band ──
    const rightW = 210;
    const leftW = W - rightW - 72;
    doc.fontSize(20);
    const nameH = heightOf(doc, doctorName, { width: leftW, weight: 'bold' });
    doc.fontSize(9.5);
    const qualH = quals ? heightOf(doc, quals, { width: leftW }) : 0;
    const addr = [location?.address, [location?.area, location?.city].filter(Boolean).join(', '), location?.pincode].filter(Boolean).join(', ');
    const contact = [location?.phone || location?.patientPhone ? `Ph. ${location.phone || location.patientPhone}` : null, hoursLine(location)].filter(Boolean);
    doc.fontSize(8.5);
    const addrH = addr ? heightOf(doc, addr, { width: rightW }) : 0;
    const leftH = nameH + 4 + qualH + (doctor?.headline ? 14 : 0) + (reg ? 14 : 0);
    const rightH = 14 + addrH + contact.length * 12;
    const bandH = Math.max(96, 24 + Math.max(leftH, rightH, 56) + 18);

    // White letterhead: a blue bar on top and a blue rule under it. Clean in
    // colour and on a black & white printer or photocopier (no solid fills).
    doc.rect(0, 0, PAGE_W, 6).fill(C.primary);
    doc.rect(M, bandH - 2, W, 1.5).fill(C.primary);
    // Logo: on white, in its own colours; initials when there is none.
    const tile = 56;
    const tx0 = M;
    if (!img(logo, tx0, 24, { fit: [tile, tile], align: 'center', valign: 'center' })) {
      doc.roundedRect(tx0, 24, tile, tile, 12).fill(C.primarySoft);
      text(initials(clinic || doctorName), tx0, 24 + tile / 2 - 11, { size: 20, weight: 'bold', color: C.primary, width: tile, align: 'center' });
    }
    let y = 22;
    const lx = M + tile + 16;
    y = text(doctorName, lx, y, { size: 20, weight: 'bold', color: C.primaryDark, width: leftW }) + 2;
    if (quals) y = text(quals, lx, y, { size: 9.5, color: C.ink2, width: leftW }) + 1;
    if (doctor?.headline) y = text(doctor.headline, lx, y, { size: 9, color: C.ink2, width: leftW }) + 1;
    if (reg) text(reg, lx, y + 2, { size: 9, weight: 'semi', color: C.ink, width: leftW });
    const rx0 = M + W - rightW;
    let ry = 24;
    if (clinic) ry = text(clinic, rx0, ry, { size: 10.5, weight: 'bold', color: C.primaryDark, width: rightW, align: 'right' }) + 2;
    if (addr) ry = text(addr, rx0, ry, { size: 8.5, color: C.ink2, width: rightW, align: 'right' }) + 2;
    for (const c of contact) ry = text(c, rx0, ry, { size: 8.5, color: C.ink2, width: rightW, align: 'right' }) + 1;

    // ── Meta strip ──
    y = bandH + 14;
    const metaH = 40;
    doc.roundedRect(M, y, W, metaH, 10).fill(C.primarySoft);
    const cells = [
      ['Prescription no.', rxNo(rx)],
      ['Date', fmtDate(rx.issuedAt)],
      ['Visit', video ? t('Video consult') : t('In clinic')],
      ['Next visit', rx.followUpDate ? fmtDate(rx.followUpDate) : '—'],
      ['Valid till', rx.validUntil ? fmtDate(rx.validUntil) : '—'],
    ];
    const cw = W / cells.length;
    cells.forEach(([k, v], i) => {
      const cx = M + i * cw + 12;
      if (i) doc.moveTo(M + i * cw, y + 10).lineTo(M + i * cw, y + metaH - 10).lineWidth(1).strokeColor(C.primaryLine).stroke();
      label(t(k), cx, y + 8, k === 'Next visit' && rx.followUpDate ? C.primary : C.ink3);
      text(v, cx, y + 19, { size: 10.5, weight: k === 'Next visit' && rx.followUpDate ? 'bold' : 'semi', color: k === 'Next visit' && rx.followUpDate ? C.primaryDark : C.ink, width: cw - 18 });
    });
    y += metaH + 10;

    // ── Patient card ──
    const age = T.ageFrom(patient);
    const sex = patient.gender ? t(patient.gender[0].toUpperCase() + patient.gender.slice(1)) : null;
    const weight = vitals?.weightKg || patient.weightKg;
    const facts = [age != null ? `${age} ${t('yrs')}` : null, sex, weight ? `${weight} kg` : null, patient.bloodGroup ? `${t('Blood')} ${patient.bloodGroup}` : null, patient.phone ? `+91 ${patient.phone}` : null].filter(Boolean).join('   ·   ');
    const home = (patient.addresses || []).find((a) => a.isDefault) || (patient.addresses || [])[0];
    const homeLine = home ? [home.line, home.area, home.city, home.pincode].filter(Boolean).join(', ') : patient.area || '';
    const allergies = (patient.allergies || []).map((a) => a.allergen || a.name).filter(Boolean);
    label(t('Patient'), M, y + 2, C.ink3);
    let py = text(patient.name, M, y + 13, { size: 13, weight: 'bold', width: W }) + 1;
    py = text(facts, M, py, { size: 9.5, color: C.ink2, width: W }) + 2;
    if (homeLine) py = text(homeLine, M, py, { size: 9, color: C.ink3, width: W }) + 2;
    if (allergies.length) {
      const pill = `${t('Allergies')}: ${allergies.join(', ')}`;
      const pw = Math.min(W, widthOf(pill, 8.5, 'semi') + 22);
      doc.roundedRect(M, py + 3, pw, 18, 9).fill(C.redSoft);
      text(pill, M + 11, py + 7.5, { size: 8.5, weight: 'semi', color: C.red, width: pw - 18 });
      py += 22;
    }
    const cardH = py - y + 10;
    y += cardH + 12;

    // ── Clinical notes ──
    const vitalsParts = vitals ? [
      vitals.bpSystolic && `BP ${vitals.bpSystolic}/${vitals.bpDiastolic} mmHg`,
      vitals.pulse && `Pulse ${vitals.pulse} /min`,
      vitals.spo2 && `SpO2 ${vitals.spo2}%`,
      vitals.temperatureF && `Temp ${vitals.temperatureF} °F`,
      vitals.bloodSugar && `Sugar ${vitals.bloodSugar} mg/dL`,
    ].filter(Boolean) : [];
    if (tr?.complaint != null) complaint = tr.complaint || complaint;
    if (complaint || rx.diagnosisSummary) {
      const colW = (W - 24) / 2;
      let ly = y;
      let ry2 = y;
      if (complaint) {
        label(t('Chief complaint'), M, ly);
        ly = text(complaint, M, ly + 12, { size: 10, width: colW }) + 8;
      }
      if (rx.diagnosisSummary) {
        const dx = complaint ? M + colW + 24 : M;
        label(t('Diagnosis'), dx, ry2);
        ry2 = text(rx.diagnosisSummary, dx, ry2 + 12, { size: 11, weight: 'semi', width: complaint ? colW : W }) + 8;
      }
      y = Math.max(ly, ry2) + 2;
    }
    if (vitalsParts.length) {
      label(t('Vitals'), M, y);
      let vx = M + 44;
      let vy = y - 5;
      doc.fontSize(8.5);
      for (const v of vitalsParts) {
        const vw = doc.font('semi').widthOfString(v) + 16;
        if (vx + vw > M + W) { vx = M + 44; vy += 22; }
        doc.roundedRect(vx, vy, vw, 18, 9).fill(C.fill);
        text(v, vx + 8, vy + 4.5, { size: 8.5, weight: 'semi', color: C.ink, width: vw });
        vx += vw + 6;
      }
      y = vy + 26;
    } else {
      y += 6;
    }

    // ── New page with a compact header ──
    const newPage = () => {
      doc.addPage({ size: 'A4', margin: 0 });
      pageCount += 1;
      doc.rect(0, 0, PAGE_W, 6).fill(C.primary);
      text(doctorName, M, 16, { size: 10.5, weight: 'bold', color: C.primaryDark, width: W / 2 });
      text(`${patient.name}  ·  ${rxNo(rx)}  ·  ${fmtDate(rx.issuedAt)}`, M + W / 2, 17, { size: 9, color: C.ink2, width: W / 2, align: 'right' });
      doc.rect(M, 36, W, 1).fill(C.primary);
      return 56;
    };
    const ensure = (h) => {
      if (y + h > BOTTOM) y = newPage();
    };

    // ── Medicines ──
    const cols = [
      { k: '#', w: 20 },
      { k: 'Medicine', w: 172 },
      { k: 'Dose', w: 78 },
      { k: 'When', w: 72 },
      { k: 'Duration', w: 60 },
      { k: 'Qty', w: 36 },
      { k: 'Instructions', w: W - 438 },
    ];
    const tableHead = () => {
      doc.roundedRect(M, y, W, 22, 6).fill(C.fill);
      let x = M;
      for (const c of cols) {
        label(t(c.k), x + 6, y + 8, C.ink2);
        x += c.w;
      }
      y += 26;
    };
    ensure(90);
    doc.fontSize(26).fillColor(C.primary).font('noto').text('℞', M - 1, y - 6, { lineBreak: false });
    doc.font('latin');
    text(`${t('Medicines')} · ${rx.items.length}`, M + 26, y + 6, { size: 11, weight: 'bold', color: C.ink });
    text(local ? t('Medicine names in English for the chemist') : 'Generic names in capitals', M + W - 230, y + 8, { size: 8, color: C.ink3, width: 230, align: 'right' });
    y += 25;
    tableHead();
    if (!rx.items.length) {
      text(t('No medicines prescribed.'), M + 6, y + 4, { size: 10, color: C.ink3 });
      y += 26;
    }
    rx.items.forEach((item, i) => {
      const stopped = item.change === 'stopped';
      const name = `${String(item.name || '').toUpperCase()}${item.strength ? ` ${item.strength}` : ''}`;
      const sub = [item.form ? item.form[0].toUpperCase() + item.form.slice(1) : null].filter(Boolean).join(' · ');
      const [dose, doseSub] = doseCell(item, t);
      const when = item.foodRelation ? t(FOOD[item.foodRelation] || item.foodRelation) : '—';
      const notes = [tr?.instructions?.[i] || item.instructions].filter(Boolean).join('\n');
      const caution = tr?.cautions?.[i] || item.caution;
      doc.fontSize(10);
      const nameH = heightOf(doc, name, { width: cols[1].w - 12, weight: 'bold' });
      doc.fontSize(8.5);
      const notesH = (notes ? heightOf(doc, notes, { width: cols[6].w - 10 }) : 0) + (caution ? heightOf(doc, caution, { width: cols[6].w - 10 }) + 3 : 0);
      const rowH = Math.max(32, nameH + 24, notesH + 14);
      if (y + rowH > BOTTOM) {
        y = newPage();
        tableHead();
      }
      let x = M;
      text(String(i + 1), x + 6, y + 6, { size: 9.5, weight: 'semi', color: C.ink3 });
      x += cols[0].w;
      const ny = text(name, x + 6, y + 6, { size: 10, weight: 'bold', color: stopped ? C.ink3 : C.ink, width: cols[1].w - 12 });
      if (stopped) {
        doc.moveTo(x + 6, y + 12).lineTo(x + 6 + Math.min(cols[1].w - 12, doc.font('bold').fontSize(10).widthOfString(name)), y + 12).lineWidth(0.8).strokeColor(C.ink3).stroke();
        doc.font('latin');
      }
      const [badgeEn, bc, bf] = CHANGE[item.change] || CHANGE.new;
      const badge = t(badgeEn);
      const bw = widthOf(badge, local ? 7 : 6.5, 'bold') + 10;
      doc.roundedRect(x + 6, ny + 2, bw, 12, 6).fill(bf);
      text(badge, x + 11, ny + (local ? 3.4 : 4.6), { size: local ? 7 : 6.5, weight: 'bold', color: bc, spacing: local ? 0 : 0.4 });
      if (sub) text(sub, x + bw + 12, ny + 3, { size: 8.5, color: C.ink3, width: cols[1].w - bw - 18 });
      x += cols[1].w;
      text(dose, x + 6, y + 6, { size: 10, weight: 'semi', width: cols[2].w - 8 });
      if (doseSub) text(doseSub, x + 6, y + 19, { size: 7, color: C.ink3, width: cols[2].w - 8 });
      x += cols[2].w;
      text(when, x + 6, y + 6, { size: 9, color: C.ink2, width: cols[3].w - 8 });
      x += cols[3].w;
      text(durationCell(item, t), x + 6, y + 6, { size: 9, color: C.ink2, width: cols[4].w - 8 });
      x += cols[4].w;
      text(item.quantity ? String(item.quantity) : '—', x + 6, y + 6, { size: 9.5, weight: 'semi', width: cols[5].w - 8 });
      x += cols[5].w;
      let iy = y + 6;
      if (notes) iy = text(notes, x + 6, iy, { size: 8.5, color: C.ink2, width: cols[6].w - 10 }) + 3;
      if (caution) text(caution, x + 6, iy, { size: 8, weight: 'semi', color: C.amber, width: cols[6].w - 10 });
      y += rowH;
      doc.moveTo(M, y).lineTo(M + W, y).lineWidth(0.5).strokeColor('#E2E6EC').stroke();
    });
    y += 12;

    // ── Investigations ──
    if (rx.tests?.length) {
      ensure(48);
      label(t('Investigations advised'), M, y);
      let tx = M;
      let ty = y + 13;
      doc.fontSize(9);
      for (const t of rx.tests) {
        const w = doc.font('semi').widthOfString(t) + 18;
        if (tx + w > M + W) { tx = M; ty += 24; ensure(24); }
        doc.roundedRect(tx, ty, w, 19, 9.5).fill(C.primarySoft);
        text(t, tx + 9, ty + 5, { size: 9, weight: 'semi', color: C.primary });
        tx += w + 6;
      }
      y = ty + 28;
    }

    // ── Advice ──
    const advice = String((tr?.advice ?? rx.advice) || '').split('\n').map((s) => s.trim()).filter(Boolean);
    if (advice.length) {
      ensure(40);
      label(t('Advice'), M, y);
      y += 14;
      for (const a of advice) {
        doc.fontSize(10);
        const h = heightOf(doc, a, { width: W - 16 });
        ensure(h + 4);
        doc.circle(M + 3, y + 6, 2).fill(C.primary);
        text(a, M + 14, y, { size: 10, color: C.ink, width: W - 16 });
        y += h + 4;
      }
      y += 6;
    }

    // ── Signature and QR ──
    ensure(96);
    const sy = y;
    if (qr) {
      img(qr, M + 9, sy + 17, { fit: [56, 56] });
      text(t('Scan to verify'), M + 86, sy + 30, { size: 9.5, weight: 'semi', color: C.ink, width: 160 });
      text(t('Checks this prescription with MedPin.'), M + 86, sy + 44, { size: 8, color: C.ink3, width: 160 });
    }
    const sw = 210;
    const sx = M + W - sw;
    const signed = img(signature, sx + (sw - 150) / 2, sy, { fit: [150, 46], align: 'center', valign: 'bottom' });
    if (!signed) {
      doc.roundedRect(sx + 20, sy + 4, sw - 40, 40, 8).fill(C.fill);
      text(t('Signature on file · scan to verify'), sx + 20, sy + 19, { size: 8, color: C.ink3, width: sw - 40, align: 'center' });
    }
    doc.moveTo(sx, sy + 50).lineTo(sx + sw, sy + 50).lineWidth(1).strokeColor(C.lineStrong).stroke();
    let gy = text(doctorName, sx, sy + 55, { size: 10.5, weight: 'bold', width: sw, align: 'center' });
    if (quals) gy = text(quals, sx, gy, { size: 8.5, color: C.ink2, width: sw, align: 'center' });
    if (reg) text(reg, sx, gy, { size: 8.5, color: C.ink2, width: sw, align: 'center' });

    // ── Footer on every page ──
    const ids = [doctor?.hprId && `HPR ID ${doctor.hprId}`, location?.hfrId && `HFR ID ${location.hfrId}`].filter(Boolean).join(' · ');
    const foot = `${signed ? `${t('Digitally signed by')} ${doctorName}` : t('Issued by the doctor')} · ${t('Generated by MedPin')}${ids ? ` · ${ids}` : ''}`;
    const range = doc.bufferedPageRange();
    for (let p = range.start; p < range.start + range.count; p++) {
      doc.switchToPage(p);
      const fy = PAGE_H - 44;
      if (video) text(t('Issued after a video consultation, as per the Telemedicine Practice Guidelines 2020.'), M, fy - 14, { size: 7.5, color: C.ink3, width: W });
      doc.moveTo(M, fy).lineTo(M + W, fy).lineWidth(0.8).strokeColor(C.line).stroke();
      text(foot, M, fy + 8, { size: 7.5, color: C.ink3, width: W - 80 });
      text(`${t('Page')} ${p - range.start + 1} ${t('of')} ${range.count}`, M + W - 80, fy + 8, { size: 7.5, weight: 'semi', color: C.ink3, width: 80, align: 'right' });
    }
    doc.flushPages();
    doc.end();
  });
}

module.exports = { renderPrescription, verifyToken, verifyUrl, PDF_VERSION, fmtDate, rxNo };

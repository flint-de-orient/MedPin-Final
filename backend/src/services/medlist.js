// Patient-Medicines "Share medicine list": the patient's current medicines as
// a clean A4 schedule for a new doctor, a pharmacist, a family member or an
// emergency. Laid out like a pharmacist's medication card (and the Universal
// Medication Schedule): who it's for, allergies first, then each medicine with
// strength, what it's for, how many to take morning / afternoon / night, food
// timing, since when and who prescribed it; weekly / when-needed medicines
// apart; when it was made and a reminder to check before changing anything.
// Same look as the prescription (services/rxpdf.js).
const path = require('path');
const PDFDocument = require('pdfkit');
const { setupFonts, write, heightOf } = require('../lib/pdftext');
const T = require('../lib/time');
const M = require('../models');

const C = {
  primary: '#003399', primaryDark: '#002470', primarySoft: '#EBF1FB', primaryLine: '#B8C6E3',
  ink: '#111827', ink2: '#3F4757', ink3: '#555E6F', line: '#E2E6EC', lineStrong: '#AEB7C4',
  fill: '#F1F4F9', red: '#B91C1C', redSoft: '#FDECEC', green: '#15803D', greenSoft: '#E8F5EC', white: '#FFFFFF',
};
const PAGE_W = 595.28;
const PAGE_H = 841.89;
const M0 = 40;
const W = PAGE_W - 2 * M0;
const BOTTOM = PAGE_H - 60;
const LOGO = path.join(__dirname, '..', '..', 'assets', 'images', 'medpin_logo.png');

const MEAL = { morning: 'breakfast', afternoon: 'lunch', night: 'dinner' };
const DAYS = { mon: 'Monday', tue: 'Tuesday', wed: 'Wednesday', thu: 'Thursday', fri: 'Friday', sat: 'Saturday', sun: 'Sunday' };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtDay = (d) => {
  if (!d) return '';
  const [y, m, dd] = T.dayKey(d).split('-');
  return `${Number(dd)} ${MON[Number(m) - 1]} ${y}`;
};
const clock = (hhmm) => (hhmm ? T.fmtTime(T.hhmmToMin(hhmm)) : '');

/** "with breakfast", "after dinner", "on an empty stomach", "at bedtime" — for the slots it's taken in. */
function howTaken(c) {
  const slots = ['morning', 'afternoon', 'night'].filter((s) => (c.dose?.[s] || 0) > 0);
  const meals = slots.map((s) => MEAL[s]).join(' & ') || 'food';
  return {
    before_food: `before ${meals}`, after_food: `after ${meals}`, with_food: `with ${meals}`,
    empty_stomach: 'on an empty stomach', bedtime: 'at bedtime',
  }[c.foodRelation] || '';
}

const qty = (n) => (!n ? '' : n === 0.5 ? '½' : Number.isInteger(n) ? String(n) : String(n));

async function renderMedicineList({ patient, courses }) {
  // What each medicine is for: the diagnosis on the prescription it came from.
  const rxs = await M.Prescription.find({ _id: { $in: courses.map((c) => c.prescriptionId).filter(Boolean) } }, 'diagnosisSummary').lean();
  const forOf = new Map(rxs.map((r) => [String(r._id), (r.diagnosisSummary || '').split(',')[0].trim()]));
  const daily = courses.filter((c) => c.frequency !== 'weekly' && c.frequency !== 'as_needed');
  const other = courses.filter((c) => c.frequency === 'weekly' || c.frequency === 'as_needed');

  return new Promise((resolve, reject) => {
    const doc = setupFonts(new PDFDocument({ size: 'A4', margin: 0, bufferPages: true, info: { Title: `Medicine list · ${patient.name}`, Author: 'MedPin', Creator: 'MedPin' } }));
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const text = (s, x, y, { size = 10, color = C.ink, weight, width, align, lineGap = 1.5 } = {}) => {
      doc.fontSize(size).fillColor(color);
      write(doc, s, { x, y, width, align, lineGap, weight });
      return doc.y;
    };
    const label = (s, x, y, color = C.ink3, width) => text(String(s).toUpperCase(), x, y, { size: 7.5, weight: 'bold', color, width });

    // ── Header ──
    const top = () => doc.rect(0, 0, PAGE_W, 6).fill(C.primary);
    top();
    try {
      doc.image(LOGO, M0, 24, { fit: [120, 40], valign: 'center' });
    } catch {
      text('MedPin', M0, 32, { size: 18, weight: 'bold', color: C.primary });
    }
    text('My medicine list', M0 + 200, 26, { size: 20, weight: 'bold', color: C.primaryDark, width: W - 200, align: 'right' });
    text(`Updated ${fmtDay(new Date())} · ${courses.length} ${courses.length === 1 ? 'medicine' : 'medicines'}`, M0 + 200, 52, { size: 9.5, color: C.ink2, width: W - 200, align: 'right' });
    doc.rect(M0, 76, W, 1.5).fill(C.primary);
    let y = 90;

    // ── Patient card ──
    const age = T.ageFrom(patient);
    const sex = patient.gender ? patient.gender[0].toUpperCase() + patient.gender.slice(1) : null;
    const facts = [age != null ? `${age} yrs` : null, sex, patient.weightKg ? `${patient.weightKg} kg` : null, patient.bloodGroup ? `Blood ${patient.bloodGroup}` : null, patient.phone ? `+91 ${patient.phone}` : null].filter(Boolean).join('   ·   ');
    const ec = patient.emergencyContact?.name ? `${patient.emergencyContact.name}${patient.emergencyContact.phone ? ` · +91 ${patient.emergencyContact.phone}` : ''}` : null;
    const conditions = (patient.conditions || []).map((c) => c.name).filter(Boolean);
    const allergies = (patient.allergies || []).map((a) => a.allergen).filter(Boolean);
    doc.fontSize(9.5);
    const condH = conditions.length ? heightOf(doc, conditions.join(', '), { width: W - 150 }) : 0;
    const cardH = 52 + (ec ? 14 : 0) + (conditions.length ? condH + 16 : 0);
    doc.roundedRect(M0, y, W, cardH, 12).fill(C.fill);
    label('Patient', M0 + 14, y + 12);
    text(patient.name, M0 + 14, y + 23, { size: 14, weight: 'bold', width: W - 28 });
    let py = text(facts, M0 + 14, y + 41, { size: 9.5, color: C.ink2, width: W - 28 });
    if (ec) py = text(`Emergency contact: ${ec}`, M0 + 14, py + 2, { size: 9.5, color: C.ink2, width: W - 28 });
    if (conditions.length) {
      label('Conditions', M0 + 14, py + 7);
      text(conditions.join(', '), M0 + 100, py + 5, { size: 9.5, color: C.ink, width: W - 120 });
    }
    y += cardH + 10;

    // Allergies: always stated, red when there are any.
    const allergyText = allergies.length ? `Allergies: ${allergies.join(', ')}` : 'No known allergies recorded';
    doc.fontSize(9.5);
    const aw = Math.min(W, doc.font('semi').widthOfString(allergyText) + 26);
    doc.font('latin');
    doc.roundedRect(M0, y, aw, 22, 11).fill(allergies.length ? C.redSoft : C.greenSoft);
    text(allergyText, M0 + 13, y + 6, { size: 9.5, weight: 'semi', color: allergies.length ? C.red : C.green, width: aw - 20 });
    y += 36;

    // ── Daily schedule ──
    const cols = [
      { k: 'Medicine', w: 170 },
      { k: 'Morning', w: 52, c: true },
      { k: 'Afternoon', w: 62, c: true },
      { k: 'Night', w: 44, c: true },
      { k: 'How to take', w: 90 },
      { k: 'Dates', w: W - 418 },
    ];
    const head = () => {
      doc.roundedRect(M0, y, W, 22, 6).fill(C.primarySoft);
      let x = M0;
      for (const c of cols) {
        label(c.k, x + 8, y + 8, C.primary, c.w - 12);
        x += c.w;
      }
      y += 26;
    };
    const newPage = () => {
      doc.addPage({ size: 'A4', margin: 0 });
      top();
      text(`${patient.name} · My medicine list (continued)`, M0, 18, { size: 9.5, weight: 'semi', color: C.ink2, width: W });
      doc.rect(M0, 36, W, 1).fill(C.primary);
      y = 52;
    };
    text('Daily medicines', M0, y, { size: 12, weight: 'bold', color: C.ink });
    text('Number of tablets at each time', M0 + 200, y + 2, { size: 8.5, color: C.ink3, width: W - 200, align: 'right' });
    y += 20;
    head();
    if (!daily.length) {
      text('No daily medicines.', M0 + 8, y + 2, { size: 10, color: C.ink3 });
      y += 22;
    }
    for (const c of daily) {
      const name = `${String(c.name).toUpperCase()}${c.strength ? ` ${c.strength}` : ''}`;
      const forText = c.prescriptionId && forOf.get(String(c.prescriptionId)) ? `For ${forOf.get(String(c.prescriptionId))}` : '';
      const by = c.prescriberName || 'Added by you';
      const sub = [forText, c.instructions && c.instructions !== howTaken(c) ? c.instructions : ''].filter(Boolean).join(' · ');
      doc.fontSize(10);
      const nameH = heightOf(doc, name, { width: cols[0].w - 14, weight: 'bold' });
      doc.fontSize(8.5);
      const subH = sub ? heightOf(doc, sub, { width: cols[0].w - 14 }) : 0;
      const howH = heightOf(doc, howTaken(c) || '—', { width: cols[4].w - 12 });
      doc.fontSize(8);
      const byH = heightOf(doc, by, { width: cols[0].w - 14 });
      const rowH = Math.max(42, nameH + subH + byH + 18, howH + 18);
      if (y + rowH > BOTTOM) { newPage(); head(); }
      let x = M0;
      let ny = text(name, x + 8, y + 7, { size: 10, weight: 'bold', width: cols[0].w - 14 });
      if (sub) ny = text(sub, x + 8, ny + 1, { size: 8.5, color: C.ink2, width: cols[0].w - 14 });
      text(by, x + 8, ny + 2, { size: 8, color: C.ink3, width: cols[0].w - 14 });
      x += cols[0].w;
      for (const [i, slot] of [[1, 'morning'], [2, 'afternoon'], [3, 'night']]) {
        const n = c.dose?.[slot] || 0;
        const cw = cols[i].w;
        if (n > 0) {
          // A filled dot with the count: easy to read at a glance.
          doc.circle(x + cw / 2, y + 16, 10).fill(C.primary);
          text(qty(n), x, y + 11, { size: 10, weight: 'bold', color: C.white, width: cw, align: 'center' });
        } else {
          text('—', x, y + 10, { size: 10, color: C.lineStrong, width: cw, align: 'center' });
        }
        x += cw;
      }
      text(howTaken(c) || '—', x + 6, y + 9, { size: 8.5, color: C.ink2, width: cols[4].w - 12 });
      x += cols[4].w;
      const dy = text(`Since ${fmtDay(c.startDate)}`, x + 6, y + 9, { size: 8.5, color: C.ink2, width: cols[5].w - 10 });
      text(c.endDate ? `Until ${fmtDay(c.endDate)}` : 'Ongoing', x + 6, dy + 2, { size: 8, color: C.ink3, width: cols[5].w - 10 });
      y += rowH;
      doc.moveTo(M0, y).lineTo(M0 + W, y).lineWidth(0.5).strokeColor(C.line).stroke();
    }
    y += 14;

    // ── Weekly / when needed ──
    if (other.length) {
      if (y + 60 > BOTTOM) newPage();
      text('Weekly and when-needed medicines', M0, y, { size: 12, weight: 'bold' });
      y += 20;
      for (const c of other) {
        const when = c.frequency === 'weekly' ? `Once a week${c.weekday ? ` · ${DAYS[c.weekday] || c.weekday}` : ''}` : 'Only when needed';
        const line = [when, howTaken(c), c.instructions, c.prescriberName].filter(Boolean).join(' · ');
        doc.fontSize(9);
        const h = Math.max(30, heightOf(doc, line, { width: W - 190 }) + 14);
        if (y + h > BOTTOM) newPage();
        text(`${String(c.name).toUpperCase()}${c.strength ? ` ${c.strength}` : ''}`, M0 + 8, y + 7, { size: 10, weight: 'bold', width: 170 });
        text(line, M0 + 186, y + 8, { size: 9, color: C.ink2, width: W - 190 });
        y += h;
        doc.moveTo(M0, y).lineTo(M0 + W, y).lineWidth(0.5).strokeColor(C.line).stroke();
      }
      y += 14;
    }

    // ── Meal times (the schedule above follows them) ──
    const t = patient.settings?.reminderTimes || {};
    if (y + 40 > BOTTOM) newPage();
    doc.roundedRect(M0, y, W, 34, 10).fill(C.primarySoft);
    text(
      `Meal times · Breakfast ${clock(t.morning || '08:00')} · Lunch ${clock(t.afternoon || '13:30')} · Dinner ${clock(t.night || '20:30')}${patient.settings?.bedAt ? ` · Bedtime ${clock(patient.settings.bedAt)}` : ''}`,
      M0 + 14, y + 11, { size: 9.5, weight: 'semi', color: C.primaryDark, width: W - 28 },
    );

    // ── Footer ──
    const range = doc.bufferedPageRange();
    for (let p = range.start; p < range.start + range.count; p++) {
      doc.switchToPage(p);
      doc.page.margins.bottom = 0;
      const fy = PAGE_H - 44;
      doc.moveTo(M0, fy).lineTo(M0 + W, fy).lineWidth(0.8).strokeColor(C.line).stroke();
      text('Shared by the patient from MedPin. Not a prescription: check with the prescribing doctor before changing or stopping any medicine.', M0, fy + 8, { size: 7.5, color: C.ink3, width: W - 70 });
      text(`Page ${p - range.start + 1} of ${range.count}`, M0 + W - 70, fy + 8, { size: 7.5, weight: 'semi', color: C.ink3, width: 70, align: 'right' });
    }
    doc.flushPages();
    doc.end();
  });
}

module.exports = { renderMedicineList };

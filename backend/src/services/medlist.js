// Patient-Medicines "Share medicine list": a one-page PDF of what the patient
// takes now, for a new doctor or pharmacy.
const PDFDocument = require('pdfkit');
const T = require('../lib/time');
const { doseText } = require('./clinical');

const FOOD = { before_food: 'before food', after_food: 'after food', with_food: 'with food', empty_stomach: 'empty stomach', bedtime: 'at bedtime' };

function renderMedicineList({ patient, courses }) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 48 });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.fontSize(18).text('Medicine list');
    doc.fontSize(11).fillColor('#555').text(`${patient.name}${T.ageFrom(patient) != null ? ` · ${T.ageFrom(patient)} yrs` : ''} · +91 ${patient.phone} · ${T.dayKey(new Date())}`);
    const allergies = (patient.allergies || []).map((a) => a.allergen).filter(Boolean);
    doc.fillColor('#000').moveDown(0.5).text(`Allergies: ${allergies.length ? allergies.join(', ') : 'none recorded'}`);
    doc.moveDown().fontSize(13).text('Taking now');
    doc.fontSize(11);
    if (!courses.length) doc.text('No medicines.');
    courses.forEach((c, i) => {
      const when = c.frequency === 'weekly' ? `Once a week${c.weekday ? ` · ${c.weekday}` : ''}` : doseText(c.dose);
      const food = c.foodRelation ? ` · ${FOOD[c.foodRelation] || c.foodRelation}` : '';
      const by = c.prescriberName ? ` · ${c.prescriberName}` : '';
      const since = c.startDate ? ` · since ${T.dayKey(c.startDate)}` : '';
      doc.text(`${i + 1}. ${c.name}${c.strength ? ` ${c.strength}` : ''} — ${when}${food}${by}${since}`);
      if (c.instructions) doc.fillColor('#555').text(`    ${c.instructions}`).fillColor('#000');
    });
    doc.moveDown(2).fontSize(9).fillColor('#777').text('Shared from the MedPin app by the patient. Check with the prescribing doctor before changing any medicine.');
    doc.end();
  });
}

module.exports = { renderMedicineList };

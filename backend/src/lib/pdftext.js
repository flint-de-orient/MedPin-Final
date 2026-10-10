// PDF text in English, Bengali and Hindi (pdfkit picks one font per run, so a
// line is split into runs by script). Fonts: Noto Sans family, SIL OFL 1.1 —
// see backend/assets/fonts/OFL.txt.
const path = require('path');

const DIR = path.join(__dirname, '..', '..', 'assets', 'fonts');
const FONTS = {
  latin: path.join(DIR, 'NotoSans.ttf'),
  bengali: path.join(DIR, 'NotoSansBengali.ttf'),
  devanagari: path.join(DIR, 'NotoSansDevanagari.ttf'),
};

/** Registers the fonts on a new PDFDocument and selects Latin. */
function setupFonts(doc) {
  for (const [name, file] of Object.entries(FONTS)) doc.registerFont(name, file);
  doc.font('latin');
  return doc;
}

const scriptOf = (ch) => {
  const c = ch.codePointAt(0);
  if (c >= 0x0980 && c <= 0x09ff) return 'bengali';
  if (c >= 0x0900 && c <= 0x097f) return 'devanagari';
  return null; // neutral: spaces, digits, punctuation join the current run
};

/** "Fever জ্বর ২ দিন" → [{font:'latin',text:'Fever '},{font:'bengali',text:'জ্বর ২ দিন'}] */
function runs(text) {
  const out = [];
  let font = 'latin';
  let buf = '';
  for (const ch of String(text ?? '')) {
    const s = scriptOf(ch);
    const next = s || (/[A-Za-z]/.test(ch) ? 'latin' : font);
    if (next !== font && buf) {
      out.push({ font, text: buf });
      buf = '';
    }
    font = next;
    buf += ch;
  }
  if (buf) out.push({ font, text: buf });
  return out;
}

/** doc.text() that switches fonts mid-line for Bengali / Devanagari. */
function write(doc, text, options = {}) {
  const parts = runs(text);
  if (!parts.length) return doc.text('', options);
  parts.forEach((p, i) => {
    doc.font(p.font).text(p.text, { ...options, continued: i < parts.length - 1 || options.continued });
  });
  return doc.font('latin');
}

module.exports = { setupFonts, write, runs };

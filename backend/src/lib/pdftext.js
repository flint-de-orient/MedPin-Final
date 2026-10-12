// PDF text in English, Bengali and Hindi (pdfkit picks one font per run, so a
// line is split into runs by script). Fonts: Noto Sans family, SIL OFL 1.1 —
// see backend/assets/fonts/OFL.txt. Latin text uses Figtree (the app's font,
// also SIL OFL 1.1) in regular, semibold and bold; Noto Sans covers symbols
// such as ℞.
const path = require('path');

const DIR = path.join(__dirname, '..', '..', 'assets', 'fonts');
const FONTS = {
  latin: path.join(DIR, 'Figtree-Regular.ttf'),
  semi: path.join(DIR, 'Figtree-SemiBold.ttf'),
  bold: path.join(DIR, 'Figtree-Bold.ttf'),
  noto: path.join(DIR, 'NotoSans.ttf'),
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

/**
 * doc.text() that switches fonts mid-line for Bengali / Devanagari.
 * options.weight: 'semi' | 'bold' for the Latin runs (Bengali / Hindi stay regular).
 * Pass x and y to place the first run; the rest follow it.
 */
function write(doc, text, options = {}) {
  const { weight, x, y, ...rest } = options;
  const latin = weight === 'bold' ? 'bold' : weight === 'semi' ? 'semi' : 'latin';
  const parts = runs(text);
  if (!parts.length) return x != null ? doc.text('', x, y, rest) : doc.text('', rest);
  parts.forEach((p, i) => {
    const o = { ...rest, continued: i < parts.length - 1 || rest.continued };
    doc.font(p.font === 'latin' ? latin : p.font);
    if (i === 0 && x != null) doc.text(p.text, x, y, o);
    else doc.text(p.text, o);
  });
  return doc.font('latin');
}

/** Height of [text] at the current size in [width] (Latin metrics; close enough for Indic). */
function heightOf(doc, text, { width, weight, lineGap } = {}) {
  const font = weight === 'bold' ? 'bold' : weight === 'semi' ? 'semi' : 'latin';
  doc.font(font);
  const h = doc.heightOfString(String(text ?? ''), { width, lineGap });
  doc.font('latin');
  return h;
}

module.exports = { setupFonts, write, runs, heightOf };

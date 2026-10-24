// Numbers as lab reports print them: "1,50,000" (Indian grouping) and "150,000" both mean
// 150000; "4.5" stays 4.5. A value that isn't a plain number ("Positive", "<0.5", "1+")
// gives NaN, so it is kept as text, never misread (parseFloat("1,50,000") is 1).
function labNumber(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : NaN;
  const s = String(v ?? '').trim().replace(/\s+/g, '');
  if (!/^-?\d{1,3}(,\d{2,3})*(\.\d+)?$|^-?\d+(\.\d+)?$/.test(s)) return NaN;
  return parseFloat(s.replace(/,/g, ''));
}

module.exports = { labNumber };

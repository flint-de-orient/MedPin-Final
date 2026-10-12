// Image clean-up for what prints on prescriptions.
const sharp = require('sharp');

/**
 * Logo with its plain background made transparent: the colour along the
 * edges (white, black or any flat colour) fades out, soft edges are kept,
 * and the empty margin is trimmed. A logo without a plain background (a photo)
 * or one that is already transparent is returned unchanged.
 * Returns { buffer, mimeType, removed }.
 */
async function removeLogoBackground(input) {
  const img = sharp(input, { failOn: 'none' }).rotate();
  const meta = await img.metadata();
  const { data, info } = await img.clone().resize({ width: Math.min(1200, meta.width || 1200), withoutEnlargement: true }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width, height } = info;
  const at = (x, y) => (y * width + x) * 4;
  // Edge pixels: is the border one flat colour?
  const edge = [];
  const step = Math.max(1, Math.round(Math.min(width, height) / 200));
  for (let x = 0; x < width; x += step) edge.push(at(x, 0), at(x, height - 1));
  for (let y = 0; y < height; y += step) edge.push(at(0, y), at(width - 1, y));
  const transparentEdge = edge.filter((i) => data[i + 3] < 30).length / edge.length;
  if (transparentEdge > 0.6) return { buffer: input, mimeType: meta.format === 'png' ? 'image/png' : `image/${meta.format}`, removed: false };
  const median = (k) => {
    const v = edge.map((i) => data[i + k]).sort((a, b) => a - b);
    return v[Math.floor(v.length / 2)];
  };
  const bg = [median(0), median(1), median(2)];
  const dist = (i) => Math.hypot(data[i] - bg[0], data[i + 1] - bg[1], data[i + 2] - bg[2]);
  const flat = edge.filter((i) => dist(i) < 40).length / edge.length;
  if (flat < 0.85) return { buffer: input, mimeType: `image/${meta.format === 'jpg' ? 'jpeg' : meta.format}`, removed: false };

  // Background → transparent (soft ramp so anti-aliased edges stay smooth).
  const out = Buffer.from(data);
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = at(x, y);
      const d = dist(i);
      const a = d <= 28 ? 0 : d >= 80 ? 255 : Math.round(((d - 28) / 52) * 255);
      out[i + 3] = Math.min(out[i + 3], a);
      if (out[i + 3] > 20) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return { buffer: input, mimeType: `image/${meta.format}`, removed: false }; // nothing but background
  const pad = 6;
  const left = Math.max(0, minX - pad);
  const top = Math.max(0, minY - pad);
  const buffer = await sharp(out, { raw: { width, height, channels: 4 } })
    .extract({ left, top, width: Math.min(width - left, maxX - minX + 1 + pad * 2), height: Math.min(height - top, maxY - minY + 1 + pad * 2) })
    .png()
    .toBuffer();
  return { buffer, mimeType: 'image/png', removed: true };
}

module.exports = { removeLogoBackground };

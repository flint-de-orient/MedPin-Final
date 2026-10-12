// Signature checker for prescription signatures.
//
// 1. Image checks (always): big enough, has ink, plain background, not a
//    photo or a page of text, not too faint, not cut off.
// 2. Clean-up: crop to the ink and make the paper transparent, so it prints
//    crisply on every letterhead.
// 3. AI reading (when an AI key is set): is it handwriting, and does it read
//    as the doctor's name. A name doubt is only a warning: many genuine
//    signatures can't be read.
//
// Each issue is { code, severity: 'block' | 'warn', message }.
const sharp = require('sharp');

const W = 800; // analysis width

const issue = (code, severity, message) => ({ code, severity, message });

/** Pixel statistics of the image (grayscale + alpha) at analysis size. */
async function measure(buffer) {
  const img = sharp(buffer, { failOn: 'none' }).rotate(); // phone photos: respect EXIF orientation
  const meta = await img.metadata();
  const { data, info } = await img
    .clone()
    .resize({ width: Math.min(W, meta.width || W), withoutEnlargement: true })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width, height } = info;
  const n = width * height;
  const lum = new Float32Array(n);
  const alpha = new Uint8Array(n);
  for (let i = 0; i < n; i += 1) {
    const r = data[i * 4];
    const g = data[i * 4 + 1];
    const b = data[i * 4 + 2];
    alpha[i] = data[i * 4 + 3];
    // Transparent pixels count as white paper.
    lum[i] = alpha[i] < 30 ? 255 : 0.299 * r + 0.587 * g + 0.114 * b;
  }
  // Paper colour and evenness from a 4% border.
  const edge = Math.max(2, Math.round(Math.min(width, height) * 0.04));
  const border = [];
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (x < edge || y < edge || x >= width - edge || y >= height - edge) border.push(lum[y * width + x]);
    }
  }
  border.sort((a, b) => a - b);
  const bg = border[Math.floor(border.length / 2)];
  const bgSpread = border[Math.floor(border.length * 0.9)] - border[Math.floor(border.length * 0.1)];
  // Ink: clearly darker than the paper.
  const inkLimit = Math.min(bg - 45, 175);
  let ink = 0;
  let inkSum = 0;
  let mid = 0;
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const v = lum[y * width + x];
      if (v < inkLimit) {
        ink += 1;
        inkSum += v;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      } else if (Math.abs(v - bg) > 25) mid += 1;
    }
  }
  return {
    meta, width, height, bg, bgSpread, inkLimit,
    coverage: ink / n,
    midTones: mid / n,
    inkMean: ink ? inkSum / ink : 255,
    box: ink ? { minX, minY, maxX, maxY } : null,
    touchesEdge: ink > 0 && (minX <= 1 || minY <= 1 || maxX >= width - 2 || maxY >= height - 2),
  };
}

/** The image checks; returns { issues, stats }. */
async function inspect(buffer) {
  let s;
  try {
    s = await measure(buffer);
  } catch {
    return { issues: [issue('UNREADABLE', 'block', "We couldn't read this image. Take the photo again or choose a PNG or JPG.")], stats: null };
  }
  const out = [];
  if ((s.meta.width || 0) < 300 || (s.meta.height || 0) < 80) {
    out.push(issue('TOO_SMALL', 'block', 'The image is too small to print clearly. Take a closer photo of the signature.'));
  }
  if (s.bg < 150 || s.bgSpread > 60) {
    out.push(issue('NOT_PLAIN', 'block', 'The background is not plain. Sign on plain white paper and photograph only the signature.'));
  } else if (s.coverage < 0.002) {
    out.push(issue('NO_INK', 'block', "We can't see a signature. Use a dark pen and fill more of the photo with it."));
  } else if (s.coverage > 0.3 || s.midTones > 0.25) {
    out.push(issue('NOT_A_SIGNATURE', 'block', 'This looks like a photo or a page, not a signature. Photograph just the signature on white paper.'));
  } else {
    if (s.inkMean > 130) out.push(issue('FAINT', 'warn', 'The signature is faint. A darker pen prints better.'));
    if (s.touchesEdge) out.push(issue('CUT_OFF', 'warn', 'Part of the signature may be cut off at the edge.'));
    const bw = s.box.maxX - s.box.minX + 1;
    const bh = s.box.maxY - s.box.minY + 1;
    if (bw / bh < 1.1) out.push(issue('SHAPE', 'warn', 'This is taller than most signatures. Check it is your signature, not initials or a stamp.'));
  }
  return { issues: out, stats: s };
}

/** Cropped, transparent PNG of the ink (dark navy), at most 600px wide. */
async function clean(buffer, stats) {
  const s = stats || (await measure(buffer));
  if (!s.box) return null;
  const scale = (s.meta.width || s.width) / s.width;
  const pad = 8;
  const left = Math.max(0, Math.floor((s.box.minX - pad) * scale));
  const top = Math.max(0, Math.floor((s.box.minY - pad) * scale));
  const width = Math.min((s.meta.width || s.width) - left, Math.ceil((s.box.maxX - s.box.minX + 1 + pad * 2) * scale));
  const height = Math.min((s.meta.height || s.height) - top, Math.ceil((s.box.maxY - s.box.minY + 1 + pad * 2) * scale));
  const cropped = sharp(buffer, { failOn: 'none' }).rotate().extract({ left, top, width, height }).resize({ width: Math.min(600, width), withoutEnlargement: true });
  const { data, info } = await cropped.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const out = Buffer.alloc(info.width * info.height * 4);
  const bg = s.bg;
  for (let i = 0; i < info.width * info.height; i += 1) {
    const a0 = data[i * 4 + 3];
    const v = a0 < 30 ? 255 : 0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2];
    // Darker than the paper → more opaque ink; paper → transparent.
    const k = Math.max(0, Math.min(1, (bg - 20 - v) / Math.max(30, bg - 20 - 40)));
    out[i * 4] = 17; // #111827-ish ink, prints black on any letterhead
    out[i * 4 + 1] = 24;
    out[i * 4 + 2] = 39;
    out[i * 4 + 3] = Math.round(k * 255);
  }
  return sharp(out, { raw: { width: info.width, height: info.height, channels: 4 } }).png().toBuffer();
}

/** AI reading of the cleaned signature (null when AI is off or fails). */
async function readWithAi(png, doctorName) {
  const ai = require('./ai');
  if (!ai.enabled()) return null;
  const out = await ai.completeJson({
    system: 'You check images uploaded as a doctor\'s handwritten signature for prescriptions. Decide if the image is a handwritten signature (not typed text, a stamp, a logo, a drawing or a photo). If it is, write what it reads as (or "unreadable"), and whether it plausibly matches the doctor\'s name: "yes" if it reads as that name, initials or surname; "no" only if it clearly reads as a different name; "unsure" when it can\'t be read. Many real signatures are scribbles: then say unsure, not no.',
    messages: [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: png.toString('base64') } },
        { type: 'text', text: `Doctor's name: ${doctorName}` },
      ],
    }],
    schema: {
      type: 'object',
      properties: {
        is_handwritten_signature: { type: 'boolean' },
        reads_as: { type: 'string' },
        matches_name: { type: 'string', enum: ['yes', 'no', 'unsure'] },
        reason: { type: 'string' },
      },
      required: ['is_handwritten_signature', 'reads_as', 'matches_name', 'reason'],
      additionalProperties: false,
    },
    vision: true,
    effort: 'low',
  }).catch((err) => {
    console.warn('[signature ai]', err.message);
    return null;
  });
  return out?.data || null;
}

/**
 * Checks an uploaded signature for [doctorName]. Returns
 * { status: 'ok' | 'warn' | 'rejected', issues, readsAs, by, cleaned }.
 */
async function check(buffer, doctorName) {
  const { issues, stats } = await inspect(buffer);
  if (issues.some((x) => x.severity === 'block')) return { status: 'rejected', issues, readsAs: null, by: 'image', cleaned: null };
  const cleaned = await clean(buffer, stats);
  let readsAs = null;
  let by = 'image';
  const ai = cleaned ? await readWithAi(cleaned, doctorName) : null;
  if (ai) {
    by = 'image+ai';
    readsAs = ai.reads_as && ai.reads_as.toLowerCase() !== 'unreadable' ? ai.reads_as.slice(0, 80) : null;
    if (!ai.is_handwritten_signature) {
      issues.push(issue('NOT_HANDWRITTEN', 'block', 'This doesn\'t look like a handwritten signature (typed text, a stamp or a logo). Sign by hand on white paper.'));
    } else if (ai.matches_name === 'no') {
      const shown = String(doctorName || '').replace(/^Dr\.?\s*/i, '');
      issues.push(issue('NAME_MISMATCH', 'warn', `This reads like “${readsAs || 'another name'}”, not ${shown}. Use it only if it is your own signature.`));
    }
  }
  const status = issues.some((x) => x.severity === 'block') ? 'rejected' : issues.length ? 'warn' : 'ok';
  return { status, issues, readsAs, by, cleaned: status === 'rejected' ? null : cleaned };
}

module.exports = { check, inspect, clean };

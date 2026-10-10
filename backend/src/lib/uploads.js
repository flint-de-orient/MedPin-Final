// Upload checks: allowed file types by content (magic bytes), not by the
// name or the content type the client claims.
const multer = require('multer');
const { badRequest } = require('./http');

const KINDS = {
  image: [
    { mime: 'image/png', test: (b) => b.length > 8 && b.readUInt32BE(0) === 0x89504e47 },
    { mime: 'image/jpeg', test: (b) => b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
    { mime: 'image/webp', test: (b) => b.length > 12 && b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP' },
    { mime: 'image/heic', test: (b) => b.length > 12 && b.toString('ascii', 4, 8) === 'ftyp' && /hei[cx]|mif1|msf1/.test(b.toString('ascii', 8, 12)) },
  ],
  pdf: [{ mime: 'application/pdf', test: (b) => b.length > 4 && b.toString('ascii', 0, 4) === '%PDF' }],
  audio: [
    { mime: 'audio/mp4', test: (b) => b.length > 12 && b.toString('ascii', 4, 8) === 'ftyp' && /M4A|mp4|isom|3gp/i.test(b.toString('ascii', 8, 12)) },
    { mime: 'audio/aac', test: (b) => b.length > 2 && b[0] === 0xff && (b[1] & 0xf6) === 0xf0 },
    { mime: 'audio/ogg', test: (b) => b.length > 4 && b.toString('ascii', 0, 4) === 'OggS' },
    { mime: 'audio/webm', test: (b) => b.length > 4 && b.readUInt32BE(0) === 0x1a45dfa3 },
    { mime: 'audio/mpeg', test: (b) => b.length > 3 && (b.toString('ascii', 0, 3) === 'ID3' || (b[0] === 0xff && (b[1] & 0xe0) === 0xe0)) },
    { mime: 'audio/wav', test: (b) => b.length > 12 && b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WAVE' },
  ],
};

const LABEL = { image: 'a photo (PNG, JPG, WebP or HEIC)', pdf: 'a PDF', audio: 'an audio recording' };

/** The detected type of [buffer] among [kinds], or null. */
function detect(buffer, kinds) {
  for (const k of kinds) {
    const hit = KINDS[k].find((t) => t.test(buffer));
    if (hit) return hit.mime;
  }
  return null;
}

/**
 * multer in memory with limits; every received file must really be one of
 * [kinds]. The detected type replaces the client's claimed mimetype.
 */
function uploader({ kinds, maxMb = 10, maxFiles = 5 }) {
  const m = multer({ storage: multer.memoryStorage(), limits: { fileSize: maxMb * 1024 * 1024, files: maxFiles } });
  const check = (req, _res, next) => {
    const files = req.file ? [req.file] : Object.values(req.files || {}).flat();
    for (const f of files) {
      const mime = detect(f.buffer, kinds);
      if (!mime) return next(badRequest(`Choose ${kinds.map((k) => LABEL[k]).join(' or ')}`, 'BAD_FILE_TYPE'));
      f.mimetype = mime;
    }
    return next();
  };
  const wrap = (mw) => (req, res, next) => mw(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      return next(badRequest(err.code === 'LIMIT_FILE_SIZE' ? `Files must be under ${maxMb} MB` : err.code === 'LIMIT_FILE_COUNT' ? `Up to ${maxFiles} files at a time` : 'The upload failed', 'BAD_UPLOAD'));
    }
    return err ? next(err) : check(req, res, next);
  });
  return { single: (field) => wrap(m.single(field)), array: (field, n) => wrap(m.array(field, n || maxFiles)) };
}

module.exports = { uploader, detect };

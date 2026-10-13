// Files go to S3-compatible storage when S3_* is set, else to ./uploads.
// Downloads use short-lived signed URLs: /files/<key>?exp=…&sig=…
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const env = require('../config/env');
const { publicBase } = require('../lib/request-base');
const { hmac, safeEqual } = require('../lib/security');

const useS3 = Boolean(env.s3.bucket && env.s3.accessKeyId && env.s3.secretAccessKey);
let s3;
const s3Client = () => {
  if (!s3) {
    const { S3Client } = require('@aws-sdk/client-s3');
    s3 = new S3Client({
      region: env.s3.region,
      endpoint: env.s3.endpoint || undefined,
      credentials: { accessKeyId: env.s3.accessKeyId, secretAccessKey: env.s3.secretAccessKey },
      forcePathStyle: Boolean(env.s3.endpoint),
    });
  }
  return s3;
};

const EXT = {
  'application/pdf': '.pdf',
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'audio/mpeg': '.mp3',
  'audio/mp4': '.m4a',
  'audio/aac': '.aac',
  'text/csv': '.csv',
  'application/json': '.json',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
};

/** Saves a buffer and returns the fileSchema object to store on a document. */
async function save(buffer, { folder, name, mimeType, pages }) {
  const ext = path.extname(name || '') || EXT[mimeType] || '';
  const key = `${folder}/${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}${ext}`;
  if (useS3) {
    const { PutObjectCommand } = require('@aws-sdk/client-s3');
    await s3Client().send(new PutObjectCommand({ Bucket: env.s3.bucket, Key: key, Body: buffer, ContentType: mimeType }));
  } else {
    const full = path.join(env.uploadsDir, key);
    await fs.promises.mkdir(path.dirname(full), { recursive: true });
    await fs.promises.writeFile(full, buffer);
  }
  return { key, name: name || path.basename(key), mimeType, sizeBytes: buffer.length, pages };
}

/** Writes a file at a given key (moving data between servers keeps the same keys). */
async function putAt(key, buffer, mimeType) {
  if (!/^[\w\-./]+$/.test(key) || key.includes('..')) throw new Error('Invalid key');
  if (useS3) {
    const { PutObjectCommand } = require('@aws-sdk/client-s3');
    await s3Client().send(new PutObjectCommand({ Bucket: env.s3.bucket, Key: key, Body: buffer, ContentType: mimeType }));
    return;
  }
  const full = path.join(env.uploadsDir, key);
  await fs.promises.mkdir(path.dirname(full), { recursive: true });
  await fs.promises.writeFile(full, buffer);
}

async function read(key) {
  if (useS3) {
    const { GetObjectCommand } = require('@aws-sdk/client-s3');
    const out = await s3Client().send(new GetObjectCommand({ Bucket: env.s3.bucket, Key: key }));
    return Buffer.from(await out.Body.transformToByteArray());
  }
  const root = path.resolve(env.uploadsDir);
  const full = path.resolve(root, key);
  if (!full.startsWith(root + path.sep)) throw new Error('Invalid key');
  return fs.promises.readFile(full);
}

const signature = (key, exp) => hmac(`file:${key}:${exp}`);

/** Signed download URL valid for `ttlSec` seconds. */
function signedUrl(key, ttlSec = 3600) {
  if (!key) return null;
  const exp = Math.floor(Date.now() / 1000) + ttlSec;
  return `${publicBase()}/files/${key}?exp=${exp}&sig=${signature(key, exp)}`;
}

function verifySignature(key, exp, sig) {
  if (!exp || !sig || Number(exp) < Date.now() / 1000) return false;
  return safeEqual(signature(key, exp), sig);
}

/** Adds a signed `url` to a stored file object (for API responses). */
const withUrl = (file) => {
  if (!file || !file.key) return file;
  const plain = file.toObject ? file.toObject() : file;
  return { ...plain, url: signedUrl(file.key) };
};

module.exports = { save, putAt, read, signedUrl, verifySignature, withUrl, useS3 };

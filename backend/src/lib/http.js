const mongoose = require('mongoose');

class HttpError extends Error {
  constructor(status, message, code, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const badRequest = (message, code = 'BAD_REQUEST', details) => new HttpError(400, message, code, details);
const unauthorized = (message = 'Sign in again', code = 'UNAUTHORIZED') => new HttpError(401, message, code);
const forbidden = (message = "You don't have access to this", code = 'FORBIDDEN') => new HttpError(403, message, code);
const notFound = (what = 'Item') => new HttpError(404, `${what} not found`, 'NOT_FOUND');
const conflict = (message, code = 'CONFLICT', details) => new HttpError(409, message, code, details);

/** Copies only the listed keys that are present (not undefined). */
const pick = (obj, keys) => {
  const out = {};
  for (const k of keys) if (obj && obj[k] !== undefined) out[k] = obj[k];
  return out;
};

const isId = (id) => mongoose.isValidObjectId(id) && String(new mongoose.Types.ObjectId(id)) === String(id);
const oid = (id, what = 'id') => {
  if (!isId(id)) throw badRequest(`Invalid ${what}`, 'INVALID_ID');
  return new mongoose.Types.ObjectId(id);
};

const paging = (query, max = 100) => {
  const limit = Math.min(Math.max(parseInt(query.limit, 10) || 50, 1), max);
  const skip = Math.max(parseInt(query.skip, 10) || 0, 0);
  return { limit, skip };
};

/** Comma-separated query value → array. */
const list = (value) =>
  (Array.isArray(value) ? value : String(value || '').split(','))
    .map((s) => String(s).trim())
    .filter(Boolean);

const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** "+91 98765-43210" → "9876543210". */
const normalizePhone = (raw) => {
  const digits = String(raw || '').replace(/\D/g, '');
  const ten = digits.length === 12 && digits.startsWith('91') ? digits.slice(2) : digits.length === 11 && digits.startsWith('0') ? digits.slice(1) : digits;
  if (!/^[6-9]\d{9}$/.test(ten)) throw badRequest('Enter a 10-digit mobile number', 'INVALID_PHONE');
  return ten;
};

const maskPhone = (p) => `+91 ${p.slice(0, 5)} •••${p.slice(-2)}`;

module.exports = {
  HttpError,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  pick,
  isId,
  oid,
  paging,
  list,
  escapeRegex,
  normalizePhone,
  maskPhone,
};

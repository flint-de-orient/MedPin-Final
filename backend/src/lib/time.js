// India has a fixed UTC+5:30 offset (no DST), so day maths is done in IST.
const IST_MS = 330 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const WEEKDAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/** IST midnight (as a UTC Date) of the day containing `d`. */
const dayStart = (d = new Date()) => {
  const t = new Date(d).getTime() + IST_MS;
  return new Date(Math.floor(t / DAY_MS) * DAY_MS - IST_MS);
};

const addDays = (d, n) => new Date(new Date(d).getTime() + n * DAY_MS);
const addMinutes = (d, n) => new Date(new Date(d).getTime() + n * 60000);

/** "2026-09-29" → IST midnight. Also accepts full ISO strings / Dates. */
const parseDay = (value) => {
  if (!value) return dayStart();
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return new Date(`${value}T00:00:00+05:30`);
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) throw Object.assign(new Error('Invalid date'), { status: 400 });
  return dayStart(d);
};

/** IST calendar key "2026-09-29". */
const dayKey = (d) => new Date(new Date(d).getTime() + IST_MS).toISOString().slice(0, 10);

/** 'mon'…'sun' for the IST day of `d`. */
const weekday = (d) => WEEKDAYS[new Date(new Date(d).getTime() + IST_MS).getUTCDay()];

/** Minutes since IST midnight. */
const minuteOfDay = (d) => Math.round((new Date(d).getTime() - dayStart(d).getTime()) / 60000);

/** Date for `minutes` after IST midnight of `day`. */
const atMinute = (day, minutes) => addMinutes(dayStart(day), minutes);

/** "HH:MM" → minutes. */
const hhmmToMin = (s) => {
  const [h, m] = String(s).split(':').map(Number);
  return h * 60 + (m || 0);
};

const fmtTime = (min) => {
  const h = Math.floor(min / 60);
  const m = min % 60;
  const h12 = ((h + 11) % 12) + 1;
  return `${h12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
};

const ageFrom = (patient, now = new Date()) => {
  if (patient.dateOfBirth) {
    const dob = new Date(patient.dateOfBirth);
    let age = now.getFullYear() - dob.getFullYear();
    if (now < new Date(now.getFullYear(), dob.getMonth(), dob.getDate())) age -= 1;
    return age;
  }
  if (patient.ageYears == null) return null;
  const since = patient.ageRecordedAt || patient.createdAt || now;
  return patient.ageYears + Math.floor((now - new Date(since)) / (365.25 * DAY_MS));
};

module.exports = {
  IST_MS, DAY_MS, dayStart, addDays, addMinutes, parseDay, dayKey, weekday, minuteOfDay, atMinute, hhmmToMin, fmtTime, ageFrom,
};

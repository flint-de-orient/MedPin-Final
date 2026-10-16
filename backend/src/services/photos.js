// Profile photos for lists and headers, on every side of the app: a user's
// photo (patients, staff, doctors — doctors' public photo is the same file),
// as a link that stays the same all day so the phone caches it.
const M = require('../models');
const storage = require('./storage');

const urlOf = (user) => (user?.photo?.key ? storage.stableUrl(user.photo.key) : user?.avatarUrl || null);

/** userId → photo link (null when none), for many users at once. */
async function photosFor(userIds) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(String))];
  if (!ids.length) return new Map();
  const users = await M.User.find({ _id: { $in: ids } }, 'photo avatarUrl').lean();
  return new Map(users.map((u) => [String(u._id), urlOf(u)]));
}

/** A doctor's photo: their public profile photo, else their account photo. */
async function doctorPhotos(userIds) {
  const map = await photosFor(userIds);
  const profiles = await M.DoctorProfile.find({ userId: { $in: [...map.keys()] }, 'photo.key': { $exists: true } }, 'userId photo').lean();
  for (const p of profiles) map.set(String(p.userId), storage.stableUrl(p.photo.key));
  return map;
}

module.exports = { photosFor, doctorPhotos, urlOf };

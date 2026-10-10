// Map points: [lng, lat] GeoJSON from app coordinates or a pasted Google Maps link.
const valid = (lat, lng) => Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);

/** A GeoJSON point from lat / lng (strings or numbers); undefined if not a real place. */
function pointFrom(lat, lng) {
  if (lat == null || lng == null || lat === '' || lng === '') return undefined;
  const a = Number(lat);
  const b = Number(lng);
  return valid(a, b) ? { type: 'Point', coordinates: [b, a] } : undefined;
}

/**
 * Coordinates inside a Google Maps link ("…/@22.58,88.41,17z", "?q=22.58,88.41",
 * "!3d22.58!4d88.41", "ll=22.58,88.41"). Short links (maps.app.goo.gl) carry none.
 */
function pointFromMapsUrl(url) {
  const s = decodeURIComponent(String(url || ''));
  const pats = [/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/, /@(-?\d+\.\d+),(-?\d+\.\d+)/, /[?&](?:q|query|ll|destination|center)=(-?\d+\.\d+),\s*(-?\d+\.\d+)/];
  for (const re of pats) {
    const m = s.match(re);
    if (m) return pointFrom(m[1], m[2]);
  }
  return undefined;
}

/** Point from a request body: lat / lng first, else its googleMapsUrl. */
const pointFromBody = (body = {}) => pointFrom(body.lat, body.lng) || pointFromMapsUrl(body.googleMapsUrl);

module.exports = { pointFrom, pointFromMapsUrl, pointFromBody };

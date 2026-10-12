// Address search and "what's at this pin" for the clinic map, through
// OpenStreetMap's Nominatim. Kept polite (one request a second, a clear
// User-Agent, results cached for a day) as its usage policy asks; set
// GEOCODER_URL to use another Nominatim-compatible service in production.
const env = require('../config/env');

const BASE = process.env.GEOCODER_URL || 'https://nominatim.openstreetmap.org';
const cache = new Map(); // key → { at, value }
const DAY = 24 * 3600e3;
let last = 0;

async function call(path, params) {
  const key = `${path}?${new URLSearchParams(params)}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < DAY) return hit.value;
  const wait = Math.max(0, last + 1100 - Date.now());
  last = Date.now() + wait;
  if (wait) await new Promise((r) => setTimeout(r, wait));
  const resp = await fetch(`${BASE}/${key}`, {
    headers: { 'user-agent': `MedPin/1.0 (clinic app${env.support.email ? `; ${env.support.email}` : ''})`, 'accept-language': 'en-IN,en' },
    signal: AbortSignal.timeout(7000),
  });
  if (!resp.ok) throw new Error(`geocoder ${resp.status}`);
  const value = await resp.json();
  cache.set(key, { at: Date.now(), value });
  if (cache.size > 2000) cache.delete(cache.keys().next().value);
  return value;
}

const parts = (a = {}) => ({
  road: [a.house_number, a.road].filter(Boolean).join(' ') || undefined,
  area: a.suburb || a.neighbourhood || a.city_district || a.village || a.town || undefined,
  city: a.city || a.town || a.state_district || a.county || undefined,
  pincode: a.postcode || undefined,
  state: a.state || undefined,
});

/** Places matching [q] in India: [{ lat, lng, label, area, city, pincode }]. */
async function search(q, { near } = {}) {
  const params = { q: String(q).slice(0, 200), format: 'jsonv2', addressdetails: 1, limit: 6, countrycodes: 'in' };
  if (near) params.viewbox = `${near.lng - 0.5},${near.lat + 0.5},${near.lng + 0.5},${near.lat - 0.5}`;
  const rows = await call('search', params);
  return rows.map((r) => ({ lat: Number(r.lat), lng: Number(r.lon), label: r.display_name, ...parts(r.address) }));
}

/** The address at a point: { label, road, area, city, pincode }. */
async function reverse(lat, lng) {
  const r = await call('reverse', { lat, lon: lng, format: 'jsonv2', addressdetails: 1, zoom: 18 });
  if (!r || r.error) return null;
  const p = parts(r.address);
  const label = [p.road, p.area, p.city, p.pincode].filter(Boolean).join(', ') || r.display_name;
  return { label, ...p };
}

/**
 * Follows a short Google Maps link (maps.app.goo.gl, goo.gl/maps) to the full
 * URL, which carries the coordinates. Returns the final URL or null.
 */
async function expandMapsLink(url) {
  if (!/^https:\/\/(maps\.app\.goo\.gl|goo\.gl\/maps|g\.co\/kgs)\//i.test(String(url || ''))) return null;
  let current = url;
  for (let i = 0; i < 4; i += 1) {
    const resp = await fetch(current, { method: 'GET', redirect: 'manual', signal: AbortSignal.timeout(6000) }).catch(() => null);
    const next = resp?.headers.get('location');
    if (!next) return i ? current : null;
    current = new URL(next, current).toString();
    if (/google\.[a-z.]+\/maps/.test(current) && /@-?\d|[?&](q|ll|query)=-?\d|!3d-?\d/.test(decodeURIComponent(current))) return current;
  }
  return current;
}

module.exports = { search, reverse, expandMapsLink };

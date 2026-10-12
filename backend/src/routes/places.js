// Clinic map helpers for signed-in users: address search and the address at a pin.
const { Router } = require('express');
const { requireAuth } = require('../middleware/auth');
const { badRequest } = require('../lib/http');
const { pointFrom } = require('../lib/geo');
const places = require('../services/places');

const r = Router();
r.use(requireAuth);

r.get('/geo/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 3) throw badRequest('Type at least 3 letters', 'QUERY_TOO_SHORT');
  const near = pointFrom(req.query.lat, req.query.lng);
  try {
    res.json({ items: await places.search(q, { near: near && { lat: near.coordinates[1], lng: near.coordinates[0] } }) });
  } catch (err) {
    console.warn('[geo search]', err.message);
    res.status(503).json({ error: { code: 'GEO_UNAVAILABLE', message: "Address search isn't available right now. Move the pin by hand." } });
  }
});

r.get('/geo/reverse', async (req, res) => {
  const p = pointFrom(req.query.lat, req.query.lng);
  if (!p) throw badRequest('Choose a point on the map', 'BAD_POINT');
  try {
    res.json({ place: await places.reverse(p.coordinates[1], p.coordinates[0]) });
  } catch (err) {
    console.warn('[geo reverse]', err.message);
    res.json({ place: null });
  }
});

module.exports = r;

// The address the current request came in on ("http://192.168.1.32:4000"),
// for links the app opens (file downloads, payment pages) when PUBLIC_URL
// isn't set — so a phone on Wi-Fi gets a link it can reach, not "localhost".
const { AsyncLocalStorage } = require('async_hooks');
const env = require('../config/env');

const als = new AsyncLocalStorage();

function middleware(req, _res, next) {
  const host = req.get('host');
  als.run({ base: host ? `${req.protocol}://${host}` : null }, next);
}

/** PUBLIC_URL when set, else the current request's own address. */
function publicBase() {
  if (env.publicUrlSet) return env.publicUrl;
  return als.getStore()?.base || env.publicUrl;
}

module.exports = { middleware, publicBase };

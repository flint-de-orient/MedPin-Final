// Loads an export made by scripts/export-doctors.js into this server's
// database and file storage (MONGODB_URI / MONGODB_DB_NAME / uploads or S3
// from .env). Records keep their ids, so running it again updates them in
// place; nothing else in the database is touched.
//
// Usage (on the new server, after `npm run db:seed -- --catalogs-only`):
//   node scripts/import-doctors.js <export-dir>
const fs = require('fs');
const path = require('path');
const { EJSON } = require('bson');
const { connect, disconnect, mongoose } = require('../src/db');
const storage = require('../src/services/storage');

const ORDER = ['practices', 'subscriptions', 'locations', 'departments', 'locationclosures', 'users', 'doctorprofiles', 'doctorlocations', 'doctorleaves', 'members', 'knowledgeentries'];
const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.pdf': 'application/pdf', '.svg': 'image/svg+xml' };

async function main() {
  const dir = path.resolve(process.argv[2] || 'doctor-export');
  const data = EJSON.parse(await fs.promises.readFile(path.join(dir, 'doctors.json'), 'utf8'), { relaxed: false });
  await connect();
  const db = mongoose.connection.db;

  for (const name of ORDER) {
    const rows = data[name] || [];
    if (!rows.length) continue;
    const res = await db.collection(name).bulkWrite(rows.map((doc) => ({ replaceOne: { filter: { _id: doc._id }, replacement: doc, upsert: true } })), { ordered: false });
    console.log(`  ${name}: ${rows.length} (${res.upsertedCount} new, ${res.modifiedCount} updated)`);
  }

  let copied = 0;
  for (const key of data.files || []) {
    const from = path.join(dir, 'files', key);
    if (!fs.existsSync(from)) {
      console.warn(`  file not in export: ${key}`);
      continue;
    }
    await storage.putAt(key, await fs.promises.readFile(from), MIME[path.extname(key).toLowerCase()] || 'application/octet-stream');
    copied += 1;
  }
  console.log(`  files: ${copied}`);
  // Unique indexes (phone numbers etc.) as the app expects.
  require('../src/models');
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes().catch(() => {})));
  console.log('Done.');
  await disconnect();
}

main().catch(async (err) => {
  console.error(err);
  await disconnect().catch(() => {});
  process.exit(1);
});

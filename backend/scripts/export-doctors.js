// Exports the clinic and its doctors (not staff or patients) to move to another
// server: practice, plan, locations, departments, closures, doctors' accounts,
// profiles, schedules, leaves, memberships and knowledge base, with the files
// they point to (photos, signatures, logos, letterheads).
//
// Usage: node scripts/export-doctors.js <out-dir> [--phone 9XXXXXXXXX]
//   --phone: only that doctor (their practice, its locations and departments).
//   → <out-dir>/doctors.json (Extended JSON: ids and dates kept) + <out-dir>/files/…
// Read-only on this database. The output holds personal data: keep it private,
// never commit it. Load it on the new server with scripts/import-doctors.js.
const fs = require('fs');
const path = require('path');
const { EJSON } = require('bson');
const { connect, disconnect, mongoose } = require('../src/db');
const storage = require('../src/services/storage');

const DOCTOR_ROLES = ['doctor'];

/** Every { key } file reference inside a document. */
function fileKeys(value, out = new Set()) {
  if (Array.isArray(value)) value.forEach((v) => fileKeys(v, out));
  else if (value && typeof value === 'object' && !(value instanceof Date) && !value._bsontype) {
    if (typeof value.key === 'string' && /^[\w\-./]+$/.test(value.key) && (value.mimeType || value.name || value.sizeBytes)) out.add(value.key);
    Object.values(value).forEach((v) => fileKeys(v, out));
  }
  return out;
}

async function main() {
  const args = process.argv.slice(2);
  const pi = args.indexOf('--phone');
  const phone = pi >= 0 ? String(args[pi + 1] || '').replace(/\D/g, '').slice(-10) : null;
  const outDir = path.resolve(args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--phone') || 'doctor-export');
  await connect();
  const db = mongoose.connection.db;
  const col = (n) => db.collection(n);

  let only = null;
  if (phone) {
    const u = await col('users').findOne({ phone: { $regex: `${phone}$` } }, { projection: { _id: 1 } });
    if (!u) throw new Error(`No account with phone ${phone}`);
    only = u._id;
  }
  const members = await col('members').find({ role: { $in: DOCTOR_ROLES }, ...(only ? { userId: only } : {}) }).toArray();
  if (!members.length) throw new Error('No doctor found to export');
  const practiceIds = [...new Set(members.map((m) => String(m.practiceId)))].map((id) => new mongoose.Types.ObjectId(id));
  const doctorIds = [...new Set(members.map((m) => String(m.userId)))].map((id) => new mongoose.Types.ObjectId(id));
  const inPractice = { practiceId: { $in: practiceIds } };

  const data = {
    exportedAt: new Date(),
    practices: await col('practices').find({ _id: { $in: practiceIds } }).toArray(),
    subscriptions: await col('subscriptions').find(inPractice).toArray(),
    locations: await col('locations').find(inPractice).toArray(),
    departments: await col('departments').find(inPractice).toArray(),
    locationclosures: await col('locationclosures').find(inPractice).toArray(),
    users: await col('users').find({ _id: { $in: doctorIds } }).toArray(),
    doctorprofiles: await col('doctorprofiles').find({ userId: { $in: doctorIds } }).toArray(),
    doctorlocations: await col('doctorlocations').find({ doctorId: { $in: doctorIds } }).toArray(),
    doctorleaves: await col('doctorleaves').find({ doctorId: { $in: doctorIds } }).toArray(),
    members,
    knowledgeentries: await col('knowledgeentries').find(inPractice).toArray(),
  };

  // Files the records point to.
  const keys = fileKeys(Object.values(data));
  await fs.promises.mkdir(path.join(outDir, 'files'), { recursive: true });
  const files = [];
  for (const key of keys) {
    try {
      const buf = await storage.read(key);
      const to = path.join(outDir, 'files', key);
      await fs.promises.mkdir(path.dirname(to), { recursive: true });
      await fs.promises.writeFile(to, buf);
      files.push(key);
    } catch (err) {
      console.warn(`  file missing, skipped: ${key} (${err.message})`);
    }
  }
  data.files = files;
  await fs.promises.writeFile(path.join(outDir, 'doctors.json'), EJSON.stringify(data, null, 2, { relaxed: false }));

  console.log(`Exported to ${outDir}`);
  for (const [k, v] of Object.entries(data)) if (Array.isArray(v)) console.log(`  ${k}: ${v.length}`);
  await disconnect();
}

main().catch(async (err) => {
  console.error(err);
  await disconnect().catch(() => {});
  process.exit(1);
});

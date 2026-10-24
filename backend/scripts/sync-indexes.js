// Creates every collection and index in the configured database.
// Usage: npm run db:sync
const { connect, disconnect, mongoose } = require('../src/db');
const env = require('../src/config/env');
require('../src/models');

(async () => {
  await connect();
  console.log(`Connected to ${env.mongo.uri} / ${env.mongo.dbName}`);
  // Family profiles (2026-10): records from before are each their phone's holder.
  const P = mongoose.models.Patient;
  if (P) {
    const r = await P.collection.updateMany({ primary: { $exists: false }, familyOf: { $exists: false } }, { $set: { primary: true } });
    if (r.modifiedCount) console.log(`  patients marked as their phone's holder: ${r.modifiedCount}`);
  }
  const names = Object.keys(mongoose.models).sort();
  for (const name of names) {
    const Model = mongoose.models[name];
    await Model.createCollection();
    await Model.syncIndexes();
    const indexes = await Model.collection.indexes();
    console.log(`  ${Model.collection.collectionName.padEnd(22)} ${indexes.length} indexes`);
  }
  console.log(`${names.length} collections ready.`);
  // MedPin's plans for clinics (a server set up without the seed had none); prices already set stay.
  await require('../src/services/billing').ensurePlans();
  console.log(`  plans: ${await mongoose.models.Plan.countDocuments({})}`);
  await disconnect();
})().catch(async (err) => {
  console.error(err.message);
  await disconnect();
  process.exit(1);
});

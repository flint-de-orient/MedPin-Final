// Creates every collection and index in the configured database.
// Usage: npm run db:sync
const { connect, disconnect, mongoose } = require('../src/db');
const env = require('../src/config/env');
require('../src/models');

(async () => {
  await connect();
  console.log(`Connected to ${env.mongo.uri} / ${env.mongo.dbName}`);
  const names = Object.keys(mongoose.models).sort();
  for (const name of names) {
    const Model = mongoose.models[name];
    await Model.createCollection();
    await Model.syncIndexes();
    const indexes = await Model.collection.indexes();
    console.log(`  ${Model.collection.collectionName.padEnd(22)} ${indexes.length} indexes`);
  }
  console.log(`${names.length} collections ready.`);
  await disconnect();
})().catch(async (err) => {
  console.error(err.message);
  await disconnect();
  process.exit(1);
});

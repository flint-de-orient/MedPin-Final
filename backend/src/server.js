const env = require('./config/env');
const { connect, disconnect, mongoose } = require('./db');
const { createApp } = require('./app');
require('./models');

async function start() {
  await connect();
  // Keep collections and indexes in step with the models on every start.
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
  const app = createApp();
  const server = app.listen(env.port, () => {
    console.log(`MedPin API on http://localhost:${env.port}  (db ${env.mongo.dbName}, ${env.nodeEnv})`);
  });
  // Reminders and summaries (JOBS=off to run an API-only process).
  const jobs = require('./services/jobs');
  if (process.env.JOBS !== 'off') jobs.start();
  const stop = async () => {
    jobs.stop();
    server.close();
    await disconnect();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

start().catch((err) => {
  console.error('Failed to start:', err.message);
  process.exit(1);
});

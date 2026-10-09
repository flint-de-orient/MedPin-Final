const mongoose = require('mongoose');
const env = require('./config/env');

mongoose.set('strictQuery', true);

async function connect() {
  await mongoose.connect(env.mongo.uri, {
    dbName: env.mongo.dbName,
    serverSelectionTimeoutMS: 5000,
  });
  return mongoose.connection;
}

async function disconnect() {
  await mongoose.disconnect();
}

module.exports = { connect, disconnect, mongoose };

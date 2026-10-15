// npm run check:push — is push sending set up on this server? Prints what's
// missing (names only) and asks Google for an access token with the key.
// Sends no notification to anyone.
const { fcmStatus, fcmAccessToken } = require('../src/services/push');

(async () => {
  const s = fcmStatus();
  if (!s.on) {
    console.log(`FCM off — ${s.problems.join('; ')}`);
    process.exit(1);
  }
  try {
    await fcmAccessToken();
    console.log(`FCM on — project ${s.projectId}; Google accepted the key. Restart the backend if it was running before the change.`);
  } catch (err) {
    console.log(`FCM key set but Google refused it: ${err.message}`);
    process.exit(1);
  }
})();

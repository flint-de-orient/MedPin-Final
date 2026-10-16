// Which watch or ring an app's data comes from (Health Connect / Apple Health
// tell the app that wrote each reading). Phone-only apps (Health Connect
// itself, Google Fit counting on the phone, MedPin) are neither.
const RINGS = {
  'com.ouraring.oura': 'Oura', 'com.ultrahuman.android': 'Ultrahuman', 'com.ringconn.app': 'RingConn',
  'com.circular.ring': 'Circular', 'com.boat.ring': 'boAt Ring', 'com.noisefit.ring': 'Noise Luna',
};
const WATCHES = {
  'com.fitbit.FitbitMobile': 'Fitbit', 'com.mi.health': 'Mi Fitness', 'com.xiaomi.wearable': 'Mi Fitness',
  'com.huami.watch.hmwatchmanager': 'Zepp (Amazfit)', 'com.garmin.android.apps.connectmobile': 'Garmin Connect',
  'com.noisefit': 'NoiseFit', 'com.coveiot.android.boat': 'boAt Crest', 'com.huawei.health': 'Huawei Health',
  'com.google.android.apps.fitness.wear': 'Wear OS', 'com.fossil.wearables.fossil': 'Fossil', 'com.oneplus.health': 'OHealth',
  'com.realme.wearable': 'realme Link', 'com.coros.coros': 'COROS', 'com.polar.beat': 'Polar', 'com.whoop.android': 'WHOOP',
  'com.samsung.android.app.watchmanager': 'Galaxy Wearable', 'com.apple.health.watch': 'Apple Watch',
};
// Apps that count steps on the phone too: a watch only when they wrote what a phone
// can't measure (heart rate, SpO₂) — a Samsung phone alone isn't a smartwatch.
const PHONE_OR_WATCH = {
  'com.sec.android.app.shealth': 'Samsung Health', 'com.huawei.health': 'Huawei Health', 'com.oneplus.health': 'OHealth',
  'com.heytap.health': 'HeyTap Health',
};
const WORN = new Set(['pulse', 'spo2']);

/** origins: package names; kinds: { package: ['steps', 'pulse', …] } — what each wrote. */
function classifyOrigins(origins, kinds = {}) {
  const watch = new Set();
  const ring = new Set();
  for (const o of origins) {
    if (PHONE_OR_WATCH[o]) {
      if ((kinds[o] || []).some((k) => WORN.has(k))) watch.add(PHONE_OR_WATCH[o]);
      continue;
    }
    if (RINGS[o]) ring.add(RINGS[o]);
    else if (WATCHES[o]) watch.add(WATCHES[o]);
    else if (/ring/i.test(o) && !/ringtone/i.test(o)) ring.add(o);
    else if (/watch|wear|band|fit(?!ness\.phone)/i.test(o) && !/google\.android\.apps\.fitness$/.test(o)) watch.add(o);
  }
  return { watch: [...watch], ring: [...ring] };
}

module.exports = { classifyOrigins, RINGS, WATCHES, PHONE_OR_WATCH };

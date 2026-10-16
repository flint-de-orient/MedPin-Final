import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../widgets/mp.dart';
import 'api.dart';
import 'config.dart';
import 'phone_steps.dart';
import 'session.dart';

/// Watch / ring / phone readings through Health Connect (Android) or Apple
/// Health (iPhone): daily steps, heart rate, SpO₂, blood pressure, sugar and
/// weight from the last 7 days go to POST /api/patient/device-sync — when the
/// app opens or comes back, and in the background on the server's silent
/// 'device_sync' push (data/push.dart; quiet: [sync] with no context).
class DeviceSync {
  DeviceSync._();
  static final _health = Health();
  static bool _configured = false;
  static DateTime? _lastRun;
  static Future<bool>? _running;
  static _ResumeSync? _resume;

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.WEIGHT,
  ];

  /// What the server calls each type (originKinds tells a watch from a phone app).
  static const _kinds = {
    HealthDataType.STEPS: 'steps',
    HealthDataType.HEART_RATE: 'pulse',
    HealthDataType.BLOOD_OXYGEN: 'spo2',
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC: 'bp',
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC: 'bp',
    HealthDataType.BLOOD_GLUCOSE: 'sugar',
    HealthDataType.WEIGHT: 'weight',
  };

  static bool get supported => !AppMode.preview && (Platform.isAndroid || Platform.isIOS);

  static Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static Future<bool> _hcAvailable() async =>
      Platform.isIOS || await _health.getHealthConnectSdkStatus() == HealthConnectSdkStatus.sdkAvailable;

  /// The types MedPin may read, one by one: Android grants each separately, so
  /// one refused type must not hide the rest. iOS never says whether reading
  /// is allowed (null), so there every type is tried.
  static Future<List<HealthDataType>> _granted() async {
    final out = <HealthDataType>[];
    for (final t in _types) {
      final ok = await _health.hasPermissions([t], permissions: const [HealthDataAccess.READ]);
      if (ok == true || (ok == null && Platform.isIOS)) out.add(t);
    }
    return out;
  }

  /// Health Connect is installed and MedPin may read at least one type
  /// (Android only: iOS doesn't tell).
  static Future<bool> healthConnectGranted() async {
    if (!supported || !Platform.isAndroid) return false;
    try {
      await _configure();
      if (!await _hcAvailable()) return false;
      for (final t in _types) {
        if (await _health.hasPermissions([t], permissions: const [HealthDataAccess.READ]) == true) return true;
      }
    } catch (e) {
      debugPrint('device sync: $e');
    }
    return false;
  }

  /// First time: asks for access (offering to install Health Connect if needed), then syncs.
  static Future<bool> connect(BuildContext context) async {
    if (!supported) return false;
    try {
      // The phone counts steps itself: no watch needed.
      final phone = await PhoneSteps.allow();
      await _configure();
      if (Platform.isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        if (status != HealthConnectSdkStatus.sdkAvailable) {
          // Steps still come from the phone, but a watch / ring only reaches
          // MedPin through Health Connect: offer it rather than stay silent.
          var sent = false;
          if (phone && context.mounted) sent = await sync(context, force: true);
          if (context.mounted) {
            await _offerHealthConnect(context, update: status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired, phone: phone);
          }
          return sent;
        }
      }
      final ok = await _health.requestAuthorization(_types, permissions: [for (final _ in _types) HealthDataAccess.READ]);
      if (!ok && !phone) {
        if (context.mounted) toast(context, 'Allow MedPin to read your health data to sync');
        return false;
      }
      if (ok) await _allowBackground();
      if (!context.mounted) return false;
      return sync(context, force: true);
    } catch (e) {
      debugPrint('device sync: $e');
      if (context.mounted) toast(context, "Couldn't connect to your phone's health data");
      return false;
    }
  }

  /// Readings also go up while MedPin is closed (the server's silent
  /// 'device_sync' push, data/push.dart): Android 14+ asks for that separately.
  /// Needs READ_HEALTH_DATA_IN_BACKGROUND in the manifest; without it Health
  /// Connect just says no and syncing still happens when the app is open.
  static Future<void> _allowBackground() async {
    if (!Platform.isAndroid) return;
    try {
      if (await _health.isHealthDataInBackgroundAvailable() && !await _health.isHealthDataInBackgroundAuthorized()) {
        await _health.requestHealthDataInBackgroundAuthorization();
      }
    } catch (e) {
      debugPrint('device sync background: $e');
    }
  }

  static Future<void> _offerHealthConnect(BuildContext context, {required bool update, required bool phone}) async {
    final label = update ? 'Update Health Connect' : 'Install Health Connect';
    final go = await openSheet<bool>(
      context,
      (c) => MpSheet(
        title: label,
        subtitle: phone
            ? 'Your steps come from your phone. Watches and rings send their readings to MedPin through Health Connect — get it, then come back and tap Connect.'
            : 'Watches and rings send their readings to MedPin through Health Connect — get it, then come back and tap Connect.',
        child: VGap(
          gap: 8,
          children: [
            MpButton(label, onTap: () => Navigator.pop(c, true)),
            MpButton('Not now', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, false)),
          ],
        ),
      ),
    );
    if (go == true) await _health.installHealthConnect();
  }

  static bool _askedPhone = false;

  /// From Home: asks once for the phone's step sensor, then syncs quietly.
  static Future<bool> auto() async {
    if (!supported) return false;
    // From now on also when the app comes back to the front (same 30-min limit).
    if (_resume == null) WidgetsBinding.instance.addObserver(_resume = _ResumeSync());
    if (!_askedPhone && PhoneSteps.supported && !await PhoneSteps.allowed) {
      _askedPhone = true;
      await PhoneSteps.allow();
    }
    return sync(null);
  }

  /// Sends the last 7 days (at most every 30 minutes unless [force]). Quiet without [context].
  static Future<bool> sync(BuildContext? context, {bool force = false}) async {
    if (!supported) return false;
    // Home and a resume can start together: one run at a time; Connect waits for it.
    if (_running != null) {
      if (!force) return false;
      await _running;
      if (context != null && !context.mounted) return false;
    }
    if (!force && _lastRun != null && DateTime.now().difference(_lastRun!) < const Duration(minutes: 30)) return false;
    final run = _sync(context, force: force);
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
    }
  }

  static Future<bool> _sync(BuildContext? context, {required bool force}) async {
    try {
      await _configure();
      final granted = await _hcAvailable() ? await _granted() : const <HealthDataType>[];
      final has = granted.isNotEmpty;
      final phoneToday = await PhoneSteps.today();
      if (!has && phoneToday == null) return false;
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      final days = <Map<String, Object>>[];
      var stepSource = 'watch';
      if (granted.contains(HealthDataType.STEPS)) {
        try {
          for (var d = from; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
            final end = d.add(const Duration(days: 1));
            final n = await _health.getTotalStepsInInterval(d, end.isAfter(now) ? now : end);
            if (n != null && n > 0) days.add({'date': _key(d), 'steps': n, 'source': 'watch'});
          }
        } catch (e) {
          debugPrint('device sync steps: $e');
        }
      }
      // Today from the phone's own sensor when it counted more, or when there's
      // no Health Connect count for today (then it's sent even when lower, so an
      // earlier wrong total is corrected).
      if (phoneToday != null) {
        final i = days.indexWhere((d) => d['date'] == _key(now));
        final had = i < 0 ? 0 : days[i]['steps'] as int;
        if (phoneToday > had || i < 0) {
          if (i >= 0) days.removeAt(i);
          days.add({'date': _key(now), 'steps': phoneToday, 'source': 'phone'});
          stepSource = 'phone';
        }
      }
      // Every point (steps too): which app wrote what tells a watch / ring from
      // the phone. Each type on its own, so one that fails keeps the rest.
      final raw = <HealthDataPoint>[];
      for (final t in granted) {
        try {
          raw.addAll(await _health.getHealthDataFromTypes(types: [t], startTime: from, endTime: now));
        } catch (e) {
          debugPrint('device sync ${t.name}: $e');
        }
      }
      final all = _health.removeDuplicates(raw);
      final originKinds = <String, Set<String>>{};
      for (final p in all) {
        if (p.sourceName.isNotEmpty) (originKinds[p.sourceName] ??= {}).add(_kinds[p.type] ?? p.type.name);
      }
      final points = all.where((p) => p.type != HealthDataType.STEPS).toList();
      final readings = <Map<String, Object?>>[];
      num? val(HealthDataPoint p) => p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue : null;
      // Heart rate, SpO₂ and weight: the latest of each day is enough.
      for (final t in [HealthDataType.HEART_RATE, HealthDataType.BLOOD_OXYGEN, HealthDataType.WEIGHT]) {
        final latest = <String, HealthDataPoint>{};
        for (final p in points.where((p) => p.type == t)) {
          final k = _key(p.dateFrom);
          if (latest[k] == null || p.dateFrom.isAfter(latest[k]!.dateFrom)) latest[k] = p;
        }
        for (final p in latest.values) {
          var v = val(p);
          if (v == null) continue;
          if (t == HealthDataType.BLOOD_OXYGEN && v <= 1) v = v * 100; // 0.97 → 97 %
          // Weight keeps one decimal (72.4 kg); pulse and SpO₂ are whole numbers.
          final value = t == HealthDataType.WEIGHT ? (v * 10).round() / 10 : v.round();
          readings.add({'kind': _kinds[t], 'at': p.dateFrom.toUtc().toIso8601String(), 'value': value});
        }
      }
      // Blood pressure: systolic and diastolic recorded at the same moment.
      final dia = {for (final p in points.where((p) => p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC)) p.dateFrom.millisecondsSinceEpoch: val(p)};
      for (final p in points.where((p) => p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC)) {
        final d = dia[p.dateFrom.millisecondsSinceEpoch];
        if (val(p) != null && d != null) readings.add({'kind': 'bp', 'at': p.dateFrom.toUtc().toIso8601String(), 'value': val(p)!.round(), 'value2': d.round()});
      }
      for (final p in points.where((p) => p.type == HealthDataType.BLOOD_GLUCOSE)) {
        var v = val(p);
        if (v == null) continue;
        if (p.unit == HealthDataUnit.MILLIMOLES_PER_LITER) v = v * 18; // mmol/L → mg/dL
        readings.add({'kind': 'sugar', 'at': p.dateFrom.toUtc().toIso8601String(), 'value': v.round()});
      }
      final res = await Api.I.post('/api/patient/device-sync', {
        'source': has ? (Platform.isIOS ? 'Apple Health' : 'Health Connect') : 'Phone',
        'stepSource': stepSource,
        'origins': originKinds.keys.toList(),
        'originKinds': {for (final e in originKinds.entries) e.key: e.value.toList()},
        'days': days,
        'readings': readings,
      }) as Map;
      // Only a sync that really went up holds off the next one for 30 minutes.
      _lastRun = DateTime.now();
      if (context != null && context.mounted && force) {
        final r = res['readings'] as num? ?? 0;
        toast(context, phoneToday != null && !has ? 'Steps updated from your phone' : 'Synced ${res['days']} days of steps and $r new readings');
      }
      return true;
    } catch (e) {
      debugPrint('device sync: $e');
      if (context != null && context.mounted && force) toast(context, "Couldn't sync just now. Try again in a moment.");
      return false;
    }
  }

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Quiet re-sync when a signed-in patient brings the app back to the front
/// (DeviceSync.sync keeps the 30-minute limit).
class _ResumeSync with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Session.I.signedIn && Session.I.landing == 'Main') DeviceSync.sync(null);
  }
}

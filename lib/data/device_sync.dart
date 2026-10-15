import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../widgets/mp.dart';
import 'api.dart';
import 'config.dart';
import 'phone_steps.dart';

/// Watch / ring / phone readings through Health Connect (Android) or Apple
/// Health (iPhone): daily steps, heart rate, SpO₂, blood pressure, sugar and
/// weight from the last 7 days go to POST /api/patient/device-sync.
class DeviceSync {
  DeviceSync._();
  static final _health = Health();
  static bool _configured = false;
  static DateTime? _lastRun;

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.WEIGHT,
  ];

  static bool get supported => !AppMode.preview && (Platform.isAndroid || Platform.isIOS);

  static Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// First time: asks for access (installing Health Connect if needed), then syncs.
  static Future<bool> connect(BuildContext context) async {
    if (!supported) return false;
    try {
      // The phone counts steps itself: no watch needed.
      final phone = await PhoneSteps.allow();
      await _configure();
      if (Platform.isAndroid && await _health.getHealthConnectSdkStatus() != HealthConnectSdkStatus.sdkAvailable) {
        // No Health Connect: steps still come from the phone.
        if (phone && context.mounted) return sync(context, force: true);
        if (context.mounted) toast(context, 'Install Health Connect to sync your watch, then try again');
        await _health.installHealthConnect();
        return false;
      }
      final ok = await _health.requestAuthorization(_types, permissions: [for (final _ in _types) HealthDataAccess.READ]);
      if (!ok && !phone) {
        if (context.mounted) toast(context, 'Allow MedPin to read your health data to sync');
        return false;
      }
      if (!context.mounted) return false;
      return sync(context, force: true);
    } catch (e) {
      debugPrint('device sync: $e');
      if (context.mounted) toast(context, "Couldn't connect to your phone's health data");
      return false;
    }
  }

  static bool _askedPhone = false;

  /// From Home: asks once for the phone's step sensor, then syncs quietly.
  static Future<bool> auto() async {
    if (!supported) return false;
    if (!_askedPhone && PhoneSteps.supported && !await PhoneSteps.allowed) {
      _askedPhone = true;
      await PhoneSteps.allow();
    }
    return sync(null);
  }

  /// Sends the last 7 days (at most every 30 minutes unless [force]). Quiet without [context].
  static Future<bool> sync(BuildContext? context, {bool force = false}) async {
    if (!supported) return false;
    if (!force && _lastRun != null && DateTime.now().difference(_lastRun!) < const Duration(minutes: 30)) return false;
    _lastRun = DateTime.now();
    try {
      await _configure();
      final hc = Platform.isIOS || await _health.getHealthConnectSdkStatus() == HealthConnectSdkStatus.sdkAvailable;
      final has = hc && await _health.hasPermissions(_types, permissions: [for (final _ in _types) HealthDataAccess.READ]) == true;
      final phoneToday = await PhoneSteps.today();
      if (!has && phoneToday == null) return false;
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      final days = <Map<String, Object>>[];
      var stepSource = 'watch';
      if (has) {
        for (var d = from; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
          final end = d.add(const Duration(days: 1));
          final n = await _health.getTotalStepsInInterval(d, end.isAfter(now) ? now : end);
          if (n != null && n > 0) days.add({'date': _key(d), 'steps': n, 'source': 'watch'});
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
      // Every point (steps too): which app wrote it tells a watch / ring from the phone.
      final all = has ? _health.removeDuplicates(await _health.getHealthDataFromTypes(types: _types, startTime: from, endTime: now)) : <HealthDataPoint>[];
      final origins = {for (final p in all) if (p.sourceName.isNotEmpty) p.sourceName}.toList();
      final points = all.where((p) => p.type != HealthDataType.STEPS).toList();
      final readings = <Map<String, Object?>>[];
      num? val(HealthDataPoint p) => p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue : null;
      // Heart rate and SpO₂: the latest of each day is enough.
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
          readings.add({'kind': t == HealthDataType.HEART_RATE ? 'pulse' : t == HealthDataType.BLOOD_OXYGEN ? 'spo2' : 'weight', 'at': p.dateFrom.toUtc().toIso8601String(), 'value': v.round()});
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
        'origins': origins,
        'days': days,
        'readings': readings,
      }) as Map;
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

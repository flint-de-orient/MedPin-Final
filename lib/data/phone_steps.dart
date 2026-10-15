import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

/// Today's steps from the phone's own step sensor (no watch needed).
///
/// Android's sensor counts steps since the phone was switched on. MedPin
/// remembers the count the first time it sees it each day and after each
/// reading, so today's steps = the count now − the count at the start of the
/// day. If the phone restarts, the steps counted earlier today are kept.
/// Steps are counted all day by the phone; MedPin only needs to be opened.
class PhoneSteps {
  PhoneSteps._();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Asks for "Physical activity" once (shown by Android). True when allowed.
  static Future<bool> allow() async {
    if (!supported) return false;
    final s = await Permission.activityRecognition.request();
    return s.isGranted;
  }

  static Future<bool> get allowed async => supported && await Permission.activityRecognition.isGranted;

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}phone_steps.json');

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Today's steps, or null when the sensor isn't there or not allowed.
  static Future<int?> today() async {
    if (!await allowed) return null;
    int counter;
    try {
      final e = await Pedometer.stepCountStream.first.timeout(const Duration(seconds: 4));
      counter = e.steps;
    } catch (_) {
      return null; // no step sensor, or it didn't answer
    }
    final f = await _file();
    Map<String, dynamic> s = {};
    try {
      if (await f.exists()) s = (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {}
    final day = _key(DateTime.now());
    int base;
    int carry; // steps today from before a phone restart
    final last = (s['last'] as num?)?.toInt();
    final lastAt = DateTime.tryParse('${s['lastAt'] ?? ''}');
    // v2: older versions could start a day from yesterday's last reading (adding
    // yesterday's evening steps to today); their saved start is not trusted.
    if (s['date'] != day || s['v'] != 2) {
      // A new day starts at 0. The sensor only knows steps since the phone was
      // switched on, so steps since the last reading can't be split at midnight —
      // they count for today only if that reading was in the last minutes of
      // yesterday. (Steps before the first reading today come from Health Connect.)
      final midnight = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final closeToMidnight = lastAt != null && lastAt.isBefore(midnight) && midnight.difference(lastAt) <= const Duration(minutes: 20);
      base = (closeToMidnight && last != null && last <= counter) ? last : counter;
      carry = 0;
    } else {
      base = (s['base'] as num?)?.toInt() ?? counter;
      carry = (s['carry'] as num?)?.toInt() ?? 0;
      if (last != null && counter < last) {
        // The phone restarted: keep what was counted, start again from 0.
        carry += last - base;
        base = 0;
      }
    }
    final steps = (carry + counter - base).clamp(0, 200000);
    try {
      await f.writeAsString(jsonEncode({'v': 2, 'date': day, 'base': base, 'carry': carry, 'last': counter, 'lastAt': DateTime.now().toIso8601String()}));
    } catch (_) {}
    return steps;
  }
}

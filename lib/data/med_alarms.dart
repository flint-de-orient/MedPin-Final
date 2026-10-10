import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'config.dart';
import 'local_notes.dart';
import 'session.dart';

/// Medicine alarms rung by the phone itself (work offline, survive reboots):
/// one alarm per dose for today and tomorrow, from GET /api/patient/doses.
/// Re-synced when the patient signs in, opens the app, marks a dose, or
/// changes medicines / reminder times. Switching "Medicine reminders" off in
/// Profile removes them.
class MedAlarms with WidgetsBindingObserver {
  MedAlarms._();
  static final MedAlarms I = MedAlarms._();

  /// Alarm ids live in their own range so other notifications are never touched.
  static const _base = 700000000;
  static const _span = 100000000;
  static int idFor(String doseId) => _base + (doseId.hashCode & 0x7fffffff) % _span;
  static bool _isAlarm(int id) => id >= _base && id < _base + _span;

  bool _observing = false;
  Timer? _debounce;

  bool get _isPatient => !AppMode.preview && Session.I.signedIn && Session.I.landing == 'Main';

  /// Starts watching app resumes; call after a patient signs in.
  void start() {
    if (!_isPatient) return;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    // Alarms at the exact dose time need permission on Android 12+.
    LocalNotes.I.requestPermission(exactAlarms: true);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  /// Re-schedules soon (several changes in a row cause one sync).
  void sync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _sync);
  }

  Future<void> _sync() async {
    if (!LocalNotes.I.supported) return;
    if (!_isPatient) return clear();
    try {
      final me = await Api.I.get('/api/patient/me') as Map;
      final on = (me['settings'] as Map?)?['medReminders'] != false;
      if (!on) return clear();
      final now = DateTime.now();
      final days = [now, now.add(const Duration(days: 1))];
      final wanted = <int, (DateTime, String, String)>{};
      for (final d in days) {
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final r = await Api.I.get('/api/patient/doses', query: {'date': key}) as Map;
        for (final dose in (r['items'] as List? ?? const [])) {
          final m = (dose as Map).cast<String, dynamic>();
          if (m['status'] != 'due') continue;
          final at = DateTime.tryParse('${m['at']}')?.toLocal();
          if (at == null || at.isBefore(now)) continue;
          final med = (m['medicine'] as Map?)?.cast<String, dynamic>() ?? const {};
          final name = [med['name'], med['strength']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
          final food = const {'before_food': 'before food', 'after_food': 'after food', 'with_food': 'with food', 'empty_stomach': 'on an empty stomach'}[med['foodRelation']];
          final slot = const {'morning': 'Morning', 'afternoon': 'Afternoon', 'night': 'Night'}[m['slot']];
          wanted[idFor('${m['id']}')] = (at, 'Time for ${name.isEmpty ? 'your medicine' : name}', [if (slot != null) '$slot dose', if (food != null) food].join(' · '));
        }
      }
      final existing = (await LocalNotes.I.scheduledIds()).where(_isAlarm).toSet();
      for (final id in existing.difference(wanted.keys.toSet())) {
        await LocalNotes.I.cancel(id);
      }
      for (final e in wanted.entries) {
        await LocalNotes.I.schedule(id: e.key, at: e.value.$1, title: e.value.$2, body: e.value.$3, payload: const {'screen': 'Patient-Medicines'});
      }
    } on ApiException {
      // Offline: the alarms already scheduled keep ringing.
    } catch (e) {
      debugPrint('Medicine alarms not synced: $e');
    }
  }

  /// Removes every medicine alarm (sign-out, reminders switched off).
  Future<void> clear() async {
    if (!LocalNotes.I.supported) return;
    for (final id in (await LocalNotes.I.scheduledIds()).where(_isAlarm)) {
      await LocalNotes.I.cancel(id);
    }
  }
}

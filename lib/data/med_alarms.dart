import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'config.dart';
import 'live.dart';
import 'local_notes.dart';
import 'push.dart';
import 'session.dart';
import '../widgets/i18n.dart';

/// Reminders rung by the phone itself (work offline, survive reboots), for
/// the next 7 days:
/// - medicine alarms: one per dose time (medicines due together share it),
///   plus "Still to take" 30 min later while any is not marked; they ring
///   like an alarm, even on silent, unless Profile → "Ring even on silent" is off;
/// - visit reminders: a day before and 2 hours before (as the server does);
/// - the daily-log reminder at its time (not today once something is logged).
///
/// Re-synced when the patient signs in, opens the app, changes anything in it
/// (a dose marked, a log, a setting — LiveBus), and when the server says
/// medicines or visits changed (silent push "reminders_changed"). Then the
/// server is told what this phone covers, so it pushes only the rest
/// (a dose changed after this sync, or beyond these 7 days).
class MedAlarms with WidgetsBindingObserver {
  MedAlarms._();
  static final MedAlarms I = MedAlarms._();

  /// Alarm ids live in their own range so other notifications are never touched.
  static const _base = 700000000;
  static const _span = 100000000;
  static int idFor(String key) => _base + (key.hashCode & 0x7fffffff) % _span;
  static bool _isAlarm(int id) => id >= _base && id < _base + _span;

  bool _observing = false;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  bool get _isPatient => !AppMode.preview && Session.I.signedIn && Session.I.landing == 'Main';

  /// Starts watching app resumes and changes; call after a patient signs in.
  void start() {
    if (!_isPatient) return;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      LiveBus.changes.addListener(_onChange);
    }
    // Alarms at the exact dose time need permission on Android 12+.
    // Then the server knows whether this phone rings them (or it should push them).
    LocalNotes.I.requestPermission(exactAlarms: true).then((_) => Push.I.refresh()).catchError((_) {});
    LocalNotes.I.onTaken = _taken;
    sync();
  }

  /// "Taken" on a medicine alarm: every dose it was for is marked taken.
  Future<void> _taken(Map<String, dynamic> payload) async {
    final ids = [for (final id in (payload['doseIds'] as List? ?? const [])) '$id'].where((s) => s.isNotEmpty);
    var n = 0;
    for (final id in ids) {
      try {
        // For whoever the alarm was for (a family member's dose too); '' = the account's own.
        await Api.I.post('/api/patient/doses/$id', const {'status': 'taken'}, '${payload['forPatientId'] ?? ''}');
        n++;
      } on ApiException catch (_) {}
    }
    if (n > 0) LiveBus.changed();
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  /// Something changed in the app (a dose marked, a log, a setting): re-sync,
  /// but at most every 20 s (a chat or a busy screen changes things often).
  void _onChange() {
    final wait = const Duration(seconds: 20) - DateTime.now().difference(_lastRun);
    _debounce?.cancel();
    _debounce = Timer(wait.isNegative ? const Duration(seconds: 2) : wait, _run);
  }

  /// Re-schedules soon (several changes in a row cause one sync).
  void sync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _run);
  }

  Future<void> _run() async {
    // One at a time; a change during a sync runs it once more after.
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _lastRun = DateTime.now();
    try {
      await _sync();
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        sync();
      }
    }
  }

  /// Alarm text in the patient's app language (the alarm rings with no screen open).
  static String _t(String s) => I18n.tr(s, '${Session.I.user['language'] ?? 'en'}');

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _sync() async {
    if (!LocalNotes.I.supported) return;
    if (!_isPatient) return clear();
    try {
      final me = (await Api.I.get('/api/patient/me') as Map).cast<String, dynamic>();
      final rem = (me['reminders'] as Map?)?.cast<String, dynamic>() ?? const {};
      final settings = (me['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
      final medsOn = rem['medicines'] ?? settings['medReminders'] != false;
      final visitsOn = rem['visits'] ?? settings['visitReminders'] != false;
      final logOn = rem['dailyLog'] == true;
      final logAt = '${rem['dailyLogAt'] ?? settings['dailyLogReminderAt'] ?? '20:00'}';
      final ring = rem['ring'] ?? settings['alarmRing'] != false;
      // Snooze on the alarm: the patient's choice (Profile), 10 min unless set.
      final snooze = ((rem['snoozeMin'] ?? settings['snoozeMin']) as num?)?.toInt() ?? 10;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
      final until = today.add(const Duration(days: 7));
      final wanted = <int, ({DateTime at, String title, String body, Map<String, dynamic> payload, String kind})>{};
      final dueIds = <String>{}; // doses still to take (a snooze for anything else is cancelled)

      // Everyone on this phone: the account's own profile and each family member (a child's
      // and a parent's medicines ring here too, named so it's clear whose they are).
      final profiles = <({String? id, String name, bool me})>[(id: null, name: '', me: true)];
      try {
        final fam = await Api.I.get('/api/patient/family', asPatient: '') as Map;
        for (final p in (fam['items'] as List? ?? const [])) {
          final m = (p as Map).cast<String, dynamic>();
          if (m['me'] == true) continue;
          profiles.add((id: '${m['id']}', name: '${m['name'] ?? ''}', me: false));
        }
      } on ApiException catch (_) {}
      String whose(({String? id, String name, bool me}) p, String title) => p.me || p.name.isEmpty ? title : '${p.name}: $title';

      for (final who in profiles) {
        // The call is for this person (the account's own: no family header at all).
        final as = who.id ?? '';
        final tag = who.id ?? '';

        // ── Medicines ──
        if (medsOn == true) {
          // Medicines due at the same minute ring as one alarm listing them; a second,
          // gentler one 30 min later only while any of them is still not marked taken
          // (marking a dose re-syncs, so it disappears as soon as they're taken).
          final groups = <DateTime, List<Map<String, dynamic>>>{};
          for (final d in days) {
            final r = await Api.I.get('/api/patient/doses', query: {'date': _day(d)}, asPatient: as) as Map;
            for (final dose in (r['items'] as List? ?? const [])) {
              final m = (dose as Map).cast<String, dynamic>();
              if (m['status'] != 'due') continue;
              dueIds.add('${m['id'] ?? m['_id']}');
              final at = DateTime.tryParse('${m['at']}')?.toLocal();
              if (at == null || at.add(const Duration(minutes: 30)).isBefore(now)) continue;
              groups.putIfAbsent(DateTime(at.year, at.month, at.day, at.hour, at.minute), () => []).add(m);
            }
          }
          for (final g in groups.entries) {
            final names = [
              for (final m in g.value)
                [(m['medicine'] as Map?)?['name'], (m['medicine'] as Map?)?['strength']].where((x) => x != null && '$x'.isNotEmpty).join(' '),
            ].where((s) => s.isNotEmpty).toList();
            final how = {for (final m in g.value) _how(m)}.whereType<String>().map(_t).join(' / ');
            final title = names.length <= 1 ? '${_t('Time for')} ${names.isEmpty ? _t('your medicine') : names.first}' : _t('Time for ${names.length} medicines');
            final body = [if (names.length > 1) names.join(', '), if (how.isNotEmpty) how].join(' · ');
            final stamp = g.key.millisecondsSinceEpoch;
            // Taken marks these doses; Snooze rings again after the patient's snooze time.
            final payload = {'screen': 'Patient-Medicines', 'snooze': snooze, if (who.id != null) 'forPatientId': who.id, 'doseIds': [for (final m in g.value) '${m['id'] ?? m['_id']}']};
            if (g.key.isAfter(now)) wanted[idFor('t$tag$stamp')] = (at: g.key, title: whose(who, title), body: body, payload: payload, kind: ring == true ? 'ring' : 'dose');
            final again = g.key.add(const Duration(minutes: 30));
            if (again.isAfter(now)) {
              wanted[idFor('f$tag$stamp')] = (
                at: again,
                title: whose(who, names.length <= 1 ? '${_t('Still to take:')} ${names.isEmpty ? _t('your medicine') : names.first}' : _t('Still to take: ${names.length} medicines')),
                body: '${_t('Tap to mark them taken')}${body.isEmpty ? '' : ' · $body'}',
                payload: payload,
                kind: 'dose', // the follow-up is gentler: an ordinary alarm notification
              );
            }
          }
        }

        // ── Visits: a day before and 2 hours before ──
        if (visitsOn == true) {
          final r = await Api.I.get('/api/patient/appointments', asPatient: as) as Map;
          for (final a in (r['items'] as List? ?? const [])) {
            final v = (a as Map).cast<String, dynamic>();
            if (!const {'booked', 'confirmed'}.contains(v['status'])) continue;
            final start = DateTime.tryParse('${v['startAt']}')?.toLocal();
            final made = DateTime.tryParse('${v['createdAt']}')?.toLocal();
            if (start == null || !start.isBefore(until)) continue;
            final doctor = (v['doctorId'] is Map) ? '${(v['doctorId'] as Map)['name'] ?? ''}' : '';
            final place = (v['locationId'] is Map) ? '${(v['locationId'] as Map)['shortName'] ?? (v['locationId'] as Map)['name'] ?? ''}' : '';
            final body = [
              '${_clock(start)}${doctor.isEmpty ? '' : ' · $doctor'}',
              if (place.isNotEmpty) place,
              if (v['token'] != null) '${_t('Token')} ${v['token']}',
            ].join(' · ');
            final payload = {
              'screen': 'Patient-DoctorDetail',
              if (who.id != null) 'forPatientId': who.id,
              if (v['doctorId'] is Map) 'doctorId': '${(v['doctorId'] as Map)['_id'] ?? (v['doctorId'] as Map)['id']}',
            };
            // Booked only shortly before: the confirmation was enough (the server's rule too).
            final dayBefore = start.subtract(const Duration(hours: 24));
            if (dayBefore.isAfter(now) && (made == null || start.difference(made).inHours >= 12)) {
              wanted[idFor('v24${v['id'] ?? v['_id']}')] = (at: dayBefore, title: whose(who, _t('Your visit is tomorrow')), body: body, payload: payload, kind: 'reminder');
            }
            final twoBefore = start.subtract(const Duration(hours: 2));
            if (twoBefore.isAfter(now) && (made == null || start.difference(made).inHours >= 2)) {
              wanted[idFor('v2${v['id'] ?? v['_id']}')] = (at: twoBefore, title: whose(who, _t('Your visit is in about 2 hours')), body: body, payload: payload, kind: 'reminder');
            }
          }
        }
      }

      // ── Daily log ──
      if (logOn) {
        final hm = logAt.split(':');
        final h = int.tryParse(hm.first) ?? 20;
        final mi = int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0;
        // Not today once something is logged today.
        var loggedToday = false;
        try {
          final hist = await Api.I.get('/api/patient/logs/history', query: {'days': '1'}) as Map;
          final d0 = ((hist['days'] as List?)?.firstOrNull as Map?)?.cast<String, dynamic>() ?? const {};
          loggedToday = (d0['meals'] as List? ?? const []).isNotEmpty ||
              ((d0['exercise'] as Map?)?['items'] as List? ?? const []).isNotEmpty ||
              ((d0['steps'] as Map?)?['total'] as num? ?? 0) > 0;
        } on ApiException catch (_) {}
        for (final d in days) {
          final at = DateTime(d.year, d.month, d.day, h, mi);
          if (!at.isAfter(now) || (loggedToday && at.day == now.day && at.month == now.month)) continue;
          wanted[idFor('log${_day(d)}')] = (
            at: at,
            title: _t("Log today's meals"),
            body: _t('A quick photo or a line is enough.'),
            payload: const {'screen': 'Patient-Log'},
            kind: 'reminder',
          );
        }
      }

      final existing = (await LocalNotes.I.scheduledIds()).where(_isAlarm).toSet();
      for (final id in existing.difference(wanted.keys.toSet())) {
        await LocalNotes.I.cancel(id);
      }
      // A snoozed alarm whose doses were marked (or whose medicine stopped) doesn't ring again.
      for (final s in await LocalNotes.I.snoozes()) {
        if (medsOn != true || !s.doseIds.any(dueIds.contains)) await LocalNotes.I.cancel(s.id);
      }
      for (final e in wanted.entries) {
        await LocalNotes.I.schedule(id: e.key, at: e.value.at, title: e.value.title, body: e.value.body, payload: e.value.payload, kind: e.value.kind);
      }
      // The server pushes only what this phone doesn't ring itself.
      await Push.I.reportReminders(until: until, dailyLogAt: logOn ? logAt : null);
    } on ApiException {
      // Offline: the alarms already scheduled keep ringing.
    } catch (e) {
      debugPrint('Reminders not synced: $e');
    }
  }

  /// "after breakfast", "before dinner", "on an empty stomach", "at bedtime".
  static String? _how(Map<String, dynamic> dose) {
    final meal = const {'morning': 'breakfast', 'afternoon': 'lunch', 'night': 'dinner'}[dose['slot']] ?? 'food';
    return switch ((dose['medicine'] as Map?)?['foodRelation']) {
      'before_food' => 'before $meal',
      'after_food' => 'after $meal',
      'with_food' => 'with $meal',
      'empty_stomach' => 'on an empty stomach',
      'bedtime' => 'at bedtime',
      _ => null,
    };
  }

  /// Removes every reminder this phone scheduled (sign-out).
  Future<void> clear() async {
    if (!LocalNotes.I.supported) return;
    await LocalNotes.I.init(); // also at launch, before anything else set it up
    for (final id in (await LocalNotes.I.scheduledIds()).where((id) => _isAlarm(id) || LocalNotes.isSnooze(id))) {
      await LocalNotes.I.cancel(id);
    }
  }
}

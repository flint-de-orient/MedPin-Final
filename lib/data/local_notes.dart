import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Buttons on a medicine alarm, pressed while MedPin isn't running: Snooze
/// rings it again after the patient's snooze time; Stop just dismisses it.
/// (Taken opens the app, which marks the doses — see LocalNotes.onAction.)
@pragma('vm:entry-point')
Future<void> localNotesBackground(NotificationResponse r) async {
  if (r.actionId != 'snooze') return;
  await LocalNotes.I.snooze(r.payload);
}

/// On-device notifications: push messages shown while the app is open, and
/// alarms scheduled on the phone (medicine doses) that ring even offline.
/// Tapping one opens the screen in its payload ({screen, params}).
class LocalNotes {
  LocalNotes._();
  static final LocalNotes I = LocalNotes._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called with {screen, params} when a notification is tapped.
  void Function(Map<String, dynamic> payload)? onTap;

  /// A medicine alarm's "Taken" button ({doseIds, …}): the app marks the doses taken.
  void Function(Map<String, dynamic> payload)? onTaken;

  static const general = AndroidNotificationChannel('medpin_general', 'Updates', description: 'Visits, messages, reports and reminders', importance: Importance.high);
  static const urgent = AndroidNotificationChannel('medpin_urgent', 'Urgent', description: 'Emergency alerts and urgent messages', importance: Importance.max);
  static const doses = AndroidNotificationChannel('medpin_doses', 'Medicine alarms', description: 'Time to take your medicine', importance: Importance.max);

  /// Medicine alarms that ring like an alarm clock: the alarm sound at alarm
  /// volume (so a phone on silent still rings), over the lock screen.
  /// Profile → "Ring even on silent" (on by default) picks this one.
  static final dosesRing = AndroidNotificationChannel(
    'medpin_doses_ring',
    'Medicine alarms (ring)',
    description: 'Rings for your medicine even when the phone is on silent',
    importance: Importance.max,
    bypassDnd: true,
    sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (_ready || !supported) return;
    _ready = true;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: _response,
      onDidReceiveBackgroundNotificationResponse: localNotesBackground,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in [general, urgent, doses, dosesRing]) {
      await android?.createNotificationChannel(c);
    }
    // Opened by tapping a notification while the app was closed.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch!.notificationResponse != null) _response(launch.notificationResponse!);
  }

  void _response(NotificationResponse r) {
    switch (r.actionId) {
      case 'snooze':
        snooze(r.payload);
      case 'stop':
        break; // dismissed (the 30-min "still to take" reminder stays while not marked)
      case 'taken':
        try {
          final p = (jsonDecode(r.payload ?? '{}') as Map).cast<String, dynamic>();
          onTaken?.call(p);
        } catch (_) {}
      default:
        _handle(r.payload);
    }
  }

  /// Rings a medicine alarm again after its snooze time (payload carries it all).
  Future<void> snooze(String? payload) async {
    try {
      final p = (jsonDecode(payload ?? '{}') as Map).cast<String, dynamic>();
      final mins = (p['snooze'] as num?)?.toInt() ?? 10;
      await schedule(
        // Its own id range (900M+): re-syncing the scheduled alarms (700M–800M) never cancels a snooze.
        id: 900000000 + (((p['alarmId'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch) % 100000000),
        at: DateTime.now().add(Duration(minutes: mins.clamp(1, 120))),
        title: '${p['title'] ?? 'Time for your medicine'}',
        body: p['body'] as String?,
        payload: p,
        kind: '${p['kind'] ?? 'dose'}',
      );
    } catch (_) {}
  }

  void _handle(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      onTap?.call((jsonDecode(payload) as Map).cast<String, dynamic>());
    } catch (_) {}
  }

  /// Asks for permission to show notifications (Android 13+, iOS) and, on
  /// Android 12+, to ring alarms at the exact dose time.
  Future<bool> requestPermission({bool exactAlarms = false}) async {
    if (!supported) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final ok = await android.requestNotificationsPermission() ?? true;
      if (exactAlarms && !(await android.canScheduleExactNotifications() ?? true)) await android.requestExactAlarmsPermission();
      return ok;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  /// Whether notifications can be shown now (the patient didn't turn them off).
  Future<bool> allowed() async {
    if (!supported) return false;
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.areNotificationsEnabled() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final s = await ios?.checkPermissions();
      return s?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Medicine alarms stay in the notification bar until the patient answers:
  /// Taken (opens MedPin, marks them), Snooze (rings again after their snooze
  /// time), Stop (dismisses).
  static List<AndroidNotificationAction> _doseActions(int snoozeMin) => [
        const AndroidNotificationAction('taken', 'Taken', showsUserInterface: true),
        AndroidNotificationAction('snooze', 'Snooze $snoozeMin min'),
        const AndroidNotificationAction('stop', 'Stop'),
      ];

  NotificationDetails _details(AndroidNotificationChannel c, {int? snoozeMin}) => NotificationDetails(
        android: c.id == dosesRing.id
            ? AndroidNotificationDetails(
                c.id,
                c.name,
                channelDescription: c.description,
                importance: Importance.max,
                priority: Priority.max,
                category: AndroidNotificationCategory.alarm,
                fullScreenIntent: true,
                audioAttributesUsage: AudioAttributesUsage.alarm,
                sound: c.sound,
                ongoing: true,
                autoCancel: false,
                visibility: NotificationVisibility.public,
                actions: _doseActions(snoozeMin ?? 10),
              )
            : c.id == doses.id
                ? AndroidNotificationDetails(
                    c.id,
                    c.name,
                    channelDescription: c.description,
                    importance: c.importance,
                    priority: Priority.max,
                    category: AndroidNotificationCategory.reminder,
                    visibility: NotificationVisibility.public,
                    actions: _doseActions(snoozeMin ?? 10),
                  )
                : AndroidNotificationDetails(c.id, c.name, channelDescription: c.description, importance: c.importance, priority: c.importance == Importance.max ? Priority.max : Priority.high),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );

  /// Shows a notification now (e.g. a push message while the app is open).
  Future<void> show({required String title, String? body, Map<String, dynamic>? payload, bool isUrgent = false}) async {
    if (!supported) return;
    await init();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      notificationDetails: _details(isUrgent ? urgent : general),
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  /// Rings at [at] (phone time), even if the app is closed or offline.
  /// [kind]: 'dose' (medicine alarm), 'ring' (medicine alarm that rings even on
  /// silent), or 'reminder' (visit, daily log — an ordinary notification).
  Future<void> schedule({required int id, required DateTime at, required String title, String? body, Map<String, dynamic>? payload, String kind = 'dose'}) async {
    if (!supported) return;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details(switch (kind) { 'ring' => dosesRing, 'reminder' => general, _ => doses }, snoozeMin: (payload?['snooze'] as num?)?.toInt()),
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      // Medicine alarms carry what Snooze / Taken need (title, body, kind, snooze time, doses).
      payload: jsonEncode({...?payload, if (kind != 'reminder') ...{'alarmId': id, 'title': title, 'body': body, 'kind': kind}}),
    );
  }

  Future<void> cancel(int id) async {
    if (supported) await _plugin.cancel(id: id);
  }

  /// Ids of the alarms scheduled now.
  Future<Set<int>> scheduledIds() async {
    if (!supported) return {};
    return {for (final p in await _plugin.pendingNotificationRequests()) p.id};
  }

  /// Snoozed medicine alarms live in their own id range (see [snooze]).
  static bool isSnooze(int id) => id >= 900000000 && id < 1000000000;

  /// Scheduled snoozes with the doses they ring for.
  Future<List<({int id, List<String> doseIds})>> snoozes() async {
    if (!supported) return const [];
    final out = <({int id, List<String> doseIds})>[];
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (!isSnooze(p.id)) continue;
      var ids = const <String>[];
      try {
        final m = (jsonDecode(p.payload ?? '{}') as Map).cast<String, dynamic>();
        ids = [for (final x in (m['doseIds'] as List? ?? const [])) '$x'];
      } catch (_) {}
      out.add((id: p.id, doseIds: ids));
    }
    return out;
  }
}

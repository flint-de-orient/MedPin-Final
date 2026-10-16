import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
      onDidReceiveNotificationResponse: (r) => _handle(r.payload),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in [general, urgent, doses, dosesRing]) {
      await android?.createNotificationChannel(c);
    }
    // Opened by tapping a notification while the app was closed.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) _handle(launch!.notificationResponse?.payload);
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

  NotificationDetails _details(AndroidNotificationChannel c) => NotificationDetails(
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
      notificationDetails: _details(switch (kind) { 'ring' => dosesRing, 'reminder' => general, _ => doses }),
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: payload == null ? null : jsonEncode(payload),
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
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/nav.dart';
import 'api.dart';
import 'nav_counts.dart';
import 'config.dart';
import 'live.dart';
import 'local_notes.dart';
import 'session.dart';

/// Push notifications (Firebase Cloud Messaging): registers this phone with
/// the backend after sign-in (POST /api/me/devices), shows messages that
/// arrive while the app is open, and opens the right screen when one is
/// tapped. The backend sends only to the people who should get each
/// notification (e.g. emergencies to the patient's doctors).
class Push {
  Push._();
  static final Push I = Push._();

  String? token;
  bool _listening = false;
  Map<String, dynamic>? _pendingTap;

  bool get _supported => !kIsWeb && !AppMode.preview && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// After sign-in (or a restored session): permission, token, listeners.
  Future<void> start() async {
    if (!_supported || !Session.I.signedIn) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await LocalNotes.I.init();
      LocalNotes.I.onTap = open;
      await LocalNotes.I.requestPermission();
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessage.listen(_foreground);
        FirebaseMessaging.onMessageOpenedApp.listen((msg) => open(msg.data));
        m.onTokenRefresh.listen(_register);
        final initial = await m.getInitialMessage();
        if (initial != null) open(initial.data);
      }
      final t = await m.getToken();
      if (t != null) await _register(t);
    } catch (e) {
      debugPrint('Push not available: $e');
    }
  }

  /// Tells the server again (e.g. notifications were just allowed, so the phone rings dose alarms itself).
  Future<void> refresh() async {
    final t = token;
    if (t != null) await _register(t);
  }

  Future<void> _register(String t) async {
    token = t;
    if (!Session.I.signedIn) return;
    try {
      await Api.I.post('/api/me/devices', {
        'token': t,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        // Patients' medicine alarms ring on the phone itself (MedAlarms), so the server doesn't push them.
        // Only when notifications are allowed; otherwise the server keeps pushing them.
        'localAlarms': Session.I.landing == 'Main' && await LocalNotes.I.allowed(),
      });
    } on ApiException catch (e) {
      debugPrint('Device not registered: ${e.message}');
    }
  }

  void _foreground(RemoteMessage msg) {
    NavCounts.refresh(force: true); // a new chat or alert changes the tab-bar badges
    LiveBus.changed(); // and whatever screen is open may now be out of date
    final n = msg.notification;
    if (n == null) return;
    final type = msg.data['type']?.toString() ?? '';
    LocalNotes.I.show(title: n.title ?? 'MedPin', body: n.body, payload: msg.data, isUrgent: type.contains('urgent') || type.contains('emergency'));
  }

  /// Opens the screen a notification points to ({screen, ...params}).
  void open(Map<String, dynamic> data) {
    final screen = data['screen']?.toString() ?? '';
    final ctx = Nav.key.currentContext;
    if (screen.isEmpty) return;
    if (ctx == null || !Session.I.signedIn) {
      _pendingTap = data; // shown after sign-in / launch
      return;
    }
    final spec = Nav.spec(screen);
    if (spec == null) return;
    // Patients open patient-app screens only, staff only staff screens.
    final isPatient = Session.I.landing == 'Main';
    if (isPatient != (spec.panel == 'patient')) return;
    final args = {for (final e in data.entries) if (!const {'screen', 'type', 'notificationId'}.contains(e.key)) e.key: e.value};
    Nav.go(ctx, screen, args: args.isEmpty ? null : args);
  }

  /// Called once the first screen after sign-in is showing.
  void flushPending() {
    final p = _pendingTap;
    _pendingTap = null;
    if (p != null) scheduleMicrotask(() => open(p));
  }

  /// On sign-out: the backend forgets this phone (sent with /api/auth/logout).
  Future<void> forget() async {
    if (!_supported) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    token = null;
  }
}

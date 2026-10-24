import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show DartPluginRegistrant, IsolateNameServer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/nav.dart';
import 'api.dart';
import 'nav_counts.dart';
import 'notify_route.dart';
import 'config.dart';
import 'device_sync.dart';
import 'live.dart';
import 'local_notes.dart';
import 'med_alarms.dart';
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

  /// The chat on screen now (its conversation id): its new messages show in
  /// the chat itself, so no notification pops up for them.
  String? openChat;
  Map<String, dynamic>? _pendingTap;

  /// True once the first screen after launch / sign-in is showing ([flushPending]). Before
  /// that a tap waits: opened earlier, the launch would replace its screen with Home.
  bool _ready = false;
  DateTime? _startedAt;

  /// Ready, or running for a few seconds already (a sign-in path that never flushed).
  bool get _launched => _ready || (_startedAt != null && DateTime.now().difference(_startedAt!) > const Duration(seconds: 5));

  bool get _supported => !kIsWeb && !AppMode.preview && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Phones only (Firebase Messaging has no background handler elsewhere).
  static bool get backgroundSupported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// In the app itself (main isolate): silent pushes that arrive while it is in
  /// the background hand their work here ([pushBackground]), so it runs with
  /// the app's own session — a second copy refreshing the sign-in token
  /// would leave the app holding a spent one.
  void listenForBackgroundWork() {
    if (!backgroundSupported) return;
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_appPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, _appPortName);
    port.listen((msg) async {
      if (msg is! List || msg.length != 2 || msg[1] is! SendPort) return;
      final reply = msg[1] as SendPort;
      reply.send('got');
      try {
        await _backgroundWork('${msg[0]}');
      } catch (e) {
        debugPrint('Background push: $e');
      }
      reply.send('done');
    });
  }

  /// After sign-in (or a restored session): permission, token, listeners.
  Future<void> start() async {
    if (!_supported || !Session.I.signedIn) return;
    _startedAt ??= DateTime.now();
    // A sign-in path that never calls flushPending: a waiting tap still opens.
    Future.delayed(const Duration(seconds: 6), () {
      if (!_ready && _pendingTap != null && Session.I.signedIn) flushPending();
    });
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

  /// What this phone scheduled itself (MedAlarms): doses and visits up to [until],
  /// the daily-log reminder at [dailyLogAt]. The server then pushes only the rest.
  Future<void> reportReminders({required DateTime until, String? dailyLogAt}) async {
    final t = token;
    if (t == null || !Session.I.signedIn) return;
    try {
      await Api.I.post('/api/me/devices/reminders', {'token': t, 'until': until.toUtc().toIso8601String(), 'dailyLogAt': dailyLogAt});
    } on ApiException catch (_) {}
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
    // Medicines or visits changed (a new prescription, a visit booked): re-schedule the phone's alarms.
    if (msg.data['type'] == 'reminders_changed') MedAlarms.I.sync();
    // Signed out from another device: this phone's alarms go at once (the next call signs it out).
    if (msg.data['type'] == 'signed_out') MedAlarms.I.clear();
    // My role / locations / access changed (Profile → People): menus and permissions follow at once.
    if (msg.data['type'] == 'membership_changed' || msg.data['type'] == 'member_access_changed') Session.I.reloadAccount().catchError((_) {});
    // The server's periodic nudge: send the watch / phone readings now.
    if (msg.data['type'] == 'device_sync' && Session.I.landing == 'Main') DeviceSync.sync(null);
    final n = msg.notification;
    if (n == null) return; // a silent "chat changed": the refresh above is all it needs
    final type = msg.data['type']?.toString() ?? '';
    if (openChat != null && msg.data['conversationId']?.toString() == openChat) return;
    LocalNotes.I.show(title: n.title ?? 'MedPin', body: n.body, payload: msg.data, isUrgent: type.contains('urgent') || type.contains('emergency'));
  }

  /// Opens the screen a notification points to ({screen, ...params}).
  void open(Map<String, dynamic> data) {
    final screen = data['screen']?.toString() ?? '';
    final ctx = Nav.key.currentContext;
    if (screen.isEmpty) return;
    if (ctx == null || !Session.I.signedIn || !_launched) {
      _pendingTap = data; // shown after sign-in / launch
      return;
    }
    // Tapped: that notice is read in the bell too (the push names its type and what it's about).
    final type = data['type']?.toString() ?? '';
    if (type.isNotEmpty) {
      Api.I.post('/api/notifications/opened', {
        'type': type,
        for (final k in const ['conversationId', 'appointmentId', 'alertId', 'patientId', 'reviewId', 'orderId', 'paymentId'])
          if (data[k] != null) k: '${data[k]}',
      }).then((_) => NavCounts.refresh(force: true)).catchError((_) {});
    }
    final spec = Nav.spec(screen);
    if (spec == null) return;
    // That chat is already on screen: refresh it instead of opening a second copy.
    final conv = data['conversationId']?.toString();
    if (conv != null && conv == openChat && (screen == 'Patient-DoctorChat' || screen == 'Patient-Thread')) {
      LiveBus.changed();
      return;
    }
    // Patients open patient-app screens only, staff only staff screens.
    final isPatient = Session.I.landing == 'Main';
    if (isPatient != (spec.panel == 'patient')) return;
    final args = {for (final e in data.entries) if (!const {'screen', 'type', 'notificationId', 'practiceId', 'forPatientId', 'forName'}.contains(e.key)) e.key: e.value};
    if (isPatient) {
      // About a family member: their profile opens first (their visit, their medicines).
      // About the account holder while a family profile is open: back to their own profile.
      final forId = data['forPatientId']?.toString();
      final target = forId != null && forId.isNotEmpty ? forId : null;
      if (target != Session.I.familyPatientId) {
        Session.I.selectFamily(target, name: data['forName']?.toString()).then((_) {
          final c = Nav.key.currentContext;
          if (c != null && c.mounted) Nav.go(c, screen, args: args.isEmpty ? null : args);
        });
        return;
      }
      Nav.go(ctx, screen, args: args.isEmpty ? null : args);
      return;
    }
    // Staff: to that clinic first (staff in two practices), then a screen this role can open.
    openStaffNotification(ctx, screen: screen, type: data['type']?.toString() ?? '', params: args, practiceId: data['practiceId']?.toString());
  }

  /// Called once the first screen after sign-in is showing.
  void flushPending() {
    _ready = true;
    final p = _pendingTap;
    _pendingTap = null;
    if (p != null) scheduleMicrotask(() => open(p));
  }

  /// Before sign-out: this phone's token, so /api/auth/logout can name it (the
  /// server also drops every phone of the ended session on its own).
  Future<void> ensureToken() async {
    if (token != null || !_supported) return;
    try {
      if (Firebase.apps.isEmpty) return;
      token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {}
  }

  /// On sign-out: the backend forgets this phone (sent with /api/auth/logout).
  Future<void> forget() async {
    _ready = false;
    _startedAt = null;
    if (!_supported || Session.I.signedIn) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      // Someone signed in meanwhile: keep the token they now use.
      if (Session.I.signedIn) return;
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    token = null;
  }
}

const _appPortName = 'medpin.push.app';

/// Silent pushes that do work in the background (nothing is shown).
const _backgroundTypes = {'device_sync', 'reminders_changed', 'signed_out'};

/// The work itself, for a signed-in patient only: watch / phone readings up
/// (DeviceSync keeps its 30-minute limit) or the medicine alarms re-scheduled.
Future<void> _backgroundWork(String type) async {
  if (type == 'signed_out') return MedAlarms.I.clear();
  if (!_backgroundTypes.contains(type) || !Session.I.signedIn || Session.I.landing != 'Main') return;
  if (type == 'device_sync') {
    await DeviceSync.sync(null);
  } else {
    MedAlarms.I.sync();
    // MedAlarms runs on its own timer; stay alive while it re-schedules.
    await Future<void>.delayed(const Duration(seconds: 10));
  }
}

/// Firebase Messaging's background handler (registered in main.dart): a data
/// message while the app is in the background or closed. No UI and no
/// BuildContext here — it may run in its own isolate with no screens.
@pragma('vm:entry-point')
Future<void> pushBackground(RemoteMessage msg) async {
  final type = msg.data['type']?.toString() ?? '';
  if (!_backgroundTypes.contains(type)) return; // notifications are shown by the system
  // Signed out from another device: no session needed to remove this phone's alarms.
  if (type == 'signed_out') {
    try {
      if (await _handToApp(type)) return;
      DartPluginRegistrant.ensureInitialized();
      await MedAlarms.I.clear();
    } catch (e) {
      debugPrint('Background sign-out: $e');
    }
    return;
  }
  try {
    // The app is still in memory: it does the work with its session.
    if (await _handToApp(type)) return;
    DartPluginRegistrant.ensureInitialized();
    if (!await _restoreSaved()) return; // not signed in: nothing to do
    if (Session.I.landing != 'Main') return; // patients only
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    // MedAlarms tells the server what this phone rings (needs this phone's token).
    Push.I.token ??= await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 10), onTimeout: () => null);
    await _backgroundWork(type);
  } catch (e) {
    debugPrint('Background push $type: $e');
  }
}

/// Asks the app (if it is running) to do [type]. False when nobody answered:
/// no app, or a name left behind by one that has closed.
Future<bool> _handToApp(String type) async {
  final app = IsolateNameServer.lookupPortByName(_appPortName);
  if (app == null) return false;
  final reply = ReceivePort();
  final got = Completer<void>();
  final done = Completer<void>();
  reply.listen((m) {
    if (m == 'got' && !got.isCompleted) got.complete();
    if (m == 'done' && !done.isCompleted) done.complete();
  });
  try {
    app.send([type, reply.sendPort]);
    await got.future.timeout(const Duration(seconds: 5));
    // Keep this handler (and so the phone's wake-up) alive until the app is done.
    await done.future.timeout(const Duration(seconds: 25), onTimeout: () {});
    return true;
  } on TimeoutException {
    return false;
  } finally {
    reply.close();
  }
}

/// The saved sign-in, read as it is (no server check, so a passing error
/// can't sign the patient out from the background). Read afresh every time:
/// this isolate can outlive an app run that has since rotated the tokens.
/// Expired tokens refresh through Api as usual and are saved for the app.
Future<bool> _restoreSaved() => Session.I.loadSaved();

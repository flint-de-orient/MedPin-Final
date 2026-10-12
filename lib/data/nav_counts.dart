import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api.dart';
import 'config.dart';
import 'session.dart';

/// Live numbers on the clinic tab bars:
/// - Messages: conversations with unread messages, patient chats plus
///   colleague chats (the same number as "N unread" on Doctor-Messages);
/// - Care: open alerts.
///
/// Refreshed when a tab bar shows (at most every 20 seconds), every 30
/// seconds while one is on screen, when a chat is read or an alert handled
/// (see [Api.onCountsChanged]), when a notification arrives and when the app
/// comes back to the front.
class NavCounts {
  NavCounts._();
  static final counts = ValueNotifier<({int messages, int care})>((messages: 0, care: 0));
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _busy = false;
  static bool _again = false;
  static Timer? _timer;
  static final _inTests = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> refresh({bool force = false}) async {
    if (AppMode.preview || !Session.I.signedIn) return;
    _keepFresh();
    if (_busy) {
      // A forced refresh during a fetch runs again right after it.
      if (force) _again = true;
      return;
    }
    if (!force && DateTime.now().difference(_last) < const Duration(seconds: 20)) return;
    _busy = true;
    _last = DateTime.now();
    try {
      final chats = Session.I.can('chats');
      final r = await Future.wait([
        chats ? _get('/api/inbox', {'type': 'all', 'tab': 'unread'}) : Future.value(null),
        chats ? _get('/api/inbox', {'type': 'direct', 'tab': 'unread'}) : Future.value(null),
        Session.I.can('alerts') ? _get('/api/alerts', {'status': 'open', 'limit': '1'}) : Future.value(null),
      ]);
      if (!Session.I.signedIn) return;
      final alerts = r[2] ?? const {};
      final open = (alerts['counts'] as Map?)?['open'] ?? alerts['total'] ?? (alerts['items'] as List?)?.length ?? 0;
      counts.value = (
        // A failed fetch keeps the last number rather than hiding the badge.
        messages: r[0] == null && r[1] == null && chats ? counts.value.messages : _unread(r[0]) + _unread(r[1]),
        care: r[2] == null ? counts.value.care : (open as num).toInt(),
      );
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        refresh(force: true);
      }
    }
  }

  /// The Messages screen just loaded both inboxes; use its number at once.
  static void setMessages(int n) {
    if (AppMode.preview || counts.value.messages == n) return;
    counts.value = (messages: n, care: counts.value.care);
  }

  /// Signed out: no badges, no polling.
  static void clear() {
    _timer?.cancel();
    _timer = null;
    _last = DateTime.fromMillisecondsSinceEpoch(0);
    counts.value = (messages: 0, care: 0);
  }

  static int _unread(Map? inbox) => (inbox?['unread'] as num?)?.toInt() ?? 0;

  static Future<Map?> _get(String path, Map<String, String> query) async {
    try {
      final r = await Api.I.get(path, query: query);
      return r is Map ? r : null;
    } catch (_) {
      return null;
    }
  }

  /// Polls every 30 seconds while a clinic account is signed in and the app
  /// is in front (patients have no clinic tab bar).
  static void _keepFresh() {
    if (_inTests) return; // widget tests drive refreshes themselves
    _timer ??= Timer.periodic(const Duration(seconds: 30), (t) {
      if (!Session.I.signedIn || Session.I.memberships.isEmpty) {
        t.cancel();
        _timer = null;
        return;
      }
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) refresh(force: true);
    });
  }
}

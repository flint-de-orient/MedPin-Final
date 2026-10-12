import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/data/api.dart';
import 'package:medpin_app/data/config.dart';
import 'package:medpin_app/data/nav_counts.dart';
import 'package:medpin_app/data/session.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/screens/doctor/common_d10.dart';
import 'package:medpin_app/widgets/navs.dart';

/// The Messages badge counts unread patient chats plus unread colleague
/// chats from the server, and follows reads.
void main() {
  var careUnread = 3;
  var directUnread = 1;
  var reads = 0;
  var notes = 0;
  var urgent = 0;

  setUpAll(() {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
  });

  setUp(() {
    careUnread = 3;
    directUnread = 1;
    reads = 0;
    notes = 0;
    urgent = 0;
    NavCounts.clear();
    Session.I
      ..accessToken = 'test-access'
      ..refreshToken = 'test-refresh'
      ..account = {
        'user': {'id': 'u1', 'name': 'Dr. Arjun Sen', 'phone': '9876518210'},
        'memberships': [
          {'id': 'm1', 'practiceId': 'p1', 'practiceName': 'City Care', 'role': 'doctor', 'isOwner': true, 'status': 'active', 'permissions': {'chats': true, 'alerts': true}},
        ],
        'patientId': null,
        'landing': 'Doctor-Dashboard',
      };
    Api.I.client = MockClient((req) async {
      const json = {'content-type': 'application/json'};
      final p = req.url.path;
      final q = req.url.queryParameters;
      if (req.method == 'POST' && p.endsWith('/read')) {
        reads++;
        careUnread = careUnread > 0 ? careUnread - 1 : 0;
        return http.Response('{"ok":true}', 200, headers: json);
      }
      if (p == '/api/inbox') {
        final n = q['type'] == 'direct' ? directUnread : careUnread;
        return http.Response(jsonEncode({'unread': n, 'urgent': 0, 'items': []}), 200, headers: json);
      }
      if (p == '/api/alerts') return http.Response(jsonEncode({'counts': {'open': 2}, 'items': []}), 200, headers: json);
      if (p == '/api/notifications') return http.Response(jsonEncode({'items': [], 'unread': notes, 'urgent': urgent}), 200, headers: json);
      return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked"}}', 404, headers: json);
    });
    Api.I.onCountsChanged = () => NavCounts.refresh(force: true);
  });

  testWidgets('Messages badge shows real unread chats and drops after a read', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(bottomNavigationBar: DoctorNav(current: 0))));
    await t.pumpAndSettle();
    expect(find.text('4'), findsOneWidget); // 3 patient chats + 1 colleague chat

    await Api.I.post('/api/conversations/c1/read', const {});
    await t.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('3'), findsOneWidget);

    careUnread = 0;
    directUnread = 0;
    await NavCounts.refresh(force: true);
    await t.pumpAndSettle();
    expect(find.text('0'), findsNothing); // no badge at zero
    expect(find.text('Messages'), findsOneWidget);
    NavCounts.clear();
  });

  testWidgets('A failed refresh keeps the last number', (t) async {
    await NavCounts.refresh(force: true);
    expect(NavCounts.counts.value.messages, 4);
    expect(NavCounts.counts.value.care, 2);
    Api.I.client = MockClient((_) async => http.Response('{"error":{"code":"SERVER_ERROR","message":"x"}}', 500, headers: const {'content-type': 'application/json'}));
    await NavCounts.refresh(force: true);
    expect(NavCounts.counts.value.messages, 4);
    NavCounts.clear();
  });

  testWidgets('Large counts show 99+', (t) async {
    careUnread = 150;
    await t.pumpWidget(const MaterialApp(home: Scaffold(bottomNavigationBar: DoctorNav(current: 0))));
    await t.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
    NavCounts.clear();
  });

  testWidgets('Front-desk bell: red dot only for an emergency, blue otherwise, none when read', (t) async {
    Color? dot() {
      final boxes = t.widgetList<Container>(find.descendant(of: find.byType(D10StaffHeader), matching: find.byType(Container)));
      for (final b in boxes) {
        final d = b.decoration;
        if (d is BoxDecoration && d.shape == BoxShape.circle && b.constraints?.maxWidth == 12) return d.color;
      }
      return null;
    }

    await t.pumpWidget(const MaterialApp(home: Scaffold(body: D10StaffHeader(bellLabel: 'Notifications'))));
    await t.pumpAndSettle();
    expect(dot(), isNull, reason: 'nothing unread: no dot');

    notes = 2;
    await NavCounts.refresh(force: true);
    await t.pumpAndSettle();
    expect(dot(), MP.primary);
    expect(find.bySemanticsLabel('Notifications, 2 new'), findsOneWidget);

    urgent = 1;
    await NavCounts.refresh(force: true);
    await t.pumpAndSettle();
    expect(dot(), MP.red);
    expect(find.bySemanticsLabel('Notifications, 2 new, 1 urgent'), findsOneWidget);
    NavCounts.clear();
  });
}

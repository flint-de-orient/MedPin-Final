import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/api.dart';
import 'package:medpin_app/data/config.dart';
import 'package:medpin_app/data/session.dart';
import 'package:medpin_app/screens/staff/staff_patients.dart';
import 'package:medpin_app/screens/staff/staff_profile.dart';
import 'package:medpin_app/screens/staff/staff_today.dart';

/// The front desk's own tabs (Today, Patients, Profile) rendered from real
/// API responses recorded from the local backend as Tania Ghosh (front desk)
/// into test/fixtures/live/staff_desk, with one action per screen.

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/staff_desk/$name.json').readAsStringSync());

/// Requests the screen made: (method, path with query, JSON body).
final _calls = <(String, String, Object?)>[];

bool _calledLike(String method, bool Function(String path) test) => _calls.any((c) => c.$1 == method && test(c.$2));

Object? _answer(http.Request r) {
  final p = r.url.path;
  if (r.method == 'GET') {
    if (p == '/api/me' || p == '/api/auth/session') return _fx('me');
    if (p == '/api/inbox') return _fx('inbox_all');
    if (p == '/api/locations') return _fx('locations');
    if (p == '/api/notifications') return _fx('notifications');
    if (p == '/api/staff/today') return _fx('today');
    if (p == '/api/doctors') return const [];
    if (p == '/api/appointment-requests') return (_fx('today') as Map)['requests'];
    return null;
  }
  if (p == '/api/me') return _fx('me');
  return {'ok': true};
}

void _serve() {
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = (_fx('session') as Map).cast<String, dynamic>();
  _calls.clear();
  Api.I.client = MockClient((req) async {
    final q = req.url.query;
    _calls.add((req.method, req.url.path + (q.isEmpty ? '' : '?$q'), req.body.isEmpty ? null : jsonDecode(req.body)));
    final a = _answer(req);
    if (a == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked: ${req.url.path}"}}', 404);
    return http.Response(jsonEncode(a), 200, headers: {'content-type': 'application/json'});
  });
}

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester t, Widget screen, {required String stem}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    onGenerateRoute: (_) => MaterialPageRoute(settings: RouteSettings(name: stem), builder: (_) => screen),
  ));
  await _settle(t);
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

Future<void> _tearDown(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 40));
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Staff-Patients lists the live inbox; Unread filters; a row opens its thread', (t) async {
    _serve();
    await _pump(t, const StaffPatientsScreen(), stem: 'Staff-Patients');
    final inbox = _fx('inbox_all') as Map;
    final items = (inbox['items'] as List).cast<Map>();
    for (final c in items) {
      expect(find.text((c['patient'] as Map)['name'] as String), findsWidgets);
    }
    expect(find.text('Unread (${inbox['unread']})'), findsOneWidget);
    expect(find.text('Needs attention'), findsWidgets);
    expect(find.textContaining('Priya Sharma, the sample'), findsNothing);

    // Unread hides chats with nothing new.
    final read = items.firstWhere((c) => c['unread'] == 0);
    await _tap(t, find.text('Unread (${inbox['unread']})'));
    expect(find.text((read['patient'] as Map)['name'] as String), findsNothing);

    final first = items.firstWhere((c) => (c['unread'] as num) > 0);
    await _tap(t, find.text((first['patient'] as Map)['name'] as String).first);
    expect(_calledLike('GET', (p) => p.startsWith('/api/conversations/${first['id']}/messages')), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Staff-Profile shows the signed-in account; app lock saves', (t) async {
    _serve();
    await _pump(t, const StaffProfileScreen(), stem: 'Staff-Profile');
    expect(find.text('Tania Ghosh'), findsOneWidget);
    expect(find.text('+91 97496 81391'), findsOneWidget);
    expect(find.text('Front desk'), findsOneWidget);
    expect(find.text('City Care Clinic · Salt Lake'), findsOneWidget);
    await _tap(t, find.bySemanticsLabel('App lock').last);
    final patch = _calls.lastWhere((c) => c.$1 == 'PATCH' && c.$2 == '/api/me');
    expect(patch.$3, {'appLock': false});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Staff-Today: a request and an appointment open with their ids', (t) async {
    _serve();
    await _pump(t, const StaffTodayScreen(), stem: 'Staff-Today');
    final today = _fx('today') as Map;
    final request = (today['requests'] as List).first as Map;
    expect(find.text((request['patientId'] as Map)['name'] as String), findsWidgets);

    await _tap(t, find.text('Assign time').first);
    // Appointments-Manage opens in "assign a request" mode (it looks the request up among the pending ones).
    expect(_calledLike('GET', (p) => p == '/api/appointment-requests?status=pending'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Staff-Today: an appointment row opens that patient at the desk', (t) async {
    _serve();
    await _pump(t, const StaffTodayScreen(), stem: 'Staff-Today');
    final items = ((_fx('today') as Map)['items'] as List).cast<Map>();
    final waiting = items.firstWhere((a) => a['status'] == 'waiting');
    final patient = waiting['patient'] as Map;
    await _tap(t, find.text(patient['name'] as String).last);
    expect(_calledLike('GET', (p) => p.startsWith('/api/patients/${patient['id']}')), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

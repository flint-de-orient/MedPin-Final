import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/api.dart';
import 'package:medpin_app/data/config.dart';
import 'package:medpin_app/data/session.dart';
import 'package:medpin_app/screens/staff/staff_book.dart';

/// Front desk "Book appointment": patient first, then a free time, then a
/// confirmed visit.
void main() {
  final calls = <(String, String, Object?)>[];

  setUpAll(() {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
  });

  setUp(() {
    calls.clear();
    Session.I
      ..accessToken = 'a'
      ..refreshToken = 'r'
      ..account = {
        'user': {'id': 'u9', 'name': 'Tania Ghosh', 'phone': '9749681391'},
        'memberships': [
          {'id': 'm9', 'practiceId': 'p1', 'practiceName': 'City Care', 'role': 'front_desk', 'isOwner': false, 'status': 'active', 'permissions': {'viewPatients': true}},
        ],
        'patientId': null,
        'landing': 'Staff-Today',
      };
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final key = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    Api.I.client = MockClient((req) async {
      calls.add((req.method, req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
      const json = {'content-type': 'application/json'};
      final p = req.url.path;
      Object? out;
      if (p == '/api/patients') {
        final q = req.url.queryParameters['q'] ?? '';
        out = {
          'items': [
            if (q.isEmpty || 'amit pal'.contains(q.toLowerCase()))
              {'id': 'pt1', 'name': 'Amit Pal', 'age': 42, 'gender': 'male', 'phone': '9831120770', 'conditions': ['Type 2 diabetes'], 'hasApp': true},
            if (q.isEmpty) {'id': 'pt2', 'name': 'Priya Sharma', 'age': 29, 'gender': 'female', 'phone': '9230592842', 'conditions': []},
          ],
        };
      } else if (p == '/api/doctors') {
        out = [
          {
            'userId': 'd1',
            'name': 'Dr. Arjun Sen',
            'locations': [
              {'id': 'l1', 'name': 'Salt Lake'},
            ],
          },
        ];
      } else if (p == '/api/doctors/d1/slots') {
        final open = req.url.queryParameters['date'] == key;
        out = {
          'open': open,
          'slots': open
              ? [
                  {'time': '9:00 AM', 'startAt': '${key}T03:30:00.000Z', 'available': false},
                  {'time': '9:30 AM', 'startAt': '${key}T04:00:00.000Z', 'available': true},
                ]
              : [],
        };
      } else if (p == '/api/appointments' && req.method == 'POST') {
        return http.Response(jsonEncode({'id': 'a1', 'status': 'confirmed', 'token': '04'}), 201, headers: json);
      }
      if (out == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"x"}}', 404, headers: json);
      return http.Response(jsonEncode(out), 200, headers: json);
    });
  });

  Future<void> settle(WidgetTester t, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('pick the patient, then a free time; books a confirmed visit', (t) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), navigatorKey: Nav.key, home: const StaffBookScreen()));
    await settle(t);
    expect(find.text('Recent patients'), findsOneWidget);
    expect(find.text('Choose the doctor and place to see free times.'), findsNothing, reason: 'the only doctor and place are chosen');

    // 1 · Patient: search narrows the list; tap to choose.
    await t.enterText(find.byType(EditableText).first, 'amit');
    await t.pump(const Duration(milliseconds: 350));
    await settle(t);
    expect(find.text('Priya Sharma'), findsNothing);
    await t.tap(find.text('Amit Pal'));
    await settle(t);
    expect(find.text('Change'), findsOneWidget, reason: 'the chosen patient shows with Change');
    expect(find.text('Dr. Sen · Salt Lake'), findsOneWidget);

    // 3 · Time: booked times are crossed out and can't be chosen.
    await t.tap(find.text('9:00 AM'));
    await t.pump();
    await t.tap(find.text('Book confirmed visit'));
    await settle(t);
    expect(calls.where((c) => c.$1 == 'POST').isEmpty, isTrue, reason: 'no time chosen yet');
    await t.tap(find.text('9:30 AM'));
    await t.pump();
    await t.tap(find.text('Book confirmed visit'));
    await settle(t);
    final body = calls.lastWhere((c) => c.$1 == 'POST' && c.$2 == '/api/appointments').$3 as Map;
    expect(body['patientId'], 'pt1');
    expect(body['doctorId'], 'd1');
    expect(body['locationId'], 'l1');
    expect(body['visitType'], 'follow_up');
    expect(body['confirmed'], true);
    expect((body['startAt'] as String).endsWith('T04:00:00.000Z'), isTrue);
    expect(find.text('Visit confirmed'), findsOneWidget);
    expect(find.textContaining('Token 04'), findsOneWidget);
    await t.tap(find.text('Done'));
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}

import 'dart:convert';
import 'dart:io';

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
import 'package:medpin_app/screens/doctor/clinic_editor.dart';
import 'package:medpin_app/screens/staff/staff_profile.dart';

/// Front desk who covers two locations of City Care Clinic and also works at
/// a second clinic: Profile lists every location with its doctors, the
/// Account sheet says what they can do, the Clinic row switches clinics, and
/// the location editor lets them add closures but shows hours read-only.

const _practice = '6ac8cfc20fd26bd4a0327bf5';
const _other = '6ac8cfc20fd26bd4a0327c99';

Map<String, dynamic> get _session => {
      'user': {'id': 'u1', 'name': 'Payel Haldar', 'phone': '9749681391', 'language': 'en', 'appLock': false},
      'memberships': [
        {'id': 'm1', 'practiceId': _practice, 'practiceName': 'City Care Clinic', 'role': 'front_desk', 'isOwner': false, 'status': 'active', 'permissions': {'viewPatients': true, 'closures': true}},
        {'id': 'm2', 'practiceId': _other, 'practiceName': 'Lake View Clinic', 'role': 'front_desk', 'isOwner': false, 'status': 'active', 'permissions': {'viewPatients': true, 'closures': true}},
      ],
      'activePracticeId': _practice,
      'patientId': null,
      'landing': 'Staff-Today',
    };

final _mine = {
  'id': 'm1',
  'role': 'front_desk',
  'isOwner': false,
  'joinedAt': '2026-03-02T05:00:00.000Z',
  'department': null,
  'allLocations': true,
  'practice': {'id': _practice, 'name': 'City Care Clinic'},
  'permissions': {'viewPatients': true, 'chats': true, 'fees': true, 'vitals': true, 'closures': true, 'manageClinic': false},
  'coverage': [
    {
      'id': 'l1', 'name': 'City Care Clinic — Salt Lake', 'shortName': 'Salt Lake',
      'doctors': [{'userId': 'd1', 'name': 'Dr. Arjun Sen'}],
      'can': {'details': false, 'hours': false, 'closures': true},
    },
    {
      'id': 'l2', 'name': 'City Care Clinic — New Town', 'shortName': 'New Town',
      'doctors': [{'userId': 'd1', 'name': 'Dr. Arjun Sen'}, {'userId': 'd2', 'name': 'Dr. Rina Mitra'}],
      'can': {'details': false, 'hours': false, 'closures': true},
    },
  ],
  'worksFor': [{'userId': 'd1', 'name': 'Dr. Arjun Sen'}, {'userId': 'd2', 'name': 'Dr. Rina Mitra'}],
};

Map<String, dynamic> get _location {
  final f = jsonDecode(File('test/fixtures/live/clinic/location.json').readAsStringSync()) as Map<String, dynamic>;
  final l = (f['data'] as Map).cast<String, dynamic>();
  return {
    ...l,
    'can': {
      'details': false, 'hours': false, 'closures': true,
      'note': 'You can add and remove holidays and closures. Details and weekly hours are changed by the owner or practice manager.',
    },
    'doctors': [
      for (final d in (l['doctors'] as List).cast<Map>()) {...d, 'canEdit': false, 'isMe': false},
    ],
  };
}

final _calls = <(String, String, Object?)>[];

void _serve() {
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..chosenPracticeId = null
    ..account = _session;
  _calls.clear();
  Api.I.client = MockClient((req) async {
    final p = req.url.path;
    _calls.add((req.method, p + (req.url.query.isEmpty ? '' : '?${req.url.query}'), req.body.isEmpty ? null : jsonDecode(req.body)));
    Object? body;
    if (req.method == 'GET') {
      if (p == '/api/me' || p == '/api/auth/session') body = _session;
      if (p == '/api/members/me') body = _mine;
      if (p == '/api/notifications') body = {'items': [], 'unread': 0, 'urgent': 0};
      if (p == '/api/locations/${_location['id']}') body = _location;
      if (p == '/api/locations') body = {'items': [_location]};
      if (p.endsWith('/closures/preview')) body = {'booked': 2};
    } else {
      body = p == '/api/me/active-practice' ? {'ok': true, ..._session, 'activePracticeId': (jsonDecode(req.body) as Map)['practiceId']} : {'ok': true, 'patientsTold': 2};
    }
    if (body == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked: $p"}}', 404);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });
}

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester t, Widget screen, {required String stem, Object? args}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    onGenerateRoute: (_) => MaterialPageRoute(settings: RouteSettings(name: stem, arguments: args), builder: (_) => screen),
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
  setUpAll(() {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
  });

  testWidgets('Staff-Profile: every location with its doctors, the account, switching clinics', (t) async {
    _serve();
    await _pump(t, const StaffProfileScreen(), stem: 'Staff-Profile');
    expect(find.text('City Care Clinic · Salt Lake'), findsOneWidget);
    expect(find.text('City Care Clinic · New Town'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen · Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('You work in 2 clinics'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Account'));
    expect(find.text('What you can do'), findsOneWidget);
    expect(find.text('Add holidays and closures'), findsOneWidget);
    expect(find.text('All locations'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen, Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Your sign-in number. To change it, ask the practice owner.'), findsOneWidget);
    await _tap(t, find.bySemanticsLabel('Close').last);

    await _tap(t, find.text('Switch'));
    await _tap(t, find.text('Lake View Clinic'));
    expect(Session.I.practiceId, _other);
    expect(_calls.any((c) => c.$1 == 'POST' && c.$2 == '/api/me/active-practice' && (c.$3 as Map)['practiceId'] == _other), isTrue);
    // The next requests go to the other clinic.
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Clinic-Editor as front desk: closures work, hours are read-only', (t) async {
    _serve();
    await _pump(t, const ClinicEditorScreen(), stem: 'Clinic-Editor', args: {'locationId': _location['id']});
    expect(find.textContaining('You can add and remove holidays and closures'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Use current location'), findsNothing);

    await _tap(t, find.text('Add closure'));
    await t.enterText(find.byType(TextField).last, 'Staff training');
    await _tap(t, find.text('Part of the day'));
    expect(find.text('2 booked patients will be told to choose another time'), findsOneWidget);
    await _tap(t, find.text('Add closure').last);
    final post = _calls.lastWhere((c) => c.$1 == 'POST');
    expect(post.$2, '/api/locations/${_location['id']}/closures');
    expect(post.$3, containsPair('allDay', false));
    expect(post.$3, containsPair('reason', 'Staff training'));
    expect((post.$3 as Map)['toMin'] as int, greaterThan((post.$3 as Map)['fromMin'] as int));

    await _tap(t, find.text('Dr. Rina Mitra'));
    expect(find.text('Only Dr. Rina Mitra, the owner or the practice manager can change these hours.'), findsOneWidget);
    expect(find.text('Save hours'), findsNothing);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

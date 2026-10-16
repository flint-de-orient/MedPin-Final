import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/data/api.dart';
import 'package:medpin_app/data/config.dart';
import 'package:medpin_app/data/session.dart';
import 'package:medpin_app/screens/doctor/care.dart';
import 'package:medpin_app/screens/doctor/doctor_home.dart';
import 'package:medpin_app/screens/doctor/doctor_myprofile.dart';
import 'package:medpin_app/screens/doctor/home_states.dart';
import 'package:medpin_app/screens/doctor/nutrition.dart';
import 'package:medpin_app/screens/doctor/practice.dart';
import 'package:medpin_app/screens/doctor/profile.dart';
import 'package:medpin_app/screens/doctor/profile_location.dart';
import 'package:medpin_app/screens/doctor/profile_professional.dart';
import 'package:medpin_app/screens/doctor/profile_schedule.dart';
import 'package:medpin_app/widgets/mp.dart';

/// The "profile" group of doctor screens rendered from real API responses
/// (recorded from the local backend into test/fixtures/live/profile).
Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/profile/$name.json').readAsStringSync());

/// The recorded alerts are from 9 Oct; Doctor-Home lists those since
/// yesterday, so they are moved to an hour ago (keeping their order).
dynamic _recent(dynamic alerts) {
  final at = DateTime.now().toUtc().subtract(const Duration(hours: 1));
  var i = 0;
  for (final a in (alerts as Map)['items'] as List) {
    (a as Map)['createdAt'] = at.subtract(Duration(seconds: i++)).toIso8601String();
  }
  return alerts;
}

/// GET responses by path (and the query that picks them).
dynamic _getResponse(Uri u) {
  final p = u.path;
  final q = u.queryParameters;
  if (p == '/api/doctor/profile') return _fx('doctor_profile');
  if (p == '/api/me') return _fx('me');
  if (p == '/api/doctor/locations') return _fx('doctor_locations');
  if (p == '/api/doctor/leaves') return _fx('leaves');
  // Leave and the clinics' holidays (Profile-Schedule, Leave and holidays).
  if (p == '/api/doctor/time-off') return {'leaves': _fx('leaves'), 'holidays': const [], 'canAddHoliday': true, 'locations': const []};
  if (p == '/api/members') return _fx('members');
  if (p == '/api/billing') return _fx('billing');
  if (p == '/api/practice') return _fx('practice');
  if (p.startsWith('/api/locations/')) return _fx('location');
  if (p == '/api/dashboard') return _fx('dashboard');
  if (p == '/api/queue') return _fx('queue');
  if (p == '/api/alerts') return _recent(_fx('alerts'));
  if (p == '/api/inbox/reviews') return _fx('reviews');
  if (p == '/api/patients' && q['filter'] == 'abnormal') return _fx('patients_abnormal');
  if (p == '/api/notifications') return _fx('notifications');
  if (p == '/api/inbox' && q['type'] == 'care') return _fx('inbox_care');
  if (p == '/api/inbox' && q['type'] == 'nutrition') return _nutrition ?? _fx('inbox_nutrition');
  return null;
}

/// Overrides the recorded (empty) nutrition inbox for one test.
Map<String, dynamic>? _nutrition;

/// Paths answered with a server error (per-card error states).
Set<String> _failing = {};

final List<http.Request> _requests = [];

http.Request? _sent(String method, String path) {
  for (final r in _requests.reversed) {
    if (r.method == method && r.url.path == path) return r;
  }
  return null;
}

Map<String, dynamic> _body(http.Request r) => (jsonDecode(r.body) as Map).cast<String, dynamic>();

void _serve() {
  final me = _fx('me') as Map;
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = {'user': me['user'], 'memberships': me['memberships'], 'patientId': null, 'landing': 'Doctor-Dashboard'};
  _requests.clear();
  _failing = {};
  _nutrition = null;
  Api.I.client = MockClient((req) async {
    _requests.add(req);
    const json = {'content-type': 'application/json'};
    if (_failing.contains(req.url.path)) {
      return http.Response('{"error":{"code":"SERVER_ERROR","message":"Something went wrong. Please try again."}}', 500, headers: json);
    }
    if (req.method == 'GET') {
      final r = _getResponse(req.url);
      if (r != null) return http.Response(jsonEncode(r), 200, headers: json);
      return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked"}}', 404, headers: json);
    }
    // Mutations: echo something sensible.
    if (req.url.path == '/api/doctor/profile' || req.url.path.startsWith('/api/doctor/qualifications')) {
      return http.Response(jsonEncode(_fx('doctor_profile')), 200, headers: json);
    }
    if (req.url.path.startsWith('/api/doctor/locations/')) {
      return http.Response(jsonEncode((_fx('doctor_locations') as List).first), 200, headers: json);
    }
    return http.Response('{"ok":true}', 200, headers: json);
  });
}

class _Pushed extends NavigatorObserver {
  final List<RouteSettings> routes = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route.settings);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

Future<_Pushed> _pumpLive(WidgetTester t, Widget screen, {Object? args, double width = 390}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pushed = _Pushed();
  await t.pumpWidget(
    MaterialApp(
      theme: medpinTheme(),
      navigatorObservers: [pushed],
      onGenerateRoute: (s) => MaterialPageRoute(settings: RouteSettings(name: 'Under-Test', arguments: args), builder: (_) => screen),
    ),
  );
  await _settle(t);
  return pushed;
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
  await _settle(t);
  await t.pump(const Duration(milliseconds: 400)); // sheet / route transitions
  await _settle(t);
}

Future<void> _tearDown(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 7));
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Doctor-MyProfile shows the live profile and saves languages', (t) async {
    _serve();
    await _pumpLive(t, const DoctorMyprofileScreen());
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('AS'), findsOneWidget);
    expect(find.text('Diabetologist · Internal medicine'), findsOneWidget);
    expect(find.text('MBBS, MD · WBMC 64213 · 16 yrs'), findsOneWidget);
    expect(find.text('Profile 57% complete'), findsOneWidget);
    expect(find.text('Add a photo and a short bio to appear higher in patient search.'), findsOneWidget);
    expect(find.textContaining('Next free slot: '), findsOneWidget);
    expect(find.textContaining(' · Salt Lake'), findsOneWidget);
    expect(find.text('English, Bengali'), findsOneWidget);
    expect(find.text('2 locations · map, address, contact'), findsOneWidget);
    expect(find.text('7 services · in clinic and video'), findsOneWidget);
    expect(find.text('No leave planned'), findsOneWidget);
    expect(find.text('Sent 3 days before · WhatsApp and app'), findsOneWidget);
    expect(find.text('Signature missing'), findsOneWidget);
    expect(find.text('Front desk at City Care Clinic · 2 people'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra and Mou Banerjee'), findsOneWidget);
    expect(find.text('MedPin Clinic · renews 14 Oct'), findsOneWidget);
    expect(find.text('English'), findsOneWidget); // app language
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Add Hindi?'));
    final r = _sent('PATCH', '/api/doctor/profile');
    expect(r, isNotNull);
    expect(_body(r!)['languagesSpoken'], ['English', 'Bengali', 'Hindi']);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Profile-Professional shows registration and qualifications and saves', (t) async {
    _serve();
    await _pumpLive(t, const ProfileProfessionalScreen());
    expect(find.text('West Bengal Medical Council'), findsOneWidget);
    expect(find.text('64213'), findsOneWidget);
    expect(find.text('Verified'), findsWidgets);
    expect(find.text('MD, Internal Medicine'), findsOneWidget);
    expect(find.text('Calcutta Medical College · 2008'), findsOneWidget);
    expect(find.text('Upload proof'), findsOneWidget);
    expect(find.text('Thyroid disorders'), findsOneWidget);
    expect(find.text('RSSDI member'), findsOneWidget);
    expect(find.text('2010'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('Not linked'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Psychologist'));
    await _tap(t, find.text('Save'));
    final r = _sent('PATCH', '/api/doctor/profile');
    expect(r, isNotNull);
    expect(_body(r!), {'profession': 'psychologist'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Profile-Location shows the location and stops practising there', (t) async {
    _serve();
    const id = '6ac8bbcee42c9f0836e98563';
    await _pumpLive(t, const ProfileLocationScreen(), args: {'locationId': id});
    expect(_sent('GET', '/api/locations/$id'), isNotNull);
    expect(find.text('City Care Clinic · Salt Lake'), findsWidgets);
    expect(find.text('DD-24, Sector 1, Salt Lake, Kolkata 700064'), findsOneWidget);
    expect(find.text('033 4012 5678'), findsOneWidget);
    expect(find.text('Repeat visit for the same problem'), findsOneWidget);
    expect(find.text('₹600'), findsNWidgets(3));
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Pharmacy'), findsOneWidget);
    expect(find.text('Mon – Sat · 9:00 AM – 1:00 PM'), findsOneWidget);
    expect(find.text('15-min slots · up to 16 patients'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Stop practising here'));
    await _tap(t, find.text('Stop practising here').last);
    expect(_sent('POST', '/api/doctor/locations/$id/stop'), isNotNull);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Profile-Schedule shows each location and saves the slot length', (t) async {
    _serve();
    await _pumpLive(t, const ProfileScheduleScreen());
    expect(find.text('Salt Lake'), findsOneWidget);
    expect(find.text('New Town'), findsOneWidget);
    expect(find.text('Mon – Sat'), findsOneWidget);
    expect(find.text('4 evenings'), findsOneWidget);
    expect(find.text('Weekly hours · Salt Lake'), findsOneWidget);
    expect(find.text('9:00 – 1:00'), findsNWidgets(5));
    expect(find.text('9:00 – 11:30'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('No leave planned'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('+').first);
    expect(find.text('20 min'), findsOneWidget);
    await _tap(t, find.text('Save'));
    final r = _sent('PUT', '/api/doctor/locations/6ac8bbcee42c9f0836e98563');
    expect(r, isNotNull);
    final schedule = (_body(r!)['schedule'] as Map).cast<String, dynamic>();
    expect(schedule['slotLengthMin'], 20);
    expect((schedule['week'] as List).first, {
      'weekday': 'mon',
      'sessions': [
        {'startMin': 540, 'endMin': 780},
      ],
    });
    expect(_sent('PUT', '/api/doctor/locations/6ac8bbd08adea6a429a731b0'), isNull);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Profile tab shows the account, badges and saves app lock', (t) async {
    _serve();
    await _pumpLive(t, const ProfileScreen());
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('+91 93304 14463'), findsOneWidget);
    expect(find.text('Doctor · Owner'), findsOneWidget);
    expect(find.text('3 open'), findsOneWidget);
    expect(find.text('2 flagged'), findsOneWidget);
    expect(find.text('MBBS, MD · WBMC 64213'), findsOneWidget);
    expect(find.text('Not added yet'), findsOneWidget);
    expect(find.text('+91 33 4000 1234'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.byType(MpSwitch));
    final r = _sent('PATCH', '/api/me');
    expect(r, isNotNull);
    expect(_body(r!), {'appLock': false});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Practice shows readiness and tiles and saves the cadence', (t) async {
    _serve();
    await _pumpLive(t, const PracticeScreen());
    expect(find.text('City Care Clinic'), findsOneWidget);
    expect(find.text('Diabetes and heart care since 2011'), findsOneWidget);
    expect(find.text('Reg. no. WB/CE/2011/0412'), findsOneWidget);
    expect(find.text('1 blocking · 1 optional · 4 done'), findsOneWidget);
    expect(find.text('Add your digital signature'), findsOneWidget);
    expect(find.text('Add a map link'), findsOneWidget);
    expect(find.text('Set holiday closures'), findsOneWidget); // done
    expect(find.text('5'), findsOneWidget); // people
    expect(find.text('2'), findsNWidgets(2)); // locations, departments
    expect(find.textContaining('every 3 days'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Weekly'));
    final r = _sent('PATCH', '/api/practice');
    expect(r, isNotNull);
    expect(_body(r!), {'foodLogReviewCadence': 'weekly'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('Doctor-Home with live data at ${width.toInt()}px', (t) async {
      _serve();
      final pushed = await _pumpLive(t, const DoctorHomeScreen(), width: width);
      expect(find.textContaining(', Dr. Sen'), findsOneWidget);
      expect(find.textContaining('Updated '), findsOneWidget);
      expect(find.text('3 open'), findsOneWidget);
      expect(find.text('Emergency'), findsOneWidget);
      expect(find.text('Chest tightness, hard to breathe.'), findsNWidgets(2)); // open alerts + needs review
      expect(find.text('8 visits · 2 waiting · 2 done'), findsOneWidget);
      expect(find.text('In consult'), findsOneWidget);
      expect(find.text('Waiting'), findsNWidgets(2));
      expect(find.textContaining(' since yesterday'), findsOneWidget); // the count depends on today's date
      expect(find.text('4 patients'), findsOneWidget);
      expect(find.text('Abnormal lab results to review'), findsNWidgets(5)); // 3 worsening + 2 triage rows
      expect(find.text('Critical'), findsNWidgets(2)); // Priya (emergency) and Sujit (critical risk)
      expect(find.text('Last 7 days · 5 consultations'), findsOneWidget);
      expect(find.text('10 min', findRichText: true), findsOneWidget);
      expect(find.text('escalated'), findsOneWidget);
      expect(t.takeException(), isNull);

      await _tap(t, find.text('Chest tightness, hard to breathe.').first);
      expect(pushed.routes.last.name, 'Patient-Thread');
      expect(pushed.routes.last.arguments, {'conversationId': '6ac8bbcee42c9f0836e9858b', 'patientId': '6ac8bbcee42c9f0836e9857c'});
      await _tearDown(t);
    });
  }

  testWidgets('Doctor-Home shows a per-card error and retries it', (t) async {
    _serve();
    _failing = {'/api/queue'};
    await _pumpLive(t, const DoctorHomeScreen());
    expect(find.text("Couldn't load this card"), findsOneWidget);
    expect(find.text('3 open'), findsOneWidget);
    _failing = {};
    await _tap(t, find.text('Try again'));
    expect(find.text("Couldn't load this card"), findsNothing);
    expect(find.text('8 visits · 2 waiting · 2 done'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Home-States uses the dashboard request', (t) async {
    _serve();
    await _pumpLive(t, const HomeStatesScreen());
    expect(find.textContaining(', Dr. Sen'), findsOneWidget);
    expect(find.textContaining('Last checked '), findsOneWidget);
    final before = _requests.where((r) => r.url.path == '/api/dashboard').length;
    await _tap(t, find.text('Retry'));
    expect(_requests.where((r) => r.url.path == '/api/dashboard').length, before + 1);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Care lists the live inbox and opens a thread', (t) async {
    _serve();
    final pushed = await _pumpLive(t, const CareScreen());
    expect(find.text('Unread (5)'), findsOneWidget);
    for (final row in (_fx('inbox_care') as Map)['items'] as List) {
      expect(find.text(((row as Map)['patient'] as Map)['name'] as String), findsOneWidget);
    }
    expect(find.textContaining('Should I take the tablet before or after food?', findRichText: true), findsOneWidget);
    expect(find.textContaining('Priya:', findRichText: true), findsOneWidget);
    expect(find.textContaining('Tania:', findRichText: true), findsOneWidget);
    expect(find.text('Needs attention'), findsNWidgets(5));
    expect(find.textContaining('enrolment'), findsNothing);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Aisha Khan'));
    expect(pushed.routes.last.name, 'Patient-Thread');
    expect(pushed.routes.last.arguments, {'conversationId': '6ac8bbd18adea6a429a7343b', 'patientId': '6ac8bbd08adea6a429a731be'});
    await _tearDown(t);
  });

  testWidgets('Nutrition shows the empty live inbox', (t) async {
    _serve();
    await _pumpLive(t, const NutritionScreen());
    expect(find.text('Unread (0)'), findsOneWidget);
    expect(find.text('No nutrition conversations yet'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Nutrition rows open the patient thread', (t) async {
    _serve();
    // The demo data has no nutrition chats: reuse a recorded care row as one.
    final row = {...((_fx('inbox_care') as Map)['items'] as List).first as Map, 'type': 'nutrition'};
    _nutrition = {'unread': 1, 'urgent': 0, 'pendingEnrolments': 0, 'items': [row]};
    final pushed = await _pumpLive(t, const NutritionScreen());
    expect(find.text('Unread (1)'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    await _tap(t, find.text('Priya Sharma'));
    expect(pushed.routes.last.name, 'Patient-Thread');
    expect((pushed.routes.last.arguments as Map)['conversationId'], row['id']);
    await _tearDown(t);
  });
}

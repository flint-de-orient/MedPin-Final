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
import 'package:medpin_app/screens/auth/auth_clinic_setup.dart';
import 'package:medpin_app/screens/auth/auth_patient_setup.dart';
import 'package:medpin_app/screens/auth/auth_welcome.dart';

/// Sign-up for a new number (doctor starts a clinic / patient profile) and
/// session refresh behaviour.

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

final _calls = <(String, String, Object?)>[];
Object? _bodyOf(String method, String path) => _calls.lastWhere((c) => c.$1 == method && c.$2 == path).$3;

Map<String, dynamic> _account(String landing) => {
      'user': {'id': 'u1', 'name': 'Dr. Ananya Sen', 'phone': '9000000001', 'appLock': false},
      'memberships': landing == 'Doctor-Dashboard'
          ? [
              {'id': 'm1', 'practiceId': 'p1', 'practiceName': 'Sen Clinic', 'role': 'doctor', 'isOwner': true, 'status': 'active'},
            ]
          : [],
      'patientId': landing == 'Main' ? 'pt1' : null,
      'landing': landing,
    };

void _serve({String afterLanding = 'Doctor-Dashboard'}) {
  Session.I
    ..accessToken = 'a'
    ..refreshToken = 'r'
    ..account = _account('Auth-Welcome');
  _calls.clear();
  Api.I.client = MockClient((req) async {
    _calls.add((req.method, req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
    final p = req.url.path;
    Object? out;
    if (p == '/api/catalog/specialties') {
      out = [
        {'key': 'general', 'label': 'General physician'},
        {'key': 'diabetes', 'label': 'Diabetes & thyroid'},
      ];
    } else if (p == '/api/auth/session') {
      out = _account(afterLanding);
    } else if (req.method == 'POST') {
      out = {'ok': true};
    }
    if (out == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"x"}}', 404);
    return http.Response(jsonEncode(out), 200, headers: {'content-type': 'application/json'});
  });
}

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester t, Widget screen, String stem) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    navigatorKey: Nav.key,
    onGenerateRoute: (s) {
      final spec = Nav.spec(s.name ?? '');
      if (s.name == '/' || spec == null) return MaterialPageRoute(settings: RouteSettings(name: stem), builder: (_) => screen);
      return MaterialPageRoute(settings: s, builder: (_) => const Scaffold(body: Text('LANDED')));
    },
  ));
  await _settle(t);
}

Future<void> _enter(WidgetTester t, int index, String text) async {
  final f = find.byType(EditableText).at(index);
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Welcome offers doctor and patient sign-up', (t) async {
    _serve();
    await _pump(t, const AuthWelcomeScreen(), 'Auth-Welcome');
    expect(find.text("I'm a doctor"), findsOneWidget);
    expect(find.text("I'm a patient"), findsOneWidget);
    expect(find.textContaining('invite'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Start your clinic validates, then creates the practice with hours and fee', (t) async {
    _serve();
    await _pump(t, const AuthClinicSetupScreen(), 'Auth-Clinic-Setup');
    await _tap(t, find.text('Create my clinic'));
    expect(_calls.any((c) => c.$2 == '/api/me/practices'), isFalse, reason: 'nothing sent while the clinic name is empty');
    // Fields: 0 name, 1 qualifications, 2 reg no, 3 clinic, 4 area, 5 address, 6 city, 7 pincode, 8 clinic phone, 9 fee
    await _enter(t, 0, 'Dr. Ananya Sen');
    await _enter(t, 3, 'Sen Diabetes Clinic');
    await _enter(t, 4, 'Salt Lake');
    await _enter(t, 7, '700091');
    await _enter(t, 9, '700');
    await _tap(t, find.text('Create my clinic'));
    expect(_calls.any((c) => c.$2 == '/api/me/practices'), isFalse, reason: 'terms must be accepted');
    await _tap(t, find.textContaining("I agree to MedPin's"));
    await _tap(t, find.text('Create my clinic'));
    final body = _bodyOf('POST', '/api/me/practices') as Map;
    expect(body['name'], 'Sen Diabetes Clinic');
    expect(body['doctorName'], 'Dr. Ananya Sen');
    expect(body['area'], 'Salt Lake');
    expect(body['pincode'], '700091');
    expect(body['fee'], 700);
    expect(body['opensAt'], 540);
    expect(body['closesAt'], 1200);
    expect(body['openDays'], ['mon', 'tue', 'wed', 'thu', 'fri', 'sat']);
    expect(body['specialtyKey'], 'general');
    await _settle(t, 12);
    expect(find.byType(AuthClinicSetupScreen), findsNothing, reason: 'moves on to the doctor panel');
    t.takeException(); // the landing screen has no mocked data
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 40));
  });

  testWidgets('Patient sign-up registers and lands on the patient home', (t) async {
    _serve(afterLanding: 'Main');
    await _pump(t, const AuthPatientSetupScreen(), 'Auth-Patient-Setup');
    await _enter(t, 0, 'Priya Sharma');
    await _enter(t, 1, '29');
    await _tap(t, find.textContaining("I agree to MedPin's"));
    await _tap(t, find.text('Continue'));
    final body = _bodyOf('POST', '/api/patient/register') as Map;
    expect(body, {'name': 'Priya Sharma', 'gender': 'female', 'ageYears': 29, 'termsAccepted': true});
    await _settle(t, 12);
    expect(find.byType(AuthPatientSetupScreen), findsNothing, reason: 'moves on to the patient home');
    t.takeException(); // the landing screen has no mocked data
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 40));
  });

  test('Parallel 401s refresh the token once and nobody is signed out', () async {
    Session.I
      ..accessToken = 'old'
      ..refreshToken = 'r1'
      ..account = _account('Doctor-Dashboard');
    var refreshes = 0;
    Api.I.client = MockClient((req) async {
      if (req.url.path == '/api/auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(jsonEncode({'accessToken': 'new', 'refreshToken': 'r2'}), 200);
      }
      if (req.headers['authorization'] == 'Bearer new') return http.Response('{"ok":true}', 200);
      return http.Response('{"error":{"code":"TOKEN_EXPIRED","message":"x"}}', 401);
    });
    await Future.wait([Api.I.get('/api/a'), Api.I.get('/api/b'), Api.I.get('/api/c')]);
    expect(refreshes, 1);
    expect(Session.I.signedIn, isTrue);
    expect(Session.I.refreshToken, 'r2');
  });
}

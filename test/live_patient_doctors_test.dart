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
import 'package:medpin_app/screens/patient/patient_doctorchat.dart';
import 'package:medpin_app/screens/patient/patient_doctordetail.dart';
import 'package:medpin_app/screens/patient/patient_doctors.dart';
import 'package:medpin_app/screens/patient/patient_finddoctor.dart';
import 'package:medpin_app/screens/patient/patient_me.dart';

/// The patient's Doctor tab, doctor page, doctor chat, Find a doctor and
/// Profile rendered from real API responses (recorded from the local backend
/// into test/fixtures/live/patient_doctors), with their main actions.

const _sen = '6ac8d0e273298218d8b84066'; // Dr. Arjun Sen
const _mitra = '6ac8d0e4fb653f61fa0676a0'; // Dr. Rina Mitra
const _conv = '6ac8d0e273298218d8b8409d'; // Priya's care thread at City Care
const _location = '6ac8d0e273298218d8b84075'; // City Care Clinic — Salt Lake
const _visit = '6ac8d0e273298218d8b84098'; // Priya's next visit with Dr. Sen

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/patient_doctors/$name.json').readAsStringSync());

/// Requests the screen made: method, path (with and without the query) and the JSON body.
final _calls = <(String, String, Object?)>[];

bool _called(String method, String path) => _calls.any((c) => c.$1 == method && c.$2 == path);
Object? _body(String method, String path) => _calls.lastWhere((c) => c.$1 == method && c.$2 == path).$3;

/// Answers a GET from the recorded fixtures (by path), mutations with small stubs.
Object? _answer(http.Request r) {
  final p = r.url.path;
  if (r.method == 'GET') {
    if (p == '/api/patient/my-doctors') return _fx('my_doctors');
    if (p == '/api/patient/doctors/search') return _fx('search');
    if (p == '/api/patient/doctors/$_sen') return _fx('doctor');
    if (p == '/api/patient/doctors/$_mitra') return _fx('doctor_mitra');
    if (p.startsWith('/api/patient/doctors/') && p.endsWith('/slots')) return _fx('slots');
    if (p == '/api/conversations/$_conv/messages') return _fx('thread');
    if (p == '/api/patient/me') return _fx('me');
    if (p == '/api/patient/care-team') return _fx('care_team');
    if (p == '/api/notifications') return _fx('notifications');
    if (p == '/api/me/support') return {'email': 'help@medpin.in', 'phone': null, 'whatsapp': null};
    return null;
  }
  if (p == '/api/patient/visit-requests') {
    return {
      'request': {'id': 'req-1', 'status': 'scheduled'},
      'appointment': {'id': 'appt-1', 'tokenNo': 3},
    };
  }
  if (p == '/api/patient/consent-code') {
    return {'code': '135790', 'display': '135 790', 'expiresAt': DateTime.now().toUtc().add(const Duration(seconds: 60)).toIso8601String()};
  }
  if (p == '/api/patient/me') return _fx('me');
  if (p == '/api/conversations/$_conv/messages') return {'message': {'id': 'm-1'}, 'aiReply': null};
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
    final body = req.body.isEmpty || !(req.headers['content-type'] ?? '').contains('json') ? null : jsonDecode(req.body);
    _calls.add((req.method, req.url.path + (q.isEmpty ? '' : '?$q'), body));
    _calls.add((req.method, req.url.path, body));
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

Future<void> _pump(WidgetTester t, Widget screen, {String stem = 'Screen', Object? args}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    onGenerateRoute: (s) => s.name == '/' || s.name == stem
        ? MaterialPageRoute(settings: RouteSettings(name: stem, arguments: args), builder: (_) => screen)
        : null,
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
  await t.pump(const Duration(seconds: 25));
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Patient-Doctors lists the care team doctors; Book a visit sends a request', (t) async {
    _serve();
    await _pump(t, const PatientDoctorsScreen(), stem: 'Patient-Doctors');
    expect(_called('GET', '/api/patient/my-doctors'), isTrue);
    expect(find.text('2 doctors caring for you'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Mou Banerjee'), findsNothing); // dietician: listed on Profile instead
    expect(find.text('Diabetes & thyroid · City Care, Salt Lake'), findsOneWidget);
    expect(find.text('Heart · City Care, Salt Lake'), findsOneWidget);
    expect(find.text('2 medicines · 0% taken'), findsOneWidget);
    expect(find.text('Visit details'), findsOneWidget);
    // The shared clinic thread's unread count shows once.
    expect(find.text('3'), findsNWidgets(2)); // Sen's card and the Doctor tab badge

    await _tap(t, find.text('Book a visit'));
    expect(_called('GET', '/api/patient/doctors/$_mitra'), isTrue);
    expect(_called('GET', '/api/patient/doctors/$_mitra/slots?locationId=$_location&next=3'), isTrue);
    expect(find.text('Request visit'), findsOneWidget);
    await _tap(t, find.text('Request visit'));
    expect(_called('POST', '/api/patient/visit-requests'), isTrue);
    final body = _body('POST', '/api/patient/visit-requests') as Map;
    expect(body['doctorId'], _mitra);
    expect(body['locationId'], _location);
    expect(body['slot'], ((_fx('slots') as Map)['slots'] as List).first['startAt']);
    expect(body['visitType'], 'follow_up'); // already her doctor
    // The list refreshes after booking.
    expect(_calls.where((c) => c.$1 == 'GET' && c.$2 == '/api/patient/my-doctors').length, greaterThanOrEqualTo(4));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-FindDoctor lists every doctor; MedPin AI matches and books', (t) async {
    _serve();
    await _pump(t, const PatientFinddoctorScreen(), stem: 'Patient-FindDoctor');
    expect(_called('GET', '/api/patient/doctors/search'), isTrue);
    expect(find.text('2 doctors on MedPin near Salt Lake'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Your doctor'), findsNWidgets(2));
    expect(find.text('₹600'), findsOneWidget);
    expect(find.text('16 yrs · City Care Clinic, Salt Lake'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'Palpitations and high blood pressure');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pump(const Duration(milliseconds: 800));
    await _settle(t);
    expect(find.text('Best matches  1'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen'), findsNothing);

    await _tap(t, find.text('Dr. Rina Mitra'));
    expect(_called('GET', '/api/patient/doctors/$_mitra/slots?locationId=$_location&next=3'), isTrue);
    expect(find.text('Open doctor page'), findsOneWidget);
    await _tap(t, find.text('Request visit'));
    final body = _body('POST', '/api/patient/visit-requests') as Map;
    expect(body['doctorId'], _mitra);
    expect(body['mode'], 'in_clinic');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-DoctorDetail shows the doctor page; to-dos and reschedule call the API', (t) async {
    _serve();
    await _pump(t, const PatientDoctordetailScreen(), stem: 'Patient-DoctorDetail', args: {'doctorId': _sen});
    expect(_called('GET', '/api/patient/doctors/$_sen'), isTrue);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('MBBS, MD · Diabetes & thyroid'), findsOneWidget);
    expect(find.text('In clinic now · replies after the clinic'), findsOneWidget);
    expect(find.text('Upload HbA1c report'), findsOneWidget);
    expect(find.text('City Care Clinic — Salt Lake · Token 04'), findsOneWidget);
    expect(find.text('Follow-up'), findsWidgets);
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('1-0-1 · after food'), findsOneWidget);
    expect(find.text('Walk 30 minutes, 5 days a week. Come back with fasting sugar.'), findsOneWidget);
    expect(find.text('Visits with Dr. Sen'), findsOneWidget);
    expect(find.text('Full record, daily log and tracked vitals'), findsOneWidget);
    expect(find.textContaining('Got your report, thanks.'), findsOneWidget);

    await _tap(t, find.text('Upload HbA1c report'));
    final todo = ((((_fx('doctor') as Map)['nextVisit'] as Map)['todos'] as List).first as Map)['_id'];
    expect(_called('POST', '/api/patient/appointments/$_visit/todos/$todo'), isTrue);
    expect(_body('POST', '/api/patient/appointments/$_visit/todos/$todo'), {'done': true});

    await _tap(t, find.text('Reschedule'));
    expect(_called('GET', '/api/patient/doctors/$_sen/slots?locationId=$_location&next=6'), isTrue);
    await _tap(t, find.text('Move my visit'));
    expect(_body('POST', '/api/patient/appointments/$_visit/reschedule'), {
      'startAt': ((_fx('slots') as Map)['slots'] as List).first['startAt'],
    });
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-DoctorChat shows the clinic thread and sends a message', (t) async {
    _serve();
    await _pump(t, const PatientDoctorchatScreen(), stem: 'Patient-DoctorChat', args: {'doctorId': _sen, 'conversationId': _conv});
    expect(_called('GET', '/api/conversations/$_conv/messages'), isTrue);
    expect(_called('POST', '/api/conversations/$_conv/read'), isTrue);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('Got your report, thanks. We will adjust the dose when you come in.'), findsOneWidget);
    expect(find.text('Should I take the tablet before or after food?'), findsOneWidget);
    expect(find.text('Type 2 diabetes mellitus, Polycystic ovary syndrome'), findsOneWidget); // shared record card
    expect(find.textContaining('Token 04'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'See you at 5');
    await t.pump();
    await _tap(t, find.bySemanticsLabel('Send'));
    expect(_body('POST', '/api/conversations/$_conv/messages'), {'text': 'See you at 5'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Args from other screens: specialty, visit and thread links', (t) async {
    _serve();
    await _pump(t, const PatientFinddoctorScreen(), stem: 'Patient-FindDoctor', args: {'specialty': 'heart'});
    expect(find.text('Heart  1'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen'), findsNothing);
    await _tearDown(t);

    _serve();
    await _pump(t, const PatientDoctordetailScreen(), stem: 'Patient-DoctorDetail', args: {'appointmentId': _visit});
    expect(_called('GET', '/api/patient/doctors/$_sen'), isTrue);
    expect(find.text('Upload HbA1c report'), findsOneWidget);
    await _tearDown(t);

    _serve();
    await _pump(t, const PatientDoctorchatScreen(), stem: 'Patient-DoctorChat', args: {'conversationId': _conv});
    expect(_called('GET', '/api/conversations/$_conv/messages'), isTrue);
    expect(_called('POST', '/api/patient/conversations'), isFalse);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Me shows the profile; reminders, sharing and log out call the API', (t) async {
    _serve();
    await _pump(t, const PatientMeScreen(), stem: 'Patient-Me');
    expect(_called('GET', '/api/patient/me'), isTrue);
    expect(_called('GET', '/api/patient/care-team'), isTrue);
    expect(_called('POST', '/api/patient/consent-code'), isTrue);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('+91 92305 92842'), findsOneWidget);
    expect(find.text('29 yrs · Female'), findsOneWidget);
    expect(find.text('135 790'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('Sulfa drugs'), findsOneWidget);
    expect(find.text('158 cm · 68.5 kg · BMI 27.4'), findsOneWidget);
    expect(find.text('Rohit Sharma · +91 98765 00000'), findsOneWidget);
    expect(find.text('Mou Banerjee'), findsOneWidget);
    expect(find.text('Heart · City Care Clinic'), findsOneWidget);

    await _tap(t, find.text('Medicine reminders'));
    expect(_body('PATCH', '/api/patient/me'), {
      'settings': {'medReminders': false},
    });

    await _tap(t, find.text('Dr. Rina Mitra'));
    await _tap(t, find.text('Daily log only'));
    await _tap(t, find.text('Save'));
    expect(_body('PATCH', '/api/patient/care-team/$_mitra'), {'accessLevel': 'daily_log_only'});

    await _tap(t, find.text('Log out').first);
    await _tap(t, find.widgetWithText(Container, 'Log out').last);
    await _settle(t);
    expect(_called('POST', '/api/auth/logout'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
  testWidgets('Patient-Me health rows: Conditions / Allergies have their own sheet; others open their section', (t) async {
    _serve();
    await _pump(t, const PatientMeScreen(), stem: 'Patient-Me');

    // Conditions: own sheet, add a common one, save → PATCH conditions (old entries kept as sent).
    await _tap(t, find.text('Conditions'));
    expect(find.text('Edit details'), findsNothing);
    expect(find.text('Add a condition'), findsOneWidget);
    await _tap(t, find.text('Thyroid'));
    await _tap(t, find.text('Save'));
    final conds = (_body('PATCH', '/api/patient/me') as Map)['conditions'] as List;
    expect(conds.first['name'], 'Type 2 diabetes');
    expect(conds.last, {'name': 'Thyroid'});

    // Allergies: remove the one there, type a new one, save.
    await _tap(t, find.text('Allergies'));
    await _tap(t, find.bySemanticsLabel('Remove Sulfa drugs').first);
    await t.enterText(find.byType(TextField).last, 'Penicillin');
    await _settle(t);
    await _tap(t, find.text('Save'));
    expect((_body('PATCH', '/api/patient/me') as Map)['allergies'], [
      {'allergen': 'Penicillin'},
    ]);

    // Blood group opens Edit details on that section.
    await _tap(t, find.text('Blood group'));
    expect(find.text('Edit details'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Blood group').last, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == MP.primarySoft)),
      findsWidgets,
    );
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

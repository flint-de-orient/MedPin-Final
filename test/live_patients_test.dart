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
import 'package:medpin_app/screens/doctor/doctor_history.dart';
import 'package:medpin_app/screens/doctor/doctor_messages.dart';
import 'package:medpin_app/screens/doctor/doctor_patients.dart';
import 'package:medpin_app/screens/doctor/doctor_patients_search.dart';
import 'package:medpin_app/screens/doctor/patient_profile.dart';
import 'package:medpin_app/screens/doctor/patient_profile_desk.dart';
import 'package:medpin_app/screens/doctor/patient_thread.dart';
import 'package:medpin_app/screens/doctor/pp_prescriptions.dart';
import 'package:medpin_app/screens/doctor/pp_summary.dart';
import 'package:medpin_app/screens/doctor/pp_tests.dart';
import 'package:medpin_app/screens/doctor/pp_treatment.dart';

/// The doctor's patients, profile tabs, history and messages rendered from
/// real API responses (recorded from the local backend into
/// test/fixtures/live/patients), with one action per screen.

const _pid = '6ac8bbcee42c9f0836e9857c'; // Priya Sharma
const _conv = '6ac8bbcee42c9f0836e9858b'; // Priya's care thread

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/patients/$name.json').readAsStringSync());

/// Requests the screen made: "METHOD path?query" and the JSON body.
final _calls = <(String, String, Object?)>[];

bool _called(String method, String path) => _calls.any((c) => c.$1 == method && c.$2 == path);
Object? _body(String method, String path) => _calls.lastWhere((c) => c.$1 == method && c.$2 == path).$3;

/// Answers a GET from the recorded fixtures (by path), mutations with small stubs.
Object? _answer(http.Request r) {
  final p = r.url.path;
  if (r.method == 'GET') {
    if (p == '/api/patients') return _fx(r.url.queryParameters['q'] != null ? 'search' : 'patients');
    if (p == '/api/patients/$_pid') return _fx('patient');
    for (final k in ['vitals', 'lab-results', 'visits', 'prescriptions', 'adherence', 'records']) {
      if (p == '/api/patients/$_pid/$k') return _fx(k == 'lab-results' ? 'labs' : k);
    }
    if (p == '/api/patients/$_pid/trends/HbA1c') return _fx('trend');
    if (p == '/api/alerts') return _fx('alerts');
    if (p == '/api/history') return _fx('history');
    if (p == '/api/inbox') return _fx(r.url.queryParameters['type'] == 'direct' ? 'inbox_direct' : 'inbox_all');
    if (p == '/api/inbox/contacts') return _fx('contacts');
    if (p.startsWith('/api/conversations/') && p.endsWith('/messages')) return _fx('thread');
    return null;
  }
  if (p == '/api/inbox') return {'id': _conv};
  if (p == '/api/consultations') return {'id': 'consult-1'};
  if (p == '/api/exports') return {'id': 'export-1', 'url': 'http://localhost:4000/files/exports/x.pdf'};
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
    _calls.add((req.method, req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
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
  await t.pump(const Duration(seconds: 20));
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Doctor-Patients lists patients with counts; a filter refetches', (t) async {
    _serve();
    await _pump(t, const DoctorPatientsScreen(), stem: 'Doctor-Patients');
    final all = (((_fx('patients') as Map)['counts'] as Map)['all'] as num).toInt();
    expect(find.text('$all patients · all branches'), findsOneWidget);
    for (final p in (_fx('patients') as Map)['items'] as List) {
      expect(find.text((p as Map)['name'] as String), findsWidgets);
    }
    expect(find.text('29 F · +91 98765 43210'), findsOneWidget);
    expect(find.text('Type 2 diabetes · PCOS'), findsOneWidget);
    await _tap(t, find.text('Follow-up due'));
    expect(_called('GET', '/api/patients?filter=follow_up_due&sort=recent&limit=50'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-Patients-Search searches by mobile digits', (t) async {
    _serve();
    await _pump(t, const DoctorPatientsSearchScreen(), stem: 'Doctor-Patients-Search');
    await t.enterText(find.byType(TextField), '98765');
    await t.pump(const Duration(milliseconds: 350));
    await _settle(t);
    expect(_called('GET', '/api/patients?q=98765&limit=30'), isTrue);
    expect(find.text('1 MATCH FOR “98765”'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('PP-Summary shows the record and abnormal findings', (t) async {
    _serve();
    await _pump(t, const PpSummaryScreen(), stem: 'PP-Summary', args: {'patientId': _pid});
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('29 yrs · Female · +91 98765 43210'), findsOneWidget);
    expect(find.text('Allergy: Sulfa drugs'), findsOneWidget);
    expect(find.text('Abnormal findings'), findsOneWidget);
    expect(find.text('5 from 3 reports'), findsOneWidget);
    expect(find.text('LDL cholesterol'), findsOneWidget);
    expect(find.textContaining('Ref below 100 · Lipid profile'), findsOneWidget);
    expect(find.text('Vitals'), findsOneWidget);
    // Record vitals opens Consult-Vitals for this patient.
    await _tap(t, find.text('Record'));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('PP-Prescriptions lists prescriptions; a filter refetches', (t) async {
    _serve();
    await _pump(t, const PpPrescriptionsScreen(), stem: 'PP-Prescriptions', args: {'patientId': _pid});
    expect(find.text('All · 1'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen · City Care Clinic'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.textContaining('2 medicines · 2 tests · Follow-up'), findsOneWidget);
    await _tap(t, find.text('This clinic · 1'));
    expect(_called('GET', '/api/patients/$_pid/prescriptions?filter=this_clinic'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('PP-Tests lists results; opening one is not marking it reviewed', (t) async {
    _serve();
    await _pump(t, const PpTestsScreen(), stem: 'PP-Tests', args: {'patientId': _pid});
    expect(find.text('All · 3'), findsOneWidget);
    expect(find.text('Abnormal · 3'), findsOneWidget);
    expect(find.text('Lipid profile'), findsOneWidget);
    expect(find.text('2 high'), findsWidgets);
    await _tap(t, find.text('Lipid profile'));
    // Reviewing is the doctor's deliberate "Mark as reviewed" on the report, not a tap on the row.
    expect(_called('POST', '/api/lab-results/6ac8bbd08adea6a429a731f9/reviewed'), isFalse);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('PP-Treatment shows medicines and adherence; Edit saves the plan', (t) async {
    _serve();
    await _pump(t, const PpTreatmentScreen(), stem: 'PP-Treatment', args: {'patientId': _pid});
    expect(find.text('YOUR PLAN'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('0%'), findsWidgets);
    expect(find.text('No instructions yet'), findsOneWidget);
    await _tap(t, find.text('Edit'));
    await t.enterText(find.byType(TextField).first, 'Cut refined carbs');
    await t.drag(find.text('Treatment plan').last, const Offset(0, -600));
    await _settle(t);
    await _tap(t, find.text('Save plan'));
    expect(_called('PUT', '/api/patients/$_pid/treatment-plan'), isTrue);
    final body = _body('PUT', '/api/patients/$_pid/treatment-plan') as Map;
    expect(body['sections'], [
      {'category': 'diet', 'items': ['Cut refined carbs']},
    ]);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Profile shows the record; Save draft starts and saves a consultation', (t) async {
    _serve();
    await _pump(t, const PatientProfileScreen(), stem: 'Patient-Profile', args: {'patientId': _pid});
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Priya shares her full record with City Care Clinic. She controls this.'), findsOneWidget);
    expect(find.text('Covered by Mou Banerjee'), findsOneWidget);
    expect(find.text('HbA1c history'), findsOneWidget);
    expect(find.text('Chest tightness, hard to breathe.'), findsOneWidget);
    expect(find.text('Draft · Dr. Arjun Sen'), findsOneWidget);
    await _tap(t, find.text('HbA1c').last);
    await _tap(t, find.text('Save draft'));
    expect(_called('POST', '/api/consultations'), isTrue);
    expect(_called('PATCH', '/api/consultations/consult-1'), isTrue);
    final body = _body('PATCH', '/api/consultations/consult-1') as Map;
    expect(body['labOrders'], [
      {'testName': 'HbA1c', 'source': 'typed', 'selected': true},
    ]);
    expect((body['diagnoses'] as List).map((d) => (d as Map)['name']), ['Type 2 diabetes', 'PCOS']);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Profile-Desk: Message patient opens the care thread', (t) async {
    _serve();
    await _pump(t, const PatientProfileDeskScreen(), stem: 'Patient-Profile-Desk', args: {'patientId': _pid});
    expect(find.text('Desk care'), findsOneWidget);
    expect(find.text("Opens Priya's conversation"), findsOneWidget);
    await _tap(t, find.text('Message patient'));
    expect(_called('POST', '/api/inbox'), isTrue);
    expect(_body('POST', '/api/inbox'), {'patientId': _pid});
    expect(find.byType(PatientThreadScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-History lists past appointments; Download posts an export', (t) async {
    _serve();
    await _pump(t, const DoctorHistoryScreen(), stem: 'Doctor-History');
    expect(_called('GET', '/api/history?period=last_3_months'), isTrue);
    expect(find.text('Aisha Khan'), findsWidgets);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Missed'), findsWidgets);
    await _tap(t, find.text('Download'));
    expect(find.textContaining('all statuses · 18 appointments'), findsOneWidget);
    await _tap(t, find.text('CSV'));
    await _tap(t, find.text('Download CSV'));
    expect(_called('POST', '/api/exports'), isTrue);
    final body = _body('POST', '/api/exports') as Map;
    expect(body['kind'], 'appointment_history');
    expect(body['format'], 'csv');
    expect(body['emailCopy'], true);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-Messages shows the urgent chat and the inbox', (t) async {
    _serve();
    await _pump(t, const DoctorMessagesScreen(), stem: 'Doctor-Messages');
    expect(find.text('5 unread · 1 urgent'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('URGENT · PATIENT'), findsOneWidget);
    expect(find.text('Aisha Khan'), findsOneWidget);
    expect(find.text('Patient · Type 2 diabetes'), findsWidgets);
    await _tap(t, find.text('Aisha Khan'));
    expect(_called('GET', '/api/conversations/6ac8bbd18adea6a429a7343b/messages'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-Messages-New: picking a colleague opens a direct thread', (t) async {
    _serve();
    await _pump(
      t,
      Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Nav.go(c, 'Doctor-Messages-New'), child: const Text('open'))))),
    );
    await _tap(t, find.text('open'));
    expect(find.text('Rahul Das'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    await _tap(t, find.text('Dr. Rina Mitra'));
    expect(_body('POST', '/api/inbox'), {'userId': '6ac8bbd08adea6a429a73197'});
    expect(find.byType(PatientThreadScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Thread shows messages, marks read and sends a reply', (t) async {
    _serve();
    await _pump(t, const PatientThreadScreen(), stem: 'Patient-Thread', args: {'conversationId': _conv});
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Chest tightness, hard to breathe.'), findsOneWidget);
    expect(find.text('Should I take the tablet before or after food?'), findsOneWidget);
    expect(find.textContaining('Next visit'), findsOneWidget);
    expect(_called('POST', '/api/conversations/$_conv/read'), isTrue);
    await t.enterText(find.byType(TextField), 'After food, please.');
    await t.pump();
    await _tap(t, find.bySemanticsLabel('Send reply'));
    final sent = _body('POST', '/api/conversations/$_conv/messages') as Map;
    expect(sent['text'], 'After food, please.');
    expect('${sent['clientId']}', isNotEmpty, reason: 'each send has its own id (a retry is saved once)');
    // Long-press → Hide.
    await t.longPress(find.text('Should I take the tablet before or after food?'));
    await _settle(t);
    await _tap(t, find.text('Hide'));
    expect(_called('POST', '/api/conversations/$_conv/messages/6ac8bbd18adea6a429a7344d/hide'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

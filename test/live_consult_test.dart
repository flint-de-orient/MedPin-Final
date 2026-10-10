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
import 'package:medpin_app/screens/doctor/common_d5.dart';

/// The consultation screens (Consult-*, Add-Patient*) rendered from real API
/// responses recorded from the local backend into test/fixtures/live/consult.
Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

Map<String, dynamic> _fx(String name) =>
    jsonDecode(File('test/fixtures/live/consult/$name.json').readAsStringSync()) as Map<String, dynamic>;
Object? _data(String name) => _fx(name)['data'];

/// Requests the screens sent: (method, path, query, body).
final _sent = <(String, String, Map<String, String>, Object?)>[];

/// Signs the fake session in and answers with [route] ('GET /api/…' → data).
void _serve(Object? Function(http.Request req) route) {
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = (_data('session') as Map).cast<String, dynamic>();
  _sent.clear();
  Api.I.client = MockClient((req) async {
    _sent.add((req.method, req.url.path, req.url.queryParameters, req.body.isEmpty ? null : jsonDecode(req.body)));
    final res = route(req);
    if (res == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked"}}', 404);
    return http.Response(jsonEncode(res), 200, headers: {'content-type': 'application/json'});
  });
}

List<(String, String, Map<String, String>, Object?)> _calls(String method, String path) =>
    [for (final s in _sent) if (s.$1 == method && s.$2 == path) s];

Future<void> _settle(WidgetTester t, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

/// Opens [stem] with [args] from a host screen (as Nav.go does in the app).
/// The sheet's result lands in [result].
Future<void> _open(WidgetTester t, String stem, {Object? args, List<Object?>? result}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: medpinTheme(),
      home: Builder(
        builder:
            (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final r = await Nav.go<Object?>(c, stem, args: args);
                    result?.add(r);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await _settle(t);
}

Future<void> _tearDown(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 7));
}

Future<void> _tapText(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).last);
  await t.pump();
  await t.tap(find.text(text).last);
  await t.pump();
  await _settle(t);
}

void main() {
  final consult = _fx('consult');
  final consultId = ((consult['data'] as Map)['consultation'] as Map)['id'] as String;
  final blank = _fx('consult_blank');
  final blankId = ((blank['data'] as Map)['consultation'] as Map)['id'] as String;

  /// The backend for a consultation: the draft, its checks and suggestions.
  Object? draftRoutes(http.Request r) {
    final p = r.url.path;
    if (r.method == 'GET' && p == '/api/consultations/$consultId') return _data('consult');
    if (r.method == 'GET' && p == '/api/consultations/$consultId/checks') return _data('checks');
    if (r.method == 'GET' && p == '/api/consultations/$consultId/suggestions') return _data('suggestions');
    if (r.method == 'PATCH' && p == '/api/consultations/$consultId') return _data('patch');
    if (r.method == 'POST' && p == '/api/consultations/$consultId/issue') return _data('issue');
    if (r.method == 'GET' && p == '/api/consultations/$blankId') return _data('consult_blank');
    if (r.method == 'GET' && p == '/api/consultations/$blankId/checks') return _data('checks_blank');
    if (r.method == 'GET' && p == '/api/consultations/$blankId/suggestions') return _data('suggestions_blank');
    if (r.method == 'PATCH' && p == '/api/consultations/$blankId') return _data('start_blank');
    if (r.method == 'POST' && p == '/api/consultations/$blankId/vitals') return {'id': 'v1'};
    if (r.method == 'GET' && p == '/api/catalog/medicines') {
      return r.url.queryParameters['q'] == 'Atorvastatin' ? _data('medicines_ator') : _data('medicines_glim');
    }
    if (r.method == 'GET' && p == '/api/catalog/icd') return _data('icd');
    return null;
  }

  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Consult-Pick: waiting now, recent, search, start from the queue', (t) async {
    _serve((r) {
      if (r.url.path == '/api/consultations/pick') {
        return r.url.queryParameters['q'] == 'Priya' ? _data('pick_q') : _data('pick');
      }
      if (r.method == 'POST' && r.url.path == '/api/consultations') return _data('start_blank');
      return draftRoutes(r);
    });
    await _open(t, 'Consult-Pick');
    final pick = _data('pick') as Map;
    final waiting = (pick['waiting'] as List).cast<Map>();
    expect(find.text('WAITING NOW'), findsOneWidget);
    expect(find.text((waiting.first['patient'] as Map)['name'] as String), findsWidgets);
    expect(find.text(waiting.first['token'] as String), findsOneWidget);
    expect(find.textContaining('+91 98311 20769'), findsWidgets);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Rahul Das'), findsOneWidget);
    expect(t.takeException(), isNull);

    // Typing searches the server.
    await t.enterText(find.byType(TextField).first, 'Priya');
    await t.pump(const Duration(milliseconds: 350));
    await _settle(t);
    expect(_calls('GET', '/api/consultations/pick').last.$3['q'], 'Priya');
    expect(find.text('PATIENTS'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Rahul Das'), findsNothing);

    // Clear and start a consultation for the first waiting patient.
    await t.enterText(find.byType(TextField).first, '');
    await t.pump();
    await t.tap(find.text((waiting.first['patient'] as Map)['name'] as String).first);
    await t.pump();
    await _settle(t);
    final post = _calls('POST', '/api/consultations');
    expect(post, hasLength(1));
    expect((post.single.$4 as Map)['appointmentId'], waiting.first['appointmentId']);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-NotFound: the typed number and close matches', (t) async {
    _serve((r) => r.url.path == '/api/consultations/pick' ? _data('pick_close') : null);
    await _open(t, 'Consult-NotFound', args: {'query': '98765 43211'});
    expect(_calls('GET', '/api/consultations/pick').single.$3['q'], '987654');
    expect(find.text('No patient with this number'), findsOneWidget);
    expect(find.text('CLOSE MATCH · CHECK BEFORE ADDING'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('29 F · +91 98765 4321'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Page: the draft live, save draft, generate prescription', (t) async {
    _serve(draftRoutes);
    await _open(t, 'Consult-Page', args: {'consultationId': consultId});
    expect(find.text('Test Consult'), findsOneWidget);
    expect(find.text('40 F'), findsOneWidget);
    expect(find.text('Allergy: Sulfa drugs'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsWidgets);
    expect(find.text('HbA1c 7.4% ↑'), findsOneWidget);
    expect(find.text('132/86'), findsOneWidget);
    expect(find.text('152'), findsOneWidget);
    expect(find.textContaining('Recorded by you'), findsOneWidget);
    expect(find.text('Tired for two weeks. Sugar readings high.'), findsOneWidget);
    expect(find.text('Type 2 diabetes mellitus'), findsOneWidget);
    expect(find.text('E11.9'), findsOneWidget);
    expect(find.text('3 added'), findsOneWidget);
    expect(find.text('Glimepiride 1 mg'), findsOneWidget);
    expect(find.text('1-0-0 · before breakfast'), findsOneWidget);
    expect(find.text('Sulfa drugs allergy · sulfonylurea'), findsOneWidget);
    expect(find.textContaining('Catalog strengths for Metformin'), findsOneWidget);
    expect(find.text('Telmisartan 40 mg'), findsOneWidget);
    expect(find.text('Prescribed once for Type 2 diabetes mellitus'), findsWidgets);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Post-prandial glucose'), findsOneWidget);
    expect(find.text('Walk 30 minutes, 5 days a week.'), findsOneWidget);
    expect(find.textContaining('· draft saved'), findsOneWidget);
    expect(t.takeException(), isNull);

    // A lab chip saves the lab orders.
    await _tapText(t, 'Post-prandial glucose');
    await t.pump(const Duration(seconds: 1));
    await _settle(t);
    final labs = _calls('PATCH', '/api/consultations/$consultId').last.$4 as Map;
    expect((labs['labOrders'] as List).any((l) => l['testName'] == 'Post-prandial glucose' && l['selected'] == true), isTrue);

    await t.tap(find.text('Save draft'));
    await t.pump();
    await _settle(t);
    final saved = _calls('PATCH', '/api/consultations/$consultId').last.$4 as Map;
    expect(saved['chiefComplaint'], 'Tired for two weeks. Sugar readings high.');
    expect((saved['medications'] as List), hasLength(3));
    expect(find.text('Draft saved'), findsOneWidget);

    await t.tap(find.text('Generate prescription'));
    await t.pump();
    await _settle(t, 10);
    expect(_calls('POST', '/api/consultations/$consultId/issue'), hasLength(1));
    expect(find.text('Prescription generated'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Blank: new patient, vitals recorded on save', (t) async {
    _serve(draftRoutes);
    await _open(t, 'Consult-Blank', args: {'consultationId': blankId, 'justAdded': true});
    expect(find.text('Test Blank'), findsOneWidget);
    expect(find.text('Male · New patient · added just now'), findsOneWidget);
    expect(find.text('What brings Test in today?'), findsOneWidget);
    expect(find.text('Send Test an upload link'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.enterText(find.byType(TextField).at(0), '120/80');
    await t.enterText(find.byType(TextField).at(1), '76');
    await t.enterText(find.byType(TextField).at(8), 'Fever for 3 days');
    await t.pump(const Duration(seconds: 1));
    await _settle(t);
    expect((_calls('PATCH', '/api/consultations/$blankId').last.$4 as Map)['chiefComplaint'], 'Fever for 3 days');

    await t.tap(find.text('Save draft'));
    await t.pump();
    await _settle(t);
    final v = _calls('POST', '/api/consultations/$blankId/vitals').single.$4 as Map;
    expect(v['bpSystolic'], 120);
    expect(v['bpDiastolic'], 80);
    expect(v['pulse'], 76);
    expect(find.text('Draft saved'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Dosage: catalog strengths, returns the prescription line', (t) async {
    _serve(draftRoutes);
    final result = <Object?>[];
    await _open(
      t,
      'Consult-Dosage',
      args: {
        'item': {'name': 'Glimepiride', 'strength': '2 mg', 'dose': {'morning': 1, 'afternoon': 0, 'night': 0}},
        'reason': 'Prescribed once for Type 2 diabetes mellitus',
      },
      result: result,
    );
    expect(_calls('GET', '/api/catalog/medicines').single.$3['q'], 'Glimepiride');
    expect(find.text('Glimepiride'), findsOneWidget);
    expect(find.text('Tablet · sulfonylurea · prescribed once for Type 2 diabetes mellitus'), findsOneWidget);
    for (final s in ['1 mg', '2 mg', '4 mg']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Quantity: 30 tablets'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tapText(t, 'Add to prescription');
    await t.pump(const Duration(milliseconds: 400));
    final r = result.single as D5MedResult;
    expect(r.name, 'Glimepiride 2 mg');
    expect(r.item!['dose'], {'morning': 1, 'afternoon': 0, 'night': 0});
    expect(r.item!['duration'], {'value': 30, 'unit': 'days'});
    expect(r.item!['medicineId'], isNotNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Voice: reads the typed line', (t) async {
    _serve(draftRoutes);
    final result = <Object?>[];
    await _open(t, 'Consult-Voice', args: {'text': 'Atorvastatin 20 at night for 3 months'}, result: result);
    expect(find.text('Atorvastatin 20 mg'), findsOneWidget);
    expect(find.text('0-0-1'), findsOneWidget);
    expect(find.text('3 months'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tapText(t, 'Add medicine');
    await t.pump(const Duration(milliseconds: 400));
    final r = result.single as D5MedResult;
    expect(r.item!['name'], 'Atorvastatin');
    expect(r.item!['entrySource'], 'voice');
    await _tearDown(t);
  });

  testWidgets('Add-Patient: lookup, phone OTP with the test code, register', (t) async {
    _serve((r) {
      if (r.url.path == '/api/patients/lookup') return _data('lookup_new');
      if (r.url.path == '/api/patients/phone-otp') return {'sent': true, 'maskedPhone': '+91 90000 •••99', 'resendInSec': 30, 'devCode': '123456'};
      if (r.method == 'POST' && r.url.path == '/api/patients') {
        return {'id': 'p-new', 'name': 'Test Add', 'phone': '9000055599', 'gender': 'female', 'age': 30};
      }
      return null;
    });
    await _open(t, 'Add-Patient');
    await t.enterText(find.byType(TextField).at(0), 'Test Add');
    await t.enterText(find.byType(TextField).at(1), '30');
    await t.enterText(find.byType(TextField).at(2), '90000 55599');
    await t.pump();
    await _tapText(t, 'Verify');
    await t.pump(const Duration(milliseconds: 400));
    expect(_calls('GET', '/api/patients/lookup').single.$3['phone'], '9000055599');
    expect((_calls('POST', '/api/patients/phone-otp').single.$4 as Map)['phone'], '9000055599');
    expect(find.text('Test code: 123456'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '123456');
    await t.tap(find.text('Verify').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Verified'), findsOneWidget);
    await _tapText(t, 'Add patient');
    final body = _calls('POST', '/api/patients').single.$4 as Map;
    expect(body['name'], 'Test Add');
    expect(body['ageYears'], 30);
    expect(body['gender'], 'female');
    expect(body['otpCode'], '123456');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Add-Patient-Existing: links with the consent code', (t) async {
    _serve((r) => r.url.path == '/api/patients/link' ? (_data('lookup_linked') as Map)['patient'] : null);
    await _open(t, 'Add-Patient-Existing', args: {'phone': '9876543210'});
    expect(find.text("6 digits, from the patient's phone for +91 98765 43210"), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '482913');
    await t.pump();
    await _tapText(t, 'Link patient');
    final body = _calls('POST', '/api/patients/link').single.$4 as Map;
    expect(body, {'phone': '9876543210', 'consentCode': '482913'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-QuickAdd: verifies the number, registers the patient and starts the consultation', (t) async {
    _serve((r) {
      if (r.url.path == '/api/patients/lookup') return _data('lookup_new');
      if (r.url.path == '/api/patients/phone-otp') return {'sent': true, 'maskedPhone': '+91 90000 •••02', 'resendInSec': 30, 'devCode': '654321'};
      if (r.method == 'POST' && r.url.path == '/api/patients') {
        return {'id': (_data('start_blank') as Map)['patientId'], 'name': 'Test Blank', 'gender': 'male', 'age': 33};
      }
      if (r.method == 'POST' && r.url.path == '/api/consultations') return _data('start_blank');
      return draftRoutes(r);
    });
    await _open(t, 'Consult-QuickAdd', args: {'query': '90000 55502'});
    expect(find.text('Carried over from your search.'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    await t.enterText(find.byType(TextField).at(1), 'Test Blank');
    await t.enterText(find.byType(TextField).at(2), '33');
    await t.pump();
    await _tapText(t, 'Add and start consultation');
    await t.pump(const Duration(milliseconds: 400));
    // The patient reads out the code sent to their phone.
    expect(_calls('POST', '/api/patients'), isEmpty, reason: 'nothing is registered before the number is verified');
    expect((_calls('POST', '/api/patients/phone-otp').single.$4 as Map)['phone'], '9000055502');
    await t.enterText(find.byType(TextField).last, '654321');
    await t.tap(find.text('Verify').last);
    await _settle(t);
    final body = _calls('POST', '/api/patients').single.$4 as Map;
    expect(body, {'name': 'Test Blank', 'phone': '9000055502', 'gender': 'male', 'ageYears': 33, 'otpCode': '654321'});
    expect(_calls('POST', '/api/consultations'), hasLength(1));
    expect(find.text('Male · New patient · added just now'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  test('typed and spoken medicine lines are read', () {
    final a = D5Live.parse('Metformin 500 twice daily');
    expect(a['name'], 'Metformin');
    expect(a['strength'], '500 mg');
    expect(a['dose'], {'morning': 1, 'afternoon': 0, 'night': 1});
    final b = D5Live.parse('Glimepiride one mg, once in the morning before breakfast, for thirty days');
    expect(b['strength'], '1 mg');
    expect(b['dose'], {'morning': 1, 'afternoon': 0, 'night': 0});
    expect(b['instructions'], 'before breakfast');
    expect(b['duration'], {'value': 30, 'unit': 'days'});
    final c = D5Live.parse('Vitamin D3 60,000 IU once a week on Sunday for 8 weeks');
    expect(c['name'], 'Vitamin D3');
    expect(c['strength'], '60000 IU');
    expect(c['frequency'], 'weekly');
    expect(c['weekday'], 'sun');
    expect(D5Live.doseText(c), 'Once a week · Sunday');
    expect(D5Live.durationText(c['duration']), '8 weeks');
  });
}

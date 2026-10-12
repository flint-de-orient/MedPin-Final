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
import 'package:medpin_app/screens/patient/med_cart.dart';
import 'package:medpin_app/screens/patient/med_pharmacy.dart';
import 'package:medpin_app/screens/patient/patient_medicines.dart';
import 'package:medpin_app/screens/patient/patient_records.dart';
import 'package:medpin_app/screens/patient/records_review.dart';

/// Patient records, medicines, cart and pharmacy rendered from real API
/// responses (recorded from the local backend into
/// test/fixtures/live/patient_records), with the actions each screen posts.

const _labId = '6ac8d26ec0d20a47471fe875'; // Lipid profile
const _rxId = '6ac8d12f316d92de32637d72'; // Dr. Sen's prescription
const _uploadId = '6ac8d257c0d20a47471fe841'; // the uploaded report (upload.json)
const _sen = '6ac8d12d5e6ed8754976cfb1';
const _mitra = '6ac8d12f316d92de32637cc7';

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/patient_records/$name.json').readAsStringSync());

final _calls = <(String, String, Object?)>[];

bool _called(String method, String path) => _calls.any((c) => c.$1 == method && c.$2 == path);
Object? _body(String method, String path) => _calls.lastWhere((c) => c.$1 == method && c.$2 == path).$3;

Object? _answer(http.Request r) {
  final p = r.url.path;
  const base = '/api/patient';
  if (r.method == 'GET') {
    if (p == '$base/records') return _fx('records');
    if (p == '$base/records/$_labId') return _fx('record_lab');
    if (p == '$base/records/$_rxId') return _fx('record_rx');
    if (p == '$base/my-doctors') return _fx('my_doctors');
    if (p == '$base/medicines') return _fx(r.url.queryParameters['status'] == 'past' ? 'medicines_past' : 'medicines');
    if (p == '$base/doses') return _fx('doses');
    if (p == '$base/cart') return _fx('cart');
    if (p == '$base/orders') return _fx('orders');
    if (p == '$base/pharmacies/quotes') return _fx(r.url.queryParameters['mode'] == 'pickup' ? 'quotes_pickup' : 'quotes_delivery');
    return null;
  }
  if (p.startsWith('$base/cart/items')) return _fx('cart');
  if (p == '$base/orders') return _fx('order');
  if (p.startsWith('$base/doses/')) return {'status': 'taken', 'takenAt': '2026-10-09T03:15:00.000Z'};
  if (p.endsWith('/split')) return [];
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
    Object? body;
    try {
      body = req.body.isEmpty ? null : jsonDecode(req.body);
    } catch (_) {}
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

  testWidgets('Patient-Records lists records by month; filters; View shares a record', (t) async {
    _serve();
    await _pump(t, const PatientRecordsScreen(), stem: 'Patient-Records');
    expect(_called('GET', '/api/patient/records'), isTrue);
    expect(find.text('All · 4'), findsOneWidget);
    expect(find.text('Prescriptions · 2'), findsOneWidget);
    expect(find.text('Tests · 2'), findsOneWidget);
    expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    expect(find.text('Lipid profile'), findsOneWidget);
    expect(find.text('Bad cholesterol (LDL) and triglycerides are high. Good cholesterol is normal.'), findsOneWidget);
    expect(find.text('2 high'), findsOneWidget);
    expect(find.text('Cholesterol prescription'), findsOneWidget);

    await _tap(t, find.text('Tests · 2'));
    expect(find.text('Cholesterol prescription'), findsNothing);
    expect(find.text('Kidney function (KFT)'), findsOneWidget);

    await _tap(t, find.text('View').first); // Lipid profile is first under Tests
    expect(_called('GET', '/api/patient/records/$_labId'), isTrue);
    expect(find.text('LDL cholesterol'), findsOneWidget);
    expect(find.text('158 mg/dL'), findsOneWidget);
    expect(find.text('Shared with'), findsOneWidget);
    // Shared with Dr. Mitra already; add Dr. Sen.
    await _tap(t, find.text('Dr. Arjun Sen'));
    expect((_body('POST', '/api/patient/records/$_labId/share') as Map)['userIds'], unorderedEquals([_mitra, _sen]));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Records {recordId} opens that record', (t) async {
    _serve();
    await _pump(t, const PatientRecordsScreen(), stem: 'Patient-Records', args: {'recordId': _rxId});
    await _settle(t);
    expect(_called('GET', '/api/patient/records/$_rxId'), isTrue);
    expect(find.text('Delete record'), findsOneWidget);
    await _tap(t, find.text('Delete record'));
    await _tap(t, find.text('Delete record').last);
    expect(_called('DELETE', '/api/patient/records/$_rxId'), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Records-Review shows the tests read from the upload and saves the kept ones', (t) async {
    _serve();
    final up = (_fx('upload') as Map).cast<String, dynamic>();
    await _pump(t, const RecordsReviewScreen(), stem: 'Records-Review', args: {
      'record': up['record'],
      'extracted': up['extracted'],
      'shareWith': [_mitra],
    });
    expect(find.textContaining('We found 2 tests in this file.', findRichText: true), findsOneWidget);
    expect(find.text('Suraksha Diagnostics'), findsWidgets);
    expect(find.text('Collected 30 Sep 2026'), findsOneWidget);
    expect(find.text('1 FILE · 3 PAGES'), findsOneWidget);
    expect(find.text('Pages 1–2'), findsOneWidget);
    expect(find.text('Kidney function (KFT)'), findsOneWidget);
    expect(find.text('1 high'), findsOneWidget);
    expect(find.text('Save 2 records'), findsOneWidget);

    await _tap(t, find.text('Kidney function (KFT)'));
    expect(find.text('Save 1 record'), findsOneWidget);
    await _tap(t, find.text('Save 1 record'));
    final body = _body('POST', '/api/patient/records/$_uploadId/split') as Map;
    expect((body['tests'] as List).map((x) => (x as Map)['testName']), ['Lipid profile']);
    expect(body['collectedAt'], '2026-09-30');
    expect(body['labName'], 'Suraksha Diagnostics');
    expect(body['shareWith'], [_mitra]);
    expect(((body['tests'] as List).first as Map)['values'], hasLength(3));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Medicines shows doses, medicines and safety; Taken posts the dose', (t) async {
    _serve();
    await _pump(t, const PatientMedicinesScreen(), stem: 'Patient-Medicines');
    expect(find.text('5 running · from 4 doctors'), findsOneWidget);
    expect(find.text('0 of 6 taken'), findsOneWidget);
    expect(find.text('MORNING'), findsOneWidget);
    expect(find.text('NIGHT'), findsOneWidget);
    expect(find.textContaining('Metformin runs out'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsWidgets);
    expect(find.text('Day 11 of 100'), findsOneWidget);
    expect(find.text('In cart · 3 strips'), findsOneWidget);
    expect(find.text('Check with your doctor'), findsOneWidget);
    expect(find.text('Glimepiride: Sulfa drugs allergy · sulfonylurea'), findsOneWidget);
    expect(find.text('Morning 7:30 AM · Night 8:30 PM'), findsOneWidget);
    expect(find.text('1 · last placed · 9 Oct'), findsOneWidget);

    await _tap(t, find.text('Taken').at(1)); // morning: Myo-inositol, Glimepiride, Metformin
    expect(_body('POST', '/api/patient/doses/6ac8d224bfcb2f5a9d64d6e2'), {'status': 'taken'});

    // Update stock → Save patches the medicine.
    await _tap(t, find.text('Update stock').first);
    await _tap(t, find.text('Save'));
    expect(_calls.any((c) => c.$1 == 'PATCH' && c.$2.startsWith('/api/patient/medicines/')), isTrue);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Med-AddToCart offers packs from the dose and posts the strips', (t) async {
    _serve();
    final glim = ((_fx('medicines') as Map)['items'] as List).cast<Map>().firstWhere((m) => m['name'] == 'Glimepiride');
    await _pump(
      t,
      Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Nav.go(c, 'Med-AddToCart', args: {'course': glim, 'nextVisitAt': null}), child: const Text('open'))))),
    );
    await _tap(t, find.text('open'));
    expect(find.text('Glimepiride 1 mg'), findsOneWidget);
    expect(find.text('Strip of 10 tablets · you take 1 a day'), findsOneWidget);
    expect(find.text('3 strips · 30 days'), findsOneWidget);
    expect(find.text('9 strips · 90 days'), findsOneWidget);
    await _tap(t, find.text('3 months'));
    await _tap(t, find.text('Add 9 strips to cart'));
    expect(_body('POST', '/api/patient/cart/items'), {'courseId': glim['id'], 'strips': 9, 'packOption': '3_months'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Med-Cart shows the cart; stepper, remove and suggestion call the API', (t) async {
    _serve();
    await _pump(t, const MedCartScreen(), stem: 'Med-Cart');
    expect(find.text('Cart · 2 medicines'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen · strip of 10'), findsOneWidget);
    expect(find.text('3 strips'), findsOneWidget);
    expect(find.text('The pharmacy sees this prescription with your order.'), findsOneWidget);
    expect(find.text('Flat 3B, 12 Purbachal Rd, Salt Lake'), findsOneWidget);
    expect(find.textContaining('Add Vitamin D3 too?', findRichText: true), findsOneWidget);

    await _tap(t, find.bySemanticsLabel('More').first);
    expect(_body('PATCH', '/api/patient/cart/items/6ac8d276c0d20a47471fe899'), {'strips': 4});
    await _tap(t, find.bySemanticsLabel('Remove Atorvastatin 10 mg'));
    expect(_called('DELETE', '/api/patient/cart/items/6ac8d276c0d20a47471fe8a6'), isTrue);
    await _tap(t, find.textContaining('Add Vitamin D3 too?', findRichText: true));
    expect((_body('POST', '/api/patient/cart/items') as Map)['strips'], 1);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Med-Pharmacy lists quotes for delivery and pick up; Place order posts the order', (t) async {
    _serve();
    await _pump(t, const MedPharmacyScreen(), stem: 'Med-Pharmacy', args: {'addressId': '6ac8d12d5e6ed8754976cfdd'});
    expect(find.text('For 3 strips Metformin, 2 strips Atorvastatin'), findsOneWidget);
    expect(find.text('CarePlus Online'), findsOneWidget);
    expect(find.text('₹211'), findsWidgets);
    expect(find.text('Delivers today in 2 hours · ₹15 delivery'), findsOneWidget);
    await _tap(t, find.text('QuickMeds'));
    expect(find.text('₹243'), findsWidgets);
    await _tap(t, find.text('Place order'));
    // How to pay: online now, or on delivery.
    expect(find.text('How would you like to pay?'), findsOneWidget);
    expect(find.text('Pay ₹243 online now'), findsOneWidget);
    await _tap(t, find.text('Pay on delivery'));
    expect(_body('POST', '/api/patient/orders'), {
      'pharmacyId': '6ac8d12dbfcb2f5a9d64d6ba',
      'mode': 'delivery',
      'addressId': '6ac8d12d5e6ed8754976cfdd',
    });
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Med-Pharmacy pick up tab shows nearby shops', (t) async {
    _serve();
    await _pump(t, const MedPharmacyScreen(), stem: 'Med-Pharmacy');
    await _tap(t, find.text('Nearby · pick up'));
    expect(find.text('Purbachal Pharmacy'), findsOneWidget);
    expect(find.text('Ready in 45 min'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

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
import 'package:medpin_app/screens/doctor/alerts.dart';
import 'package:medpin_app/screens/doctor/appointments.dart';
import 'package:medpin_app/screens/doctor/appointments_manage.dart';
import 'package:medpin_app/screens/doctor/clinic_editor.dart';
import 'package:medpin_app/screens/doctor/clinics.dart';
import 'package:medpin_app/screens/doctor/consult_advice.dart';
import 'package:medpin_app/screens/doctor/consult_diagnosis.dart';
import 'package:medpin_app/screens/doctor/consult_vitals.dart';
import 'package:medpin_app/screens/doctor/departments.dart';
import 'package:medpin_app/screens/doctor/prescriptions.dart';

/// The clinic-group doctor screens rendered from real API responses
/// (recorded from the local backend into test/fixtures/live/clinic), with one
/// action per screen checked against the request it sends.
Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

const _dir = 'test/fixtures/live/clinic';

Map<String, dynamic> _fx(String name) =>
    jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map<String, dynamic>;

dynamic _data(String name) => _fx(name)['data'];

/// Every recorded GET fixture.
final List<Map<String, dynamic>> _gets = [
  for (final f in Directory(_dir).listSync().whereType<File>())
    if (!f.path.endsWith('session.json')) jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
];

/// Requests the screen sent other than GET: method, path, body.
final List<(String, String, Map<String, dynamic>)> _sent = [];

/// Answers for actions, by "METHOD path"; default `{}` with 200.
final Map<String, http.Response> _answers = {};

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void _serve() {
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = (jsonDecode(File('$_dir/session.json').readAsStringSync()) as Map).cast<String, dynamic>();
  _sent.clear();
  _answers.clear();
  Api.I.client = MockClient((req) async {
    final path = req.url.path;
    if (req.method == 'GET') {
      if (path.startsWith('/api/doctors/') && path.endsWith('/slots')) return _json(_data('slots'));
      if (path == '/api/geo/search') {
        return _json({
          'items': [
            {'lat': 22.5801, 'lng': 88.4142, 'label': 'Sector 2, Salt Lake, Kolkata 700091', 'area': 'Salt Lake', 'city': 'Kolkata'},
          ],
        });
      }
      for (final f in _gets) {
        if (f['path'] != path) continue;
        final q = (f['query'] as Map).cast<String, dynamic>();
        if (q.entries.every((e) => req.url.queryParameters[e.key] == '${e.value}')) return _json(f['data']);
      }
      return _json({'error': {'code': 'NOT_MOCKED', 'message': 'not mocked: $path'}}, 404);
    }
    _sent.add((req.method, path, req.body.isEmpty ? const {} : (jsonDecode(req.body) as Map).cast<String, dynamic>()));
    return _answers['${req.method} $path'] ?? _json(const {});
  });
}

Future<void> _settle(WidgetTester t, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
  }
}

Future<void> _pumpLive(WidgetTester t, Widget screen, {Object? args, String name = '/'}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: medpinTheme(),
      onGenerateRoute: (s) => MaterialPageRoute(settings: RouteSettings(name: name, arguments: args), builder: (_) => screen),
    ),
  );
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
  await t.pump(const Duration(seconds: 7));
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Alerts: live list, counts and acknowledge', (t) async {
    _serve();
    await _pumpLive(t, const AlertsScreen());
    final d = _data('alerts') as Map;
    final items = (d['items'] as List).cast<Map>();
    final open = items.where((a) => a['status'] == 'open').toList();
    expect(find.text('Open (${open.length})'), findsOneWidget);
    expect(find.text('${open.length} open · most severe first'), findsOneWidget);
    for (final a in open) {
      expect(find.text((a['patient'] as Map)['name'] as String), findsWidgets);
      expect(find.text(a['detail'] as String), findsOneWidget);
    }
    expect(find.text('29 F · Type 2 diabetes, PCOS'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Acknowledge').first);
    expect(_sent.single.$1, 'POST');
    expect(_sent.single.$2, '/api/alerts/${open.first['id']}/acknowledge');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Appointments: live day list, stats, requests and decline', (t) async {
    _serve();
    await _pumpLive(t, const AppointmentsScreen());
    final today = _data('appointments_today') as Map;
    final stats = today['stats'] as Map;
    expect(find.text('${stats['booked']}'), findsOneWidget);
    expect(find.text('${stats['freedUp']}'), findsOneWidget);
    for (final a in (today['items'] as List).cast<Map>()) {
      expect(find.text((a['patient'] as Map)['name'] as String), findsWidgets);
    }
    expect(find.text('In consultation'), findsOneWidget);
    expect(find.text('Checked in'), findsWidgets);
    final requests = (_data('requests_pending') as List).cast<Map>();
    expect(find.text(requests.first['reason'] as String), findsOneWidget);
    expect(find.textContaining(requests.first['preferredTime'] as String, findRichText: true), findsOneWidget);
    expect(find.text('Declined requests (0)'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Decline').first);
    expect(_sent.single.$1, 'POST');
    expect(_sent.single.$2, '/api/appointment-requests/${requests.first['id']}/decline');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Appointments-Manage: live slots and reschedule', (t) async {
    _serve();
    final appt = _data('appointment') as Map;
    await _pumpLive(
      t,
      const Scaffold(body: SingleChildScrollView(child: AppointmentsManageSheet())),
      args: {'appointmentId': appt['id']},
    );
    expect(find.text('Manage appointment'), findsOneWidget);
    expect(find.textContaining((appt['patient'] as Map)['name'] as String), findsOneWidget);
    expect(find.textContaining('City Care Clinic — Salt Lake'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('Crossed-out times are already booked.'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('10:00 AM'));
    await _tap(t, find.text('Reschedule'));
    final slot = ((_data('slots') as Map)['slots'] as List).cast<Map>().firstWhere((s) => s['time'] == '10:00 AM');
    expect(_sent.single.$2, '/api/appointments/${appt['id']}/reschedule');
    // Same time of day as the recorded slot, on the first day with free times.
    final sent = DateTime.parse(_sent.single.$3['startAt'] as String).toLocal();
    final recorded = DateTime.parse(slot['startAt'] as String).toLocal();
    expect((sent.hour, sent.minute), (recorded.hour, recorded.minute));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Clinics: live locations and summary', (t) async {
    _serve();
    await _pumpLive(t, const ClinicsScreen());
    final d = _data('locations') as Map;
    final s = d['summary'] as Map;
    expect(find.text('City Care Clinic · ${s['active']} active'), findsOneWidget);
    for (final l in (d['items'] as List).cast<Map>()) {
      expect(find.text(l['name'] as String), findsOneWidget);
    }
    expect(find.text('Mon–Sat · 15-min slots'), findsOneWidget);
    expect(find.text('Tue · Thu · Sat · 20-min slots'), findsOneWidget);
    expect(find.text('DD-24, Sector 1, Salt Lake · 2 doctors'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Clinic-Editor: live location and save', (t) async {
    _serve();
    final l = _data('location') as Map;
    await _pumpLive(t, const ClinicEditorScreen(), args: {'locationId': l['id']});
    expect(find.text('Edit location'), findsOneWidget);
    expect(find.text(l['address'] as String), findsOneWidget);
    expect(find.text(l['phone'] as String), findsOneWidget);
    expect(find.text('9:00 AM – 2:00 PM'), findsOneWidget); // Saturday
    expect(find.text('Durga Puja · closed all day'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Tue · Thu · 5:00 – 8:00 PM'), findsOneWidget);
    expect(find.textContaining('upcoming booking'), findsOneWidget);
    expect(t.takeException(), isNull);

    // A typed address moves the pin (map search), shown under the field.
    final addr = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == l['address']);
    await t.ensureVisible(addr);
    await t.enterText(addr, 'BD-12, Sector 2, Salt Lake, Kolkata');
    await t.pump(const Duration(milliseconds: 950));
    await _settle(t);
    expect(find.text('Pin moved to Salt Lake, Kolkata'), findsOneWidget);

    await _tap(t, find.text('Save changes'));
    expect(_sent.single.$1, 'PATCH');
    expect(_sent.single.$2, '/api/locations/${l['id']}');
    final body = _sent.single.$3;
    expect(body['name'], l['name']);
    expect(body['address'], 'BD-12, Sector 2, Salt Lake, Kolkata');
    expect([body['lat'], body['lng']], [22.5801, 88.4142], reason: 'the pin follows the typed address');
    expect((body['weeklyHours'] as List).length, 7);
    expect((body['letterhead'] as Map)['registrationNo'], 'WBMC 64213');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Departments: live list and add', (t) async {
    _serve();
    await _pumpLive(t, const DepartmentsScreen());
    for (final dep in (_data('departments') as List).cast<Map>()) {
      expect(find.text(dep['name'] as String), findsOneWidget);
    }
    expect(find.text('Specialties City Care Clinic has added'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Add department'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Test clinic Rheumatology');
    await _tap(t, find.text('Add department').last);
    expect(_sent.single.$1, 'POST');
    expect(_sent.single.$2, '/api/departments');
    expect(_sent.single.$3['name'], 'Test clinic Rheumatology');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Vitals: prefilled vitals and next', (t) async {
    _serve();
    final c = _data('consultation') as Map;
    final id = (c['consultation'] as Map)['id'];
    await _pumpLive(t, const ConsultVitalsScreen(), args: {'consultationId': id});
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('Allergy: Sulfa drugs', findRichText: true), findsOneWidget);
    final v = c['vitals'] as Map;
    expect(find.text('${v['bpSystolic']}'), findsOneWidget);
    expect(find.text('${v['pulse']}'), findsOneWidget);
    expect(find.text('158'), findsOneWidget); // height from the patient record
    expect(find.text('27.4'), findsOneWidget); // BMI
    expect(find.text((c['consultation'] as Map)['chiefComplaint'] as String), findsOneWidget);
    expect(find.textContaining('Recorded at the front desk'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Next: Diagnosis'));
    // Vitals unchanged and already on this visit: only the draft is saved.
    expect(_sent.first.$1, 'PATCH');
    expect(_sent.first.$2, '/api/consultations/$id');
    expect(_sent.first.$3['chiefComplaint'], (c['consultation'] as Map)['chiefComplaint']);
    await _settle(t, 10);
    expect(find.text('Add a diagnosis'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Diagnosis: ICD search and save', (t) async {
    _serve();
    final c = _data('consultation') as Map;
    final id = (c['consultation'] as Map)['id'];
    await _pumpLive(t, const ConsultDiagnosisScreen(), args: {'consultationId': id});
    for (final dx in ((c['consultation'] as Map)['diagnoses'] as List).cast<Map>()) {
      expect(find.text(dx['name'] as String), findsOneWidget);
    }
    expect(find.text('No previous diagnoses for this patient yet'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.enterText(find.byType(TextField).first, 'hyper');
    await t.pump(const Duration(milliseconds: 300));
    await _settle(t);
    expect(find.text('Essential hypertension'), findsOneWidget);
    await _tap(t, find.bySemanticsLabel('Add Essential hypertension'));
    await _tap(t, find.text('Next: Advice'));
    expect(_sent.first.$1, 'PATCH');
    final dx = (_sent.first.$3['diagnoses'] as List).cast<Map>();
    expect(dx.length, 3);
    expect(dx.last['icdCode'], 'I10');
    expect(dx.last['source'], 'catalog');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Consult-Advice: draft and generate prescription', (t) async {
    _serve();
    final c = _data('consultation') as Map;
    final id = (c['consultation'] as Map)['id'];
    final rx = _data('prescription') as Map;
    _answers['POST /api/consultations/$id/issue'] = _json({
      'consultation': c['consultation'],
      'prescription': rx,
    });
    await _pumpLive(t, const ConsultAdviceScreen(), args: {'consultationId': id});
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('1-0-1 · After food · 3 months'), findsOneWidget);
    expect(find.text('1-0-0 · Before food · 1 month'), findsOneWidget);
    expect(find.text('Sulfa drugs allergy · sulfonylurea'), findsOneWidget);
    expect(find.text('2 added · checked against the brand catalog'), findsOneWidget);
    expect(find.text('Lipid profile'), findsOneWidget);
    expect(find.text('Come back with fasting sugar.'), findsOneWidget);
    expect(find.text('MBBS, MD · WBMC 64213'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Generate prescription'));
    expect(_sent.map((s) => '${s.$1} ${s.$2}'), ['PATCH /api/consultations/$id', 'POST /api/consultations/$id/issue']);
    expect(((_sent.first.$3['labOrders'] as List).first as Map)['testName'], 'HbA1c');
    expect((_sent.first.$3['followUp'] as Map)['enabled'], true);
    await _settle(t, 10);
    expect(find.text('Prescriptions'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Prescriptions: live list and send without signature', (t) async {
    _serve();
    final rx = _data('prescription') as Map;
    _answers['POST /api/prescriptions/${rx['id']}/send'] = _json({
      'error': {'code': 'SIGNATURE_REQUIRED', 'message': 'Add your digital signature first'},
    }, 409);
    await _pumpLive(t, const PrescriptionsScreen(), args: {'prescriptionId': rx['id']});
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('1 PRESCRIPTION · LATEST FIRST'), findsOneWidget);
    expect(find.text(rx['diagnosisSummary'] as String), findsOneWidget);
    expect(find.text('Metformin 500 mg, Glimepiride 1 mg'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen · City Care Clinic, Salt Lake'), findsOneWidget);
    expect(t.takeException(), isNull);

    await _tap(t, find.text('Send to patient'));
    expect(_sent.single.$2, '/api/prescriptions/${rx['id']}/send');
    // No signature yet: the doctor is asked to add one right there.
    expect(find.text('Add your digital signature'), findsOneWidget);
    expect(find.text('Add signature'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

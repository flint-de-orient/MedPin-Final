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
import 'package:medpin_app/screens/doctor/common_d3.dart';
import 'package:medpin_app/screens/doctor/doctor_reports.dart';
import 'package:medpin_app/screens/doctor/report_consultations.dart';
import 'package:medpin_app/screens/doctor/report_fees.dart';
import 'package:medpin_app/screens/doctor/report_followups.dart';
import 'package:medpin_app/screens/doctor/report_prescriptions.dart';
import 'package:medpin_app/screens/doctor/report_referrals.dart';

/// The doctor's Reports tab rendered from real API responses (recorded from
/// the local backend into test/fixtures/live/reports), with the actions'
/// requests checked against a mock client.
const _dir = 'test/fixtures/live/reports';

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

Map<String, dynamic> _json(String name) => jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Recorded response body of a fixture.
dynamic _data(String name) => _json(name)['data'];

/// Requests the screens sent, in order.
final _sent = <http.Request>[];

/// Answers GETs from the fixtures and actions with [actions] (path → body).
void _serve({Map<String, Object?> actions = const {}}) {
  _sent.clear();
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = jsonDecode(File('$_dir/session.json').readAsStringSync()) as Map<String, dynamic>;
  const gets = {
    '/api/reports/summary': 'summary',
    '/api/reports/filter-counts': 'filter_counts',
    '/api/locations': 'locations',
    '/api/reports/consultations': 'consultations',
    '/api/reports/prescriptions': 'prescriptions',
    '/api/reports/fees': 'fees',
    '/api/payments': 'payments_pending',
    '/api/reports/follow-ups': 'follow_ups',
  };
  Api.I.client = MockClient((req) async {
    _sent.add(req);
    final path = req.url.path;
    Object? body;
    if (req.method == 'GET' && path == '/api/referrals') {
      body = _data('referrals_${req.url.queryParameters['direction']}');
    } else if (req.method == 'GET' && gets[path] != null) {
      body = _data(gets[path]!);
    } else if (actions.containsKey(path)) {
      body = actions[path];
    }
    if (body == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked"}}', 404);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

/// A fixed period around the recorded data, so the test doesn't depend on
/// today's date.
final _period = D3Filters(range: 'custom', from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 9));

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpLive(WidgetTester t, String stem, Widget screen, {Object? args}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    onGenerateRoute: (_) => MaterialPageRoute(settings: RouteSettings(name: stem, arguments: args), builder: (_) => screen),
  ));
  await _settle(t);
}

Future<void> _tearDown(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 7));
}

Iterable<http.Request> _requests(String method, String path) => _sent.where((r) => r.method == method && r.url.path == path);

void main() {
  final launched = <Uri>[];

  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    d3Launch = (uri) async {
      launched.add(uri);
      return true;
    };
    await _loadFigtree();
  });

  setUp(launched.clear);

  testWidgets('Doctor-Reports: live KPIs, splits, range tabs and the filter sheet', (t) async {
    _serve();
    await _pumpLive(t, 'Doctor-Reports', const DoctorReportsScreen());
    final s = _data('summary') as Map<String, dynamic>;
    final k = s['kpis'] as Map<String, dynamic>;
    expect(find.text('${(k['consultations'] as Map)['value']}'), findsWidgets);
    expect(find.text(d3RupeesShort((k['feesCollected'] as Map)['value'] as num)), findsOneWidget);
    expect(find.text('Booked, didn’t come · ${(k['missed'] as Map)['pct']}%'), findsOneWidget);
    expect(find.textContaining('+${(k['consultations'] as Map)['changePct']}% vs '), findsOneWidget);
    expect(find.text('${(k['avgConsultMin'] as Map)['value']} min'), findsOneWidget);
    expect(find.text('City Care Clinic · Salt Lake'), findsOneWidget);
    expect(find.text('Follow-up'), findsOneWidget);
    expect(find.text(((s['topDiagnoses'] as List).first as Map)['key'] as String), findsOneWidget);
    expect(find.textContaining('Closed on Sundays.'), findsOneWidget);
    expect(find.text(const D3Filters().longLabel), findsOneWidget);
    expect(t.takeException(), isNull);

    // Range tab → summary fetched again for the last 7 days.
    await t.tap(find.text('7 days'));
    await _settle(t);
    expect(_requests('GET', '/api/reports/summary').last.url.queryParameters['range'], '7_days');

    // Filters → sheet with live counts; untick Video → recount; apply.
    await t.tap(find.text('Filters'));
    await _settle(t);
    expect(find.text('Show ${(_data('filter_counts') as Map)['matching']} consultations'), findsOneWidget);
    expect(find.text('City Care — New Town'.replaceAll(' — ', ' · ')), findsWidgets);
    await t.ensureVisible(find.text('Video'));
    await t.tap(find.text('Video'));
    await _settle(t);
    final counted = _requests('GET', '/api/reports/filter-counts').last.url.queryParameters;
    expect(counted['modes'], 'in_clinic');
    expect(counted['range'], '7_days');
    await t.tap(find.textContaining('Show '));
    await _settle(t);
    final q = _requests('GET', '/api/reports/summary').last.url.queryParameters;
    expect(q['modes'], 'in_clinic');
    expect(q['range'], '7_days');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Report-Consultations: grouped by day, search goes to the API', (t) async {
    _serve();
    await _pumpLive(t, 'Report-Consultations', const ReportConsultationsScreen(), args: {'filters': _period});
    final c = _data('consultations') as Map<String, dynamic>;
    final items = (c['items'] as List).cast<Map<String, dynamic>>();
    final totals = c['totals'] as Map<String, dynamic>;
    expect(find.text('${totals['consultations']} consultations · 1 Sep – 9 Oct'), findsOneWidget);
    expect(find.text(d3RupeesShort(totals['feesBilled'] as num)), findsOneWidget);
    expect(find.text('${totals['avgMin']} min'), findsOneWidget);
    final first = items.first;
    expect(find.text((first['patient'] as Map)['name'] as String), findsWidgets);
    final day = d3Day(first['date'])!;
    final sameDay = items.where((a) => F2.same(d3Day(a['date'])!, day)).length;
    expect(find.text(d3DayHead(day).toUpperCase()), findsOneWidget);
    expect(find.text(sameDay == 1 ? '1 consultation' : '$sameDay consultations'), findsWidgets);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Fee pending'), findsWidgets);
    expect(_requests('GET', '/api/reports/consultations').first.url.queryParameters['from'], '2026-09-01');
    expect(t.takeException(), isNull);

    await t.enterText(find.byType(TextField), 'Amit');
    await t.pump(const Duration(milliseconds: 350));
    await _settle(t);
    expect(_requests('GET', '/api/reports/consultations').last.url.queryParameters['q'], 'Amit');
    await _tearDown(t);
  });

  testWidgets('Report-Prescriptions: totals, top medicines and the register', (t) async {
    _serve();
    await _pumpLive(t, 'Report-Prescriptions', const ReportPrescriptionsScreen(), args: {'filters': _period});
    final p = _data('prescriptions') as Map<String, dynamic>;
    final items = (p['items'] as List).cast<Map<String, dynamic>>();
    expect(find.text('${(p['totals'] as Map)['prescriptions']} prescriptions · 1 Sep – 9 Oct'), findsOneWidget);
    expect(find.text('Most prescribed medicines'), findsOneWidget);
    expect(find.text(((p['topMedicines'] as List).first as Map)['key'] as String), findsWidgets);
    expect(find.text(((p['topTests'] as List).first as Map)['key'] as String), findsWidgets);
    expect(find.text('${(p['totals'] as Map)['labTests']}'), findsWidgets);
    final rx = items.first;
    expect(find.text(rx['patient'] as String), findsWidgets);
    final tests = (rx['tests'] as List).cast<String>();
    expect(find.text('Rx ${rx['rxNumber']} · ${tests.isEmpty ? 'No tests' : tests.join(', ')}'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Report-Fees: totals, pending list, mark as paid and payment link', (t) async {
    final fees = _data('fees') as Map<String, dynamic>;
    final pending = (fees['pending'] as List).cast<Map<String, dynamic>>();
    final id = pending.first['id'];
    _serve(actions: {
      '/api/payments/$id/mark-paid': {'id': id, 'status': 'paid', 'method': 'cash'},
      '/api/payments/$id/link': {'id': id, 'paymentLinkUrl': 'http://localhost:4000/dev/pay/$id'},
    });
    await _pumpLive(t, 'Report-Fees', const ReportFeesScreen(), args: {'filters': _period});
    expect(find.text('${d3Rupees(fees['billed'] as int)} billed · 1 Sep – 9 Oct'), findsOneWidget);
    expect(find.text(d3RupeesShort(fees['collected'] as num)), findsOneWidget);
    expect(find.text(d3Rupees(fees['pendingAmount'] as int)), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('${pending.length} patients'), findsOneWidget);
    expect(find.text(pending.first['patient'] as String), findsWidgets);
    expect(find.text('Show ${pending.length - 3} more'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.ensureVisible(find.text('Mark as paid').first);
    await t.tap(find.text('Mark as paid').first);
    await _settle(t);
    final paid = _requests('POST', '/api/payments/$id/mark-paid').single;
    expect(jsonDecode(paid.body), {'method': 'cash'});
    expect(find.text('${pending.first['patient']} marked as paid'), findsOneWidget);

    await t.tap(find.text('Send payment link').first);
    await _settle(t);
    expect(_requests('POST', '/api/payments/$id/link'), hasLength(1));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Report-FollowUps: compliance, missed list, reminder and call', (t) async {
    final f = _data('follow_ups') as Map<String, dynamic>;
    final missed = (f['missedList'] as List).cast<Map<String, dynamic>>()
      ..sort((a, b) => (b['daysLate'] as num).compareTo(a['daysLate'] as num));
    final m = missed.first;
    final patient = m['patient'] as Map<String, dynamic>;
    _serve(actions: {
      '/api/follow-ups/${m['id']}/remind': {'id': m['id'], 'remindersSent': 1},
      '/api/patients/${patient['id']}': {
        'patient': {'id': patient['id'], 'name': patient['name'], 'phone': '9831120764'},
      },
    });
    await _pumpLive(t, 'Report-FollowUps', const ReportFollowupsScreen(), args: {'filters': _period});
    expect(find.text('${f['due']} follow-ups due · 1 Sep – 9 Oct'), findsOneWidget);
    expect(find.text('${f['onTimePct']}%'), findsWidgets);
    expect(find.text(patient['name'] as String), findsOneWidget);
    expect(find.text('${m['daysLate']} days late'), findsOneWidget);
    final due = d3Day(m['dueDate'])!;
    expect(find.text('${patient['age']} M · ${patient['condition']} · due ${due.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][due.month - 1]}'), findsOneWidget);
    expect(find.text('${missed.length} patients'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.ensureVisible(find.text('Send reminder').first);
    await t.tap(find.text('Send reminder').first);
    await _settle(t);
    expect(_requests('POST', '/api/follow-ups/${m['id']}/remind'), hasLength(1));
    expect(find.text('Reminder sent to ${patient['name']}'), findsOneWidget);

    await t.tap(find.text('Call').first);
    await _settle(t);
    expect(launched, [Uri(scheme: 'tel', path: '9831120764')]);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Report-Referrals: sent and received tabs', (t) async {
    _serve();
    await _pumpLive(t, 'Report-Referrals', const ReportReferralsScreen(), args: {'filters': _period});
    final sent = ((_data('referrals_sent') as Map)['items'] as List).cast<Map<String, dynamic>>();
    final received = ((_data('referrals_received') as Map)['items'] as List).cast<Map<String, dynamic>>();
    expect(find.text('Sent · ${sent.length}'), findsOneWidget);
    expect(find.text('Received · ${received.length}'), findsOneWidget);
    expect(find.text('${sent.length + received.length} referrals · 1 Sep – 9 Oct'), findsOneWidget);
    final s = sent.first;
    expect(find.text((s['patientId'] as Map)['name'] as String), findsOneWidget);
    expect(find.text('To ${s['counterpartName']} · ${s['specialty']} · ${s['reason']}'), findsOneWidget);
    expect(find.text('Awaiting'), findsWidgets);

    await t.tap(find.text('Received · ${received.length}'));
    await t.pump();
    final r = received.first;
    expect(find.text((r['patientId'] as Map)['name'] as String), findsOneWidget);
    expect(find.text('From ${r['counterpartName']} · ${r['specialty']} · ${r['reason']}'), findsOneWidget);
    expect(find.textContaining('Seen '), findsWidgets);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Report-Download: POST /api/exports and opens the file', (t) async {
    _serve(actions: {
      '/api/exports': {'id': 'x1', 'status': 'done', 'url': 'http://localhost:4000/files/exports/medpin-prescriptions.xlsx?sig=1', 'emailed': true},
    });
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: medpinTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Nav.go(context, 'Report-Download', args: _period.downloadArgs('prescriptions')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Prescription register · 1 Sep – 9 Oct · all locations'), findsOneWidget);
    await t.tap(find.text('Excel (.xlsx)'));
    await t.pump();
    await t.tap(find.text('Download Excel'));
    await _settle(t);
    final body = jsonDecode(_requests('POST', '/api/exports').single.body) as Map<String, dynamic>;
    expect(body['kind'], 'report');
    expect(body['reportType'], 'prescriptions');
    expect(body['format'], 'xlsx');
    expect(body['filters'], {'from': '2026-09-01', 'to': '2026-10-09'});
    expect(body['includeMobiles'], false);
    expect(body['emailCopy'], true);
    expect(launched.single.toString(), 'http://localhost:4000/files/exports/medpin-prescriptions.xlsx?sig=1');
    expect(find.text('Excel ready · copy sent to your email'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

/// Small date helper for the assertions.
class F2 {
  static bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

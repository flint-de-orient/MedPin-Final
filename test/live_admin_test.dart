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
import 'package:medpin_app/data/format.dart';
import 'package:medpin_app/data/session.dart';
import 'package:medpin_app/screens/doctor/billing.dart';
import 'package:medpin_app/screens/doctor/cards_analytics.dart';
import 'package:medpin_app/screens/doctor/cards_clinical.dart';
import 'package:medpin_app/screens/doctor/common_d3.dart';
import 'package:medpin_app/screens/doctor/common_d9.dart';
import 'package:medpin_app/screens/doctor/daily_report.dart';
import 'package:medpin_app/screens/doctor/export.dart';
import 'package:medpin_app/screens/doctor/people.dart';
import 'package:medpin_app/screens/doctor/people_add.dart';
import 'package:medpin_app/screens/doctor/people_member.dart';
import 'package:medpin_app/widgets/mp.dart';

/// The admin screens (billing, team, exports, daily report, dashboard cards)
/// rendered from real API responses recorded into test/fixtures/live/admin.

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/admin/$name.json').readAsStringSync());

const _rinaId = '6ac8bbd08adea6a429a731a5';

/// Requests the screens sent, newest last.
final _requests = <http.Request>[];

/// Answers for mutating calls: 'METHOD /path' → (status, body).
Map<String, (int, Object?)> _answers = {};

http.Response _json(int status, Object? body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void _serve([Map<String, (int, Object?)> answers = const {}]) {
  _answers = answers;
  _requests.clear();
  final session = (jsonDecode(File('test/fixtures/live/doctor.json').readAsStringSync()) as Map)['session'] as Map;
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = session.cast<String, dynamic>();
  Api.I.client = MockClient((req) async {
    _requests.add(req);
    final key = '${req.method} ${req.url.path}';
    final a = _answers[key];
    if (a != null) return _json(a.$1, a.$2);
    if (req.method == 'GET') {
      final p = req.url.path;
      final name = switch (p) {
        '/api/billing' => req.url.queryParameters['invoices'] == '50' ? 'billing_all' : 'billing',
        '/api/members' => 'members',
        '/api/members/$_rinaId' => 'member',
        '/api/departments' => 'departments',
        '/api/locations' => 'locations',
        '/api/dashboard' => 'dashboard',
        '/api/dashboard/cards' => 'cards',
        '/api/reports/daily' => 'daily',
        '/api/appointments' => 'appointments',
        '/api/alerts' => 'alerts',
        '/api/follow-ups' => 'follow_ups',
        '/api/inbox/summaries' => 'summaries',
        _ => null,
      };
      if (name != null) return _json(200, _fx(name));
    }
    return _json(404, {'error': {'code': 'NOT_MOCKED', 'message': 'not mocked: $key'}});
  });
}

http.Request _last(String method, String path) => _requests.lastWhere((r) => r.method == method && r.url.path == path);
Map<String, dynamic> _body(http.Request r) => (jsonDecode(r.body) as Map).cast<String, dynamic>();

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _pump(WidgetTester t, Widget screen, {Object? args}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    onGenerateRoute: (s) => MaterialPageRoute(
      settings: RouteSettings(name: 'Test', arguments: args),
      builder: (_) => screen,
    ),
  ));
  await t.pump();
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

String _d(Object? iso) => D9Fmt.date(F.date(iso)!);

void main() {
  final launched = <Uri>[];

  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    D9Open.launcher = (uri) async {
      launched.add(uri);
      return true;
    };
    // Saved / shared files are recorded instead of written to the phone.
    d3Save = (context, url, name) async {
      launched.add(Uri.parse(url));
      return true;
    };
    d3Share = (context, url, name) async => launched.add(Uri.parse(url));
    await _loadFigtree();
  });
  setUp(launched.clear);

  testWidgets('Billing shows the plan, usage, invoices and plans; switch, download, view all', (t) async {
    final b = _fx('billing') as Map;
    final inv = (b['invoices'] as List).first as Map;
    _serve({
      'POST /api/billing/switch': (409, {
        'error': {'code': 'TOO_MANY_SEATS', 'message': 'Server: your team has 5 people, so 2 would need to be removed first'},
      }),
      'GET /api/billing/invoices/${inv['id']}/download': (200, {'url': 'http://localhost:4000/files/invoices/x.pdf?exp=1&sig=a'}),
    });
    await _pump(t, const BillingScreen());
    expect(find.text('Clinic plan'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('₹2,499 / month', findRichText: true), findsNWidgets(2));
    final renew = _d((b['subscription'] as Map)['currentPeriodEnd']);
    expect(find.text('Renews $renew'), findsOneWidget);
    expect(find.text('This billing cycle · resets $renew'), findsOneWidget);
    expect(find.text('1,860 of 3,000', findRichText: true), findsOneWidget);
    expect(find.text('5 of 8', findRichText: true), findsOneWidget);
    expect(find.text('8 of 500', findRichText: true), findsOneWidget);
    expect(find.text(_d(inv['issuedAt'])), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('Hospital'), findsOneWidget);
    expect(find.text('3 seats · 150 active patients · 1,000 AI chats a month'), findsOneWidget);
    expect(find.text('Your team has 5 people, so 2 would need to be removed first'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);

    // Switch to Starter → the server refuses with the seat message.
    await _tap(t, find.text('Switch plan').first);
    expect(_body(_last('POST', '/api/billing/switch')), {'planKey': 'starter'});
    expect(find.text('Server: your team has 5 people, so 2 would need to be removed first'), findsOneWidget);

    // Download the newest invoice.
    await _tap(t, find.bySemanticsLabel('Download invoice for ${_d(inv['issuedAt'])}'));
    expect(_requests.any((r) => r.url.path == '/api/billing/invoices/${inv['id']}/download'), isTrue);
    expect(launched.single.path, '/files/invoices/x.pdf');

    // View all → ?invoices=50.
    await _tap(t, find.text('View all'));
    expect(_requests.last.url.queryParameters['invoices'], '50');
    final all = (_fx('billing_all') as Map)['invoices'] as List;
    expect(find.text(_d((all.last as Map)['issuedAt'])), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('People lists the team by role and opens a member', (t) async {
    _serve();
    await _pump(t, const PeopleScreen());
    expect(find.text('5 of 8 seats used on the Clinic plan'), findsOneWidget);
    expect(find.text('DOCTORS'), findsOneWidget);
    expect(find.text('DIETICIANS'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Cardiology · Salt Lake'), findsOneWidget);
    expect(find.text('Endocrinology · All locations'), findsWidgets);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Test admin'), findsOneWidget);
    expect(find.text('Suspended'), findsOneWidget);
    await _tap(t, find.text('Dr. Rina Mitra'));
    expect(_requests.any((r) => r.url.path == '/api/members/$_rinaId'), isTrue);
    expect(find.text('+91 98111 22233 · Joined Oct 2026'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('People-Member edits and suspends via PATCH', (t) async {
    final m = _fx('member') as Map;
    _serve({'PATCH /api/members/$_rinaId': (200, m)});
    await _pump(t, const PeopleMemberScreen(), args: {'memberId': _rinaId});
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Cardiology'), findsOneWidget);
    expect(find.text('City Care Clinic — Salt Lake'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Set by the Doctor role'), findsOneWidget);
    await _tap(t, find.byType(MpSwitch));
    await _tap(t, find.text('Save'));
    final body = _body(_last('PATCH', '/api/members/$_rinaId'));
    expect(body, {
      'role': 'doctor',
      'departmentId': '6ac8bbcebfcb2f5a9d64d518',
      'locationIds': ['6ac8bbcee42c9f0836e98563'],
      'allLocations': false,
      'suspended': true,
    });
    expect(find.text('Saved'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  for (final noSeats in [false, true]) {
    testWidgets('People-Add verifies the phone and adds${noSeats ? ' (no seats left)' : ''}', (t) async {
      _serve({
        'POST /api/members/phone-otp': (200, {'sent': true, 'maskedPhone': '+91 98111 •••02', 'resendInSec': 30, 'devCode': '123456'}),
        'POST /api/members': noSeats
            ? (409, {'error': {'code': 'NO_SEATS', 'message': 'All 8 seats on the Clinic plan are used'}})
            : (201, {'id': 'new', 'name': 'Test admin two'}),
      });
      await _pump(t, const PeopleAddScreen());
      expect(find.text('Cardiology'), findsOneWidget); // first department
      expect(find.text('City Care Clinic — Salt Lake'), findsOneWidget);
      await _tap(t, find.text('Front desk'));
      await t.enterText(find.byType(TextField).at(0), 'Test admin two');
      await t.enterText(find.byType(TextField).at(1), '98111 00002');
      await t.pump();
      await _tap(t, find.text('Add to team'));
      expect(_body(_last('POST', '/api/members/phone-otp')), {'phone': '9811100002'});
      expect(find.text('Test code: 123456'), findsOneWidget);
      expect(find.text('Enter the code sent to +91 98111 •••02'), findsOneWidget);
      await t.enterText(find.descendant(of: find.byType(MpSheet), matching: find.byType(TextField)), '123456');
      await _tap(t, find.text('Confirm and add'));
      expect(_body(_last('POST', '/api/members')), {
        'role': 'front_desk',
        'name': 'Test admin two',
        'phone': '9811100002',
        'departmentId': '6ac8bbcebfcb2f5a9d64d518',
        'locationIds': ['6ac8bbcee42c9f0836e98563'],
        'allLocations': false,
        'otpCode': '123456',
      });
      expect(find.text(noSeats ? 'All 8 seats on the Clinic plan are used' : 'Added to team'), findsOneWidget);
      expect(t.takeException(), isNull);
      await _tearDown(t);
    });
  }

  testWidgets('Daily-Report shows the chosen day and downloads the PDF', (t) async {
    final d = _fx('daily') as Map;
    final c = (d['items'] as List).first as Map;
    _serve({'POST /api/exports': (201, {'id': 'e1', 'url': 'http://localhost:4000/files/exports/daily.pdf?exp=1&sig=a'})});
    await _pump(t, const DailyReportScreen(), args: {'date': '2026-10-06'});
    expect(_last('GET', '/api/reports/daily').url.queryParameters['date'], '2026-10-06');
    expect(find.textContaining('Tue, 6 Oct 2026'), findsOneWidget);
    expect(find.text('Amit Pal'), findsOneWidget);
    expect(find.text('42 M · Seen ${F.time(F.date(c['seenAt'])!)}'), findsOneWidget);
    expect(find.text('Routine diabetes review'), findsOneWidget);
    expect(find.text('Type 2 diabetes mellitus'), findsOneWidget);
    expect(find.text('123/81'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('76 kg'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('1-0-1 · after food · 3 months'), findsOneWidget);
    expect(find.text(F.dateLong(F.date(c['followUpDate'])!)), findsOneWidget);
    expect(find.text('Follow-up'), findsWidgets);
    expect(find.text('Show 11 more consultations'), findsNothing);
    await _tap(t, find.text('Download PDF'));
    expect(_body(_last('POST', '/api/exports')), {
      'kind': 'report',
      'reportType': 'daily',
      'format': 'pdf',
      'filters': {'from': '2026-10-06', 'to': '2026-10-06'},
    });
    expect(launched.single.path, '/files/exports/daily.pdf');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  for (final owner in [true, false]) {
    testWidgets('Export posts a data export${owner ? '' : ' (not the owner)'}', (t) async {
      _serve({
        'POST /api/exports': owner
            ? (201, {'id': 'e2', 'url': 'http://localhost:4000/files/exports/data.csv?exp=1&sig=a'})
            : (409, {'error': {'code': 'OWNER_REQUIRED', 'message': 'Only the practice owner can export patient data'}}),
      });
      await _pump(t, const ExportScreen());
      expect(find.text('Includes all 8 patients, not just the first page'), findsOneWidget);
      final now = DateTime.now();
      expect(find.text(D9Fmt.date(now)), findsOneWidget);
      await _tap(t, find.text('Alerts'));
      await _tap(t, find.text('Export and share'));
      expect(_body(_last('POST', '/api/exports')), {
        'kind': 'data_export',
        'datasets': ['patients', 'clinical_summary'],
        'format': 'csv',
        'filters': {
          'from': D9Fmt.dayKey(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 90))),
          'to': D9Fmt.dayKey(now),
        },
      });
      if (owner) {
        expect(find.text('CSV export ready to share'), findsOneWidget);
        expect(launched.single.path, '/files/exports/data.csv');
      } else {
        expect(find.text('Only the practice owner can export patient data'), findsOneWidget);
        expect(launched, isEmpty);
      }
      expect(t.takeException(), isNull);
      await _tearDown(t);
    });
  }

  testWidgets('Cards-Clinical shows live clinic, labs, BP, follow-ups and conditions', (t) async {
    _serve();
    await _pump(t, const CardsClinicalScreen());
    expect(find.text('8 visits · Dr. Sen'), findsOneWidget);
    expect(find.text('DR. ARJUN SEN · 8 VISITS'), findsOneWidget);
    expect(find.text('Amit Pal'), findsOneWidget);
    expect(find.text('Done'), findsWidgets);
    expect(find.text('In consult'), findsOneWidget);
    expect(find.text('+ 5 more today'), findsOneWidget);
    expect(find.text('1 critical'), findsOneWidget);
    expect(find.text('Potassium 6.1 mmol/L · ref 3.5–5.1', findRichText: true), findsOneWidget);
    expect(find.text('61 M · Chronic kidney disease · Hypertension'), findsOneWidget);
    expect(find.text('Recent lab reports'), findsNothing);
    expect(find.text('Last 30 days · 7 results'), findsOneWidget);
    expect(find.text('Last 90 days · 8 of 8 measured'), findsOneWidget);
    expect(find.text('NEEDS ATTENTION'), findsNothing);
    expect(find.text('OVERDUE · 2'), findsOneWidget);
    expect(find.text('10 days overdue · was due Tue, 29 Sep', findRichText: true), findsOneWidget);
    expect(find.text('DUE THIS WEEK · 3'), findsOneWidget);
    expect(find.text('Practice-wide · 8 patients'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Cards-Analytics shows live ECGs, lipids and chat summaries', (t) async {
    _serve();
    await _pump(t, const CardsAnalyticsScreen());
    expect(find.text('Heart rate flags'), findsNothing); // 0 flags
    expect(find.text('Recent ECGs'), findsOneWidget);
    expect(find.text('1 of 8 patients in caseload', findRichText: true), findsOneWidget);
    expect(find.text('Latest result · LDL target <100 mg/dL'), findsOneWidget);
    expect(find.text('with an LDL result, of 8'), findsOneWidget);
    expect(find.text('Clinic snapshot'), findsNothing);
    expect(find.text('Chat summaries'), findsOneWidget);
    expect(find.text('patients wrote'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Needs reply'), findsNWidgets(3));
    expect(find.text('+ 2 more who wrote today'), findsOneWidget);
    expect(find.text('Live activity'), findsNothing);
    expect(find.text('Nutrition reviews'), findsNothing); // none due
    expect(_last('GET', '/api/inbox/summaries').url.queryParameters['date'], 'today');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

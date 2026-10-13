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
import 'package:medpin_app/screens/patient/common_p1.dart';
import 'package:medpin_app/screens/patient/hero_carousel.dart';
import 'package:medpin_app/screens/patient/p1_sheets.dart';
import 'package:medpin_app/screens/patient/patient_chat.dart';
import 'package:medpin_app/screens/patient/patient_home.dart';
import 'package:medpin_app/widgets/mp.dart';

/// Patient home, its sheets (adherence, track, log, emergency, Ask AI), the
/// urgent chat and the carousel rendered from real API responses (recorded
/// from the local backend into test/fixtures/live/patient_care), with the
/// requests their buttons make. The AI is never called: /ai/ask answers from
/// a recorded response made with the AI off.

const _conv = '6ac8d0bd07fdebd2731d1ee8'; // Priya's care thread
const _sen = '6ac8d0bd07fdebd2731d1eb3'; // Dr. Arjun Sen
const _mou = '6ac8d0c08645bb27079976bd'; // Mou Banerjee (dietician)

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/patient_care/$name.json').readAsStringSync());

/// Requests made: method, path (with and without the query) and JSON body.
final _calls = <(String, String, Object?)>[];

bool _called(String method, String path) => _calls.any((c) => c.$1 == method && c.$2 == path);
Map<String, dynamic> _body(String method, String path) =>
    (_calls.lastWhere((c) => c.$1 == method && c.$2 == path).$3 as Map).cast<String, dynamic>();

Object? _answer(http.Request r) {
  final p = r.url.path;
  if (r.method == 'GET') {
    return switch (p) {
      '/api/patient/home' => _fx('home'),
      '/api/patient/adherence' => _fx('adherence'),
      '/api/patient/me' => _fx('me'),
      '/api/patient/logs/options' => _fx('log_options'),
      '/api/patient/urgent/doctors' => _fx('urgent_doctors'),
      '/api/patient/conversations' => _fx('conversations'),
      '/api/conversations/$_conv/messages' => _fx('thread'),
      '/api/patient/readings' => _fx(r.url.queryParameters['measure'] == null ? 'readings_7d' : 'readings_sugar'),
      '/api/notifications' => _fx('notifications'),
      '/api/patient/logs' => _fx('logs_today'),
      _ => null,
    };
  }
  if (p == '/api/patient/ai/ask') return _fx('ai_ask');
  if (p == '/api/patient/urgent') return {'conversationId': _conv, 'messageId': 'm1', 'alertId': 'a1', 'call': '108'};
  if (p == '/api/patient/readings') return {'reading': {'id': 'r1'}, 'alerted': false};
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
    final body = req.body.isEmpty ? null : jsonDecode(req.body);
    _calls.add((req.method, req.url.path + (q.isEmpty ? '' : '?$q'), body));
    _calls.add((req.method, req.url.path, body));
    final a = _answer(req);
    if (a == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked: ${req.url.path}"}}', 404);
    return http.Response(jsonEncode(a), 200, headers: {'content-type': 'application/json'});
  });
}

Future<void> _settle(WidgetTester t, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 60));
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

/// A blank screen with an "Open" button that opens [stem] (a sheet) with [args].
Future<void> _host(WidgetTester t, String stem, {Object? args, WidgetBuilder? sheet}) async {
  await _pump(
    t,
    Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => sheet == null ? Nav.go(c, stem, args: args) : openSheet<void>(c, sheet),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await _settle(t);
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
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

  testWidgets('Home shows today\'s doses and visit to-dos; a dose is marked taken', (t) async {
    _serve();
    await _pump(t, const PatientHomeScreen(), stem: 'Main');
    expect(_called('GET', '/api/patient/home'), isTrue);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Upload HbA1c report'), findsOneWidget);
    expect(find.text('Note down questions for Dr. Sen'), findsOneWidget);
    expect(find.text('Visit with Dr. Sen'), findsOneWidget);
    expect(find.text('0 of 7 tasks done'), findsOneWidget);
    expect(find.text('Shared with Dr. Sen and Mou (dietician)'), findsOneWidget);

    await _tap(t, find.text('Glimepiride 1 mg'));
    expect(find.text('Skip this dose'), findsOneWidget);
    await _tap(t, find.widgetWithText(MpButton, 'Taken'));
    expect(_body('POST', '/api/patient/doses/6ac8d0f0bfcb2f5a9d64d644'), {'status': 'taken'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Home: a "Done" visit to-do is ticked off', (t) async {
    _serve();
    await _pump(t, const PatientHomeScreen(), stem: 'Main');
    await _tap(t, find.widgetWithText(P1SoftButton, 'Done').first);
    expect(_body('POST', '/api/patient/appointments/6ac8d0bd07fdebd2731d1ee3/todos/6ac8d0bd07fdebd2731d1ee6'), {'done': true});
    await _tearDown(t);
  });

  testWidgets('Patient-Adherence shows each doctor and sets the reminder', (t) async {
    _serve();
    await _host(t, 'Patient-Adherence');
    expect(_called('GET', '/api/patient/adherence?days=30'), isTrue);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('Diabetes & thyroid · City Care Clinic'), findsOneWidget);
    expect(find.text('Metformin 0% · Glimepiride 0%'), findsOneWidget);
    expect(find.textContaining('Most misses are in the morning.', findRichText: true), findsOneWidget);
    // Reminders are on, so it offers to change the time: pick one, then OK.
    await _tap(t, find.text('Change'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    final body = _body('PATCH', '/api/patient/me');
    expect((body['settings'] as Map)['medReminders'], true);
    expect((body['settings'] as Map)['reminderTimes'], {'morning': '07:30'});
    await _tearDown(t);
  });

  testWidgets('Patient-Track loads the tracked measures and saves the new choice', (t) async {
    _serve();
    await _host(t, 'Patient-Track');
    expect(_called('GET', '/api/patient/me'), isTrue);
    expect(find.text('Save · 2 selected'), findsOneWidget);
    await _tap(t, find.text('Weight'));
    await _tap(t, find.text('Save · 3 selected'));
    expect(_body('PATCH', '/api/patient/me'), {
      'trackedMeasures': ['blood_sugar', 'blood_pressure', 'weight'],
    });
    await _tearDown(t);
  });

  testWidgets('Patient-Log shares with the care team and saves a meal', (t) async {
    _serve();
    await _host(t, 'Patient-Log');
    expect(_called('GET', '/api/patient/logs/options'), isTrue);
    expect(find.text('Mou Banerjee'), findsOneWidget);
    expect(find.text('Dietician · reviews every 3 days'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    await _tap(t, find.text('Lunch'));
    await t.enterText(find.byType(TextField).first, '2 rotis, dal');
    await _tap(t, find.text('Save lunch'));
    final body = _body('POST', '/api/patient/logs');
    expect(body['type'], 'meal');
    expect(body['mealType'], 'lunch');
    expect(body['note'], '2 rotis, dal');
    expect(body['sharedWith'], [_mou, _sen]);
    await _tearDown(t);
  });

  testWidgets('Patient-Emergency alerts the chosen doctor and opens the urgent chat', (t) async {
    _serve();
    await _host(t, 'Patient-Emergency');
    expect(_called('GET', '/api/patient/urgent/doctors'), isTrue);
    expect(find.text('Dr. Rina Mitra'), findsOneWidget);
    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('In clinic · usually replies in 15 min'), findsOneWidget);
    await _tap(t, find.text('Dr. Arjun Sen'));
    expect(_body('POST', '/api/patient/urgent')['doctorId'], _sen);
    expect(_called('GET', '/api/conversations/$_conv/messages'), isTrue);
    expect(find.text('Chest tightness, hard to breathe.'), findsOneWidget);
    expect(find.textContaining('Dr. Sen has been alerted.', findRichText: true), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Patient-Chat shows the thread and sends an urgent message', (t) async {
    _serve();
    await _pump(t, const PatientChatScreen(), stem: 'Patient-Chat', args: {'conversationId': _conv, 'doctorId': _sen, 'doctorName': 'Dr. Arjun Sen'});
    expect(find.text('Should I take the tablet before or after food?'), findsOneWidget);
    expect(find.text('Dr. Arjun Sen'), findsOneWidget);
    expect(find.text('In clinic · usually replies in 15 min'), findsOneWidget);
    expect(_called('POST', '/api/conversations/$_conv/read'), isTrue);
    await t.enterText(find.byType(TextField), 'Leaving home now');
    await t.pump();
    await _tap(t, find.bySemanticsLabel('Send'));
    expect(_body('POST', '/api/conversations/$_conv/messages'), {'text': 'Leaving home now', 'isUrgent': true});
    await _tearDown(t);
  });

  testWidgets('Patient-AskAI sends the question and shows the answer with the emergency strip', (t) async {
    _serve();
    await _host(t, 'Patient-AskAI', args: {'prefill': 'I have chest pain'});
    await _tap(t, find.bySemanticsLabel('Send'));
    expect(_body('POST', '/api/patient/ai/ask'), {'text': 'I have chest pain', 'inputMode': 'typed'});
    expect(find.textContaining('MedPin AI is not available right now'), findsOneWidget);
    expect(find.textContaining('This may be an emergency.', findRichText: true), findsOneWidget);
    expect(find.text('Message your doctor now'), findsOneWidget);
    await _tearDown(t);
  });

  testWidgets('Reading sheet shows recent readings and saves a fasting sugar', (t) async {
    _serve();
    await _host(t, '', sheet: (_) => const P1ReadingSheet(measure: 'blood_sugar'));
    expect(_called('GET', '/api/patient/readings?measure=blood_sugar&days=30'), isTrue);
    expect(find.text('RECENT'), findsOneWidget);
    await t.enterText(find.byType(TextField), '118');
    await _tap(t, find.text('Save reading'));
    expect(_body('POST', '/api/patient/readings'), {'bloodSugar': 118, 'sugarType': 'fasting'});
    await _tearDown(t);
  });

  testWidgets('Hero-Carousel shows the current slides', (t) async {
    _serve();
    await _pump(t, const HeroCarouselScreen(), stem: 'Hero-Carousel');
    expect(find.text('Home carousel · 3 slides'), findsOneWidget);
    expect(find.text('Visit with Dr. Sen'), findsOneWidget);
    expect(find.text('Your Vitamin D is in'), findsOneWidget);
    expect(find.text('Health score up by 3'), findsOneWidget);
    await _tearDown(t);
  });
}

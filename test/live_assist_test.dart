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
import 'package:medpin_app/screens/doctor/chat_review.dart';
import 'package:medpin_app/screens/doctor/chat_review_detail.dart';
import 'package:medpin_app/screens/doctor/chat_summaries.dart';
import 'package:medpin_app/screens/doctor/doctor_ai.dart';
import 'package:medpin_app/screens/doctor/doctor_ai_chat.dart';
import 'package:medpin_app/screens/doctor/doctor_followups.dart';
import 'package:medpin_app/screens/doctor/feedback.dart';
import 'package:medpin_app/screens/doctor/knowledge.dart';
import 'package:medpin_app/screens/doctor/knowledge_editor.dart';
import 'package:medpin_app/screens/doctor/knowledge_shared.dart';
import 'package:medpin_app/screens/doctor/queue_list.dart';
import 'package:medpin_app/screens/doctor/queue_select.dart';

/// The "assist" group of doctor screens (queue, follow-ups, AI assistant,
/// chat review, knowledge base, feedback) rendered from real API responses
/// recorded from the local backend into test/fixtures/live/assist.

dynamic _fx(String name) => jsonDecode(File('test/fixtures/live/assist/$name.json').readAsStringSync());

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

/// Requests the screen made: "METHOD /path?query" and their JSON bodies.
final _calls = <String>[];
final _bodies = <String, Object?>{};

/// Serves fixtures by "METHOD /path" (query ignored). Unknown calls get a 404.
void _serve(Map<String, Object? Function(http.Request)> routes) {
  _calls.clear();
  _bodies.clear();
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = (_fx('session') as Map).cast<String, dynamic>();
  Api.I.client = MockClient((req) async {
    final key = '${req.method} ${req.url.path}';
    _calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    _bodies[key] = req.body.isEmpty ? null : jsonDecode(req.body);
    final h = routes[key];
    if (h == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"Not mocked: $key"}}', 404);
    final out = h(req);
    if (out is http.Response) return out;
    return http.Response(jsonEncode(out), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

Object? Function(http.Request) _f(String name) => (_) => _fx(name);

final _pushed = <RouteSettings>[];

class _Observer extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pushed.add(route.settings);
  }
}

Future<void> _settle(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

Future<void> _pump(WidgetTester t, Widget screen, {String name = 'screen', Map<String, dynamic>? args}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _pushed.clear();
  await t.pumpWidget(MaterialApp(
    theme: medpinTheme(),
    navigatorObservers: [_Observer()],
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name, arguments: args),
      builder: (_) => screen,
    ),
  ));
  await t.pump();
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
  await t.pump(const Duration(seconds: 7));
}

const _saltLake = '6ac8bbcee42c9f0836e98563';
const _newTown = '6ac8bbd08adea6a429a73189';

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
    await _loadFigtree();
  });

  testWidgets('Queue-Select: locations, "Don\'t ask again today" saves the default', (t) async {
    _serve({
      'GET /api/queue/locations': _f('queue_locations'),
      'PUT /api/doctor/default-queue-location': (_) => {'ok': true},
      'GET /api/queue': _f('queue'),
    });
    await _pump(t, const QueueSelectSheet(), name: 'Queue-Select');
    expect(find.text('City Care Clinic — Salt Lake'), findsOneWidget);
    expect(find.text('Clinic · 9:00 AM – 1:00 PM'), findsOneWidget);
    expect(find.text('Open now'), findsOneWidget);
    expect(find.textContaining('8 booked'), findsOneWidget);
    expect(find.textContaining('2 waiting'), findsOneWidget);
    expect(find.text('Closed today · next session Sat, 10 Oct'), findsOneWidget);
    await _tap(t, find.text('Show queue'));
    expect(_calls, contains('PUT /api/doctor/default-queue-location'));
    expect(_bodies['PUT /api/doctor/default-queue-location'], {'locationId': _saltLake});
    expect(_pushed.last.name, 'Queue-List');
    expect(_pushed.last.arguments, {'locationId': _saltLake});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Queue-Select falls back to the schedule when /api/queue/locations fails', (t) async {
    _serve({
      'GET /api/queue/locations': (_) => http.Response('{"error":{"code":"SERVER_ERROR","message":"Something went wrong. Please try again."}}', 500),
      'GET /api/doctor/locations': _f('doctor_locations'),
      'GET /api/queue': (r) => _fx(r.url.queryParameters['locationId'] == _newTown ? 'queue_newtown' : 'queue'),
    });
    await _pump(t, const QueueSelectSheet(), name: 'Queue-Select');
    expect(find.text('City Care Clinic — Salt Lake'), findsOneWidget);
    expect(find.text('City Care — New Town'), findsOneWidget);
    expect(find.textContaining('8 booked'), findsOneWidget);
    expect(_calls.where((c) => c.startsWith('GET /api/queue?locationId=')).length, 2);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Queue-List: live queue, stats and Start consultation', (t) async {
    _serve({'GET /api/queue/locations': _f('queue_locations'), 'GET /api/queue': _f('queue')});
    await _pump(t, const QueueListScreen(), name: 'Queue-List', args: {'locationId': _saltLake});
    final q = _fx('queue') as Map;
    expect(_calls, contains('GET /api/queue?locationId=$_saltLake'));
    expect(find.text('City Care Clinic — Salt Lake'), findsOneWidget);
    expect(find.text('All · ${q['stats']['all']}'), findsOneWidget);
    expect(find.text('Waiting · ${q['stats']['waiting']}'), findsOneWidget);
    for (final a in q['items'] as List) {
      expect(find.text(a['patient']['name'] as String), findsWidgets);
    }
    expect(find.textContaining('Updated'), findsOneWidget);
    final waiting = (q['items'] as List).firstWhere((a) => a['status'] == 'waiting' && a['isNext'] == true) as Map;
    expect(find.text('NEXT'), findsOneWidget);
    await _tap(t, find.text('Start consultation').first);
    expect(_pushed.last.name, 'Consult-Page');
    expect(_pushed.last.arguments, {'appointmentId': waiting['id'], 'patientId': waiting['patientId']});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-FollowUps: groups, counts and Remind', (t) async {
    _serve({
      'GET /api/follow-ups': _f('follow_ups'),
      'GET /api/doctor/locations': _f('doctor_locations'),
      'GET /api/doctor/profile': _f('doctor_profile'),
      'POST /api/follow-ups/6ac8bbd08adea6a429a73265/remind': (_) => {'id': '6ac8bbd08adea6a429a73265', 'remindersSent': 1},
    });
    await _pump(t, const DoctorFollowupsScreen(), name: 'Doctor-FollowUps');
    final f = _fx('follow_ups') as Map;
    expect(_calls.first, startsWith('GET /api/follow-ups?doctorId=me'));
    expect(find.text('All due · ${f['counts']['all']}'), findsOneWidget);
    expect(find.text('Not booked · ${f['counts']['notBooked']}'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Rahul Das'), findsOneWidget);
    expect(find.text('45 M · Hypertension · +91 98311 20764'), findsOneWidget);
    expect(find.text('10 days overdue'), findsOneWidget);
    expect(find.text('You advised on 15 Sep: “Come back with fasting sugar.”'), findsOneWidget);
    await _tap(t, find.text('Remind').first);
    expect(_calls, contains('POST /api/follow-ups/6ac8bbd08adea6a429a73265/remind'));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-AI: recent conversations', (t) async {
    _serve({'GET /api/ai/sessions': _f('ai_sessions')});
    await _pump(t, const DoctorAiScreen(), name: 'Doctor-AI');
    expect(find.text('What do you need, Dr. Sen?'), findsOneWidget);
    expect(find.text('Test assist'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-AI-Chat: thread, patient card, vote and ask', (t) async {
    const sid = '6ac8bdaf0640a42493dc534d';
    const pid = '6ac8bbcee42c9f0836e9857c';
    final ask = _fx('ai_ask') as Map;
    final answer = ask['answer'] as Map;
    _serve({
      'GET /api/ai/sessions/$sid/messages': _f('ai_messages'),
      'GET /api/patients/$pid': _f('patient'),
      'POST /api/ai/messages/${answer['id']}/vote': (_) => {...answer, 'vote': 1},
      'POST /api/ai/sessions/$sid/messages': (_) => ask,
    });
    await _pump(t, const DoctorAiChatScreen(), name: 'Doctor-AI-Chat', args: {'sessionId': sid, 'patientId': pid});
    expect(find.text('Summarise her recent abnormal results'), findsOneWidget);
    expect(find.textContaining('Glycaemic Markers'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('Priya Sharma'), findsOneWidget); // "Talking about" chip
    expect(find.text('Priya Sharma, 29 F'), findsOneWidget);
    expect(find.text('Allergic to Sulfa drugs'), findsOneWidget);
    expect(find.text('LDL cholesterol'), findsOneWidget);
    expect(find.text('162 mg/dL'), findsOneWidget);
    expect(find.text('7.2%'), findsOneWidget);
    expect(find.text('Metformin 500 mg '), findsNothing);
    expect(find.text('74'), findsOneWidget);
    await _tap(t, find.bySemanticsLabel('Helpful').first);
    expect(_calls, contains('POST /api/ai/messages/${answer['id']}/vote'));
    expect(_bodies['POST /api/ai/messages/${answer['id']}/vote'], {'vote': 1});

    await t.enterText(find.byType(TextField), 'Any new results?');
    await t.pump();
    await _tap(t, find.bySemanticsLabel('Send').first);
    expect(_bodies['POST /api/ai/sessions/$sid/messages'], {'text': 'Any new results?', 'inputMode': 'typed'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Doctor-AI-Chat: a new conversation asks the question it was opened with', (t) async {
    final ask = _fx('ai_ask') as Map;
    _serve({
      'POST /api/ai/sessions': (_) => _fx('ai_session_created'),
      'POST /api/ai/sessions/6ac8bdaf0640a42493dc534d/messages': (_) => ask,
    });
    await _pump(t, const DoctorAiChatScreen(), name: 'Doctor-AI-Chat', args: {'text': 'Who is next in today’s queue?'});
    await _settle(t);
    expect(_calls, contains('POST /api/ai/sessions'));
    expect(_bodies['POST /api/ai/sessions/6ac8bdaf0640a42493dc534d/messages'], {'text': 'Who is next in today’s queue?', 'inputMode': 'typed'});
    expect(find.textContaining('Glycaemic Markers'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Chat-Review: flagged answers, most urgent first', (t) async {
    _serve({'GET /api/inbox/reviews': _f('reviews_all')});
    await _pump(t, const ChatReviewScreen(), name: 'Chat-Review');
    expect(find.text('Flagged (2)'), findsOneWidget);
    expect(find.text('Rahul Das'), findsOneWidget);
    expect(find.text('Symptom question: BP with headache'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.textContaining('AI: That reading is high.'), findsOneWidget);
    await _tap(t, find.text('Rahul Das'));
    expect(_pushed.last.name, 'Chat-Review-Detail');
    expect((_pushed.last.arguments as Map)['reviewId'], '6ac8bbd08adea6a429a7341f');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Chat-Review-Detail: thread with the flagged turn, reply and Mark reviewed', (t) async {
    const cid = '6ac8bbd08adea6a429a7340c';
    const rid = '6ac8bbd08adea6a429a7341f';
    _serve({
      'GET /api/inbox/reviews': _f('reviews_all'),
      'GET /api/conversations/$cid/messages': _f('review_thread'),
      'GET /api/patients/6ac8bbd08adea6a429a731b7': (_) => {'patient': {'name': 'Rahul Das', 'phone': '9831120764'}},
      'POST /api/conversations/$cid/messages': (_) => {'message': {}},
      'POST /api/inbox/reviews/$rid/reviewed': (_) => {'id': rid, 'status': 'reviewed'},
    });
    await _pump(t, const ChatReviewDetailScreen(), name: 'Chat-Review-Detail', args: {'reviewId': rid});
    expect(find.text('Rahul Das'), findsOneWidget);
    expect(find.text('Flagged · symptom question'), findsOneWidget);
    expect(find.text('BP is 172/104 and I have a headache.'), findsOneWidget);
    expect(find.text('Flagged for review'), findsOneWidget);
    expect(find.text('Urgency: High'), findsOneWidget);
    expect(find.text('1.2 s'), findsOneWidget);
    expect(find.text('No citations'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Please come in today.');
    await _tap(t, find.bySemanticsLabel('Send reply'));
    expect(_bodies['POST /api/conversations/$cid/messages'], {'text': 'Please come in today.'});
    await _tap(t, find.text('Mark reviewed'));
    expect(_calls, contains('POST /api/inbox/reviews/$rid/reviewed'));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Chat-Summaries: today, my patients, then the whole practice', (t) async {
    _serve({'GET /api/inbox/summaries': _f('summaries')});
    await _pump(t, const ChatSummariesScreen(), name: 'Chat-Summaries');
    expect(_calls.first, 'GET /api/inbox/summaries?date=today&scope=mine');
    expect(find.text('5 patients wrote today · 3 need a reply', findRichText: true), findsOneWidget);
    for (final m in (_fx('summaries') as Map)['items'] as List) {
      expect(find.text(m['patientId']['name'] as String), findsOneWidget);
    }
    expect(find.text('Flagged: dosage question'), findsOneWidget);
    expect(find.text('Needs reply'), findsNWidgets(3));
    await _tap(t, find.text('Whole practice'));
    expect(_calls.last, 'GET /api/inbox/summaries?date=today');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Knowledge: practice and shared entries with counts', (t) async {
    _serve({
      'GET /api/knowledge': (r) => _fx(r.url.queryParameters['shared'] == 'true' ? 'knowledge_shared_list' : 'knowledge'),
    });
    await _pump(t, const KnowledgeScreen(), name: 'Knowledge');
    final k = _fx('knowledge') as Map;
    final total = (k['items'] as List).length + 1;
    expect(find.text('All · $total'), findsOneWidget);
    expect(find.text('Approved · ${(k['counts'] as Map)['approved'] + 1}'), findsOneWidget);
    expect(find.text('When to repeat HbA1c'), findsOneWidget);
    expect(find.text('Thyroid tablet on an empty stomach'), findsOneWidget);
    expect(find.text('Shared by MedPin'), findsOneWidget);
    expect(find.textContaining('Retired 12 Sep'), findsOneWidget);
    await _tap(t, find.text('Thyroid tablet on an empty stomach'));
    expect(_pushed.last.name, 'Knowledge-Shared');
    expect(_pushed.last.arguments, {'knowledgeId': '6ac8bbd18adea6a429a73467'});
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Knowledge-Editor: loads the entry and saves the draft', (t) async {
    const id = '6ac8bbd18adea6a429a73461';
    _serve({
      'GET /api/knowledge/$id': _f('knowledge_entry'),
      'PATCH /api/knowledge/$id': (_) => _fx('knowledge_entry'),
    });
    await _pump(t, const KnowledgeEditorScreen(), name: 'Knowledge-Editor', args: {'knowledgeId': id});
    expect(find.text('When to repeat HbA1c'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Diabetes'), findsOneWidget);
    expect(find.text('hba1c'), findsOneWidget);
    await _tap(t, find.text('Save draft'));
    final body = _bodies['PATCH /api/knowledge/$id'] as Map;
    expect(body['title'], 'When to repeat HbA1c');
    expect(body['category'], 'diabetes');
    expect(body['language'], 'en');
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Knowledge-Shared: shared entry and Adopt', (t) async {
    const id = '6ac8bbd18adea6a429a73467';
    _serve({
      'GET /api/knowledge/$id': _f('knowledge_shared'),
      'POST /api/knowledge/$id/adopt': (_) => {'ok': true, 'adopted': true},
    });
    await _pump(t, const KnowledgeSharedScreen(), name: 'Knowledge-Shared', args: {'knowledgeId': id});
    expect(find.text('Thyroid tablet on an empty stomach'), findsOneWidget);
    expect(find.text('Not yet adopted by your practice'), findsOneWidget);
    expect(find.text('American Thyroid Association, Hypothyroidism guidelines'), findsOneWidget);
    expect(find.text('Thyroid'), findsOneWidget);
    expect(find.textContaining('MedPin clinical team · 9 Oct 2026'), findsOneWidget);
    await _tap(t, find.text('Adopt for my practice'));
    expect(_calls, contains('POST /api/knowledge/$id/adopt'));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });

  testWidgets('Feedback: counts, read receipts, replies; unread items are marked read', (t) async {
    _serve({
      'GET /api/feedback': _f('feedback'),
      'POST /api/feedback/6ac8bbd18adea6a429a7346a/read': (_) => {},
      'POST /api/feedback/6ac8bbd18adea6a429a7346b/read': (_) => {},
      'POST /api/feedback/6ac8bbd18adea6a429a7346c/read': (_) => {},
    });
    await _pump(t, const FeedbackScreen(), name: 'Feedback');
    expect(find.text('All · 4'), findsOneWidget);
    expect(find.text('Care · 3'), findsOneWidget);
    expect(find.text('App · 1'), findsOneWidget);
    expect(find.text('Moumita Roy'), findsOneWidget);
    expect(find.text('Read by Dr. Sen, Tania'), findsOneWidget);
    expect(find.text('Thank you, Moumita. See you at your follow-up.'), findsOneWidget);
    expect(find.text('Clinic replied · Tania Ghosh · 8 Oct'), findsOneWidget);
    expect(_calls.where((c) => c.endsWith('/read')).length, 3);
    expect(_calls, isNot(contains('POST /api/feedback/6ac8bbd18adea6a429a73469/read')));
    expect(t.takeException(), isNull);
    await _tearDown(t);
  });
}

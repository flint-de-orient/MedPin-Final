import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

/// Patient chat feels instant: the message shows before the server answers,
/// "MedPin AI is typing…" shows until the reply arrives, and a failed send can
/// be retried.
void main() {
  late List<Map<String, dynamic>> thread;
  late Completer<void> serverGate;
  var failNext = false;
  var aiAnswers = false;

  setUpAll(() {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
  });

  setUp(() {
    thread = [
      {'id': 'm1', 'senderType': 'doctor', 'text': 'Hello Priya', 'kind': 'text', 'createdAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String()},
    ];
    serverGate = Completer<void>();
    failNext = false;
    aiAnswers = false;
    Session.I
      ..accessToken = 'a'
      ..refreshToken = 'r'
      ..account = {'user': {'id': 'u2', 'name': 'Priya Sharma', 'phone': '9230592842'}, 'memberships': [], 'patientId': 'pt1', 'landing': 'Main'};
    Api.I.client = MockClient((req) async {
      const json = {'content-type': 'application/json'};
      final p = req.url.path;
      if (p == '/api/patient/my-doctors') {
        return http.Response(jsonEncode([
          {'doctorId': 'd1', 'name': 'Dr. Arjun Sen', 'role': 'doctor', 'conversationId': 'c1', 'presence': 'away'},
        ]), 200, headers: json);
      }
      if (p == '/api/conversations/c1/messages' && req.method == 'GET') {
        if (aiAnswers && thread.last['senderType'] == 'patient') {
          thread.add({'id': 'ai1', 'senderType': 'ai', 'senderLabel': 'MedPin AI', 'text': 'Take it after breakfast.', 'kind': 'text', 'createdAt': DateTime.now().toIso8601String()});
        }
        return http.Response(jsonEncode({'conversation': {'id': 'c1'}, 'items': thread}), 200, headers: json);
      }
      if (p == '/api/conversations/c1/messages' && req.method == 'POST') {
        await serverGate.future; // the server is slow
        if (failNext) {
          failNext = false;
          return http.Response('{"error":{"code":"NETWORK","message":"x"}}', 503, headers: json);
        }
        final text = (jsonDecode(req.body) as Map)['text'];
        thread.add({'id': 'm${thread.length + 1}', 'senderType': 'patient', 'mine': true, 'text': text, 'kind': 'text', 'createdAt': DateTime.now().toIso8601String()});
        return http.Response(jsonEncode({'message': thread.last, 'aiPending': true}), 201, headers: json);
      }
      return http.Response('{"ok":true}', 200, headers: json);
    });
  });

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> send(WidgetTester t, String text) async {
    await t.enterText(find.byType(EditableText).last, text);
    await t.pump();
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    if (find.text(text).evaluate().isEmpty) {
      // No keyboard send action: the send button.
      await t.tap(find.bySemanticsLabel('Send').last);
      await t.pump();
    }
  }

  testWidgets('message shows at once, then AI typing, then the reply', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: medpinTheme(),
      navigatorKey: Nav.key,
      onGenerateRoute: (s) => MaterialPageRoute(settings: RouteSettings(name: 'Patient-DoctorChat', arguments: const {'doctorId': 'd1'}), builder: (_) => const PatientDoctorchatScreen()),
    ));
    await settle(t);
    expect(find.text('Hello Priya'), findsOneWidget);

    await send(t, 'Before or after breakfast?');
    // Before the server answers: already on screen, marked Sending….
    expect(find.text('Before or after breakfast?'), findsOneWidget);
    expect(find.text('Sending…'), findsOneWidget);

    aiAnswers = true;
    serverGate.complete();
    await settle(t);
    expect(find.text('Sending…'), findsNothing);
    expect(find.text('Before or after breakfast?'), findsOneWidget, reason: 'shown once, from the server now');
    // The AI reply comes with the next check.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await settle(t);
    expect(find.text('Take it after breakfast.'), findsOneWidget);
    expect(find.text('MedPin AI is typing…'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
  });

  testWidgets('a failed send can be retried', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: medpinTheme(),
      navigatorKey: Nav.key,
      onGenerateRoute: (s) => MaterialPageRoute(settings: RouteSettings(name: 'Patient-DoctorChat', arguments: const {'doctorId': 'd1'}), builder: (_) => const PatientDoctorchatScreen()),
    ));
    await settle(t);
    failNext = true;
    serverGate.complete();
    await send(t, 'Hello?');
    await settle(t);
    expect(find.text('Not sent · Tap to retry'), findsOneWidget);
    await t.tap(find.text('Not sent · Tap to retry'));
    await settle(t);
    expect(find.text('Not sent · Tap to retry'), findsNothing);
    expect(find.text('Hello?'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
  });
}

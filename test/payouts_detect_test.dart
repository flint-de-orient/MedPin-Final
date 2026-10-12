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
import 'package:medpin_app/screens/doctor/profile_payouts.dart';

/// Payouts: the IFSC fills in the bank and branch, the UPI ID names its app,
/// the account number is typed twice, and a wrong IFSC can't be saved.
void main() {
  final calls = <(String, String, Object?)>[];

  setUpAll(() {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
  });

  setUp(() {
    calls.clear();
    Session.I
      ..accessToken = 'a'
      ..refreshToken = 'r'
      ..account = {
        'user': {'id': 'u1', 'name': 'Dr. Arjun Sen', 'phone': '9876518210'},
        'memberships': [
          {'id': 'm1', 'practiceId': 'p1', 'practiceName': 'City Care', 'role': 'doctor', 'isOwner': true, 'status': 'active'},
        ],
        'patientId': null,
        'landing': 'Doctor-Dashboard',
      };
    Api.I.client = MockClient((req) async {
      calls.add((req.method, req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
      const json = {'content-type': 'application/json'};
      final p = req.url.path;
      Object? out;
      if (p == '/api/doctor/profile' && req.method == 'GET') {
        out = {'displayName': 'Dr. Arjun Sen', 'payout': {}};
      } else if (p == '/api/doctor/payouts') {
        out = {'waiting': {'amount': 0, 'count': 0}, 'items': []};
      } else if (p == '/api/banks/ifsc/SBIN0000001') {
        out = {'valid': true, 'found': true, 'ifsc': 'SBIN0000001', 'bank': 'State Bank of India', 'branch': 'Kolkata Main', 'city': 'Kolkata'};
      } else if (p.startsWith('/api/banks/ifsc/')) {
        out = {'valid': true, 'found': false, 'ifsc': p.split('/').last};
      } else if (p == '/api/banks/upi') {
        final vpa = req.url.queryParameters['vpa'] ?? '';
        out = vpa.endsWith('@oksbi')
            ? {'valid': true, 'known': true, 'handle': 'oksbi', 'app': 'Google Pay', 'bank': 'State Bank of India'}
            : {'valid': true, 'known': false, 'handle': vpa.split('@').last};
      } else if (p == '/api/doctor/profile' && req.method == 'PATCH') {
        out = {'ok': true};
      }
      if (out == null) return http.Response('{"error":{"code":"NOT_MOCKED","message":"x"}}', 404, headers: json);
      return http.Response(jsonEncode(out), 200, headers: json);
    });
  });

  Future<void> settle(WidgetTester t, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Finder field(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: find.byType(EditableText),
      );

  testWidgets('IFSC fills the bank, UPI names the app, numbers must match', (t) async {
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), navigatorKey: Nav.key, home: const ProfilePayoutsScreen()));
    await settle(t);

    // UPI: the handle names the app and bank.
    await t.enterText(field('UPI ID'), 'tanmoydas5242@oksbi');
    await settle(t);
    expect(find.text('Google Pay · State Bank of India'), findsOneWidget);
    await t.enterText(field('UPI ID'), 'me@newbankx');
    await settle(t);
    expect(find.textContaining('isn’t a UPI app we know'), findsOneWidget);
    await t.enterText(field('UPI ID'), 'tanmoydas5242@oksbi');
    await settle(t);

    // IFSC: a wrong one is flagged and can't be saved.
    await t.enterText(field('IFSC'), 'SBIN0999999');
    await settle(t);
    expect(find.textContaining('doesn’t exist'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget, reason: 'bank typed by hand while the IFSC is unknown');

    // A real one fills in the bank and branch; the Bank box goes away.
    await t.enterText(field('IFSC'), 'sbin0000001');
    await settle(t);
    expect(find.text('State Bank of India · Kolkata Main, Kolkata'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);

    // Account number twice.
    await t.enterText(field('Account holder'), 'Tanmoy Das');
    await t.enterText(field('Account number'), '30123456789');
    await settle(t, 3);
    await t.enterText(field('Re-enter account number'), '30123456788');
    await settle(t, 3);
    expect(find.text('The two numbers don’t match'), findsOneWidget);
    await t.tap(find.text('Save'));
    await settle(t, 3);
    expect(calls.any((c) => c.$1 == 'PATCH'), isFalse, reason: 'not saved while the numbers differ');
    await t.enterText(field('Re-enter account number'), '30123456789');
    await settle(t, 3);
    await t.tap(find.text('Save'));
    await settle(t);
    final body = (calls.lastWhere((c) => c.$1 == 'PATCH').$3 as Map)['payout'] as Map;
    expect(body['upiId'], 'tanmoydas5242@oksbi');
    expect(body['ifsc'], 'SBIN0000001');
    expect(body['bankName'], 'State Bank of India');
    expect(body['accountNumber'], '30123456789');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}

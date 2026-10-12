import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/api.dart';
import 'package:medpin_app/data/checkout.dart';
import 'package:medpin_app/data/config.dart';
import 'package:medpin_app/data/session.dart';

/// In-app payment: the Pay sheet, checkout (test mode without Razorpay keys),
/// the server confirm, and the success sheet. Cancelling charges nothing.
void main() {
  final calls = <(String, String, Object?)>[];
  var offline = false;

  setUpAll(() {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    AppMode.preview = false;
  });

  setUp(() {
    calls.clear();
    offline = false;
    Session.I
      ..accessToken = 'a'
      ..refreshToken = 'r'
      ..account = {'user': {'id': 'u2', 'name': 'Priya Sharma', 'phone': '9230592842'}, 'memberships': [], 'patientId': 'pt1', 'landing': 'Main'};
    Api.I.client = MockClient((req) async {
      calls.add((req.method, req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
      const json = {'content-type': 'application/json'};
      if (req.url.path == '/api/patient/checkout') {
        if (offline) return http.Response('{"error":{"code":"ONLINE_PAY_OFF","message":"This clinic takes the fee at the visit"}}', 409, headers: json);
        return http.Response(jsonEncode({
          'kind': 'fee', 'id': 'ap1', 'amount': 600, 'currency': 'INR', 'title': 'Consultation fee', 'detail': 'Dr. Arjun Sen · Salt Lake',
          'test': true, 'orderId': 'order_test_ap1', 'prefill': {'name': 'Priya Sharma', 'contact': '+919230592842'},
        }), 200, headers: json);
      }
      if (req.url.path == '/api/patient/checkout/confirm') {
        return http.Response(jsonEncode({'paid': true, 'paymentId': 'pay_test_abc', 'amount': 600}), 200, headers: json);
      }
      return http.Response('{"error":{"code":"NOT_MOCKED","message":"x"}}', 404, headers: json);
    });
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<Future<bool>> start(WidgetTester t, {String? later, bool optional = false}) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), navigatorKey: Nav.key, home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    })));
    final f = Checkout.pay(ctx, kind: 'fee', id: 'ap1', laterLabel: later, optional: optional);
    await settle(t);
    return f;
  }

  testWidgets('pay a visit fee: sheet, checkout, confirm, success', (t) async {
    final paid = await start(t);
    expect(find.text('₹600'), findsOneWidget);
    expect(find.text('Consultation fee'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Net banking'), findsOneWidget);
    expect(find.text('Test mode · no money moves'), findsOneWidget);
    await t.tap(find.text('Pay ₹600'));
    await settle(t);
    expect(find.text('Test checkout'), findsOneWidget);
    await t.tap(find.text('Cards'));
    await t.pump();
    await t.tap(find.text('Pay ₹600 (test)'));
    await settle(t);
    final confirm = calls.lastWhere((c) => c.$2 == '/api/patient/checkout/confirm').$3 as Map;
    expect(confirm, {'kind': 'fee', 'id': 'ap1', 'orderId': 'order_test_ap1'});
    expect(find.text('Payment successful'), findsOneWidget);
    expect(find.text('Reference pay_test_abc'), findsOneWidget);
    await t.tap(find.text('Done'));
    await settle(t);
    expect(await paid, isTrue);
  });

  testWidgets('cancelling charges nothing; "Pay at the clinic" skips', (t) async {
    var f = await start(t, later: 'Pay at the clinic');
    await t.tap(find.text('Pay at the clinic'));
    await settle(t);
    expect(await f, isFalse);
    expect(calls.any((c) => c.$2 == '/api/patient/checkout/confirm'), isFalse);

    f = await start(t);
    await t.tap(find.text('Pay ₹600'));
    await settle(t);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(await f, isFalse);
    expect(calls.any((c) => c.$2 == '/api/patient/checkout/confirm'), isFalse);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('right after booking, a cash-only clinic is skipped quietly', (t) async {
    offline = true;
    final f = await start(t, optional: true);
    expect(await f, isFalse);
    expect(find.textContaining('takes the fee'), findsNothing, reason: 'no error after a booking');
  });
}

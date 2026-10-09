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
import 'package:medpin_app/screens/doctor/doctor_dashboard.dart';
import 'package:medpin_app/screens/patient/patient_home.dart';
import 'package:medpin_app/screens/staff/staff_today.dart';

/// The home screens rendered from real API responses (recorded from the local
/// backend into test/fixtures/live), at three phone widths.
Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

Map<String, dynamic> _fixture(String role) =>
    jsonDecode(File('test/fixtures/live/$role.json').readAsStringSync()) as Map<String, dynamic>;

/// Signs the fake session in and answers the screen's one API call.
void _serve(Map<String, dynamic> f) {
  Session.I
    ..accessToken = 'test-access'
    ..refreshToken = 'test-refresh'
    ..account = (f['session'] as Map).cast<String, dynamic>();
  Api.I.client = MockClient((req) async {
    if (req.url.path == f['path']) return http.Response(jsonEncode(f['data']), 200, headers: {'content-type': 'application/json'});
    return http.Response('{"error":{"code":"NOT_MOCKED","message":"not mocked"}}', 404);
  });
}

Future<void> _pumpLive(WidgetTester t, Widget screen, double width) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: medpinTheme(), home: screen));
  // Let the (mocked) request complete, then build with the data.
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
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

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('Doctor-Dashboard with live data at ${width.toInt()}px', (t) async {
      final f = _fixture('doctor');
      _serve(f);
      await _pumpLive(t, const DoctorDashboardScreen(), width);
      final d = f['data'] as Map;
      expect(find.text('Hi, Dr. Sen'), findsOneWidget);
      expect(find.text('${(d['today'] as Map)['total']}'), findsWidgets);
      expect(find.textContaining(d['practiceName'] as String), findsOneWidget);
      expect(t.takeException(), isNull);
      await _tearDown(t);
    });

    testWidgets('Staff-Today with live data at ${width.toInt()}px', (t) async {
      final f = _fixture('staff');
      _serve(f);
      await _pumpLive(t, const StaffTodayScreen(), width);
      expect(find.textContaining(', Tania'), findsOneWidget);
      for (final a in (f['data'] as Map)['items'] as List) {
        expect(find.text(((a as Map)['patient'] as Map)['name'] as String), findsWidgets);
      }
      expect(t.takeException(), isNull);
      await _tearDown(t);
    });

    testWidgets('Patient home with live data at ${width.toInt()}px', (t) async {
      final f = _fixture('patient');
      _serve(f);
      await _pumpLive(t, const PatientHomeScreen(), width);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(t.takeException(), isNull);
      await _tearDown(t);
    });
  }

  testWidgets('an API error shows the message and a retry', (t) async {
    final f = _fixture('doctor');
    _serve(f);
    Api.I.client = MockClient((_) async => http.Response('{"error":{"code":"SERVER_ERROR","message":"Something went wrong. Please try again."}}', 500));
    await _pumpLive(t, const DoctorDashboardScreen(), 390);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await _tearDown(t);
  });
}

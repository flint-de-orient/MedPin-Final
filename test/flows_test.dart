import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/app/launcher.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/app/splash.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/session.dart';
import 'package:medpin_app/screens/auth/auth_login.dart';
import 'package:medpin_app/screens/doctor/doctor_dashboard.dart';
import 'package:medpin_app/screens/doctor/doctor_history.dart';
import 'package:medpin_app/screens/doctor/doctor_messages.dart';
import 'package:medpin_app/screens/doctor/doctor_patients.dart';
import 'package:medpin_app/screens/doctor/doctor_reports.dart';
import 'package:medpin_app/screens/doctor/pp_prescriptions.dart';
import 'package:medpin_app/screens/doctor/pp_summary.dart';
import 'package:medpin_app/screens/doctor/pp_tests.dart';
import 'package:medpin_app/screens/doctor/pp_treatment.dart';
import 'package:medpin_app/screens/patient/patient_doctors.dart';
import 'package:medpin_app/screens/patient/patient_finddoctor.dart';
import 'package:medpin_app/screens/patient/patient_home.dart';
import 'package:medpin_app/screens/patient/patient_me.dart';
import 'package:medpin_app/screens/patient/patient_medicines.dart';
import 'package:medpin_app/screens/patient/patient_records.dart';

Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the floating-nav tab with [label] (the last match is the nav one).
Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.text(label).last);
  await _settle(t);
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore(); // no secure storage plugin in tests
    await _loadFigtree();
  });

  testWidgets('splash plays, then lands on sign-in when signed out', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), home: const SplashScreen()));
    // Let the mark layers decode (real async), then run the animation.
    for (var i = 0; i < 20 && find.byType(CustomPaint).evaluate().length < 2; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(find.byType(AuthLoginScreen), findsNothing);
    await t.pump(const Duration(milliseconds: 2800));
    await _settle(t);
    await t.pump(const Duration(milliseconds: 800));
    expect(find.byType(AuthLoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('doctor: sign in, then every bottom tab', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), home: const LauncherScreen()));

    await t.tap(find.text('Doctor app'));
    await _settle(t);
    expect(find.text('Sign in'), findsWidgets);

    await t.tap(find.text('Send code'));
    await _settle(t);
    await t.tap(find.text('Verify'));
    await _settle(t);
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);
    expect(find.text('Hi, Dr. Sen'), findsOneWidget);

    await _tab(t, 'Patients');
    expect(find.byType(DoctorPatientsScreen), findsOneWidget);
    await _tab(t, 'Messages');
    expect(find.byType(DoctorMessagesScreen), findsOneWidget);
    await _tab(t, 'Reports');
    expect(find.byType(DoctorReportsScreen), findsOneWidget);
    await _tab(t, 'History');
    expect(find.byType(DoctorHistoryScreen), findsOneWidget);
    await _tab(t, 'Home');
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);

    // Quick action that opens a sheet over the dashboard.
    await t.tap(find.text('Patient queue'));
    await _settle(t);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets('doctor: a patient opens the tabbed profile, every tab works', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), home: const DoctorPatientsScreen()));
    await _settle(t);

    await t.tap(find.text('View').first);
    await _settle(t);
    expect(find.byType(PpSummaryScreen), findsOneWidget);
    expect(find.text('Start consultation'), findsOneWidget);

    Future<void> tabTo(String label) async {
      final f = find.text(label).first;
      await t.ensureVisible(f);
      await _settle(t);
      await t.tap(f);
      await _settle(t);
    }

    await tabTo('Prescriptions');
    expect(find.byType(PpPrescriptionsScreen), findsOneWidget);
    await tabTo('Test results');
    expect(find.byType(PpTestsScreen), findsOneWidget);
    await tabTo('Treatment plan');
    expect(find.byType(PpTreatmentScreen), findsOneWidget);
    await tabTo('Summary');
    expect(find.byType(PpSummaryScreen), findsOneWidget);

    // Back returns to the patient list, not through every tab.
    await t.tap(find.bySemanticsLabel('Back').first);
    await _settle(t);
    expect(find.byType(DoctorPatientsScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('patient: find a new doctor with MedPin AI', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), home: const PatientDoctorsScreen()));
    await _settle(t);

    // The banner is first on the Doctor tab.
    expect(find.text('Find a new doctor'), findsOneWidget);
    await t.tap(find.text('Search doctors'));
    await _settle(t);
    expect(find.byType(PatientFinddoctorScreen), findsOneWidget);
    expect(find.textContaining('All doctors', findRichText: true), findsOneWidget);
    expect(find.text('Dr. Suchitra Bose'), findsOneWidget); // nearest first

    await t.enterText(find.byType(TextField), 'High sugar and always tired, Bengali doctor');
    await t.tap(find.text('Find doctors'));
    await t.pump(const Duration(milliseconds: 900));
    await _settle(t);
    expect(find.textContaining('Best matches', findRichText: true), findsOneWidget);
    expect(find.textContaining('Diabetes and thyroid specialist', findRichText: true), findsOneWidget);
    expect(find.text('Dr. Ananya Ghosh'), findsOneWidget);
    expect(find.text('Dr. Rina Mitra'), findsNothing);

    // Chest pain also raises the emergency card.
    await t.enterText(find.byType(TextField), 'chest pain and sweating');
    await t.ensureVisible(find.text('Find doctors'));
    await _settle(t);
    await t.tap(find.text('Find doctors'));
    await t.pump(const Duration(milliseconds: 900));
    await _settle(t);
    expect(find.text('This may be an emergency'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('patient: home and the bottom tabs', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: medpinTheme(), home: const LauncherScreen()));

    await t.tap(find.text('Patient app'));
    await _settle(t);
    expect(find.byType(PatientHomeScreen), findsOneWidget);

    await _tab(t, 'Doctor');
    expect(find.byType(PatientDoctorsScreen), findsOneWidget);
    await _tab(t, 'Medicines');
    expect(find.byType(PatientMedicinesScreen), findsOneWidget);
    await _tab(t, 'Records');
    expect(find.byType(PatientRecordsScreen), findsOneWidget);
    await _tab(t, 'Profile');
    expect(find.byType(PatientMeScreen), findsOneWidget);
    expect(find.text('Your consent code'), findsOneWidget);
    await _tab(t, 'Home');
    expect(find.byType(PatientHomeScreen), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  });
}

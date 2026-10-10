import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/app/launcher.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/session.dart';

/// Loads the real Figtree files so text measures like the app, not like the
/// test font (Ahem), which would make every check meaningless.
Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

Widget _host(ScreenSpec s) => MaterialApp(
      theme: medpinTheme(),
      home: s.sheet
          // Sheets are shown on their own, docked at the bottom like the modal.
          ? Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Builder(builder: s.builder)))
          : Builder(builder: s.builder),
    );

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore(); // no secure storage plugin in tests
    await _loadFigtree();
  });

  test('every design artboard has a screen', () {
    // 96 artboards + the patient Profile tab + Find a doctor + 9 doctor screens
    // added after the design (settings, AI history, lab report, entry options).
    expect(screenRegistry.length, 112);
    expect(screenRegistry.values.where((s) => s.panel == 'doctor').length, 88);
    expect(screenRegistry.values.where((s) => s.panel == 'staff').length, 3);
    expect(screenRegistry.values.where((s) => s.panel == 'patient').length, 21);
    for (final s in screenRegistry.values.where((s) => s.sheet)) {
      expect(screenRegistry.containsKey(s.parent), isTrue, reason: '${s.stem} parent ${s.parent}');
    }
  });

  testWidgets('launcher builds', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: medpinTheme(), home: const LauncherScreen()));
    expect(find.text('Choose an app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Every screen must lay out without overflow or exceptions on small,
  // design-size and large phones.
  for (final s in screenRegistry.values) {
    for (final width in const [360.0, 390.0, 430.0]) {
      testWidgets('${s.stem} builds at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(s));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);

        // Dispose, then let any running animations or timers wind down.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 7));
      });
    }
  }
}

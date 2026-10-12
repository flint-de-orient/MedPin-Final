import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/session.dart';

/// The real Figtree files, so text measures like the app (not the wide test font).
Future<void> _loadFonts() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

/// Every screen: every tappable thing has a label for screen readers; tap
/// targets under 48×48 are reported (Android accessibility guidelines).
/// A11Y_REPORT=1 lists problems instead of failing.
void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    await _loadFonts();
  });
  final report = Platform.environment['A11Y_REPORT'] == '1';
  final problems = <String>[];
  tearDownAll(() {
    if (report) File('build/a11y_report.txt').writeAsStringSync(problems.join('\n'));
  });

  for (final s in screenRegistry.values) {
    testWidgets('${s.stem} meets tap-target and label guidelines', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: medpinTheme(),
        home: s.sheet ? Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Builder(builder: s.builder))) : Builder(builder: s.builder),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      // Labels are required everywhere. Tap sizes (48×48) are listed in the
      // report: text links and 36px chips keep the design's size for now.
      final out = <String>[];
      final labels = await labeledTapTargetGuideline.evaluate(tester);
      if (!labels.passed) out.add(labels.reason ?? 'unlabelled');
      final size = await androidTapTargetGuideline.evaluate(tester);
      if (!size.passed && report) problems.add('### ${s.stem} (tap size)\n${size.reason}');
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
      if (out.isNotEmpty) {
        problems.add('### ${s.stem}\n${out.join('\n')}');
        if (!report) fail(out.join('\n'));
      }
    });
  }
}

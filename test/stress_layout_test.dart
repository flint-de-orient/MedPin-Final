import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/session.dart';

/// Small phones and large text (and Bengali, the longest translation):
/// every screen must lay out without overflow. Set STRESS_REPORT=1 to list
/// problems instead of failing on the first.
Future<void> _loadFonts() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

const _cases = [
  ('320px', Size(320, 640), 1.0, 'en'),
  ('360px text 130%', Size(360, 760), 1.3, 'en'),
  ('360px Bengali', Size(360, 760), 1.0, 'bn'),
];

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    Session.I.store = MemorySessionStore();
    await _loadFonts();
  });

  final report = Platform.environment['STRESS_REPORT'] == '1';
  final problems = <String>[];
  tearDownAll(() {
    if (report) File('build/stress_report.txt').writeAsStringSync(problems.join('\n'));
  });

  for (final s in screenRegistry.values) {
    for (final c in _cases) {
      testWidgets('${s.stem} · ${c.$1}', (tester) async {
        tester.view.physicalSize = c.$2;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) {
          final where = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(d.toString())?.group(0) ?? '';
          errors.add('${d.exceptionAsString().split('\n').first} @ $where');
        };
        await tester.pumpWidget(MaterialApp(
          theme: medpinTheme(),
          locale: Locale(c.$4),
          supportedLocales: const [Locale('en'), Locale('bn'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(c.$3)), child: child!),
          home: s.sheet ? Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Builder(builder: s.builder))) : Builder(builder: s.builder),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        FlutterError.onError = old;
        final e = tester.takeException();
        if (e != null) errors.add('$e'.split('\n').first);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 7));
        if (errors.isNotEmpty) {
          problems.add('${s.stem} · ${c.$1}: ${errors.toSet().join(' | ')}');
          if (!report) fail(errors.toSet().join('\n'));
        }
      });
    }
  }
}

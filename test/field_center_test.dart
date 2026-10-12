import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';
import 'package:medpin_app/data/config.dart';

/// One-line text fields sit in the middle of their box (the box is the tap
/// target, the text stays centred). Checked on every screen in the design.
Future<void> _loadFigtree() async {
  final loader = FontLoader('Figtree');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    Nav.registry = screenRegistry;
    AppMode.preview = true;
    await _loadFigtree();
  });

  for (final s in screenRegistry.values) {
    testWidgets('${s.stem}: one-line fields are vertically centred', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: medpinTheme(),
        home: s.sheet ? Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Builder(builder: s.builder))) : Builder(builder: s.builder),
      ));
      await t.pump(const Duration(milliseconds: 400));
      final problems = <String>[];
      for (final e in find.byType(EditableText).evaluate()) {
        final edit = e.widget as EditableText;
        if (edit.maxLines != 1) continue;
        final box = e.renderObject as RenderBox;
        if (!box.hasSize || !box.attached) continue;
        final r = box.localToGlobal(Offset.zero) & box.size;
        // The nearest ancestor drawn as the field's box (a decorated box at
        // least 40px tall around the text).
        Rect? frame;
        e.visitAncestorElements((a) {
          final ro = a.renderObject;
          if (a.widget is DecoratedBox || (a.widget is Container && (a.widget as Container).decoration != null)) {
            if (ro is RenderBox && ro.hasSize && ro.size.height >= 40 && ro.size.height <= 80) {
              frame = ro.localToGlobal(Offset.zero) & ro.size;
              return false;
            }
          }
          return true;
        });
        if (frame == null) continue;
        final off = (r.center.dy - frame!.center.dy).abs();
        if (off > 3) problems.add('text at ${r.center.dy.toStringAsFixed(1)} vs box centre ${frame!.center.dy.toStringAsFixed(1)} (${frame!.height.toStringAsFixed(0)}px box)');
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}

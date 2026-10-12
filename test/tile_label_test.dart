import 'package:flutter/material.dart' hide Text;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/widgets/mp.dart';

void main() {
  Future<RenderBox> pump(WidgetTester t, double width, double scale) async {
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Center(child: SizedBox(width: width, child: MpTileLabel('Total appointments', style: tx(13)))),
      ),
    ));
    return t.renderObject<RenderBox>(find.byType(MpTileLabel));
  }

  testWidgets('a word wider than the tile shrinks the label instead of breaking', (t) async {
    final box = await pump(t, 60, 1.3);
    expect(find.text('Total appointments'), findsOneWidget, reason: 'still a normal Text');
    final text = t.renderObject<RenderParagraph>(find.byType(RichText));
    expect(text.size.width, greaterThan(60), reason: 'laid out wider, then drawn smaller');
    expect(box.size.width, 60);
    expect(t.takeException(), isNull);
  });

  testWidgets('a label that fits is drawn at its normal size', (t) async {
    await pump(t, 200, 1);
    final text = t.renderObject<RenderParagraph>(find.byType(RichText));
    expect(text.size.width, lessThanOrEqualTo(200));
    expect(t.takeException(), isNull);
  });
}

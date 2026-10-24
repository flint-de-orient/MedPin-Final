import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/widgets/i18n.dart';

Widget _app(String lang, Widget child) => MaterialApp(
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('bn'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    );

void main() {
  test('numbers fill the #1, #2 places', () {
    expect(I18n.tr('2 of 5 tasks done', 'bn'), '5টির মধ্যে 2টি কাজ শেষ');
    expect(I18n.tr('2 of 5 tasks done', 'hi'), '5 में से 2 काम पूरे');
    expect(I18n.tr('2 of 5 tasks done', 'en'), '2 of 5 tasks done');
    expect(I18n.tr('Something new', 'bn'), 'Something new', reason: 'missing entries stay English');
  });

  test('lines of parts and capital labels translate', () {
    // " · " lines with a name: the fixed parts translate, the name stays.
    expect(I18n.tr('Follow-up · Dr. Sen · Tomorrow', 'bn'), 'ফলো-আপ · Dr. Sen · আগামীকাল');
    // A whole-line entry with numbers still wins over splitting.
    expect(I18n.tr('2 of 5 tasks done', 'bn'), '5টির মধ্যে 2টি কাজ শেষ');
    // Labels in capitals use their ordinary entry.
    expect(I18n.tr('MORNING', 'bn'), 'সকাল');
    expect(I18n.tr('MORNING', 'en'), 'MORNING');
  });

  test('doctor and staff screens are translated too', () {
    expect(I18n.tr('Payouts and bank account', 'bn'), 'পেমেন্ট ও ব্যাংক অ্যাকাউন্ট');
    expect(I18n.tr('Signature checked · looks good', 'hi'), 'हस्ताक्षर जांचा गया · ठीक है');
    expect(I18n.tr('Show 3 more patients', 'bn'), 'আরও 3 জন রোগী দেখান');
    expect(I18n.tr('Waiting 12 min', 'hi'), '12 मिनट इंतज़ार');
    expect(I18n.tr('Video consultation', 'hi'), 'वीडियो परामर्श');
  });

  testWidgets('Text follows the app language', (t) async {
    await t.pumpWidget(_app('bn', const Column(children: [Text('Save'), Text.rich(TextSpan(text: 'Medicines'))])));
    expect(find.text('সেভ করুন'), findsOneWidget);
    expect(find.text('ওষুধ', findRichText: true), findsOneWidget);
    await t.pumpWidget(_app('hi', const Text('Save')));
    expect(find.text('सेव करें'), findsOneWidget);
    await t.pumpWidget(_app('en', const Text('Save')));
    expect(find.text('Save'), findsOneWidget);
  });
}

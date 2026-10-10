import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';

import '../l10n/bn.dart';
import '../l10n/hi.dart';

/// App text in the account language (English, বাংলা, हिन्दी).
///
/// Screens import this [Text] in place of Material's, so every label, button
/// and toast is looked up in the word lists at build time (English when there
/// is no translation). A string's numbers are matched as #1, #2…, so
/// "2 of 5 done" uses the entry for "#1 of #2 done".
class I18n {
  I18n._();
  static const _maps = {'bn': bn, 'hi': hi};
  static final _num = RegExp(r'\d+(?:[.:]\d+)?');

  static String tr(String s, String lang) {
    final map = _maps[lang];
    if (map == null || s.isEmpty) return s;
    final exact = map[s];
    if (exact != null) return exact;
    final nums = [for (final x in _num.allMatches(s)) x.group(0)!];
    if (nums.isEmpty) return s;
    var i = 0;
    final key = s.replaceAllMapped(_num, (_) => '#${++i}');
    final hit = map[key];
    if (hit == null) return s;
    return hit.replaceAllMapped(RegExp(r'#(\d)'), (x) {
      final n = int.parse(x.group(1)!) - 1;
      return n < nums.length ? nums[n] : x.group(0)!;
    });
  }

  /// Language of the nearest app locale ('en' when unsure).
  static String langOf(BuildContext context) => Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
}

/// Translates [s] for the screen at [context].
String tr(BuildContext context, String s) => I18n.tr(s, I18n.langOf(context));

/// Material's [m.Text], translated. Same constructor, so `const Text('Save')` still works.
class Text extends StatelessWidget {
  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  static InlineSpan _span(InlineSpan s, String lang) {
    if (s is! TextSpan) return s;
    return TextSpan(
      text: s.text == null ? null : I18n.tr(s.text!, lang),
      style: s.style,
      recognizer: s.recognizer,
      mouseCursor: s.mouseCursor,
      onEnter: s.onEnter,
      onExit: s.onExit,
      semanticsLabel: s.semanticsLabel,
      locale: s.locale,
      spellOut: s.spellOut,
      children: s.children?.map((c) => _span(c, lang)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = I18n.langOf(context);
    if (textSpan != null) {
      return m.Text.rich(
        lang == 'en' ? textSpan! : _span(textSpan!, lang),
        style: style, strutStyle: strutStyle, textAlign: textAlign, textDirection: textDirection, locale: locale, softWrap: softWrap,
        overflow: overflow, textScaler: textScaler, maxLines: maxLines, semanticsLabel: semanticsLabel, textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior, selectionColor: selectionColor,
      );
    }
    return m.Text(
      I18n.tr(data!, lang),
      style: style, strutStyle: strutStyle, textAlign: textAlign, textDirection: textDirection, locale: locale, softWrap: softWrap,
      overflow: overflow, textScaler: textScaler, maxLines: maxLines, semanticsLabel: semanticsLabel, textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior, selectionColor: selectionColor,
    );
  }
}

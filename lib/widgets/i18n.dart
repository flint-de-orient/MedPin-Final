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
    if (nums.isNotEmpty) {
      var i = 0;
      final key = s.replaceAllMapped(_num, (_) => '#${++i}');
      final hit = map[key];
      if (hit != null) {
        return hit.replaceAllMapped(RegExp(r'#(\d)'), (x) {
          final n = int.parse(x.group(1)!) - 1;
          return n < nums.length ? nums[n] : x.group(0)!;
        });
      }
    }
    // A line made of parts ("Follow-up · Dr. Sen · 3 free") with no entry of its own: each
    // part on its own, so the fixed words translate even with a name or date in the line.
    if (s.contains(' · ')) return [for (final p in s.split(' · ')) tr(p, lang)].join(' · ');
    // A label shown in capitals ("MORNING", "PEOPLE OFTEN ASK"): its entry is "Morning" /
    // "People often ask" (Bengali and Hindi have no capitals).
    if (s == s.toUpperCase() && RegExp(r'[A-Z]').hasMatch(s)) {
      final lower = s.toLowerCase();
      final sentence = lower[0].toUpperCase() + lower.substring(1);
      final words = lower.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
      for (final k in [sentence, words, lower]) {
        final hit = map[k];
        if (hit != null) return hit;
      }
    }
    return s;
  }

  /// Language of the nearest app locale ('en' when unsure).
  static String langOf(BuildContext context) => Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
}

/// Translates [s] for the screen at [context].
String tr(BuildContext context, String s) => I18n.tr(s, I18n.langOf(context));

/// A sentence with names or dates in it: [template] ("Visit moved to {slot}") is looked up
/// as it is, then {key}s are filled from [values] — so the sentence is translated even
/// though every patient's name differs.
String trf(BuildContext context, String template, Map<String, Object?> values) {
  var out = tr(context, template);
  values.forEach((k, v) => out = out.replaceAll('{$k}', '${v ?? ''}'));
  return out;
}

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

/// Text someone wrote — a chat message, a caption, MedPin AI's reply — shown
/// exactly as written, never run through the app's translations (a message
/// "Thank you" or "Report" must not turn into different words). Only the
/// app's own placeholders ("This message was deleted") are translated.
class UserText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  const UserText(this.data, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  static const _appPhrases = {
    'This message was deleted', 'Message deleted', 'Sent a file', 'Attachment', 'Voice message',
    // The clinic's automatic safety reply to an urgent message out of hours (care.js awayReply).
    'The clinic is closed now. If this is an emergency, call 108 or go to the nearest emergency department. Your doctor has been told.',
  };

  @override
  Widget build(BuildContext context) => m.Text(
        _appPhrases.contains(data) ? I18n.tr(data, I18n.langOf(context)) : data,
        style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow,
      );
}

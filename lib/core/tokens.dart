import 'package:flutter/material.dart';

/// MedPin design tokens, taken 1:1 from the design canvas.
class MP {
  MP._();

  // Brand
  static const primary = Color(0xFF003399);
  static const primaryDark = Color(0xFF002470);
  static const primarySoft = Color(0xFFEBF1FB);
  static const primaryLine = Color(0xFFB8C6E3);
  static const primaryMid = Color(0xFF7F99CC);

  // Neutrals
  static const bg = Color(0xFFF7F9FC);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111827);
  static const ink2 = Color(0xFF545E72);
  static const ink3 = Color(0xFF69738A);
  static const line = Color(0xFFE5E9F0);
  static const lineStrong = Color(0xFFD5DBE5);
  static const fill = Color(0xFFF1F4F9);
  static const fill2 = Color(0xFFEEF2F7);

  // Status
  static const amber = Color(0xFFB45309);
  static const amberSoft = Color(0xFFFEF6E7);
  static const amberLine = Color(0xFFF0D3A8);
  static const green = Color(0xFF076B3C);
  static const greenSoft = Color(0xFFE7F5EE);
  static const greenLine = Color(0xFFDCEBDF);
  static const red = Color(0xFFB91C1C);
  static const redSoft = Color(0xFFFDECEC);
  static const redLine = Color(0xFFF3C4C4);
  static const redMuted = Color(0xFFD5A0A0);

  /// rgba(17,24,39,0.40) — modal scrim.
  static const scrim = Color(0x66111827);

  /// Parses '#RRGGBB' (or 'RRGGBB') into a Color.
  static Color hex(String h) {
    final s = h.replaceAll('#', '');
    return Color(int.parse(s.length == 6 ? 'FF$s' : s, radix: 16));
  }
}

/// Shadows used in the design (all tinted with the brand blue).
class MPShadow {
  MPShadow._();

  /// 0 1px 2px rgba(0,51,153,.05), 0 1px 3px rgba(0,51,153,.04)
  static const card = [
    BoxShadow(color: Color(0x0D003399), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A003399), offset: Offset(0, 1), blurRadius: 3),
  ];

  /// 0 8px 24px rgba(0,51,153,.10) — floating nav, sheets.
  static const float = [
    BoxShadow(color: Color(0x1A003399), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// 0 8px 24px rgba(0,51,153,.18)
  static const floatStrong = [
    BoxShadow(color: Color(0x2E003399), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// 0 8px 24px rgba(0,51,153,.22) — blue hero cards.
  static const hero = [
    BoxShadow(color: Color(0x38003399), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// 0 6px 16px rgba(0,51,153,.24) — primary buttons.
  static const button = [
    BoxShadow(color: Color(0x3D003399), offset: Offset(0, 6), blurRadius: 16),
  ];

  /// 0 6px 16px rgba(0,51,153,.28)
  static const buttonStrong = [
    BoxShadow(color: Color(0x47003399), offset: Offset(0, 6), blurRadius: 16),
  ];

  /// 0 1px 2px rgba(0,51,153,.08)
  static const hairline = [
    BoxShadow(color: Color(0x14003399), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// 0 1px 2px rgba(17,24,39,.2) — switch knobs.
  static const knob = [
    BoxShadow(color: Color(0x33111827), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// 0 0 0 3px #EBF1FB — focus ring.
  static const focusRing = [
    BoxShadow(color: MP.primarySoft, spreadRadius: 3),
  ];
}

/// Text style helper. `em` is letter-spacing in em (CSS style), `h` is
/// line-height multiplier (CSS unitless line-height). For CSS
/// `text-transform: uppercase`, uppercase the string itself.
TextStyle tx(
  double size, {
  FontWeight w = FontWeight.w400,
  Color c = MP.ink,
  double? h,
  double em = 0,
  bool tab = false,
  TextDecoration? deco,
  Color? decoColor,
  FontStyle? style,
}) {
  return TextStyle(
    fontFamily: 'Figtree',
    fontSize: size,
    fontWeight: w,
    color: c,
    // Always explicit, so nothing inherits Material's letterSpacing/height.
    height: h ?? normalLineHeight(size),
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: size * em,
    fontFeatures: tab ? const [FontFeature.tabularFigures()] : null,
    decoration: deco,
    decorationColor: decoColor ?? c,
    fontStyle: style,
  );
}

/// Chrome's `line-height: normal` for Figtree (typo ascender 950, descender
/// 250, line gap 0 per 1000 units). Blink rounds ascent and descent
/// separately, so 14px → 13 + 4 = 17px (not 16.8), 16px → 19px, 18px → 22px.
double normalLineHeight(double size) => ((size * 0.95).round() + (size * 0.25).round()) / size;

/// Shorthand font weights.
const w400 = FontWeight.w400;
const w500 = FontWeight.w500;
const w600 = FontWeight.w600;
const w700 = FontWeight.w700;
const w800 = FontWeight.w800;

/// Vertical / horizontal gap widgets.
class Gap extends StatelessWidget {
  final double size;
  const Gap(this.size, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// Common box decorations.
class MPDeco {
  MPDeco._();

  /// White card, 1px #E5E9F0 border, radius 24, card shadow.
  static BoxDecoration card({
    double radius = 24,
    Color color = MP.white,
    Color border = MP.line,
    List<BoxShadow>? shadow = MPShadow.card,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: shadow,
      );
}

ThemeData medpinTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Figtree',
    scaffoldBackgroundColor: MP.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MP.primary,
      primary: MP.primary,
      surface: MP.white,
      onSurface: MP.ink,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: const Color(0x0A003399),
    splashColor: const Color(0x14003399),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MP.primary,
      selectionColor: Color(0x33003399),
      selectionHandleColor: MP.primary,
    ),
  );
  return base.copyWith(
    textTheme: _cleanTextTheme(base.textTheme),
    primaryTextTheme: _cleanTextTheme(base.primaryTextTheme),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      modalBarrierColor: MP.scrim,
    ),
  );
}

/// Material 3 text styles carry letterSpacing (0.1–0.5) and line heights
/// (1.43 …) that CSS doesn't have. Rebuild them with only size and weight.
TextTheme _cleanTextTheme(TextTheme t) {
  TextStyle? f(TextStyle? s) => s == null
      ? null
      : TextStyle(
          fontFamily: 'Figtree',
          fontSize: s.fontSize,
          fontWeight: s.fontWeight,
          color: MP.ink,
          letterSpacing: 0,
          height: 1.2,
          leadingDistribution: TextLeadingDistribution.even,
        );
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

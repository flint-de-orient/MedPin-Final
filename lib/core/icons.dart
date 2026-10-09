import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';

String _hex(Color c) {
  final v = c.toARGB32();
  return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

String _opacity(Color c) => (((c.toARGB32() >> 24) & 0xFF) / 255).toStringAsFixed(3);

/// A stroke icon drawn from the exact SVG markup used in the design
/// (24×24 viewBox, round caps/joins). `d` is the inner markup of the `<svg>`,
/// e.g. `'<path d="m9 6 6 6-6 6"/>'`. `currentColor` inside it is replaced
/// with [color].
class Ico extends StatelessWidget {
  final String d;
  final double size;
  final Color? color;
  final double stroke;

  /// Fill the shapes with [color] instead of stroking them.
  final bool filled;
  const Ico(this.d, {super.key, this.size = 22, this.color, this.stroke = 1.75, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? MP.ink;
    final hex = _hex(c);
    final op = _opacity(c);
    final inner = d.replaceAll('currentColor', hex);
    final attrs = filled
        ? 'fill="$hex" fill-opacity="$op" stroke="none"'
        : 'fill="none" stroke="$hex" stroke-opacity="$op" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round"';
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" $attrs>$inner</svg>';
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(svg, width: size, height: size),
    );
  }
}

/// Raw SVG (charts, illustrations) with an arbitrary viewBox.
/// `currentColor` is replaced with [color] when given.
class Svg extends StatelessWidget {
  final String svg;
  final double? width;
  final double? height;
  final Color? color;
  final BoxFit fit;
  const Svg(this.svg, {super.key, this.width, this.height, this.color, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    var s = _dashedCircles(_normalizeFonts(svg));
    if (color != null) s = s.replaceAll('currentColor', _hex(color!));
    if (!s.contains('xmlns=')) s = s.replaceFirst('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
    return SvgPicture.string(s, width: width, height: height, fit: fit);
  }
}

final _ffDouble = RegExp(r'font-family\s*=\s*"[^"]*"');
final _ffSingle = RegExp(r"font-family\s*=\s*'[^']*'");
final _ffCss = RegExp(r'font-family\s*:\s*[^;"]*');
final _svgOpen = RegExp(r'<svg[^>]*>');

/// flutter_svg can't resolve CSS font lists like `'Figtree', system-ui,
/// sans-serif`, and SVG text in the browser inherits the page font. So every
/// font-family becomes plain `Figtree`, and the root `<svg>` gets it too.
String _normalizeFonts(String svg) {
  if (!svg.contains('<text') && !svg.contains('font-family')) return svg;
  var s = svg
      .replaceAll(_ffDouble, 'font-family="Figtree"')
      .replaceAll(_ffSingle, 'font-family="Figtree"')
      .replaceAll(_ffCss, 'font-family: Figtree');
  final open = _svgOpen.firstMatch(s);
  if (open != null && !open.group(0)!.contains('font-family')) {
    s = s.replaceFirst('<svg', '<svg font-family="Figtree"');
  }
  return s;
}

final _circleTag = RegExp(r'<circle\b([^>]*?)(/?)>(\s*</circle>)?');
final _circleGeom = RegExp('\\b(cx|cy|r)\\s*=\\s*["\'][^"\']*["\']');

double? _attrNum(String attrs, String name) {
  final m = RegExp('\\b$name\\s*=\\s*["\']([-0-9.]+)').firstMatch(attrs);
  return m == null ? null : double.tryParse(m.group(1)!);
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Browsers start a `<circle>`'s outline at 3 o'clock and run clockwise, which
/// is what `stroke-dasharray` progress rings rely on (with `rotate(-90)`).
/// flutter_svg starts circles elsewhere, so dashed circles are rewritten as
/// the equivalent path that starts at 3 o'clock.
String _dashedCircles(String svg) {
  if (!svg.contains('stroke-dasharray') || !svg.contains('<circle')) return svg;
  return svg.replaceAllMapped(_circleTag, (m) {
    final attrs = m.group(1)!;
    if (!attrs.contains('stroke-dasharray')) return m.group(0)!;
    final r = _attrNum(attrs, 'r');
    if (r == null) return m.group(0)!;
    final cx = _attrNum(attrs, 'cx') ?? 0, cy = _attrNum(attrs, 'cy') ?? 0;
    final rest = attrs.replaceAll(_circleGeom, '');
    final d = 'M${_n(cx + r)} ${_n(cy)}A${_n(r)} ${_n(r)} 0 1 1 ${_n(cx - r)} ${_n(cy)}'
        'A${_n(r)} ${_n(r)} 0 1 1 ${_n(cx + r)} ${_n(cy)}Z';
    return '<path d="$d"$rest/>';
  });
}

/// The design's icon set (inner SVG markup, 24×24).
class I {
  I._();
  static const chevronRight = '<path d="m9 6 6 6-6 6"/>';
  static const chevronDown = '<path d="m6 9 6 6 6-6"/>';
  static const chevronUp = '<path d="m18 15-6-6-6 6"/>';
  static const chevronLeft = '<path d="m15 18-6-6 6-6"/>';
  static const back = '<path d="M19 12H5M12 19l-7-7 7-7"/>';
  static const arrowRight = '<path d="M5 12h14M12 5l7 7-7 7"/>';
  static const arrowUp = '<path d="M12 19V5M5 12l7-7 7 7"/>';
  static const arrowUpRight = '<path d="M7 17 17 7M8 7h9v9"/>';
  static const check = '<path d="M20 6 9 17l-5-5"/>';
  static const checkAlt = '<path d="m5 12 5 5 9-10"/>';
  static const close = '<path d="M18 6 6 18M6 6l12 12"/>';
  static const plus = '<path d="M12 5v14M5 12h14"/>';
  static const minus = '<path d="M5 12h14"/>';
  static const calendar = '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>';
  static const calendarDots =
      '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01"/>';
  static const sparkle = '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>';
  static const sparkles =
      '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>';
  static const search = '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>';
  static const message = '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>';
  static const messageAlert =
      '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M12 7v4M12 14h.01"/>';
  static const fileText =
      '<path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>';
  static const file = '<path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8z"/><path d="M14 3v5h5"/>';
  static const mic = '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>';
  static const home = '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>';
  static const user = '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>';
  static const users =
      '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>';
  static const userPlus =
      '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6M16 11h6"/>';
  static const alert =
      '<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><path d="M12 9v4M12 17h.01"/>';
  static const download = '<path d="M12 3v12M7 10l5 5 5-5M4 19h16"/>';
  static const downloadAlt = '<path d="M12 3v12M7 10l5 5 5-5M5 21h14"/>';
  static const upload = '<path d="M12 15V3M7 8l5-5 5 5M4 15v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4"/>';
  static const lock = '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>';
  static const bell = '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>';
  static const phone =
      '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>';
  static const edit = '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/>';
  static const pencil = '<path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>';
  static const circle = '<circle cx="12" cy="12" r="9"/>';
  static const clock = '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>';
  static const history = '<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>';
  static const historyClock = '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/>';
  static const pill = '<path d="m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7z"/><path d="m8.5 8.5 7 7"/>';
  static const filter = '<path d="M4 6h16M7 12h10M10 18h4"/>';
  static const moreV = '<circle cx="12" cy="5" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="12" cy="19" r="1.6"/>';
  static const shield = '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>';
  static const mail = '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>';
  static const image = '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21"/>';
  static const heart =
      '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>';
  static const leaf =
      '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"/><path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>';
  static const pin = '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>';
  static const activity = '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>';
  static const camera =
      '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z"/><circle cx="12" cy="13" r="3"/>';
  static const cameraAlt =
      '<path d="M3 8a2 2 0 0 1 2-2h2l2-2h6l2 2h2a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><circle cx="12" cy="13" r="3.5"/>';
  static const share =
      '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.59 13.51 6.83 3.98M15.41 6.51l-6.82 3.98"/>';
  static const flask = '<path d="M9 3h6M10 3v6L4.5 18.5A1.7 1.7 0 0 0 6 21h12a1.7 1.7 0 0 0 1.5-2.5L14 9V3"/><path d="M7 15h10"/>';
  static const eye = '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>';
  static const send = '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>';
  static const stethoscope = '<path d="M5 3v5a5 5 0 0 0 10 0V3"/><path d="M10 13v2a5 5 0 0 0 10 0v-1"/><circle cx="20" cy="12" r="2"/>';
  static const paperclip =
      '<path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"/>';
  static const cart = '<circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/><path d="M2 3h3l2.6 12.4a2 2 0 0 0 2 1.6h7.9a2 2 0 0 0 2-1.5L21 7H6"/>';
  static const moreVSmall = '<circle cx="12" cy="5" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="12" cy="19" r="1.2"/>';
  static const logout = '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>';
  static const book = '<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/>';
  static const volume = '<path d="M11 5 6 9H3v6h3l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/>';
  static const thumbUp = '<path d="M7 10v11M15 5.9 14 10h5.8a2 2 0 0 1 2 2.3l-1.4 7A2 2 0 0 1 18.4 21H7V10l4-8a3 3 0 0 1 4 3.9z"/>';
  static const thumbDown = '<path d="M17 14V3M9 18.1 10 14H4.2a2 2 0 0 1-2-2.3l1.4-7A2 2 0 0 1 5.6 3H17v11l-4 8a3 3 0 0 1-4-3.9z"/>';
  static const pause = '<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>';
  static const stop = '<rect x="6" y="6" width="12" height="12" rx="2.5"/>';
  static const emergency = '<path d="M12 4v16M5.1 8l13.8 8M5.1 16l13.8-8"/>';
  static const star = '<path d="m12 2 3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z"/>';
  static const drop = '<path d="M12 2.7 6.3 9.4a7 7 0 1 0 11.4 0z"/>';

  /// Verified badge — already coloured, render with `Svg`.
  static const verifiedSvg =
      '<svg viewBox="0 0 24 24"><path fill="#003399" d="M12 2l2.4 1.8 3-.2.9 2.9 2.5 1.7-1 2.8 1 2.8-2.5 1.7-.9 2.9-3-.2L12 22l-2.4-1.8-3 .2-.9-2.9L3.2 15.8l1-2.8-1-2.8 2.5-1.7.9-2.9 3 .2z"/><path d="m8.5 12 2.5 2.5 4.5-5" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
}

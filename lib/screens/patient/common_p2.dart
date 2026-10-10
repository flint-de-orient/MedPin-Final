import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/downloads.dart';
import '../../data/where.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch P2 (patient app: records, doctors, medicines).

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// [days] after the design's "today" (Thu, 1 Oct 2026).
DateTime p2FromToday(int days) => DateTime(2026, 10, 1 + days);

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "1 Nov"-style short date.
String p2Day(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

/// The current time as "8:40 AM".
String p2Now() {
  final t = TimeOfDay.now();
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

/// Closes the sheet [context] belongs to, then opens [stem] from the screen under it.
void p2SheetThen(BuildContext context, String stem) {
  final nav = Navigator.of(context);
  nav.pop();
  Nav.go(nav.context, stem);
}

/// Feedback for a control whose screen is not part of the design.
void p2Missing(BuildContext context, String what) => toast(context, '$what is not in the design yet');

/// Opens a link (file, map, phone) outside the app; toasts [failed] if it can't.
Future<void> p2Open(BuildContext context, String? url, {String failed = "Couldn't open this"}) async {
  if (url == null || url.isEmpty) {
    toast(context, failed);
    return;
  }
  if (Downloads.isFile(url)) {
    await Downloads.open(context, url);
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) toast(context, failed);
}

/// Directions to a clinic: its Google Maps link, or a maps search for the address.
Future<void> p2Directions(BuildContext context, {String? mapUrl, String? address, num? lat, num? lng}) {
  final url = lat != null && lng != null
      ? directionsUrl(lat.toDouble(), lng.toDouble())
      : (mapUrl != null && mapUrl.isNotEmpty)
          ? mapUrl
          : (address == null || address.isEmpty ? null : 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
  return p2Open(context, url, failed: "Couldn't open the map");
}

/// What a care-team member can see (Patient-Me, Patient-DoctorDetail), most to least.
const p2AccessLevels = <String, String>{
  'full_with_logs': 'Full record, daily log and tracked vitals',
  'full_record': 'Full record',
  'prescriptions_and_tests': 'Prescriptions and test results',
  'daily_log_only': 'Daily log only',
  'not_shared': 'Not shared',
};

/// The doctor a doctor screen is about: `Nav.go(..., args: doctorId)` or
/// `args: {'doctorId': …, 'conversationId': …, 'appointmentId': …}`.
Map<String, String> p2DoctorArgs(BuildContext context) {
  final a = Nav.args<Object>(context);
  if (a is String) return {'doctorId': a};
  if (a is Map) {
    return {
      for (final e in a.entries)
        if (e.value != null) '${e.key}': '${e.value}',
    };
  }
  return const {};
}

/// "Dr. Arjun Sen" / "Mou" → "Dr. Sen" / "Mou" for chat lines.
String p2ShortName(String name) {
  final t = name.trim();
  if (RegExp(r'^Dr\.?\s', caseSensitive: false).hasMatch(t)) return 'Dr. ${t.split(RegExp(r'\s+')).last}';
  return t.split(RegExp(r'\s+')).first;
}

BorderRadius _shrink(BorderRadius r, double d) {
  Radius s(Radius x) => Radius.elliptical(math.max(0.0, x.x - d), math.max(0.0, x.y - d));
  return BorderRadius.only(
    topLeft: s(r.topLeft),
    topRight: s(r.topRight),
    bottomLeft: s(r.bottomLeft),
    bottomRight: s(r.bottomRight),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Boxes
// ─────────────────────────────────────────────────────────────────────────────

/// A decorated box that follows the CSS box model: the border takes layout
/// space (content sits inside border + padding), [width]/[height] are the
/// outer size. Optional ink ripple clipped to the shape, optional dashed border
/// (CSS `dashed`: dash 3×width, gap 2×width) and top-only border for list rows.
class P2Box extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final BorderRadius? borderRadius;
  final Color? color;
  final Color? border;
  final double borderWidth;
  final bool dashed;
  final BorderSide? topBorder;
  final List<BoxShadow>? shadow;
  final double? width;
  final double? height;
  final double? minHeight;
  final AlignmentGeometry? alignment;
  final String? label;

  const P2Box({
    super.key,
    required this.child,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.radius = 0,
    this.borderRadius,
    this.color,
    this.border,
    this.borderWidth = 1,
    this.dashed = false,
    this.topBorder,
    this.shadow,
    this.width,
    this.height,
    this.minHeight,
    this.alignment,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(radius);
    final solid = border != null && !dashed;
    final dash = border != null && dashed;
    Widget inner = alignment == null ? child : Align(alignment: alignment!, child: child);
    inner = Padding(padding: dash ? padding.add(EdgeInsets.all(borderWidth)) : padding, child: inner);
    if (onTap != null) {
      inner = Material(
        type: MaterialType.transparency,
        borderRadius: solid ? _shrink(br, borderWidth) : br,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: inner),
      );
    }
    Widget box = Container(
      width: width,
      height: height,
      constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      decoration: BoxDecoration(
        color: color,
        borderRadius: br,
        border:
            solid
                ? Border.all(color: border!, width: borderWidth)
                : (topBorder == null ? null : Border(top: topBorder!)),
        boxShadow: shadow,
      ),
      child: inner,
    );
    if (dash) box = CustomPaint(foregroundPainter: _DashPainter(br, borderWidth, border!), child: box);
    if (label != null || onTap != null) box = Semantics(button: onTap != null, label: label, child: box);
    return box;
  }
}

class _DashPainter extends CustomPainter {
  final BorderRadius radius;
  final double width;
  final Color color;
  const _DashPainter(this.radius, this.width, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = Path()..addRRect(_shrink(radius, width / 2).toRRect(rect));
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width;
    final dash = width * 3, gap = width * 2;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.radius != radius || old.width != width || old.color != color;
}

/// Lays [child] out at [width]×[height] but only takes `width - right` ×
/// `height - top` (CSS negative margins `margin: -top -right 0 0`).
class P2Bleed extends StatelessWidget {
  final double width;
  final double height;
  final double top;
  final double right;
  final Widget child;
  const P2Bleed({
    super.key,
    required this.width,
    required this.height,
    this.top = 0,
    this.right = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width - right,
    height: height - top,
    child: OverflowBox(
      minWidth: width,
      maxWidth: width,
      minHeight: height,
      maxHeight: height,
      alignment: Alignment.bottomLeft,
      child: child,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Status pill (radius 999). Defaults: 22px tall, 0 8px padding, 12/700.
class P2Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double height;
  final double padX;
  final double fontSize;
  final FontWeight weight;
  final bool tab;
  final double minWidth;
  const P2Pill(
    this.text, {
    super.key,
    this.bg = MP.fill,
    this.fg = MP.ink2,
    this.height = 22,
    this.padX = 8,
    this.fontSize = 12,
    this.weight = w700,
    this.tab = false,
    this.minWidth = 0,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    constraints: BoxConstraints(minWidth: minWidth),
    padding: EdgeInsets.symmetric(horizontal: padX),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text(text, maxLines: 1, style: tx(fontSize, w: weight, c: fg, tab: tab))],
    ),
  );
}

/// 22px radio ring: 2px #003399 with a 10px dot when on, 2px #D5DBE5 when off.
class P2Radio extends StatelessWidget {
  final bool on;
  const P2Radio(this.on, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: on ? MP.primary : MP.lineStrong, width: 2),
    ),
    child:
        on
            ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
            )
            : null,
  );
}

/// Two-up segmented control used in these designs: #F1F4F9 track (padding 4,
/// radius 16), no gap, white selected segment (radius 12, hairline shadow).
class P2Segmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const P2Segmented({super.key, required this.options, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? MP.white : const Color(0x00FFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: i == index ? MPShadow.hairline : const [],
                    ),
                    child: Text(
                      options[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(15, w: i == index ? w600 : w500, c: i == index ? MP.ink : MP.ink2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sheet title row: 20/700 title, 14px #545E72 subtitle and the 44px close
/// button pulled up/right by `margin: -6px -10px 0 0`.
class P2SheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final double? subtitleHeight;
  const P2SheetHeader({super.key, required this.title, required this.subtitle, this.subtitleHeight});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: tx(20, w: w700, h: 1.25)),
            const Gap(4),
            Text(subtitle, style: tx(14, c: MP.ink2, h: subtitleHeight)),
          ],
        ),
      ),
      const Gap(8),
      P2Bleed(
        width: 44,
        height: 44,
        top: 6,
        right: 10,
        child: MpIconButton(
          I.close,
          label: 'Close',
          color: MP.ink2,
          iconSize: 20,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
    ],
  );
}

/// Initials avatar with a presence dot (white ring) at the bottom right.
class P2AvatarDot extends StatelessWidget {
  final String initials;
  final double size;
  final double fontSize;
  final Color dot;

  /// Outer size of the dot (CSS width + 2 × border).
  final double dotSize;
  final double dotBorder;
  final double inset;
  const P2AvatarDot(
    this.initials, {
    super.key,
    required this.size,
    required this.fontSize,
    required this.dot,
    required this.dotSize,
    required this.dotBorder,
    required this.inset,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        MpAvatar(initials, size: size, fontSize: fontSize),
        Positioned(
          right: inset,
          bottom: inset,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              border: Border.all(color: MP.white, width: dotBorder),
            ),
          ),
        ),
      ],
    ),
  );
}

/// White top bar with a 1px bottom border under the 64px bar (CSS
/// `height: 64px; border-bottom: 1px`, i.e. 65px in all).
class P2WhiteHeader extends StatelessWidget {
  final String title;
  const P2WhiteHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
    child: MpHeader(title, background: MP.white),
  );
}

/// − value + stepper: 1px #D5DBE5 border, radius 12, white buttons with
/// #003399 icons.
class P2Stepper extends StatelessWidget {
  final String value;
  final double button;
  final double valueWidth;
  final double iconSize;
  final TextStyle style;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final String minusLabel;
  final String plusLabel;
  final String? label;
  const P2Stepper({
    super.key,
    required this.value,
    required this.button,
    required this.valueWidth,
    required this.iconSize,
    required this.style,
    this.onMinus,
    this.onPlus,
    this.minusLabel = 'Less',
    this.plusLabel = 'More',
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(String icon, String l, VoidCallback? onTap) => Semantics(
      button: true,
      label: l,
      child: Material(
        color: MP.white,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: button,
            height: button,
            child: Center(child: Ico(icon, size: iconSize, color: MP.primary, stroke: 2)),
          ),
        ),
      ),
    );
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.all(1),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: MP.lineStrong),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(I.minus, minusLabel, onMinus),
              SizedBox(width: valueWidth, child: Text(value, textAlign: TextAlign.center, maxLines: 1, style: style)),
              btn(I.plus, plusLabel, onPlus),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text input as drawn in these designs (border-box, 1px #D5DBE5, 16px text).
/// [padLeft]/[padRight] are the CSS paddings inside the border; an optional
/// 20px [icon] sits 16px from the outer left edge. Focus: #003399 border with
/// the #EBF1FB ring, as [MpInput].
class P2Field extends StatefulWidget {
  final String? value;
  final String? hint;
  final String? icon;
  final Color iconColor;
  final double height;
  final double radius;
  final double padLeft;
  final double padRight;
  final Color fill;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? action;
  const P2Field({
    super.key,
    this.value,
    this.hint,
    this.icon,
    this.iconColor = MP.ink2,
    this.height = 56,
    this.radius = 16,
    this.padLeft = 16,
    this.padRight = 16,
    this.fill = MP.white,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.action,
  });

  @override
  State<P2Field> createState() => _P2FieldState();
}

class _P2FieldState extends State<P2Field> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: widget.value ?? '');
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _f.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _f.hasFocus;
    return GestureDetector(
      onTap: _f.requestFocus,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.fill,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: focused ? MP.primary : MP.lineStrong),
          boxShadow: focused ? MPShadow.focusRing : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                SizedBox(width: widget.padLeft),
                Expanded(
                  child: TextField(
                    controller: _c,
                    focusNode: _f,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textInputAction: widget.action,
                    style: tx(16),
                    cursorColor: MP.primary,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hint == null ? null : tr(context, widget.hint!),
                      hintStyle: tx(16, c: MP.ink3),
                    ),
                  ),
                ),
                SizedBox(width: widget.padRight),
              ],
            ),
            if (widget.icon != null)
              Positioned(
                left: 15,
                top: 0,
                bottom: 0,
                child: IgnorePointer(child: Center(child: Ico(widget.icon!, size: 20, color: widget.iconColor))),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Share with" doctor picker (Records-Add, Records-Review)
// ─────────────────────────────────────────────────────────────────────────────

class P2Doctor {
  final String name;
  final String sub;

  /// Sub line in #003399 (suggested doctors) instead of #545E72.
  final bool suggested;
  final bool on;

  /// The doctor's user id when the list comes from the API.
  final String? id;
  const P2Doctor(this.name, this.sub, {this.suggested = false, this.on = false, this.id});
}

/// "Share with … / Pick any doctors" header, checkbox rows (min-height 56,
/// hairline between rows) and the "Share with another doctor" link.
class P2ShareDoctors extends StatefulWidget {
  final String title;
  final List<P2Doctor> doctors;

  /// Called with the ticked state of every row after each change.
  final ValueChanged<List<bool>>? onChanged;

  /// "Share with another doctor"; defaults to the Find a doctor screen.
  final VoidCallback? onAnother;
  const P2ShareDoctors({super.key, required this.title, required this.doctors, this.onChanged, this.onAnother});

  @override
  State<P2ShareDoctors> createState() => _P2ShareDoctorsState();
}

class _P2ShareDoctorsState extends State<P2ShareDoctors> {
  late final List<bool> _on = [for (final d in widget.doctors) d.on];

  void _toggle(int i) {
    setState(() => _on[i] = !_on[i]);
    widget.onChanged?.call(List.unmodifiable(_on));
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.doctors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(widget.title, style: tx(14, w: w600))),
              Text('Pick any doctors', style: tx(13, c: MP.ink3)),
            ],
          ),
        ),
        for (var i = 0; i < docs.length; i++)
          P2Box(
            onTap: () => _toggle(i),
            label: docs[i].name,
            topBorder: i == 0 ? null : const BorderSide(color: MP.line),
            minHeight: i == 0 ? 56 : 57,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                MpCheck(value: _on[i], onChanged: (_) => _toggle(i)),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(docs[i].name, style: tx(15, w: w600)),
                      const Gap(1),
                      Text(docs[i].sub, style: tx(13, c: docs[i].suggested ? MP.primary : MP.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        P2Box(
          onTap: widget.onAnother ?? () => Nav.go(context, 'Patient-FindDoctor'),
          topBorder: const BorderSide(color: MP.line),
          minHeight: 53,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Ico(I.search, size: 20, color: MP.primary),
              const Gap(12),
              Flexible(child: Text('Share with another doctor', style: tx(15, w: w600, c: MP.primary))),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheets shared by the doctor screens and Patient-Me
// ─────────────────────────────────────────────────────────────────────────────

/// "What Dr. Sen can see": the access levels plus "Stop sharing". Pops the
/// chosen label (a value of [p2AccessLevels]).
class P2SharingSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String current;
  const P2SharingSheet({super.key, required this.title, required this.subtitle, required this.current});

  @override
  State<P2SharingSheet> createState() => _P2SharingSheetState();
}

class _P2SharingSheetState extends State<P2SharingSheet> {
  late String _level = widget.current;
  static final _levels = p2AccessLevels.values.toList();

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: P2SheetHeader(title: widget.title, subtitle: widget.subtitle),
          ),
          const Gap(16),
          for (var i = 0; i < _levels.length; i++) ...[
            if (i > 0) const MpDivider(),
            _option(_levels[i]),
          ],
          const Gap(20),
          MpButton('Save', onTap: () => Navigator.pop(context, _level)),
        ],
      ),
    );
  }

  Widget _option(String level) {
    final stop = level == p2AccessLevels['not_shared'];
    final on = _level == level;
    return Tap(
      onTap: () => setState(() => _level = level),
      radius: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  stop ? 'Stop sharing' : level,
                  style: tx(16, w: on ? w600 : w500, c: stop ? MP.red : MP.ink, h: 1.4),
                ),
              ),
              const Gap(12),
              P2Radio(on),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list of actions in a sheet (icon tile + label), like the file-source
/// picker. Pops the index tapped.
class P2ActionSheet extends StatelessWidget {
  final String title;
  final List<(String, String, bool)> actions;
  const P2ActionSheet({super.key, required this.title, required this.actions});

  @override
  Widget build(BuildContext context) => MpSheet(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < actions.length; i++)
          Tap(
            onTap: () => Navigator.pop(context, i),
            radius: 12,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  MpIconTile(
                    actions[i].$1,
                    size: 40,
                    iconSize: 20,
                    radius: 12,
                    bg: actions[i].$3 ? MP.redSoft : MP.primarySoft,
                    fg: actions[i].$3 ? MP.red : MP.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(actions[i].$2, style: tx(16, w: w600, c: actions[i].$3 ? MP.red : MP.ink))),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// "Log out of MedPin?"-style confirmation. Pops true when confirmed.
class P2ConfirmSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final String confirm;
  final String cancel;
  final bool danger;
  const P2ConfirmSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.confirm,
    this.cancel = 'Cancel',
    this.danger = true,
  });

  @override
  Widget build(BuildContext context) => MpSheet(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: P2SheetHeader(title: title, subtitle: subtitle),
        ),
        const Gap(24),
        MpButton(confirm, kind: danger ? MpBtn.danger : MpBtn.primary, onTap: () => Navigator.pop(context, true)),
        const Gap(12),
        MpButton(cancel, kind: MpBtn.secondary, onTap: () => Navigator.pop(context, false)),
      ],
    ),
  );
}

/// Pick a new time with a doctor at one clinic (GET
/// /api/patient/doctors/:id/slots?next=6). Pops the chosen startAt (ISO).
class P2SlotSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String doctorId;
  final String locationId;
  final String action;
  const P2SlotSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.doctorId,
    required this.locationId,
    this.action = 'Save',
  });

  @override
  State<P2SlotSheet> createState() => _P2SlotSheetState();
}

class _P2SlotSheetState extends State<P2SlotSheet> {
  List<Map<String, dynamic>>? _slots;
  String? _picked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.I.get(
        '/api/patient/doctors/${widget.doctorId}/slots',
        query: {'locationId': widget.locationId, 'next': 6},
      );
      if (!mounted) return;
      setState(() {
        _slots = (res as Map).cast<String, dynamic>().list('slots');
        _picked = _slots!.isEmpty ? null : _slots!.first.str('startAt');
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _label(Map<String, dynamic> s) {
    final at = F.date(s['startAt']);
    return at == null ? s.str('time') : F.when(at);
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: P2SheetHeader(title: widget.title, subtitle: widget.subtitle),
          ),
          const Gap(16),
          if (_error != null)
            Text(_error!, style: tx(14, c: MP.ink2, h: 1.45))
          else if (slots == null)
            const SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary)),
              ),
            )
          else if (slots.isEmpty)
            Text('No free times in the next two weeks. Please call the clinic.', style: tx(14, c: MP.ink2, h: 1.45))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in slots)
                  MpChip(
                    _label(s),
                    selected: _picked == s.str('startAt'),
                    tonal: true,
                    onTap: () => setState(() => _picked = s.str('startAt')),
                  ),
              ],
            ),
          const Gap(20),
          MpButton(widget.action, onTap: _picked == null ? null : () => Navigator.pop(context, _picked)),
        ],
      ),
    );
  }
}

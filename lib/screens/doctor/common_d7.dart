import 'package:flutter/material.dart' hide Text;

import '../../data/format.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D7: the three consultation steps (Consult-Vitals,
// Consult-Diagnosis, Consult-Advice) and the clinic-operations screens.
// Boxes are built with Container borders so that, like CSS border-box,
// the 1px border sits inside the given size and in front of the padding.

/// Card heading: 20 / 700 / 1.25, with an optional 14px #545E72 line 2px below.
class D7Title extends StatelessWidget {
  final String text;
  final String? sub;

  /// Line height of [sub]: 1.45 on most cards, `null` = CSS `normal`.
  final double? subHeight;
  const D7Title(this.text, {super.key, this.sub, this.subHeight = 1.45});

  @override
  Widget build(BuildContext context) {
    final title = Text(text, style: tx(20, w: w700, h: 1.25));
    if (sub == null) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [title, const SizedBox(height: 2), Text(sub!, style: tx(14, c: MP.ink2, h: subHeight))],
    );
  }
}

/// Field label (14 / 600), the control 8px below, optional 13px #69738A help.
class D7Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  final String? help;
  const D7Labeled(this.label, {super.key, required this.child, this.help});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: tx(14, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 8),
      child,
      if (help != null) ...[const SizedBox(height: 8), Text(help!, style: tx(13, c: MP.ink3))],
    ],
  );
}

/// Text input with the design's box: 1px #D5DBE5 border, radius 16, white,
/// 16px text; focus → #003399 border + 3px #EBF1FB ring (as `MpInput`).
/// [padding] is the CSS padding inside the border. [overlays] are
/// `Positioned` widgets placed from the box's outer edge — the design's
/// absolutely positioned icons, units and clear buttons.
class D7Field extends StatefulWidget {
  final String? value;
  final TextEditingController? controller;
  final String? hint;
  final double height;
  final int lines;
  final EdgeInsetsGeometry padding;
  final bool tab;
  final Color border;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final ValueChanged<String>? onChanged;
  final List<Widget> overlays;

  /// CSS `text-overflow: ellipsis`: while the field is not focused, a value
  /// too long for the box ends in "…" instead of being cut off.
  final bool ellipsis;
  const D7Field({
    super.key,
    this.value,
    this.controller,
    this.hint,
    this.height = 56,
    this.lines = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.tab = false,
    this.border = MP.lineStrong,
    this.keyboard,
    this.action,
    this.onChanged,
    this.overlays = const [],
    this.ellipsis = false,
  });

  @override
  State<D7Field> createState() => _D7FieldState();
}

class _D7FieldState extends State<D7Field> {
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
    final multi = widget.lines > 1;
    final style = tx(16, h: multi ? 1.5 : null, tab: widget.tab);
    final cover = widget.ellipsis && !multi && !focused;
    Widget field = TextField(
      controller: _c,
      focusNode: _f,
      maxLines: widget.lines,
      minLines: widget.lines,
      keyboardType: widget.keyboard ?? (multi ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.action,
      onChanged: widget.onChanged,
      style: cover ? style.copyWith(color: Colors.transparent) : style,
      cursorColor: MP.primary,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: widget.hint,
        hintStyle: style.copyWith(color: MP.ink3),
      ),
    );
    if (cover) {
      field = Stack(
        children: [
          field,
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _c,
                  builder:
                      (context, v, _) =>
                          Text(v.text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _f.requestFocus,
          child: Container(
            height: widget.height,
            padding: widget.padding,
            alignment: multi ? Alignment.topLeft : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: MP.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: focused ? MP.primary : widget.border),
              boxShadow: focused ? MPShadow.focusRing : null,
            ),
            child: field,
          ),
        ),
        ...widget.overlays,
      ],
    );
  }
}

/// Button or text link with literal CSS metrics: [height], [radius],
/// [padding] (inside the optional 1px [border]), 600-weight label of [size]
/// and an optional leading [icon].
class D7Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final Color? border;
  final List<BoxShadow>? shadow;
  final double height;
  final double radius;
  final double size;
  final EdgeInsetsGeometry padding;
  final String? icon;
  final double iconSize;
  final double iconStroke;
  final double gap;
  final bool expand;
  const D7Btn(
    this.label, {
    super.key,
    this.onTap,
    this.bg = Colors.transparent,
    this.fg = MP.primary,
    this.border,
    this.shadow,
    this.height = 48,
    this.radius = 12,
    this.size = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.icon,
    this.iconSize = 18,
    this.iconStroke = 1.75,
    this.gap = 8,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Tap(
        onTap: onTap ?? () {},
        radius: radius,
        color: bg,
        shadow: shadow,
        child: Container(
          padding: padding,
          decoration:
              border == null
                  ? null
                  : BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: border!)),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Ico(icon!, size: iconSize, color: fg, stroke: iconStroke), SizedBox(width: gap)],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(size, w: w600, c: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40px pill (filter chip / toggle). Off: white, 1px #D5DBE5, #545E72.
/// On: #003399 fill + white text (1px #003399 border when [borderOn]), or
/// the [tonal] #EBF1FB / #003399 variant. [check] adds the 16px check when on;
/// [dot] a leading 8px status dot; [fill] stretches to the parent width.
class D7Pill extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final bool check;
  final bool borderOn;
  final bool tonal;
  final double hPad;
  final Color? dot;
  final bool fill;
  const D7Pill(
    this.label, {
    super.key,
    this.on = false,
    this.onTap,
    this.check = false,
    this.borderOn = true,
    this.tonal = false,
    this.hPad = 16,
    this.dot,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = on ? (tonal ? MP.primarySoft : MP.primary) : MP.white;
    final fg = on ? (tonal ? MP.primary : MP.white) : MP.ink2;
    final Color? line = !on ? MP.lineStrong : (borderOn || tonal ? MP.primary : null);
    final text = Text(label, maxLines: 1, softWrap: false, style: tx(14, w: w600, c: fg));
    return Semantics(
      button: true,
      selected: on,
      child: Tap(
        onTap: onTap ?? () {},
        radius: 999,
        color: bg,
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          decoration:
              line == null
                  ? null
                  : BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: line)),
          child: Row(
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              if (check && on) ...[Ico(I.check, size: 16, color: fg, stroke: 2.25), const SizedBox(width: 6)],
              if (fill) Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: text)) else text,
            ],
          ),
        ),
      ),
    );
  }
}

/// CSS `border-top` (and optionally `border-bottom`) 1px #E5E9F0 + padding.
class D7Ruled extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool top;
  final bool bottom;
  const D7Ruled({super.key, required this.child, this.padding = EdgeInsets.zero, this.top = true, this.bottom = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      border: Border(
        top: top ? const BorderSide(color: MP.line) : BorderSide.none,
        bottom: bottom ? const BorderSide(color: MP.line) : BorderSide.none,
      ),
    ),
    child: child,
  );
}

/// Patient strip (Priya Sharma · allergy) and the 3-step progress
/// (Vitals · Diagnosis · Advice) shown above every consultation step.
class D7ConsultTop extends StatelessWidget {
  /// 0 = Vitals, 1 = Diagnosis, 2 = Advice.
  final int step;

  /// Live: the patient summary from the API (`{patient: {name, age, gender},
  /// allergies: [{allergen}]}`); null shows the design's patient.
  final Map<String, dynamic>? summary;
  const D7ConsultTop({super.key, required this.step, this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final p = s?['patient'] is Map ? (s!['patient'] as Map).cast<String, dynamic>() : null;
    final name = p == null ? 'Priya Sharma' : '${p['name'] ?? 'Patient'}';
    final g = p == null ? 'F' : '${p['gender'] ?? ''}';
    final who =
        p == null
            ? '29 F'
            : [if (p['age'] != null) '${p['age']}', if (g.isNotEmpty) g[0].toUpperCase()].join(' ');
    final allergies =
        s == null
            ? 'Sulfa drugs'
            : [
              for (final a in (s['allergies'] as List? ?? const []))
                if (a is Map && a['allergen'] != null) '${a['allergen']}',
            ].join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MpAvatar(F.initials(name), size: 40, fontSize: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: tx(16, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: allergies.isEmpty ? who : '$who · ',
                        style: tx(14, c: MP.ink2, h: 1.45),
                        children: [
                          if (allergies.isNotEmpty)
                            TextSpan(text: 'Allergy: $allergies', style: tx(14, w: w600, c: MP.amber, h: 1.45)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Stepper(step: step),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int step;
  const _Stepper({required this.step});

  static const _labels = ['Vitals', 'Diagnosis', 'Advice'];

  /// Width of the blue progress line, as a share of the row (CSS 0 / 33.33 / 66.67%).
  static const _progress = [0.0, 0.3333, 0.6667];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Consultation steps, step ${step + 1} of 3',
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final inset = w * 0.1667;
          return Stack(
            children: [
              Positioned(top: 13, left: inset, right: inset, height: 2, child: const ColoredBox(color: MP.lineStrong)),
              Positioned(
                top: 13,
                left: inset,
                width: w * _progress[step],
                height: 2,
                child: const ColoredBox(color: MP.primary),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (var i = 0; i < 3; i++) Expanded(child: _item(i))],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(int i) {
    final done = i < step;
    final current = i == step;
    final Widget circle;
    if (done) {
      circle = Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
        child: const Ico(I.check, size: 16, color: MP.white, stroke: 2.5),
      );
    } else if (current) {
      circle = Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: MP.primary,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: MP.primarySoft, spreadRadius: 4)],
        ),
        child: Text('${i + 1}', style: tx(14, w: w700, c: MP.white)),
      );
    } else {
      circle = Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MP.white,
          shape: BoxShape.circle,
          border: Border.all(color: MP.lineStrong, width: 1.5),
        ),
        child: Text('${i + 1}', style: tx(14, w: w600, c: MP.ink3)),
      );
    }
    final style =
        current
            ? tx(14, w: w700)
            : done
            ? tx(14, w: w600, c: MP.ink2)
            : tx(14, w: w500, c: MP.ink3);
    return Column(
      children: [
        circle,
        const SizedBox(height: 8),
        Text(_labels[i], style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// 'Thu, 29 Oct 2026'.
String d7Date(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}

/// 'Tue 29 Sep'.
String d7DayShort(DateTime d) {
  final long = d7Date(d);
  return long.substring(0, long.lastIndexOf(' ')).replaceFirst(',', '');
}

/// 'today, 8:15 AM', 'yesterday, 6:40 PM', '27 Sep, 11:00 AM'.
String d7DayTime(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day =
      F.sameDay(d, n)
          ? 'today'
          : F.sameDay(d, n.subtract(const Duration(days: 1)))
          ? 'yesterday'
          : F.dayMonth(d);
  return '$day, ${F.time(d)}';
}

const d7Weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const d7WeekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Open days of a location's `weeklyHours`: 'Mon–Sat', 'Tue · Thu · Sat'.
String d7OpenDays(List<Map<String, dynamic>> hours) {
  final open = [
    for (var i = 0; i < 7; i++)
      if (hours.any((h) => h['weekday'] == d7Weekdays[i] && h['isOpen'] != false)) i,
  ];
  if (open.isEmpty) return '';
  final run = open.length >= 3 && open.last - open.first == open.length - 1;
  if (run) return '${d7WeekdayNames[open.first]}–${d7WeekdayNames[open.last]}';
  return open.map((i) => d7WeekdayNames[i]).join(' · ');
}

/// The street part of a location's address ("DD-24, Sector 1, Salt Lake"),
/// without the city and PIN code.
String d7ShortAddress(Map<String, dynamic> l) {
  final city = (l['city'] as String? ?? '').toLowerCase();
  final parts = (l['address'] as String? ?? '').split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  while (parts.length > 1 && city.isNotEmpty && parts.last.toLowerCase().startsWith(city)) {
    parts.removeLast();
  }
  return parts.join(', ');
}

/// "9:00 AM" for minutes after midnight.
String d7Minutes(num m) {
  final h = m ~/ 60;
  final min = (m % 60).toInt();
  return F.time(DateTime(2000, 1, 1, h.toInt(), min));
}

/// "9:00 AM – 1:00 PM", or "5:00 – 8:00 PM" when both are in the afternoon
/// (or both in the morning).
String d7Range(num from, num to) {
  final a = d7Minutes(from);
  final b = d7Minutes(to);
  final same = a.substring(a.length - 2) == b.substring(b.length - 2);
  return same ? '${a.substring(0, a.length - 3)} – $b' : '$a – $b';
}

/// "9:30 AM" → 570 (minutes after midnight); null if it isn't a time.
int? d7ParseTime(String t) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(t.trim());
  if (m == null) return null;
  var h = int.parse(m.group(1)!) % 12;
  if (m.group(3) == 'PM') h += 12;
  return h * 60 + int.parse(m.group(2)!);
}

/// YYYY-MM-DD of a local date (the API's `date` parameter).
String d7Key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

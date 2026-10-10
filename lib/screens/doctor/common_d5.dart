import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'signature_gate.dart';
import '../../widgets/i18n.dart';

// Shared pieces for the consultation screens of batch D5:
// Consult-Page, Consult-Voice, Consult-Dosage, Consult-Pick,
// Consult-NotFound, Consult-QuickAdd and Consult-Blank.

/// What the dosage and voice sheets hand back when a medicine is added.
/// Live, [item] is the prescription line as the API stores it.
typedef D5MedResult = ({String name, String dose, String duration, Map<String, dynamic>? item});

/// A medicine on the prescription being written.
class D5Med {
  final String name;
  final String dose;
  final String meta;
  final String caution;
  const D5Med(this.name, this.dose, this.meta, [this.caution = '']);
}

/// Dates of the consultation (the visit is on Tue, 29 Sep 2026).
class D5Date {
  D5Date._();
  static final today = DateTime(2026, 9, 29);
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// 'Thu, 29 Oct 2026'.
  static String format(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

  /// [d] plus an option such as '15 days', '2 weeks' or '3 months'.
  static DateTime add(DateTime d, String option) {
    final parts = option.split(' ');
    final n = int.tryParse(parts.first) ?? 0;
    final unit = parts.length > 1 ? parts[1] : 'days';
    if (unit.startsWith('week')) return DateTime(d.year, d.month, d.day + 7 * n);
    if (unit.startsWith('month')) return DateTime(d.year, d.month + n, d.day);
    return DateTime(d.year, d.month, d.day + n);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header, titles, labels
// ─────────────────────────────────────────────────────────────────────────────

/// White 64px top bar with a bottom border: back, title + subtitle and an
/// optional text action ("Save draft").
class D5Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onAction;
  const D5Header(this.title, {super.key, required this.subtitle, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 64px content + 1px bottom border, as in the design (content-box).
      height: 65,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(20, w: w700, h: 1.25), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: tx(13, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (action != null) ...[
            const Gap(4),
            Tap(
              onTap: onAction ?? () {},
              radius: 12,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Text(action!, style: tx(15, w: w600, c: MP.primary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Numbered step heading: 26px #003399 circle + 20/700 title (+ count).
class D5Step extends StatelessWidget {
  final String n;
  final String title;
  final String? trailing;
  const D5Step(this.n, this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
        child: Text(n, style: tx(13, w: w700, c: MP.white)),
      ),
      const Gap(10),
      Expanded(child: Text(title, style: tx(20, w: w700, h: 1.25))),
      if (trailing != null) ...[const Gap(10), Text(trailing!, style: tx(14, c: MP.ink2))],
    ],
  );
}

/// Uppercase label (12 / 700 / .06em) with an optional 14px icon.
class D5Label extends StatelessWidget {
  final String text;
  final Color color;
  final String? icon;
  final double stroke;
  final double bottom;
  const D5Label(this.text, {super.key, this.color = MP.ink3, this.icon, this.stroke = 2, this.bottom = 0});

  @override
  Widget build(BuildContext context) {
    final style = tx(12, w: w700, c: color, em: 0.06);
    final label = text.toUpperCase();
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child:
          icon == null
              ? Text(label, style: style)
              : D5IconText(icon: icon!, size: 14, stroke: stroke, color: color, gap: 6, text: label, style: style),
    );
  }
}

/// Max-content and min-content widths of [span], as CSS sizes text.
(double, double) _textWidths(BuildContext context, InlineSpan span) {
  final tp = TextPainter(
    text: span,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final widths = (tp.maxIntrinsicWidth, tp.minIntrinsicWidth);
  tp.dispose();
  return widths;
}

/// CSS flexbox "resolve flexible lengths" for a single line that overflows,
/// every item with flex-shrink 1: items start at [base] (max-content), shrink
/// in proportion to their base, and are frozen at [min] (min-content) when
/// they would go below it. [avail] excludes the gaps.
List<double> _flexShrink(List<double> base, List<double> min, double avail) {
  final n = base.length;
  final size = [...base];
  if (base.fold<double>(0, (a, b) => a + b) <= avail) return size;
  final frozen = List<bool>.generate(n, (i) => base[i] <= min[i]);
  for (var i = 0; i < n; i++) {
    if (frozen[i]) size[i] = min[i];
  }
  while (frozen.contains(false)) {
    var used = 0.0, scaled = 0.0;
    for (var i = 0; i < n; i++) {
      used += frozen[i] ? size[i] : base[i];
      if (!frozen[i]) scaled += base[i];
    }
    if (scaled <= 0) break;
    final free = avail - used;
    final clamped = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      if (frozen[i]) continue;
      final t = base[i] + free * base[i] / scaled;
      clamped[i] = t < min[i];
      size[i] = clamped[i] ? min[i] : t;
    }
    if (!clamped.contains(true)) break;
    for (var i = 0; i < n; i++) {
      if (clamped[i]) frozen[i] = true;
    }
  }
  return size;
}

/// CSS flex row of an icon, a gap and wrapping text where the icon has no
/// `flex-shrink: 0`. When the text's max-content width does not fit, Chrome
/// shrinks both items in proportion to their widths, so the icon gets smaller
/// (its SVG scales down inside the box) and the text wraps a little later.
class D5IconText extends StatelessWidget {
  final String icon;
  final double size;
  final double stroke;
  final Color color;
  final double gap;
  final String text;
  final TextStyle style;
  const D5IconText({
    super.key,
    required this.icon,
    required this.text,
    required this.style,
    this.size = 16,
    this.stroke = 1.75,
    this.color = MP.ink3,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final (textMax, textMin) = _textWidths(context, TextSpan(text: text, style: style));
      final w = _flexShrink([size, textMax], [0, textMin], constraints.maxWidth - gap)[0];
      return Row(
        children: [
          SizedBox(width: w, height: size, child: Center(child: Ico(icon, size: w, color: color, stroke: stroke))),
          SizedBox(width: gap),
          Expanded(child: Text(text, style: style)),
        ],
      );
    },
  );
}

/// Inline text link (14 / 600 / #003399), optionally with a 16px icon.
class D5Link extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  const D5Link(this.label, {super.key, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap ?? () {},
    radius: 6,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Ico(icon!, size: 16, color: MP.primary, stroke: 2), const Gap(6)],
        Text(label, style: tx(14, w: w600, c: MP.primary)),
      ],
    ),
  );
}

/// Sheet title row: 20/700 title, 14px subtitle and a 44px close button that
/// overhangs the corner (margin: -6px -10px 0 0 in the design).
class D5SheetTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const D5SheetTitle(this.title, {super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: tx(20, w: w700, h: 1.25)),
            const Gap(2),
            Text(subtitle, style: tx(14, c: MP.ink2)),
          ],
        ),
      ),
      const Gap(8),
      SizedBox(
        width: 34,
        height: 38,
        child: OverflowBox(
          alignment: Alignment.bottomLeft,
          minWidth: 44,
          maxWidth: 44,
          minHeight: 44,
          maxHeight: 44,
          child: MpIconButton(
            I.close,
            label: 'Close',
            color: MP.ink2,
            iconSize: 20,
            onTap: () => Navigator.pop(context),
          ),
        ),
      ),
    ],
  );
}

/// Amber caution box with the warning triangle.
class D5Note extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry margin;
  const D5Note(this.text, {super.key, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.alert, size: 16, color: MP.amber, stroke: 2)),
        const Gap(8),
        Expanded(child: Text(text, style: tx(13, h: 1.45))),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons and choices
// ─────────────────────────────────────────────────────────────────────────────

/// Full-width design button (56px / radius 16 / 16px 600 by default).
class D5Button extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final double iconSize;
  final double height;
  final double radius;
  final double fontSize;
  final Color bg;
  final Color fg;
  final Color? border;
  final List<BoxShadow>? shadow;

  /// Primary: #003399, white label, blue shadow.
  const D5Button(
    this.label, {
    super.key,
    this.onTap,
    this.icon,
    this.iconSize = 20,
    this.height = 56,
    this.radius = 16,
    this.fontSize = 16,
  }) : bg = MP.primary,
       fg = MP.white,
       border = null,
       shadow = MPShadow.button;

  /// White, #D5DBE5 border, ink label.
  const D5Button.secondary(
    this.label, {
    super.key,
    this.onTap,
    this.icon,
    this.iconSize = 20,
    this.height = 56,
    this.radius = 16,
    this.fontSize = 16,
  }) : bg = MP.white,
       fg = MP.ink,
       border = MP.lineStrong,
       shadow = null;

  /// White, #D5DBE5 border, blue label.
  const D5Button.outline(
    this.label, {
    super.key,
    this.onTap,
    this.icon,
    this.iconSize = 20,
    this.height = 56,
    this.radius = 16,
    this.fontSize = 16,
  }) : bg = MP.white,
       fg = MP.primary,
       border = MP.lineStrong,
       shadow = null;

  /// #EBF1FB fill, blue label.
  const D5Button.tonal(
    this.label, {
    super.key,
    this.onTap,
    this.icon,
    this.iconSize = 20,
    this.height = 56,
    this.radius = 16,
    this.fontSize = 16,
  }) : bg = MP.primarySoft,
       fg = MP.primary,
       border = null,
       shadow = null;

  /// Disabled: #E5E9F0 fill, #69738A label.
  const D5Button.disabled(this.label, {super.key, this.height = 56, this.radius = 16, this.fontSize = 16})
    : onTap = null,
      icon = null,
      iconSize = 20,
      bg = MP.line,
      fg = MP.ink3,
      border = null,
      shadow = null;

  /// Disabled outline: white, #E5E9F0 border, #69738A label.
  const D5Button.disabledOutline(this.label, {super.key, this.height = 56, this.radius = 16, this.fontSize = 16})
    : onTap = null,
      icon = null,
      iconSize = 20,
      bg = MP.white,
      fg = MP.ink3,
      border = MP.line,
      shadow = null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Tap(
          onTap: onTap,
          radius: radius,
          color: bg,
          border: border,
          shadow: shadow,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Ico(icon!, size: iconSize, color: fg), const Gap(8)],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(fontSize, w: w600, c: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40px pill choice. Solid: selected #003399 / white. Tonal: selected
/// #EBF1FB / #003399. Unselected: white, #545E72, 1px #D5DBE5.
class D5Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final bool tonal;

  /// CSS padding inside the 1px border.
  final EdgeInsets padding;
  final String? icon;
  final double iconStroke;
  const D5Chip(
    this.label, {
    super.key,
    required this.on,
    this.onTap,
    this.tonal = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.icon,
    this.iconStroke = 2,
  });

  /// Lab test chip: tonal when selected, with a check (on) or plus (off).
  const D5Chip.lab(this.label, {super.key, required this.on, this.onTap})
    : tonal = true,
      padding = const EdgeInsets.fromLTRB(10, 0, 14, 0),
      icon = on ? I.check : I.plus,
      iconStroke = on ? 2.5 : 2.0;

  @override
  Widget build(BuildContext context) {
    final bg = on ? (tonal ? MP.primarySoft : MP.primary) : MP.white;
    final fg = on ? (tonal ? MP.primary : MP.white) : MP.ink2;
    return Semantics(
      button: true,
      selected: on,
      child: SizedBox(
        height: 40,
        child: Tap(
          onTap: onTap ?? () {},
          radius: 999,
          color: bg,
          border: on ? MP.primary : MP.lineStrong,
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Ico(icon!, size: 16, color: fg, stroke: iconStroke), const Gap(6)],
              Text(label, style: tx(14, w: w600, c: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control: #F1F4F9 track (padding 4), white selected segment with
/// a hairline shadow, 600 #111827 vs 500 #545E72 labels, no gap.
class D5Segmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int>? onChanged;
  final double height;
  final double radius;
  final double innerRadius;
  final double fontSize;

  /// Equal columns (CSS grid) when true, content width (padding 0 14) when false.
  final bool expand;
  const D5Segmented({
    super.key,
    required this.options,
    required this.index,
    this.onChanged,
    this.height = 44,
    this.radius = 16,
    this.innerRadius = 12,
    this.fontSize = 15,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget segment(int i) {
      final sel = i == index;
      return Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged?.call(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: height,
            padding: expand ? null : const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? MP.white : MP.white.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(innerRadius),
              boxShadow: sel ? MPShadow.hairline : null,
            ),
            child: Text(
              options[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tx(fontSize, w: sel ? w600 : w500, c: sel ? MP.ink : MP.ink2),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(radius)),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [for (var i = 0; i < options.length; i++) expand ? Expanded(child: segment(i)) : segment(i)],
      ),
    );
  }
}

/// The 56px "Valid till … / Change" date button. As in the design's flex row,
/// the label wraps to two lines and the calendar icon shrinks when the label
/// does not fit beside "Change" (which never shrinks below its one word).
class D5DateRow extends StatelessWidget {
  final String lead;
  final String date;
  final VoidCallback? onTap;
  const D5DateRow({super.key, required this.lead, required this.date, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Tap(
      onTap: onTap ?? () {},
      radius: 16,
      color: MP.white,
      border: MP.lineStrong,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = TextSpan(text: lead, style: tx(16), children: [TextSpan(text: date, style: tx(16, w: w700))]);
          final change = TextSpan(text: 'Change', style: tx(14, w: w600, c: MP.primary));
          final (labelMax, labelMin) = _textWidths(context, label);
          final (changeMax, _) = _textWidths(context, change);
          final icon = _flexShrink([20, labelMax, changeMax], [0, labelMin, changeMax], constraints.maxWidth - 24)[0];
          return Row(
            children: [
              SizedBox(width: icon, height: 20, child: Center(child: Ico(I.calendar, size: icon, color: MP.ink2))),
              const SizedBox(width: 12),
              Expanded(child: Text.rich(label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 12),
              Text.rich(change),
            ],
          );
        },
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inputs
// ─────────────────────────────────────────────────────────────────────────────

/// Single-line design input: 56px, radius 16, 1px #D5DBE5 border; focused (or
/// [highlight]ed) → 2px #003399. [overlays] are Stack children drawn on top
/// (icons, "+91", units, mic buttons). The placeholder is clipped like a
/// browser placeholder instead of ending in an ellipsis.
class D5Field extends StatefulWidget {
  final TextEditingController? controller;
  final String? value;
  final String? hint;
  final double height;
  final double radius;
  final double padLeft;
  final double padRight;
  final double fontSize;
  final bool tab;
  final Color background;
  final bool highlight;
  final bool readOnly;
  final bool autofocus;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFocus;
  final List<Widget> overlays;
  const D5Field({
    super.key,
    this.controller,
    this.value,
    this.hint,
    this.height = 56,
    this.radius = 16,
    this.padLeft = 16,
    this.padRight = 16,
    this.fontSize = 16,
    this.tab = false,
    this.background = MP.white,
    this.highlight = false,
    this.readOnly = false,
    this.autofocus = false,
    this.keyboard,
    this.action,
    this.formatters,
    this.onChanged,
    this.onSubmitted,
    this.onFocus,
    this.overlays = const [],
  });

  @override
  State<D5Field> createState() => _D5FieldState();
}

class _D5FieldState extends State<D5Field> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: widget.value ?? '');
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_f.hasFocus) widget.onFocus?.call();
    setState(() {});
  }

  @override
  void dispose() {
    _f
      ..removeListener(_focusChanged)
      ..dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = !widget.readOnly && (widget.highlight || _f.hasFocus);
    final bw = on ? 2.0 : 1.0;
    final style = tx(widget.fontSize, tab: widget.tab);
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(left: widget.padLeft, right: widget.padRight),
              decoration: BoxDecoration(
                color: widget.background,
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(color: on ? MP.primary : MP.lineStrong, width: bw),
              ),
              child: IgnorePointer(
                ignoring: widget.readOnly,
                child: TextField(
                  controller: _c,
                  focusNode: _f,
                  autofocus: widget.autofocus,
                  readOnly: widget.readOnly,
                  keyboardType: widget.keyboard,
                  textInputAction: widget.action,
                  inputFormatters: widget.formatters,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: style,
                  cursorColor: MP.primary,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    // Kept for semantics; the visible placeholder is drawn below.
                    hintText: widget.hint,
                    hintStyle: style.copyWith(color: MP.ink3.withValues(alpha: 0)),
                  ),
                ),
              ),
            ),
          ),
          if (widget.hint != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(left: widget.padLeft + bw, right: widget.padRight + bw),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ListenableBuilder(
                      listenable: _c,
                      builder:
                          (context, _) =>
                              _c.text.isEmpty
                                  ? Text(
                                    widget.hint!,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.clip,
                                    style: tx(widget.fontSize, c: MP.ink3, tab: widget.tab),
                                  )
                                  : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ...widget.overlays,
        ],
      ),
    );
  }
}

/// Input with the 44px #EBF1FB mic button inside on the right.
class D5MicField extends StatelessWidget {
  final String hint;
  final String micLabel;
  final double fontSize;
  final TextEditingController? controller;
  final VoidCallback? onMic;
  final ValueChanged<String>? onSubmitted;
  const D5MicField({
    super.key,
    required this.hint,
    required this.micLabel,
    this.fontSize = 16,
    this.controller,
    this.onMic,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => D5Field(
    controller: controller,
    hint: hint,
    fontSize: fontSize,
    padRight: 60,
    action: TextInputAction.done,
    onSubmitted: onSubmitted,
    overlays: [
      Positioned(
        right: 6,
        top: 6,
        child: MpIconButton(
          I.mic,
          label: micLabel,
          iconSize: 20,
          color: MP.primary,
          background: MP.primarySoft,
          onTap: onMic,
        ),
      ),
    ],
  );
}

/// Patient search: magnifier on the left, 2px #003399 border, optional clear.
class D5SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? value;
  final String? hint;
  final bool autofocus;
  final bool tab;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  const D5SearchField({
    super.key,
    this.controller,
    this.value,
    this.hint,
    this.autofocus = false,
    this.tab = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => D5Field(
    controller: controller,
    value: value,
    hint: hint,
    highlight: true,
    autofocus: autofocus,
    tab: tab,
    padLeft: 46,
    padRight: onClear != null ? 52 : 16,
    action: TextInputAction.search,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    overlays: [
      const Positioned(left: 16, top: 0, bottom: 0, child: Center(child: Ico(I.search, size: 20, color: MP.ink2))),
      if (onClear != null)
        Positioned(
          right: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: MpIconButton(I.close, label: 'Clear search', iconSize: 18, color: MP.ink2, onTap: onClear),
          ),
        ),
    ],
  );
}

/// Multi-line field with the "Speak" button in its bottom-right corner.
class D5TextArea extends StatefulWidget {
  final TextEditingController? controller;
  final String? value;
  final String? hint;
  final double height;
  final double bottomPad;
  final String speakLabel;
  final VoidCallback? onSpeak;
  const D5TextArea({
    super.key,
    this.controller,
    this.value,
    this.hint,
    this.height = 120,
    this.bottomPad = 56,
    required this.speakLabel,
    this.onSpeak,
  });

  @override
  State<D5TextArea> createState() => _D5TextAreaState();
}

class _D5TextAreaState extends State<D5TextArea> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: widget.value ?? '');
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _f
      ..removeListener(_focusChanged)
      ..dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = _f.hasFocus;
    // In the design the textarea is inline-block inside a plain <div>, so the
    // wrapper is 4px taller (the 16px strut's descent) and the Speak button,
    // positioned against the wrapper, sits 4px above the textarea's bottom.
    return SizedBox(
      height: widget.height + 4,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: widget.height,
            // Like a CSS textarea, text may run into the padding (the third
            // line of a long complaint shows beside Speak) and is clipped at
            // the rounded border, not at the content box.
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 14, 16, widget.bottomPad),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: MP.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? MP.primary : MP.lineStrong, width: on ? 2 : 1),
              ),
              child: TextField(
                controller: _c,
                focusNode: _f,
                clipBehavior: Clip.none,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: tx(16, h: 1.5),
                cursorColor: MP.primary,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: tx(16, c: MP.ink3, h: 1.5),
                ),
              ),
            ),
          ),
          Positioned(right: 8, bottom: 8, child: _SpeakButton(label: widget.speakLabel, onTap: widget.onSpeak)),
        ],
      ),
    );
  }
}

class _SpeakButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SpeakButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Tap(
      onTap: onTap ?? () {},
      radius: 12,
      color: MP.primarySoft,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Ico(I.mic, size: 18, color: MP.primary),
            const Gap(6),
            Text('Speak', style: tx(14, w: w600, c: MP.primary)),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rows
// ─────────────────────────────────────────────────────────────────────────────

/// Selected diagnosis: #EBF1FB row with name, ICD code and a remove button.
class D5DxRow extends StatelessWidget {
  final String name;
  final String code;
  final VoidCallback? onRemove;
  const D5DxRow({super.key, required this.name, this.code = '', this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
    decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: tx(15, w: w600)),
                if (code.isNotEmpty) Text(code, style: tx(12, c: MP.ink2)),
              ],
            ),
          ),
        ),
        const Gap(10),
        MpIconButton(I.close, label: 'Remove $name', iconSize: 18, color: MP.ink2, onTap: onRemove),
      ],
    ),
  );
}

/// Suggestion row: name, reason and an outlined "+ Add" button.
class D5SuggestRow extends StatelessWidget {
  final String name;
  final String why;
  final bool first;
  final VoidCallback? onAdd;
  const D5SuggestRow({super.key, required this.name, required this.why, this.first = false, this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: MP.line))),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(name, style: tx(15, w: w600)), const Gap(2), Text(why, style: tx(13, c: MP.ink3))],
          ),
        ),
        const Gap(12),
        Semantics(
          button: true,
          label: 'Add $name',
          excludeSemantics: true,
          child: SizedBox(
            height: 40,
            child: Tap(
              onTap: onAdd ?? () {},
              radius: 12,
              color: MP.white,
              border: MP.lineStrong,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Ico(I.plus, size: 16, color: MP.primary, stroke: 2),
                  const Gap(4),
                  Text('Add', style: tx(14, w: w600, c: MP.primary)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Medicine card: name, dose, duration, edit / remove and an optional caution.
class D5MedCard extends StatelessWidget {
  final D5Med med;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  const D5MedCard({super.key, required this.med, this.onEdit, this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(med.name, style: tx(16, w: w700)),
                  const Gap(3),
                  Text(med.dose, style: tx(14, tab: true)),
                  const Gap(3),
                  Text(med.meta, style: tx(13, c: MP.ink3)),
                ],
              ),
            ),
            const Gap(8),
            MpIconButton(I.edit, label: 'Edit ${med.name}', iconSize: 18, color: MP.ink2, onTap: onEdit),
            const Gap(8),
            MpIconButton(I.close, label: 'Remove ${med.name}', iconSize: 18, color: MP.ink2, onTap: onRemove),
          ],
        ),
        if (med.caution.isNotEmpty) ...[const Gap(10), D5Note(med.caution, margin: const EdgeInsets.only(right: 8))],
      ],
    ),
  );
}

/// Patient row in the search lists: leading tile/avatar, name, meta, chevron.
class D5PersonRow extends StatelessWidget {
  final Widget leading;
  final String name;
  final InlineSpan meta;
  final bool first;
  final bool tab;
  final VoidCallback? onTap;
  const D5PersonRow({
    super.key,
    required this.leading,
    required this.name,
    required this.meta,
    this.first = false,
    this.tab = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    radius: 0,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: MP.line))),
      child: Row(
        children: [
          leading,
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: tx(16, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Gap(2),
                Text.rich(meta, style: tx(13, c: MP.ink2, tab: tab)),
              ],
            ),
          ),
          const Gap(12),
          const Ico(I.chevronRight, size: 18, color: MP.ink3),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 6 · Validity & follow-up
// ─────────────────────────────────────────────────────────────────────────────

/// "Prescription valid for" chips + date, divider, follow-up switch, chips,
/// date and the reminder checkbox. Dates follow the chosen option.
class D5ValidityFollowUp extends StatefulWidget {
  /// First name used in "Remind … 2 days before".
  final String patient;
  final bool followUp;

  /// Live: the visit day the options count from (the design's 29 Sep otherwise).
  final DateTime? today;

  /// Live: the draft's `validity` and `followUp` objects.
  final Map<String, dynamic>? validity;
  final Map<String, dynamic>? followUpData;

  /// Live: called with the new `validity` and `followUp` objects to save.
  final void Function(Map<String, dynamic> validity, Map<String, dynamic> followUp)? onChanged;
  const D5ValidityFollowUp({
    super.key,
    required this.patient,
    this.followUp = true,
    this.today,
    this.validity,
    this.followUpData,
    this.onChanged,
  });

  @override
  State<D5ValidityFollowUp> createState() => _D5ValidityFollowUpState();
}

class _D5ValidityFollowUpState extends State<D5ValidityFollowUp> {
  static const _validity = ['15 days', '1 month', '3 months'];
  static const _follow = ['1 week', '2 weeks', '1 month', '3 months'];
  static const _validityKeys = ['15_days', '1_month', '3_months'];
  static const _followKeys = ['1_week', '2_weeks', '1_month', '3_months'];

  late final DateTime _today = widget.today ?? D5Date.today;
  late int _v = _initialV();
  late int _f = _initialF();
  late DateTime _validTill = _initialDate(widget.validity?['validUntil']) ?? D5Date.add(_today, _validity[_v < 0 ? 1 : _v]);
  late DateTime _followOn = _initialDate(widget.followUpData?['date']) ?? D5Date.add(_today, _follow[_f < 0 ? 1 : _f]);
  late bool _followUp = widget.followUpData == null ? widget.followUp : widget.followUpData!['enabled'] == true;
  late bool _remind = widget.followUpData?['remindPatient'] != false;

  int _initialV() {
    final p = widget.validity?['preset'];
    if (p == null) return 1;
    return _validityKeys.indexOf('$p');
  }

  int _initialF() {
    final p = widget.followUpData?['preset'];
    if (p == null) return 1;
    return _followKeys.indexOf('$p');
  }

  DateTime? _initialDate(Object? v) {
    final d = F.date(v);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Hands the current choice to the screen (live) so it is saved.
  void _changed() {
    widget.onChanged?.call(
      {'preset': _v < 0 ? 'custom' : _validityKeys[_v], 'validUntil': _day(_validTill)},
      {
        'enabled': _followUp,
        'preset': _f < 0 ? 'custom' : _followKeys[_f],
        'date': _day(_followOn),
        'remindPatient': _remind,
      },
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changed();
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial.isBefore(_today) ? _today : initial,
    firstDate: _today,
    lastDate: widget.today == null ? DateTime(2027, 12, 31) : DateTime(_today.year + 2, 12, 31),
  );

  Future<void> _changeValidity() async {
    final d = await _pick(_validTill);
    if (d == null || !mounted) return;
    setState(() {
      _validTill = d;
      _v = _validity.indexWhere((o) => D5Date.add(_today, o) == d);
    });
  }

  Future<void> _changeFollowUp() async {
    final d = await _pick(_followOn);
    if (d == null || !mounted) return;
    setState(() {
      _followOn = d;
      _f = _follow.indexWhere((o) => D5Date.add(_today, o) == d);
    });
  }

  @override
  Widget build(BuildContext context) {
    return VGap(
      gap: 16,
      children: [
        VGap(
          gap: 10,
          children: [
            Text('Prescription valid for', style: tx(15, w: w600)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _validity.length; i++)
                  D5Chip(
                    _validity[i],
                    on: i == _v,
                    onTap:
                        () => setState(() {
                          _v = i;
                          _validTill = D5Date.add(_today, _validity[i]);
                        }),
                  ),
              ],
            ),
            D5DateRow(lead: 'Valid till ', date: D5Date.format(_validTill), onTap: _changeValidity),
          ],
        ),
        const MpDivider(),
        VGap(
          gap: 10,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _followUp = !_followUp),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Follow-up visit', style: tx(15, w: w600)),
                        const Gap(2),
                        Text('Optional', style: tx(13, c: MP.ink3)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  MpSwitch(value: _followUp, onChanged: (v) => setState(() => _followUp = v)),
                ],
              ),
            ),
            if (_followUp) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _follow.length; i++)
                    D5Chip(
                      _follow[i],
                      on: i == _f,
                      onTap:
                          () => setState(() {
                            _f = i;
                            _followOn = D5Date.add(_today, _follow[i]);
                          }),
                    ),
                ],
              ),
              D5DateRow(lead: 'Follow-up on ', date: D5Date.format(_followOn), onTap: _changeFollowUp),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _remind = !_remind),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      MpCheck(value: _remind, onChanged: (v) => setState(() => _remind = v)),
                      const Gap(12),
                      Expanded(child: Text('Remind ${widget.patient} 2 days before', style: tx(15))),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live data: API JSON ↔ the design's text
// ─────────────────────────────────────────────────────────────────────────────

/// Formatting and parsing shared by the live consultation screens.
class D5Live {
  D5Live._();

  static List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v is List ? v : const [])) if (x is Map) x.cast<String, dynamic>(),
  ];

  /// '9831120764' → '+91 98311 20764'.
  static String phone(Object? raw) {
    final d = '${raw ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (d.length != 10) return d.isEmpty ? '' : '+91 $d';
    return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
  }

  /// Digits of a typed phone number without the +91 / 0 prefix.
  static String digits(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 12 && d.startsWith('91')) return d.substring(2);
    if (d.length == 11 && d.startsWith('0')) return d.substring(1);
    return d;
  }

  /// '45 M' — the age and the gender's initial (either may be missing).
  static String ageSex(Map<String, dynamic> p) {
    final g = p.str('gender');
    return [if (p['age'] != null) '${p['age']}', if (g.isNotEmpty) g[0].toUpperCase()].join(' ');
  }

  static String gender(Object? g) => switch ('$g') {
    'female' => 'Female',
    'male' => 'Male',
    'other' => 'Other',
    _ => '',
  };

  /// 'waiting 22 min', 'waiting 1 h 5 min'.
  static String waiting(Object? min) {
    if (min is! num) return 'waiting';
    final m = min.round();
    if (m < 60) return 'waiting $m min';
    return 'waiting ${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}';
  }

  /// 7.0 → '7', 7.2 → '7.2'.
  static String number(Object? v) {
    if (v is! num) return v == null ? '' : '$v';
    return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  }

  /// Shows the code the dev backend returns for test numbers.
  static void devCode(BuildContext context, Object? res) {
    final code = res is Map ? res['devCode'] : null;
    if (code != null && context.mounted) toast(context, 'Test code: $code');
  }

  /// Opens [stem] in place of the current screen, with [args].
  static void replace(BuildContext context, String stem, Object? args) {
    final s = Nav.spec(stem);
    if (s == null) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        settings: RouteSettings(name: stem, arguments: args),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (c, _, __) => s.builder(c),
      ),
    );
  }

  /// Starts (or resumes) a consultation — POST /api/consultations — and
  /// opens [stem] for it.
  static Future<void> start(
    BuildContext context, {
    String? appointmentId,
    String? patientId,
    String stem = 'Consult-Page',
    bool justAdded = false,
    ValueNotifier<bool>? busy,
  }) async {
    final res = await runAction(
      context,
      () => Api.I.post('/api/consultations', {
        if (appointmentId != null) 'appointmentId': appointmentId else 'patientId': patientId,
      }),
      busy: busy,
    );
    if (res is! Map || !context.mounted) return;
    Nav.go(
      context,
      stem,
      args: {
        'consultationId': '${res['id']}',
        'patientId': '${res['patientId'] ?? patientId}',
        if (appointmentId != null) 'appointmentId': appointmentId,
        if (justAdded) 'justAdded': true,
      },
    );
  }

  // Medicines ----------------------------------------------------------------

  static const foodText = {
    'before_food': 'before food',
    'after_food': 'after food',
    'with_food': 'with food',
    'empty_stomach': 'empty stomach',
    'bedtime': 'at bedtime',
  };

  static const _weekdays = {
    'mon': 'Monday',
    'tue': 'Tuesday',
    'wed': 'Wednesday',
    'thu': 'Thursday',
    'fri': 'Friday',
    'sat': 'Saturday',
    'sun': 'Sunday',
  };

  /// 'Glimepiride 1 mg'.
  static String medName(Map<String, dynamic> m) =>
      [m.str('name'), m.str('strength')].where((s) => s.isNotEmpty).join(' ');

  /// '1-0-1', 'Once a week · Sunday' or 'As needed'.
  static String when(Map<String, dynamic> m) {
    switch (m['frequency']) {
      case 'weekly':
        final wd = _weekdays[m['weekday']];
        return wd == null ? 'Once a week' : 'Once a week · $wd';
      case 'as_needed':
        return 'As needed';
    }
    final d = m.obj('dose');
    return '${number(d['morning'] ?? 0)}-${number(d['afternoon'] ?? 0)}-${number(d['night'] ?? 0)}';
  }

  /// 'before breakfast' (the doctor's words) or 'after food'.
  static String food(Map<String, dynamic> m) {
    final i = m.str('instructions').trim();
    return i.isNotEmpty ? i : foodText[m['foodRelation']] ?? '';
  }

  /// '1-0-1 · after food'.
  static String doseText(Map<String, dynamic> m) {
    final f = food(m);
    return f.isEmpty ? when(m) : '${when(m)} · $f';
  }

  /// '30 days', '1 month', 'Ongoing' ('' without a duration).
  static String durationText(Object? d) {
    if (d is! Map) return '';
    final unit = '${d['unit'] ?? 'days'}';
    if (unit == 'ongoing') return 'Ongoing';
    final v = d['value'];
    if (v is! num || v <= 0) return '';
    final one = unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit;
    return v == 1 ? '1 $one' : '${number(v)} $unit';
  }

  /// Days in a duration (weeks × 7, months × 30); null when open-ended.
  static int? days(Object? d) {
    if (d is! Map || d['value'] is! num) return null;
    final v = (d['value'] as num).round();
    return switch ('${d['unit'] ?? 'days'}') {
      'weeks' => v * 7,
      'months' => v * 30,
      'ongoing' => null,
      _ => v,
    };
  }

  /// The medicine card for a draft line, with any warnings from the checks.
  static D5Med med(Map<String, dynamic> m, [List<String> warnings = const []]) {
    final dur = durationText(m['duration']);
    final change = m.str('change', 'new');
    final caution = <String>[
      if (m.str('caution').isNotEmpty) m.str('caution'),
      for (final w in warnings)
        if (w != m['caution']) w,
    ].join('\n');
    return D5Med(medName(m), doseText(m), dur.isEmpty ? change : '$dur · $change', caution);
  }

  static const _itemFields = [
    'medicineId', 'name', 'strength', 'form', 'dose', 'frequency', 'weekday', 'foodRelation', //
    'instructions', 'duration', 'quantity', 'change', 'caution', 'entrySource',
  ];

  /// A prescription line with only the fields the API stores.
  static Map<String, dynamic> item(Map<String, dynamic> m) => {
    for (final k in _itemFields)
      if (m[k] != null) k: m[k],
  };

  /// 'new', 'continued' or 'changed' against the patient's running medicines.
  static String change(Map<String, dynamic> m, List<Map<String, dynamic>> current) {
    final same = current.where((c) => c.str('name').toLowerCase() == m.str('name').toLowerCase());
    if (same.isEmpty) return 'new';
    return same.any((c) => c.str('strength') == m.str('strength')) ? 'continued' : 'changed';
  }

  /// "Prescribed 1 times for …" reads "Prescribed once for …".
  static String reason(Object? r) => '${r ?? ''}'.replaceAll(RegExp(r'\b1 times\b'), 'once');

  static const _numbers = <String, num>{
    'half': 0.5, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, //
    'nine': 9, 'ten': 10, 'twelve': 12, 'fourteen': 14, 'fifteen': 15, 'twenty': 20, 'thirty': 30,
    'forty': 40, 'fifty': 50, 'sixty': 60, 'ninety': 90, 'hundred': 100,
  };
  static const _units = {
    'mg': 'mg', 'g': 'g', 'gm': 'g', 'mcg': 'mcg', 'iu': 'IU', 'ml': 'ml', 'unit': 'units', 'units': 'units', //
  };
  static const _stop = {
    'once', 'twice', 'thrice', 'daily', 'weekly', 'morning', 'afternoon', 'night', 'evening', 'bedtime', //
    'before', 'after', 'with', 'for', 'at', 'in', 'od', 'bd', 'bid', 'tds', 'tid', 'sos', 'every', 'a', 'x',
  };

  static num? _num(String w) => num.tryParse(w.replaceAll(',', '')) ?? _numbers[w.toLowerCase()];

  /// Reads a typed or spoken line — "Metformin 500 twice daily",
  /// "Glimepiride one mg, once in the morning before breakfast, for thirty
  /// days", "Atorvastatin 20 at night for 3 months" — into a prescription line.
  static Map<String, dynamic> parse(String text, {String source = 'typed'}) {
    final words = <String>[
      for (final w in text.replaceAll(RegExp(r'[“”"]'), ' ').split(RegExp(r'\s+')))
        if (w.replaceAll(RegExp(r'[,.;]+$'), '').isNotEmpty) w.replaceAll(RegExp(r'[,.;]+$'), ''),
    ];
    var i = 0;
    final name = <String>[];
    while (i < words.length &&
        _num(words[i]) == null &&
        !RegExp(r'^\d').hasMatch(words[i]) &&
        !(name.isNotEmpty && _stop.contains(words[i].toLowerCase()))) {
      name.add(words[i]);
      i++;
    }
    String? strength;
    final glued =
        i < words.length
            ? RegExp(r'^(\d[\d,]*(?:\.\d+)?)(mg|g|gm|mcg|iu|ml)$', caseSensitive: false).firstMatch(words[i])
            : null;
    if (glued != null) {
      strength = '${number(_num(glued.group(1)!))} ${_units[glued.group(2)!.toLowerCase()]}';
      i++;
    } else if (i < words.length && _num(words[i]) != null && !words[i].contains('-')) {
      final v = _num(words[i])!;
      i++;
      var unit = 'mg';
      if (i < words.length && _units.containsKey(words[i].toLowerCase())) unit = _units[words[i++].toLowerCase()]!;
      strength = '${number(v)} $unit';
    }
    final rest = ' ${words.sublist(i).join(' ').toLowerCase()} ';
    bool has(String re) => RegExp(re).hasMatch(rest);

    var dose = <String, num>{'morning': 1, 'afternoon': 0, 'night': 0};
    var frequency = 'daily';
    String? weekday;
    final pattern = RegExp(r'\b(\d(?:\.\d)?)\s*-\s*(\d(?:\.\d)?)\s*-\s*(\d(?:\.\d)?)\b').firstMatch(rest);
    if (pattern != null) {
      dose = {
        'morning': num.parse(pattern.group(1)!),
        'afternoon': num.parse(pattern.group(2)!),
        'night': num.parse(pattern.group(3)!),
      };
    } else if (has(r'\b(weekly|once a week|every week)\b')) {
      frequency = 'weekly';
      for (final e in _weekdays.entries) {
        if (rest.contains(e.value.toLowerCase())) weekday = e.key;
      }
    } else if (has(r'\b(sos|as needed|when needed|if needed)\b')) {
      frequency = 'as_needed';
      dose = {'morning': 0, 'afternoon': 0, 'night': 0};
    } else if (has(r'\b(thrice|three times|tds|tid)\b')) {
      dose = {'morning': 1, 'afternoon': 1, 'night': 1};
    } else if (has(r'\b(twice|two times|bd|bid)\b')) {
      dose = {'morning': 1, 'afternoon': 0, 'night': 1};
    } else {
      final m = has(r'\b(morning|breakfast)\b');
      final a = has(r'\b(afternoon|lunch)\b');
      final n = has(r'\b(night|evening|dinner|bedtime)\b');
      if (m || a || n) dose = {'morning': m ? 1 : 0, 'afternoon': a ? 1 : 0, 'night': n ? 1 : 0};
    }

    String? foodRelation;
    String? instructions;
    final meal = RegExp(r'\b(before|after|with)\s+(food|meals?|breakfast|lunch|dinner)\b').firstMatch(rest);
    if (meal != null) {
      foodRelation = '${meal.group(1)}_food';
      instructions = '${meal.group(1)} ${meal.group(2)}';
    } else if (has(r'\bempty stomach\b')) {
      foodRelation = 'empty_stomach';
      instructions = 'empty stomach';
    } else if (has(r'\bbedtime\b')) {
      foodRelation = 'bedtime';
    }

    Map<String, dynamic>? duration;
    // "for 8 weeks" (not the "a week" of "once a week").
    final dm = RegExp(r'(\S+)\s+(days?|weeks?|months?)\b')
        .allMatches(rest)
        .where((m) => (_num(m.group(1)!) ?? 0) > 0)
        .firstOrNull;
    final dv = dm == null ? null : _num(dm.group(1)!);
    if (dm != null && dv != null) {
      final u = dm.group(2)!;
      duration = {'value': dv.round(), 'unit': u.endsWith('s') ? u : '${u}s'};
    } else if (has(r'\b(ongoing|long term|continue)\b')) {
      duration = {'unit': 'ongoing'};
    }

    final n = name.join(' ');
    return {
      'name': n.isEmpty ? n : n[0].toUpperCase() + n.substring(1),
      if (strength != null) 'strength': strength,
      'dose': dose,
      'frequency': frequency,
      if (weekday != null) 'weekday': weekday,
      if (foodRelation != null) 'foodRelation': foodRelation,
      if (instructions != null) 'instructions': instructions,
      if (duration != null) 'duration': duration,
      'entrySource': source,
    };
  }

  // Snapshot -----------------------------------------------------------------

  /// 'LDL 162 ↑', 'HbA1c 7.2% ↑', 'Vitamin D 14 ↓' (latest per analyte).
  static List<String> abnormal(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    return [
      for (final r in rows)
        if (seen.add(r.str('analyte', r.str('test')).toLowerCase()))
          '${r.str('analyte', r.str('test')).replaceFirst(RegExp(r'\s+cholesterol$', caseSensitive: false), '')} '
              '${number(r['value'])}${r['unit'] == '%' ? '%' : ''} ${r['flag'] == 'low' ? '↓' : '↑'}',
    ];
  }

  /// The six vitals tiles: (label, value, unit, colour).
  static List<(String, String, String, Color)> vitalTiles(Map<String, dynamic> v) {
    String n(Object? x) => x is num ? number(x) : '—';
    final sys = v['bpSystolic'], dia = v['bpDiastolic'];
    final sugar = v['bloodSugar'];
    final fasting = v['sugarType'] != 'random';
    final bpHigh = (sys is num && sys >= 140) || (dia is num && dia >= 90);
    final sugarHigh = sugar is num && sugar >= (fasting ? 100 : 140);
    final spo2 = v['spo2'];
    return [
      ('BP', sys is num && dia is num ? '${n(sys)}/${n(dia)}' : '—', 'mmHg', bpHigh ? MP.amber : MP.ink),
      ('Pulse', n(v['pulse']), 'bpm', MP.ink),
      ('SpO₂', n(spo2), '%', spo2 is num && spo2 < 95 ? MP.amber : MP.ink),
      (fasting ? 'Sugar (F)' : 'Sugar (R)', n(sugar), 'mg/dL', sugarHigh ? MP.amber : MP.ink),
      ('Weight', n(v['weightKg']), 'kg', MP.ink),
      ('Temp', n(v['temperatureF']), '°F', MP.ink),
    ];
  }

  /// 'Recorded at front desk, 8:52 AM', 'Home reading, 28 Sep, 7:40 AM'.
  static String recorded(Map<String, dynamic> v, String myUserId) {
    final at = F.date(v['recordedAt']);
    final when = at == null ? '' : (F.sameDay(at, DateTime.now()) ? F.time(at) : '${F.dayMonth(at)}, ${F.time(at)}');
    final who =
        v['source'] == 'home' || v['recordedByRole'] == 'patient'
            ? 'Home reading'
            : v.str('recordedBy') == myUserId && myUserId.isNotEmpty
            ? 'Recorded by you'
            : v['recordedByRole'] == 'doctor'
            ? 'Recorded by the doctor'
            : 'Recorded at front desk';
    return when.isEmpty ? who : '$who, $when';
  }
}

/// The draft consultation behind Consult-Page and Consult-Blank (live):
/// opens or resumes it, keeps the snapshot, and saves every change with
/// PATCH /api/consultations/:id after a short pause.
mixin D5Draft<W extends StatefulWidget> on LiveData<W> {
  String? consultId;
  Map<String, dynamic> consult = const {};
  Map<String, dynamic> summary = const {};
  Map<String, dynamic>? vitals;
  Map<String, dynamic>? appointment;
  List<Map<String, dynamic>> previousDiagnoses = const [];
  Object? previousVisitAt;
  List<Map<String, dynamic>> checks = const [];
  Map<String, dynamic> suggestions = const {};

  /// Opened right after Consult-QuickAdd created the patient.
  bool justAdded = false;

  /// The prescription once "Generate prescription" has issued it.
  String? issuedRxId;
  final busy = ValueNotifier(false);

  Timer? _saveTimer;
  final _pending = <String, dynamic>{};
  Future<void>? _saving;

  /// Something was typed or picked on this screen (so the draft is kept).
  bool _edited = false;

  /// This screen started (or reopened) the draft; only it may discard an empty one.
  bool _openedHere = false;

  /// True while a change to [field] is still waiting to be sent.
  bool pendingHas(String field) => _pending.containsKey(field);

  Map<String, dynamic> get patient => summary.obj('patient');
  String get patientId => consult.str('patientId', patient.str('id'));
  String get firstName => F.firstName(patient.str('name'));
  List<Map<String, dynamic>> get currentMedicines => summary.list('currentMedicines');

  /// The draft has loaded: fill the screen's lists and fields from it.
  void draftLoaded();

  /// Everything on the screen, saved by "Save draft".
  Map<String, dynamic> draftFields();

  /// A save returned the draft ([fields] were sent); runs inside setState.
  void draftSaved(Set<String> fields) {}

  /// Runs before "Save draft" / "Generate prescription" (e.g. record vitals).
  Future<bool> beforeSave() async => true;

  /// Warnings from GET …/checks for the draft medicine at [i].
  List<String> warningsAt(int i) => [
    if (i < checks.length)
      for (final w in checks[i].list('warnings')) w.str('text'),
  ];

  /// 'Started 9:14 AM · draft saved'.
  String get startedLine {
    final s = F.date(consult['startedAt']);
    final base = s == null ? 'Draft' : 'Started ${F.time(s)}';
    return consult['draftSavedAt'] != null ? '$base · draft saved' : base;
  }

  /// For fetch(): resolves the consultation from the route args and loads it.
  Future<Map<String, dynamic>> loadDraft() async {
    await Future<void>.value(); // the route args are read after initState
    if (!mounted) return const {};
    final a = Nav.args<Map>(context) ?? const {};
    justAdded = a['justAdded'] == true;
    var id = a['consultationId'] as String?;
    if (id == null) {
      Map<String, dynamic> body;
      if (a['appointmentId'] != null) {
        body = {'appointmentId': a['appointmentId']};
      } else if (a['patientId'] != null) {
        body = {'patientId': a['patientId']};
      } else {
        // No patient chosen: the doctor's patient in consultation now, if any.
        final r = await Api.I.get(
          '/api/appointments',
          query: {'view': 'today', 'doctorId': 'me', 'status': 'in_consultation'},
        );
        final items = D5Live.list(r is Map ? r['items'] : null);
        if (items.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            toast(context, 'Choose a patient first');
            Nav.tab(context, 'Consult-Pick');
          });
          throw const ApiException(404, 'NO_PATIENT', 'Choose a patient first');
        }
        body = {'appointmentId': items.first['id']};
      }
      final c = await Api.I.post('/api/consultations', body);
      id = '${(c as Map)['id']}';
      _openedHere = true;
    }
    final res = await Future.wait([
      Api.I.get('/api/consultations/$id'),
      Api.I.get('/api/consultations/$id/checks'),
      Api.I.get('/api/consultations/$id/suggestions'),
    ]);
    final d = (res[0] as Map).cast<String, dynamic>();
    consultId = id;
    consult = d.obj('consultation');
    summary = d.obj('summary');
    vitals = d['vitals'] is Map ? d.obj('vitals') : null;
    previousDiagnoses = d.list('previousDiagnoses');
    previousVisitAt = d['previousVisitAt'];
    checks = D5Live.list(res[1]);
    suggestions = res[2] is Map ? (res[2] as Map).cast<String, dynamic>() : const {};
    appointment = null;
    if (consult['appointmentId'] != null) {
      try {
        final ap = await Api.I.get('/api/appointments/${consult['appointmentId']}');
        if (ap is Map) appointment = ap.cast<String, dynamic>();
      } on ApiException {
        appointment = null;
      }
    }
    if (consult['status'] != null && consult['status'] != 'draft') issuedRxId = consult.str('prescriptionId');
    draftLoaded();
    return d;
  }

  /// Queues [fields] for PATCH /api/consultations/:id.
  void save(Map<String, dynamic> fields, {Duration delay = const Duration(milliseconds: 700)}) {
    if (!isLive || consultId == null || issuedRxId != null) return;
    _edited = true;
    _pending.addAll(fields);
    _saveTimer?.cancel();
    _saveTimer = Timer(delay, flush);
  }

  /// Sends the queued changes now; false when the save failed.
  Future<bool> flush() async {
    _saveTimer?.cancel();
    while (_saving != null) {
      await _saving;
    }
    if (_pending.isEmpty || consultId == null) return true;
    final body = Map<String, dynamic>.of(_pending);
    _pending.clear();
    var ok = false;
    Future<void> send() async {
      try {
        final res = await Api.I.patch('/api/consultations/$consultId', body);
        if (res is Map) consult = res.cast<String, dynamic>();
        if (body.containsKey('medications')) {
          try {
            checks = D5Live.list(await Api.I.get('/api/consultations/$consultId/checks'));
          } on ApiException {
            // keep the previous warnings
          }
        }
        if (body.containsKey('diagnoses')) {
          try {
            final s = await Api.I.get('/api/consultations/$consultId/suggestions');
            if (s is Map) suggestions = s.cast<String, dynamic>();
          } on ApiException {
            // keep the previous suggestions
          }
        }
        ok = true;
        if (mounted) setState(() => draftSaved(body.keys.toSet()));
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message);
      }
    }

    final f = send();
    _saving = f;
    await f;
    _saving = null;
    return ok;
  }

  /// "Save draft".
  Future<void> saveDraft() async {
    if (busy.value) return;
    busy.value = true;
    try {
      if (!await beforeSave()) return;
      _pending.addAll(draftFields());
      if (await flush() && mounted) toast(context, 'Draft saved');
    } finally {
      busy.value = false;
    }
  }

  /// "Generate prescription": saves, issues, then opens the prescription.
  Future<void> generate() async {
    if (issuedRxId != null) {
      Nav.go(context, 'Prescriptions', args: {'prescriptionId': issuedRxId, 'patientId': patientId, 'consultationId': consultId});
      return;
    }
    if (busy.value) return;
    busy.value = true;
    try {
      if (!await beforeSave()) return;
      _pending.addAll(draftFields());
      if (!await flush() || !mounted) return;
    } finally {
      busy.value = false;
    }
    final res = await withSignature(context, () => Api.I.post('/api/consultations/$consultId/issue'), busy: busy);
    if (res is! Map || !mounted) return;
    final rx = res['prescription'] is Map ? (res['prescription'] as Map) : const {};
    setState(() {
      issuedRxId = '${rx['id']}';
      if (res['consultation'] is Map) consult = (res['consultation'] as Map).cast<String, dynamic>();
    });
    toast(context, 'Prescription generated');
    Nav.go(context, 'Prescriptions', args: {'prescriptionId': issuedRxId, 'patientId': patientId, 'consultationId': consultId});
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_pending.isNotEmpty) {
      flush();
    } else if (isLive && _openedHere && consultId != null && issuedRxId == null && !_edited && _isEmptyDraft) {
      // Opened and left without entering anything: don't leave an empty draft behind
      // (the server deletes it only if it is still empty).
      // A few seconds later, so a save still on its way from another consult screen lands first.
      final id = consultId;
      Future.delayed(const Duration(seconds: 4), () => Api.I.delete('/api/consultations/$id')).catchError((_) => null);
    }
    busy.dispose();
    super.dispose();
  }

  bool get _isEmptyDraft =>
      consult.str('status', 'draft') == 'draft' &&
      consult.str('chiefComplaint').isEmpty &&
      consult.list('diagnoses').isEmpty &&
      consult.list('medications').isEmpty &&
      consult.list('labOrders').isEmpty;
}

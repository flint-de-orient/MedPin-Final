import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';

// Shared pieces for the consultation screens of batch D5:
// Consult-Page, Consult-Voice, Consult-Dosage, Consult-Pick,
// Consult-NotFound, Consult-QuickAdd and Consult-Blank.

/// What the dosage and voice sheets hand back when a medicine is added.
typedef D5MedResult = ({String name, String dose, String duration});

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
  const D5ValidityFollowUp({super.key, required this.patient, this.followUp = true});

  @override
  State<D5ValidityFollowUp> createState() => _D5ValidityFollowUpState();
}

class _D5ValidityFollowUpState extends State<D5ValidityFollowUp> {
  static const _validity = ['15 days', '1 month', '3 months'];
  static const _follow = ['1 week', '2 weeks', '1 month', '3 months'];

  int _v = 1;
  int _f = 1;
  late DateTime _validTill = D5Date.add(D5Date.today, _validity[_v]);
  late DateTime _followOn = D5Date.add(D5Date.today, _follow[_f]);
  late bool _followUp = widget.followUp;
  bool _remind = true;

  Future<DateTime?> _pick(DateTime initial) =>
      showDatePicker(context: context, initialDate: initial, firstDate: D5Date.today, lastDate: DateTime(2027, 12, 31));

  Future<void> _changeValidity() async {
    final d = await _pick(_validTill);
    if (d == null || !mounted) return;
    setState(() {
      _validTill = d;
      _v = _validity.indexWhere((o) => D5Date.add(D5Date.today, o) == d);
    });
  }

  Future<void> _changeFollowUp() async {
    final d = await _pick(_followOn);
    if (d == null || !mounted) return;
    setState(() {
      _followOn = d;
      _f = _follow.indexWhere((o) => D5Date.add(D5Date.today, o) == d);
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
                          _validTill = D5Date.add(D5Date.today, _validity[i]);
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
                            _followOn = D5Date.add(D5Date.today, _follow[i]);
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

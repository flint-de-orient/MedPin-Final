import 'package:flutter/material.dart' hide Text;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/icons.dart';
import '../core/nav.dart';
import '../core/tokens.dart';
import 'i18n.dart';

export '../core/icons.dart';
export '../core/nav.dart';
export '../core/tokens.dart';
export 'navs.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page scaffolding
// ─────────────────────────────────────────────────────────────────────────────

/// Standard MedPin page: #F7F9FC background, optional pinned [header],
/// scrolling [body], optional floating [nav] (bottom nav) and pinned [bottom]
/// (sticky action bar). Pass [scroll] = false when [body] scrolls itself.
class MpPage extends StatelessWidget {
  final Widget? header;
  final Widget body;
  final Widget? nav;
  final Widget? bottom;
  final Color background;
  final bool scroll;
  final EdgeInsetsGeometry padding;

  /// Extra widgets stacked over the page (FABs etc.).
  final List<Widget> overlays;

  const MpPage({
    super.key,
    this.header,
    required this.body,
    this.nav,
    this.bottom,
    this.background = MP.bg,
    this.scroll = true,
    this.padding = EdgeInsets.zero,
    this.overlays = const [],
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // Room under the content so the floating nav never hides it (design: 112px).
    final navSpace = nav != null ? 112.0 + safeBottom : 0.0;
    Widget content = Padding(padding: padding, child: body);
    if (scroll) {
      content = SingleChildScrollView(
        padding: EdgeInsets.only(bottom: navSpace),
        child: content,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null) header!,
                  Expanded(child: content),
                  if (bottom != null) bottom!,
                ],
              ),
              if (nav != null) Positioned(left: 16, right: 16, bottom: 24 + safeBottom, child: nav!),
              ...overlays,
            ],
          ),
        ),
      ),
    );
  }
}

/// The 64px top bar: back button (44×44) + title (20/700) + trailing actions.
class MpHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;
  final Color background;
  final bool border;

  /// Use the close (×) glyph instead of the back arrow.
  final bool close;

  const MpHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
    this.onBack,
    this.background = MP.bg,
    this.border = false,
    this.close = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: (subtitle == null ? 64 : 72) + (border ? 1 : 0),
      padding: EdgeInsets.fromLTRB(showBack ? 4 : 20, 0, 8, 0),
      decoration: BoxDecoration(
        color: background,
        border: border ? const Border(bottom: BorderSide(color: MP.line)) : null,
      ),
      child: Row(
        children: [
          if (showBack)
            MpIconButton(
              close ? I.close : I.back,
              label: close ? 'Close' : 'Back',
              onTap: onBack ?? () => Nav.back(context),
            ),
          if (showBack) const Gap(4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(20, w: w700, h: 1.25), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) Text(subtitle!, style: tx(13, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 44×44 transparent icon button (radius 12).
class MpIconButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? borderColor;
  final double radius;
  final double stroke;
  final bool filled;
  const MpIconButton(
    this.icon, {
    super.key,
    required this.label,
    this.onTap,
    this.color = MP.ink,
    this.size = 44,
    this.iconSize = 22,
    this.background,
    this.borderColor,
    this.radius = 12,
    this.stroke = 1.75,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    // Outer size stays `size` with or without a border (border-box button).
    final button = SizedBox(
      width: size,
      height: size,
      child: Tap(
        onTap: onTap ?? () {},
        radius: radius,
        color: background,
        border: borderColor,
        child: Center(child: Ico(icon, size: iconSize, color: color, stroke: stroke, filled: filled)),
      ),
    );
    // The standard 44px button keeps its look but gets a 48×48 touch area
    // (Android minimum). Deliberately small ones (36, 40) sit in tight rows
    // and keep their size.
    if (size >= 48 || size < 44) return Semantics(button: true, label: label, child: button);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: button)),
      ),
    );
  }
}

/// Pressable surface: decoration + ink ripple clipped to [radius].
class Tap extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final BorderRadius? borderRadius;
  final Color? color;
  final Color? border;
  final double borderWidth;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;
  const Tap({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 12,
    this.borderRadius,
    this.color,
    this.border,
    this.borderWidth = 1,
    this.shadow,
    this.padding,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(radius);
    // Like Container with a BoxDecoration border (and CSS): the border takes
    // layout space, so the child is inset by its width.
    final inset = border == null ? EdgeInsets.zero : EdgeInsets.all(borderWidth);
    final pad = padding == null ? inset : padding!.add(inset);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: br,
        boxShadow: shadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: br,
          side: border == null ? BorderSide.none : BorderSide(color: border!, width: borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: pad == EdgeInsets.zero ? child : Padding(padding: pad, child: child),
        ),
      ),
    );
  }
}

/// White card: 1px #E5E9F0 border, radius 24, padding 20, soft shadow.
class MpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color border;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;
  const MpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.color = MP.white,
    this.border = MP.line,
    this.shadow = MPShadow.card,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (onTap != null) {
      return Tap(
        onTap: onTap,
        radius: radius,
        color: color,
        border: border,
        shadow: shadow,
        padding: padding,
        child: child,
      );
    }
    return Container(
      padding: padding,
      decoration: MPDeco.card(radius: radius, color: color, border: border, shadow: shadow),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

enum MpBtn { primary, secondary, tonal, ghost, danger, dangerSoft, dark }

/// Design buttons. Primary: 56px, radius 16, #003399, blue shadow.
class MpButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final MpBtn kind;
  final double height;
  final double radius;
  final double fontSize;
  final String? icon;
  final bool iconAfter;
  final double iconSize;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final double iconStroke;
  const MpButton(
    this.label, {
    super.key,
    this.onTap,
    this.kind = MpBtn.primary,
    this.height = 56,
    this.radius = 16,
    this.fontSize = 16,
    this.icon,
    this.iconAfter = false,
    this.iconSize = 20,
    this.expand = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.iconStroke = 2,
  });

  /// Compact 48px / radius 12 / 15px variant used inside cards.
  const MpButton.small(
    this.label, {
    super.key,
    this.onTap,
    this.kind = MpBtn.tonal,
    this.icon,
    this.iconAfter = false,
    this.expand = true,
    this.iconSize = 18,
    this.iconStroke = 2,
  })  : height = 48,
        radius = 12,
        fontSize = 15,
        padding = const EdgeInsets.symmetric(horizontal: 16);

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    Color? border;
    List<BoxShadow>? shadow;
    switch (kind) {
      case MpBtn.primary:
        bg = MP.primary;
        fg = MP.white;
        shadow = MPShadow.button;
      case MpBtn.secondary:
        bg = MP.white;
        fg = MP.ink;
        border = MP.lineStrong;
      case MpBtn.tonal:
        bg = MP.primarySoft;
        fg = MP.primary;
      case MpBtn.ghost:
        bg = Colors.transparent;
        fg = MP.primary;
      case MpBtn.danger:
        bg = MP.red;
        fg = MP.white;
      case MpBtn.dangerSoft:
        bg = Colors.transparent;
        fg = MP.red;
      case MpBtn.dark:
        bg = MP.ink;
        fg = MP.white;
    }
    final ic = icon == null ? null : Ico(icon!, size: iconSize, color: fg, stroke: iconStroke);
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (ic != null && !iconAfter) ...[ic, const Gap(8)],
        Flexible(child: Text(label, style: tx(fontSize, w: w600, c: fg), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (ic != null && iconAfter) ...[const Gap(8), ic],
      ],
    );
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Tap(
        onTap: onTap ?? () {},
        radius: radius,
        color: bg,
        border: border,
        shadow: shadow,
        child: Padding(padding: padding, child: row),
      ),
    );
  }
}

/// Text link styled as in the design (14–15px, 600, #003399 by default).
class MpLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final FontWeight weight;
  final String? icon;
  final bool iconAfter;
  final double height;
  const MpLink(
    this.label, {
    super.key,
    this.onTap,
    this.color = MP.primary,
    this.size = 14,
    this.weight = w600,
    this.icon,
    this.iconAfter = true,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final ic = icon == null ? null : Ico(icon!, size: size + 2, color: color, stroke: 2);
    return Tap(
      onTap: onTap ?? () {},
      radius: 8,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ic != null && !iconAfter) ...[ic, const Gap(6)],
            Text(label, style: tx(size, w: weight, c: color)),
            if (ic != null && iconAfter) ...[const Gap(4), ic],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form controls
// ─────────────────────────────────────────────────────────────────────────────

/// Field label (14 / 600).
class MpLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  final double? h;
  const MpLabel(this.text, {super.key, this.trailing, this.h});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(text, style: tx(14, w: w600, h: h))),
          if (trailing != null) Text(trailing!, style: tx(13, c: MP.ink3, h: h)),
        ],
      );
}

/// Text input: 56px, radius 16, 1px #D5DBE5 border; focus → #003399 border
/// with a 3px #EBF1FB ring. Supports a "+91"-style [prefixText] cell, leading
/// icon, unit/trailing widget, label and help text.
class MpInput extends StatefulWidget {
  final String? label;
  final String? labelTrailing;
  final String? value;
  final String? hint;
  final String? help;
  final Color? helpColor;
  final String? prefixText;
  final String? leadingIcon;
  final Widget? trailing;
  final String? unit;
  final double height;
  final double radius;
  final int maxLines;
  final TextInputType? keyboard;
  final bool obscure;
  final bool autofocus;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final double fontSize;
  final double? width;
  final bool forceFocus;
  final Color? borderColor;
  final TextEditingController? controller;
  final TextAlign align;
  final bool tab;
  const MpInput({
    super.key,
    this.label,
    this.labelTrailing,
    this.value,
    this.hint,
    this.help,
    this.helpColor,
    this.prefixText,
    this.leadingIcon,
    this.trailing,
    this.unit,
    this.height = 56,
    this.radius = 16,
    this.maxLines = 1,
    this.keyboard,
    this.obscure = false,
    this.autofocus = false,
    this.readOnly = false,
    this.onChanged,
    this.onTap,
    this.fontSize = 16,
    this.width,
    this.forceFocus = false,
    this.borderColor,
    this.controller,
    this.align = TextAlign.start,
    this.tab = false,
  });

  @override
  State<MpInput> createState() => _MpInputState();
}

class _MpInputState extends State<MpInput> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: widget.value ?? '');
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _f.hasFocus || widget.forceFocus;
    final multi = widget.maxLines > 1;
    final field = TextField(
      controller: _c,
      focusNode: _f,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      obscureText: widget.obscure,
      keyboardType: widget.keyboard ?? (multi ? TextInputType.multiline : null),
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: multi ? widget.maxLines : 1,
      onChanged: widget.onChanged,
      textAlign: widget.align,
      style: tx(widget.fontSize, h: multi ? 1.5 : null, tab: widget.tab),
      cursorColor: MP.primary,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: widget.hint == null ? null : tr(context, widget.hint!),
        hintStyle: tx(widget.fontSize, c: MP.ink3, h: multi ? 1.5 : null),
      ),
    );
    final box = Container(
      width: widget.width,
      height: multi ? null : widget.height,
      constraints: multi ? BoxConstraints(minHeight: widget.height) : null,
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: focused ? MP.primary : (widget.borderColor ?? MP.lineStrong)),
        boxShadow: focused ? MPShadow.focusRing : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (widget.prefixText != null)
            Container(
              height: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              alignment: Alignment.center,
              decoration: const BoxDecoration(border: Border(right: BorderSide(color: MP.line))),
              child: Text(widget.prefixText!, style: tx(16, w: w600, c: MP.ink2, tab: true)),
            ),
          if (widget.leadingIcon != null)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Ico(widget.leadingIcon!, size: 20, color: MP.ink3),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.prefixText != null ? 12 : (widget.leadingIcon != null ? 10 : 16),
                multi ? 14 : 0,
                widget.trailing != null || widget.unit != null ? 8 : 16,
                multi ? 14 : 0,
              ),
              child: field,
            ),
          ),
          if (widget.unit != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(widget.unit!, style: tx(14, c: MP.ink3)),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
    if (widget.label == null && widget.help == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[MpLabel(widget.label!, trailing: widget.labelTrailing), const Gap(8)],
        box,
        if (widget.help != null) ...[
          const Gap(8),
          Text(widget.help!, style: tx(13, c: widget.helpColor ?? MP.ink3, h: 1.4)),
        ],
      ],
    );
  }
}

/// Dropdown-looking field (56px, chevron on the right). Opens a picker sheet.
class MpSelect extends StatelessWidget {
  final String? label;
  final String value;
  final List<String> options;
  final ValueChanged<String>? onChanged;
  final String? leadingIcon;
  const MpSelect({super.key, this.label, required this.value, this.options = const [], this.onChanged, this.leadingIcon});

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(height: 56, child: Tap(
      onTap: () async {
        if (options.isEmpty) return;
        final v = await openSheet<String>(
          context,
          (c) => MpSheet(
            title: label,
            child: Column(
              children: [
                for (final o in options)
                  Tap(
                    onTap: () => Navigator.pop(c, o),
                    radius: 12,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.centerLeft,
                      child: Row(children: [
                        Expanded(child: Text(o, style: tx(16, w: o == value ? w600 : w400))),
                        if (o == value) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        );
        if (v != null) onChanged?.call(v);
      },
      radius: 16,
      color: MP.white,
      border: MP.lineStrong,
      // CSS: 1px border + 16px padding-left (text at 17px); chevron 16px from the edge.
      child: Row(children: [
        const Gap(16),
        if (leadingIcon != null) ...[Ico(leadingIcon!, size: 20, color: MP.ink3), const Gap(10)],
        Expanded(child: Text(value, style: tx(16), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const Ico(I.chevronDown, size: 20, color: MP.ink2),
        const Gap(15),
      ]),
    ));
    if (label == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [MpLabel(label!), const Gap(8), box],
    );
  }
}

/// Segmented control: #F1F4F9 track (radius 16, padding 4), white selected
/// segment (radius 12, card shadow).
class MpSegmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int>? onChanged;
  final double height;
  final double fontSize;

  /// Space between segments (CSS `gap`; some designs use 0).
  final double gap;

  /// Shadow of the selected segment (some designs use [MPShadow.hairline]).
  final List<BoxShadow> selectedShadow;
  const MpSegmented({
    super.key,
    required this.options,
    required this.index,
    this.onChanged,
    this.height = 44,
    this.fontSize = 15,
    this.gap = 4,
    this.selectedShadow = MPShadow.card,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0 && gap > 0) SizedBox(width: gap),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged?.call(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Transparent *white* so the fade never passes through grey.
                    color: i == index ? MP.white : MP.white.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == index ? selectedShadow : null,
                  ),
                  child: Text(
                    options[i],
                    style: tx(fontSize, w: i == index ? w600 : w500, c: i == index ? MP.ink : MP.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter chip / pill: 40px, radius 999. Selected = #003399 fill, white text.
class MpChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? dot;
  final String? icon;
  final double height;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  /// Selected style variant: tonal (#EBF1FB bg, #003399 text, blue border).
  final bool tonal;
  const MpChip(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
    this.dot,
    this.icon,
    this.height = 40,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? (tonal ? MP.primarySoft : MP.primary) : MP.white;
    final fg = selected ? (tonal ? MP.primary : MP.white) : MP.ink2;
    final border = selected ? (tonal ? MP.primary : null) : MP.lineStrong;
    return SizedBox(
      height: height,
      child: Tap(
        onTap: onTap ?? () {},
        radius: 999,
        color: bg,
        border: border,
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const Gap(8),
              ],
              if (icon != null) ...[Ico(icon!, size: 16, color: fg, stroke: 2), const Gap(6)],
              Text(label, style: tx(fontSize, w: w600, c: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrolling chip row with the page's 20px gutters.
class MpChipRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final EdgeInsetsGeometry padding;
  const MpChipRow({super.key, required this.children, this.gap = 6, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) Gap(gap), children[i]],
          ],
        ),
      );
}

/// iOS-style switch from the design. Large: 52×32 (knob 28); small: 46×26.
class MpSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool small;

  /// Screen-reader name. Without one the switch joins its row (the row's text
  /// and tap), which is how most settings rows are built.
  final String? label;
  const MpSwitch({super.key, required this.value, this.onChanged, this.small = false, this.label});

  @override
  Widget build(BuildContext context) {
    final w = small ? 46.0 : 52.0, h = small ? 26.0 : 32.0, k = small ? 22.0 : 28.0;
    return Semantics(
      toggled: value,
      label: label,
      onTap: label == null || onChanged == null ? null : () => onChanged!(!value),
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: () => onChanged?.call(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: w,
          height: h,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: value ? MP.primary : MP.lineStrong, borderRadius: BorderRadius.circular(999)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: k,
              height: k,
              decoration: BoxDecoration(color: MP.white, shape: BoxShape.circle, boxShadow: small ? MPShadow.knob : MPShadow.card),
            ),
          ),
        ),
      ),
    );
  }
}

/// 22×22 checkbox, radius 6. Checked: #003399 with a white 3px check.
class MpCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  /// Screen-reader name; without one the box joins its row (see [MpSwitch]).
  final String? label;
  const MpCheck({super.key, required this.value, this.onChanged, this.size = 22, this.label});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: label,
      onTap: label == null || onChanged == null ? null : () => onChanged!(!value),
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: () => onChanged?.call(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: value ? MP.primary : MP.white,
            borderRadius: BorderRadius.circular(6),
            border: value ? null : Border.all(color: MP.lineStrong, width: 1.5),
          ),
          child: value ? Center(child: Ico(I.check, size: size * 0.64, color: MP.white, stroke: 3)) : null,
        ),
      ),
    );
  }
}

/// 22px radio (border-box): 2px #D5DBE5 ring; selected = 2px #003399 ring
/// with a 10px #003399 dot.
class MpRadio extends StatelessWidget {
  final bool value;
  final VoidCallback? onTap;
  final double size;
  const MpRadio({super.key, required this.value, this.onTap, this.size = 22});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          // No fill, as in CSS: a tinted selected card shows through.
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: value ? MP.primary : MP.lineStrong, width: 2),
          ),
          child: value
              ? Center(
                  child: Container(
                    width: size * 10 / 22,
                    height: size * 10 / 22,
                    decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
                  ),
                )
              : null,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small display pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Status pill: 24px, radius 999, 12px/700.
class MpBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double height;
  final double fontSize;
  final FontWeight weight;
  final String? icon;
  final Color? border;
  final Color? dot;
  final double radius;
  final double padX;
  const MpBadge(
    this.text, {
    super.key,
    this.bg = MP.fill,
    this.fg = MP.ink2,
    this.height = 24,
    this.fontSize = 12,
    this.weight = w700,
    this.icon,
    this.border,
    this.dot,
    this.radius = 999,
    this.padX = 10,
  });

  const MpBadge.blue(this.text, {super.key, this.icon, this.dot, this.height = 24, this.fontSize = 12, this.weight = w700, this.radius = 999, this.padX = 10})
      : bg = MP.primarySoft,
        fg = MP.primary,
        border = null;
  const MpBadge.green(this.text, {super.key, this.icon, this.dot, this.height = 24, this.fontSize = 12, this.weight = w700, this.radius = 999, this.padX = 10})
      : bg = MP.greenSoft,
        fg = MP.green,
        border = null;
  const MpBadge.amber(this.text, {super.key, this.icon, this.dot, this.height = 24, this.fontSize = 12, this.weight = w700, this.radius = 999, this.padX = 10})
      : bg = MP.amberSoft,
        fg = MP.amber,
        border = null;
  const MpBadge.red(this.text, {super.key, this.icon, this.dot, this.height = 24, this.fontSize = 12, this.weight = w700, this.radius = 999, this.padX = 10})
      : bg = MP.redSoft,
        fg = MP.red,
        border = null;
  const MpBadge.grey(this.text, {super.key, this.icon, this.dot, this.height = 24, this.fontSize = 12, this.weight = w700, this.radius = 999, this.padX = 10})
      : bg = MP.fill,
        fg = MP.ink2,
        border = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: padX),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const Gap(6),
          ],
          if (icon != null) ...[Ico(icon!, size: fontSize + 2, color: fg, stroke: 2.25), const Gap(4)],
          Text(text, style: tx(fontSize, w: weight, c: fg, h: 1)),
        ],
      ),
    );
  }
}

/// Initials avatar (circle, #EBF1FB / #003399 by default).
class MpAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final Color bg;
  final Color fg;
  final double? fontSize;
  final double? radius;
  final Color? border;
  final FontWeight weight;

  /// Profile photo link; the initials show while it loads or if it fails.
  final String? photo;
  const MpAvatar(
    this.initials, {
    super.key,
    this.photo,
    this.size = 40,
    this.bg = MP.primarySoft,
    this.fg = MP.primary,
    this.fontSize,
    this.radius,
    this.border,
    this.weight = w700,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius ?? size / 2),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      clipBehavior: photo == null ? Clip.none : Clip.antiAlias,
      child: photo == null
          ? Text(initials, style: tx(fontSize ?? (size * 0.35).roundToDouble(), w: weight, c: fg, h: 1))
          : Image.network(
              photo!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Text(initials, style: tx(fontSize ?? (size * 0.35).roundToDouble(), w: weight, c: fg, h: 1)),
            ),
    );
  }
}

/// Rounded-square icon tile (e.g. 48×48 radius 14 #EBF1FB with a blue icon).
class MpIconTile extends StatelessWidget {
  final String icon;
  final double size;
  final double iconSize;
  final double radius;
  final Color bg;
  final Color fg;
  final double stroke;
  final Color? border;
  const MpIconTile(
    this.icon, {
    super.key,
    this.size = 48,
    this.iconSize = 22,
    this.radius = 14,
    this.bg = MP.primarySoft,
    this.fg = MP.primary,
    this.stroke = 1.75,
    this.border,
  });
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Ico(icon, size: iconSize, color: fg, stroke: stroke),
      );
}

/// Uppercase section label: 12px / 600 / .06em / #69738A.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final Color color;
  final double size;
  final FontWeight weight;
  final double? h;
  const SectionLabel(this.text, {super.key, this.trailing, this.color = MP.ink3, this.size = 12, this.weight = w600, this.h});
  @override
  Widget build(BuildContext context) {
    final t = Text(text.toUpperCase(), style: tx(size, w: weight, c: color, em: 0.06, h: h));
    if (trailing == null) return t;
    return Row(children: [Expanded(child: t), trailing!]);
  }
}

/// Section heading (18/700) with an optional trailing link.
class SectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final double size;
  const SectionTitle(this.text, {super.key, this.action, this.onAction, this.size = 18});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(text, style: tx(size, w: w700, h: 1.25))),
          if (action != null) MpLink(action!, onTap: onAction, height: 32),
        ],
      );
}

/// 1px #E5E9F0 divider.
class MpDivider extends StatelessWidget {
  final double indent;
  final Color color;
  const MpDivider({super.key, this.indent = 0, this.color = MP.line});
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: EdgeInsets.only(left: indent),
        color: color,
      );
}

/// Grab handle for sheets: 36×4, #D5DBE5.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: MP.lineStrong, borderRadius: BorderRadius.circular(999)),
        ),
      );
}

/// Bottom sheet surface: white, radius 24 on top, handle, padding 12/20/32.
/// Optional [title]/[subtitle] row with a close button.
class MpSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final bool showClose;
  final EdgeInsetsGeometry padding;
  final bool scroll;
  const MpSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.showClose = false,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 32),
    this.scroll = true,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHandle(),
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: tx(20, w: w700, h: 1.25)),
                      if (subtitle != null) ...[const Gap(4), Text(subtitle!, style: tx(14, c: MP.ink2, h: 1.45))],
                    ],
                  ),
                ),
                if (showClose)
                  // CSS: 44×44 with margin -8px -8px 0 0 → takes 36×36 in layout.
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: OverflowBox(
                      alignment: Alignment.bottomLeft,
                      minWidth: 44,
                      maxWidth: 44,
                      minHeight: 44,
                      maxHeight: 44,
                      child: MpIconButton(I.close, label: 'Close', color: MP.ink2, onTap: () => Navigator.of(context).maybePop()),
                    ),
                  ),
              ],
            ),
          ),
        if (title != null) const Gap(20),
        child,
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.94),
        decoration: const BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: MPShadow.float,
        ),
        child: SafeArea(
          top: false,
          child: scroll
              ? SingleChildScrollView(padding: padding, child: body)
              : Padding(padding: padding, child: body),
        ),
      ),
    );
  }
}

/// Sticky bottom action bar (white, top border) used on form screens.
class MpBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool border;
  const MpBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
    this.color = MP.white,
    this.border = true,
  });
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          border: border ? const Border(top: BorderSide(color: MP.line)) : null,
        ),
        child: SafeArea(top: false, child: Padding(padding: padding, child: child)),
      );
}

/// MedPin logo (36×97 in headers).
class MpLogo extends StatelessWidget {
  final double height;
  const MpLogo({super.key, this.height = 36});
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/medpin_logo.png',
        height: height,
        width: height * 97 / 36,
        fit: BoxFit.contain,
        semanticLabel: 'MedPin — Care Connected',
      );
}

/// Simple progress bar (radius 999).
class MpProgress extends StatelessWidget {
  final double value;
  final double height;
  final Color color;
  final Color track;
  const MpProgress(this.value, {super.key, this.height = 8, this.color = MP.primary, this.track = MP.fill});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1).toDouble(),
              child: Container(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ]),
        ),
      );
}

/// A key/value row inside a card (label left, value right).
class MpKV extends StatelessWidget {
  final String k;
  final String v;
  final Color? vColor;
  final FontWeight vWeight;
  final EdgeInsetsGeometry padding;
  const MpKV(this.k, this.v, {super.key, this.vColor, this.vWeight = w600, this.padding = const EdgeInsets.symmetric(vertical: 10)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(k, style: tx(15, c: MP.ink2))),
            const Gap(12),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: tx(15, w: vWeight, c: vColor ?? MP.ink, tab: true))),
          ],
        ),
      );
}

/// Joins children with a fixed gap (CSS `gap`) along a column.
class VGap extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment cross;
  final EdgeInsetsGeometry padding;
  const VGap({super.key, required this.children, this.gap = 16, this.cross = CrossAxisAlignment.stretch, this.padding = EdgeInsets.zero});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: cross,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
          ],
        ),
      );
}

/// Equal-width grid with fixed gaps (CSS grid repeat(n, 1fr)).
class MpGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  final double gap;
  final double rowGap;
  const MpGrid({super.key, required this.columns, required this.children, this.gap = 8, double? rowGap}) : rowGap = rowGap ?? gap;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: rowGap));
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Centred label for narrow tiles (stat cards): wraps between words, and if
/// one word is still wider than the tile (large phone text, long words) the
/// whole label is drawn a little smaller instead of breaking that word.
class MpTileLabel extends StatelessWidget {
  final String text;
  final TextStyle style;
  const MpTileLabel(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) => _WordFit(
        words: tr(context, text).split(RegExp(r'\s+')),
        style: style,
        scaler: MediaQuery.textScalerOf(context),
        child: Text(text, textAlign: TextAlign.center, style: style),
      );
}

class _WordFit extends SingleChildRenderObjectWidget {
  final List<String> words;
  final TextStyle style;
  final TextScaler scaler;
  const _WordFit({required this.words, required this.style, required this.scaler, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWordFit(words, style, scaler);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    final r = renderObject as _RenderWordFit;
    r.words = words;
    r.style = style;
    r.scaler = scaler;
    r.markNeedsLayout();
  }
}

class _RenderWordFit extends RenderProxyBox {
  _RenderWordFit(this.words, this.style, this.scaler);
  List<String> words;
  TextStyle style;
  TextScaler scaler;
  double _scale = 1;

  double get _widest {
    var w = 0.0;
    for (final word in words) {
      final tp = TextPainter(text: TextSpan(text: word, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      if (tp.width > w) w = tp.width;
      tp.dispose();
    }
    return w;
  }

  /// How much to shrink so the longest word fits [width] (never below 70%).
  double _scaleFor(double width) {
    if (!width.isFinite || width <= 0) return 1;
    final w = _widest;
    return w <= width ? 1 : (width / w).clamp(0.7, 1.0);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final k = _scaleFor(width);
    return (child?.getMinIntrinsicHeight(width / k) ?? 0) * k;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final k = _scaleFor(width);
    return (child?.getMaxIntrinsicHeight(width / k) ?? 0) * k;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final k = _scaleFor(constraints.maxWidth);
    final c = child?.getDryLayout(BoxConstraints(maxWidth: constraints.maxWidth / k)) ?? Size.zero;
    return constraints.constrain(Size(constraints.maxWidth.isFinite ? constraints.maxWidth : c.width * k, c.height * k));
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _scale = _scaleFor(width);
    final c = child!;
    c.layout(BoxConstraints(minWidth: width.isFinite ? width / _scale : 0, maxWidth: width.isFinite ? width / _scale : double.infinity), parentUsesSize: true);
    size = constraints.constrain(Size(width.isFinite ? width : c.size.width * _scale, c.size.height * _scale));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_scale == 1) return context.paintChild(child!, offset);
    context.pushTransform(needsCompositing, offset, Matrix4.diagonal3Values(_scale, _scale, 1), (ctx, o) => ctx.paintChild(child!, o));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.scaleByDouble(_scale, _scale, 1, 1);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintTransform(
        transform: Matrix4.diagonal3Values(_scale, _scale, 1),
        position: position,
        hitTest: (r, p) => child?.hitTest(r, position: p) ?? false,
      );
}

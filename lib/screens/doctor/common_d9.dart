import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/format.dart';
import '../../data/downloads.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D9 (dashboard cards, team, plan & billing, export and
// the daily report). Every public name is prefixed with `D9`.

// ─────────────────────────────────────────────────────────────────────────────
// Page & card scaffolding
// ─────────────────────────────────────────────────────────────────────────────

/// White section card: 1px border, radius 24, padding 20, card shadow, and a
/// column of [children] separated by [gap] (CSS flex `gap`).
class D9Card extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final Color border;
  final double radius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadow;
  const D9Card({
    super.key,
    required this.children,
    this.gap = 0,
    this.border = MP.line,
    this.radius = 24,
    this.padding = const EdgeInsets.all(20),
    this.shadow = MPShadow.card,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: MPDeco.card(radius: radius, border: border, shadow: shadow),
    child: VGap(gap: gap, children: children),
  );
}

/// Card heading: 20px/700 title over a 14px #545E72 subtitle (gap 2), with an
/// optional [trailing] link or pill aligned to the top (CSS flex-start).
class D9Head extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? trailing;

  /// CSS padding-bottom under the heading.
  final double bottom;

  /// Subtitle line-height multiplier (20px → 20/14, or 1.45).
  final double subH;
  final bool subTab;
  const D9Head(
    this.title, {
    super.key,
    this.sub,
    this.trailing,
    this.bottom = 0,
    this.subH = 20 / 14,
    this.subTab = false,
  });

  @override
  Widget build(BuildContext context) {
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: tx(20, w: w700, h: 1.25)),
        if (sub != null) ...[const Gap(2), Text(sub!, style: tx(14, c: MP.ink2, h: subH, tab: subTab))],
      ],
    );
    final Widget body =
        trailing == null
            ? head
            : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: head), const Gap(12), trailing!],
            );
    return bottom == 0 ? body : Padding(padding: EdgeInsets.only(bottom: bottom), child: body);
  }
}

/// Uppercase section label: 12px / 600 / .06em (#69738A by default).
class D9Label extends StatelessWidget {
  final String text;
  final Color color;
  final EdgeInsetsGeometry padding;

  /// Line-height multiplier (16px → 16/12, or 1.35).
  final double h;
  const D9Label(this.text, {super.key, this.color = MP.ink3, this.padding = EdgeInsets.zero, this.h = 16 / 12});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text.toUpperCase(), style: tx(12, w: w600, c: color, em: 0.06, h: h)));
}

/// Inline text link (#003399). Kept at text size so it does not change layout.
class D9Link extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final double size;
  final FontWeight weight;
  final double? h;

  /// CSS padding-top (e.g. 3px for "View all" next to a card title).
  final double top;
  final bool underline;
  const D9Link(
    this.text, {
    super.key,
    this.onTap,
    this.size = 14,
    this.weight = w600,
    this.h = 20 / 14,
    this.top = 0,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Tap(
      onTap: onTap ?? () {},
      radius: 6,
      child: Text(
        text,
        style: tx(size, w: weight, c: MP.primary, h: h, deco: underline ? TextDecoration.underline : null),
      ),
    ),
  );
}

/// List row inside a card: 1px #E5E9F0 top border + vertical padding.
class D9Row extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool border;
  const D9Row({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: border ? const BoxDecoration(border: Border(top: BorderSide(color: MP.line))) : null,
      child: child,
    );
    return onTap == null ? box : Tap(onTap: onTap, radius: 0, child: box);
  }
}

/// "+ N more …" footer link: top border, 14px padding-top, 14/20 600 #003399.
class D9More extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const D9More(this.text, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap ?? () {},
    radius: 0,
    child: Container(
      padding: const EdgeInsets.only(top: 14),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Text(text, style: tx(14, w: w600, c: MP.primary, h: 20 / 14)),
    ),
  );
}

/// Row chevron: 18px, #69738A, stroke 1.75.
class D9Chevron extends StatelessWidget {
  const D9Chevron({super.key});
  @override
  Widget build(BuildContext context) => const Ico(I.chevronRight, size: 18, color: MP.ink3);
}

/// Name (16/22 600) over a 14/20 #545E72 detail line (gap 2). The detail is
/// always single-line with an ellipsis; the name only when [clipTitle].
class D9Lines extends StatelessWidget {
  final String title;
  final String? sub;
  final List<InlineSpan>? subSpans;
  final bool clipTitle;
  const D9Lines(this.title, {super.key, this.sub, this.subSpans, this.clipTitle = true});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: tx(16, w: w600, h: 22 / 16),
        maxLines: clipTitle ? 1 : null,
        overflow: clipTitle ? TextOverflow.ellipsis : null,
      ),
      const Gap(2),
      Text.rich(
        TextSpan(text: sub, children: subSpans, style: tx(14, c: MP.ink2, h: 20 / 14)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

/// Big stat number: 30px / 800 / -0.02em / line-height 1, tabular, with an
/// optional 16px/600 grey suffix (letter-spacing 0). [suffixH] is the
/// line-height the suffix inherits: `line-height: 1` → 1, `30px` → 30/16.
class D9Big extends StatelessWidget {
  final String value;
  final String? suffix;
  final Color color;
  final double suffixH;
  const D9Big(this.value, {super.key, this.suffix, this.color = MP.ink, this.suffixH = 1});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: value,
      style: tx(30, w: w800, h: 1, em: -0.02, tab: true, c: color),
      children: [if (suffix != null) TextSpan(text: suffix, style: tx(16, w: w600, c: MP.ink2, h: suffixH, tab: true))],
    ),
  );
}

/// Soft grey tile (#F7F9FC, radius 12, padding 12/14) used for small stats.
class D9Tile extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const D9Tile({super.key, required this.children, this.gap = 4});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
    child: VGap(gap: gap, cross: CrossAxisAlignment.start, children: children),
  );
}

/// Grey footer note: "**31** patients with …" + a trailing link.
class D9Note extends StatelessWidget {
  final String strong;
  final String text;
  final String action;
  final VoidCallback? onAction;
  const D9Note({super.key, required this.strong, required this.text, required this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: tx(14, c: MP.ink2, h: 20 / 14),
              children: [
                TextSpan(text: strong, style: tx(14, w: w700, c: MP.ink, h: 20 / 14, tab: true)),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
        const Gap(12),
        D9Link(action, onTap: onAction),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Distribution bars & swatches
// ─────────────────────────────────────────────────────────────────────────────

/// One segment of a [D9Bar]: CSS `flex: <flex> 1 0%`, background [color],
/// optional 1px inset [ring], [opacity]; [width] pins a tiny segment to its
/// CSS min-width.
class D9Seg {
  final int flex;
  final Color color;
  final Color? ring;
  final double opacity;
  final double? width;
  const D9Seg(this.flex, this.color, {this.ring, this.opacity = 1, this.width});
}

/// 12px stacked distribution bar, radius 999, 2px gaps between segments.
class D9Bar extends StatelessWidget {
  final List<D9Seg> segs;
  final String? label;
  final double height;
  final double gap;
  const D9Bar(this.segs, {super.key, this.label, this.height = 12, this.gap = 2});

  Widget _cell(D9Seg s) => DecoratedBox(
    decoration: BoxDecoration(
      color: s.opacity == 1 ? s.color : s.color.withValues(alpha: s.opacity),
      border: s.ring == null ? null : Border.all(color: s.ring!),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Live counts can be zero: those segments are left out, and an all-zero
    // bar is an empty grey track.
    final shown = segs.where((s) => s.width != null || s.flex > 0).toList();
    if (shown.isEmpty) shown.add(const D9Seg(1, MP.fill));
    return Semantics(
      label: label,
      image: label != null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                if (shown[i].width != null)
                  SizedBox(width: shown[i].width, child: _cell(shown[i]))
                else
                  Expanded(flex: shown[i].flex, child: _cell(shown[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Legend swatch: 8×8, radius 2, optional 1px inset ring and opacity.
class D9Swatch extends StatelessWidget {
  final Color color;
  final Color? ring;
  final double opacity;
  final double width;
  final double height;
  const D9Swatch(this.color, {super.key, this.ring, this.opacity = 1, this.width = 8, this.height = 8});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: opacity == 1 ? color : color.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(2),
      border: ring == null ? null : Border.all(color: ring!),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Form pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Field label: 14px / 600, line-height 1.45 by default.
class D9FieldLabel extends StatelessWidget {
  final String text;
  final double bottom;
  final double h;
  const D9FieldLabel(this.text, {super.key, this.bottom = 0, this.h = 1.45});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(bottom: bottom), child: Text(text, style: tx(14, w: w600, h: h)));
}

/// Label + 8px + field (CSS column with gap 8).
class D9Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  final double h;
  const D9Labeled(this.label, {super.key, required this.child, this.h = 1.45});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [D9FieldLabel(label, h: h), const Gap(8), child],
  );
}

/// Editable 56px text field (radius 16, 1px #D5DBE5; focus → #003399 border
/// with a 3px #EBF1FB ring). Supports tabular figures and an overlaid
/// [trailing] widget positioned like the design's `position: absolute` tags.
class D9Input extends StatefulWidget {
  final String value;
  final TextEditingController? controller;
  final bool tab;
  final TextInputType? keyboard;

  /// CSS padding-right of the input (room left for [trailing]).
  final double padRight;
  final Widget? trailing;

  /// Distance of [trailing] from the field's outer right edge.
  final double trailingRight;
  const D9Input({
    super.key,
    this.value = '',
    this.controller,
    this.tab = false,
    this.keyboard,
    this.padRight = 16,
    this.trailing,
    this.trailingRight = 16,
  });

  @override
  State<D9Input> createState() => _D9InputState();
}

class _D9InputState extends State<D9Input> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

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
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focused ? MP.primary : MP.lineStrong),
        boxShadow: focused ? MPShadow.focusRing : null,
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, widget.padRight, 0),
            child: TextField(
              controller: _c,
              focusNode: _f,
              keyboardType: widget.keyboard,
              style: tx(16, tab: widget.tab),
              cursorColor: MP.primary,
              decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
            ),
          ),
          if (widget.trailing != null)
            Positioned(
              top: 0,
              bottom: 0,
              // The 1px border already insets the stack.
              right: widget.trailingRight - 1,
              child: IgnorePointer(child: Center(child: widget.trailing)),
            ),
        ],
      ),
    );
  }
}

/// Dropdown-looking 56px button field: optional leading icon, value, optional
/// grey count ("1 of 2") and a 20px chevron.
class D9Field extends StatelessWidget {
  final String value;
  final VoidCallback? onTap;
  final String? leading;
  final Color leadingColor;
  final String? count;
  final Color chevronColor;

  /// Chevron distance from the outer right edge: 17 (1px border + 16px
  /// padding) for a flex `<button>`, 16 for a `<select>`'s absolute chevron.
  final double right;
  const D9Field({
    super.key,
    required this.value,
    this.onTap,
    this.leading,
    this.leadingColor = MP.ink2,
    this.count,
    this.chevronColor = MP.ink2,
    this.right = 16,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Tap(
      onTap: onTap ?? () {},
      radius: 16,
      color: MP.white,
      border: MP.lineStrong,
      child: Padding(
        // Tap already insets its 1px border; this is the CSS padding.
        padding: EdgeInsets.fromLTRB(16, 0, right - 1, 0),
        child: Row(
          children: [
            if (leading != null) ...[Ico(leading!, size: 20, color: leadingColor), const Gap(12)],
            Expanded(child: Text(value, style: tx(16), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (count != null) ...[const Gap(12), Text(count!, style: tx(14, c: MP.ink3, tab: true))],
            const Gap(12),
            Ico(I.chevronDown, size: 20, color: chevronColor),
          ],
        ),
      ),
    ),
  );
}

/// Option picker sheet (same look as MpSelect's). Returns the chosen option.
class D9Picker {
  D9Picker._();

  static Future<String?> show(
    BuildContext context, {
    String? title,
    required List<String> options,
    required String value,
  }) {
    return openSheet<String>(
      context,
      (c) => MpSheet(
        title: title,
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
                  child: Row(
                    children: [
                      Expanded(child: Text(o, style: tx(16, w: o == value ? w600 : w400))),
                      if (o == value) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A working select: [D9Field] that opens [D9Picker] and reports the choice.
class D9Select extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? title;
  final String? leading;
  final Color leadingColor;
  final Color chevronColor;
  final double right;
  const D9Select({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.title,
    this.leading,
    this.leadingColor = MP.ink2,
    this.chevronColor = MP.ink2,
    this.right = 16,
  });

  @override
  Widget build(BuildContext context) => D9Field(
    value: value,
    leading: leading,
    leadingColor: leadingColor,
    chevronColor: chevronColor,
    right: right,
    onTap: () async {
      final v = await D9Picker.show(context, title: title, options: options, value: value);
      if (v != null) onChanged(v);
    },
  );
}

/// 22×22 checkbox, radius 6. Checked: #003399 with a 16px white check
/// (stroke 2.5); unchecked: white with a 1.5px #D5DBE5 border.
class D9Check extends StatelessWidget {
  final bool value;
  const D9Check(this.value, {super.key});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: value ? MP.primary : MP.white,
      borderRadius: BorderRadius.circular(6),
      border: value ? null : Border.all(color: MP.lineStrong, width: 1.5),
    ),
    child: value ? const Ico(I.check, size: 16, color: MP.white, stroke: 2.5) : null,
  );
}

/// Bordered box of the practice's locations, each a 56px checkable row.
class D9Locations extends StatelessWidget {
  static const names = ['City Care Clinic, Salt Lake', 'City Care — New Town'];
  final List<bool> value;
  final ValueChanged<int> onToggle;

  /// The practice's location names (live); the design's two by default.
  final List<String> labels;
  const D9Locations({super.key, required this.value, required this.onToggle, this.labels = names});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: MP.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MP.lineStrong),
    ),
    child: Column(
      children: [
        for (var i = 0; i < labels.length && i < value.length; i++) ...[
          if (i > 0) const MpDivider(),
          Semantics(
            checked: value[i],
            child: Tap(
              onTap: () => onToggle(i),
              radius: 0,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [D9Check(value[i]), const Gap(12), Expanded(child: Text(labels[i], style: tx(16)))],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Team roles (People · add / People · member)
// ─────────────────────────────────────────────────────────────────────────────

/// Team roles and the permissions each role preset grants.
class D9Roles {
  D9Roles._();

  static const all = [
    'Doctor',
    'Front desk',
    "Doctor's assistant",
    'Dietician',
    'Lab manager',
    'Lab technician',
    'Practice manager',
  ];

  // (view patients, edit records, read and reply to chats, prescribe).
  static const _grants = <String, (bool, bool, bool, bool)>{
    'Doctor': (true, true, true, true),
    'Front desk': (true, false, true, false),
    "Doctor's assistant": (true, true, true, false),
    'Dietician': (true, true, true, false),
    'Lab manager': (true, true, false, false),
    'Lab technician': (true, false, false, false),
    'Practice manager': (true, true, true, false),
  };

  /// API role keys, in the same order as [all].
  static const keys = [
    'doctor',
    'front_desk',
    'doctor_assistant',
    'dietician',
    'lab_manager',
    'lab_technician',
    'practice_manager',
  ];

  /// "doctor_assistant" → "Doctor's assistant".
  static String label(String key) {
    final i = keys.indexOf(key);
    return i < 0 ? key : all[i];
  }

  /// "Doctor's assistant" → "doctor_assistant".
  static String key(String label) {
    final i = all.indexOf(label);
    return i < 0 ? label : keys[i];
  }

  static (bool, bool, bool, bool) _g(String role) => _grants[role] ?? (true, false, false, false);

  /// Read-only permission list shown on the member screen.
  static List<(String, bool)> perms(String role) {
    final g = _g(role);
    return [('View patients', g.$1), ('Edit records', g.$2), ('Read and reply to chats', g.$3), ('Prescribe', g.$4)];
  }

  /// One-line summary, e.g. "Doctor: view, edit, prescribe, chat read + reply.
  /// There's no separate permission step."
  static String summary(String role) {
    final g = _g(role);
    final parts = [if (g.$1) 'view', if (g.$2) 'edit', if (g.$4) 'prescribe', if (g.$3) 'chat read + reply'];
    return "$role: ${parts.join(', ')}. There's no separate permission step.";
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Opens a signed file link (invoice, export, report PDF) outside the app.
class D9Open {
  D9Open._();

  /// Replaced in tests.
  static Future<bool> Function(Uri) launcher = (uri) async {
    final ctx = Nav.key.currentContext;
    if (Downloads.isFile('$uri') && ctx != null && ctx.mounted) {
      await Downloads.open(ctx, '$uri');
      return true;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  };

  static Future<bool> url(BuildContext context, Object? url, {String failed = "Couldn't open the file"}) async {
    final uri = url is String && url.isNotEmpty ? Uri.tryParse(url) : null;
    var ok = false;
    if (uri != null) {
      try {
        ok = await launcher(uri);
      } catch (_) {
        ok = false;
      }
    }
    if (!ok && context.mounted) toast(context, failed);
    return ok;
  }
}

/// Formatting shared by the D9 screens.
class D9Fmt {
  D9Fmt._();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// 2499 → "₹2,499"
  static String money(num n) => '₹${F.count(n)}';

  /// "14 Sep 2026"
  static String date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "Mar 2026"
  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  /// "2026-09-14" (the API's day key)
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Parses "14 Sep 2026", "14/09/2026" or "2026-09-14".
  static DateTime? parseDate(String text) {
    final t = text.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (iso != null) return _ymd(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(t);
    if (dmy != null) return _ymd(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
    final named = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})$').firstMatch(t);
    if (named != null) {
      final m = _months.indexWhere((x) => x.toLowerCase() == named[2]!.toLowerCase());
      if (m >= 0) return _ymd(int.parse(named[3]!), m + 1, int.parse(named[1]!));
    }
    return null;
  }

  static DateTime? _ymd(int y, int m, int d) {
    final v = DateTime(y, m, d);
    return v.year == y && v.month == m && v.day == d ? v : null;
  }

  /// "9831120486" → "+91 98311 20486"
  static String phone(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    final local = d.length > 10 ? d.substring(d.length - 10) : d;
    return local.length == 10 ? '+91 ${local.substring(0, 5)} ${local.substring(5)}' : digits;
  }

  /// "male" → "M"
  static String gender(Object? g) => switch ('$g') {
    'male' => 'M',
    'female' => 'F',
    'other' => 'O',
    _ => '',
  };

  /// "1 visit" / "3 visits"
  static String plural(num n, String one, [String? many]) => '${F.count(n)} ${n == 1 ? one : (many ?? '${one}s')}';
}

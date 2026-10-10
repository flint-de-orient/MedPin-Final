import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D4: the doctor's "My profile" hub and its editors
// (Profile-Professional, Profile-Location, Profile-Schedule).
//
// CSS note: the design's <a>/<span>/<div> boxes are content-box (a 1px border
// adds to their size) while <button>s are border-box. Sizes below follow that.

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

/// White 64px top bar with a 1px #E5E9F0 bottom border: back button, 20/700
/// title, optional 13px #545E72 subtitle (1px apart) and a tonal "Save".
class D4Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSave;
  const D4Header(this.title, {super.key, this.subtitle, this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      // height 64 + border-bottom 1 (content-box)
      height: 65,
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(20, w: w700, h: 1.25), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: tx(13, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (onSave != null) ...[
            const SizedBox(width: 4),
            MpButton(
              'Save',
              onTap: onSave,
              kind: MpBtn.tonal,
              height: 40,
              radius: 12,
              fontSize: 15,
              expand: false,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ],
        ],
      ),
    );
  }
}

/// Header "Save": confirm, then return to the screen underneath.
void d4Save(BuildContext context, [String message = 'Saved']) {
  toast(context, message);
  Nav.back(context);
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards and text
// ─────────────────────────────────────────────────────────────────────────────

/// Section card (white, 1px #E5E9F0 border, radius 24, padding 20, card
/// shadow) whose children are stacked with a CSS-style [gap].
class D4Card extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const D4Card({super.key, required this.children, this.gap = 14});

  @override
  Widget build(BuildContext context) => MpCard(child: VGap(gap: gap, children: children));
}

/// Card heading (17/700) with an optional trailing 14/600 link, baseline-aligned.
class D4CardTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const D4CardTitle(this.text, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Expanded(child: Text(text, style: tx(17, w: w700))),
      if (action != null) ...[const SizedBox(width: 8), D4TextLink(action!, onTap: onAction)],
    ],
  );
}

/// Helper copy: 13px / 1.45, #545E72.
class D4Note extends StatelessWidget {
  final String text;
  const D4Note(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(text, style: tx(13, c: MP.ink2, h: 1.45));
}

/// A 15px title over a 13px #545E72 line, 2px apart.
class D4TitleSub extends StatelessWidget {
  final String title;
  final String? sub;
  final FontWeight weight;
  const D4TitleSub(this.title, this.sub, {super.key, this.weight = w600});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: tx(15, w: weight)),
      if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: tx(13, c: MP.ink2))],
    ],
  );
}

/// Inline text link: 14/600, #003399 by default, no padding.
class D4TextLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  const D4TextLink(this.label, {super.key, this.onTap, this.color = MP.primary});

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap ?? () {},
    radius: 6,
    child: Text(label, maxLines: 1, softWrap: false, style: tx(14, w: w600, c: color)),
  );
}

/// 22px status pill: padding 0 8, radius 999, 12/700.
class D4Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const D4Pill(this.text, {super.key, this.bg = MP.fill, this.fg = MP.ink2});
  const D4Pill.green(this.text, {super.key}) : bg = MP.greenSoft, fg = MP.green;
  const D4Pill.amber(this.text, {super.key}) : bg = MP.amberSoft, fg = MP.amber;
  const D4Pill.blue(this.text, {super.key}) : bg = MP.primarySoft, fg = MP.primary;

  @override
  Widget build(BuildContext context) => Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Center(widthFactor: 1, child: Text(text, maxLines: 1, softWrap: false, style: tx(12, w: w700, c: fg, h: 1))),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Form fields
// ─────────────────────────────────────────────────────────────────────────────

/// Field label (13/600 #545E72) above its control, 6px apart.
class D4Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const D4Labeled({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [Text(label, style: tx(13, w: w600, c: MP.ink2)), const SizedBox(height: 6), child],
  );
}

/// The field box: min-height 48 (border-box), padding 12/14, 1px #D5DBE5
/// border, radius 16. Focus: #003399 border + 3px #EBF1FB ring.
class D4FieldBox extends StatelessWidget {
  final Widget child;
  final Widget? trailing;
  final bool focused;
  const D4FieldBox({super.key, required this.child, this.trailing, this.focused = false});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: MP.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: focused ? MP.primary : MP.lineStrong),
      boxShadow: focused ? MPShadow.focusRing : null,
    ),
    child: Row(
      children: [
        Expanded(child: child),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

/// Editable labelled field (15px / 1.4 text, wraps like the design's span).
class D4Field extends StatefulWidget {
  final String label;
  final String value;
  final Widget? trailing;
  final TextInputType keyboard;

  /// Called with the text as it is edited (live screens collect it to save).
  final ValueChanged<String>? onChanged;
  const D4Field(this.label, this.value, {super.key, this.trailing, this.keyboard = TextInputType.text, this.onChanged});

  @override
  State<D4Field> createState() => _D4FieldState();
}

class _D4FieldState extends State<D4Field> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
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
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return D4Labeled(
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _f.requestFocus,
        child: D4FieldBox(
          focused: _f.hasFocus,
          trailing: widget.trailing,
          child: TextField(
            controller: _c,
            focusNode: _f,
            keyboardType: widget.keyboard,
            textInputAction: TextInputAction.done,
            onChanged: widget.onChanged,
            maxLines: null,
            style: tx(15, h: 1.4),
            cursorColor: MP.primary,
            decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
          ),
        ),
      ),
    );
  }
}

/// Labelled select field (value + 16px chevron); opens a picker sheet.
class D4SelectField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const D4SelectField(this.label, this.value, {super.key, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => D4Labeled(
    label: label,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Tap(
        onTap: () async {
          final v = await d4PickOne(context, title: label, options: options, value: value);
          if (v != null) onChanged(v);
        },
        radius: 16,
        color: MP.white,
        border: MP.lineStrong,
        // padding 12/14; Tap adds the 1px border outside it (content-box)
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(value, style: tx(15, h: 1.4))),
            const SizedBox(width: 8),
            const Ico(I.chevronDown, size: 16, color: MP.ink3, stroke: 2),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tags and buttons
// ─────────────────────────────────────────────────────────────────────────────

/// Removable tag: 34px, padding 0 8 0 12, #EBF1FB / #003399, 14/600, with a
/// 22px × button.
class D4Tag extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  const D4Tag(this.label, {super.key, this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
    decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: w600, c: MP.primary)),
        ),
        const SizedBox(width: 4),
        MpIconButton(
          I.close,
          label: 'Remove $label',
          onTap: onRemove,
          size: 22,
          iconSize: 12,
          radius: 999,
          color: MP.primary,
          stroke: 2.5,
        ),
      ],
    ),
  );
}

/// Wrap (gap 8) of removable tags plus a dashed "+ Add" chip that opens a
/// one-field sheet.
class D4TagEditor extends StatefulWidget {
  final List<String> initial;
  final String addTitle;
  final String addLabel;
  final String? addHint;

  /// Called with the full list after each add or remove.
  final ValueChanged<List<String>>? onChanged;
  const D4TagEditor({
    super.key,
    required this.initial,
    required this.addTitle,
    required this.addLabel,
    this.addHint,
    this.onChanged,
  });

  @override
  State<D4TagEditor> createState() => _D4TagEditorState();
}

class _D4TagEditorState extends State<D4TagEditor> {
  late final List<String> _tags = [...widget.initial];

  Future<void> _add() async {
    final r = await d4FormSheet(
      context,
      title: widget.addTitle,
      fields: [D4FormField(widget.addLabel, hint: widget.addHint)],
      confirm: 'Add',
    );
    final v = (r == null || r.isEmpty) ? '' : r.first;
    if (!mounted || v.isEmpty || _tags.contains(v)) return;
    setState(() => _tags.add(v));
    widget.onChanged?.call([..._tags]);
  }

  void _remove(String t) {
    setState(() => _tags.remove(t));
    widget.onChanged?.call([..._tags]);
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final t in _tags) D4Tag(t, onRemove: () => _remove(t)),
      D4DashedButton('+ Add', onTap: _add),
    ],
  );
}

/// White button with a 1px dashed #D5DBE5 border and #003399 600 label
/// ("+ Add" chips: 34px pill; "+ Add qualification": 44px, radius 12, full width).
class D4DashedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final double radius;
  final double fontSize;
  final bool expand;
  const D4DashedButton(
    this.label, {
    super.key,
    this.onTap,
    this.height = 34,
    this.radius = 999,
    this.fontSize = 14,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = math.min(radius, height / 2);
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: CustomPaint(
        foregroundPainter: _DashedRRect(color: MP.lineStrong, radius: r),
        child: Tap(
          onTap: onTap ?? () {},
          radius: r,
          color: MP.white,
          // padding 0 12 + the 1px border
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Center(
            widthFactor: expand ? null : 1,
            child: Text(label, maxLines: 1, softWrap: false, style: tx(fontSize, w: w600, c: MP.primary)),
          ),
        ),
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRect({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - 0.5))));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color || old.radius != radius;
}

/// 52px full-width white button with a 1px border and a #B91C1C 15/600 label
/// ("Log out", "Stop practising here").
class D4OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color border;
  const D4OutlineButton(this.label, {super.key, this.onTap, this.border = MP.lineStrong});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    width: double.infinity,
    child: Tap(
      onTap: onTap ?? () {},
      radius: 16,
      color: MP.white,
      border: border,
      child: Center(child: Text(label, style: tx(15, w: w600, c: MP.red))),
    ),
  );
}

/// Selectable option card (aria-pressed button): radius 16; selected =
/// 1.5px #003399 border on #EBF1FB, otherwise 1px #D5DBE5 on white.
/// Title 700 #111827 over a 12px #545E72 line, 2px apart.
class D4OptionCard extends StatelessWidget {
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback? onTap;

  /// The CSS padding (the border is added on top of it).
  final EdgeInsets padding;
  final double titleSize;
  final bool nowrap;
  const D4OptionCard({
    super.key,
    required this.title,
    required this.sub,
    required this.selected,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.titleSize = 15,
    this.nowrap = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Tap(
      onTap: onTap,
      radius: 16,
      color: selected ? MP.primarySoft : MP.white,
      border: selected ? MP.primary : MP.lineStrong,
      borderWidth: selected ? 1.5 : 1,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: nowrap ? 1 : null, softWrap: !nowrap, style: tx(titleSize, w: w700)),
          const SizedBox(height: 2),
          Text(sub, maxLines: nowrap ? 1 : null, softWrap: !nowrap, style: tx(12, c: MP.ink2)),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Setting rows: switch and stepper
// ─────────────────────────────────────────────────────────────────────────────

/// Switch row (a `label` in the design): title/sub on the left, small 46×26
/// switch on the right. Tapping anywhere on the row toggles it.
class D4SwitchRow extends StatelessWidget {
  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const D4SwitchRow({super.key, required this.title, required this.sub, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        Expanded(child: D4TitleSub(title, sub)),
        const SizedBox(width: 12),
        MpSwitch(value: value, small: true, onChanged: onChanged),
      ],
    ),
  );
}

/// − value + stepper: 1px #D5DBE5 border, radius 12; 36×40 white buttons with
/// an 18/700 #003399 glyph; value 14/700 tabular, min-width 56.
class D4Stepper extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const D4Stepper({super.key, required this.value, required this.label, this.onMinus, this.onPlus});

  Widget _button(String glyph, String name, VoidCallback? onTap) => Semantics(
    button: true,
    label: name,
    child: Tap(
      onTap: onTap ?? () {},
      radius: 0,
      color: MP.white,
      child: SizedBox(width: 36, height: 40, child: Center(child: Text(glyph, style: tx(18, w: w700, c: MP.primary)))),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: MP.lineStrong)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button('−', 'Less', onMinus),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 56),
                child: Text(value, textAlign: TextAlign.center, style: tx(14, w: w700, tab: true)),
              ),
              _button('+', 'More', onPlus),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Title/sub on the left, [D4Stepper] on the right (gap 12).
class D4StepperRow extends StatelessWidget {
  final String title;
  final String sub;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const D4StepperRow({
    super.key,
    required this.title,
    required this.sub,
    required this.value,
    this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: D4TitleSub(title, sub)),
      const SizedBox(width: 12),
      D4Stepper(value: value, label: title, onMinus: onMinus, onPlus: onPlus),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ABDM registry card
// ─────────────────────────────────────────────────────────────────────────────

/// ABDM registry card (kicker "ABDM", registry name) with a Not linked /
/// Linked pill, a tonal "Link [idName]" button and a "New? Register" link.
class D4AbdmCard extends StatefulWidget {
  final String title;
  final String body;
  final String idName;
  final String hint;

  /// The linked ID (live data); null or empty = not linked.
  final String? linkedId;

  /// Saves the entered ID; resolves true when it was linked. Without it the
  /// card only marks itself linked (design preview).
  final Future<bool> Function(String id)? onLink;

  /// The ABDM site where a new ID is made ("New? Register").
  final String? registerUrl;

  /// What a valid ID looks like (checked before saving).
  final RegExp? pattern;
  const D4AbdmCard({
    super.key,
    required this.title,
    required this.body,
    required this.idName,
    required this.hint,
    this.linkedId,
    this.onLink,
    this.registerUrl,
    this.pattern,
  });

  @override
  State<D4AbdmCard> createState() => _D4AbdmCardState();
}

class _D4AbdmCardState extends State<D4AbdmCard> {
  late bool _linked = (widget.linkedId ?? '').isNotEmpty;

  @override
  void didUpdateWidget(D4AbdmCard old) {
    super.didUpdateWidget(old);
    if (old.linkedId != widget.linkedId) _linked = (widget.linkedId ?? '').isNotEmpty;
  }

  Future<void> _link() async {
    final r = await d4FormSheet(
      context,
      title: 'Link ${widget.idName}',
      fields: [D4FormField(widget.idName, value: widget.linkedId ?? '', hint: widget.hint)],
      confirm: 'Link',
    );
    if (!mounted || r == null || r.isEmpty || r.first.isEmpty) return;
    final id = r.first.trim();
    if (widget.pattern != null && !widget.pattern!.hasMatch(id)) {
      toast(context, "That doesn't look like an ${widget.idName} (${widget.hint})");
      return;
    }
    final save = widget.onLink;
    if (save != null && !await save(id)) return;
    if (!mounted) return;
    setState(() => _linked = true);
    toast(context, '${widget.idName} linked');
  }

  @override
  Widget build(BuildContext context) => D4Card(
    gap: 12,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ABDM', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                const SizedBox(height: 2),
                Text(widget.title, style: tx(17, w: w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _linked ? const D4Pill.green('Linked') : const D4Pill('Not linked'),
        ],
      ),
      D4Note(widget.body),
      Row(
        children: [
          MpButton(
            'Link ${widget.idName}',
            onTap: _link,
            kind: MpBtn.tonal,
            height: 44,
            radius: 12,
            fontSize: 15,
            expand: false,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: D4TextLink('New? Register', onTap: () async {
              final url = widget.registerUrl;
              if (url == null) return toast(context, 'Opening ABDM registration');
              final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
              if (!ok && context.mounted) toast(context, "Couldn't open $url");
            }),
          ),
        ],
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small sheets (pickers and quick forms behind the design's links)
// ─────────────────────────────────────────────────────────────────────────────

/// One field of [d4FormSheet].
class D4FormField {
  final String label;
  final String value;
  final String? hint;
  final TextInputType? keyboard;
  const D4FormField(this.label, {this.value = '', this.hint, this.keyboard});
}

/// Opens a short form sheet. Resolves with the trimmed field values, with an
/// empty list when [removeLabel] was tapped, or null when dismissed.
Future<List<String>?> d4FormSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<D4FormField> fields,
  String confirm = 'Save',
  String? removeLabel,
}) {
  return openSheet<List<String>>(
    context,
    (_) => _D4FormSheet(title: title, subtitle: subtitle, fields: fields, confirm: confirm, removeLabel: removeLabel),
  );
}

class _D4FormSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<D4FormField> fields;
  final String confirm;
  final String? removeLabel;
  const _D4FormSheet({
    required this.title,
    this.subtitle,
    required this.fields,
    required this.confirm,
    this.removeLabel,
  });

  @override
  State<_D4FormSheet> createState() => _D4FormSheetState();
}

class _D4FormSheetState extends State<_D4FormSheet> {
  late final List<TextEditingController> _c = [for (final f in widget.fields) TextEditingController(text: f.value)];

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      showClose: true,
      child: VGap(
        gap: 16,
        children: [
          for (var i = 0; i < widget.fields.length; i++)
            MpInput(
              label: widget.fields[i].label,
              hint: widget.fields[i].hint,
              keyboard: widget.fields[i].keyboard,
              controller: _c[i],
              autofocus: i == 0,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MpButton(widget.confirm, onTap: () => Navigator.pop(context, [for (final c in _c) c.text.trim()])),
          ),
          if (widget.removeLabel != null)
            MpButton(
              widget.removeLabel!,
              kind: MpBtn.dangerSoft,
              height: 48,
              onTap: () => Navigator.pop(context, const <String>[]),
            ),
        ],
      ),
    );
  }
}

/// Single-choice picker sheet (same look as `MpSelect`'s list).
Future<String?> d4PickOne(BuildContext context, {required String title, required List<String> options, String? value}) {
  return openSheet<String>(
    context,
    (c) => MpSheet(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options)
            Tap(
              onTap: () => Navigator.pop(c, o),
              radius: 12,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 4),
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

/// Destructive confirmation sheet. Resolves true when confirmed.
Future<bool> d4Confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) async {
  final ok = await openSheet<bool>(
    context,
    (c) => MpSheet(
      title: title,
      subtitle: body,
      child: VGap(
        gap: 8,
        children: [
          MpButton(confirm, kind: MpBtn.danger, onTap: () => Navigator.pop(c, true)),
          MpButton('Cancel', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, false)),
        ],
      ),
    ),
  );
  return ok ?? false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Live-data helpers
// ─────────────────────────────────────────────────────────────────────────────

/// "1 location", "3 locations".
String d4Plural(num n, String one, [String? many]) => '${n.round()} ${n == 1 ? one : (many ?? '${one}s')}';

/// Leave/closure dates: "19 Oct", "19 – 23 Oct", "30 Oct – 2 Nov".
String d4DateRange(DateTime start, DateTime end) {
  if (F.sameDay(start, end) || end.isBefore(start)) return F.dayMonth(start);
  if (start.year == end.year && start.month == end.month) return '${start.day} – ${F.dayMonth(end)}';
  return '${F.dayMonth(start)} – ${F.dayMonth(end)}';
}

/// `Api.I.get` for a part of a screen that may fail on its own (e.g. a
/// member without access to billing): resolves null instead of throwing.
Future<Object?> d4Optional(String path, {Map<String, Object?>? query}) =>
    Api.I.get(path, query: query).then<Object?>((v) => v, onError: (Object _) => null);

/// A location's display name ("City Care Clinic — Salt Lake" → "City Care Clinic · Salt Lake").
String d4LocationName(Map<String, dynamic> loc) => loc.str('name', loc.str('shortName')).replaceAll(' — ', ' · ');

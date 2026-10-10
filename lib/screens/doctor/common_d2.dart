import 'package:flutter/material.dart' hide Text;

import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D2: the doctor's Patients, Messages and History
// tabs and their search / sheet screens.

/// White tab header: 28px title + 14px subtitle, optional trailing [action],
/// optional [search] row and a [chips] row that scrolls edge to edge.
/// CSS: background #FFF · border-bottom 1px #E5E9F0 · padding 16 20 14 · gap 14.
class D2TabHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? search;
  final List<Widget> chips;
  const D2TabHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.search,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 14),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tx(28, w: w800, h: 1.15, em: -0.02),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(2),
                      Text(subtitle, style: tx(14, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (action != null) ...[const Gap(12), action!],
              ],
            ),
          ),
          if (search != null) ...[
            const Gap(14),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: search),
          ],
          if (chips.isNotEmpty) ...[const Gap(14), MpChipRow(gap: 8, children: chips)],
        ],
      ),
    );
  }
}

/// 36px pill (filter tab / recent search). Selected: #003399 fill, white text;
/// otherwise white, 1px #D5DBE5 border, #111827 text. Optional [count] is
/// drawn at weight 500 / 75% opacity, 6px after the label.
class D2Chip extends StatelessWidget {
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback? onTap;
  final FontWeight weight;
  const D2Chip(this.label, {super.key, this.count, this.selected = false, this.onTap, this.weight = w600});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? MP.white : MP.ink;
    return Semantics(
      button: true,
      selected: selected,
      // <button>: border-box, 36px including the 1px border.
      child: SizedBox(
        height: 36,
        child: Tap(
          onTap: onTap ?? () {},
          radius: 999,
          color: selected ? MP.primary : MP.white,
          border: selected ? MP.primary : MP.lineStrong,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: tx(14, w: weight, c: fg)),
              if (count != null) ...[
                const Gap(6),
                Text(count!, style: tx(14, w: w500, c: fg.withValues(alpha: 0.75), tab: true)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + label button: tonal (#EBF1FB / #003399) or outlined (white,
/// 1px #D5DBE5, #111827). Default: 44px, radius 12, padding 0 14 0 12, gap 6.
class D2PillButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool outlined;
  final double height;
  final double radius;
  final double fontSize;
  final double iconSize;
  final double stroke;
  final EdgeInsets padding;
  const D2PillButton(
    this.label, {
    super.key,
    required this.icon,
    this.onTap,
    this.outlined = false,
    this.height = 44,
    this.radius = 12,
    this.fontSize = 14,
    this.iconSize = 18,
    this.stroke = 2,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 14, 0),
  });

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? MP.ink : MP.primary;
    return SizedBox(
      height: height,
      child: Tap(
        onTap: onTap ?? () {},
        radius: radius,
        color: outlined ? MP.white : MP.primarySoft,
        border: outlined ? MP.lineStrong : null,
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Ico(icon, size: iconSize, color: fg, stroke: stroke),
              const Gap(6),
              Text(label, style: tx(fontSize, w: w600, c: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search box: radius 16, 1px #D5DBE5 border (1.5px #003399 when focused or
/// [active]), #69738A magnifier, 15px text. With [onTap] it is a button that
/// opens a search screen instead of an editable field.
class D2SearchField extends StatefulWidget {
  final String hint;
  final double height;
  final double padH;
  final double iconSize;
  final Color? color;
  final bool active;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  const D2SearchField({
    super.key,
    required this.hint,
    this.height = 52,
    this.padH = 16,
    this.iconSize = 20,
    this.color = MP.white,
    this.active = false,
    this.onTap,
    this.onChanged,
  });

  @override
  State<D2SearchField> createState() => _D2SearchFieldState();
}

class _D2SearchFieldState extends State<D2SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.active || _focus.hasFocus;
    final hintStyle = tx(15, c: MP.ink3);
    final box = Container(
      height: widget.height,
      padding: EdgeInsets.symmetric(horizontal: widget.padH),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? MP.primary : MP.lineStrong, width: on ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Ico(I.search, size: widget.iconSize, color: MP.ink3),
          const Gap(10),
          Expanded(
            child:
                widget.onTap != null
                    ? Text(widget.hint, style: hintStyle, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : TextField(
                      focusNode: _focus,
                      onChanged: widget.onChanged,
                      style: tx(15),
                      cursorColor: MP.primary,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: hintStyle,
                      ),
                    ),
          ),
        ],
      ),
    );
    if (widget.onTap == null) return box;
    return Semantics(
      button: true,
      label: widget.hint,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: box),
    );
  }
}

/// "View" (outlined) + "Consult" (tonal) pair, 8px apart, 15/600, radius 12.
/// The View link is `height: 44px` plus a 1px border on a content-box element,
/// so it renders 46px tall next to the 44px Consult link (top-aligned).
class D2ViewConsult extends StatelessWidget {
  final VoidCallback onView;
  final VoidCallback onConsult;
  const D2ViewConsult({super.key, required this.onView, required this.onConsult});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: MpButton('View', kind: MpBtn.secondary, height: 46, radius: 12, fontSize: 15, onTap: onView)),
        const Gap(8),
        Expanded(child: MpButton('Consult', kind: MpBtn.tonal, height: 44, radius: 12, fontSize: 15, onTap: onConsult)),
      ],
    );
  }
}

/// Uppercase list caption used across the batch: 13px / 700 / .06em / #69738A.
class D2Caps extends StatelessWidget {
  final String text;
  const D2Caps(this.text, {super.key});
  @override
  Widget build(BuildContext context) => SectionLabel(text, size: 13, weight: w700);
}

/// Closes the current sheet, then opens [stem] from the screen underneath.
void d2CloseThenGo(BuildContext context, String stem, {Object? args}) {
  final nav = Navigator.of(context);
  nav.pop();
  Nav.go(nav.context, stem, args: args);
}

// ── Live helpers ──

/// "9876543210" → "98765 43210"
String d2Phone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  final ten = d.length == 12 && d.startsWith('91') ? d.substring(2) : d;
  return ten.length == 10 ? '${ten.substring(0, 5)} ${ten.substring(5)}' : phone;
}

/// "F" / "M" / "" from the API gender.
String d2Sex(Object? g) => switch (g) { 'female' => 'F', 'male' => 'M', 'other' => 'O', _ => '' };

/// "29 F" from a patient row.
String d2AgeSex(Map p) => [if (p['age'] is num) '${p['age']}', d2Sex(p['gender'])].where((s) => s.isNotEmpty).join(' ');

/// "29 F · +91 98765 43210"
String d2PatientMeta(Map p) {
  final phone = '${p['phone'] ?? ''}';
  return [d2AgeSex(p), if (phone.isNotEmpty) '+91 ${d2Phone(phone)}'].where((s) => s.isNotEmpty).join(' · ');
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "02 Sep"
String d2DayMonth(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';

/// Last visit: "Today", "Yesterday", "24 Sep", or "New" when never seen.
String d2LastSeen(Object? iso) {
  final d = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
  if (d == null) return 'New';
  final n = DateTime.now();
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, n)) return 'Today';
  if (same(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return d2DayMonth(d);
}

/// Chat-list time: "9:40 AM", "Yesterday", "29 Sep".
String d2ChatTime(Object? iso) {
  final d = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
  if (d == null) return '';
  final n = DateTime.now();
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, n)) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  if (same(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${d.day} ${_months[d.month - 1]}';
}

/// Staff role label: "Front desk", "Dietician", "Doctor assistant".
String d2Role(Object? role) {
  final s = '${role ?? ''}'.replaceAll('_', ' ');
  return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}

/// Option picker sheet (same look as the MpSelect picker). Returns the choice.
Future<String?> d2PickOption(
  BuildContext context, {
  required String title,
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

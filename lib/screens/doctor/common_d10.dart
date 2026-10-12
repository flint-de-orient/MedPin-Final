import 'package:flutter/material.dart' hide Text;

import '../../data/config.dart';
import '../../data/nav_counts.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D10 (AI assistant & feedback, front desk).

/// Uppercase caption: 12px / 600 / .06em / #69738A with an explicit CSS
/// line height in px ([lineHeight]).
class D10Caps extends StatelessWidget {
  final String text;
  final double lineHeight;
  final TextAlign? align;
  final Color color;
  const D10Caps(this.text, {super.key, this.lineHeight = 16, this.align, this.color = MP.ink3});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), textAlign: align, style: tx(12, w: w600, c: color, em: 0.06, h: lineHeight / 12));
}

/// Filter pill: 40px, radius 999, 14/600, 0 16px padding. Selected: #003399
/// fill, white text, no border. Otherwise white with a 1px #D5DBE5 border
/// (which adds 2px of width, as in CSS; MpChip/Tap account for it).
class D10FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const D10FilterChip(this.label, {super.key, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: MpChip(
      label,
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}

/// Search box: 56px, radius 16, 1px #D5DBE5, white; a 20px #69738A search
/// icon 16px from the left edge and the text at the design's [padLeft]
/// (CSS padding-left). Focus: #003399 border + 3px #EBF1FB ring.
class D10SearchField extends StatefulWidget {
  final String hint;
  final double padLeft;
  final ValueChanged<String>? onChanged;
  const D10SearchField({super.key, required this.hint, this.padLeft = 46, this.onChanged});

  @override
  State<D10SearchField> createState() => _D10SearchFieldState();
}

class _D10SearchFieldState extends State<D10SearchField> {
  final _focus = FocusNode();
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return GestureDetector(
      // The field inside is what screen readers focus.
      excludeFromSemantics: true,
      onTap: _focus.requestFocus,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? MP.primary : MP.lineStrong),
          boxShadow: focused ? MPShadow.focusRing : null,
        ),
        child: Row(
          children: [
            // 1px border + 15 = icon at 16px from the outer edge.
            const SizedBox(width: 15),
            const Ico(I.search, size: 20, color: MP.ink3),
            // Text starts at 1px border + padLeft from the outer edge.
            SizedBox(width: widget.padLeft - 35),
            Expanded(
              child: MpFieldArea(child: TextField(
                textAlignVertical: TextAlignVertical.center,
                controller: _c,
                focusNode: _focus,
                onChanged: widget.onChanged,
                textInputAction: TextInputAction.search,
                style: tx(16),
                cursorColor: MP.primary,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: tx(16, c: MP.ink3),
                ),
              )),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// Option picker sheet (same look as `MpSelect`'s). Resolves to the chosen
/// option, or null when dismissed.
class D10Picker {
  D10Picker._();

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
          mainAxisSize: MainAxisSize.min,
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

/// `<select>` from the design: 56px, radius 16, 1px #D5DBE5, white, 16px
/// text (padding 0 40px 0 16px) and a 20px #69738A chevron 14px from the
/// right edge. Opens [D10Picker].
class D10Select extends StatelessWidget {
  final String value;
  final List<String> options;
  final String? title;
  final ValueChanged<String>? onChanged;
  const D10Select({super.key, required this.value, required this.options, this.title, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      value: value,
      // 56px outer (border-box <select>); Tap insets the row by the 1px border.
      child: SizedBox(
        height: 56,
        child: Tap(
          onTap: () async {
            final v = await D10Picker.show(context, title: title, options: options, value: value);
            if (v != null) onChanged?.call(v);
          },
          radius: 16,
          color: MP.white,
          border: MP.lineStrong,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(child: Text(value, style: tx(16), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 7),
              const Ico(I.chevronDown, size: 20, color: MP.ink3),
              const SizedBox(width: 13),
            ],
          ),
        ),
      ),
    );
  }
}

/// Front-desk top bar (scrolls with the page): logo, 44px bell with a dot
/// (8px colour + 2px #F7F9FC ring) and an optional 40px "TG" profile avatar.
///
/// Live, the bell follows [NavCounts.bell]: a red dot when an unread
/// notification is an emergency, blue for other unread ones, none when all
/// are read. [bellLabel] and [dot] are the design's sample (preview).
class D10StaffHeader extends StatelessWidget {
  final String bellLabel;
  final Color dot;
  final bool showAvatar;
  const D10StaffHeader({super.key, required this.bellLabel, this.dot = MP.primary, this.showAvatar = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          const MpLogo(),
          const Spacer(),
          if (AppMode.preview)
            _bell(context, bellLabel, dot)
          else
            ValueListenableBuilder(
              valueListenable: NavCounts.watchBell(),
              builder: (context, b, _) => _bell(
                context,
                b.unread == 0
                    ? 'Notifications'
                    : b.urgent > 0
                        ? 'Notifications, ${b.unread} new, ${b.urgent} urgent'
                        : 'Notifications, ${b.unread} new',
                b.unread == 0 ? null : (b.urgent > 0 ? MP.red : MP.primary),
              ),
            ),
          if (showAvatar) ...[
            const Gap(4),
            MpHitSlop(child: Semantics(
              button: true,
              label: 'Profile',
              child: Tap(
                onTap: () => Nav.tab(context, 'Staff-Profile'),
                radius: 999,
                child: const MpAvatar('TG', size: 40, fontSize: 15),
              ),
            )),
          ],
        ],
      ),
    );
  }

  static Widget _bell(BuildContext context, String label, Color? dot) => Stack(
    clipBehavior: Clip.none,
    children: [
      MpIconButton(
        I.bell,
        label: label,
        onTap: () async {
          await Nav.go(context, 'Notifications');
          NavCounts.refresh(force: true); // back from the list: read ones are gone
        },
      ),
      if (dot != null)
        Positioned(
          top: 10,
          right: 11,
          child: IgnorePointer(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: MP.bg, width: 2)),
            ),
          ),
        ),
    ],
  );
}

/// White list card (radius 24, 1px #E5E9F0 border, card shadow, 4px top and
/// bottom padding). Rows bleed to the card edges so the press ripple fills
/// the card width; each [D10ListRow] keeps the 20px side gutter itself.
class D10ListCard extends StatelessWidget {
  final List<Widget> children;
  const D10ListCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: MPDeco.card(),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// A row inside [D10ListCard]: 20px side gutter, optional 1px #E5E9F0 top
/// divider (inset by the gutter, as in the design) and [vPad] top/bottom.
class D10ListRow extends StatelessWidget {
  final Widget child;
  final bool divider;
  final double vPad;
  final VoidCallback? onTap;
  const D10ListRow({super.key, required this.child, this.divider = false, this.vPad = 16, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad),
        decoration: divider ? const BoxDecoration(border: Border(top: BorderSide(color: MP.line))) : null,
        child: child,
      ),
    );
    if (onTap == null) return content;
    return Tap(onTap: onTap, radius: 0, child: content);
  }
}

// ── Live helpers (AI assistant & feedback screens) ──

/// Why an AI answer was flagged: 'dosage_question' → 'dosage question'.
String d10Reason(String reason) => switch (reason) {
  'symptom_question' => 'symptom question',
  'dosage_question' => 'dosage question',
  'low_confidence' => 'low-confidence answer',
  'outside_knowledge_base' => 'outside knowledge base',
  '' => 'needs review',
  _ => reason.replaceAll('_', ' '),
};

/// 'high' → 'High'
String d10Cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Knowledge-base languages: API code → label.
const d10Languages = {'en': 'English', 'bn': 'Bengali', 'hi': 'Hindi'};

/// Knowledge-base categories: API code → label.
const d10Categories = {
  'medicines': 'Medicines',
  'diabetes': 'Diabetes',
  'hypertension': 'Hypertension',
  'diet': 'Diet',
  'infections': 'Infections',
  'thyroid': 'Thyroid',
  'other': 'Other',
};

const _d10Months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

int _d10DaysAgo(DateTime d, DateTime n) =>
    DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;

/// "today", "yesterday", "3 days ago", "2 weeks ago", "1 Sep".
String d10Since(DateTime d, {DateTime? now}) {
  final days = _d10DaysAgo(d, now ?? DateTime.now());
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 28) return days < 14 ? '1 week ago' : '${days ~/ 7} weeks ago';
  return '${d.day} ${_d10Months[d.month - 1]}';
}

/// Day caption above chat messages: "Today", "Yesterday", "Sat, 12 Sep".
String d10DayCaption(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = _d10DaysAgo(d, n);
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[d.weekday - 1]}, ${d.day} ${_d10Months[d.month - 1]}${d.year == n.year ? '' : ' ${d.year}'}';
}

/// A person in a "Read by" / "replied" line: "Dr. Sen", "Tania".
String d10Person(String name) {
  final n = name.trim();
  if (n.isEmpty) return '';
  if (RegExp(r'^Dr\.?\s', caseSensitive: false).hasMatch(n)) {
    final parts = n.replaceFirst(RegExp(r'^Dr\.?\s+', caseSensitive: false), '').split(RegExp(r'\s+'));
    return 'Dr. ${parts.last}';
  }
  return n.split(RegExp(r'\s+')).first;
}

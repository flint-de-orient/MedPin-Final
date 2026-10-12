import 'package:flutter/material.dart' hide Text;

import '../../widgets/mp.dart';
import 'common_d4.dart';
import '../../widgets/i18n.dart';

/// Shared pieces for the doctor's settings screens added after the design
/// (About and photo, Chat, Notifications, Payouts, Privacy, Help), the lab
/// report view and the AI history. They reuse the My-profile look exactly.

/// Settings group: 13/700 uppercase caption over a white card of rows.
class D11Group extends StatelessWidget {
  final String label;
  final List<Widget> rows;
  const D11Group(this.label, this.rows, {super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(label.toUpperCase(), style: tx(13, w: w700, c: MP.ink3, em: 0.06)),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: MPDeco.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) const MpDivider(), rows[i]],
          ],
        ),
      ),
    ],
  );
}

/// Settings row: 15/600 title, optional 13px line, optional 14/600 value,
/// chevron (or a custom [trailing]). Padding 14 0.
class D11Row extends StatelessWidget {
  final String title;
  final String? sub;
  final String? value;
  final Color valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const D11Row(this.title, {super.key, this.sub, this.value, this.valueColor = MP.ink2, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(15, w: w600)),
                if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: tx(13, c: MP.ink2, h: 1.4))],
              ],
            ),
          ),
          if (value != null) ...[const SizedBox(width: 12), Text(value!, style: tx(14, w: w600, c: valueColor))],
          const SizedBox(width: 12),
          trailing ?? (onTap == null ? const SizedBox.shrink() : const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2)),
        ],
      ),
    );
    if (onTap == null) return row;
    return Tap(onTap: onTap, radius: 0, child: row);
  }
}

/// A switch inside a settings card, padded like [D11Row].
class D11Switch extends StatelessWidget {
  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const D11Switch(this.title, this.sub, {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: D4SwitchRow(title: title, sub: sub, value: value, onChanged: onChanged),
  );
}

/// Labelled text field with a controller (looks like `D4Field`).
class D11Field extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType keyboard;
  final int? maxLines;
  final int? maxLength;
  final TextCapitalization caps;
  const D11Field(
    this.label,
    this.controller, {
    super.key,
    this.hint,
    this.keyboard = TextInputType.text,
    this.maxLines = 1,
    this.maxLength,
    this.caps = TextCapitalization.none,
  });

  @override
  State<D11Field> createState() => _D11FieldState();
}

class _D11FieldState extends State<D11Field> {
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.maxLength;
    return D4Labeled(
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            // The field inside is what screen readers focus.
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: _f.requestFocus,
            child: D4FieldBox(
              focused: _f.hasFocus,
              child: TextField(
                controller: widget.controller,
                focusNode: _f,
                keyboardType: widget.maxLines == 1 ? widget.keyboard : TextInputType.multiline,
                textCapitalization: widget.caps,
                maxLines: widget.maxLines,
                minLines: widget.maxLines == null ? 4 : null,
                maxLength: max,
                style: tx(15, h: 1.4),
                cursorColor: MP.primary,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: d4FieldPad,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: tx(15, h: 1.4, c: MP.ink3),
                  counterText: '',
                ),
              ),
            ),
          ),
          if (max != null) ...[
            const SizedBox(height: 6),
            Text('${widget.controller.text.length} / $max', textAlign: TextAlign.right, style: tx(12, c: MP.ink3, tab: true)),
          ],
        ],
      ),
    );
  }
}

/// "9:00 AM" for "09:00".
String d11Clock(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Half-hour times "00:00" … "23:30".
final d11Times = [for (var i = 0; i < 48; i++) '${(i ~/ 2).toString().padLeft(2, '0')}:${i.isEven ? '00' : '30'}'];

/// Picks a time with the app's picker sheet; returns "HH:MM" or null.
Future<String?> d11PickTime(BuildContext context, String title, String current) async {
  final labels = [for (final t in d11Times) d11Clock(t)];
  final r = await d4PickOne(context, title: title, options: labels, value: d11Clock(current));
  return r == null ? null : d11Times[labels.indexOf(r)];
}

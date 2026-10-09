import 'package:flutter/material.dart';

import '../../widgets/mp.dart';

/// Design: Report-Download.dc.html — "Report · download options".
/// Sheet over 'Doctor-Reports' (also opened from the report registers).
class ReportDownloadSheet extends StatefulWidget {
  const ReportDownloadSheet({super.key});

  @override
  State<ReportDownloadSheet> createState() => _ReportDownloadSheetState();
}

// (title, description, short name for the button)
const _formats = [
  ('PDF', 'Formatted with summary and charts. Best to print or share.', 'PDF'),
  ('Excel (.xlsx)', 'One row per consultation. Best for your accountant.', 'Excel'),
  ('CSV', 'Plain data for other software', 'CSV'),
];

class _ReportDownloadSheetState extends State<ReportDownloadSheet> {
  int _fmt = 0;
  bool _mobiles = false;
  bool _email = true;

  void _download() {
    final name = _formats[_fmt].$3;
    toast(context, _email ? '$name downloaded · copy sent to your email' : '$name downloaded');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Download report', style: tx(20, w: w700, h: 1.25)),
              const SizedBox(height: 4),
              Text('Consultation register · 1 – 30 Sep · all locations', style: tx(14, c: MP.ink2)),
            ],
          ),
          const SizedBox(height: 18),

          // Format
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Format', style: tx(14, w: w600))),
          for (var i = 0; i < _formats.length; i++) ...[if (i > 0) const SizedBox(height: 8), _option(i)],
          const SizedBox(height: 18),

          // Options
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toggle(
                  'Include patient mobile numbers',
                  'Off by default to protect privacy',
                  _mobiles,
                  (v) => setState(() => _mobiles = v),
                ),
                _toggle(
                  'Email a copy to me',
                  'Sent to your registered email',
                  _email,
                  (v) => setState(() => _email = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          MpButton('Download ${_formats[_fmt].$3}', onTap: _download),
        ],
      ),
    );
  }

  Widget _option(int i) {
    final sel = i == _fmt;
    // Selected border is 1.5px (1px otherwise); Tap insets by it like CSS.
    final bw = sel ? 1.5 : 1.0;
    return Semantics(
      button: true,
      selected: sel,
      child: Tap(
        onTap: () => setState(() => _fmt = i),
        radius: 16,
        color: sel ? MP.primarySoft : MP.white,
        border: sel ? MP.primary : MP.lineStrong,
        borderWidth: bw,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _Radio(sel),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formats[i].$1, style: tx(16, w: w700)),
                  const SizedBox(height: 2),
                  Text(_formats[i].$2, style: tx(13, c: MP.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tx(15, w: w600)),
                  const SizedBox(height: 2),
                  Text(sub, style: tx(13, c: MP.ink2)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MpSwitch(value: value, small: true, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// 22px radio with a 2px ring (#003399 / #D5DBE5) and a 10px dot.
class _Radio extends StatelessWidget {
  final bool on;
  const _Radio(this.on);

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

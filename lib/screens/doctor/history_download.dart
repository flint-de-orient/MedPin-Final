import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d2.dart';

/// Design: History-Download.dc.html — "Doctor · History · download".
/// Sheet over 'Doctor-History'.
class HistoryDownloadSheet extends StatefulWidget {
  const HistoryDownloadSheet({super.key});

  @override
  State<HistoryDownloadSheet> createState() => _HistoryDownloadSheetState();
}

const _periods = ['This month', 'Last 3 months', 'This year', 'Custom'];

/// (title, description, button label)
const _formats = [
  ('PDF', 'Formatted with summary and charts. Best to print or share.', 'PDF'),
  ('Excel (.xlsx)', 'One row per appointment, with status and fee.', 'Excel'),
  ('CSV', 'Plain data for other software', 'CSV'),
];

class _HistoryDownloadSheetState extends State<HistoryDownloadSheet> {
  int _period = 1;
  int _format = 0;
  bool _mobiles = false;
  bool _email = true;

  void _download() {
    final nav = Navigator.of(context);
    nav.pop();
    toast(nav.context, _email ? 'Download started · a copy is on its way to your email' : 'Download started');
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: VGap(
          gap: 18,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Download history', style: tx(20, w: w700, h: 1.25)),
                const Gap(4),
                Text('1 Jul – 1 Oct 2026 · all statuses · 942 appointments', style: tx(14, c: MP.ink2)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Legend('Period'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _periods.length; i++)
                      D2Chip(_periods[i], selected: i == _period, onTap: () => setState(() => _period = i)),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Legend('Format'),
                for (var i = 0; i < _formats.length; i++) ...[
                  if (i > 0) const Gap(8),
                  _FormatOption(
                    title: _formats[i].$1,
                    description: _formats[i].$2,
                    selected: i == _format,
                    onTap: () => setState(() => _format = i),
                  ),
                ],
              ],
            ),
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Column(
                children: [
                  _ToggleRow(
                    title: 'Include patient mobile numbers',
                    subtitle: 'Off by default to protect privacy',
                    value: _mobiles,
                    onChanged: (v) => setState(() => _mobiles = v),
                  ),
                  _ToggleRow(
                    title: 'Email a copy to me',
                    subtitle: 'Sent to your registered email',
                    value: _email,
                    onChanged: (v) => setState(() => _email = v),
                  ),
                ],
              ),
            ),
            MpButton('Download ${_formats[_format].$3}', onTap: _download),
          ],
        ),
      ),
    );
  }
}

/// Fieldset legend: 14/600 with 8px below.
class _Legend extends StatelessWidget {
  final String text;
  const _Legend(this.text);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: tx(14, w: w600)));
}

class _FormatOption extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  const _FormatOption({required this.title, required this.description, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Tap(
        onTap: onTap,
        radius: 16,
        color: selected ? MP.primarySoft : MP.white,
        border: selected ? MP.primary : MP.lineStrong,
        borderWidth: selected ? 1.5 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? MP.primary : MP.lineStrong, width: 2),
              ),
              child:
                  selected
                      ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
                      )
                      : null,
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tx(16, w: w700)),
                  const Gap(2),
                  Text(description, style: tx(13, c: MP.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
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
                  const Gap(2),
                  Text(subtitle, style: tx(13, c: MP.ink2)),
                ],
              ),
            ),
            const Gap(12),
            MpSwitch(value: value, onChanged: onChanged, small: true),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';
import 'common_d3.dart';
import '../../widgets/i18n.dart';

/// Design: History-Download.dc.html — "Doctor · History · download".
/// Sheet over 'Doctor-History'. Live: the subtitle counts GET /api/history for
/// the period; Download posts POST /api/exports and opens the file link.
class HistoryDownloadSheet extends StatefulWidget {
  const HistoryDownloadSheet({super.key});

  @override
  State<HistoryDownloadSheet> createState() => _HistoryDownloadSheetState();
}

const _periods = ['This month', 'Last 3 months', 'This year', 'Custom'];
const _periodKeys = ['this_month', 'last_3_months', 'this_year'];
const _formatKeys = ['pdf', 'xlsx', 'csv'];
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "1 Jul – 1 Oct 2026" (year on both ends when they differ).
String _range(DateTime a, DateTime b) =>
    a.year == b.year ? '${a.day} ${_mon[a.month - 1]} – ${b.day} ${_mon[b.month - 1]} ${b.year}' : '${a.day} ${_mon[a.month - 1]} ${a.year} – ${b.day} ${_mon[b.month - 1]} ${b.year}';

/// (title, description, button label)
const _formats = [
  ('PDF', 'Formatted with summary and charts. Best to print or share.', 'PDF'),
  ('Excel (.xlsx)', 'One row per appointment, with status and fee.', 'Excel'),
  ('CSV', 'Plain data for other software', 'CSV'),
];

class _HistoryDownloadSheetState extends State<HistoryDownloadSheet> with LiveData {
  int _period = 1;
  int _format = 0;
  bool _mobiles = false;
  bool _email = true;
  bool _periodFromArgs = false;
  DateTimeRange? _custom;
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    if (!_periodFromArgs) {
      _periodFromArgs = true;
      final a = Nav.args<Map>(context);
      final i = _periodKeys.indexOf('${a?['period']}');
      if (i >= 0) _period = i;
    }
    return Api.I.get('/api/history', query: _query);
  }

  Map<String, Object?> get _query {
    final c = _custom;
    if (_period == 3 && c != null) return {'from': _ymd(c.start), 'to': _ymd(c.end), 'limit': 1};
    return {'period': _periodKeys[_period == 3 ? 1 : _period], 'limit': 1};
  }

  /// "1 Jul – 1 Oct 2026 · all statuses · 942 appointments"
  String get _subtitle {
    final d = data;
    if (d == null) return isLive ? 'All statuses' : '1 Jul – 1 Oct 2026 · all statuses · 942 appointments';
    final from = F.date(d['from']);
    final to = F.date(d['to'])?.subtract(const Duration(days: 1));
    final n = d.obj('summary').numOr('total').toInt();
    return [if (from != null && to != null) _range(from, to), 'all statuses', '$n ${n == 1 ? 'appointment' : 'appointments'}'].join(' · ');
  }

  Future<void> _pickPeriod(int i) async {
    if (!isLive) {
      setState(() => _period = i);
      return;
    }
    if (i == 3) {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      );
      if (r == null || !mounted) return;
      _custom = r;
    }
    setState(() => _period = i);
    reload(quiet: true);
  }

  Future<void> _downloadLive() async {
    final d = data;
    final from = F.date(d?['from']);
    final to = F.date(d?['to'])?.subtract(const Duration(days: 1));
    final body = <String, Object?>{
      'kind': 'appointment_history',
      'format': _formatKeys[_format],
      'filters': {if (from != null) 'from': _ymd(from), if (to != null) 'to': _ymd(to)},
      'includeMobiles': _mobiles,
    };
    // "Email me a copy": emailed (asks for an email if none), and saved here too.
    final dynamic res;
    if (_email) {
      res = await d3EmailExport(context, body, name: 'MedPin-appointment-history', busy: _busy, shareOnFail: false);
    } else {
      res = await runAction(context, () => Api.I.post('/api/exports', body), busy: _busy);
    }
    if (res is! Map || !mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    final url = res['url'] as String?;
    var ok = false;
    final under = nav.context;
    if (url != null && under.mounted) {
      await d3Save(under, url, ['MedPin-appointment-history', if (from != null) _ymd(from), if (to != null) _ymd(to)].join('-'));
      ok = true;
    }
    if (!under.mounted) return;
    if (!ok) {
      toast(under, "The file is ready but couldn't be opened");
      return;
    }
  }

  void _download() {
    if (isLive) {
      _downloadLive();
      return;
    }
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
                Text(_subtitle, style: tx(14, c: MP.ink2)),
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
                      D2Chip(_periods[i], selected: i == _period, onTap: () => _pickPeriod(i)),
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

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';
import '../../widgets/i18n.dart';

/// Design: Report-Referrals.dc.html — "Report · Referrals".
/// Live data: GET /api/referrals?direction=sent|received (period applied
/// to `referredAt` on the device).
class ReportReferralsScreen extends StatefulWidget {
  const ReportReferralsScreen({super.key});

  @override
  State<ReportReferralsScreen> createState() => _ReportReferralsScreenState();
}

class _Ref {
  final String name;
  final String status;
  final String detail;
  final String date;
  final bool seen;
  const _Ref(this.name, this.status, this.detail, this.date, {this.seen = false});
}

/// One direction of the Sent / Received tabs.
class _Dir {
  final String tab;
  final List<(String, String, Color)> stats;
  final String barTitle;
  final List<D3BarRow> bars;
  final String listTitle;
  final List<_Ref> rows;
  final List<_Ref> more;
  const _Dir({
    required this.tab,
    required this.stats,
    required this.barTitle,
    required this.bars,
    required this.listTitle,
    required this.rows,
    required this.more,
  });
}

const _dirs = [
  _Dir(
    tab: 'Sent · 9',
    stats: [('9', 'Sent', MP.ink), ('6', 'Seen by them', MP.green), ('3', 'Awaiting', MP.amber)],
    barTitle: 'Sent to',
    bars: [
      D3BarRow('Cardiology', '4', 0.44),
      D3BarRow('Nephrology', '2', 0.22),
      D3BarRow('Ophthalmology', '2', 0.22),
      D3BarRow('Gynaecology', '1', 0.11),
    ],
    listTitle: 'All sent',
    rows: [
      _Ref('Amit Pal', 'Awaiting', 'To Dr. Sourav Lahiri · Nephrology · Rising creatinine', '24 Sep'),
      _Ref('Priya Sharma', 'Awaiting', 'To Dr. Rina Mitra · Cardiology · LDL still high', '29 Sep'),
      _Ref('Tapas Kar', 'Seen 25 Sep', 'To Eye clinic · Ophthalmology · Diabetic eye check', '18 Sep', seen: true),
      _Ref('Moumita Roy', 'Seen 8 Sep', 'To Dr. Rina Mitra · Cardiology · Palpitations', '2 Sep', seen: true),
    ],
    // Revealed by "Show 5 more".
    more: [
      _Ref('Debasish Bose', 'Awaiting', 'To Dr. Sourav Lahiri · Nephrology · Protein in urine', '27 Sep'),
      _Ref(
        'Partha Ghosh',
        'Seen 22 Sep',
        'To Dr. Rina Mitra · Cardiology · Breathless on stairs',
        '16 Sep',
        seen: true,
      ),
      _Ref('Ritam Sarkar', 'Seen 19 Sep', 'To Eye clinic · Ophthalmology · Blurred vision', '11 Sep', seen: true),
      _Ref('Sohini Bose', 'Seen 15 Sep', 'To Dr. Mitali Sen · Gynaecology · Irregular periods', '9 Sep', seen: true),
      _Ref('Subhash Dey', 'Seen 10 Sep', 'To Dr. Rina Mitra · Cardiology · ECG changes', '4 Sep', seen: true),
    ],
  ),
  _Dir(
    tab: 'Received · 6',
    stats: [('6', 'Received', MP.ink), ('4', 'Seen by you', MP.green), ('2', 'Awaiting', MP.amber)],
    barTitle: 'Received from',
    bars: [
      D3BarRow('General medicine', '3', 0.50),
      D3BarRow('Gynaecology', '2', 0.33),
      D3BarRow('Cardiology', '1', 0.17),
    ],
    listTitle: 'All received',
    rows: [
      _Ref('Rahul Das', 'Awaiting', 'From Dr. Rina Mitra · Cardiology · BP and sugar review', '29 Sep'),
      _Ref(
        'Payel Mukherjee',
        'Seen 30 Sep',
        'From Dr. Mitali Sen · Gynaecology · Thyroid before pregnancy',
        '27 Sep',
        seen: true,
      ),
      _Ref('Aisha Khan', 'Awaiting', 'From Dr. Anjan Basu · General medicine · TSH high on screening', '26 Sep'),
      _Ref('Farhana Islam', 'Seen 25 Sep', 'From Dr. Mitali Sen · Gynaecology · Low haemoglobin', '22 Sep', seen: true),
    ],
    more: [
      _Ref(
        'Kakoli Das',
        'Seen 18 Sep',
        'From Dr. Anjan Basu · General medicine · Newly found diabetes',
        '15 Sep',
        seen: true,
      ),
      _Ref(
        'Haripada Saha',
        'Seen 5 Sep',
        'From Dr. Anjan Basu · General medicine · BP not controlled',
        '3 Sep',
        seen: true,
      ),
    ],
  ),
];

class _ReportReferralsScreenState extends State<ReportReferralsScreen> with LiveData, D3FilterState {
  int _tab = 0;
  final _more = [false, false];
  static const _shown = 4;

  /// Both directions at once, so switching tabs needs no fetch.
  @override
  Future<Object?> fetch() async {
    await loadFilters();
    final r = await Future.wait([
      Api.I.get('/api/referrals', query: {'direction': 'sent'}),
      Api.I.get('/api/referrals', query: {'direction': 'received'}),
    ]);
    return {'sent': r[0], 'received': r[1]};
  }

  /// Referrals of one direction made in the chosen period, newest first.
  /// (GET /api/referrals has no date range, so the period is applied here.)
  List<Map<String, dynamic>> _items(String dir) {
    final (from, to) = filters.days;
    final out = [
      for (final r in data!.obj(dir).list('items'))
        if (d3Day(r['referredAt']) case final d? when !d.isBefore(from) && !d.isAfter(to)) r,
    ];
    out.sort((a, b) => b.str('referredAt').compareTo(a.str('referredAt')));
    return out;
  }

  _Ref _refOf(Map<String, dynamic> r, String dir) {
    final p = r['patientId'] is Map ? (r['patientId'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final seen = r['status'] == 'seen';
    final seenAt = d3Day(r['seenAt']);
    final at = d3Day(r['referredAt']);
    final detail = [
      '${dir == 'sent' ? 'To' : 'From'} ${r.str('counterpartName')}',
      r.str('specialty'),
      r.str('reason'),
    ].where((s) => s.trim().isNotEmpty && s.trim() != 'To' && s.trim() != 'From').join(' · ');
    return _Ref(
      p.str('name', 'Patient'),
      r['status'] == 'cancelled' ? 'Cancelled' : (seen ? (seenAt == null ? 'Seen' : 'Seen ${F.dayMonth(seenAt)}') : 'Awaiting'),
      detail,
      at == null ? '' : F.dayMonth(at),
      seen: seen,
    );
  }

  /// The design's direction view, built from live referrals.
  _Dir _liveDir(int i) {
    final dir = i == 0 ? 'sent' : 'received';
    final items = _items(dir);
    final seen = items.where((r) => r['status'] == 'seen').length;
    final awaiting = items.where((r) => r['status'] == 'awaiting').length;
    final by = <String, int>{};
    for (final r in items) {
      final s = r.str('specialty', 'Other');
      by[s.isEmpty ? 'Other' : s] = (by[s.isEmpty ? 'Other' : s] ?? 0) + 1;
    }
    final bars = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final refs = [for (final r in items) _refOf(r, dir)];
    return _Dir(
      tab: '${i == 0 ? 'Sent' : 'Received'} · ${items.length}',
      stats: [
        (F.count(items.length), i == 0 ? 'Sent' : 'Received', MP.ink),
        (F.count(seen), i == 0 ? 'Seen by them' : 'Seen by you', MP.green),
        (F.count(awaiting), 'Awaiting', MP.amber),
      ],
      barTitle: i == 0 ? 'Sent to' : 'Received from',
      bars: [for (final b in bars) D3BarRow(b.key, F.count(b.value), items.isEmpty ? 0 : b.value / items.length)],
      listTitle: i == 0 ? 'All sent' : 'All received',
      rows: refs.take(_shown).toList(),
      more: refs.skip(_shown).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = isLive;
    final dirs = data == null ? _dirs : [_liveDir(0), _liveDir(1)];
    final d = dirs[_tab];
    final rows = [...d.rows, if (_more[_tab]) ...d.more];
    final rawRows = data == null ? null : _items(_tab == 0 ? 'sent' : 'received');
    final total = data == null ? 0 : _items('sent').length + _items('received').length;
    return MpPage(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          live
              ? D3ReportHeader(
                title: 'Referrals',
                subtitle: data == null ? filters.label : '${d3Plural(total, 'referral')} · ${filters.label}',
                rangeLabel: filters.label,
                locationLabel: filters.locationLabel,
                onFilters: pickFilters,
              )
              : const D3ReportHeader(title: 'Referrals', subtitle: '15 referrals · 1 – 30 Sep'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: D3Tabs(
              options: [for (final x in dirs) x.tab],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
        ],
      ),
      bottom: live
          ? D3DownloadBar('Download report', reportType: 'referrals', filters: filters)
          : const D3DownloadBar('Download report'),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          D3StatTiles(d.stats),
          if (d.bars.isNotEmpty) D3BarCard(title: d.barTitle, note: 'Referrals', rows: d.bars),
          D3SectionHead(d.listTitle, trailing: 'Newest first'),
          if (rows.isNotEmpty)
            D3ListCard(children: [for (var i = 0; i < rows.length; i++) _row(rows[i], rawRows?[i])]),
          if (!_more[_tab] && d.more.isNotEmpty)
            D3ShowMore('Show ${d.more.length} more', onTap: () => setState(() => _more[_tab] = true)),
        ],
      ),
    );
  }

  Widget _row(_Ref r, [Map<String, dynamic>? raw]) {
    final p = raw?['patientId'];
    return D3RegisterRow(
      name: r.name,
      trailing: D3Badge(r.status, tone: r.seen ? D3Tone.green : D3Tone.amber),
      detail: r.detail,
      footer: Text(r.date, style: tx(13, c: MP.ink3)),
      onTap: () => Nav.go(
        context,
        'PP-Summary',
        args: raw == null ? null : {if (p is Map) 'patientId': p['id'], 'referralId': raw['id']},
      ),
    );
  }
}

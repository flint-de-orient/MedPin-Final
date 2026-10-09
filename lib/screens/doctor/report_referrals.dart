import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Report-Referrals.dc.html — "Report · Referrals".
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

class _ReportReferralsScreenState extends State<ReportReferralsScreen> {
  int _tab = 0;
  final _more = [false, false];

  @override
  Widget build(BuildContext context) {
    final d = _dirs[_tab];
    final rows = [...d.rows, if (_more[_tab]) ...d.more];
    return MpPage(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const D3ReportHeader(title: 'Referrals', subtitle: '15 referrals · 1 – 30 Sep'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: D3Tabs(
              options: [for (final x in _dirs) x.tab],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
        ],
      ),
      bottom: const D3DownloadBar('Download report'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          D3StatTiles(d.stats),
          D3BarCard(title: d.barTitle, note: 'Referrals', rows: d.bars),
          D3SectionHead(d.listTitle, trailing: 'Newest first'),
          D3ListCard(children: [for (final r in rows) _row(r)]),
          if (!_more[_tab]) D3ShowMore('Show ${d.more.length} more', onTap: () => setState(() => _more[_tab] = true)),
        ],
      ),
    );
  }

  Widget _row(_Ref r) => D3RegisterRow(
    name: r.name,
    trailing: D3Badge(r.status, tone: r.seen ? D3Tone.green : D3Tone.amber),
    detail: r.detail,
    footer: Text(r.date, style: tx(13, c: MP.ink3)),
    onTap: () => Nav.go(context, 'PP-Summary'),
  );
}

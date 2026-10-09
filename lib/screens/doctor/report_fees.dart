import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Report-Fees.dc.html — "Report · Fees and collections".
class ReportFeesScreen extends StatefulWidget {
  const ReportFeesScreen({super.key});

  @override
  State<ReportFeesScreen> createState() => _ReportFeesScreenState();
}

const _byLocation = [
  D3BarRow('City Care · Salt Lake', '₹97,200', 0.60),
  D3BarRow('City Care · New Town', '₹40,000', 0.25),
  D3BarRow('Sen Diabetes Chamber · Gariahat', '₹23,800', 0.15),
];

const _byMethod = [
  D3BarRow('UPI', '₹98,400', 0.63),
  D3BarRow('Cash', '₹41,600', 0.27),
  D3BarRow('Card', '₹16,800', 0.11),
];

// (patient, visit) — every pending fee is ₹600; the first three are shown,
// the rest are revealed by "Show 4 more" (7 patients · ₹4,200 in all).
const _pending = [
  ('Nasreen Begum', '29 Sep · Salt Lake · in clinic'),
  ('Kaushik Paul', '26 Sep · Salt Lake · video'),
  ('Shreya Basu', '22 Sep · Salt Lake · in clinic'),
  ('Partha Ghosh', '18 Sep · Salt Lake · video'),
  ('Sohini Bose', '15 Sep · Salt Lake · in clinic'),
  ('Subrata Pal', '11 Sep · Salt Lake · video'),
  ('Mousumi Dey', '4 Sep · Salt Lake · in clinic'),
];
const _shown = 3;
const _fee = 600;
const _collected = 156800;

class _ReportFeesScreenState extends State<ReportFeesScreen> {
  final _paid = <int>{};
  bool _more = false;

  void _markPaid(int i) {
    setState(() => _paid.add(i));
    toast(context, '${_pending[i].$1} marked as paid');
  }

  @override
  Widget build(BuildContext context) {
    final left = _pending.length - _paid.length;
    final visible = [
      for (var i = 0; i < (_more ? _pending.length : _shown); i++)
        if (!_paid.contains(i)) i,
    ];
    final collected = (_collected + _fee * _paid.length) / 100000;
    return MpPage(
      header: const D3ReportHeader(title: 'Fees and collections', subtitle: '₹1,61,000 billed · 1 – 30 Sep'),
      bottom: const D3DownloadBar('Download report'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          D3StatTiles([
            ('₹1.61L', 'Billed', MP.ink),
            ('₹${collected.toStringAsFixed(2)}L', 'Collected', MP.green),
            (d3Rupees(left * _fee), 'Pending', MP.amber),
          ]),
          const D3BarCard(title: 'By location', note: 'Billed', rows: _byLocation),
          const D3BarCard(title: 'By payment method', note: 'Collected', rows: _byMethod),

          // Free visits
          MpCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Free visits', style: tx(15, w: w700)),
                      const SizedBox(height: 2),
                      Text('Report reviews within 7 days of a visit', style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('10', style: tx(20, w: w800, tab: true)),
              ],
            ),
          ),

          D3SectionHead('Pending payments', trailing: '$left patient${left == 1 ? '' : 's'}'),
          if (visible.isNotEmpty) D3ListCard(children: [for (final i in visible) _row(i)]),
          if (!_more) D3ShowMore('Show ${_pending.length - _shown} more', onTap: () => setState(() => _more = true)),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final p = _pending[i];
    return D3RegisterRow(
      name: p.$1,
      trailing: D3Amount(d3Rupees(_fee)),
      detail: p.$2,
      footer: D3LinkRow([
        ('Send payment link', () => toast(context, 'Payment link sent to ${p.$1}')),
        ('Mark as paid', () => _markPaid(i)),
      ]),
      onTap: () => Nav.go(context, 'PP-Summary'),
    );
  }
}

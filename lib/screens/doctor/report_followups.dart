import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Report-FollowUps.dc.html — "Report · Follow-up compliance".
class ReportFollowupsScreen extends StatefulWidget {
  const ReportFollowupsScreen({super.key});

  @override
  State<ReportFollowupsScreen> createState() => _ReportFollowupsScreenState();
}

const _byCondition = [
  D3BarRow('Type 2 diabetes', '78%', 0.78),
  D3BarRow('Hypertension', '70%', 0.70),
  D3BarRow('Hypothyroidism', '65%', 0.65),
];

// (patient, days late, detail)
const _missed = [
  ('Kaushik Paul', '23 days late', '47 M · Type 2 diabetes · due 8 Sep'),
  ('Shreya Basu', '17 days late', '33 F · Hypothyroidism · due 14 Sep'),
  ('Gopal Mitra', '12 days late', '66 M · Hypertension · due 19 Sep'),
  ('Ananya Chatterjee', '7 days late', '39 F · Type 2 diabetes · due 24 Sep'),
];

/// Revealed by "Show 20 more" (24 missed in all; today is 1 Oct).
const _missedMore = [
  ('Rakhi Sen', '7 days late', '52 F · Hypertension · due 24 Sep'),
  ('Pranab Das', '6 days late', '60 M · Type 2 diabetes · due 25 Sep'),
  ('Sumita Ghosh', '6 days late', '44 F · Hypothyroidism · due 25 Sep'),
  ('Dipak Mondal', '6 days late', '58 M · Hypertension · due 25 Sep'),
  ('Rupa Dey', '5 days late', '36 F · Type 2 diabetes · due 26 Sep'),
  ('Haripada Saha', '5 days late', '69 M · Hypertension · due 26 Sep'),
  ('Moni Begum', '5 days late', '41 F · Hypothyroidism · due 26 Sep'),
  ('Sukanta Roy', '4 days late', '50 M · Type 2 diabetes · due 27 Sep'),
  ('Jayeeta Bose', '4 days late', '29 F · Hypothyroidism · due 27 Sep'),
  ('Tarun Kundu', '3 days late', '63 M · Type 2 diabetes · due 28 Sep'),
  ('Shampa Nag', '3 days late', '47 F · Hypertension · due 28 Sep'),
  ('Arup Biswas', '3 days late', '55 M · Type 2 diabetes · due 28 Sep'),
  ('Mahua Pal', '2 days late', '38 F · Hypothyroidism · due 29 Sep'),
  ('Nirmal Dutta', '2 days late', '71 M · Hypertension · due 29 Sep'),
  ('Rubina Khatun', '2 days late', '33 F · Type 2 diabetes · due 29 Sep'),
  ('Kartik Majhi', '2 days late', '46 M · Hypertension · due 29 Sep'),
  ('Ritam Sarkar', '1 day late', '41 M · Type 2 diabetes · due 30 Sep'),
  ('Sohini Bose', '1 day late', '36 F · Hypothyroidism · due 30 Sep'),
  ('Bapi Hazra', '1 day late', '52 M · Type 2 diabetes · due 30 Sep'),
  ('Ankita Ghosh', '1 day late', '27 F · Hypothyroidism · due 30 Sep'),
];

class _ReportFollowupsScreenState extends State<ReportFollowupsScreen> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final rows = [..._missed, if (_more) ..._missedMore];
    return MpPage(
      header: const D3ReportHeader(title: 'Follow-up compliance', subtitle: '150 follow-ups due · 1 – 30 Sep'),
      bottom: const D3DownloadBar('Download report'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          const _Summary(),
          const D3BarCard(title: 'On time by condition', rows: _byCondition),
          const D3SectionHead('Missed follow-ups', trailing: '24 patients'),
          D3ListCard(children: [for (final r in rows) _row(r)]),
          if (!_more) D3ShowMore('Show ${_missedMore.length} more', onTap: () => setState(() => _more = true)),
        ],
      ),
    );
  }

  Widget _row((String, String, String) r) => D3RegisterRow(
    name: r.$1,
    trailing: D3Badge(r.$2, tone: D3Tone.red),
    detail: r.$3,
    footer: D3LinkRow([
      ('Send reminder', () => toast(context, 'Reminder sent to ${r.$1}')),
      ('Call', () => toast(context, 'Calling ${r.$1}')),
    ]),
    onTap: () => Nav.go(context, 'PP-Summary'),
  );
}

/// 72% headline, stacked on-time / late / missed bar and its legend.
class _Summary extends StatelessWidget {
  const _Summary();

  @override
  Widget build(BuildContext context) {
    return MpCard(
      padding: const EdgeInsets.all(20),
      child: VGap(
        gap: 14,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('72%', style: tx(36, w: w800, h: 1, em: -0.02)),
              const SizedBox(width: 10),
              Flexible(child: Text('came back on time', style: tx(14, c: MP.ink2))),
            ],
          ),
          Semantics(
            label: '108 on time, 18 late, 24 missed',
            child: SizedBox(
              height: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 72,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: MP.primary,
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(999)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Expanded(flex: 12, child: ColoredBox(color: MP.primaryMid)),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: 16,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: MP.lineStrong,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(999)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _legend(MP.primary, 'On time', '108')),
              const SizedBox(width: 8),
              Expanded(child: _legend(MP.primaryMid, 'Late', '18')),
              const SizedBox(width: 8),
              Expanded(child: _legend(MP.lineStrong, 'Missed', '24')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color dot, String label, String n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2))),
        ],
      ),
      const SizedBox(height: 2),
      Text(n, style: tx(17, w: w700)),
    ],
  );
}

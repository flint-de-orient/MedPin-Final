import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: Daily-Report.dc.html — "Daily report".
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

const _dates = [
  'Today · Tue, 29 Sep 2026',
  'Yesterday · Mon, 28 Sep 2026',
  'Sun, 27 Sep 2026',
  'Sat, 26 Sep 2026',
  'Fri, 25 Sep 2026',
];

const _vitalLabels = ['BP mmHg', 'Pulse', 'SpO₂', 'Weight'];

typedef _Visit =
    ({
      String name,
      String meta,
      bool isNew,
      String complaint,
      String diagnosis,
      List<String> vitals,
      List<(String, String)> rx,
      String advice,
      String followUp,
    });

const List<_Visit> _visits = [
  (
    name: 'Priya Sharma',
    meta: '29 F · Seen 9:04 AM',
    isNew: false,
    complaint: 'Tiredness and excess thirst, 2 weeks',
    diagnosis: 'Type 2 diabetes (uncontrolled), PCOS',
    vitals: ['118/76', '82', '99%', '68 kg'],
    rx: [
      ('Metformin 500 mg', '1-0-1 · after food · 3 months'),
      ('Glimepiride 1 mg', '1-0-0 · before breakfast · 3 months'),
      ('Vitamin D3 60,000 IU', 'Once a week · after food · 8 weeks'),
    ],
    advice: 'Walk 30 minutes daily and cut sugary drinks. Repeat HbA1c before the next visit.',
    followUp: 'Tue, 27 Oct 2026',
  ),
  (
    name: 'Rahul Das',
    meta: '45 M · Seen 9:38 AM',
    isNew: true,
    complaint: 'Headaches, home BP over 160/100',
    diagnosis: 'Essential hypertension, stage 2',
    vitals: ['158/98', '88', '98%', '82 kg'],
    rx: [
      ('Telmisartan 40 mg', '1-0-0 · after breakfast · 1 month'),
      ('Amlodipine 5 mg', '0-0-1 · after dinner · 1 month'),
    ],
    advice: 'Keep salt under 5 g a day. Log home BP twice daily in the app.',
    followUp: 'Tue, 13 Oct 2026',
  ),
  (
    name: 'Aisha Khan',
    meta: '52 F · Seen 10:06 AM',
    isNew: false,
    complaint: 'Weight gain, feels cold all the time',
    diagnosis: 'Hypothyroidism, under-replaced',
    vitals: ['124/80', '64', '98%', '71 kg'],
    rx: [('Levothyroxine 75 mcg', '1-0-0 · empty stomach · 6 weeks')],
    advice: 'Take it 30 minutes before breakfast or tea. Repeat TSH in 6 weeks.',
    followUp: 'Tue, 10 Nov 2026',
  ),
];

class _DailyReportScreenState extends State<DailyReportScreen> {
  String _date = _dates.first;

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: MpHeader(
        'Daily report',
        actions: [MpIconButton(I.share, label: 'Share report', onTap: () => toast(context, 'Report shared'))],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          D9Labeled(
            'Report date',
            h: 20 / 14,
            child: D9Select(
              title: 'Report date',
              value: _date,
              options: _dates,
              leading: I.calendar,
              leadingColor: MP.ink2,
              chevronColor: MP.ink3,
              right: 17,
              onChanged: (v) => setState(() => _date = v),
            ),
          ),
          const _DaySummary(),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: D9Label('Consultations')),
                  Text('In visit order', style: tx(13, c: MP.ink3)),
                ],
              ),
            ),
          ),
          for (final v in _visits) _VisitCard(v),
          SizedBox(
            height: 48,
            child: Tap(
              onTap: () => Nav.go(context, 'Report-Consultations'),
              radius: 12,
              child: Center(child: Text('Show 11 more consultations', style: tx(15, w: w600, c: MP.primary))),
            ),
          ),
        ],
      ),
      bottom: MpBottomBar(
        child: MpButton(
          'Download PDF',
          icon: I.download,
          iconStroke: 1.75,
          onTap: () => toast(context, 'PDF downloaded'),
        ),
      ),
    );
  }
}

/// White card with a 1.3fr / 1fr / 1fr grid of day totals.
class _DaySummary extends StatelessWidget {
  const _DaySummary();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Day summary',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: MPDeco.card(),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 13, child: _SummaryCell('14', 'Consultations', pad: 20, divider: false)),
            Expanded(flex: 10, child: _SummaryCell('3', 'New')),
            Expanded(flex: 10, child: _SummaryCell('11', 'Follow-up')),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String n;
  final String label;
  final double pad;
  final bool divider;
  const _SummaryCell(this.n, this.label, {this.pad = 16, this.divider = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad),
      decoration: divider ? const BoxDecoration(border: Border(left: BorderSide(color: MP.line))) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
          const Gap(4),
          // CSS grid keeps the label on one line (min-content track); scale
          // down instead of wrapping on the narrowest phones.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: tx(14, c: MP.ink2, h: 20 / 14), maxLines: 1),
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final _Visit v;
  const _VisitCard(this.v);

  Widget _block(String label, Widget child, {double gap = 4}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [D9Label(label), Gap(gap), child]);

  @override
  Widget build(BuildContext context) {
    return D9Card(
      gap: 16,
      children: [
        D9Head(
          v.name,
          sub: v.meta,
          subTab: true,
          trailing: v.isNew ? const MpBadge.blue('New', weight: w600) : const MpBadge.grey('Follow-up', weight: w600),
        ),
        _block('Complaint', Text(v.complaint, style: tx(16, h: 1.5))),
        _block('Diagnosis', Text(v.diagnosis, style: tx(16, w: w600, h: 1.5))),
        _block(
          'Vitals',
          gap: 8,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _vitalLabels.length; i++) ...[
                  if (i > 0) const Gap(8),
                  Expanded(
                    flex: i == 0 ? 125 : 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _vitalLabels[i],
                          style: tx(12, c: MP.ink3, h: 16 / 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Gap(2),
                        Text(
                          v.vitals[i],
                          style: tx(15, w: w600, h: 20 / 15, tab: true),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _block(
          'Prescription',
          gap: 8,
          VGap(
            gap: 12,
            cross: CrossAxisAlignment.start,
            children: [
              for (final (drug, detail) in v.rx)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drug, style: tx(16, w: w600, h: 24 / 16)),
                    Text(detail, style: tx(14, c: MP.ink2, h: 20 / 14, tab: true)),
                  ],
                ),
            ],
          ),
        ),
        _block('Advice', Text(v.advice, style: tx(16, h: 1.5))),
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
          child: Row(
            children: [
              const Ico(I.calendar, size: 18, color: MP.ink2),
              const Gap(8),
              Text('Follow-up', style: tx(14, c: MP.ink2)),
              const Gap(12),
              Expanded(
                child: Text(v.followUp, textAlign: TextAlign.right, style: tx(16, w: w600, h: 24 / 16, tab: true)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d6.dart';

/// Design: PP-Summary.dc.html — "Patient profile · Summary".
class PpSummaryScreen extends StatelessWidget {
  const PpSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const D6PatientTabsPage(tab: 0, children: [_AiSummary(), _Vitals(), _FastingSugar()]);
  }
}

class _AiSummary extends StatelessWidget {
  const _AiSummary();

  /// name, value, flag, reference range, source.
  static const _findings = [
    ('LDL cholesterol', '162 mg/dL', 'High', '< 100', 'Lipid profile, 12 Mar 2026'),
    ('Triglycerides', '210 mg/dL', 'High', '< 150', 'Lipid profile, 12 Mar 2026'),
    ('HbA1c', '7.2%', 'High', '< 7.0', 'Diabetes panel, 18 Jul 2026'),
    ('Fasting glucose', '138 mg/dL', 'High', '70–99', 'Diabetes panel, 18 Jul 2026'),
    ('Vitamin D', '14 ng/mL', 'Low', '30–100', 'Vitamin D, 18 Jul 2026'),
  ];

  @override
  Widget build(BuildContext context) {
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: VGap(
        gap: 16,
        children: [
          Row(
            children: [
              const Ico(I.sparkle, size: 16, color: MP.primary),
              const Gap(6),
              const Expanded(child: D6Caps('AI summary', color: MP.primary)),
              Text('Updated today, 8:55 AM', style: tx(13, c: MP.ink3)),
            ],
          ),
          Text.rich(
            TextSpan(
              style: tx(16, h: 1.55),
              children: [
                const TextSpan(
                  text:
                      'Type 2 diabetes since Jun 2025, with PCOS. Sugar control improved on Metformin '
                      '(HbA1c 8.4% → 6.8%) but has drifted back to 7.2%. LDL stays high on Atorvastatin. '
                      'Adherence is 86% with 4 missed doses this week. ',
                ),
                TextSpan(text: 'Reported chest tightness this morning.', style: tx(16, w: w700, h: 1.55)),
              ],
            ),
          ),

          // Abnormal findings
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text('Abnormal findings', style: tx(16, w: w700))),
                    Text('5 from 3 reports', style: tx(13, c: MP.ink3)),
                  ],
                ),
              ),
              for (final f in _findings) _finding(context, f),
            ],
          ),

          // Source note
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Written by AI from Priya's shared records. Check the source before acting.",
                    style: tx(13, c: MP.ink3, h: 1.4),
                  ),
                ),
                const Gap(12),
                D6Link('Sources', onTap: () => Nav.tab(context, 'PP-Tests')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _finding(BuildContext context, (String, String, String, String, String) f) {
    final name = tx(15, w: w600);
    final ref = tx(13, c: MP.ink3);
    final value = tx(15, w: w700, tab: true);
    final flag = tx(12, w: w700, c: MP.amber);
    final refText = 'Ref ${f.$4} · ${f.$5}';
    // Like Chrome, only break "138 mg/dL" at the space, not after the slash.
    final valueText = f.$2.replaceAll('/', '/\u2060');
    return D6Row(
      padding: const EdgeInsets.symmetric(vertical: 12),
      onTap: () => Nav.tab(context, 'PP-Tests'),
      child: LayoutBuilder(
        builder: (context, c) {
          // Both columns are flex items: when they don't fit side by side they
          // shrink together (e.g. "Fasting glucose": "138 / mg/dL" wraps).
          final (wl, wr) = D6Flex.pair(
            context,
            avail: c.maxWidth - 12,
            a: [(f.$1, name), (refText, ref)],
            b: [(valueText, value), (f.$3, flag)],
            aMinZero: true,
          );
          return Row(
            children: [
              SizedBox(
                width: wl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(f.$1, style: name), const Gap(2), Text(refText, style: ref)],
                ),
              ),
              const Gap(12),
              SizedBox(
                width: wr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [Text(valueText, style: value), const Gap(2), Text(f.$3, style: flag)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Vitals extends StatelessWidget {
  const _Vitals();

  /// label, value, unit, band, band colour.
  static const _vitals = [
    ('Blood pressure', '128/82', 'mmHg', 'Normal', MP.green),
    ('Pulse', '78', 'bpm', 'Normal', MP.green),
    ('SpO₂', '98', '%', 'Normal', MP.green),
    ('Temperature', '98.4', '°F', 'Normal', MP.green),
    ('Fasting sugar', '142', 'mg/dL', 'High · home reading', MP.amber),
    ('BMI', '27.4', '', 'Overweight', MP.amber),
    ('Weight', '68.5', 'kg', '−0.8 kg since Aug', MP.ink2),
    ('Height', '158', 'cm', 'Recorded Jun 2025', MP.ink2),
  ];

  @override
  Widget build(BuildContext context) {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: D6Title('Vitals', sub: 'Today, 8:52 AM · front desk', subH: null)),
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: D6Link('Record', onTap: () => Nav.go(context, 'Consult-Vitals')),
              ),
            ],
          ),
          MpGrid(
            columns: 2,
            children: [
              for (final v in _vitals)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.$1, style: tx(13, c: MP.ink2)),
                      const Gap(4),
                      Text.rich(
                        TextSpan(
                          text: v.$2,
                          style: tx(22, w: w800, h: 1.15, em: -0.01, tab: true),
                          // Inherits line-height 1.15 and -0.01em of 22px in CSS.
                          children: [
                            TextSpan(
                              text: ' ${v.$3}',
                              style: tx(13, w: w500, c: MP.ink3, h: 1.15).copyWith(letterSpacing: -0.22),
                            ),
                          ],
                        ),
                      ),
                      const Gap(4),
                      Text(v.$4, style: tx(12, w: w700, c: v.$5)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FastingSugar extends StatelessWidget {
  const _FastingSugar();

  static const _chart =
      r'''<svg xmlns="http://www.w3.org/2000/svg" width="310" height="140" viewBox="0 0 310 140" font-family="Figtree">
<g stroke="#E5E9F0" stroke-width="1"><line x1="34" y1="10" x2="306" y2="10"/><line x1="34" y1="50" x2="306" y2="50"/><line x1="34" y1="90" x2="306" y2="90"/><line x1="34" y1="118" x2="306" y2="118"/></g>
<g font-size="11" fill="#69738A" text-anchor="end"><text x="26" y="14">200</text><text x="26" y="54">150</text><text x="26" y="94">100</text><text x="26" y="122">70</text></g>
<line x1="34" y1="66" x2="306" y2="66" stroke="#076B3C" stroke-width="1" stroke-dasharray="4 3"/>
<text x="306" y="80" font-size="11" fill="#076B3C" text-anchor="end">Target 130</text>
<polyline points="40,50 84,54.8 128,58.8 172,57.2 216,53.2 260,59.6 302,56.4" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
<g fill="#FFFFFF" stroke="#003399" stroke-width="2"><circle cx="40" cy="50" r="3"/><circle cx="84" cy="54.8" r="3"/><circle cx="128" cy="58.8" r="3"/><circle cx="172" cy="57.2" r="3"/><circle cx="216" cy="53.2" r="3"/><circle cx="260" cy="59.6" r="3"/><circle cx="302" cy="56.4" r="3.5" fill="#003399"/></g>
<g font-size="11" fill="#69738A" text-anchor="middle"><text x="40" y="136">Wed</text><text x="84" y="136">Thu</text><text x="128" y="136">Fri</text><text x="172" y="136">Sat</text><text x="216" y="136">Sun</text><text x="260" y="136">Mon</text><text x="298" y="136">Tue</text></g>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return MpCard(
      child: VGap(
        gap: 12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Fasting sugar', style: tx(20, w: w700, h: 1.25))),
              const Gap(8),
              Text.rich(
                TextSpan(
                  style: tx(14, c: MP.ink2),
                  children: [
                    const TextSpan(text: 'Last 7 days · avg '),
                    TextSpan(text: '143', style: tx(14, w: w700, tab: true)),
                  ],
                ),
              ),
            ],
          ),
          Semantics(
            label: 'Fasting sugar between 138 and 150 mg/dL over 7 days, above the 130 target',
            image: true,
            child: const D6Chart(_chart, width: 310, height: 140),
          ),
        ],
      ),
    );
  }
}

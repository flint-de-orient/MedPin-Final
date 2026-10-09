import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d6.dart';

/// Design: PP-Treatment.dc.html — "Patient profile · Treatment plan".
class PpTreatmentScreen extends StatelessWidget {
  const PpTreatmentScreen({super.key});

  /// name, dose, since, adherence, colour, font size.
  static const _meds = [
    ('Metformin 500 mg', '1-0-1 · after food', 'Since Jun 2025 · ongoing', '78%', MP.amber, 16.0),
    ('Glimepiride 2 mg', '1-0-0 · before breakfast', 'Started today · 30 days', 'New', MP.ink3, 14.0),
    ('Vitamin D3 60,000 IU', 'Once a week · Sunday', 'Since 20 Jul 2026 · 8 weeks', '100%', MP.green, 16.0),
  ];

  /// label, text, label colour.
  static const _advice = [
    (
      'Diet',
      'Cut refined carbs. Three meals and two small snacks a day. Food logs reviewed by Mou Banerjee, dietician.',
      MP.ink3,
    ),
    ('Activity', 'Brisk walk for 30 minutes, 5 days a week.', MP.ink3),
    ('Monitoring', 'Check fasting sugar 3 times a week and log it in the app.', MP.ink3),
    ('Before next visit', 'HbA1c, fasting and post-meal glucose.', MP.ink3),
    ('Come in immediately if', 'Chest pain, breathlessness, or sugar below 70 mg/dL.', MP.red),
  ];

  /// doctor, where, medicine, dose, adherence, colour, font size, advice.
  static const _others = [
    (
      'Dr. Rina Mitra',
      'Cardiology · City Care · 02 Feb 2026',
      'Atorvastatin 10 mg',
      '0-0-1 · at night',
      '91%',
      MP.green,
      16.0,
      'Walk 30 minutes daily. Limit salt and fried food.',
    ),
    (
      'Dr. Nandita Gupta',
      'Gynaecology · Apollo Clinic · 18 Nov 2025',
      'Myo-inositol 2 g',
      '1-0-1 · after food',
      'Not tracked',
      MP.ink3,
      13.0,
      'Aim to lose 5% body weight in 6 months.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return D6PatientTabsPage(
      tab: 3,
      children: [
        // Plan owner
        MpCard(
          radius: 20,
          shadow: MPShadow.float,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const D6Caps('Your plan'),
                    const Gap(4),
                    Text('Dr. Arjun Sen', style: tx(20, w: w700, h: 1.25)),
                    const Gap(4),
                    Text('Updated 29 Sep 2026 · Next visit Thu, 29 Oct', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: D6Link('Edit', onTap: () => Nav.go(context, 'Consult-Advice')),
              ),
            ],
          ),
        ),

        const _Adherence(),

        // Current medications
        MpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text('Current medications', style: tx(20, w: w700, h: 1.25))),
                    const Gap(12),
                    const D6Caps('Taken'),
                  ],
                ),
              ),
              for (final m in _meds)
                D6Row(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$1, style: tx(16, w: w600)),
                            const Gap(3),
                            Text(m.$2, style: tx(14, tab: true)),
                            const Gap(3),
                            Text(m.$3, style: tx(13, c: MP.ink3)),
                          ],
                        ),
                      ),
                      const Gap(12),
                      Text(m.$4, textAlign: TextAlign.right, style: tx(m.$6, w: w700, c: m.$5, tab: true)),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Instructions & advice
        MpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Instructions & advice', style: tx(20, w: w700, h: 1.25)),
              ),
              for (final a in _advice)
                D6Row(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [D6Caps(a.$1, color: a.$3), const Gap(4), Text(a.$2, style: tx(15, h: 1.5))],
                  ),
                ),
            ],
          ),
        ),

        // From other doctors
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From other doctors', style: tx(20, w: w700, h: 1.25)),
              const Gap(4),
              Row(
                children: [
                  const Ico(I.lock, size: 16, color: MP.ink2),
                  const Gap(6),
                  Expanded(child: Text('Shared by Priya · read only', style: tx(14, c: MP.ink2))),
                ],
              ),
            ],
          ),
        ),
        for (final o in _others)
          MpCard(
            child: VGap(
              gap: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(o.$1, style: tx(16, w: w700)), const Gap(2), Text(o.$2, style: tx(14, c: MP.ink2))],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.$3, style: tx(15, w: w600)),
                            const Gap(2),
                            Text(o.$4, style: tx(13, c: MP.ink2)),
                          ],
                        ),
                      ),
                      const Gap(12),
                      Text(o.$5, textAlign: TextAlign.right, style: tx(o.$7, w: w700, c: o.$6)),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: tx(14, h: 1.5),
                    children: [
                      TextSpan(text: 'Advice:', style: tx(14, w: w600, c: MP.ink2, h: 1.5)),
                      TextSpan(text: ' ${o.$8}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adherence
// ─────────────────────────────────────────────────────────────────────────────

class _Adherence extends StatelessWidget {
  const _Adherence();

  @override
  Widget build(BuildContext context) {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Adherence', style: tx(20, w: w700, h: 1.25))),
              Text('Last 30 days', style: tx(14, c: MP.ink2)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('86%', style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                  const Gap(10),
                  Flexible(child: Text('−4 pts vs previous 30 days', style: tx(14, w: w600, c: MP.amber))),
                ],
              ),
              const Gap(10),
              Semantics(
                label: '86 percent of doses taken',
                image: true,
                child: const MpProgress(0.86, height: 8, track: MP.line),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D6Caps('This week'),
              const Gap(8),
              Semantics(
                label: 'Doses this week: morning doses all taken; evening doses missed Friday to Monday',
                image: true,
                excludeSemantics: true,
                child: const _WeekGrid(),
              ),
              const Gap(8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _legend(
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MP.greenSoft,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: MP.green),
                        ),
                      ),
                      'Taken',
                    ),
                    _legend(
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MP.amberSoft,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: MP.amber),
                        ),
                      ),
                      'Missed',
                    ),
                    _legend(const CustomPaint(size: Size(14, 14), painter: _DashedRRect(radius: 4)), 'Due later'),
                  ],
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(
                style: tx(14, h: 1.45),
                children: [
                  TextSpan(text: '4 evening doses missed', style: tx(14, w: w700, c: MP.amber, h: 1.45)),
                  const TextSpan(text: ' in a row (Fri–Mon), all Metformin.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Widget swatch, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [swatch, const Gap(6), Text(label, style: tx(13, c: MP.ink2))]);
}

/// Grid: 64px label column + 7 equal day columns, 6px gaps, 28px rows.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid();

  static const _days = ['Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue'];

  // t = taken, m = missed, d = due later.
  static const _morning = ['t', 't', 't', 't', 't', 't', 't'];
  static const _evening = ['t', 't', 'm', 'm', 'm', 'm', 'd'];

  @override
  Widget build(BuildContext context) {
    final label = tx(12, w: w600, c: MP.ink2);
    return LayoutBuilder(
      builder: (context, c) {
        final col = math.max(0.0, (c.maxWidth - 64 - 6 * 7) / 7);
        final cell = math.min(28.0, col);

        Widget row(String name, List<Widget> cells) => SizedBox(
          height: 28,
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Align(alignment: Alignment.centerLeft, child: Text(name, style: label, maxLines: 1)),
              ),
              for (final w in cells) ...[const Gap(6), SizedBox(width: col, child: Center(child: w))],
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('', [for (final d in _days) Text(d, style: label, maxLines: 1, softWrap: false)]),
            const Gap(6),
            row('Morning', [for (final k in _morning) _Dose(k, size: cell)]),
            const Gap(6),
            row('Evening', [for (final k in _evening) _Dose(k, size: cell)]),
          ],
        );
      },
    );
  }
}

class _Dose extends StatelessWidget {
  final String kind;
  final double size;
  const _Dose(this.kind, {required this.size});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 't':
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(8)),
          child: const Ico(I.check, size: 14, color: MP.green, stroke: 2.5),
        );
      case 'm':
        // 26px content box + 1px border = 28px.
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MP.amberSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MP.amber),
          ),
          child: const Ico(I.close, size: 12, color: MP.amber, stroke: 2.5),
        );
      default:
        return CustomPaint(size: Size(size, size), painter: const _DashedRRect(radius: 8));
    }
  }
}

/// 1px dashed rounded-rect outline (#69738A), like a CSS `1px dashed` border
/// (3px dashes, 2px gaps).
class _DashedRRect extends CustomPainter {
  final double radius;
  const _DashedRRect({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = MP.ink3
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius - 0.5));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 3, metric.length)), paint);
        d += 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect oldDelegate) => oldDelegate.radius != radius;
}

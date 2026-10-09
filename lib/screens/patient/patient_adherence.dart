import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Patient-Adherence.dc.html — "Patient · adherence by doctor" (sheet over 'Main').
class PatientAdherenceSheet extends StatelessWidget {
  const PatientAdherenceSheet({super.key});

  static const _docs = [
    (
      name: 'Dr. Arjun Sen',
      dept: 'Diabetes · City Care',
      pct: '82%',
      pctSize: 20.0,
      pctColor: MP.amber,
      bar: 0.82,
      barColor: MP.amber,
      meds: 'Metformin 78% · Glimepiride started today · Vitamin D3 100%',
    ),
    (
      name: 'Dr. Rina Mitra',
      dept: 'Heart · City Care',
      pct: '91%',
      pctSize: 20.0,
      pctColor: MP.green,
      bar: 0.91,
      barColor: MP.primary,
      meds: 'Atorvastatin 91%',
    ),
    (
      name: 'Dr. Nandita Gupta',
      dept: 'Gynaecology · Apollo Clinic',
      pct: 'Not tracked',
      pctSize: 14.0,
      pctColor: MP.ink3,
      bar: null,
      barColor: MP.primary,
      meds: 'Myo-inositol · turn on reminders to start tracking',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P1SheetHeader(
              title: Text('Taking your medicines', style: tx(20, w: w700, h: 1.25)),
              subtitle: Text.rich(
                TextSpan(
                  style: tx(14, c: MP.ink2),
                  children: [
                    const TextSpan(text: 'Last 30 days · '),
                    TextSpan(text: '86%', style: tx(14, w: w700, tab: true)),
                    const TextSpan(text: ' of doses taken'),
                  ],
                ),
              ),
            ),
            for (final d in _docs) ...[
              const Gap(18),
              pad(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MP.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.name, style: tx(16, w: w700)),
                                const Gap(2),
                                Text(d.dept, style: tx(13, c: MP.ink2)),
                              ],
                            ),
                          ),
                          const Gap(12),
                          Text(d.pct, style: tx(d.pctSize, w: w800, tab: true, c: d.pctColor)),
                        ],
                      ),
                      if (d.bar != null) ...[
                        const Gap(10),
                        MpProgress(d.bar!, height: 6, color: d.barColor, track: MP.line),
                      ],
                      const Gap(10),
                      Text(d.meds, style: tx(13, h: 1.45, c: MP.ink2)),
                    ],
                  ),
                ),
              ),
            ],
            const Gap(18),
            pad(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: tx(14, h: 1.45),
                          children: [
                            TextSpan(text: 'Most misses are in the evening.', style: tx(14, w: w700, h: 1.45, c: MP.amber)),
                            const TextSpan(text: ' A reminder at 8:30 PM can help.'),
                          ],
                        ),
                      ),
                    ),
                    const Gap(12),
                    P1SoftButton(
                      'Set',
                      padding: 14,
                      background: MP.white,
                      onTap: () => P1.closeWithToast(context, 'Reminder set for 8:30 PM'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

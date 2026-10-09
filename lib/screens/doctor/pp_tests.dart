import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d6.dart';

/// Design: PP-Tests.dc.html — "Patient profile · Test results".
class PpTestsScreen extends StatefulWidget {
  const PpTestsScreen({super.key});

  @override
  State<PpTestsScreen> createState() => _PpTestsScreenState();
}

class _PpTestsScreenState extends State<PpTestsScreen> {
  /// name, flag, finding, date, source.
  static const _abnormal = [
    ('Lipid profile', '2 high', 'LDL 162 · Triglycerides 210 mg/dL', '12 Mar 2026', 'SRL Diagnostics'),
    ('Diabetes panel', '2 high', 'HbA1c 7.2% · Fasting glucose 138', '18 Jul 2026', 'City Care lab'),
    ('Vitamin D (25-OH)', 'Low', '14 ng/mL · ref 30–100', '18 Jul 2026', 'Uploaded by Priya'),
  ];

  /// name, date, source.
  static const _normal = [
    ('ECG', '12 Aug 2026', 'City Care'),
    ('Kidney function test', '18 Jul 2026', 'City Care lab'),
    ('Complete blood count', '18 Jul 2026', 'City Care lab'),
    ('Thyroid profile', '10 Jan 2026', 'Uploaded by Priya'),
    ('Urine routine', '10 Jan 2026', 'City Care lab'),
  ];

  static const _filters = ['All · 8', 'Abnormal · 3', 'Normal · 5'];

  int _filter = 0;

  // There is no report-detail screen in the design yet.
  void _open(BuildContext context) => toast(context, 'Report view is not in the design yet');

  @override
  Widget build(BuildContext context) {
    return D6PatientTabsPage(
      tab: 2,
      gap: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _filters.length; i++)
              D6FilterChip(_filters[i], selected: _filter == i, onTap: () => setState(() => _filter = i)),
          ],
        ),
        const D6ShieldNote('Reports Priya has shared with you. Abnormal first.'),
        if (_filter != 2)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: D6Caps('Abnormal findings', color: MP.amber),
                ),
                for (final t in _abnormal)
                  D6Row(
                    onTap: () => _open(context),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(t.$1, style: tx(16, w: w600))),
                                  const Gap(8),
                                  D6Pill(t.$2, bg: MP.amberSoft, fg: MP.amber),
                                ],
                              ),
                              const Gap(3),
                              Text(t.$3, style: tx(14, w: w600, c: MP.amber, tab: true)),
                              const Gap(3),
                              Text('${t.$4} · ${t.$5}', style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (_filter != 1)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(padding: EdgeInsets.only(bottom: 12), child: D6Caps('Within normal range')),
                for (final t in _normal)
                  D6Row(
                    onTap: () => _open(context),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.$1, style: tx(16, w: w600)),
                              const Gap(3),
                              Text('${t.$2} · ${t.$3}', style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const D6Pill('Normal', bg: MP.greenSoft, fg: MP.green),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
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

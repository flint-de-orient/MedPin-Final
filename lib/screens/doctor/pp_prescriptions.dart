import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d6.dart';

/// Design: PP-Prescriptions.dc.html — "Patient profile · Prescriptions".
class PpPrescriptionsScreen extends StatefulWidget {
  const PpPrescriptionsScreen({super.key});

  @override
  State<PpPrescriptionsScreen> createState() => _PpPrescriptionsScreenState();
}

enum _Tag { none, latest, shared }

class _PpPrescriptionsScreenState extends State<PpPrescriptionsScreen> {
  /// date, prescriber, summary, meta, tag.
  static const _rx = [
    (
      '29 Sep 2026',
      'Dr. Arjun Sen · Endocrinology · City Care',
      'Diabetes follow-up. Glimepiride 2 mg added, Metformin continued. HbA1c and glucose tests advised.',
      '3 medicines · 3 tests · Follow-up 29 Oct',
      _Tag.latest,
    ),
    (
      '12 Mar 2026',
      'Dr. Arjun Sen · Endocrinology · City Care',
      'Sugar stable. Metformin continued. Lipid profile ordered after a high LDL reading.',
      '2 medicines · 1 test · Follow-up 12 Jun',
      _Tag.none,
    ),
    (
      '02 Feb 2026',
      'Dr. Rina Mitra · Cardiology · City Care',
      'Chest discomfort review. ECG normal. Atorvastatin 10 mg started for raised LDL.',
      '1 medicine · 1 test',
      _Tag.none,
    ),
    (
      '12 Jan 2026',
      'Dr. Arjun Sen · Endocrinology · City Care',
      'HbA1c improved to 6.8%. Metformin kept at 500 mg twice daily.',
      '1 medicine · 2 tests',
      _Tag.none,
    ),
    (
      '18 Nov 2025',
      'Dr. Nandita Gupta · Gynaecology · Apollo Clinic',
      'PCOS review. Myo-inositol started, with diet and activity advice.',
      '1 medicine · 1 test',
      _Tag.shared,
    ),
    (
      '05 Sep 2025',
      'Dr. S. Chatterjee · General medicine · scanned paper',
      'Diabetes diagnosed. Metformin 500 mg once daily started.',
      'Uploaded by Priya · 1 medicine',
      _Tag.shared,
    ),
  ];

  /// label, horizontal padding.
  static const _filters = [('All · 6', 16.0), ('This clinic · 4', 16.0), ('Shared · 2', 14.0)];

  int _filter = 0;

  bool _visible(_Tag tag) => switch (_filter) {
    1 => tag != _Tag.shared,
    2 => tag == _Tag.shared,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    return D6PatientTabsPage(
      tab: 1,
      gap: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _filters.length; i++)
              D6FilterChip(
                _filters[i].$1,
                padH: _filters[i].$2,
                selected: _filter == i,
                onTap: () => setState(() => _filter = i),
              ),
          ],
        ),
        const D6ShieldNote('Includes prescriptions Priya chose to share from other clinics.'),
        for (final r in _rx)
          if (_visible(r.$5)) _RxCard(date: r.$1, by: r.$2, summary: r.$3, meta: r.$4, tag: r.$5),
      ],
    );
  }
}

class _RxCard extends StatelessWidget {
  final String date;
  final String by;
  final String summary;
  final String meta;
  final _Tag tag;
  const _RxCard({required this.date, required this.by, required this.summary, required this.meta, required this.tag});

  @override
  Widget build(BuildContext context) {
    final pill = switch (tag) {
      _Tag.latest => const D6Pill('Latest', bg: MP.fill, fg: MP.ink2),
      _Tag.shared => const D6Pill('Shared by patient', bg: MP.primarySoft, fg: MP.primary),
      _Tag.none => null,
    };
    return MpCard(
      child: VGap(
        gap: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(date, style: tx(18, w: w700, h: 1.25, tab: true))),
                  if (pill != null) ...[const Gap(8), pill],
                ],
              ),
              const Gap(4),
              Text(by, style: tx(14, c: MP.ink2)),
            ],
          ),
          Text(summary, style: tx(15, h: 1.5)),
          Text(meta, style: tx(13, c: MP.ink3)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Tap(
                    onTap: () => Nav.go(context, 'Prescriptions'),
                    radius: 12,
                    color: MP.primarySoft,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Ico(I.eye, size: 18, color: MP.primary),
                          const Gap(8),
                          Text('View', style: tx(15, w: w600, c: MP.primary)),
                        ],
                      ),
                    ),
                  ),
                ),
                const Gap(8),
                MpIconButton(
                  I.download,
                  label: 'Download $date prescription',
                  size: 48,
                  iconSize: 20,
                  color: MP.primary,
                  background: MP.white,
                  borderColor: MP.lineStrong,
                  onTap: () => toast(context, 'Downloading $date prescription'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

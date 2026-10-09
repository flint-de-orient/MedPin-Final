import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d6.dart';

/// Design: Patient-Profile-Desk.dc.html — "Patient profile · front desk".
class PatientProfileDeskScreen extends StatelessWidget {
  const PatientProfileDeskScreen({super.key});

  /// Desk care rows: icon, title, detail, target screen.
  static const _care = [
    (I.activity, 'Record vitals', 'Last recorded today, 8:52 AM', 'Consult-Vitals'),
    (I.upload, "Upload report for today's visit", 'Nothing uploaded for this visit yet', 'Records-Add'),
    (I.calendar, 'Book follow-up', 'City Care Clinic, Salt Lake', 'Appointments'),
    (I.message, 'Message patient', "Opens Priya's conversation", 'Patient-Thread'),
    (I.eye, 'Prescriptions (view only)', 'Latest 12 Mar 2026 · Dr. Arjun Sen', 'Prescriptions'),
  ];

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader(
        'Patient profile',
        actions: [MpIconButton(I.moreVSmall, label: 'More options', filled: true)],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          const D6ProfileHero(),
          const D6ConsentNote(),
          const D6RecordCaption(),
          const D6OverviewCard(),
          const D6MeasurementsCard(),

          // Desk care (replaces prescribing for the front desk)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: D6Title('Desk care', sub: "Today's visit · 9:00 AM with Dr. Arjun Sen"),
                ),
                for (var i = 0; i < _care.length; i++)
                  D6Row(
                    padding: i == _care.length - 1
                        ? const EdgeInsets.only(top: 14)
                        : const EdgeInsets.symmetric(vertical: 14),
                    onTap: () => Nav.go(context, _care[i].$4),
                    child: Row(
                      children: [
                        Ico(_care[i].$1, size: 22, color: MP.primary),
                        const Gap(14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_care[i].$2, style: tx(16, w: w600)),
                              const Gap(2),
                              Text(_care[i].$3, style: tx(14, c: MP.ink2, h: 1.45)),
                            ],
                          ),
                        ),
                        const Gap(14),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

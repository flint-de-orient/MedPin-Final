import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Patient-Emergency.dc.html — "Patient · emergency: choose doctor" (sheet over 'Main').
class PatientEmergencySheet extends StatelessWidget {
  const PatientEmergencySheet({super.key});

  static const _doctors = [
    (initials: 'AS', name: 'Dr. Arjun Sen', dept: 'Diabetes · City Care', status: 'Available now', statusColor: MP.green, dot: MP.green),
    (
      initials: 'RM',
      name: 'Dr. Rina Mitra',
      dept: 'Heart · City Care',
      status: 'In clinic · usually replies in 15 min',
      statusColor: MP.ink2,
      dot: MP.amber,
    ),
    (
      initials: 'NG',
      name: 'Dr. Nandita Gupta',
      dept: 'Gynaecology · Apollo Clinic',
      status: 'Away · her clinic team will see it',
      statusColor: MP.ink2,
      dot: MP.lineStrong,
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
              closeWidth: 35.9,
              title: Text('Which doctor do you need?', style: tx(20, w: w700, h: 1.25)),
              subtitle: Text(
                'Your message is marked urgent and the doctor is alerted right away.',
                style: tx(14, h: 1.45, c: MP.ink2),
              ),
            ),
            const Gap(18),
            pad(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < _doctors.length; i++) _doctorRow(context, i)],
              ),
            ),
            const Gap(18),
            pad(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: MP.redSoft, borderRadius: BorderRadius.circular(12)),
                child: Text.rich(
                  TextSpan(
                    style: tx(14, h: 1.45),
                    children: [
                      TextSpan(text: 'Chest pain, trouble breathing or fainting?', style: tx(14, w: w700, h: 1.45, c: MP.red)),
                      const TextSpan(text: " Don't wait for a reply. "),
                      P1.link(
                        'Call 108',
                        style: tx(14, w: w700, h: 1.45, c: MP.red),
                        onTap: () => P1.closeWithToast(context, 'Calling 108…'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doctorRow(BuildContext context, int i) {
    final d = _doctors[i];
    return Tap(
      onTap: () => P1.closeThen(context, 'Patient-Chat'),
      radius: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                children: [
                  MpAvatar(d.initials, size: 48, fontSize: 15),
                  // 12px status dot with a 2px white ring, bottom-right.
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: d.dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: MP.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name, style: tx(16, w: w700)),
                  const Gap(2),
                  Text(d.dept, style: tx(13, c: MP.ink2)),
                  const Gap(2),
                  Text(d.status, style: tx(13, w: w600, c: d.statusColor)),
                ],
              ),
            ),
            const Gap(12),
            const Ico(I.chevronRight, size: 18, color: MP.ink3),
          ],
        ),
      ),
    );
  }
}

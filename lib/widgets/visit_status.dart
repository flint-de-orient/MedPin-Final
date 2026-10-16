import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import '../data/live.dart';
import 'i18n.dart';
import 'mp.dart';

/// A clinic visit's status, in the words the desk and doctor use for physical
/// visits: Upcoming → Arrived → With doctor → Done (or Missed / Cancelled).
String visitStatusLabel(String status) => switch (status) {
      'booked' || 'confirmed' => 'Upcoming',
      'waiting' => 'Arrived',
      'in_consultation' => 'With doctor',
      'completed' => 'Done',
      'missed' => 'Missed',
      'cancelled' => 'Cancelled',
      _ => status,
    };

/// "Change status" for a visit: only the steps that make sense from where it is
/// now (POST /api/appointments/:id/status, or …/cancel). True when it changed.
Future<bool> changeVisitStatus(BuildContext context, {required String appointmentId, required String status, String? patientName}) async {
  final options = <(String, String, String)>[
    // (new status, label, what it means)
    if (status == 'booked' || status == 'confirmed') ...[
      ('waiting', 'Arrived', 'Checked in at the clinic, waiting'),
      ('missed', 'Missed', "Didn't come"),
      ('cancelled', 'Cancel visit', 'The patient is told; a fee paid is refunded'),
    ],
    if (status == 'waiting') ...[
      ('in_consultation', 'With doctor', 'Sent in to see the doctor'),
      ('completed', 'Done', 'Seen — e.g. a paper prescription or a quick review'),
      ('missed', 'Left without being seen', 'Marked as missed'),
      ('booked', 'Undo check-in', 'Checked in by mistake'),
    ],
    if (status == 'in_consultation') ...[
      ('completed', 'Done', 'The visit is over'),
      ('waiting', 'Back to waiting', 'e.g. sent for a test first'),
    ],
    if (status == 'missed') ('waiting', 'Arrived late', 'Check them in now'),
  ];
  if (options.isEmpty) {
    toast(context, status == 'completed' ? 'This visit is done' : 'This visit can’t be changed');
    return false;
  }
  final picked = await openSheet<String>(
    context,
    (c) => MpSheet(
      title: 'Change status',
      subtitle: patientName == null
          ? tr(context, 'Now: #1').replaceFirst('#1', tr(context, visitStatusLabel(status)))
          : '$patientName · ${tr(context, 'Now: #1').replaceFirst('#1', tr(context, visitStatusLabel(status)))}',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++)
              Tap(
                onTap: () => Navigator.pop(c, options[i].$1),
                radius: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(options[i].$2, style: tx(16, w: w600, c: options[i].$1 == 'cancelled' ? MP.red : MP.ink)),
                            const Gap(2),
                            Text(options[i].$3, style: tx(13, c: MP.ink2)),
                          ],
                        ),
                      ),
                      const Ico(I.chevronRight, size: 18, color: MP.ink3),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return false;
  final ok = await runAction(
    context,
    () => picked == 'cancelled'
        ? Api.I.post('/api/appointments/$appointmentId/cancel', const {'reason': 'Cancelled by the clinic'})
        : Api.I.post('/api/appointments/$appointmentId/status', {'status': picked}),
  );
  if (ok == null || !context.mounted) return false;
  toast(context, tr(context, 'Status: #1').replaceFirst('#1', tr(context, visitStatusLabel(picked))));
  return true;
}

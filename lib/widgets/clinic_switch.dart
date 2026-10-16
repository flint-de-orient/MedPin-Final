import 'package:flutter/material.dart' hide Text;

import '../data/session.dart';
import 'i18n.dart';
import 'mp.dart';

/// A team role in plain words ("Front desk", "Doctor's assistant").
String roleLabel(String? role) => const {
      'doctor': 'Doctor',
      'front_desk': 'Front desk',
      'doctor_assistant': "Doctor's assistant",
      'dietician': 'Dietician',
      'lab_manager': 'Lab manager',
      'lab_technician': 'Lab technician',
      'practice_manager': 'Practice manager',
    }[role] ??
    'Team member';

/// Staff who work in more than one clinic choose the one to work in
/// (Profile → Clinic). Only offered with two or more active memberships.
Future<void> chooseClinic(BuildContext context) async {
  final list = Session.I.activeMemberships;
  if (list.length < 2) return;
  final current = Session.I.practiceId;
  final id = await openSheet<String>(
    context,
    (c) => MpSheet(
      title: 'Clinic',
      subtitle: 'Appointments, patients and chats are shown for the clinic you choose.',
      showClose: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in list)
            Tap(
              onTap: () => Navigator.pop(c, '${m['practiceId']}'),
              radius: 12,
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m['practiceName'] ?? ''}', style: tx(16, w: '${m['practiceId']}' == current ? w600 : w400)),
                          const Gap(2),
                          Text(roleLabel(m['role'] as String?), style: tx(14, c: MP.ink2)),
                        ],
                      ),
                    ),
                    if ('${m['practiceId']}' == current) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  await switchToClinic(context, id);
}

/// Works in clinic [id] from now on (Session.I.usePractice): screens reload,
/// and when the first screen differs there (a doctor in one clinic, front desk
/// in another) the app starts again on it. For a notification from another
/// clinic, call this before opening its screen. Returns false when [id] isn't
/// one of this person's clinics.
Future<bool> switchToClinic(BuildContext context, String id) async {
  final before = Session.I.landing;
  final was = Session.I.practiceId;
  if (!await Session.I.usePractice(id)) return false;
  if (!context.mounted || was == id) return true;
  toast(context, tr(context, 'Now working in #1').replaceFirst('#1', Session.I.practiceName(id) ?? ''));
  if (Session.I.landing != before) Nav.reset(context, Session.I.landing);
  return true;
}

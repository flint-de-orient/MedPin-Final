import 'package:flutter/widgets.dart';

import '../core/nav.dart';
import 'session.dart';

/// Where a staff notification opens for the person signed in.
///
/// The server names one screen for everyone it tells; a role that can't use
/// that screen gets the one that does the same job for them, so no tap ends
/// on a doctor-only page:
/// - front desk on an emergency / clinical alert → the patient's chat (they
///   don't have Clinical alerts; the chat has Call the patient · Doctor informed);
/// - fees and refunds → Payments for the desk (Fees report for doctors);
/// - the doctor's own pages (dashboard, my patients, payouts, the queue) → none
///   or the desk's Today.
/// null: nothing to open (the notification is just information).
({String screen, Map<String, dynamic>? args})? staffNotificationTarget(String screen, String type, Map<String, dynamic>? params) {
  final p = params ?? const <String, dynamic>{};
  final role = Session.I.role;
  final doctor = role == 'doctor';
  final desk = const {'front_desk', 'practice_manager', 'doctor_assistant'}.contains(role);
  String? s = screen.isEmpty ? null : screen;
  if (desk && Session.I.can('fees') && RegExp(r'fee_|refund').hasMatch(type)) s = 'Staff-Payments';
  if (s == 'Alerts' && !Session.I.can('alerts')) s = p['conversationId'] != null || p['patientId'] != null ? 'Patient-Thread' : null;
  if (s == 'Report-Fees' && !Session.I.can('reports')) s = Session.I.can('fees') ? 'Staff-Payments' : null;
  if (!doctor && const {'Doctor-Dashboard', 'Doctor-Patients', 'Profile-Payouts', 'Profile-Professional'}.contains(s)) s = null;
  if (!doctor && s == 'Queue-List') s = 'Staff-Today';
  if (s == null || Nav.spec(s) == null || Nav.spec(s)!.panel == 'patient') return null;
  return (screen: s, args: p.isEmpty ? null : p);
}

/// Opens a staff notification: first switches to its clinic when it is from
/// another of my clinics (staff in two practices), then its screen.
/// [practiceId]: the notification's clinic (null / mine: no switch).
Future<void> openStaffNotification(BuildContext context, {required String screen, required String type, Map<String, dynamic>? params, String? practiceId}) async {
  var ctx = context;
  final pid = practiceId ?? '';
  if (pid.isNotEmpty && pid != Session.I.practiceId) {
    final before = Session.I.landing;
    final switched = await Session.I.usePractice(pid);
    if (!switched || !ctx.mounted) return;
    // A different role there (doctor in one clinic, front desk in the other): start on its first screen.
    if (Session.I.landing != before) {
      Nav.reset(ctx, Session.I.landing);
      ctx = Nav.key.currentContext ?? ctx;
    }
  }
  if (!ctx.mounted) return;
  final t = staffNotificationTarget(screen, type, params);
  if (t == null) return;
  await Nav.go(ctx, t.screen, args: t.args);
}

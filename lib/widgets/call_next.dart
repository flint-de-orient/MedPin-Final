import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import 'i18n.dart';
import 'mp.dart';

/// "Call next" (a clinic setting, on by default): tells the next waiting patient — or the
/// visit [appointmentId] ("Call again") — that it's their turn. With several doctors'
/// patients waiting, asks whose. True when someone was called (the list should refresh).
/// POST /api/queue/call-next, POST /api/appointments/:id/call.
Future<bool> callNextPatient(BuildContext context, {String? appointmentId, String? locationId, String? doctorId}) async {
  Object? res;
  try {
    res = appointmentId != null
        ? await Api.I.post('/api/appointments/$appointmentId/call', const {})
        : await Api.I.post('/api/queue/call-next', {if (locationId != null) 'locationId': locationId, if (doctorId != null) 'doctorId': doctorId});
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (e.code == 'CHOOSE_DOCTOR') {
      final choices = [for (final c in (e.details?['choices'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
      final pick = await openSheet<String>(
        context,
        (c) => MpSheet(
          title: 'Call the next patient of',
          showClose: true,
          child: Column(children: [
            for (final d in choices)
              Tap(
                onTap: () => Navigator.pop(c, '${d['doctorId']}'),
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Row(children: [
                  Expanded(child: Text('${d['doctorName'] ?? 'Doctor'}', style: tx(16, w: w600))),
                  Text(tr(context, '#1 waiting').replaceFirst('#1', '${d['waiting'] ?? ''}'), style: tx(13, c: MP.ink2)),
                ]),
              ),
          ]),
        ),
      );
      if (pick == null || !context.mounted) return false;
      return callNextPatient(context, locationId: locationId, doctorId: pick);
    }
    toast(context, e.message);
    return false;
  }
  if (res is! Map || !context.mounted) return false;
  final who = '${res['patient'] ?? ''}';
  final token = res['token'] == null ? '' : ' · ${tr(context, 'Token')} ${'${res['token']}'.padLeft(2, '0')}';
  toast(
    context,
    res['hasApp'] == true
        ? '${trf(context, "{name} was told it's their turn", {'name': who})}$token'
        : '${trf(context, 'Call {name} in (no MedPin app)', {'name': who})}$token',
  );
  return true;
}

/// "Running late": tells every patient still to come today that the doctor is about N minutes
/// late (in the app and on WhatsApp). The doctor's own, or (desk) the doctor chosen.
/// POST /api/queue/running-late.
Future<void> tellRunningLate(BuildContext context, {String? doctorId, String? locationId}) async {
  final minutes = await openSheet<int>(
    context,
    (c) => MpSheet(
      title: 'Running late',
      subtitle: "Patients still to come today are told, so they don't wait long at the clinic.",
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const [15, 30, 45, 60, 90]) MpChip(tr(context, '#1 min late').replaceFirst('#1', '$m'), onTap: () => Navigator.pop(c, m)),
        ]),
      ),
    ),
  );
  if (minutes == null || !context.mounted) return;
  try {
    final res = await Api.I.post('/api/queue/running-late', {'minutes': minutes, if (doctorId != null) 'doctorId': doctorId, if (locationId != null) 'locationId': locationId}) as Map;
    if (!context.mounted) return;
    final told = (res['told'] as num?)?.toInt() ?? 0;
    final without = (res['withoutApp'] as num?)?.toInt() ?? 0;
    toast(
      context,
      told == 0 && without == 0
          ? tr(context, 'Nobody else is booked for today')
          : [if (told > 0) tr(context, '#1 patients told').replaceFirst('#1', '$told'), if (without > 0) tr(context, '#1 without the app: call them').replaceFirst('#1', '$without')].join(' · '),
    );
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
  }
}

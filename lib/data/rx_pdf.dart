import 'package:flutter/material.dart';

import '../widgets/mp.dart';
import 'api.dart';
import 'config.dart';
import 'downloads.dart';

/// A prescription's PDF: View opens it in the phone's PDF viewer, Download
/// saves it to Downloads › MedPin with a small "Saved" note.
///
/// The link comes fresh from GET /api/prescriptions/:id/pdf (clinic) or
/// /api/patient/prescriptions/:id/pdf (patient): signed links expire after an
/// hour, and older prescriptions are drawn again in the current layout.
class RxPdf {
  RxPdf._();

  static Future<Map<String, dynamic>?> _link(BuildContext context, String id, bool patient) async {
    try {
      final r = await Api.I.get(patient ? '/api/patient/prescriptions/$id/pdf' : '/api/prescriptions/$id/pdf');
      return r is Map ? r.cast<String, dynamic>() : null;
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.status == 404 ? 'No PDF for this prescription yet' : e.message);
      return null;
    }
  }

  static Future<void> view(BuildContext context, String? id, {bool patient = false}) async {
    if (AppMode.preview) return toast(context, 'Opening prescription');
    if (id == null || id.isEmpty) return toast(context, 'No PDF for this prescription yet');
    toast(context, 'Opening…');
    final f = await _link(context, id, patient);
    if (f == null || !context.mounted) return;
    await Downloads.open(context, f['url'] as String?, name: f['name'] as String?);
  }

  static Future<void> download(BuildContext context, String? id, {bool patient = false}) async {
    if (AppMode.preview) return toast(context, 'Prescription downloaded');
    if (id == null || id.isEmpty) return toast(context, 'No PDF for this prescription yet');
    final f = await _link(context, id, patient);
    if (f == null || !context.mounted) return;
    await Downloads.save(context, f['url'] as String?, name: f['name'] as String?, title: 'Prescription downloaded');
  }
}

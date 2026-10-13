import 'package:flutter/material.dart' hide Text;

import '../widgets/mp.dart';
import 'api.dart';
import 'config.dart';
import 'downloads.dart';
import 'session.dart';
import '../widgets/i18n.dart';

/// A prescription's PDF: View opens it in the phone's PDF viewer, Download
/// saves it to Downloads › MedPin with a small "Saved" note.
///
/// The link comes fresh from GET /api/prescriptions/:id/pdf (clinic) or
/// /api/patient/prescriptions/:id/pdf (patient): signed links expire after an
/// hour, and older prescriptions are drawn again in the current layout.
///
/// Patients choose the language first (English, বাংলা, हिन्दी): instructions
/// and advice in their language, medicine names stay in English.
class RxPdf {
  RxPdf._();

  static const _langs = [('en', 'English', 'As the doctor wrote it'), ('bn', 'বাংলা', 'Bengali · medicine names in English'), ('hi', 'हिन्दी', 'Hindi · medicine names in English')];

  /// The last language chosen (else the app's language).
  static String? _last;

  static Future<String?> _pickLang(BuildContext context, String action) {
    final current = _last ?? (const ['bn', 'hi'].contains(Session.I.user['language']) ? '${Session.I.user['language']}' : 'en');
    return openSheet<String>(
      context,
      (c) => MpSheet(
        title: action,
        subtitle: 'Choose the language you are most comfortable reading.',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _langs.length; i++) ...[
                if (i > 0) const MpDivider(),
                Tap(
                  onTap: () => Navigator.pop(c, _langs[i].$1),
                  radius: 0,
                  child: SizedBox(
                    height: 64,
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_langs[i].$2, style: tx(16, w: w600)),
                            Text(_langs[i].$3, style: tx(13, c: MP.ink3)),
                          ],
                        ),
                      ),
                      if (_langs[i].$1 == current) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Future<Map<String, dynamic>?> _link(BuildContext context, String id, bool patient, [String lang = 'en']) async {
    try {
      final r = await Api.I.get(patient ? '/api/patient/prescriptions/$id/pdf' : '/api/prescriptions/$id/pdf', query: patient && lang != 'en' ? {'lang': lang} : null);
      return r is Map ? r.cast<String, dynamic>() : null;
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.status == 404 ? 'No PDF for this prescription yet' : e.message);
      return null;
    }
  }

  static Future<void> view(BuildContext context, String? id, {bool patient = false}) async {
    if (AppMode.preview) return toast(context, 'Opening prescription');
    if (id == null || id.isEmpty) return toast(context, 'No PDF for this prescription yet');
    final lang = patient ? await _pickLang(context, 'Open prescription in') : 'en';
    if (lang == null || !context.mounted) return;
    _last = patient ? lang : _last;
    toast(context, lang == 'en' ? 'Opening…' : 'Preparing it in your language…');
    final f = await _link(context, id, patient, lang);
    if (f == null || !context.mounted) return;
    await Downloads.open(context, f['url'] as String?, name: f['name'] as String?);
  }

  static Future<void> download(BuildContext context, String? id, {bool patient = false}) async {
    if (AppMode.preview) return toast(context, 'Prescription downloaded');
    if (id == null || id.isEmpty) return toast(context, 'No PDF for this prescription yet');
    final lang = patient ? await _pickLang(context, 'Download prescription in') : 'en';
    if (lang == null || !context.mounted) return;
    _last = patient ? lang : _last;
    if (lang != 'en') toast(context, 'Preparing it in your language…');
    final f = await _link(context, id, patient, lang);
    if (f == null || !context.mounted) return;
    await Downloads.save(context, f['url'] as String?, name: f['name'] as String?, title: 'Prescription downloaded');
  }
}

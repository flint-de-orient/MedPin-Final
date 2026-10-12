import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';
import 'common_d4.dart';

/// Like runAction, for issuing / sending prescriptions: when the server says
/// the doctor's signature is missing (SIGNATURE_REQUIRED), asks for it right
/// there, uploads it, and tries once more. Other errors are shown as a toast.
Future<T?> withSignature<T>(BuildContext context, Future<T> Function() action, {ValueNotifier<bool>? busy}) async {
  Future<T?> attempt() async {
    if (busy?.value == true) return null;
    busy?.value = true;
    try {
      return await action();
    } finally {
      busy?.value = false;
    }
  }

  try {
    return await attempt();
  } on ApiException catch (e) {
    if (e.code != 'SIGNATURE_REQUIRED') {
      if (context.mounted) toast(context, e.message);
      return null;
    }
    if (!context.mounted || !await addSignature(context) || !context.mounted) return null;
    try {
      return await attempt();
    } on ApiException catch (e2) {
      if (context.mounted) toast(context, e2.message);
      return null;
    }
  }
}

/// "Add your digital signature" → photo of the signature → uploaded.
/// Returns true when it was saved.
Future<bool> addSignature(BuildContext context) async {
  final go = await d4Confirm(
    context,
    title: 'Add your digital signature',
    body: 'It is printed on every prescription. Sign on plain white paper and take a clear photo, or choose a PNG.',
    confirm: 'Add signature',
  );
  if (!go || !context.mounted) return false;
  return chooseAndUploadSignature(context);
}

/// Picks a photo of the signature and sends it through the signature checker
/// (POST /api/doctor/profile/signature):
/// - refused (blurred, not on plain paper, not a signature…): says why, offers another photo;
/// - doubts (reads as another name, faint, cut off): shows them, "Use anyway" sends it again with accept;
/// - fine: saved (the cleaned, transparent version prints).
/// Returns true once a signature is saved.
Future<bool> chooseAndUploadSignature(BuildContext context, {ValueNotifier<bool>? busy}) async {
  while (true) {
    if (!context.mounted) return false;
    final file = await Files.chooseSource(context, title: 'Digital signature', allowPdf: false);
    if (file == null || !context.mounted) return false;
    var accept = false;
    while (true) {
      busy?.value = true;
      try {
        await Api.I.upload('/api/doctor/profile/signature', files: {'file': [file]}, fields: {if (accept) 'accept': 'true'});
        if (context.mounted) toast(context, 'Signature saved · printed on every prescription');
        return true;
      } on ApiException catch (e) {
        if (!context.mounted) return false;
        final issues = [for (final i in (e.details?['issues'] as List? ?? const [])) (i as Map).cast<String, dynamic>()];
        if (e.code == 'SIGNATURE_REJECTED') {
          final again = await openSheet<bool>(context, (_) => _CheckSheet(issues: issues, rejected: true));
          if (again != true || !context.mounted) return false;
          break; // choose another photo
        }
        if (e.code == 'SIGNATURE_CHECK') {
          final r = await openSheet<String>(context, (_) => _CheckSheet(issues: issues, rejected: false));
          if (r == 'accept') {
            accept = true;
            continue;
          }
          if (r == 'another' && context.mounted) break;
          return false;
        }
        toast(context, e.message);
        return false;
      } finally {
        busy?.value = false;
      }
    }
  }
}

/// What the signature checker found, with the way forward.
class _CheckSheet extends StatelessWidget {
  final List<Map<String, dynamic>> issues;
  final bool rejected;
  const _CheckSheet({required this.issues, required this.rejected});

  @override
  Widget build(BuildContext context) => MpSheet(
        title: rejected ? "This photo can't be used" : 'Check this signature',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in issues) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Ico(I.alert, size: 18, color: i['severity'] == 'block' ? MP.red : MP.amber),
                  ),
                  const Gap(10),
                  Expanded(child: Text('${i['message'] ?? ''}', style: tx(15, h: 1.45))),
                ],
              ),
              const Gap(12),
            ],
            const Gap(4),
            if (rejected)
              MpButton('Choose another photo', onTap: () => Navigator.pop(context, true))
            else ...[
              MpButton('Choose another photo', onTap: () => Navigator.pop(context, 'another')),
              const Gap(10),
              MpButton("It's my signature · use it", kind: MpBtn.secondary, onTap: () => Navigator.pop(context, 'accept')),
            ],
          ],
        ),
      );
}

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/files.dart';
import '../../widgets/mp.dart';
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
  final file = await Files.chooseSource(context, title: 'Digital signature', allowPdf: false);
  if (file == null || !context.mounted) return false;
  try {
    await Api.I.upload('/api/doctor/profile/signature', files: {'file': [file]});
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
  if (context.mounted) toast(context, 'Signature saved');
  return true;
}

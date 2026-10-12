import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/firebase_phone.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';

/// Sign in and Register share one phone check: text a code, then Auth-OTP.

/// Sends a code to [digits] (10-digit Indian mobile) and opens Auth-OTP.
/// Returns false when the code could not be sent (a toast says why).
Future<bool> sendSignInCode(BuildContext context, String digits) async {
  if (AppMode.preview) {
    Nav.go(context, 'Auth-OTP');
    return true;
  }
  try {
    final res = await Api.I.post('/api/auth/otp/request', {'phone': digits}) as Map;
    final s = Session.I
      ..pendingPhone = digits
      ..pendingMaskedPhone = res['maskedPhone'] as String?
      ..pendingResendIn = (res['resendInSec'] as num?)?.toInt() ?? 30
      ..pendingDevCode = res['devCode'] as String?
      ..pendingMethod = res['method'] == 'firebase' ? 'firebase' : 'server';
    if (s.pendingMethod == 'firebase') {
      // Firebase texts the code; Android may also read it and sign in by itself.
      await FirebasePhone.I.sendCode(digits, onAutoVerified: _signedInAutomatically);
    }
    if (!context.mounted) return false;
    if (s.pendingDevCode != null) toast(context, 'Test code: ${s.pendingDevCode}');
    Nav.go(context, 'Auth-OTP');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
}

Future<void> _signedInAutomatically(Map<String, dynamic> body) async {
  final note = await finishSignIn(body);
  final ctx = Nav.key.currentContext;
  if (ctx == null || !ctx.mounted) return;
  Nav.reset(ctx, Session.I.landing == 'Auth-Welcome' && note != null ? 'Auth-Patient-Setup' : Session.I.landing);
  if (note != null) toast(ctx, note);
}

/// Saves a verified sign-in. After Register it also creates the patient
/// profile with the details typed there. Returns a note to show, if any.
Future<String?> finishSignIn(Map<String, dynamic> body) async {
  final signup = Session.I.pendingSignup;
  Session.I.pendingSignup = null;
  await Session.I.signIn(body);
  if (signup == null) return null;
  if (Session.I.patientId != null) return 'You already have a MedPin account. You are signed in.';
  if (Session.I.memberships.isNotEmpty) return 'This number is already set up for a clinic. You are signed in.';
  try {
    await Api.I.post('/api/patient/register', signup);
    await Session.I.reloadAccount();
    return null;
  } on ApiException catch (e) {
    // Signed in but no profile yet: Auth-Patient-Setup asks again.
    return e.message;
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// Firebase Phone Authentication: Firebase sends the SMS code and checks it;
/// the backend then signs the user in with Firebase's ID token.
///
/// Used when the backend answers `method: firebase` to a code request.
/// Only set up on Android (google-services.json); elsewhere the backend's own
/// codes are used.
class FirebasePhone {
  FirebasePhone._();
  static final FirebasePhone I = FirebasePhone._();

  bool ready = false;
  String? _verificationId;
  int? _resendToken;

  /// Called once at start-up. Never throws: without Firebase the app still works.
  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
      ready = true;
    } catch (e) {
      debugPrint('Firebase not available: $e');
    }
  }

  /// Asks Firebase to text a code to [phone] (10 digits, India).
  /// [onAutoVerified] runs if Android reads the SMS by itself and signs in.
  Future<void> sendCode(String phone, {bool resend = false, void Function(Map<String, dynamic> session)? onAutoVerified}) async {
    if (!ready) throw const ApiException(0, 'FIREBASE_UNAVAILABLE', 'SMS sign-in is not available on this device.');
    final done = Completer<void>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91$phone',
      forceResendingToken: resend ? _resendToken : null,
      timeout: const Duration(seconds: 60),
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!done.isCompleted) done.complete();
      },
      codeAutoRetrievalTimeout: (verificationId) => _verificationId = verificationId,
      verificationCompleted: (credential) async {
        // Android verified the SMS automatically.
        try {
          final session = await _exchange(credential);
          onAutoVerified?.call(session);
        } catch (e) {
          debugPrint('Auto sign-in failed: $e');
        }
        if (!done.isCompleted) done.complete();
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(_friendly(e));
      },
    );
    return done.future;
  }

  /// Checks the 6-digit [code] with Firebase and signs in with the backend.
  /// Returns the backend's sign-in response (tokens + account).
  Future<Map<String, dynamic>> verify(String code) async {
    final id = _verificationId;
    if (id == null) throw const ApiException(400, 'NO_CODE', 'Ask for a new code first.');
    try {
      return await _exchange(PhoneAuthProvider.credential(verificationId: id, smsCode: code));
    } on FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  Future<Map<String, dynamic>> _exchange(PhoneAuthCredential credential) async {
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    final idToken = await result.user?.getIdToken();
    if (idToken == null) throw const ApiException(401, 'FIREBASE_NO_TOKEN', 'Sign-in failed. Please try again.');
    final body = await Api.I.post('/api/auth/firebase', {'idToken': idToken}) as Map;
    // The backend session is what the app uses from here on.
    await FirebaseAuth.instance.signOut();
    return body.cast<String, dynamic>();
  }

  static ApiException _friendly(FirebaseAuthException e) {
    // Phone sign-in not enabled in the Firebase project (Authentication → Sign-in method → Phone).
    if ('${e.message}'.contains('CONFIGURATION_NOT_FOUND')) {
      return const ApiException(400, 'FIREBASE_NOT_CONFIGURED', 'SMS sign-in is not switched on in Firebase yet. Enable Phone sign-in in the Firebase console.');
    }
    final message = switch (e.code) {
      'invalid-verification-code' => "That code isn't right",
      'session-expired' || 'code-expired' => 'The code has expired. Ask for a new one.',
      'too-many-requests' => 'Too many tries. Please wait a while and try again.',
      'invalid-phone-number' => 'Enter a 10-digit mobile number',
      'quota-exceeded' => 'SMS limit reached for now. Please try again later.',
      'network-request-failed' => "Can't reach the SMS service. Check your internet connection.",
      'app-not-authorized' || 'missing-client-identifier' || 'invalid-app-credential' =>
        'This app isn’t registered for SMS sign-in yet (add its SHA fingerprints in Firebase).',
      _ => e.message ?? 'Could not send the code. Please try again.',
    };
    return ApiException(400, 'FIREBASE_${e.code}', message);
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Where the session is kept between launches.
abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Keychain / Keystore (encrypted storage on web and desktop).
class SecureSessionStore implements SessionStore {
  static const _key = 'medpin.session';
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySessionStore implements SessionStore {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async => _value = value;
  @override
  Future<void> clear() async => _value = null;
}

/// The signed-in account: tokens, memberships and the patient profile id.
class Session extends ChangeNotifier {
  Session._();
  static final Session I = Session._();

  SessionStore store = SecureSessionStore();

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? account;

  /// The number a code was just sent to (between Login and OTP).
  String? pendingPhone;
  String? pendingMaskedPhone;
  int pendingResendIn = 30;

  /// 'firebase' when Firebase texts the code, 'server' when the backend does.
  String pendingMethod = 'server';

  /// Code returned by the API for test numbers / dev mode (never in production).
  String? pendingDevCode;

  /// Details typed on Register (name, gender, age) waiting for the phone to
  /// be verified; the patient profile is created right after the code.
  Map<String, dynamic>? pendingSignup;

  bool get signedIn => refreshToken != null && account != null;

  /// True when this session was restored from storage at app launch (the app
  /// lock asks to unlock then; a fresh sign-in doesn't need it).
  bool restoredAtLaunch = false;

  Map<String, dynamic> get user => (account?['user'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get name => (user['name'] as String?)?.trim() ?? '';
  String get phone => (user['phone'] as String?) ?? '';

  List<Map<String, dynamic>> get memberships =>
      [for (final m in (account?['memberships'] as List? ?? const [])) (m as Map).cast<String, dynamic>()];

  Map<String, dynamic>? get activeMembership {
    for (final m in memberships) {
      if (m['status'] == 'active') return m;
    }
    return null;
  }

  String? get practiceId => activeMembership?['practiceId'] as String?;
  String? get role => activeMembership?['role'] as String?;
  bool get isOwner => activeMembership?['isOwner'] == true;

  /// Whether the active role may do [perm] (backend ROLE_PERMISSIONS, e.g.
  /// 'prescribe', 'alerts', 'ai', 'reports'). Owners run their practice.
  bool can(String perm) {
    final perms = (activeMembership?['permissions'] as Map?) ?? const {};
    if (perms.isEmpty) return role == 'doctor'; // older sessions: doctors could do everything
    return perms[perm] == true || (isOwner && perm != 'prescribe');
  }
  String? get patientId => account?['patientId'] as String?;

  /// The first screen for this account: Doctor-Dashboard, Staff-Today, Main or Auth-Welcome.
  String get landing => (account?['landing'] as String?) ?? 'Auth-Login';

  /// Loads the saved session and checks it with the server.
  /// Returns false when the user has to sign in.
  Future<bool> restore() async {
    try {
      final raw = await store.read();
      if (raw == null) return false;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      accessToken = data['accessToken'] as String?;
      refreshToken = data['refreshToken'] as String?;
      account = (data['account'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      await _clearLocal();
      return false;
    }
    if (refreshToken == null) return false;
    try {
      final fresh = await Api.I.get('/api/auth/session');
      account = (fresh as Map).cast<String, dynamic>();
      await _save();
      restoredAtLaunch = true;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      // Offline: keep the saved account so the app still opens.
      if (e.isNetwork && account != null) {
        restoredAtLaunch = true;
        notifyListeners();
        return true;
      }
      await _clearLocal();
      return false;
    }
  }

  /// Saves the result of a successful OTP verification.
  Future<void> signIn(Map<String, dynamic> body) async {
    accessToken = body['accessToken'] as String?;
    refreshToken = body['refreshToken'] as String?;
    account = {
      for (final k in ['user', 'memberships', 'patientId', 'landing']) k: body[k],
    };
    pendingPhone = pendingMaskedPhone = pendingDevCode = null;
    restoredAtLaunch = false;
    await _save();
    notifyListeners();
  }

  /// Applies account fields just saved with PATCH /api/me (name, email,
  /// language, appLock) so the app lock and greetings follow at once.
  Future<void> patchUser(Map<String, dynamic> fields) async {
    if (account == null) return;
    final u = Map<String, dynamic>.from(user);
    for (final k in const ['name', 'email', 'language', 'appLock']) {
      if (fields.containsKey(k)) u[k] = fields[k];
    }
    account = {...account!, 'user': u};
    await _save();
    notifyListeners();
  }

  /// Uses an account summary an API call returned (e.g. after a new photo).
  Future<void> adoptAccount(Map<String, dynamic> body) async {
    if (account == null) return;
    account = {
      ...account!,
      for (final k in ['user', 'memberships', 'patientId', 'landing'])
        if (body.containsKey(k)) k: body[k],
    };
    await _save();
    notifyListeners();
  }

  /// Re-reads the account (after registering, joining a practice…).
  Future<void> reloadAccount() async {
    account = ((await Api.I.get('/api/auth/session')) as Map).cast<String, dynamic>();
    await _save();
    notifyListeners();
  }

  /// Device details sent with sign-in, shown in "Signed-in devices".
  static Map<String, String> get deviceInfo {
    final p = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      _ => 'web',
    };
    final name = switch (p) { 'android' => 'Android phone', 'ios' => 'iPhone', 'windows' => 'Windows PC', _ => 'Web browser' };
    return {'platform': kIsWeb ? 'web' : p, 'deviceName': kIsWeb ? 'Web browser' : 'MedPin on $name'};
  }

  Future<bool>? _refreshing;

  /// Gets a new access token with the refresh token. Returns false if signed out.
  ///
  /// Only one refresh runs at a time: screens often fire several requests at
  /// once, and each would otherwise spend the same (single-use) refresh token.
  Future<bool> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    final token = refreshToken;
    if (token == null) return false;
    try {
      final body = await Api.I.post('/api/auth/refresh', {'refreshToken': token}) as Map;
      accessToken = body['accessToken'] as String?;
      refreshToken = body['refreshToken'] as String?;
      await _save();
      return true;
    } on ApiException catch (e) {
      if (e.code == 'REFRESH_RACE') return _adoptSavedToken(token);
      return e.isNetwork; // a network blip shouldn't sign the user out
    }
  }

  /// Another request already rotated the token: use the one it saved.
  Future<bool> _adoptSavedToken(String spent) async {
    if (refreshToken != null && refreshToken != spent) return true;
    try {
      final raw = await store.read();
      if (raw == null) return false;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final saved = data['refreshToken'] as String?;
      if (saved == null || saved == spent) return false;
      accessToken = data['accessToken'] as String?;
      refreshToken = saved;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The server no longer accepts this session.
  Future<void> expire() async {
    await _clearLocal();
    notifyListeners();
  }

  /// This phone's push token, sent on sign-out so the backend stops pushing to it.
  String? Function() deviceToken = () => null;

  Future<void> logout() async {
    final token = refreshToken;
    if (token != null) {
      try {
        await Api.I.post('/api/auth/logout', {'refreshToken': token, if (deviceToken() != null) 'deviceToken': deviceToken()});
      } catch (_) {
        // Signing out locally is enough if the server can't be reached.
      }
    }
    await _clearLocal();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await store.write(jsonEncode({'accessToken': accessToken, 'refreshToken': refreshToken, 'account': account}));
    } catch (e) {
      debugPrint('Session not saved: $e');
    }
  }

  Future<void> _clearLocal() async {
    accessToken = refreshToken = null;
    pendingSignup = null;
    account = null;
    try {
      await store.clear();
    } catch (_) {}
  }
}

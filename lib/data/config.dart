import 'package:flutter/foundation.dart';

/// Build-time settings (pass with `--dart-define`).
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000
///   flutter run --dart-define=MEDPIN_PREVIEW=true   # design launcher, no backend
class AppConfig {
  AppConfig._();

  static const _baseUrl = String.fromEnvironment('API_BASE_URL');

  /// Opens the design launcher after the splash instead of the real sign-in.
  static const previewLauncher = bool.fromEnvironment('MEDPIN_PREVIEW');

  /// The MedPin API. Defaults to the backend running on this computer:
  /// the Android emulator reaches it at 10.0.2.2, everything else at localhost.
  static String get apiBaseUrl {
    if (_baseUrl.isNotEmpty) return _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }
}

/// Whether screens run against the backend or show the design's sample data.
class AppMode {
  AppMode._();

  /// True inside the design launcher / screen gallery (and widget tests):
  /// screens keep their built-in sample data and sign-in needs no backend.
  static bool preview = false;
}

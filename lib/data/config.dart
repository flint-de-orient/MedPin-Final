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

  /// The MedPin API. Without API_BASE_URL a debug build uses the backend on
  /// this computer at localhost:4000; a phone or emulator reaches it after
  /// `adb reverse tcp:4000 tcp:4000`. (10.0.2.2 only works on the emulator,
  /// so a phone build pointed there just times out.)
  ///
  /// Release builds must be given the real HTTPS address:
  ///   flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
  static String get apiBaseUrl {
    if (_baseUrl.isNotEmpty) return _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return 'http://localhost:4000';
  }

  /// A release build without a server address cannot work (see [apiBaseUrl]).
  static bool get missingReleaseServer => kReleaseMode && _baseUrl.isEmpty;
}

/// Whether screens run against the backend or show the design's sample data.
class AppMode {
  AppMode._();

  /// True inside the design launcher / screen gallery (and widget tests):
  /// screens keep their built-in sample data and sign-in needs no backend.
  static bool preview = false;
}

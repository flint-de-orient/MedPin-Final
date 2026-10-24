import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The sound a medicine alarm rings with (Profile › Alarm sound), chosen on this phone —
/// for every profile on it. The phone's alarm (default), its ringtone or notification
/// sound, three MedPin tones (res/raw), or any alarm / ringtone picked from the phone.
///
/// Android fixes a notification channel's sound when the channel is made, so each sound
/// rings through a channel of its own ("medpin_doses_ring" for the phone's alarm,
/// "medpin_doses_ring_" + the sound for the others); choosing another removes the old one and
/// the alarms are scheduled again (MedAlarms).
class AlarmSound {
  final String key; // alarm · ringtone · notification · chime · bell · beeps · phone
  final String title;
  final String? uri; // a sound picked from the phone (content://…)
  const AlarmSound(this.key, this.title, {this.uri});

  static const _pkg = 'com.fdo.medpin';
  static const _channel = MethodChannel('medpin/sound');
  static const _storage = FlutterSecureStorage();
  static const _storeKey = 'medpin_alarm_sound';

  /// What can be chosen (the phone's own pick comes from [pickFromPhone]).
  static const builtIn = [
    AlarmSound('alarm', "Phone's alarm sound"),
    AlarmSound('chime', 'MedPin chime'),
    AlarmSound('bell', 'MedPin soft bell'),
    AlarmSound('beeps', 'MedPin beeps'),
    AlarmSound('ringtone', "Phone's ringtone"),
    AlarmSound('notification', "Phone's notification sound"),
  ];
  static const fallback = AlarmSound('alarm', "Phone's alarm sound");

  static AlarmSound current = fallback;

  /// The sound as Android plays it (also for the preview).
  String get playUri => switch (key) {
        'ringtone' => 'content://settings/system/ringtone',
        'notification' => 'content://settings/system/notification_sound',
        'chime' => 'android.resource://$_pkg/raw/medpin_chime',
        'bell' => 'android.resource://$_pkg/raw/medpin_bell',
        'beeps' => 'android.resource://$_pkg/raw/medpin_beeps',
        'phone' => uri ?? 'content://settings/system/alarm_alert',
        _ => 'content://settings/system/alarm_alert',
      };

  AndroidNotificationSound get notificationSound => switch (key) {
        'chime' => const RawResourceAndroidNotificationSound('medpin_chime'),
        'bell' => const RawResourceAndroidNotificationSound('medpin_bell'),
        'beeps' => const RawResourceAndroidNotificationSound('medpin_beeps'),
        _ => UriAndroidNotificationSound(playUri),
      };

  /// The ringing channel for this sound ("medpin_doses_ring" for the phone's alarm).
  String get channelId => key == 'alarm' ? 'medpin_doses_ring' : 'medpin_doses_ring_${key == 'phone' ? (uri ?? '').hashCode.toUnsigned(32).toRadixString(36) : key}';

  Map<String, String> toJson() => {'key': key, 'title': title, if (uri != null) 'uri': uri!};

  static AlarmSound fromJson(Map m) {
    final key = '${m['key'] ?? 'alarm'}';
    if (key == 'phone' && m['uri'] is String) return AlarmSound('phone', '${m['title'] ?? 'Sound from this phone'}', uri: m['uri'] as String);
    return builtIn.firstWhere((s) => s.key == key, orElse: () => fallback);
  }

  /// Reads the saved choice (at start, before the alarms are scheduled).
  static Future<AlarmSound> load() async {
    try {
      final raw = await _storage.read(key: _storeKey);
      if (raw != null && raw.contains('=')) {
        final m = Uri.splitQueryString(raw);
        current = fromJson(m);
      }
    } catch (_) {}
    return current;
  }

  static Future<void> save(AlarmSound s) async {
    current = s;
    try {
      await _storage.write(key: _storeKey, value: Uri(queryParameters: s.toJson()).query);
    } catch (_) {}
  }

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Plays a few seconds of [s] at alarm volume. False when this phone can't play it.
  static Future<bool> preview(AlarmSound s) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('preview', {'uri': s.playUri}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopPreview() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  /// Android's own sound picker (alarms and ringtones on the phone). Null when cancelled.
  static Future<AlarmSound?> pickFromPhone() async {
    if (!supported) return null;
    final r = await _channel.invokeMapMethod<String, dynamic>('pick', {if (current.key == 'phone' && current.uri != null) 'current': current.uri});
    if (r == null || r['uri'] == null) return null;
    return AlarmSound('phone', '${r['title'] ?? 'Sound from this phone'}', uri: '${r['uri']}');
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/med_alarms.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';

/// Medicine alarms on time: many Android phones (Infinix, Tecno, Xiaomi,
/// Realme, Oppo, Vivo…) stop apps in the background to save battery, and
/// their alarms then come late or not at all. Asking once to be left out of
/// battery saving fixes most of it; these phones also have an "auto-start"
/// switch only the patient can turn on.
class AlarmCheck {
  AlarmCheck._();

  static const _store = FlutterSecureStorage();
  static const _askedKey = 'alarm_check_asked_v1';

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Left out of battery saving (or not an Android phone, where it doesn't apply).
  static Future<bool> ok() async {
    if (!_android) return true;
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Once, the first time it matters (the patient has medicine alarms): the sheet.
  static Future<void> askOnce(BuildContext context) async {
    if (!_android || await ok()) return;
    try {
      if (await _store.read(key: _askedKey) != null) return;
      await _store.write(key: _askedKey, value: DateTime.now().toIso8601String());
    } catch (_) {
      return;
    }
    if (context.mounted) await show(context);
  }

  /// The sheet: why, the one-tap fix, and the auto-start steps.
  static Future<void> show(BuildContext context) async {
    await openSheet<void>(
      context,
      (c) => MpSheet(
        title: 'Keep medicine alarms on time',
        subtitle: 'Your phone may stop MedPin in the background to save battery. Then medicine alarms can come late or not at all.',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: VGap(
            gap: 12,
            children: [
              MpButton('Allow background alarms', onTap: () async {
                final s = await Permission.ignoreBatteryOptimizations.request();
                if (!c.mounted) return;
                if (s.isGranted) {
                  MedAlarms.I.sync();
                  Navigator.pop(c);
                  toast(c, 'Medicine alarms will ring on time');
                }
              }),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('On Infinix, Tecno, Xiaomi, Realme, Oppo or Vivo, also:', style: tx(14, w: w600)),
                    const Gap(6),
                    Text(
                      'Settings → Apps → MedPin → Battery: allow background activity, and turn on Auto-start (Auto-launch).',
                      style: tx(14, c: MP.ink2, h: 1.45),
                    ),
                  ],
                ),
              ),
              MpButton('Open MedPin settings', kind: MpBtn.secondary, onTap: () => openAppSettings()),
            ],
          ),
        ),
      ),
    );
  }
}

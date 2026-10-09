import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';

/// Doctor · Privacy and data — signed-in devices, a copy of your data, and
/// account deletion.
/// Live data: GET /api/me/sessions, POST /api/me/sessions/:id/revoke,
/// POST /api/me/sessions/revoke-others, POST /api/me/export, POST /api/me/delete-request.
class ProfilePrivacyScreen extends StatefulWidget {
  const ProfilePrivacyScreen({super.key});

  @override
  State<ProfilePrivacyScreen> createState() => _ProfilePrivacyScreenState();
}

class _ProfilePrivacyScreenState extends State<ProfilePrivacyScreen> with LiveData {
  static const _sampleDevices = [
    {'platform': 'android', 'deviceName': 'Infinix X6720', 'current': true, 'signedInAt': null},
    {'platform': 'web', 'deviceName': 'Chrome on Windows', 'current': false, 'signedInAt': null},
  ];

  @override
  Future<Object?> fetch() => Api.I.get('/api/me/sessions');

  List<Map<String, dynamic>> get _devices => data == null
      ? [for (final d in _sampleDevices) Map<String, dynamic>.from(d)]
      : data!.list('items');

  static String _deviceLabel(Map<String, dynamic> d) {
    final name = d.str('deviceName');
    if (name.isNotEmpty) return name;
    return const {'android': 'Android phone', 'ios': 'iPhone', 'web': 'Web browser', 'windows': 'Windows'}[d['platform']] ?? 'Unknown device';
  }

  String _deviceSub(Map<String, dynamic> d) {
    final at = F.date(d['signedInAt']);
    final when = at == null ? 'Signed in recently' : 'Signed in ${F.dayMonth(at)}, ${F.time(at)}';
    return d['current'] == true ? '$when · this device' : when;
  }

  Future<void> _signOut(Map<String, dynamic> d) async {
    if (!isLive) {
      toast(context, 'Signed out of ${_deviceLabel(d)}');
      return;
    }
    final ok = await runAction(context, () => Api.I.post('/api/me/sessions/${d['id']}/revoke'));
    if (ok == null || !mounted) return;
    toast(context, 'Signed out of ${_deviceLabel(d)}');
    reload(quiet: true);
  }

  Future<void> _signOutOthers() async {
    final yes = await d4Confirm(context, title: 'Sign out of other devices?', body: 'Every device except this one will need to sign in again with a code.', confirm: 'Sign out others');
    if (!yes || !mounted) return;
    if (!isLive) {
      toast(context, 'Signed out of other devices');
      return;
    }
    final r = await runAction(context, () => Api.I.post('/api/me/sessions/revoke-others'));
    if (r == null || !mounted) return;
    final n = (r as Map)['signedOut'] ?? 0;
    toast(context, n == 0 ? 'No other devices were signed in' : 'Signed out of $n ${n == 1 ? 'device' : 'devices'}');
    reload(quiet: true);
  }

  Future<void> _download() async {
    if (!isLive) {
      toast(context, 'Your data is ready');
      return;
    }
    final r = await runAction(context, () => Api.I.post('/api/me/export'));
    if (r == null || !mounted) return;
    final url = (r as Map)['url'] as String?;
    if (url == null || !await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) toast(context, "Couldn't open the file");
    }
  }

  Future<void> _deleteAccount() async {
    final yes = await d4Confirm(
      context,
      title: 'Delete your MedPin account?',
      body: 'We’ll contact you to confirm. Patient records your practice keeps by law are not deleted; your sign-in and profile are.',
      confirm: 'Send request',
    );
    if (!yes || !mounted) return;
    if (!isLive) {
      toast(context, 'Request sent. We’ll contact you to confirm.');
      return;
    }
    final ok = await runAction(context, () => Api.I.post('/api/me/delete-request', {'reason': 'Requested from Privacy and data'}));
    if (ok != null && mounted) toast(context, 'Request sent. We’ll contact you to confirm.');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final devices = _devices;
    return MpPage(
      header: const D4Header('Privacy and data'),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              D11Group('Signed-in devices', [
                for (final d in devices)
                  D11Row(
                    _deviceLabel(d),
                    sub: _deviceSub(d),
                    trailing: d['current'] == true
                        ? const MpBadge.grey('This device')
                        : D4TextLink('Sign out', color: MP.red, onTap: () => _signOut(d)),
                  ),
                if (devices.isEmpty) const D11Row('No devices signed in'),
              ]),
              if (devices.length > 1) D4OutlineButton('Sign out of all other devices', onTap: _signOutOthers),
              D11Group('Your data', [
                D11Row('Download my data', sub: 'Your account and profile as a file', onTap: _download),
                const D11Row(
                  'Patient records',
                  sub: 'Patients control who sees their records. Your practice keeps clinical records as the law requires.',
                ),
              ]),
              D4Note('Only people in your practice with the right role can open patient records. Every export is logged.'),
              D4OutlineButton('Delete my account', border: MP.redLine, onTap: _deleteAccount),
            ],
          ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/config.dart';
import '../data/session.dart';
import '../widgets/mp.dart';

/// App lock: when the signed-in user has "App lock" on, MedPin asks for the
/// phone's fingerprint / face / PIN when it opens and when it comes back after
/// [_grace] in the background. Phones without a screen lock are not locked
/// (there is nothing to unlock with); the setting explains this.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  /// Testing hook: replaces the platform authenticator.
  static LocalAuthentication auth = LocalAuthentication();

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

const _grace = Duration(seconds: 30);

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = false;
  bool _wasSignedIn = false;
  DateTime? _pausedAt;

  bool get _wanted => !AppMode.preview && Session.I.signedIn && Session.I.user['appLock'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.I.addListener(_sessionChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Session.I.removeListener(_sessionChanged);
    super.dispose();
  }

  /// Lock once when a saved session is restored at launch (not right after a
  /// fresh sign-in — the user just proved who they are with the code).
  void _sessionChanged() {
    final signedIn = Session.I.signedIn;
    if (signedIn && !_wasSignedIn && Session.I.restoredAtLaunch) _lock();
    if (!signedIn && _locked) setState(() => _locked = false);
    _wasSignedIn = signedIn;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (away >= _grace) _lock();
    }
  }

  Future<void> _lock() async {
    if (!_wanted || _locked || _checking) return;
    bool supported;
    try {
      supported = await AppLockGate.auth.isDeviceSupported();
    } catch (_) {
      supported = false;
    }
    if (!supported || !mounted) return;
    setState(() => _locked = true);
    _unlock();
  }

  Future<void> _unlock() async {
    if (_checking) return;
    setState(() => _checking = true);
    bool ok = false;
    try {
      ok = await AppLockGate.auth.authenticate(localizedReason: 'Unlock MedPin to see your health information', persistAcrossBackgrounding: true);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (ok) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: Material(
              color: MP.bg,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: MpLogo()),
                      const Spacer(),
                      const Center(child: MpIconTile(I.lock, size: 72, iconSize: 32, radius: 22)),
                      const Gap(20),
                      Text('MedPin is locked', textAlign: TextAlign.center, style: tx(24, w: w700, h: 1.25)),
                      const Gap(8),
                      Text('Use your fingerprint, face or phone PIN to continue.', textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.5)),
                      const Spacer(),
                      MpButton(_checking ? 'Waiting…' : 'Unlock', onTap: _checking ? null : _unlock),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

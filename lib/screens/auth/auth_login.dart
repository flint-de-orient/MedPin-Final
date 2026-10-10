import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/splash.dart' show kLogoHeroTag;
import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/firebase_phone.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'auth_register.dart';

/// Design: Auth-Login.dc.html — "Login" (Sign in).
class AuthLoginScreen extends StatefulWidget {
  const AuthLoginScreen({super.key});

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  // The design shows a sample number; the real sign-in starts empty.
  late final _phone = TextEditingController(text: AppMode.preview ? '98765 18210' : Session.I.pendingPhone ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendCode(BuildContext context) async {
    if (AppMode.preview) {
      Nav.go(context, 'Auth-OTP');
      return;
    }
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      toast(context, 'Enter a 10-digit mobile number');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
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
      if (!context.mounted) return;
      if (s.pendingDevCode != null) toast(context, 'Test code: ${s.pendingDevCode}');
      Nav.go(context, 'Auth-OTP');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<void> _signedInAutomatically(Map<String, dynamic> body) async {
    await Session.I.signIn(body);
    final ctx = Nav.key.currentContext;
    if (ctx != null && ctx.mounted) Nav.reset(ctx, Session.I.landing);
  }

  void _register(BuildContext context) {
    // Registering starts by verifying the phone; new numbers land on Register.
    if (!AppMode.preview) {
      _sendCode(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Auth-Register'),
      builder: (_) => const AuthRegisterScreen(fromLogin: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      scroll: false,
      // main grows and the footer sits at the bottom of the screen; the whole
      // page scrolls when the screen is shorter than the content.
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: Hero(tag: kLogoHeroTag, child: MpLogo())),
                      const Gap(48),
                      Text('Sign in', style: tx(32, w: w700, h: 1.2, em: -0.02)),
                      const Gap(8),
                      Text('For doctors, clinic staff and patients.', style: tx(16, c: MP.ink2, h: 1.5)),
                      const Gap(32),
                      Text('Mobile number', style: tx(14, w: w600, h: 1.4)),
                      const Gap(8),
                      _PhoneField(controller: _phone),
                      const Gap(8),
                      Text('10-digit Indian mobile number', style: tx(13, c: MP.ink3, h: 1.4)),
                      const Gap(24),
                      MpButton('Send code', onTap: () => _sendCode(context)),
                      const Gap(12),
                      Text(
                        "No password needed. We'll text a 6-digit code.",
                        textAlign: TextAlign.center,
                        style: tx(14, c: MP.ink2, h: 1.4),
                      ),

                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text('New to MedPin?', style: tx(15, c: MP.ink2, h: 1.4))),
                      const Gap(4),
                      _TextLink('Register', size: 15, padding: 4, onTap: () => _register(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "+91" phone field. The design shows it in its focused state
/// (1px #003399 border with the 3px #EBF1FB ring).
class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  const _PhoneField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.primary),
        boxShadow: MPShadow.focusRing,
      ),
      child: Row(
        children: [
          Container(
            height: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
            alignment: Alignment.center,
            decoration: const BoxDecoration(border: Border(right: BorderSide(color: MP.line))),
            child: Text('+91', style: tx(16, w: w600, tab: true)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Semantics(
                label: 'Mobile number',
                hint: '10-digit Indian mobile number',
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                    LengthLimitingTextInputFormatter(11),
                  ],
                  style: tx(16, em: 0.02, tab: true),
                  cursorColor: MP.primary,
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 48px text link (600 weight) with horizontal [padding].
class _TextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double size;
  final double padding;
  const _TextLink(this.label, {required this.onTap, this.size = 14, this.padding = 0});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(label, style: tx(size, w: w600, c: MP.primary))],
          ),
        ),
      ),
    );
  }
}

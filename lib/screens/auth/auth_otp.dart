import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/firebase_phone.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../../data/push.dart';

/// Design: Auth-OTP.dc.html — "Login · code" (Sign in).
class AuthOtpScreen extends StatefulWidget {
  const AuthOtpScreen({super.key});

  @override
  State<AuthOtpScreen> createState() => _AuthOtpScreenState();
}

class _AuthOtpScreenState extends State<AuthOtpScreen> with SingleTickerProviderStateMixin {
  // One hidden field holds the code; the six boxes render it.
  // The design shows a half-typed sample code; the real screen starts empty.
  final _code = TextEditingController(text: AppMode.preview ? '482' : '');
  final _focus = FocusNode();
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  late final Animation<double> _caret = _blink.drive(TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
  ]));
  Timer? _timer;
  int _left = AppMode.preview ? 24 : Session.I.pendingResendIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_changed);
    _code.addListener(_autoVerify);
    _focus.addListener(_changed);
    _startTimer();
  }

  void _changed() {
    // Keep the caret at the end so digits always fill left to right.
    final end = TextSelection.collapsed(offset: _code.text.length);
    if (_code.selection != end) _code.selection = end;
    if (mounted) setState(() {});
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    final phone = Session.I.pendingPhone;
    if (!AppMode.preview && phone != null) {
      try {
        if (Session.I.pendingMethod == 'firebase') {
          await FirebasePhone.I.sendCode(phone, resend: true);
        } else {
          final res = await Api.I.post('/api/auth/otp/request', {'phone': phone}) as Map;
          Session.I.pendingDevCode = res['devCode'] as String?;
        }
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _left = 30);
    _startTimer();
    final dev = AppMode.preview ? null : Session.I.pendingDevCode;
    toast(context, dev == null ? 'New code sent' : 'Test code: $dev');
  }

  void _autoVerify() {
    if (!AppMode.preview && _code.text.length == 6 && !_busy) _verify();
  }

  Future<void> _verify() async {
    if (AppMode.preview) {
      Nav.reset(context, 'Doctor-Dashboard');
      return;
    }
    final phone = Session.I.pendingPhone;
    if (phone == null) {
      Nav.back(context);
      return;
    }
    if (_code.text.length != 6) {
      toast(context, 'Enter the 6-digit code');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = Session.I.pendingMethod == 'firebase'
          ? await FirebasePhone.I.verify(_code.text)
          : ((await Api.I.post('/api/auth/otp/verify', {'phone': phone, 'code': _code.text, ...Session.deviceInfo}) as Map).cast<String, dynamic>());
      await Session.I.signIn(res);
      if (mounted) Nav.reset(context, Session.I.landing);
      Future.delayed(const Duration(milliseconds: 600), Push.I.flushPending);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message);
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openKeyboard() {
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blink.dispose();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code.text;
    final active = _focus.hasFocus ? (code.length < 6 ? code.length : 5) : -1;
    return MpPage(
      header: const MpHeader(''),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter the 6-digit code', style: tx(32, w: w700, h: 1.2, em: -0.02)),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Sent to ${AppMode.preview ? '+91 98765 •••10' : Session.I.pendingMaskedPhone ?? ''}', style: tx(16, c: MP.ink2, h: 1.5, tab: true)),
                Tap(
                  onTap: () => Nav.back(context),
                  radius: 6,
                  child: Text('Change', style: tx(16, w: w600, c: MP.primary, h: 1.5)),
                ),
              ],
            ),
            const Gap(32),
            Semantics(
              label: 'One-time code',
              value: code,
              textField: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: _code,
                        focusNode: _focus,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        showCursor: false,
                        enableInteractiveSelection: false,
                        style: tx(24, c: MP.white.withValues(alpha: 0)),
                        decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openKeyboard,
                    child: Row(
                      children: [
                        for (var i = 0; i < 6; i++) ...[
                          if (i > 0) const Gap(8),
                          Expanded(child: _box(i < code.length ? code[i] : '', i == active)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Gap(20),
            if (_left > 0)
              Text.rich(
                TextSpan(
                  text: 'Resend code in ',
                  style: tx(14, c: MP.ink2, h: 1.4),
                  children: [
                    TextSpan(
                      text: '0:${_left.toString().padLeft(2, '0')}',
                      style: tx(14, w: w600, c: MP.ink, h: 1.4, tab: true),
                    ),
                  ],
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Tap(
                  onTap: _resend,
                  radius: 6,
                  child: Text('Resend code', style: tx(14, w: w600, c: MP.primary, h: 1.4)),
                ),
              ),
            const Gap(32),
            MpButton('Verify', onTap: _verify),
          ],
        ),
      ),
    );
  }

  /// One digit box: 56px, radius 12, 1px #D5DBE5; the box being typed into
  /// gets a 2px #003399 border, the focus ring and a 2×24 caret.
  Widget _box(String digit, bool active) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? MP.primary : MP.lineStrong, width: active ? 2 : 1),
        boxShadow: active ? MPShadow.focusRing : null,
      ),
      child: digit.isNotEmpty
          ? Text(digit, style: tx(24, w: w700, tab: true))
          : active
              ? FadeTransition(
                  opacity: _caret,
                  child: Container(
                    width: 2,
                    height: 24,
                    decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(999)),
                  ),
                )
              : null,
    );
  }
}

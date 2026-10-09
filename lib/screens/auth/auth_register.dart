import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';

/// Design: Auth-Register.dc.html — "Register" (Sign in).
class AuthRegisterScreen extends StatefulWidget {
  /// True when opened from the sign-in screen; "Sign in" then just goes back.
  final bool fromLogin;
  const AuthRegisterScreen({super.key, this.fromLogin = false});

  @override
  State<AuthRegisterScreen> createState() => _AuthRegisterScreenState();
}

const _languages = ['English', 'বাংলা (Bengali)', 'हिन्दी (Hindi)'];

class _AuthRegisterScreenState extends State<AuthRegisterScreen> {
  final _invite = TextEditingController(text: 'CCC-4821');
  final _inviteFocus = FocusNode();
  late final _terms = TapGestureRecognizer()..onTap = () => toast(context, 'Terms of Use is not in the design yet');
  late final _privacy = TapGestureRecognizer()..onTap = () => toast(context, 'Privacy Policy is not in the design yet');
  String _lang = _languages.first;
  bool _agree = true;

  @override
  void initState() {
    super.initState();
    _invite.addListener(_changed);
    _inviteFocus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _inviteOk => RegExp(r'^[A-Z]{3}-\d{4}$').hasMatch(_invite.text.trim());

  @override
  void dispose() {
    _invite.dispose();
    _inviteFocus.dispose();
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  void _create() {
    if (!_agree) {
      toast(context, 'Please agree to the Terms of Use and Privacy Policy');
      return;
    }
    // The invite is for the front desk, so the new account lands there.
    Nav.reset(context, 'Staff-Today');
  }

  void _signIn() {
    if (widget.fromLogin) {
      Navigator.pop(context);
    } else {
      Navigator.of(context).pushReplacementNamed('Auth-Login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = tx(14, w: w600, c: MP.primary, h: 1.4);
    return MpPage(
      header: const MpHeader('Create account'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1 · Mobile number (done)
            const _Step('1 · Mobile number'),
            const Gap(8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: MP.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MP.line),
              ),
              child: Row(
                children: [
                  const Ico(I.check, size: 20, color: MP.green, stroke: 2.25),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phone verified', style: tx(16, w: w600, h: 1.4)),
                        const Gap(2),
                        Text('+91 98765 18210', style: tx(14, c: MP.ink2, h: 1.4, tab: true)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2 · Invite
            const Gap(32),
            const _Step('2 · Invite'),
            const Gap(8),
            const _Label('Invite code'),
            const Gap(8),
            _inviteField(),
            const Gap(8),
            Text('Your invite code decides which fields appear below.', style: tx(13, c: MP.ink3, h: 1.4)),
            if (_inviteOk) ...[
              const Gap(12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invite from City Care Clinic', style: tx(16, w: w600, h: 1.4)),
                    const Gap(4),
                    Text('Role: Front desk · Location: Salt Lake', style: tx(14, c: MP.ink2, h: 1.4)),
                  ],
                ),
              ),
            ],

            // 3 · Your details
            const Gap(32),
            const _Step('3 · Your details'),
            const Gap(8),
            const _Label('Full name'),
            const Gap(8),
            const MpInput(value: 'Tania Ghosh', keyboard: TextInputType.name),
            const Gap(20),
            Text.rich(
              TextSpan(
                text: 'Email ',
                style: tx(14, w: w600, h: 1.4),
                children: [TextSpan(text: '(optional)', style: tx(14, c: MP.ink2, h: 1.4))],
              ),
            ),
            const Gap(8),
            const MpInput(hint: 'name@example.com', keyboard: TextInputType.emailAddress),
            const Gap(20),
            const _Label('Preferred language'),
            const Gap(8),
            MpSelect(
              value: _lang,
              options: _languages,
              onChanged: (v) => setState(() => _lang = v),
            ),

            // Terms
            const Gap(24),
            Semantics(
              checked: _agree,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _agree = !_agree),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -1),
                      child: MpCheck(value: _agree, onChanged: (v) => setState(() => _agree = v)),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: tx(14, c: MP.ink2, h: 1.4),
                          children: [
                            const TextSpan(text: "I agree to MedPin's "),
                            TextSpan(text: 'Terms of Use', style: link, recognizer: _terms),
                            const TextSpan(text: ' and '),
                            TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(24),
            MpButton('Create account', onTap: _create),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text('Already have an account?', style: tx(15, c: MP.ink2, h: 1.4))),
                const Gap(4),
                Tap(
                  onTap: _signIn,
                  radius: 12,
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('Sign in', style: tx(15, w: w600, c: MP.primary))],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Invite code: 56px field, 16/600/.06em uppercase, green check when valid.
  Widget _inviteField() {
    final focused = _inviteFocus.hasFocus;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focused ? MP.primary : MP.lineStrong),
        boxShadow: focused ? MPShadow.focusRing : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Invite code',
              child: TextField(
                controller: _invite,
                focusNode: _inviteFocus,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCase()],
                style: tx(16, w: w600, em: 0.06, tab: true),
                cursorColor: MP.primary,
                decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
              ),
            ),
          ),
          if (_inviteOk)
            Semantics(
              label: 'Code accepted',
              child: const Ico(I.check, size: 20, color: MP.green, stroke: 2.25),
            ),
        ],
      ),
    );
  }
}

/// Step heading: 12px / 1.35 / 600 / .06em uppercase #69738A.
class _Step extends StatelessWidget {
  final String text;
  const _Step(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: tx(12, w: w600, c: MP.ink3, h: 1.35, em: 0.06));
}

/// Field label: 14 / 600, inherited line-height 1.4.
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text, style: tx(14, w: w600, h: 1.4));
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

/// Design: Auth-Register.dc.html — "Register" (Sign in).
class AuthRegisterScreen extends StatefulWidget {
  /// True when opened from the sign-in screen; "Sign in" then just goes back.
  final bool fromLogin;
  const AuthRegisterScreen({super.key, this.fromLogin = false});

  @override
  State<AuthRegisterScreen> createState() => _AuthRegisterScreenState();
}

const _languages = ['English', 'বাংলা (Bengali)', 'हिन्दी (Hindi)'];
const _languageCodes = ['en', 'bn', 'hi'];

const _roleLabels = {
  'doctor': 'Doctor',
  'front_desk': 'Front desk',
  'doctor_assistant': "Doctor's assistant",
  'dietician': 'Dietician',
  'lab_manager': 'Lab manager',
  'lab_technician': 'Lab technician',
  'practice_manager': 'Practice manager',
};

class _AuthRegisterScreenState extends State<AuthRegisterScreen> {
  // The design shows a sample invite and name; the real form starts empty.
  final _invite = TextEditingController(text: AppMode.preview ? 'CCC-4821' : '');
  final _name = TextEditingController(text: AppMode.preview ? 'Tania Ghosh' : Session.I.name);
  final _email = TextEditingController();

  /// Live invite details from the server, for the code currently typed.
  String? _checkedCode;
  Map<String, dynamic>? _inviteInfo;
  bool _busy = false;
  final _inviteFocus = FocusNode();
  late final _terms = TapGestureRecognizer()..onTap = () => Nav.go(context, 'Legal', args: {'doc': 'terms'});
  late final _privacy = TapGestureRecognizer()..onTap = () => Nav.go(context, 'Legal', args: {'doc': 'privacy'});
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
    if (!AppMode.preview && _formatOk && _checkedCode != _invite.text.trim()) _checkInvite();
  }

  bool get _formatOk => RegExp(r'^[A-Z]{3}-\d{4}$').hasMatch(_invite.text.trim());

  /// Preview: any well-formed code. Live: the server has to know it.
  bool get _inviteOk => AppMode.preview ? _formatOk : _formatOk && _inviteInfo != null && _checkedCode == _invite.text.trim();

  Future<void> _checkInvite() async {
    final code = _invite.text.trim();
    _checkedCode = code;
    _inviteInfo = null;
    try {
      final res = await Api.I.get('/api/auth/invites/$code') as Map;
      if (mounted && _checkedCode == code) setState(() => _inviteInfo = res.cast<String, dynamic>());
    } on ApiException catch (e) {
      if (mounted && _checkedCode == code) toast(context, e.status == 404 ? "That invite code isn't valid" : e.message);
    }
  }

  String get _inviteTitle => AppMode.preview ? 'Invite from City Care Clinic' : 'Invite from ${_inviteInfo?['practiceName'] ?? ''}';

  String get _inviteDetail {
    if (AppMode.preview) return 'Role: Front desk · Location: Salt Lake';
    final role = _roleLabels[_inviteInfo?['role']] ?? '';
    final locations = [for (final l in (_inviteInfo?['locations'] as List? ?? const [])) '$l'];
    return locations.isEmpty ? 'Role: $role' : 'Role: $role · Location: ${locations.join(', ')}';
  }

  String get _phoneText {
    if (AppMode.preview) return '+91 98765 18210';
    final p = Session.I.phone;
    return p.length == 10 ? '+91 ${p.substring(0, 5)} ${p.substring(5)}' : p;
  }

  @override
  void dispose() {
    _invite.dispose();
    _name.dispose();
    _email.dispose();
    _inviteFocus.dispose();
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_agree) {
      toast(context, 'Please agree to the Terms of Use and Privacy Policy');
      return;
    }
    if (AppMode.preview) {
      // The invite is for the front desk, so the new account lands there.
      Nav.reset(context, 'Staff-Today');
      return;
    }
    if (!Session.I.signedIn) {
      toast(context, 'Verify your mobile number first');
      Navigator.of(context).pushReplacementNamed('Auth-Login');
      return;
    }
    if (!_inviteOk) {
      toast(context, 'Enter the invite code from your clinic');
      return;
    }
    if (_name.text.trim().isEmpty) {
      toast(context, 'Enter your full name');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Api.I.post('/api/auth/register', {
        'inviteCode': _invite.text.trim(),
        'name': _name.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        'language': _languageCodes[_languages.indexOf(_lang)],
        'termsAccepted': true,
      });
      await Session.I.reloadAccount();
      if (mounted) Nav.reset(context, Session.I.landing);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                        Text(_phoneText, style: tx(14, c: MP.ink2, h: 1.4, tab: true)),
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
                    Text(_inviteTitle, style: tx(16, w: w600, h: 1.4)),
                    const Gap(4),
                    Text(_inviteDetail, style: tx(14, c: MP.ink2, h: 1.4)),
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
            MpInput(controller: _name, keyboard: TextInputType.name),
            const Gap(20),
            Text.rich(
              TextSpan(
                text: 'Email ',
                style: tx(14, w: w600, h: 1.4),
                children: [TextSpan(text: '(optional)', style: tx(14, c: MP.ink2, h: 1.4))],
              ),
            ),
            const Gap(8),
            MpInput(controller: _email, hint: 'name@example.com', keyboard: TextInputType.emailAddress),
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

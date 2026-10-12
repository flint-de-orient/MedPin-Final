import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/config.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_a1.dart';
import 'sign_in_flow.dart';
import '../../widgets/i18n.dart';

/// "New to MedPin? Register" — patients sign themselves up.
/// Doctors are set up by MedPin and clinic staff are added by their clinic,
/// so this screen is for patients only.
///
/// Flow: name, gender, age and mobile → a 6-digit code (Auth-OTP, read from
/// the SMS by itself) → POST /api/patient/register with these details →
/// the patient home. If a clinic already added this number, that record is
/// linked instead of making a second one.
class AuthPatientRegisterScreen extends StatefulWidget {
  const AuthPatientRegisterScreen({super.key});

  @override
  State<AuthPatientRegisterScreen> createState() => _AuthPatientRegisterScreenState();
}

const _genders = ['Female', 'Male', 'Other'];
const _genderKeys = ['female', 'male', 'other'];

class _AuthPatientRegisterScreenState extends State<AuthPatientRegisterScreen> {
  // The design shows sample details; the real form starts empty.
  final _name = TextEditingController(text: AppMode.preview ? 'Priya Sharma' : '');
  final _age = TextEditingController(text: AppMode.preview ? '34' : '');
  late final _phone = TextEditingController(text: AppMode.preview ? '98300 41275' : '');
  int _gender = 0;
  bool _agree = AppMode.preview;
  bool _busy = false;
  bool _argsRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    // The number typed on Sign in, if any.
    final p = (Nav.args<Map>(context) ?? const {})['phone']?.toString();
    if (p != null && p.length == 10 && _phone.text.isEmpty) _phone.text = '${p.substring(0, 5)} ${p.substring(5)}';
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final age = int.tryParse(_age.text.trim());
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (name.length < 2) return toast(context, 'Enter your full name');
    if (age == null || age < 0 || age > 120) return toast(context, 'Enter your age in years');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return toast(context, 'Enter a 10-digit mobile number');
    if (!_agree) return toast(context, 'Please agree to the Terms of Use and Privacy Policy');
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    Session.I.pendingSignup = {'name': name, 'gender': _genderKeys[_gender], 'ageYears': age, 'termsAccepted': true};
    final sent = await sendSignInCode(context, digits);
    if (!sent) Session.I.pendingSignup = null;
    if (mounted) setState(() => _busy = false);
  }

  void _signIn() {
    if (Navigator.of(context).canPop()) {
      Nav.back(context);
    } else {
      Nav.reset(context, 'Auth-Login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader(''),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create your account', style: tx(32, w: w700, h: 1.2, em: -0.02)),
            const Gap(8),
            Text(
              'For patients. Book doctors and keep your medicines, reports and visits in one place.',
              style: tx(16, c: MP.ink2, h: 1.5),
            ),
            const Gap(28),
            const A1Step('1 · About you'),
            const Gap(12),
            const A1Label('Full name'),
            const Gap(8),
            MpInput(
              controller: _name,
              hint: 'As on your ID',
              keyboard: TextInputType.name,
              autofillHints: const [AutofillHints.name],
            ),
            const Gap(16),
            const A1Label('Gender'),
            const Gap(8),
            MpSegmented(options: _genders, index: _gender, onChanged: (i) => setState(() => _gender = i)),
            const Gap(16),
            const A1Label('Age'),
            const Gap(8),
            SizedBox(
              width: 160,
              child: MpInput(
                controller: _age,
                keyboard: TextInputType.number,
                unit: 'years',
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              ),
            ),
            const Gap(28),
            const A1Step('2 · Verify your mobile'),
            const Gap(12),
            const A1Label('Mobile number'),
            const Gap(8),
            Semantics(
              label: 'Mobile number',
              child: MpInput(
                controller: _phone,
                prefixText: '+91',
                keyboard: TextInputType.phone,
                tab: true,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: const [MpPhoneFormatter()],
              ),
            ),
            const Gap(8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.shield, size: 16, color: MP.ink3)),
                const Gap(8),
                Expanded(
                  child: Text(
                    "We'll text a 6-digit code to check it's your number. MedPin fills it in for you.",
                    style: tx(13, c: MP.ink3, h: 1.4),
                  ),
                ),
              ],
            ),
            const Gap(24),
            A1Terms(value: _agree, onChanged: (v) => setState(() => _agree = v)),
            const Gap(24),
            MpButton(_busy ? 'Sending code…' : 'Send code', onTap: _busy ? null : _send),
            const Gap(20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Ico(I.stethoscope, size: 20, color: MP.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Doctor or clinic staff? MedPin sets up your clinic and the clinic adds its staff. Just sign in with your number.',
                      style: tx(14, h: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text('Already on MedPin?', style: tx(15, c: MP.ink2, h: 1.4))),
                const Gap(4),
                Tap(
                  onTap: _signIn,
                  radius: 12,
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Center(child: Text('Sign in', style: tx(15, w: w600, c: MP.primary))),
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
}

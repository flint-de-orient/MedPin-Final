import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_a1.dart';
import '../../widgets/i18n.dart';

/// "I'm a patient" — name, gender and age, then the patient home.
/// POST /api/patient/register (links an existing clinic record for this number).
class AuthPatientSetupScreen extends StatefulWidget {
  const AuthPatientSetupScreen({super.key});

  @override
  State<AuthPatientSetupScreen> createState() => _AuthPatientSetupScreenState();
}

const _genders = ['Female', 'Male', 'Other'];
const _genderKeys = ['female', 'male', 'other'];

class _AuthPatientSetupScreenState extends State<AuthPatientSetupScreen> {
  final _name = TextEditingController(text: Session.I.name);
  final _age = TextEditingController();
  int _gender = 0;
  bool _agree = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final age = int.tryParse(_age.text.trim());
    if (_name.text.trim().length < 2) return toast(context, 'Enter your full name');
    if (age == null || age < 0 || age > 120) return toast(context, 'Enter your age in years');
    if (!_agree) return toast(context, 'Please agree to the Terms of Use and Privacy Policy');
    if (AppMode.preview) return Nav.reset(context, 'Main');
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Api.I.post('/api/patient/register', {
        'name': _name.text.trim(),
        'gender': _genderKeys[_gender],
        'ageYears': age,
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

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Create your profile'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your doctors see these details when you share your records. If a clinic already added you, we link that record.',
              style: tx(14, c: MP.ink2, h: 1.45),
            ),
            const Gap(20),
            const A1Label('Full name'),
            const Gap(8),
            MpInput(controller: _name, hint: 'Priya Sharma', keyboard: TextInputType.name),
            const Gap(16),
            const A1Label('Gender'),
            const Gap(8),
            MpSegmented(options: _genders, index: _gender, onChanged: (i) => setState(() => _gender = i)),
            const Gap(16),
            const A1Label('Age'),
            const Gap(8),
            SizedBox(width: 160, child: MpInput(controller: _age, keyboard: TextInputType.number, unit: 'years')),
            const Gap(24),
            A1Terms(value: _agree, onChanged: (v) => setState(() => _agree = v)),
            const Gap(24),
            MpButton(_busy ? 'Creating…' : 'Continue', onTap: _busy ? null : _create),
          ],
        ),
      ),
    );
  }
}

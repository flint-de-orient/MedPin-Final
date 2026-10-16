import 'package:flutter/material.dart' hide Text;

import '../../data/config.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../patient/address_sheet.dart';
import '../../widgets/i18n.dart';

/// Patient sign-up, last step (optional): "Your address". Clinics near the
/// patient and "km from you" are measured from it. The address sheet
/// (patient/address_sheet.dart) does the work — "Use my current location" or
/// typing — and saves it with PATCH /api/patient/me {address}. "Skip for now"
/// leaves it for Profile → Home address.
class AuthPatientAddressScreen extends StatefulWidget {
  const AuthPatientAddressScreen({super.key});

  @override
  State<AuthPatientAddressScreen> createState() => _AuthPatientAddressScreenState();
}

/// After Register created the profile: Auth-OTP opens the patient home as soon
/// as sign-in returns, so the address step opens on top of it a moment later.
void openAddressStepAfterSignUp() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 300), () {
      final ctx = Nav.key.currentContext;
      if (ctx == null || !ctx.mounted || !Session.I.signedIn || Session.I.landing != 'Main') return;
      Nav.go(ctx, 'Auth-Patient-Address');
    });
  });
}

class _AuthPatientAddressScreenState extends State<AuthPatientAddressScreen> {
  /// On to the patient home: back to it when this step opened over it,
  /// otherwise (from Auth-Patient-Setup) it replaces this one.
  void _done() {
    if (Navigator.of(context).canPop()) {
      Nav.back(context);
    } else {
      Nav.reset(context, AppMode.preview ? 'Main' : Session.I.landing);
    }
  }

  Future<void> _add() async {
    final saved = await openSheet<bool>(context, (_) => const AddressSheet());
    if (saved == true && mounted) _done();
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('', showBack: false),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your address', style: tx(32, w: w700, h: 1.2, em: -0.02)),
            const Gap(8),
            Text(
              'Add your home address to see clinics near you and how far they are. You can change it later in Profile.',
              style: tx(16, c: MP.ink2, h: 1.5),
            ),
            const Gap(28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Ico(I.pin, size: 20, color: MP.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      '“Use my current location” fills it in for you, or type it yourself.',
                      style: tx(14, h: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(24),
            MpButton('Add your address', icon: I.pin, onTap: _add),
            const Gap(12),
            MpButton('Skip for now', kind: MpBtn.secondary, onTap: _done),
          ],
        ),
      ),
    );
  }
}

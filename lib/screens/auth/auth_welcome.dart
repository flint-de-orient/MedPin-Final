import 'package:flutter/material.dart';

import '../../data/config.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_a1.dart';

/// First screen for a new mobile number (after the code is verified):
/// start a clinic as a doctor, or sign up as a patient. Clinic staff are
/// added by the clinic owner (People → Add) and land on their panel directly.
class AuthWelcomeScreen extends StatelessWidget {
  const AuthWelcomeScreen({super.key});

  String get _phone {
    final p = Session.I.phone;
    if (AppMode.preview || p.length != 10) return '+91 98300 41275';
    return '+91 ${p.substring(0, 5)} ${p.substring(5)}';
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(alignment: Alignment.centerLeft, child: MpLogo()),
            const Gap(40),
            Text('Welcome to MedPin', style: tx(30, w: w700, h: 1.2, em: -0.02)),
            const Gap(8),
            Text('Your number $_phone is verified. How will you use MedPin?', style: tx(16, c: MP.ink2, h: 1.5)),
            const Gap(28),
            A1Choice(
              icon: I.stethoscope,
              title: "I'm a doctor",
              subtitle: 'Set up your clinic, schedule and fees. Patients can book you right away.',
              onTap: () => Nav.go(context, 'Auth-Clinic-Setup'),
            ),
            const Gap(12),
            A1Choice(
              icon: I.heart,
              title: "I'm a patient",
              subtitle: 'Keep your medicines, reports and doctors in one place.',
              onTap: () => Nav.go(context, 'Auth-Patient-Setup'),
            ),
            const Gap(24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Ico(I.users, size: 20, color: MP.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Joining a clinic as staff? Ask the clinic owner to add this number in People, then sign in again.',
                      style: tx(14, h: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(24),
            Center(
              child: Tap(
                onTap: () => signOut(context),
                radius: 12,
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(child: Text('Use a different number', style: tx(15, w: w600, c: MP.primary))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart' hide Text;

import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

/// Terms of Use / Privacy Policy, opened with {'doc': 'terms' | 'privacy'}.
///
/// The text is a plain-language draft for MedPin's owners to have reviewed by a
/// lawyer before launch (Digital Personal Data Protection Act, 2023;
/// Telemedicine Practice Guidelines, 2020).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Nav.args<Map>(context) ?? const {};
    final privacy = a['doc'] == 'privacy';
    final sections = privacy ? _privacy : _terms;
    return MpPage(
      header: MpHeader(privacy ? 'Privacy Policy' : 'Terms of Use'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Last updated 10 October 2026', style: tx(13, c: MP.ink3, h: 1.4)),
            for (final (title, body) in sections) ...[
              const Gap(20),
              Text(title, style: tx(17, w: w700, h: 1.3)),
              const Gap(6),
              Text(body, style: tx(15, c: MP.ink2, h: 1.55)),
            ],
          ],
        ),
      ),
    );
  }
}

const _terms = [
  ('What MedPin is',
      'MedPin connects patients with their doctors and clinics: appointments, prescriptions, reports, medicines and messages. MedPin is a tool for care; it does not replace a consultation with a qualified doctor.'),
  ('Your account',
      'You sign in with your mobile number and a one-time code. Keep your phone secure. You are responsible for activity on your account and must give correct details.'),
  ('Doctors and clinics',
      'Doctors confirm they hold a valid registration with a State Medical Council or the National Medical Commission and follow the Telemedicine Practice Guidelines. Clinics are responsible for the staff they add and the information they record.'),
  ('MedPin AI',
      'MedPin AI explains information in plain words and helps you find the right doctor. It does not diagnose, prescribe, change doses or order tests. For doctors it is an assistant; the doctor decides.'),
  ('Emergencies',
      'MedPin is not an emergency service. In an emergency call 108 or go to the nearest emergency department.'),
  ('Payments',
      'Consultation fees are set by each doctor or clinic. Pharmacy orders are between you and the pharmacy.'),
  ('Acceptable use',
      'Do not misuse MedPin: no false information, no access to records you are not allowed to see, no attempts to break or overload the service.'),
  ('Changes and contact',
      'We may update these terms and will tell you in the app. Questions: use Help and support in your profile.'),
];

const _privacy = [
  ('What we collect',
      'Your mobile number, name, age and gender; health information you or your doctors add (visits, prescriptions, reports, vitals, medicines, messages); and basic technical data needed to run the app.'),
  ('Why we use it',
      'To provide your care: appointments, prescriptions, reminders, messages and records. We do not sell your data or use it for advertising.'),
  ('Who can see your records',
      'Only the doctors and clinics you are linked with, at the level you choose in "Who can see my records". You can change or stop sharing at any time. A new clinic needs your consent code.'),
  ('AI',
      'When you or your doctor use MedPin AI, the relevant information is sent to our AI service provider to produce the answer.'),
  ('Your rights',
      'You can see and download your data, correct it, withdraw consent for a clinic, and ask us to delete your account from Privacy and data in your profile.'),
  ('Security and storage',
      'Access to records is limited by role and by your sharing choices, and files are shared only through short-lived links.'),
  ('Contact',
      'For privacy questions or complaints, use Help and support in your profile; we will reply within 30 days.'),
];

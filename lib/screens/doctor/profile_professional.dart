import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Design: Profile-Professional.dc.html — "Profile · professional details".
class ProfileProfessionalScreen extends StatefulWidget {
  const ProfileProfessionalScreen({super.key});

  @override
  State<ProfileProfessionalScreen> createState() => _ProfileProfessionalScreenState();
}

enum _Proof { verified, upload, review }

class _Qualification {
  final String name;
  final String meta;
  _Proof proof;
  _Qualification(this.name, this.meta, this.proof);
}

class _ProfileProfessionalScreenState extends State<ProfileProfessionalScreen> {
  static const _professions = [
    ('Doctor', 'MBBS, MD, MS…'),
    ('Psychologist', 'Counsellor, therapist'),
    ('Physiotherapist', 'BPT, MPT'),
    ('Dietician', 'Nutritionist'),
    ('Fitness coach', 'Trainer, yoga'),
    ('Other', 'Dentist, AYUSH…'),
  ];

  int _profession = 0;
  final List<_Qualification> _qualifications = [
    _Qualification('MBBS', 'Calcutta Medical College · 2008', _Proof.verified),
    _Qualification('MD, Internal Medicine', 'IPGMER, Kolkata · 2012', _Proof.verified),
    _Qualification('Fellowship in Diabetology', 'RSSDI · 2014', _Proof.upload),
  ];

  Future<void> _addQualification() async {
    final r = await d4FormSheet(
      context,
      title: 'Add qualification',
      fields: const [
        D4FormField('Qualification', hint: 'e.g. DM, Endocrinology'),
        D4FormField('Institution', hint: 'e.g. AIIMS, New Delhi'),
        D4FormField('Year', hint: 'e.g. 2016', keyboard: TextInputType.number),
      ],
      confirm: 'Add qualification',
    );
    if (!mounted || r == null || r.length < 3 || r[0].isEmpty) return;
    final meta = [r[1], r[2]].where((s) => s.isNotEmpty).join(' · ');
    setState(() => _qualifications.add(_Qualification(r[0], meta, _Proof.upload)));
  }

  void _uploadProof(_Qualification q) {
    setState(() => q.proof = _Proof.review);
    toast(context, 'Proof sent for verification');
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: D4Header('Professional details', onSave: () => d4Save(context)),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        gap: 16,
        children: [
          D4Card(
            children: [
              const D4CardTitle('Your profession'),
              const D4Note(
                'We tailor your profile to it. A psychologist sets session length and therapy approaches; '
                'a physiotherapist can offer home visits.',
              ),
              MpGrid(
                columns: 2,
                gap: 8,
                children: [
                  for (var i = 0; i < _professions.length; i++)
                    D4OptionCard(
                      title: _professions[i].$1,
                      sub: _professions[i].$2,
                      selected: i == _profession,
                      onTap: () => setState(() => _profession = i),
                    ),
                ],
              ),
            ],
          ),
          const D4Card(
            children: [
              D4CardTitle('Registration'),
              VGap(
                gap: 12,
                children: [
                  D4Field('Council', 'West Bengal Medical Council'),
                  D4Field(
                    'Registration number',
                    '64213',
                    keyboard: TextInputType.number,
                    trailing: D4Pill.green('Verified'),
                  ),
                  D4Field('Year', '2008', keyboard: TextInputType.number),
                ],
              ),
            ],
          ),
          const D4AbdmCard(
            title: 'Healthcare Professionals Registry',
            body:
                'Link your HPR ID to be verified through ABDM and to share records with patients’ ABHA accounts, '
                'with their consent.',
            idName: 'HPR ID',
            hint: 'e.g. 71-1234-5678-9012',
          ),
          D4Card(
            children: [
              const D4CardTitle('Qualifications'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _qualifications.length; i++) ...[
                    if (i > 0) ...[const SizedBox(height: 14), const MpDivider(), const SizedBox(height: 14)],
                    _qualificationRow(_qualifications[i]),
                  ],
                ],
              ),
              D4DashedButton(
                '+ Add qualification',
                height: 44,
                radius: 12,
                fontSize: 15,
                expand: true,
                onTap: _addQualification,
              ),
            ],
          ),
          const D4Card(
            children: [
              D4CardTitle('Specialisations'),
              D4TagEditor(
                initial: ['Diabetology', 'Internal medicine'],
                addTitle: 'Add specialisation',
                addLabel: 'Specialisation',
                addHint: 'e.g. Endocrinology',
              ),
            ],
          ),
          const D4Card(
            children: [
              D4CardTitle('Conditions you treat'),
              D4Note('Patients find you when they search these.'),
              D4TagEditor(
                initial: ['Type 2 diabetes', 'Hypertension', 'Thyroid disorders', 'PCOS', 'Obesity'],
                addTitle: 'Add condition',
                addLabel: 'Condition',
                addHint: 'e.g. Type 1 diabetes',
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Experience'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: D4Field('Practising since', '2010', keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: D4Field(
                      'Years',
                      '14',
                      keyboard: TextInputType.number,
                      trailing: Text('yrs', style: tx(14, c: MP.ink3)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const D4Card(
            children: [
              D4CardTitle('Memberships and awards'),
              D4TagEditor(
                initial: ['RSSDI member', 'API member'],
                addTitle: 'Add membership or award',
                addLabel: 'Membership or award',
                addHint: 'e.g. ESI member',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qualificationRow(_Qualification q) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: D4TitleSub(q.name, q.meta, weight: w700)),
        const SizedBox(width: 12),
        switch (q.proof) {
          _Proof.verified => const D4Pill.green('Verified'),
          _Proof.review => const D4Pill.blue('In review'),
          _Proof.upload => Semantics(
            button: true,
            child: GestureDetector(onTap: () => _uploadProof(q), child: const D4Pill.amber('Upload proof')),
          ),
        },
      ],
    );
  }
}

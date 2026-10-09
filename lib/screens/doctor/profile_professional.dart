import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/live.dart';
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

  /// Server id (live data only).
  final String? id;
  _Qualification(this.name, this.meta, this.proof, [this.id]);
}

class _ProfileProfessionalScreenState extends State<ProfileProfessionalScreen> with LiveData {
  /// API values for [_professions], in the same order.
  static const _professionKeys = ['doctor', 'psychologist', 'physiotherapist', 'dietician', 'fitness_coach', 'other'];
  static const _professions = [
    ('Doctor', 'MBBS, MD, MS…'),
    ('Psychologist', 'Counsellor, therapist'),
    ('Physiotherapist', 'BPT, MPT'),
    ('Dietician', 'Nutritionist'),
    ('Fitness coach', 'Trainer, yoga'),
    ('Other', 'Dentist, AYUSH…'),
  ];

  int? _pickedProfession;
  final List<_Qualification> _sampleQualifications = [
    _Qualification('MBBS', 'Calcutta Medical College · 2008', _Proof.verified),
    _Qualification('MD, Internal Medicine', 'IPGMER, Kolkata · 2012', _Proof.verified),
    _Qualification('Fellowship in Diabetology', 'RSSDI · 2014', _Proof.upload),
  ];

  /// Edited fields, sent with PATCH /api/doctor/profile on Save.
  final Map<String, Object?> _changes = {};
  final Map<String, Object?> _registration = {};

  @override
  Future<Object?> fetch() => Api.I.get('/api/doctor/profile');

  int get _profession {
    if (_pickedProfession != null) return _pickedProfession!;
    if (data == null) return 0;
    final i = _professionKeys.indexOf(data!.str('profession', 'doctor'));
    return i < 0 ? 0 : i;
  }

  List<_Qualification> get _qualifications {
    if (data == null) return _sampleQualifications;
    return [
      for (final q in data!.list('qualifications'))
        _Qualification(
          q.str('name'),
          [q.str('institution'), q.str('year')].where((s) => s.isNotEmpty).join(' · '),
          switch (q['proofStatus']) {
            'verified' => _Proof.verified,
            'review' => _Proof.review,
            _ => _Proof.upload,
          },
          q.str('id', q.str('_id')),
        ),
    ];
  }

  Map<String, dynamic> get _reg => data?.obj('registration') ?? const {};
  String _v(String sample, String Function(Map<String, dynamic> d) live) => data == null ? sample : live(data!);
  List<String> _tags(List<String> sample, String key) =>
      data == null ? sample : [for (final t in (data![key] as List? ?? const [])) '$t'];

  Widget? get _registrationPill {
    final status = data == null ? 'verified' : _reg.str('status');
    if (_reg.str('number').isEmpty && data != null) return null;
    return switch (status) {
      'verified' => const D4Pill.green('Verified'),
      'in_review' => const D4Pill.blue('In review'),
      'rejected' => const D4Pill.amber('Not verified'),
      _ => null,
    };
  }

  Future<void> _save() async {
    if (!isLive) {
      d4Save(context);
      return;
    }
    final body = {..._changes, if (_registration.isNotEmpty) 'registration': {..._registration}};
    for (final k in ['practisingSince']) {
      if (body[k] is String) {
        final n = int.tryParse('${body[k]}'.trim());
        if (n == null || n < 1950 || n > DateTime.now().year) {
          toast(context, 'Enter the year you started practising, like 2010');
          return;
        }
        body[k] = n;
      }
    }
    final reg = body['registration'];
    if (reg is Map && reg['year'] is String) {
      final y = int.tryParse('${reg['year']}'.trim());
      if (y == null) {
        toast(context, 'Enter the registration year, like 2008');
        return;
      }
      reg['year'] = y;
    }
    if (body.isEmpty) {
      d4Save(context);
      return;
    }
    final ok = await runAction(context, () => Api.I.patch('/api/doctor/profile', body));
    if (ok == null || !mounted) return;
    d4Save(context);
  }

  Future<bool> _linkHpr(String id) async {
    if (!isLive) return true;
    final ok = await runAction(context, () => Api.I.patch('/api/doctor/profile', {'hprId': id}));
    if (ok != null && mounted) reload(quiet: true);
    return ok != null;
  }

  Future<void> _removeQualification(_Qualification q) async {
    final ok = await d4Confirm(
      context,
      title: 'Remove ${q.name}?',
      body: 'It will no longer show on your profile.',
      confirm: 'Remove qualification',
    );
    if (!ok || !mounted || q.id == null) return;
    final r = await runAction(context, () => Api.I.delete('/api/doctor/qualifications/${q.id}'));
    if (r == null || !mounted) return;
    toast(context, '${q.name} removed');
    reload(quiet: true);
  }

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
    if (!isLive) {
      final meta = [r[1], r[2]].where((s) => s.isNotEmpty).join(' · ');
      setState(() => _sampleQualifications.add(_Qualification(r[0], meta, _Proof.upload)));
      return;
    }
    final year = int.tryParse(r[2]);
    final ok = await runAction(
      context,
      () => Api.I.post('/api/doctor/qualifications', {
        'name': r[0],
        if (r[1].isNotEmpty) 'institution': r[1],
        if (year != null) 'year': year,
      }),
    );
    if (ok == null || !mounted) return;
    toast(context, '${r[0]} added');
    reload(quiet: true);
  }

  Future<void> _uploadProof(_Qualification q) async {
    if (!isLive || q.id == null) {
      setState(() => q.proof = _Proof.review);
      toast(context, 'Proof sent for verification');
      return;
    }
    final file = await Files.chooseSource(context, title: 'Proof of ${q.name}');
    if (file == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.upload('/api/doctor/qualifications/${q.id}/proof', files: {'file': [file]}));
    if (ok == null || !mounted) return;
    toast(context, 'Proof sent for verification');
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (placeholder != null) return MpPage(header: const D4Header('Professional details'), body: placeholder);
    final qualifications = _qualifications;
    final years = data?['yearsExperience'];
    return MpPage(
      header: D4Header('Professional details', onSave: _save),
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
                      onTap: () => setState(() {
                        _pickedProfession = i;
                        _changes['profession'] = _professionKeys[i];
                      }),
                    ),
                ],
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Registration'),
              VGap(
                gap: 12,
                children: [
                  D4Field(
                    'Council',
                    _v('West Bengal Medical Council', (_) => _reg.str('council')),
                    onChanged: (v) => _registration['council'] = v.trim(),
                  ),
                  D4Field(
                    'Registration number',
                    _v('64213', (_) => _reg.str('number')),
                    keyboard: TextInputType.number,
                    trailing: _registrationPill,
                    onChanged: (v) => _registration['number'] = v.trim(),
                  ),
                  D4Field(
                    'Year',
                    _v('2008', (_) => _reg.str('year')),
                    keyboard: TextInputType.number,
                    onChanged: (v) => _registration['year'] = v,
                  ),
                ],
              ),
            ],
          ),
          D4AbdmCard(
            title: 'Healthcare Professionals Registry',
            body:
                'Link your HPR ID to be verified through ABDM and to share records with patients’ ABHA accounts, '
                'with their consent.',
            idName: 'HPR ID',
            hint: 'e.g. 71-1234-5678-9012',
            linkedId: data?.str('hprId'),
            onLink: isLive ? _linkHpr : null,
          ),
          D4Card(
            children: [
              const D4CardTitle('Qualifications'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < qualifications.length; i++) ...[
                    if (i > 0) ...[const SizedBox(height: 14), const MpDivider(), const SizedBox(height: 14)],
                    _qualificationRow(qualifications[i]),
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
          D4Card(
            children: [
              const D4CardTitle('Specialisations'),
              D4TagEditor(
                initial: _tags(const ['Diabetology', 'Internal medicine'], 'specialisations'),
                addTitle: 'Add specialisation',
                addLabel: 'Specialisation',
                addHint: 'e.g. Endocrinology',
                onChanged: (v) => _changes['specialisations'] = v,
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Conditions you treat'),
              const D4Note('Patients find you when they search these.'),
              D4TagEditor(
                initial: _tags(const ['Type 2 diabetes', 'Hypertension', 'Thyroid disorders', 'PCOS', 'Obesity'], 'conditionsTreated'),
                addTitle: 'Add condition',
                addLabel: 'Condition',
                addHint: 'e.g. Type 1 diabetes',
                onChanged: (v) => _changes['conditionsTreated'] = v,
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Experience'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: D4Field(
                      'Practising since',
                      _v('2010', (d) => d.str('practisingSince')),
                      keyboard: TextInputType.number,
                      onChanged: (v) => _changes['practisingSince'] = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: D4Field(
                      'Years',
                      data == null ? '14' : (years is num ? '${years.round()}' : ''),
                      keyboard: TextInputType.number,
                      trailing: Text('yrs', style: tx(14, c: MP.ink3)),
                      // Years is derived from "Practising since" unless that was edited too.
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n >= 0 && n < 80) _changes['practisingSince'] ??= '${DateTime.now().year - n}';
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Memberships and awards'),
              D4TagEditor(
                initial: _tags(const ['RSSDI member', 'API member'], 'memberships'),
                addTitle: 'Add membership or award',
                addLabel: 'Membership or award',
                addHint: 'e.g. ESI member',
                onChanged: (v) => _changes['memberships'] = v,
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
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Live: tap a qualification to remove it (DELETE /api/doctor/qualifications/:qid).
            onTap: isLive && q.id != null ? () => _removeQualification(q) : null,
            child: D4TitleSub(q.name, data != null && q.meta.isEmpty ? null : q.meta, weight: w700),
          ),
        ),
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

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/photo.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d8.dart';

/// Design: Profile.dc.html — "Profile" (Clinician · tabs): the doctor's
/// profile tab with clinic tools, letterhead, security and log out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _Tool {
  final String label;
  final String badge;
  final (Color, Color)? tone;
  final String stem;
  const _Tool(this.label, this.stem, {this.badge = '', this.tone});
}

const _tools = [
  _Tool('Practice', 'Practice'),
  _Tool('Plan & billing', 'Billing'),
  _Tool('Daily report', 'Daily-Report'),
  _Tool('Clinical alerts', 'Alerts', badge: '2 open', tone: (MP.redSoft, MP.red)),
  _Tool('People', 'People'),
  _Tool('Export data', 'Export'),
  _Tool('Chat review', 'Chat-Review', badge: '3 flagged', tone: (MP.fill, MP.ink2)),
  _Tool('Knowledge base', 'Knowledge'),
  _Tool('Patient feedback', 'Feedback'),
];

/// Language options used elsewhere in the design (Auth-Register).
const _languages = ['English', 'বাংলা (Bengali)', 'हिन्दी (Hindi)'];

const _signatureSvg =
    '<svg width="176" height="56" viewBox="0 0 176 56" fill="none" stroke="#111827" '
    'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M6 40c5-10 11-26 17-28 5-2 1 14-4 24-3 6-6 8-6 5 0-5 12-15 20-15 5 0 2 9 6 9 4 0 7-9 11-9 3 0 1 8 5 8 '
    '5 0 8-14 13-15 3 0-1 12 3 12 5 0 9-16 14-16 2 0 0 7 1 10 3-5 8-8 12-8 5 0 3 6 8 6 7 0 15-7 25-9"/>'
    '<path d="M22 46c24-5 60-8 110-8"/>'
    '<path d="M150 20c-3 4-4 9-1 10"/>'
    '</svg>';

class _ProfileScreenState extends State<ProfileScreen> with LiveData {
  bool _sampleAppLock = true;
  String _sampleLanguage = _languages.first;

  /// API codes of [_languages], in the same order.
  static const _languageCodes = ['en', 'bn', 'hi'];
  static const _roleNames = {
    'doctor': 'Doctor',
    'front_desk': 'Front desk',
    'doctor_assistant': 'Doctor assistant',
    'dietician': 'Dietician',
    'lab_manager': 'Lab manager',
    'lab_technician': 'Lab technician',
    'practice_manager': 'Practice manager',
  };

  /// GET /api/me, /api/doctor/profile, /api/practice, and the open-alert and
  /// flagged-chat counts for the tool badges (optional).
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/me'),
      Api.I.get('/api/doctor/profile'),
      Api.I.get('/api/practice'),
      d4Optional('/api/alerts', query: {'status': 'open'}),
      d4Optional('/api/inbox/reviews', query: {'status': 'needs_review'}),
    ]);
    return {'me': r[0], 'profile': r[1], 'practice': r[2], 'alerts': r[3], 'reviews': r[4]};
  }

  Map<String, dynamic> get _user => data!.obj('me').obj('user');
  Map<String, dynamic> get _p => data!.obj('profile');
  Map<String, dynamic> get _practice => data!.obj('practice');

  bool get _appLock => data == null ? _sampleAppLock : _user['appLock'] == true;

  String get _language {
    if (data == null) return _sampleLanguage;
    final i = _languageCodes.indexOf(_user.str('language', 'en'));
    return _languages[i < 0 ? 0 : i];
  }

  String get _name => data == null ? 'Dr. Arjun Sen' : _p.str('displayName', _user.str('name'));

  /// "9830041275" → "+91 98300 41275"
  String get _phone {
    if (data == null) return '+91 98300 41275';
    final p = _user.str('phone').replaceAll(RegExp(r'\D'), '');
    final ten = p.length > 10 ? p.substring(p.length - 10) : p;
    return ten.length == 10 ? '+91 ${ten.substring(0, 5)} ${ten.substring(5)}' : _user.str('phone');
  }

  /// "Doctor · Owner"
  String get _roleBadge {
    if (data == null) return 'Doctor · Owner';
    final role = _roleNames[_practice.str('role')] ?? 'Member';
    return _practice['isOwner'] == true ? '$role · Owner' : role;
  }

  /// "MBBS, MD (Medicine) · WBMC 64213"
  String get _credentials => data == null
      ? 'MBBS, MD (Medicine) · WBMC 64213'
      : [_p.str('degreesSummary'), _p.str('registrationDisplay')].where((s) => s.isNotEmpty).join(' · ');

  String? get _signatureUrl => data == null ? null : _p.obj('signature')['url'] as String?;
  bool get _hasSignature => data == null || _signatureUrl != null;

  String get _callNumber {
    if (data == null) return '+91 33 4000 1234';
    final n = _practice.obj('practice').str('patientCallNumber');
    return n.isEmpty ? 'Not set' : n;
  }

  /// Tool badges: open alerts and flagged AI answers (hidden at zero).
  List<_Tool> get _toolList {
    if (data == null) return _tools;
    final open = data!.obj('alerts').obj('counts').numOr('open').toInt();
    final flagged = data!.obj('reviews').numOr('flagged').toInt();
    return [
      for (final t in _tools)
        switch (t.stem) {
          'Alerts' => open > 0 ? _Tool(t.label, t.stem, badge: '$open open', tone: t.tone) : _Tool(t.label, t.stem),
          'Chat-Review' => flagged > 0 ? _Tool(t.label, t.stem, badge: '$flagged flagged', tone: t.tone) : _Tool(t.label, t.stem),
          _ => t,
        },
    ];
  }

  Future<void> _setAppLock(bool v) async {
    if (!isLive) {
      setState(() => _sampleAppLock = v);
      return;
    }
    setState(() => _user['appLock'] = v);
    final ok = await runAction(context, () => Api.I.patch('/api/me', {'appLock': v}));
    if (!mounted) return;
    if (ok == null) {
      setState(() => _user['appLock'] = !v);
      return;
    }
    toast(context, v ? 'App lock on' : 'App lock off');
  }

  Future<void> _replaceSignature() async {
    if (!isLive) {
      toast(context, 'Signature replaced');
      return;
    }
    // A photo of the signature on white paper (or a PNG with a clear background).
    final file = await Files.chooseSource(context, title: 'Digital signature', allowPdf: false);
    if (file == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.upload('/api/doctor/profile/signature', files: {'file': [file]}));
    if (ok == null || !mounted) return;
    toast(context, 'Signature saved · printed on every prescription');
    reload(quiet: true);
  }

  Future<void> _editCallNumber() async {
    if (!isLive) {
      Nav.go(context, 'Profile-Location');
      return;
    }
    final current = _practice.obj('practice').str('patientCallNumber');
    final r = await d4FormSheet(
      context,
      title: 'Patient call number',
      subtitle: 'Patients call this number from the app',
      fields: [D4FormField('Phone number', value: current, hint: 'e.g. +91 33 4000 1234', keyboard: TextInputType.phone)],
    );
    if (r == null || r.isEmpty || !mounted || r.first == current) return;
    final ok = await runAction(context, () => Api.I.patch('/api/practice', {'patientCallNumber': r.first}));
    if (ok == null || !mounted) return;
    toast(context, 'Patient call number saved');
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final tools = _toolList;
    return MpPage(
      nav: const ClinicianNav(current: 3),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D8TabHeader(),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 24,
            children: [
              _identity(),
              _Group(
                label: 'Account',
                child: _NavRow('Edit profile', onTap: () => Nav.go(context, 'Doctor-MyProfile')),
              ),
              _Group(
                label: 'Language',
                child: _NavRow(
                  'App language',
                  value: Text(_language, style: tx(14, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: _pickLanguage,
                ),
              ),
              _Group(
                label: 'Clinic tools',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tools.length; i++)
                      _NavRow(
                        tools[i].label,
                        divider: i > 0,
                        value:
                            tools[i].tone == null
                                ? null
                                : MpBadge(tools[i].badge, bg: tools[i].tone!.$1, fg: tools[i].tone!.$2),
                        onTap: () => Nav.go(context, tools[i].stem),
                      ),
                  ],
                ),
              ),
              _Group(label: 'Prescription letterhead', child: _letterhead(context)),
              _Group(
                label: 'Security',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      const Expanded(child: _TwoLine('App lock', 'Fingerprint or PIN to open')),
                      const Gap(12),
                      Semantics(
                        label: 'App lock',
                        child: MpSwitch(value: _appLock, onChanged: _setAppLock),
                      ),
                    ],
                  ),
                ),
              ),
              _Group(
                label: 'Clinic',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(child: _TwoLine('Patient call number', _callNumber, tabular: true)),
                      const Gap(12),
                      D8Link(
                        'Edit',
                        size: 15,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        semanticLabel: 'Edit patient call number',
                        onTap: _editCallNumber,
                      ),
                    ],
                  ),
                ),
              ),
              _Group(
                label: 'About',
                child: SizedBox(
                  height: 56,
                  child: Row(
                    // Label left, status flush right; the status shrinks
                    // (ellipsis) only if it can't fit.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('App version', style: tx(16)),
                      const Gap(12),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Ico(I.check, size: 16, color: MP.green, stroke: 2.25),
                            const Gap(6),
                            Flexible(
                              child: Text(
                                '3.8.2 · Up to date',
                                style: tx(14, c: MP.ink2, tab: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _Card(
                child: Semantics(
                  button: true,
                  child: Tap(
                    onTap: () => signOut(context),
                    radius: 0,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          const Ico(I.logout, size: 20, color: MP.ink),
                          const Gap(12),
                          Text('Log out', style: tx(16, w: w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identity() {
    return Row(
      children: [
        isLive ? MyPhotoAvatar(F.initials(_name), size: 72, fontSize: 26, weight: w600) : MpAvatar(F.initials(_name), size: 72, fontSize: 26, weight: w600),
        const Gap(16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name, style: tx(28, w: w800, h: 1.15, em: -0.02)),
              const Gap(4),
              Text(_phone, style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
              // Column gap 4px + `margin-top: 4px`.
              const Gap(8),
              MpBadge.blue(_roleBadge, weight: w600),
            ],
          ),
        ),
      ],
    );
  }

  Widget _letterhead(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tap(
          onTap: () => Nav.go(context, 'Profile-Professional'),
          radius: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: _TwoLine('Professional details', _credentials)),
                const Gap(12),
                const Ico(I.chevronRight, size: 18, color: MP.ink3),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(top: 16, bottom: 20),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TwoLine('Digital signature', _hasSignature ? 'Printed on every prescription' : 'Not added yet'),
                  ),
                  const Gap(12),
                  MpButton.small(_hasSignature ? 'Replace' : 'Add', expand: false, onTap: _replaceSignature),
                ],
              ),
              if (_hasSignature) ...[
                const Gap(12),
                // <figure>: the signature as printed.
                Semantics(
                  image: true,
                  label: 'Signature preview as printed',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: MP.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MP.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_signatureUrl != null)
                          Image.network(_signatureUrl!, width: 176, height: 56, fit: BoxFit.contain, alignment: Alignment.centerLeft)
                        else
                          const Svg(_signatureSvg, width: 176, height: 56),
                        Container(height: 1, margin: const EdgeInsets.only(top: 4), color: MP.line),
                        const Gap(8),
                        Text(_name, style: tx(14, w: w600, h: 20 / 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickLanguage() async {
    final picked = await openSheet<String>(
      context,
      (c) => MpSheet(
        title: 'App language',
        child: Column(
          children: [
            for (final o in _languages)
              Tap(
                onTap: () => Navigator.pop(c, o),
                radius: 12,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Expanded(child: Text(o, style: tx(16, w: o == _language ? w600 : w400))),
                      if (o == _language) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (!isLive) {
      setState(() => _sampleLanguage = picked);
      return;
    }
    if (picked == _language) return;
    final code = _languageCodes[_languages.indexOf(picked)];
    final ok = await runAction(context, () => Api.I.patch('/api/me', {'language': code}));
    if (ok == null || !mounted) return;
    toast(context, 'App language: $picked');
    reload(quiet: true);
  }
}

/// White settings card: radius 24, 1px border, `padding: 0 20px`.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => MpCard(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
}

/// Settings group: uppercase 12px label (`padding: 0 4px`), gap 8, card.
class _Group extends StatelessWidget {
  final String label;
  final Widget child;
  const _Group({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: SectionLabel(label, h: 1.35)),
        const Gap(8),
        _Card(child: child),
      ],
    );
  }
}

/// 56px settings row: label, optional value/badge, chevron. Rows after the
/// first add a 1px top border (`box-sizing: content-box`).
class _NavRow extends StatelessWidget {
  final String label;
  final Widget? value;
  final bool divider;
  final VoidCallback onTap;
  const _NavRow(this.label, {this.value, this.divider = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 0,
      child: Container(
        height: divider ? 57 : 56,
        decoration: divider ? const BoxDecoration(border: Border(top: BorderSide(color: MP.line))) : null,
        child: Row(
          children: [
            Expanded(child: Text(label, style: tx(16), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (value != null) ...[const Gap(12), value!],
            const Gap(12),
            const Ico(I.chevronRight, size: 18, color: MP.ink3),
          ],
        ),
      ),
    );
  }
}

/// 16/24 title over a 14/20 #545E72 line.
class _TwoLine extends StatelessWidget {
  final String title;
  final String sub;
  final bool tabular;
  const _TwoLine(this.title, this.sub, {this.tabular = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: tx(16, h: 1.5)),
        Text(sub, style: tx(14, c: MP.ink2, h: 20 / 14, tab: tabular), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

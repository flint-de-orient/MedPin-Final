import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Patient app · Profile tab ("My profile"). Not an artboard in the design
/// canvas: built from the front-desk Profile pattern (Staff-Profile) and the
/// patient's own data used across the patient screens.
///
/// Live data: GET /api/patient/me, GET /api/patient/care-team and the bell
/// (GET /api/notifications). Edits: PATCH /api/patient/me (details,
/// reminders, language, app lock), PATCH /api/patient/care-team/:userId,
/// POST /api/patient/consent-code, POST /api/me/support, /api/me/export and
/// /api/me/delete-request.
class PatientMeScreen extends StatefulWidget {
  const PatientMeScreen({super.key});

  @override
  State<PatientMeScreen> createState() => _PatientMeScreenState();
}

// ── Data ─────────────────────────────────────────────────────────────────────

class _Me {
  final String name;
  final int? age;
  final String gender;
  final String phone;
  final double? heightCm;
  final double? weightKg;
  final String? bloodGroup;
  final String? emergencyName;
  final String? emergencyPhone;
  const _Me({
    required this.name,
    required this.age,
    required this.gender,
    required this.phone,
    required this.heightCm,
    required this.weightKg,
    this.bloodGroup,
    this.emergencyName,
    this.emergencyPhone,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  double? get bmi => heightCm == null || weightKg == null ? null : weightKg! / ((heightCm! / 100) * (heightCm! / 100));
}

const _conditions = ['Type 2 diabetes', 'PCOS'];
const _allergy = 'Sulfa drugs';

/// What a person on the care team can see, most to least.
const _levels = [
  'Full record, daily log and tracked vitals',
  'Full record',
  'Prescriptions and test results',
  'Daily log only',
];
const _stopSharing = 'Not shared';

class _Viewer {
  final String initials;
  final String name;
  final String role;

  /// Live only: their user id.
  final String? userId;
  const _Viewer(this.initials, this.name, this.role, {this.userId});
}

const _viewers = [
  _Viewer('AS', 'Dr. Arjun Sen', 'Diabetes · City Care Clinic'),
  _Viewer('RM', 'Dr. Rina Mitra', 'Heart · City Care Clinic'),
  _Viewer('NG', 'Dr. Nandita Gupta', 'Gynaecology · Apollo Clinic'),
  _Viewer('MO', 'Mou', 'Dietician · City Care Clinic'),
];

const _languages = ['English', 'हिन्दी (Hindi)', 'বাংলা (Bengali)'];
const _languageCodes = ['en', 'hi', 'bn'];
const _bloodGroups = ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−', 'Not sure'];

const _roleLabels = {
  'doctor': 'Doctor',
  'dietician': 'Dietician',
  'front_desk': 'Front desk',
  'doctor_assistant': 'Assistant',
  'lab_manager': 'Lab',
  'lab_technician': 'Lab',
  'practice_manager': 'Clinic manager',
};

/// 'A−' ↔ 'A-', 'Not sure' ↔ 'not_sure'.
String? _bloodToApi(String? v) => v == null ? null : (v == 'Not sure' ? 'not_sure' : v.replaceAll('−', '-'));
String? _bloodFromApi(Object? v) => v == null ? null : (v == 'not_sure' ? 'Not sure' : '$v'.replaceAll('-', '−'));

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "9876543210" → "98765 43210".
String _phoneText(String p) {
  final d = p.replaceAll(RegExp(r'\D'), '');
  final ten = d.length > 10 ? d.substring(d.length - 10) : d;
  return ten.length == 10 ? '${ten.substring(0, 5)} ${ten.substring(5)}' : p;
}

/// "20:00" → "8:00 PM".
String _clock(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm);
  if (m == null) return hhmm;
  return F.time(DateTime(2026, 1, 1, int.parse(m[1]!), int.parse(m[2]!)));
}

// Icons used here that aren't in the shared set (24×24, stroke).
const _icGlobe = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>';
const _icHelp = '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>';
const _icCopy = '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>';
const _icRuler = '<path d="M21.3 15.3 8.7 2.7a1 1 0 0 0-1.4 0L2.7 7.3a1 1 0 0 0 0 1.4l12.6 12.6a1 1 0 0 0 1.4 0l4.6-4.6a1 1 0 0 0 0-1.4Z"/><path d="m7.5 10.5 2-2M10.5 13.5l2-2M13.5 16.5l2-2"/>';

// ── Screen ───────────────────────────────────────────────────────────────────

class _PatientMeScreenState extends State<PatientMeScreen> with LiveData {
  _Me _sample = const _Me(
    name: 'Priya Sharma',
    age: 29,
    gender: 'Female',
    phone: '98765 43210',
    heightCm: 158,
    weightKg: 68.5,
  );
  final List<String> _sharing = [_levels[0], _levels[1], _levels[2], _levels[3]];
  String _language = _languages.first;
  bool _medReminders = true;
  bool _logReminder = true;
  bool _visitReminders = true;
  bool _appLock = true;

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/patient/me'),
      Api.I.get('/api/patient/care-team'),
      Api.I.get('/api/notifications', query: {'limit': 20}).then<Object?>((v) => v, onError: (_) => null),
    ]);
    return {'me': r[0], 'team': r[1], 'notifications': r[2]};
  }

  Map<String, dynamic> get _p => data?.obj('me') ?? const {};
  Map<String, dynamic> get _settings => _p.obj('settings');

  _Me get _me {
    if (data == null) return _sample;
    final ec = _p.obj('emergencyContact');
    return _Me(
      name: _p.str('name'),
      age: (_p['age'] as num?)?.toInt(),
      gender: _cap(_p.str('gender')),
      phone: _phoneText(_p.str('phone')),
      heightCm: (_p['heightCm'] as num?)?.toDouble(),
      weightKg: (_p['weightKg'] as num?)?.toDouble(),
      bloodGroup: _bloodFromApi(_p['bloodGroup']),
      emergencyName: ec.str('name').isEmpty ? null : ec.str('name'),
      emergencyPhone: ec.str('name').isEmpty || ec.str('phone').isEmpty ? null : _phoneText(ec.str('phone')),
    );
  }

  List<String> get _conditionList => data == null ? _conditions : [for (final c in _p.list('conditions')) c.str('name')];
  List<String> get _allergyList => data == null ? const [_allergy] : [for (final a in _p.list('allergies')) a.str('allergen')];

  List<Map<String, dynamic>> get _team => data?.list('team') ?? const [];

  List<(_Viewer, String)> get _viewerRows {
    if (data == null) return [for (var i = 0; i < _viewers.length; i++) (_viewers[i], _sharing[i])];
    return [
      for (final t in _team)
        (
          _Viewer(
            F.initials(t.str('name')),
            t.str('name'),
            [
              t.str('specialty', t.str('headline', _roleLabels[t.str('role')] ?? '')),
              t.str('practice'),
            ].where((x) => x.isNotEmpty).join(' · '),
            userId: t.str('userId'),
          ),
          p2AccessLevels[t.str('accessLevel')] ?? _levels[1],
        ),
    ];
  }

  bool get _medR => data == null ? _medReminders : _settings['medReminders'] != false;
  bool get _logR => data == null ? _logReminder : _settings['dailyLogReminder'] != false;
  bool get _visitR => data == null ? _visitReminders : _settings['visitReminders'] != false;
  bool get _lock => data == null ? _appLock : _p['appLock'] == true;
  String get _lang {
    if (data == null) return _language;
    final i = _languageCodes.indexOf(_p.str('language', 'en'));
    return _languages[i < 0 ? 0 : i];
  }

  int get _unreadNotifications => data == null ? 1 : data!.obj('notifications').numOr('unread').toInt();

  /// PATCH /api/patient/me and show the saved profile. Returns false on error.
  Future<bool> _save(Map<String, dynamic> body) async {
    final res = await runAction(context, () => Api.I.patch('/api/patient/me', body));
    if (res is! Map || !mounted) return false;
    setState(() => data = {...?data, 'me': res.cast<String, dynamic>()});
    return true;
  }

  /// A reminder / app-lock switch: flips at once, reverts if saving fails.
  Future<void> _toggle(String key, bool value, {bool setting = true}) async {
    final me = Map<String, dynamic>.of(_p);
    if (setting) {
      me['settings'] = {..._settings, key: value};
    } else {
      me[key] = value;
    }
    final before = data;
    setState(() => data = {...?data, 'me': me});
    final ok = await _save(setting ? {'settings': {key: value}} : {key: value});
    if (!ok && mounted) setState(() => data = before);
  }

  Future<void> _edit() async {
    final updated = await openSheet<_Me>(context, (_) => _EditSheet(me: _me));
    if (updated == null || !mounted) return;
    if (data == null) {
      setState(() => _sample = updated);
      toast(context, 'Profile updated');
      return;
    }
    final phone = (updated.emergencyPhone ?? '').replaceAll(RegExp(r'\D'), '');
    final ok = await _save({
      'name': updated.name,
      if (updated.age != null) 'ageYears': updated.age,
      'gender': updated.gender.toLowerCase(),
      if (updated.heightCm != null) 'heightCm': updated.heightCm,
      if (updated.weightKg != null) 'weightKg': updated.weightKg,
      if (updated.bloodGroup != null) 'bloodGroup': _bloodToApi(updated.bloodGroup),
      'emergencyContact': updated.emergencyName == null
          ? {'name': null}
          : {'name': updated.emergencyName, if (phone.isNotEmpty) 'phone': phone.length > 10 ? phone.substring(phone.length - 10) : phone},
    });
    if (ok && mounted) toast(context, 'Profile updated');
  }

  Future<void> _manage(int i) async {
    final (v, current) = _viewerRows[i];
    final level = await openSheet<String>(context, (_) => _SharingSheet(viewer: v, current: current));
    if (level == null || !mounted || level == current) return;
    if (data != null) {
      final key = p2AccessLevels.entries.firstWhere((e) => e.value == level, orElse: () => const MapEntry('not_shared', '')).key;
      final ok = await runAction(context, () => Api.I.patch('/api/patient/care-team/${v.userId}', {'accessLevel': key}));
      if (ok == null || !mounted) return;
      reload(quiet: true);
    } else {
      setState(() => _sharing[i] = level);
    }
    toast(context, level == _stopSharing ? 'Stopped sharing with ${v.name}' : '${v.name} can now see: ${level.toLowerCase()}');
  }

  Future<void> _pickLanguage() async {
    final l = await openSheet<String>(
      context,
      (_) => _PickSheet(title: 'App language', subtitle: 'MedPin and your reminders use this language.', options: _languages, value: _lang),
    );
    if (l == null || !mounted || l == _lang) return;
    if (data == null) {
      setState(() => _language = l);
      return;
    }
    await _save({'language': _languageCodes[_languages.indexOf(l)]});
  }

  Future<void> _logOut() async {
    final ok = await openSheet<bool>(context, (_) => const _LogOutSheet());
    if (ok != true || !mounted) return;
    if (isLive) {
      await signOut(context);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _notifications() async {
    if (data == null) {
      toast(context, 'Notifications are not in the design yet');
      return;
    }
    final items = data!.obj('notifications').list('items');
    await openSheet<void>(context, (_) => _NotificationsSheet(items: items));
    if (!mounted || _unreadNotifications == 0) return;
    await runAction(context, () => Api.I.post('/api/notifications/read-all'));
    if (mounted) reload(quiet: true);
  }

  Future<void> _help() async {
    if (data == null) {
      toast(context, 'Help is not in the design yet');
      return;
    }
    await openSheet<void>(context, (_) => const _HelpSheet());
  }

  Future<void> _privacy() async {
    if (data == null) {
      toast(context, 'Privacy and terms are not in the design yet');
      return;
    }
    final i = await openSheet<int>(
      context,
      (_) => const P2ActionSheet(
        title: 'Privacy and data',
        actions: [(I.download, 'Download my data', false), (I.alert, 'Delete my account', true)],
      ),
    );
    if (i == null || !mounted) return;
    if (i == 0) {
      final r = await runAction(context, () => Api.I.post('/api/me/export'));
      if (r is Map && mounted) await p2Open(context, r['url'] as String?, failed: "Couldn't open your data file");
      return;
    }
    final sure = await openSheet<bool>(
      context,
      (_) => const P2ConfirmSheet(
        title: 'Delete your MedPin account?',
        subtitle: 'We will check with your clinics, then delete your account and tell you by SMS.',
        confirm: 'Ask to delete',
      ),
    );
    if (sure != true || !mounted) return;
    final r = await runAction(context, () => Api.I.post('/api/me/delete-request', {'reason': 'Requested from the patient app'}));
    if (r != null && mounted) toast(context, 'Request sent. Our team will contact you.');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final me = _me;
    final viewers = _viewerRows;
    final allergies = _allergyList;
    final conditions = _conditionList;
    final logAt = data == null ? '8:00 PM' : _clock(_settings.str('dailyLogReminderAt', '20:00'));
    return MpPage(
      nav: const PatientNav(current: 4),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(),
          if (placeholder != null)
            placeholder
          else
            VGap(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              gap: 24,
              children: [
                _identity(me),
                _ConsentCard(live: data != null),
                _section('Health details', [
                  _Row(
                    icon: I.activity,
                    title: 'Conditions',
                    sub: conditions.isEmpty ? 'None added' : null,
                    subColor: MP.ink3,
                    below: conditions.isEmpty ? null : Wrap(spacing: 6, runSpacing: 6, children: [for (final c in conditions) _Tag(c)]),
                    onTap: _edit,
                  ),
                  _Row(
                    icon: I.alert,
                    title: 'Allergies',
                    sub: allergies.isEmpty ? 'None added' : null,
                    subColor: MP.ink3,
                    below: allergies.isEmpty
                        ? null
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final a in allergies)
                                MpBadge(a, bg: MP.amberSoft, fg: MP.amber, border: MP.amberLine, icon: I.alert, weight: w600, padX: 8),
                            ],
                          ),
                    onTap: _edit,
                  ),
                  _Row(
                    icon: _icRuler,
                    title: 'Height and weight',
                    sub: me.heightCm == null && me.weightKg == null
                        ? 'Not added'
                        : [
                            if (me.heightCm != null) '${_fmt(me.heightCm!)} cm',
                            if (me.weightKg != null) '${_fmt(me.weightKg!)} kg',
                            if (me.bmi != null) 'BMI ${me.bmi!.toStringAsFixed(1)}',
                          ].join(' · '),
                    subColor: me.heightCm == null && me.weightKg == null ? MP.ink3 : MP.ink2,
                    trailing: me.heightCm == null && me.weightKg == null ? const _Action('Add') : const _Chevron(),
                    onTap: _edit,
                  ),
                  _Row(
                    icon: I.drop,
                    title: 'Blood group',
                    sub: me.bloodGroup ?? 'Not added',
                    subColor: me.bloodGroup == null ? MP.ink3 : MP.ink2,
                    trailing: me.bloodGroup == null ? const _Action('Add') : const _Chevron(),
                    onTap: _edit,
                  ),
                  _Row(
                    icon: I.phone,
                    title: 'Emergency contact',
                    sub: me.emergencyName == null
                        ? 'Someone we can call for you'
                        : '${me.emergencyName}${me.emergencyPhone == null ? '' : ' · +91 ${me.emergencyPhone}'}',
                    subColor: me.emergencyName == null ? MP.ink3 : MP.ink2,
                    trailing: me.emergencyName == null ? const _Action('Add') : const _Chevron(),
                    onTap: _edit,
                  ),
                ]),
                if (viewers.isNotEmpty)
                  _section(
                    'Who can see my records',
                    [
                      for (var i = 0; i < viewers.length; i++)
                        _Row(
                          leading: MpAvatar(viewers[i].$1.initials, size: 40, fontSize: 14),
                          title: viewers[i].$1.name,
                          sub: viewers[i].$2,
                          subColor: viewers[i].$2 == _stopSharing ? MP.ink3 : MP.ink2,
                          meta: viewers[i].$1.role,
                          trailing: const _Action('Manage'),
                          onTap: () => _manage(i),
                        ),
                    ],
                    caption: 'You decide who sees what. They are told when you change it.',
                  ),
                _section('Reminders', [
                  _Row(
                    icon: I.pill,
                    title: 'Medicine reminders',
                    sub: 'At each dose time',
                    trailing: MpSwitch(value: _medR, onChanged: (v) => _setReminder('medReminders', v)),
                    onTap: () => _setReminder('medReminders', !_medR),
                  ),
                  _Row(
                    icon: I.edit,
                    title: 'Daily log reminder',
                    sub: '$logAt every day',
                    trailing: MpSwitch(value: _logR, onChanged: (v) => _setReminder('dailyLogReminder', v)),
                    onTap: () => _setReminder('dailyLogReminder', !_logR),
                  ),
                  _Row(
                    icon: I.calendar,
                    title: 'Visit reminders',
                    sub: 'A day before and 2 hours before',
                    trailing: MpSwitch(value: _visitR, onChanged: (v) => _setReminder('visitReminders', v)),
                    onTap: () => _setReminder('visitReminders', !_visitR),
                  ),
                ]),
                _section('General', [
                  _Row(
                    icon: _icGlobe,
                    title: 'Language',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_lang, style: tx(14, c: MP.ink2)),
                      const Gap(12),
                      const _Chevron(),
                    ]),
                    onTap: _pickLanguage,
                  ),
                  _Row(
                    icon: I.lock,
                    title: 'App lock',
                    sub: 'Fingerprint or PIN to open MedPin',
                    trailing: MpSwitch(value: _lock, onChanged: _setAppLock),
                    onTap: () => _setAppLock(!_lock),
                  ),
                  _Row(
                    icon: _icHelp,
                    title: 'Help and support',
                    trailing: const _Chevron(),
                    onTap: _help,
                  ),
                  _Row(
                    icon: I.shield,
                    title: 'Privacy and terms',
                    trailing: const _Chevron(),
                    onTap: _privacy,
                  ),
                ]),
                _card([
                  _Row(
                    icon: I.logout,
                    title: 'Log out',
                    onTap: _logOut,
                  ),
                ]),
                Text(
                  'MedPin 1.0.0 · Care Connected',
                  textAlign: TextAlign.center,
                  style: tx(13, c: MP.ink3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _setReminder(String key, bool v) {
    if (data == null) {
      setState(() {
        switch (key) {
          case 'medReminders':
            _medReminders = v;
          case 'dailyLogReminder':
            _logReminder = v;
          default:
            _visitReminders = v;
        }
      });
      return;
    }
    _toggle(key, v);
  }

  void _setAppLock(bool v) {
    if (data == null) {
      setState(() => _appLock = v);
      return;
    }
    _toggle('appLock', v, setting: false);
  }

  // Logo + bell, as on the front-desk Profile tab.
  Widget _topBar() {
    final unread = _unreadNotifications;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          const MpLogo(),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              MpIconButton(
                I.bell,
                label: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
                onTap: _notifications,
              ),
              if (unread > 0)
                Positioned(
                  top: 10,
                  right: 11,
                  child: IgnorePointer(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: MP.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: MP.bg, width: 2),
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

  Widget _identity(_Me me) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            MpAvatar(me.initials, size: 72, fontSize: 24),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    me.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tx(28, w: w800, h: 1.15, em: -0.02),
                  ),
                  const Gap(4),
                  Text('+91 ${me.phone}', style: tx(14, c: MP.ink2, tab: true)),
                  const Gap(6),
                  MpBadge([if (me.age != null) '${me.age} yrs', me.gender].where((x) => x.isNotEmpty).join(' · '), weight: w600),
                ],
              ),
            ),
            const Gap(8),
            MpIconButton(I.pencil, label: 'Edit your details', color: MP.primary, iconSize: 20, onTap: _edit),
          ],
        ),
      );

  Widget _section(String label, List<Widget> rows, {String? caption}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: SectionLabel(label, h: 1.35),
          ),
          const Gap(8),
          _card(rows),
          if (caption != null) ...[
            const Gap(8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(caption, style: tx(13, c: MP.ink3, h: 1.4)),
            ),
          ],
        ],
      );

  /// White card (radius 24, 1px #E5E9F0, padding 4/20) with hairlines between rows.
  Widget _card(List<Widget> rows) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        decoration: MPDeco.card(),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const MpDivider(),
              rows[i],
            ],
          ],
        ),
      );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

// ── Pieces ───────────────────────────────────────────────────────────────────

/// Settings row: 22px #545E72 icon (or a leading widget), 16/600 title,
/// optional 14px line, optional widget under it, trailing control.
class _Row extends StatelessWidget {
  final String? icon;
  final Widget? leading;
  final String title;
  final String? sub;
  final Color subColor;
  final String? meta;
  final Widget? below;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({
    this.icon,
    this.leading,
    required this.title,
    this.sub,
    this.subColor = MP.ink2,
    this.meta,
    this.below,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        if (leading != null) ...[leading!, const Gap(12)],
        if (icon != null) ...[Ico(icon!, size: 22, color: MP.ink2), const Gap(12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: tx(16, w: w600, h: 1.4)),
              if (meta != null) Text(meta!, style: tx(13, c: MP.ink3, h: 1.4)),
              if (sub != null) ...[
                const Gap(2),
                Text(sub!, style: tx(14, c: subColor, h: 1.4)),
              ],
              if (below != null) ...[const Gap(8), below!],
            ],
          ),
        ),
        if (trailing != null) ...[const Gap(12), trailing!],
      ],
    );
    return Tap(
      onTap: onTap,
      radius: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: content),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();
  @override
  Widget build(BuildContext context) => const Ico(I.chevronRight, size: 18, color: MP.ink3);
}

class _Action extends StatelessWidget {
  final String label;
  const _Action(this.label);
  @override
  Widget build(BuildContext context) => Text(label, style: tx(14, w: w600, c: MP.primary));
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => MpBadge(text, weight: w600, padX: 10);
}

// ── Consent code ─────────────────────────────────────────────────────────────

/// The code a clinic asks for to link this record to their practice
/// (see Add-Patient-Existing). It changes every 60 seconds.
///
/// Live: each code comes from POST /api/patient/consent-code and counts down
/// to its own expiry.
class _ConsentCard extends StatefulWidget {
  final bool live;
  const _ConsentCard({this.live = false});
  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends State<_ConsentCard> {
  static const _period = 60;
  int _seed = 0;
  int _left = _period;
  Timer? _timer;

  /// Live: the current code and when it expires.
  String? _liveCode;
  DateTime? _expiresAt;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    if (widget.live) _fetch();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (widget.live) {
          final exp = _expiresAt;
          if (exp == null) return;
          _left = exp.difference(DateTime.now()).inSeconds.clamp(0, _period);
          if (_left <= 0) _fetch();
        } else if (--_left <= 0) {
          _next();
        }
      });
    });
  }

  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final r = await Api.I.post('/api/patient/consent-code');
      if (!mounted || r is! Map) return;
      setState(() {
        _liveCode = '${r['code']}';
        _expiresAt = F.date(r['expiresAt']) ?? DateTime.now().add(const Duration(seconds: _period));
        _left = _expiresAt!.difference(DateTime.now()).inSeconds.clamp(0, _period);
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _expiresAt = DateTime.now().add(const Duration(seconds: 15))); // try again shortly
        toast(context, e.message);
      }
    } finally {
      _fetching = false;
    }
  }

  void _next() {
    _seed++;
    _left = _period;
  }

  /// Six digits; the first matches the code typed in Add-Patient-Existing.
  String get _code {
    if (widget.live) return _liveCode ?? '······';
    if (_seed == 0) return '482917';
    final n = (482917 + _seed * 7919 * 104729) % 1000000;
    return n.toString().padLeft(6, '0');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final white82 = MP.white.withValues(alpha: 0.82);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MP.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: MPShadow.hero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MP.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MP.white.withValues(alpha: 0.22)),
                ),
                child: const Ico(I.shield, size: 22, color: MP.white),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your consent code', style: tx(17, w: w700, c: MP.white)),
                    const Gap(4),
                    Text(
                      'Give this to a clinic to link your MedPin record. Only you can see it.',
                      style: tx(14, c: white82, h: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(18),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Consent code ${code.split('').join(' ')}',
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${code.substring(0, 3)} ${code.substring(3)}',
                        style: tx(34, w: w800, c: MP.white, h: 1.1, em: 0.08, tab: true),
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(12),
              SizedBox(
                height: 40,
                child: Tap(
                  onTap: () {
                    if (widget.live && _liveCode == null) return;
                    Clipboard.setData(ClipboardData(text: code));
                    toast(context, 'Code copied');
                  },
                  radius: 12,
                  color: MP.white.withValues(alpha: 0.16),
                  border: MP.white.withValues(alpha: 0.28),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(_icCopy, size: 16, color: MP.white, stroke: 2),
                      const Gap(6),
                      Text('Copy', style: tx(14, w: w600, c: MP.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Gap(16),
          MpProgress(
            _left / _period,
            height: 4,
            color: MP.white,
            track: MP.white.withValues(alpha: 0.18),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Changes in 0:${_left.toString().padLeft(2, '0')}',
                  style: tx(13, c: white82, tab: true),
                ),
              ),
              Tap(
                onTap: () => widget.live ? _fetch() : setState(_next),
                radius: 8,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('New code', style: tx(14, w: w600, c: MP.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

class _EditSheet extends StatefulWidget {
  final _Me me;
  const _EditSheet({required this.me});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(text: widget.me.name);
  late final _age = TextEditingController(text: widget.me.age == null ? '' : '${widget.me.age}');
  late final _height = TextEditingController(text: widget.me.heightCm == null ? '' : _PatientMeScreenState._fmt(widget.me.heightCm!));
  late final _weight = TextEditingController(text: widget.me.weightKg == null ? '' : _PatientMeScreenState._fmt(widget.me.weightKg!));
  late final _ecName = TextEditingController(text: widget.me.emergencyName ?? '');
  late final _ecPhone = TextEditingController(text: widget.me.emergencyPhone ?? '');
  late String _gender = widget.me.gender;
  late String? _blood = widget.me.bloodGroup;

  @override
  void dispose() {
    for (final c in [_name, _age, _height, _weight, _ecName, _ecPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final m = widget.me;
    double? num(TextEditingController c, double? fallback) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;
    final name = _ecName.text.trim();
    final phone = _ecPhone.text.trim();
    Navigator.pop(
      context,
      _Me(
        name: _name.text.trim().isEmpty ? m.name : _name.text.trim(),
        age: int.tryParse(_age.text.trim()) ?? m.age,
        gender: _gender,
        phone: m.phone,
        heightCm: num(_height, m.heightCm)?.clamp(50, 250).toDouble(),
        weightKg: num(_weight, m.weightKg)?.clamp(2, 400).toDouble(),
        bloodGroup: _blood,
        emergencyName: name.isEmpty ? null : name,
        emergencyPhone: name.isEmpty || phone.isEmpty ? null : phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const genders = ['Female', 'Male', 'Other'];
    return MpSheet(
      child: VGap(
        gap: 16,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: P2SheetHeader(title: 'Edit details', subtitle: 'Your doctors see these on your record.'),
          ),
          MpInput(label: 'Full name', controller: _name),
          MpInput(
            label: 'Phone number',
            value: widget.me.phone,
            prefixText: '+91',
            readOnly: true,
            tab: true,
            trailing: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Ico(I.check, size: 18, color: MP.green, stroke: 2.25),
                const Gap(6),
                Text('Verified', style: tx(14, w: w600, c: MP.green)),
              ]),
            ),
            help: 'You sign in with this number. To change it, contact your clinic.',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: MpInput(label: 'Age', controller: _age, unit: 'yrs', keyboard: TextInputType.number, tab: true),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MpLabel('Gender'),
                    const Gap(8),
                    MpSegmented(
                      options: genders,
                      index: genders.indexOf(_gender).clamp(0, 2),
                      height: 40,
                      fontSize: 14,
                      onChanged: (i) => setState(() => _gender = genders[i]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: MpInput(label: 'Height', controller: _height, unit: 'cm', keyboard: const TextInputType.numberWithOptions(decimal: true), tab: true),
              ),
              const Gap(12),
              Expanded(
                child: MpInput(label: 'Weight', controller: _weight, unit: 'kg', keyboard: const TextInputType.numberWithOptions(decimal: true), tab: true),
              ),
            ],
          ),
          MpSelect(
            label: 'Blood group',
            value: _blood ?? 'Not added',
            options: _bloodGroups,
            leadingIcon: I.drop,
            onChanged: (v) => setState(() => _blood = v),
          ),
          const Gap(4),
          const SectionLabel('Emergency contact', h: 1.35),
          MpInput(label: 'Name', controller: _ecName, hint: 'e.g. Rohit Sharma'),
          MpInput(label: 'Phone', controller: _ecPhone, prefixText: '+91', keyboard: TextInputType.phone, hint: '10-digit mobile', tab: true),
          const Gap(4),
          MpButton('Save', onTap: _save),
        ],
      ),
    );
  }
}

class _SharingSheet extends StatefulWidget {
  final _Viewer viewer;
  final String current;
  const _SharingSheet({required this.viewer, required this.current});
  @override
  State<_SharingSheet> createState() => _SharingSheetState();
}

class _SharingSheetState extends State<_SharingSheet> {
  late String _level = widget.current;

  @override
  Widget build(BuildContext context) {
    final v = widget.viewer;
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: P2SheetHeader(title: 'What ${v.name} can see', subtitle: v.role),
          ),
          const Gap(16),
          for (var i = 0; i < _levels.length + 1; i++) ...[
            if (i > 0) const MpDivider(),
            _option(i < _levels.length ? _levels[i] : _stopSharing),
          ],
          const Gap(20),
          MpButton('Save', onTap: () => Navigator.pop(context, _level)),
        ],
      ),
    );
  }

  Widget _option(String level) {
    final stop = level == _stopSharing;
    final on = _level == level;
    return Tap(
      onTap: () => setState(() => _level = level),
      radius: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  stop ? 'Stop sharing' : level,
                  style: tx(16, w: on ? w600 : w500, c: stop ? MP.red : MP.ink, h: 1.4),
                ),
              ),
              const Gap(12),
              P2Radio(on),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> options;
  final String value;
  const _PickSheet({required this.title, required this.subtitle, required this.options, required this.value});

  @override
  Widget build(BuildContext context) => MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: P2SheetHeader(title: title, subtitle: subtitle),
            ),
            const Gap(12),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const MpDivider(),
              Tap(
                onTap: () => Navigator.pop(context, options[i]),
                radius: 0,
                child: SizedBox(
                  height: 56,
                  child: Row(children: [
                    Expanded(child: Text(options[i], style: tx(16, w: options[i] == value ? w600 : w500))),
                    P2Radio(options[i] == value),
                  ]),
                ),
              ),
            ],
          ],
        ),
      );
}

class _LogOutSheet extends StatelessWidget {
  const _LogOutSheet();
  @override
  Widget build(BuildContext context) => MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: P2SheetHeader(
                title: 'Log out of MedPin?',
                subtitle: 'Your records stay safe. Sign in again with your phone number.',
              ),
            ),
            const Gap(24),
            MpButton('Log out', kind: MpBtn.danger, onTap: () => Navigator.pop(context, true)),
            const Gap(12),
            MpButton('Cancel', kind: MpBtn.secondary, onTap: () => Navigator.pop(context, false)),
          ],
        ),
      );
}

/// The bell: recent notifications (GET /api/notifications).
class _NotificationsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _NotificationsSheet({required this.items});

  @override
  Widget build(BuildContext context) => MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: P2SheetHeader(title: 'Notifications', subtitle: 'Visits, messages and reports from your clinics.'),
            ),
            const Gap(12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Nothing new yet.', style: tx(15, c: MP.ink2)),
              ),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const MpDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: items[i]['readAt'] == null ? MP.primary : MP.lineStrong,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].str('title'), style: tx(15, w: w600, h: 1.4)),
                          if (items[i].str('body').isNotEmpty) Text(items[i].str('body'), style: tx(14, c: MP.ink2, h: 1.4)),
                        ],
                      ),
                    ),
                    const Gap(12),
                    if (F.date(items[i]['createdAt']) case final at?) Text(F.ago(at), style: tx(13, c: MP.ink3)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

/// Help and support: the support contacts (GET /api/me/support) and a message
/// to the MedPin team (POST /api/me/support).
class _HelpSheet extends StatefulWidget {
  const _HelpSheet();
  @override
  State<_HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends State<_HelpSheet> {
  final _msg = TextEditingController();
  final _busy = ValueNotifier(false);
  Map<String, dynamic> _contacts = const {};

  @override
  void initState() {
    super.initState();
    Api.I.get('/api/me/support').then((r) {
      if (mounted && r is Map) setState(() => _contacts = r.cast<String, dynamic>());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _msg.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msg.text.trim();
    final r = await runAction(context, () => Api.I.post('/api/me/support', {'topic': 'problem', 'message': text, 'platform': 'app'}), busy: _busy);
    if (r == null || !mounted) return;
    Navigator.pop(context);
    toast(context, 'Message sent. We will reply by phone or email.');
  }

  @override
  Widget build(BuildContext context) {
    final phone = _contacts.str('phone');
    final email = _contacts.str('email');
    return MpSheet(
      child: VGap(
        gap: 16,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: P2SheetHeader(title: 'Help and support', subtitle: 'Tell us what went wrong. A person from MedPin will reply.'),
          ),
          if (phone.isNotEmpty || email.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  if (phone.isNotEmpty) Tap(onTap: () => p2Open(context, 'tel:$phone'), child: MpKV('Call', phone, vColor: MP.primary)),
                  if (phone.isNotEmpty && email.isNotEmpty) const MpDivider(),
                  if (email.isNotEmpty) Tap(onTap: () => p2Open(context, 'mailto:$email'), child: MpKV('Email', email, vColor: MP.primary)),
                ],
              ),
            ),
          MpInput(label: 'Your message', controller: _msg, hint: 'e.g. My reminders stopped coming', maxLines: 4, height: 120),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, __) => MpButton(busy ? 'Sending…' : 'Send message', onTap: busy ? null : _send),
          ),
        ],
      ),
    );
  }
}

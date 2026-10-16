import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/photo.dart';
import '../../data/session.dart';
import '../../widgets/clinic_switch.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'profile_booking.dart';
import 'profile_leave.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-MyProfile.dc.html — "Doctor · My profile (settings hub)".
class DoctorMyprofileScreen extends StatefulWidget {
  const DoctorMyprofileScreen({super.key});

  @override
  State<DoctorMyprofileScreen> createState() => _DoctorMyprofileScreenState();
}

class _DoctorMyprofileScreenState extends State<DoctorMyprofileScreen> with LiveData {
  static const _spoken = ['English', 'Bengali', 'Hindi', 'Urdu', 'Odia', 'Assamese'];
  static const _appLanguages = ['English', 'Bengali', 'Hindi'];
  static const _languageCodes = {'English': 'en', 'Bengali': 'bn', 'Hindi': 'hi'};

  List<String> _sampleLanguages = const ['English', 'Bengali'];
  String _sampleAppLanguage = 'English';

  /// GET /api/doctor/profile, /api/me, /api/doctor/locations, plus the team
  /// and plan rows (optional: they stay blank if the member can't see them).
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/doctor/profile'),
      Api.I.get('/api/me'),
      Api.I.get('/api/doctor/locations'),
      d4Optional('/api/members'),
      d4Optional('/api/billing'),
    ]);
    return {'profile': r[0], 'me': r[1], 'locations': r[2], 'members': r[3], 'billing': r[4]};
  }

  Map<String, dynamic> get _p => data!.obj('profile');
  Map<String, dynamic> get _user => data!.obj('me').obj('user');

  List<String> get _languages =>
      data == null ? _sampleLanguages : [for (final l in (_p['languagesSpoken'] as List? ?? const [])) '$l'];

  String get _appLanguage {
    if (data == null) return _sampleAppLanguage;
    final code = _user.str('language', 'en');
    return _languageCodes.entries.firstWhere((e) => e.value == code, orElse: () => _languageCodes.entries.first).key;
  }

  String get _name => data == null ? 'Dr. Arjun Sen' : _p.str('displayName', Session.I.name);
  String get _headline => data == null ? 'Diabetologist · Internal medicine' : _p.str('headline');
  bool get _verified => data == null || _p['isVerified'] == true;

  /// "MBBS, MD · WBMC 64213 · 14 yrs"
  String get _credentials {
    if (data == null) return 'MBBS, MD · WBMC 64213 · 14 yrs';
    final years = _p['yearsExperience'];
    return [
      _p.str('degreesSummary'),
      _p.str('registrationDisplay'),
      if (years is num) '${years.round()} ${years == 1 ? 'yr' : 'yrs'}',
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  int get _completion => data == null ? 85 : _p.numOr('completionPct').round();

  /// A photo / signature counts once its file is stored (it then has a link).
  bool _hasFile(String k) => _p.obj(k).str('url').isNotEmpty;

  /// What's still missing, in the order the completion check counts it.
  String get _completionHint {
    if (data == null) return 'Add your languages and a clinic photo to appear higher in patient search.';
    final missing = [
      if (!_hasFile('photo')) 'a photo',
      if (_p.str('bio').isEmpty) 'a short bio',
      if (_languages.isEmpty) 'your languages',
      if (_p.list('qualifications').isEmpty) 'your qualifications',
      if (_p.obj('registration').str('number').isEmpty) 'your registration',
      if ((_p['specialisations'] as List? ?? const []).isEmpty) 'your specialisations',
      if (!_hasFile('signature')) 'your signature',
    ];
    if (missing.isEmpty) return 'Your profile is complete.';
    return 'Add ${F.joinAnd(missing.take(2).toList())} to appear higher in patient search.';
  }

  bool get _taking => data == null || _p['acceptingBookings'] != false;

  /// "Next free slot: today, 12:15 PM · Salt Lake"
  String get _nextSlot {
    if (data == null) return 'Next free slot: today, 12:15 PM · Salt Lake';
    final s = _p.obj('nextFreeSlot');
    final at = F.date(s['startAt']);
    if (at == null) return 'No free slots open for booking';
    var when = F.when(at);
    if (when.startsWith('Today') || when.startsWith('Tomorrow')) when = when[0].toLowerCase() + when.substring(1);
    final where = s.str('location');
    return 'Next free slot: $when${where.isEmpty ? '' : ' · $where'}';
  }

  int get _locationCount => data == null ? 3 : _p.numOr('locations').toInt();

  List<Map<String, dynamic>> get _activeLocations => [
    for (final l in data!.list('locations'))
      if (l['status'] != 'ended') l,
  ];

  /// "5 services · in clinic and video"
  String get _servicesLine {
    if (data == null) return '5 services · in clinic and video';
    final modes = <String>{
      for (final l in _activeLocations)
        for (final s in l.list('services')) s.str('mode', 'in_clinic') == 'video' ? 'video' : 'in clinic',
    };
    final n = _p.numOr('services');
    final order = [for (final m in const ['in clinic', 'video']) if (modes.contains(m)) m];
    return order.isEmpty ? d4Plural(n, 'service') : '${d4Plural(n, 'service')} · ${F.joinAnd(order)}';
  }

  /// "Durga Puja · 19 – 23 Oct"
  String get _leaveLine {
    if (data == null) return 'Durga Puja · 19 – 23 Oct';
    final l = _p.obj('upcomingLeave');
    final start = F.date(l['startDate']), end = F.date(l['endDate']);
    if (start == null) return 'No leave planned';
    return '${l.str('reason', 'Leave')} · ${d4DateRange(start, end ?? start)}';
  }

  /// "Sent 3 days before · WhatsApp and app"
  String get _reminderLine {
    if (data == null) return 'Sent 3 days before · WhatsApp and app';
    final r = _p.obj('followUpReminder');
    final days = r.numOr('daysBefore', 3);
    const names = {'whatsapp': 'WhatsApp', 'app': 'app', 'sms': 'SMS'};
    final channels = [for (final c in (r['channels'] as List? ?? const [])) names['$c'] ?? '$c'];
    final when = 'Sent ${d4Plural(days, 'day')} before';
    if (channels.isEmpty) return when;
    final via = F.joinAnd(channels);
    return '$when · ${via[0].toUpperCase()}${via.substring(1)}';
  }

  bool get _signatureMissing => data == null || !_hasFile('signature');
  bool get _hprLinked => data != null && _p.str('hprId').isNotEmpty;

  List<Map<String, dynamic>> get _team => [
    for (final m in data?.obj('members').list('items') ?? const <Map<String, dynamic>>[])
      if (m['status'] == 'active' && m.str('userId') != _user.str('id')) m,
  ];

  static const _supportRoles = {'front_desk', 'doctor_assistant', 'practice_manager', 'lab_manager', 'lab_technician'};

  /// "Front desk at City Care · 2 people"
  String? get _staffLine {
    if (data == null) return 'Front desk at City Care · 2 people';
    if (data!['members'] == null) return null;
    final n = _team.where((m) => _supportRoles.contains(m['role'])).length;
    final practice = Session.I.activeMembership?['practiceName'] as String? ?? '';
    return practice.isEmpty ? d4Plural(n, 'person', 'people') : 'Front desk at $practice · ${d4Plural(n, 'person', 'people')}';
  }

  /// "Dietician, cardiologist and 4 more" — live: the clinicians' names.
  String? get _colleaguesLine {
    if (data == null) return 'Dietician, cardiologist and 4 more';
    if (data!['members'] == null) return null;
    final names = [
      for (final m in _team)
        if (!_supportRoles.contains(m['role'])) m.str('name'),
    ];
    if (names.isEmpty) return 'No colleagues added yet';
    if (names.length <= 2) return F.joinAnd(names);
    return '${names.take(2).join(', ')} and ${names.length - 2} more';
  }

  /// "MedPin Pro · renews 12 Jan"
  String? get _planLine {
    if (data == null) return 'MedPin Pro · renews 12 Jan';
    final b = data!.obj('billing');
    final plan = b.obj('plan').str('name');
    if (plan.isEmpty) return null;
    final renews = F.date(b.obj('subscription')['currentPeriodEnd']);
    return renews == null ? 'MedPin $plan' : 'MedPin $plan · renews ${F.dayMonth(renews)}';
  }

  String? get _firstLocationId {
    if (data == null) return null;
    final l = _activeLocations;
    return l.isEmpty ? null : (l.first['locationId'] is Map ? l.first.obj('locationId').str('id') : l.first.str('locationId'));
  }

  void _go(String stem, [Object? args]) => Nav.go(context, stem, args: args);

  /// Leave and holidays sheet (with [add]: straight to Add leave); the hub's
  /// leave line and next free slot follow.
  Future<void> _timeOff({bool add = false}) async {
    await openTimeOff(context, add: add);
    if (mounted && isLive) reload(quiet: true);
  }

  Future<void> _bookingRules() async {
    await openBookingRules(context, locationId: _firstLocationId);
    if (mounted && isLive) reload(quiet: true);
  }

  /// "Online · 7 days ahead · cancel up to 2 hrs before" for the first location.
  String get _rulesLine {
    if (data == null || _activeLocations.isEmpty) return 'How far ahead, cancellations, walk-ins';
    final s = _activeLocations.first.obj('schedule');
    final ahead = s.numOr('bookingWindowDays', 7).toInt();
    final cut = s.numOr('cancelCutoffHours', 2).toInt();
    final head = s['onlineBooking'] == false ? 'Online booking off' : (s['requireApproval'] == true ? 'Online · you approve' : 'Online');
    return '$head · ${d4Plural(ahead, 'day')} ahead · cancel up to ${cut == 1 ? '1 hr' : '$cut hrs'} before';
  }

  /// Rows whose editor is not part of the design yet.
  /// Like [_open], with screen args.
  Future<void> _openWith(String stem, Object args) async {
    await Nav.go(context, stem, args: args);
    if (mounted && isLive) reload(quiet: true);
  }

  /// Opens a settings screen and refreshes this hub when you come back.
  Future<void> _open(String stem) async {
    await Nav.go(context, stem);
    if (mounted && isLive) reload(quiet: true);
  }

  bool _sampleAppLock = true;
  bool get _appLock => data == null ? _sampleAppLock : _user['appLock'] == true;

  /// App lock (fingerprint / PIN): PATCH /api/me; the lock follows at once.
  Future<void> _setAppLock(bool v) async {
    if (!isLive) {
      setState(() => _sampleAppLock = v);
      return;
    }
    setState(() => data!.obj('me').obj('user')['appLock'] = v);
    final ok = await runAction(context, () => Api.I.patch('/api/me', {'appLock': v}));
    if (!mounted) return;
    if (ok == null) {
      reload(quiet: true);
      return;
    }
    toast(context, v ? 'App lock on' : 'App lock off');
  }

  Future<void> _changePhoto() async {
    if (!isLive) {
      _open('Profile-About');
      return;
    }
    final file = await Files.chooseSource(context, title: 'Profile photo', allowPdf: false);
    if (file == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.upload('/api/doctor/profile/photo', files: {'file': [file]}));
    if (ok == null || !mounted) return;
    toast(context, 'Photo updated');
    reload(quiet: true);
    Session.I.reloadAccount().catchError((_) {}); // headers show the new photo
  }

  Future<void> _saveLanguages(List<String> langs, String done) async {
    if (!isLive) {
      setState(() => _sampleLanguages = langs);
      if (done.isNotEmpty) toast(context, done);
      return;
    }
    final ok = await runAction(context, () => Api.I.patch('/api/doctor/profile', {'languagesSpoken': langs}));
    if (ok == null || !mounted) return;
    toast(context, done.isEmpty ? 'Languages saved' : done);
    reload(quiet: true);
  }

  Future<void> _editLanguages() async {
    final r = await openSheet<List<String>>(context, (_) => _LanguagesSheet(options: _spoken, selected: _languages));
    if (r != null && mounted) await _saveLanguages(r, '');
  }

  void _addHindi() => _saveLanguages([..._languages, 'Hindi'], 'Hindi added');

  Future<void> _pickAppLanguage() async {
    final r = await d4PickOne(context, title: 'App language', options: _appLanguages, value: _appLanguage);
    if (r == null || !mounted) return;
    if (!isLive) {
      setState(() => _sampleAppLanguage = r);
      return;
    }
    final ok = await runAction(context, () => Api.I.patch('/api/me', {'language': _languageCodes[r]}));
    if (ok == null || !mounted) return;
    toast(context, 'App language: $r');
    reload(quiet: true);
  }

  void _share() {
    final text = data == null
        ? 'Dr. Arjun Sen · Diabetologist · Internal medicine · MBBS, MD · WBMC 64213 — book on MedPin'
        : '${[_name, _headline, _p.str('degreesSummary'), _p.str('registrationDisplay')].where((s) => s.isNotEmpty).join(' · ')} — book on MedPin';
    Clipboard.setData(ClipboardData(text: text));
    toast(context, 'Profile copied to share');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (placeholder != null) return MpPage(header: const D4Header('My profile'), body: placeholder);
    final languages = _languages.isEmpty ? 'Add the languages you speak' : _languages.join(', ');
    return MpPage(
      header: const D4Header('My profile'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        gap: 16,
        children: [
          _profileCard(),
          _bookingCard(),
          _Group('About you', [
            _SettingRow(
              'Professional details',
              sub: 'Profession, qualifications, registration, specialisations',
              emptyValue: true,
              onTap: () => _open('Profile-Professional'),
            ),
            _SettingRow(
              'ABDM · HPR ID',
              sub: 'Ayushman Bharat Digital Mission',
              value: _hprLinked ? 'Linked' : 'Link',
              valueColor: _hprLinked ? MP.green : MP.primary,
              onTap: () => _openWith('Profile-Professional', const {'section': 'abdm'}),
            ),
            _SettingRow(
              'About and photo',
              sub: 'Bio patients read before booking',
              onTap: () => _open('Profile-About'),
            ),
            _SettingRow(
              'Languages',
              sub: languages,
              value: _languages.contains('Hindi') ? null : 'Add Hindi?',
              valueColor: MP.primary,
              onValue: _addHindi,
              onTap: _editLanguages,
            ),
          ]),
          _Group('Practice', [
            // A doctor in two clinics: which one this app works in now.
            if (isLive && Session.I.activeMemberships.length > 1)
              _SettingRow(
                Session.I.practiceName(Session.I.practiceId) ?? 'Clinic',
                sub: tr(context, 'You work in #1 clinics').replaceFirst('#1', '${Session.I.activeMemberships.length}'),
                value: 'Switch',
                valueColor: MP.primary,
                onTap: () => chooseClinic(context),
              ),
            _SettingRow(
              'Locations',
              sub: '${d4Plural(_locationCount, 'location')} · map, address, contact',
              value: '$_locationCount',
              onTap: () => _go('Clinics'),
            ),
            _SettingRow(
              'Schedules and slots',
              sub: 'Hours and slot rules for each location',
              onTap: () => _go('Profile-Schedule'),
            ),
            _SettingRow(
              'Services and fees',
              sub: _servicesLine,
              onTap: () => _go('Profile-Location', _firstLocationId == null ? null : {'locationId': _firstLocationId}),
            ),
            _SettingRow('Leave and holidays', sub: _leaveLine, onTap: _timeOff),
          ]),
          _Group('Patients and care', [
            _SettingRow(
              'Booking rules',
              sub: _rulesLine,
              onTap: _bookingRules,
            ),
            _SettingRow(
              'Follow-up reminders',
              sub: _reminderLine,
              onTap: () => _go('Doctor-FollowUps'),
            ),
            _SettingRow(
              'Chat and urgent messages',
              sub: 'When patients can message you',
              onTap: () => _open('Profile-Chat'),
            ),
            _SettingRow(
              'Prescription letterhead and signature',
              sub: 'Printed on every prescription',
              value: _signatureMissing ? 'Signature missing' : null,
              valueColor: MP.amber,
              onTap: () => _open('Profile-Signature'),
            ),
          ]),
          _Group('Team', [
            _SettingRow('Staff and assistants', sub: _staffLine, onTap: () => _open('People')),
            _SettingRow(
              'Colleagues you work with',
              sub: _colleaguesLine,
              onTap: () => _open('People'),
            ),
          ]),
          _Group('Account', [
            _SettingRow('Notifications', onTap: () => _open('Profile-Notifications')),
            _SettingRow(
              'Payouts and bank account',
              sub: 'UPI and bank for online fees',
              onTap: () => _open('Profile-Payouts'),
            ),
            _SettingRow('Plan and billing', sub: _planLine, onTap: () => _go('Billing')),
            _SettingRow('Privacy and data', onTap: () => _open('Profile-Privacy')),
            _SettingRow('App language', sub: _appLanguage, onTap: _pickAppLanguage),
            _SettingRow(
              'App lock',
              sub: 'Fingerprint or PIN to open MedPin',
              trailing: MpSwitch(value: _appLock, onChanged: _setAppLock),
              onTap: () => _setAppLock(!_appLock),
            ),
            _SettingRow('Help and support', onTap: () => _open('Profile-Help')),
          ]),
          D4OutlineButton('Log out', border: MP.redLine, onTap: () => signOut(context)),
          Text('MedPin 3.8.2', textAlign: TextAlign.center, style: tx(12, c: MP.ink3)),
        ],
      ),
    );
  }

  Widget _profileCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MpAvatar(F.initials(_name), size: 72, fontSize: 24, weight: w800, photo: isLive ? ((_p['photo'] as Map?)?['url'] as String?) ?? myPhotoUrl : null),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: MpHitSlop(child: Semantics(
                        button: true,
                        label: 'Change photo',
                        // <button> is border-box: 28×28 including the 2px border.
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Tap(
                            onTap: _changePhoto,
                            radius: 999,
                            color: MP.primary,
                            border: MP.white,
                            borderWidth: 2,
                            child: const Center(child: Ico(I.cameraAlt, size: 14, color: MP.white, stroke: 2)),
                          ),
                        ),
                      )),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx(20, w: w800, em: -0.01),
                          ),
                        ),
                        if (_verified) ...[
                          const SizedBox(width: 6),
                          Semantics(label: 'Verified', child: const Svg(I.verifiedSvg, width: 18, height: 18)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(_headline, style: tx(14, c: MP.ink2)),
                    const SizedBox(height: 3),
                    Text(_credentials, style: tx(13, c: MP.ink3)),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('Profile $_completion% complete', style: tx(14, w: w600))),
                  D4TextLink(
                    'Finish',
                    onTap: data == null || _languages.isEmpty ? _editLanguages : () => _go('Profile-Professional'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MpProgress(_completion / 100, height: 6),
              const SizedBox(height: 8),
              Text(_completionHint, style: tx(13, c: MP.ink2)),
            ],
          ),
          // Grid 1fr 1fr: the bordered link is 44 + 2px tall, the tonal one 44px.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: Tap(
                    onTap: () => _go('Patient-DoctorDetail'),
                    radius: 12,
                    border: MP.lineStrong,
                    child: Center(child: Text('See as a patient', style: tx(14, w: w600))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Tap(
                    onTap: _share,
                    radius: 12,
                    color: MP.primarySoft,
                    child: Center(child: Text('Share profile', style: tx(14, w: w600, c: MP.primary))),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bookingCard() {
    return MpCard(
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: _taking ? MP.green : MP.ink3, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_taking ? 'Taking bookings' : 'Not taking bookings', style: tx(15, w: w700)),
                const SizedBox(height: 2),
                Text(_nextSlot, style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          D4TextLink('Take leave', onTap: () => _timeOff(add: true)),
        ],
      ),
    );
  }
}

/// Uppercase group label (13/700, .06em, #69738A, padding 0 4) over a white
/// list card (padding 0 16, radius 24) of rows separated by 1px lines.
class _Group extends StatelessWidget {
  final String label;
  final List<Widget> rows;
  const _Group(this.label, this.rows);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(label.toUpperCase(), style: tx(13, w: w700, c: MP.ink3, em: 0.06)),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: MPDeco.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) const MpDivider(), rows[i]],
          ],
        ),
      ),
    ],
  );
}

/// Settings row: 15/600 title, optional 13px / 1.4 #545E72 line, optional
/// 14/600 value, #69738A chevron. Padding 14 0, gap 12.
class _SettingRow extends StatelessWidget {
  final String title;
  final String? sub;
  final String? value;
  final Color valueColor;

  /// Makes [value] a link of its own (e.g. "Add Hindi?").
  final VoidCallback? onValue;

  /// The design keeps an empty value slot on this row (one more 12px gap).
  final bool emptyValue;
  final VoidCallback onTap;

  /// In place of the chevron (e.g. a switch).
  final Widget? trailing;
  const _SettingRow(
    this.title, {
    this.trailing,
    this.sub,
    this.value,
    this.valueColor = MP.ink2,
    this.onValue,
    this.emptyValue = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Tap(
      onTap: onTap,
      radius: 0,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(15, w: w600)),
                if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: tx(13, c: MP.ink2, h: 1.4))],
              ],
            ),
          ),
          if (emptyValue) const SizedBox(width: 12),
          if (v != null) ...[
            const SizedBox(width: 12),
            onValue == null
                ? Text(v, style: tx(14, w: w600, c: valueColor))
                : D4TextLink(v, color: valueColor, onTap: onValue),
          ],
          const SizedBox(width: 12),
          trailing ?? const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
        ],
      ),
    );
  }
}

/// Spoken-languages picker opened from the Languages row and "Finish".
class _LanguagesSheet extends StatefulWidget {
  final List<String> options;
  final List<String> selected;
  const _LanguagesSheet({required this.options, required this.selected});

  @override
  State<_LanguagesSheet> createState() => _LanguagesSheetState();
}

class _LanguagesSheetState extends State<_LanguagesSheet> {
  late final Set<String> _on = {...widget.selected};

  void _toggle(String l) => setState(() {
    if (!_on.remove(l)) _on.add(l);
  });

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Languages',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in widget.options)
            Tap(
              onTap: () => _toggle(l),
              radius: 12,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(l, style: tx(16, w: _on.contains(l) ? w600 : w400))),
                    MpCheck(value: _on.contains(l), onChanged: (_) => _toggle(l)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          MpButton(
            'Save',
            onTap:
                () => Navigator.pop(context, [
                  for (final l in widget.options)
                    if (_on.contains(l)) l,
                ]),
          ),
        ],
      ),
    );
  }
}

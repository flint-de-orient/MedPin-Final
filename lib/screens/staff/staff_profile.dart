import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/photo.dart';
import '../../data/session.dart';
import '../../widgets/clinic_switch.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Staff-Profile.dc.html — "Profile" (front desk).
class StaffProfileScreen extends StatefulWidget {
  const StaffProfileScreen({super.key});

  @override
  State<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

/// The canvas sets `line-height: 1.4` on the page.
const _lh = 1.4;

const _globe = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>';
const _building =
    '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4M9 6h.01M15 6h.01M9 10h.01M15 10h.01M9 14h.01M15 14h.01"/>';

const _languages = ['English', 'Bengali', 'Hindi'];

/// App language name ↔ API code.
const _languageCodes = {'English': 'en', 'Bengali': 'bn', 'Hindi': 'hi'};

/// Live data: GET /api/me (name, phone, language, app lock, membership),
/// GET /api/members/me (my role here, the locations I cover with their
/// doctors, the doctors I work for, permissions; GET /api/locations when the
/// server is older), unread notifications. Saves: PATCH /api/me.
/// Staff in two clinics get a Clinic row to switch (Session.I.usePractice).
class _StaffProfileScreenState extends State<StaffProfileScreen> with LiveData {
  String _language = 'English';
  bool _appLock = true;

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait<Object?>([
      Api.I.get('/api/me'),
      Api.I.get('/api/members/me').then<Object?>((v) => v, onError: (_) => null),
      Api.I.get('/api/notifications', query: {'limit': '1', if (Session.I.practiceId != null) 'practiceId': Session.I.practiceId}),
    ]);
    final me = (r[0] as Map).cast<String, dynamic>();
    final user = me.obj('user');
    _language = _languageCodes.entries.firstWhere((e) => e.value == user['language'], orElse: () => _languageCodes.entries.first).key;
    _appLock = user['appLock'] == true;
    final mine = r[1] is Map ? (r[1] as Map).cast<String, dynamic>() : null;
    Object? location;
    if (mine == null) {
      final l = await Api.I.get('/api/locations');
      final locs = l is List ? l : ((l as Map)['items'] as List? ?? const []);
      location = locs.isEmpty ? null : locs.first;
    }
    return {...me, 'mine': mine, 'location': location, 'unreadNotifications': (r[2] as Map)['unread'] ?? 0};
  }

  /// My membership in the active clinic (GET /api/members/me), if the server has it.
  Map<String, dynamic> get _mine => data?.obj('mine') ?? const {};

  Map<String, dynamic> get _user => data?.obj('user') ?? const {};
  /// The clinic I'm working in now (the one chosen when I'm in several).
  Map<String, dynamic> get _membership {
    final list = data?.list('memberships') ?? const [];
    final active = list.where((m) => m['status'] == 'active');
    return active.where((m) => '${m['practiceId']}' == Session.I.practiceId).firstOrNull ?? active.firstOrNull ?? (list.isEmpty ? const {} : list.first);
  }

  String get _name => data == null ? 'Tania Ghosh' : _user.str('name', 'Your name');

  /// "+91 98765 18210"
  String get _phone {
    if (data == null) return '+91 98765 18210';
    final p = _user.str('phone');
    return p.length == 10 ? '+91 ${p.substring(0, 5)} ${p.substring(5)}' : p;
  }

  String get _role => data == null ? 'Front desk' : roleLabel(_membership['role'] as String?);

  String get _practiceName => data == null ? 'City Care Clinic' : _mine.obj('practice').str('name', _membership.str('practiceName'));

  /// "City Care Clinic · Salt Lake" for a location.
  String _placeLine(Map<String, dynamic> loc) {
    final place = loc.str('shortName', loc.str('name'));
    final practice = _practiceName;
    if (place.isNotEmpty && practice.isNotEmpty && place.toLowerCase().contains(practice.toLowerCase())) return place;
    return [practice, if (place.isNotEmpty) place].where((x) => x.isNotEmpty).join(' · ');
  }

  /// The locations I cover, each with the doctors working there and what I may change.
  List<Map<String, dynamic>> get _places {
    if (data == null) {
      return const [
        {'id': null, 'shortName': 'Salt Lake', 'doctors': [{'name': 'Dr. Arjun Sen'}, {'name': 'Dr. Rina Mitra'}]},
      ];
    }
    if (_mine.isNotEmpty) return _mine.list('coverage');
    final loc = data!.obj('location');
    return loc.isEmpty ? const [] : [loc];
  }

  /// "Dr. Arjun Sen · Dr. Rina Mitra", "No doctors here yet"; null when unknown (older server).
  String? _doctorsLine(Map<String, dynamic> loc) {
    if (!loc.containsKey('doctors') || loc['doctors'] is! List) return null;
    final names = [for (final d in loc.list('doctors')) d.str('name')].where((n) => n.isNotEmpty).toList();
    return names.isEmpty ? 'No doctors here yet' : names.join(' · ');
  }

  /// Can I change anything at this location (details, hours or closures)?
  bool _canChange(Map<String, dynamic> loc) {
    if (!isLive) return true;
    final can = loc.obj('can');
    if (can.isEmpty) return Session.I.isOwner || Session.I.role == 'practice_manager';
    return can['details'] == true || can['closures'] == true;
  }

  int get _notes => data == null ? 3 : data!.numOr('unreadNotifications').toInt();

  /// Saves account fields; returns false (after a toast) when it fails.
  Future<bool> _save(Map<String, Object?> body) async {
    final r = await runAction(context, () => Api.I.patch('/api/me', body));
    if (r == null) return false;
    await Session.I.reloadAccount();
    return true;
  }

  Future<void> _pickLanguage() async {
    final v = await D10Picker.show(context, title: 'Language', options: _languages, value: _language);
    if (v == null || !mounted || v == _language) return;
    final before = _language;
    setState(() => _language = v);
    if (!isLive) return;
    if (!await _save({'language': _languageCodes[v]}) && mounted) setState(() => _language = before);
  }

  Future<void> _setAppLock(bool v) async {
    setState(() => _appLock = v);
    if (!isLive) return;
    if (!await _save({'appLock': v}) && mounted) setState(() => _appLock = !v);
  }

  Future<void> _editAccount() async {
    if (!isLive) {
      toast(context, 'Account settings are not in the design yet');
      return;
    }
    final v = await openSheet<Map<String, String>>(
      context,
      (_) => _AccountSheet(user: _user, mine: _mine, role: _role, practice: _practiceName, phone: _phone),
    );
    if (v == null || !mounted) return;
    if (v['name'] == _user.str('name') && v['email'] == _user.str('email')) return;
    if (!await _save(v) || !mounted) return;
    toast(context, 'Account updated');
    reload(quiet: true);
  }

  Future<void> _openClinic(Map<String, dynamic> loc) async {
    final id = loc['id'];
    await Nav.go(context, 'Clinic-Editor', args: isLive && id != null ? {'locationId': '$id'} : null);
    if (mounted && isLive) reload(quiet: true);
  }

  Future<void> _switchClinic() async {
    await chooseClinic(context);
    if (mounted && isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = tx(16, w: w600, h: _lh);
    final sub = tx(14, c: MP.ink2, h: _lh);
    final placeholder = livePlaceholder();
    return MpPage(
      nav: const StaffNav(current: 2),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D10StaffHeader(bellLabel: _notes > 0 ? 'Notifications, $_notes new' : 'Notifications', dot: _notes > 0 ? MP.primary : MP.line, showAvatar: false),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 24,
            children: [
              // Identity
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    data == null ? const ExcludeSemantics(child: MpAvatar('TG', size: 72, fontSize: 24)) : MyPhotoAvatar(F.initials(_name)),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_name, style: tx(28, w: w800, h: 1.15, em: -0.02)),
                          const Gap(4),
                          Text(_phone, style: tx(14, c: MP.ink2, h: _lh, tab: true)),
                          const Gap(6),
                          MpBadge(_role, weight: w600),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // General
              _Section(
                title: 'General',
                rows: [
                  D10ListRow(
                    vPad: 0,
                    onTap: _pickLanguage,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(
                        children: [
                          const Ico(_globe, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(child: Text('Language', style: title)),
                          const Gap(12),
                          Text(_language, style: sub),
                          const Gap(12),
                          const Ico(I.chevronRight, size: 18, color: MP.ink3),
                        ],
                      ),
                    ),
                  ),
                  D10ListRow(
                    divider: true,
                    vPad: 12,
                    onTap: _editAccount,
                    child: Row(
                      children: [
                        const Ico(I.user, size: 22, color: MP.ink2),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Account', style: title),
                              const Gap(2),
                              Text('Name, phone and email', maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
                ],
              ),

              // Clinic: the one I work in (switch when I'm in several) and every location I cover.
              _Section(
                title: 'Clinic',
                rows: [
                  if (isLive && Session.I.activeMemberships.length > 1)
                    D10ListRow(
                      vPad: 12,
                      onTap: _switchClinic,
                      child: Row(
                        children: [
                          const Ico(_building, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_practiceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: title),
                                const Gap(2),
                                Text(
                                  tr(context, 'You work in #1 clinics').replaceFirst('#1', '${Session.I.activeMemberships.length}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sub,
                                ),
                              ],
                            ),
                          ),
                          const Gap(12),
                          Text('Switch', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                        ],
                      ),
                    ),
                  if (_places.isEmpty)
                    D10ListRow(
                      vPad: 12,
                      child: Row(
                        children: [
                          const Ico(_building, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(child: Text('No locations yet', style: sub)),
                        ],
                      ),
                    ),
                  for (final (i, loc) in _places.indexed)
                    D10ListRow(
                      divider: i > 0 || (isLive && Session.I.activeMemberships.length > 1),
                      vPad: 12,
                      onTap: () => _openClinic(loc),
                      child: Row(
                        children: [
                          const Ico(_building, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_placeLine(loc), maxLines: 2, overflow: TextOverflow.ellipsis, style: title),
                                if (_doctorsLine(loc) != null) ...[
                                  const Gap(2),
                                  Text(_doctorsLine(loc)!, maxLines: 2, overflow: TextOverflow.ellipsis, style: sub),
                                ],
                              ],
                            ),
                          ),
                          const Gap(12),
                          if (_canChange(loc)) ...[
                            const Ico(I.edit, size: 16, color: MP.primary),
                            const Gap(4),
                            Text('Edit', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                          ] else ...[
                            Text('View', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                            const Gap(4),
                            const Ico(I.chevronRight, size: 18, color: MP.ink3),
                          ],
                        ],
                      ),
                    ),
                ],
              ),

              // Security
              _Section(
                title: 'Security',
                rows: [
                  D10ListRow(
                    vPad: 12,
                    child: Row(
                      children: [
                        const Ico(I.lock, size: 22, color: MP.ink2),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('App lock', style: title),
                              const Gap(2),
                              Text('Fingerprint or PIN to open MedPin', style: sub),
                            ],
                          ),
                        ),
                        const Gap(12),
                        _Switch(
                          value: _appLock,
                          label: 'App lock',
                          onChanged: _setAppLock,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Log out
              D10ListCard(
                children: [
                  D10ListRow(
                    vPad: 0,
                    onTap: () => signOut(context),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(
                        children: [
                          const Ico(I.logout, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(child: Text('Log out', style: title)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Uppercase heading (12 / 1.35, 4px inset) over a list card, 8px apart.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => VGap(
        gap: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(header: true, child: D10Caps(title, lineHeight: 12 * 1.35)),
          ),
          D10ListCard(children: rows),
        ],
      );
}

/// 52×32 switch; knob 28px with this design's 0 1px 3px rgba(0,51,153,.24).
class _Switch extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  const _Switch({required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MpHitSlop(child: Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? MP.primary : MP.lineStrong,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: MP.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x3D003399), offset: Offset(0, 1), blurRadius: 3)],
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

/// What a role's permissions let someone do, in plain words (Account sheet).
const _canSay = [
  ('viewPatients', 'See patients and book their visits'),
  ('vitals', 'Record vitals (BP, sugar, weight)'),
  ('fees', 'Collect fees and give refunds'),
  ('chats', 'Chat with patients'),
  ('closures', 'Add holidays and closures'),
  ('doctorHours', "Change doctors' hours"),
  ('manageClinic', 'Change clinic details and weekly hours'),
  ('clinical', 'Open consultations and clinical notes'),
  ('editRecords', 'Update allergies, conditions and patient details'),
  ('prescribe', 'Write prescriptions'),
  ('labs', 'Enter lab results'),
  ('labReview', 'Mark lab results reviewed'),
  ('alerts', 'See health alerts'),
  ('manageAlerts', 'Act on health alerts'),
  ('ai', 'Use MedPin AI'),
  ('reports', 'See clinic reports'),
  ('exports', 'Download patient lists'),
  ('billing', 'Manage the MedPin plan and invoices'),
];

/// Profile → Account: photo, name and email (editable), the sign-in number,
/// and my place in the clinic — role, practice, department, locations, the
/// doctors I work for, when I joined and what my role lets me do.
/// Resolves with {name, email} to save, or null.
class _AccountSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> mine;
  final String role;
  final String practice;
  final String phone;
  const _AccountSheet({required this.user, required this.mine, required this.role, required this.practice, required this.phone});

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final _name = TextEditingController(text: widget.user.str('name'));
  late final _email = TextEditingController(text: widget.user.str('email'));

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) return toast(context, 'Enter your name');
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return toast(context, 'Enter a valid email');
    Navigator.pop(context, {'name': name, 'email': email});
  }

  String get _locations {
    final m = widget.mine;
    if (m['allLocations'] == true) return 'All locations';
    final names = [for (final l in m.list('coverage')) l.str('shortName', l.str('name'))].where((n) => n.isNotEmpty).toList();
    return names.isEmpty ? '—' : names.join(', ');
  }

  String? get _joined {
    final d = F.date(widget.mine['joinedAt']);
    return d == null ? null : '${F.dayMonth(d)} ${d.year}';
  }

  List<String> get _can {
    final perms = widget.mine.obj('permissions');
    if (widget.mine['isOwner'] == true) return const ['Everything in this clinic (you are an owner)'];
    return [for (final (k, say) in _canSay) if (perms[k] == true) say];
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mine;
    final department = m.obj('department').str('name');
    final doctors = [for (final d in m.list('worksFor')) d.str('name')].where((n) => n.isNotEmpty).toList();
    return MpSheet(
      title: 'Account',
      showClose: true,
      child: VGap(
        gap: 16,
        children: [
          Row(
            children: [
              MyPhotoAvatar(F.initials(_name.text.isEmpty ? widget.user.str('name') : _name.text), size: 64, fontSize: 22),
              const Gap(16),
              Expanded(child: Text('Tap the camera to change your photo. Patients and your team see it.', style: tx(14, c: MP.ink2, h: 1.45))),
            ],
          ),
          MpInput(label: 'Name', controller: _name, autofillHints: const [AutofillHints.name]),
          MpInput(
            label: 'Phone',
            value: widget.phone,
            readOnly: true,
            tab: true,
            help: 'Your sign-in number. To change it, ask the practice owner.',
          ),
          MpInput(label: 'Email (optional)', controller: _email, hint: 'name@example.com', keyboard: TextInputType.emailAddress),
          if (m.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MpKV('Role', widget.role),
                  if (widget.practice.isNotEmpty) MpKV('Clinic', widget.practice),
                  if (department.isNotEmpty) MpKV('Department', department),
                  MpKV('Locations', _locations),
                  if (doctors.isNotEmpty) MpKV(m['role'] == 'doctor_assistant' ? 'Assists' : 'Doctors', doctors.join(', ')),
                  if (_joined != null) MpKV('Joined', _joined!),
                ],
              ),
            ),
          if (_can.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text('What you can do', style: tx(14, w: w600))),
                const Gap(8),
                for (final line in _can)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.check, size: 16, color: MP.primary, stroke: 2)),
                        const Gap(8),
                        Expanded(child: Text(line, style: tx(14, c: MP.ink2, h: 1.4))),
                      ],
                    ),
                  ),
                Text('Need something else? Ask the practice owner.', style: tx(13, c: MP.ink3, h: 1.4)),
              ],
            ),
          MpButton('Save', onTap: _done),
        ],
      ),
    );
  }
}

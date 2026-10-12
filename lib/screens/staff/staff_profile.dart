import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/photo.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';
import '../doctor/common_d4.dart';
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

const _roleLabels = {'front_desk': 'Front desk', 'doctor': 'Doctor', 'nurse': 'Nurse', 'dietician': 'Dietician', 'admin': 'Admin'};

/// Live data: GET /api/me (name, phone, language, app lock, membership),
/// GET /api/locations (clinic line), unread notifications.
/// Saves: PATCH /api/me.
class _StaffProfileScreenState extends State<StaffProfileScreen> with LiveData {
  String _language = 'English';
  bool _appLock = true;

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/me'),
      Api.I.get('/api/locations'),
      Api.I.get('/api/notifications', query: {'limit': '1', if (Session.I.practiceId != null) 'practiceId': Session.I.practiceId}),
    ]);
    final me = (r[0] as Map).cast<String, dynamic>();
    final user = me.obj('user');
    _language = _languageCodes.entries.firstWhere((e) => e.value == user['language'], orElse: () => _languageCodes.entries.first).key;
    _appLock = user['appLock'] != false;
    final locs = r[1] is List ? r[1] as List : ((r[1] as Map)['items'] as List? ?? const []);
    return {...me, 'location': locs.isEmpty ? null : locs.first, 'unreadNotifications': (r[2] as Map)['unread'] ?? 0};
  }

  Map<String, dynamic> get _user => data?.obj('user') ?? const {};
  Map<String, dynamic> get _membership {
    final list = data?.list('memberships') ?? const [];
    return list.where((m) => m['status'] == 'active').firstOrNull ?? (list.isEmpty ? const {} : list.first);
  }

  String get _name => data == null ? 'Tania Ghosh' : _user.str('name', 'Your name');

  /// "+91 98765 18210"
  String get _phone {
    if (data == null) return '+91 98765 18210';
    final p = _user.str('phone');
    return p.length == 10 ? '+91 ${p.substring(0, 5)} ${p.substring(5)}' : p;
  }

  String get _role => data == null ? 'Front desk' : (_roleLabels[_membership['role']] ?? 'Team member');

  String get _clinicLine {
    if (data == null) return 'City Care Clinic · Salt Lake';
    final loc = data!.obj('location');
    final place = loc.str('shortName', loc.str('name'));
    return [_membership.str('practiceName'), if (place.isNotEmpty) place].where((x) => x.isNotEmpty).join(' · ');
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
    final v = await d4FormSheet(
      context,
      title: 'Account',
      subtitle: 'Your phone number is how you sign in. To change it, ask the practice owner.',
      fields: [
        D4FormField('Name', value: _user.str('name')),
        D4FormField('Email (optional)', value: _user.str('email'), hint: 'name@example.com', keyboard: TextInputType.emailAddress),
      ],
    );
    if (v == null || v.isEmpty || !mounted) return;
    if (v[0].isEmpty) {
      toast(context, 'Enter your name');
      return;
    }
    if (v[1].isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v[1])) {
      toast(context, 'Enter a valid email');
      return;
    }
    if (!await _save({'name': v[0], 'email': v[1]}) || !mounted) return;
    toast(context, 'Account updated');
    reload(quiet: true);
  }

  Future<void> _openClinic() async {
    final id = data?.obj('location')['id'];
    await Nav.go(context, 'Clinic-Editor', args: isLive && id != null ? {'locationId': '$id'} : null);
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
                    onTap: _openClinic,
                    child: Row(
                      children: [
                        const Ico(_building, size: 22, color: MP.ink2),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Clinic details', style: title),
                              const Gap(2),
                              Text(
                                _clinicLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sub,
                              ),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.edit, size: 16, color: MP.primary),
                        const Gap(4),
                        Text('Edit', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                      ],
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

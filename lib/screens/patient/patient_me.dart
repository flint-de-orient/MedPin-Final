import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Patient app · Profile tab ("My profile"). Not an artboard in the design
/// canvas: built from the front-desk Profile pattern (Staff-Profile) and the
/// patient's own data used across the patient screens.
class PatientMeScreen extends StatefulWidget {
  const PatientMeScreen({super.key});

  @override
  State<PatientMeScreen> createState() => _PatientMeScreenState();
}

// ── Data ─────────────────────────────────────────────────────────────────────

class _Me {
  final String name;
  final int age;
  final String gender;
  final String phone;
  final double heightCm;
  final double weightKg;
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

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));
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
  const _Viewer(this.initials, this.name, this.role);
}

const _viewers = [
  _Viewer('AS', 'Dr. Arjun Sen', 'Diabetes · City Care Clinic'),
  _Viewer('RM', 'Dr. Rina Mitra', 'Heart · City Care Clinic'),
  _Viewer('NG', 'Dr. Nandita Gupta', 'Gynaecology · Apollo Clinic'),
  _Viewer('MO', 'Mou', 'Dietician · City Care Clinic'),
];

const _languages = ['English', 'हिन्दी (Hindi)', 'বাংলা (Bengali)'];
const _bloodGroups = ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−', 'Not sure'];

// Icons used here that aren't in the shared set (24×24, stroke).
const _icGlobe = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>';
const _icHelp = '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>';
const _icCopy = '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>';
const _icRuler = '<path d="M21.3 15.3 8.7 2.7a1 1 0 0 0-1.4 0L2.7 7.3a1 1 0 0 0 0 1.4l12.6 12.6a1 1 0 0 0 1.4 0l4.6-4.6a1 1 0 0 0 0-1.4Z"/><path d="m7.5 10.5 2-2M10.5 13.5l2-2M13.5 16.5l2-2"/>';

// ── Screen ───────────────────────────────────────────────────────────────────

class _PatientMeScreenState extends State<PatientMeScreen> {
  _Me _me = const _Me(
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

  Future<void> _edit() async {
    final updated = await openSheet<_Me>(context, (_) => _EditSheet(me: _me));
    if (updated == null || !mounted) return;
    setState(() => _me = updated);
    toast(context, 'Profile updated');
  }

  Future<void> _manage(int i) async {
    final v = _viewers[i];
    final level = await openSheet<String>(context, (_) => _SharingSheet(viewer: v, current: _sharing[i]));
    if (level == null || !mounted || level == _sharing[i]) return;
    setState(() => _sharing[i] = level);
    toast(context, level == _stopSharing ? 'Stopped sharing with ${v.name}' : '${v.name} can now see: ${level.toLowerCase()}');
  }

  Future<void> _pickLanguage() async {
    final l = await openSheet<String>(
      context,
      (_) => _PickSheet(title: 'App language', subtitle: 'MedPin and your reminders use this language.', options: _languages, value: _language),
    );
    if (l != null && mounted) setState(() => _language = l);
  }

  Future<void> _logOut() async {
    final ok = await openSheet<bool>(context, (_) => const _LogOutSheet());
    if (ok == true && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      nav: const PatientNav(current: 4),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 24,
            children: [
              _identity(),
              const _ConsentCard(),
              _section('Health details', [
                _Row(
                  icon: I.activity,
                  title: 'Conditions',
                  below: Wrap(spacing: 6, runSpacing: 6, children: [for (final c in _conditions) _Tag(c)]),
                  onTap: _edit,
                ),
                _Row(
                  icon: I.alert,
                  title: 'Allergies',
                  below: const MpBadge(
                    _allergy,
                    bg: MP.amberSoft,
                    fg: MP.amber,
                    border: MP.amberLine,
                    icon: I.alert,
                    weight: w600,
                    padX: 8,
                  ),
                  onTap: _edit,
                ),
                _Row(
                  icon: _icRuler,
                  title: 'Height and weight',
                  sub: '${_fmt(_me.heightCm)} cm · ${_fmt(_me.weightKg)} kg · BMI ${_me.bmi.toStringAsFixed(1)}',
                  trailing: const _Chevron(),
                  onTap: _edit,
                ),
                _Row(
                  icon: I.drop,
                  title: 'Blood group',
                  sub: _me.bloodGroup ?? 'Not added',
                  subColor: _me.bloodGroup == null ? MP.ink3 : MP.ink2,
                  trailing: _me.bloodGroup == null ? const _Action('Add') : const _Chevron(),
                  onTap: _edit,
                ),
                _Row(
                  icon: I.phone,
                  title: 'Emergency contact',
                  sub: _me.emergencyName == null
                      ? 'Someone we can call for you'
                      : '${_me.emergencyName} · +91 ${_me.emergencyPhone}',
                  subColor: _me.emergencyName == null ? MP.ink3 : MP.ink2,
                  trailing: _me.emergencyName == null ? const _Action('Add') : const _Chevron(),
                  onTap: _edit,
                ),
              ]),
              _section(
                'Who can see my records',
                [
                  for (var i = 0; i < _viewers.length; i++)
                    _Row(
                      leading: MpAvatar(_viewers[i].initials, size: 40, fontSize: 14),
                      title: _viewers[i].name,
                      sub: _sharing[i] == _stopSharing ? _stopSharing : _sharing[i],
                      subColor: _sharing[i] == _stopSharing ? MP.ink3 : MP.ink2,
                      meta: _viewers[i].role,
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
                  trailing: MpSwitch(value: _medReminders, onChanged: (v) => setState(() => _medReminders = v)),
                  onTap: () => setState(() => _medReminders = !_medReminders),
                ),
                _Row(
                  icon: I.edit,
                  title: 'Daily log reminder',
                  sub: '8:00 PM every day',
                  trailing: MpSwitch(value: _logReminder, onChanged: (v) => setState(() => _logReminder = v)),
                  onTap: () => setState(() => _logReminder = !_logReminder),
                ),
                _Row(
                  icon: I.calendar,
                  title: 'Visit reminders',
                  sub: 'A day before and 2 hours before',
                  trailing: MpSwitch(value: _visitReminders, onChanged: (v) => setState(() => _visitReminders = v)),
                  onTap: () => setState(() => _visitReminders = !_visitReminders),
                ),
              ]),
              _section('General', [
                _Row(
                  icon: _icGlobe,
                  title: 'Language',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_language, style: tx(14, c: MP.ink2)),
                    const Gap(12),
                    const _Chevron(),
                  ]),
                  onTap: _pickLanguage,
                ),
                _Row(
                  icon: I.lock,
                  title: 'App lock',
                  sub: 'Fingerprint or PIN to open MedPin',
                  trailing: MpSwitch(value: _appLock, onChanged: (v) => setState(() => _appLock = v)),
                  onTap: () => setState(() => _appLock = !_appLock),
                ),
                _Row(
                  icon: _icHelp,
                  title: 'Help and support',
                  trailing: const _Chevron(),
                  onTap: () => toast(context, 'Help is not in the design yet'),
                ),
                _Row(
                  icon: I.shield,
                  title: 'Privacy and terms',
                  trailing: const _Chevron(),
                  onTap: () => toast(context, 'Privacy and terms are not in the design yet'),
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

  // Logo + bell, as on the front-desk Profile tab.
  Widget _topBar() => Padding(
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
                  label: 'Notifications, 1 new',
                  onTap: () => toast(context, 'Notifications are not in the design yet'),
                ),
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

  Widget _identity() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            MpAvatar(_me.initials, size: 72, fontSize: 24),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _me.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tx(28, w: w800, h: 1.15, em: -0.02),
                  ),
                  const Gap(4),
                  Text('+91 ${_me.phone}', style: tx(14, c: MP.ink2, tab: true)),
                  const Gap(6),
                  MpBadge('${_me.age} yrs · ${_me.gender}', weight: w600),
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
class _ConsentCard extends StatefulWidget {
  const _ConsentCard();
  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends State<_ConsentCard> {
  static const _period = 60;
  int _seed = 0;
  int _left = _period;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (--_left <= 0) _next();
      });
    });
  }

  void _next() {
    _seed++;
    _left = _period;
  }

  /// Six digits; the first matches the code typed in Add-Patient-Existing.
  String get _code {
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
                onTap: () => setState(_next),
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
  late final _age = TextEditingController(text: '${widget.me.age}');
  late final _height = TextEditingController(text: _PatientMeScreenState._fmt(widget.me.heightCm));
  late final _weight = TextEditingController(text: _PatientMeScreenState._fmt(widget.me.weightKg));
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
    double num(TextEditingController c, double fallback) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;
    final name = _ecName.text.trim();
    final phone = _ecPhone.text.trim();
    Navigator.pop(
      context,
      _Me(
        name: _name.text.trim().isEmpty ? m.name : _name.text.trim(),
        age: int.tryParse(_age.text.trim()) ?? m.age,
        gender: _gender,
        phone: m.phone,
        heightCm: num(_height, m.heightCm).clamp(50, 250).toDouble(),
        weightKg: num(_weight, m.weightKg).clamp(2, 400).toDouble(),
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

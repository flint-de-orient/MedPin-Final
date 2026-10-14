import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'add_patient.dart' show PatientOtpSheet;
import 'common_d9.dart';
import '../../widgets/i18n.dart';

/// Design: People-Add.dc.html — "People · add".
/// Live data: GET /api/departments, /api/locations. "Add to team" verifies
/// the phone (POST /api/members/phone-otp, code entered in a sheet) and then
/// POST /api/members with the code.
class PeopleAddScreen extends StatefulWidget {
  const PeopleAddScreen({super.key});

  @override
  State<PeopleAddScreen> createState() => _PeopleAddScreenState();
}

class _PeopleAddScreenState extends State<PeopleAddScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  static const _sampleDepartments = [
    'Endocrinology',
    'Diabetology',
    'Cardiology',
    'General medicine',
    'Gynaecology',
    'Nephrology',
  ];

  String _role = 'Doctor';
  String _department = 'Endocrinology';
  List<bool> _locations = [true, false];

  late final _name = TextEditingController(text: isLive ? '' : 'Dr. Ananya Basu');
  late final _phone = TextEditingController(text: isLive ? '' : '+91 98300 45127')..addListener(_phoneEdited);

  // Doctor-only fields keep their text while another role is picked.
  late final _qualifications = TextEditingController(text: isLive ? '' : 'MBBS, DNB (Endocrinology)');
  late final _registration = TextEditingController(text: isLive ? '' : 'WBMC 71842');

  /// The code the new member's phone received, once entered.
  String? _otpCode;
  String? _otpPhone;
  final _busy = ValueNotifier(false);

  bool get _verified => !isLive || (_otpCode != null && _otpPhone == _digits);

  String get _digits {
    final d = _phone.text.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  void _phoneEdited() {
    if (_otpCode != null && _otpPhone != _digits) setState(() => _otpCode = null);
  }

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([Api.I.get('/api/departments'), Api.I.get('/api/locations')]);
    final deps = r[0] as List? ?? const [];
    final locs = ((r[1] as Map)['items'] as List? ?? const []);
    if (deps.isNotEmpty && data == null) _department = '${(deps.first as Map)['name']}';
    if (_locations.length != locs.length) _locations = [for (var i = 0; i < locs.length; i++) i == 0];
    return {'departments': deps, 'locations': r[1]};
  }

  List<Map<String, dynamic>> get _departmentItems => [
    for (final d in (data!['departments'] as List? ?? const [])) (d as Map).cast<String, dynamic>(),
  ];
  List<Map<String, dynamic>> get _locationItems => data!.obj('locations').list('items');

  List<String> get _departments => data == null ? _sampleDepartments : [for (final d in _departmentItems) d.str('name')];
  List<String> get _locationNames => data == null ? D9Locations.names : [for (final l in _locationItems) l.str('name')];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _qualifications.dispose();
    _registration.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!isLive) {
      toast(context, 'Added to team');
      Nav.back(context);
      return;
    }
    if (_busy.value) return;
    final name = _name.text.trim();
    final phone = _digits;
    if (name.isEmpty) return toast(context, 'Enter the full name');
    if (phone.length != 10) return toast(context, 'Enter a 10-digit mobile number');

    if (!_verified) {
      Future<Map?> send() async {
        final r = await runAction(context, () => Api.I.post('/api/members/phone-otp', {'phone': phone}), busy: _busy);
        if (r is Map && r['devCode'] != null && mounted) toast(context, 'Test code: ${r['devCode']}');
        return r is Map ? r : null;
      }

      final sent = await send();
      if (sent == null || !mounted) return;
      final code = await openSheet<String>(
        context,
        (_) => PatientOtpSheet(title: 'Confirm the phone', button: 'Confirm and add', masked: '${sent['maskedPhone'] ?? D9Fmt.phone(phone)}', resendIn: (sent['resendInSec'] as num?)?.toInt() ?? 30, resend: send),
      );
      if (code == null || code.isEmpty || !mounted) return;
      setState(() {
        _otpCode = code;
        _otpPhone = phone;
      });
    }

    final locs = _locationItems;
    final ids = [
      for (var i = 0; i < locs.length && i < _locations.length; i++)
        if (_locations[i]) locs[i].str('id'),
    ];
    final doctor = _role == 'Doctor';
    final body = <String, Object?>{
      'role': D9Roles.key(_role),
      'name': name,
      'phone': phone,
      'departmentId': _departmentItems.where((d) => d.str('name') == _department).map((d) => d['id']).firstOrNull,
      'locationIds': ids,
      'allLocations': locs.isNotEmpty && ids.length == locs.length,
      if (doctor && _qualifications.text.trim().isNotEmpty) 'qualifications': _qualifications.text.trim(),
      if (doctor && _registration.text.trim().isNotEmpty) 'registrationNo': _registration.text.trim(),
      'otpCode': _otpCode,
    };
    // Errors (e.g. 409 NO_SEATS "All 8 seats on the Clinic plan are used")
    // are shown as a toast.
    final res = await runAction(context, () => Api.I.post('/api/members', body), busy: _busy);
    if (!mounted) return;
    if (res == null) {
      // The server checks (and uses up) the code first, so a retry needs a new one.
      setState(() => _otpCode = null);
      return;
    }
    toast(context, 'Added to team');
    Nav.back(context);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: const MpHeader('Add someone'),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 24,
        children: [
          // Role picker
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const D9FieldLabel('Role', bottom: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in D9Roles.all)
                    MpHitSlop(child: Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: r == _role,
                      child: _RoleChip(r, selected: r == _role, onTap: () => setState(() => _role = r)),
                    )),
                ],
              ),
            ],
          ),

          D9Labeled('Full name', child: D9Input(controller: _name)),

          // Phone, verified
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Phone'),
              const Gap(8),
              D9Input(
                controller: _phone,
                tab: true,
                keyboard: TextInputType.phone,
                padRight: 112,
                trailing: _verified
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Ico(I.check, size: 18, color: MP.green, stroke: 2.25),
                          const Gap(6),
                          Text('Verified', style: tx(14, w: w600, c: MP.green)),
                        ],
                      )
                    : null,
              ),
              const Gap(8),
              Text(
                _verified ? 'OTP confirmed just now' : "We'll send a code to this number to confirm it",
                style: tx(13, c: MP.ink3, h: 1.4),
              ),
            ],
          ),

          // Doctor-only fields
          if (_role == 'Doctor')
            VGap(
              gap: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const D9Label('Doctor details', h: 1.35),
                    const Gap(4),
                    Text("Printed on this doctor's prescriptions", style: tx(13, c: MP.ink3, h: 1.4)),
                  ],
                ),
                D9Labeled('Qualifications', child: D9Input(controller: _qualifications)),
                D9Labeled('Registration number', child: D9Input(controller: _registration, tab: true)),
              ],
            ),

          D9Labeled(
            'Department',
            child: D9Select(
              title: 'Department',
              value: _department,
              options: _departments,
              onChanged: (v) => setState(() => _department = v),
            ),
          ),

          // Locations
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Locations', bottom: 8),
              D9Locations(
                value: _locations,
                labels: _locationNames,
                onToggle: (i) => setState(() => _locations[i] = !_locations[i]),
              ),
            ],
          ),

          // Permissions info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.shield, size: 20, color: MP.primary)),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Permissions come from the role', style: tx(15, w: w600, c: MP.primary, h: 1.45)),
                      const Gap(2),
                      Text(D9Roles.summary(_role), style: tx(14, h: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          MpButton('Add to team', onTap: _submit),
        ],
      ),
    );
  }
}

/// Role radio pill: 40px, padding 0 16, radius 999 and a 1px border in both
/// states (#003399 on the filled selected pill, #D5DBE5 otherwise).
class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip(this.label, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Tap(
        onTap: onTap,
        radius: 999,
        color: selected ? MP.primary : MP.white,
        border: selected ? MP.primary : MP.lineStrong,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: tx(14, w: w600, c: selected ? MP.white : MP.ink2), maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

/// Live only: the 6-digit code sent to the new member's phone. Returns it.

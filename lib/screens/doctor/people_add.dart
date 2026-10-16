import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'add_patient.dart' show PatientOtpSheet;
import 'common_d9.dart';
import 'people_access.dart';
import '../../widgets/i18n.dart';

/// Design: People-Add.dc.html — "People · add".
/// Live data: GET /api/members/options (active locations, the doctors at each
/// with their departments, all departments). The form follows the role:
/// doctors add qualifications, registration and their department; a doctor's
/// assistant picks the doctor(s) they assist, and their department comes from
/// those doctors; a dietician's from the doctors at their locations; front
/// desk, lab roles and practice managers have no department. "Add to team"
/// verifies the phone (POST /api/members/phone-otp, code entered in a sheet)
/// and then POST /api/members with the code.
class PeopleAddScreen extends StatefulWidget {
  const PeopleAddScreen({super.key});

  @override
  State<PeopleAddScreen> createState() => _PeopleAddScreenState();
}

class _PeopleAddScreenState extends State<PeopleAddScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  String _role = 'Doctor';
  String? _department;
  List<bool> _locations = [true, false];
  final _assists = <String>{};

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
    final r = (await Api.I.get('/api/members/options') as Map).cast<String, dynamic>();
    final n = r.list('locations').length;
    // One location: it's ticked; several: the first, changed below.
    if (_locations.length != n) _locations = [for (var i = 0; i < n; i++) i == 0];
    return r;
  }

  TeamOptions get _options => TeamOptions(data);

  List<(String, String)> get _locationItems => _options.locations;

  Set<String> get _chosenLocations => {
    for (var i = 0; i < _locationItems.length && i < _locations.length; i++)
      if (_locations[i]) _locationItems[i].$1,
  };

  bool get _allLocations => _locations.isNotEmpty && _locations.every((v) => v);

  /// Doctors an assistant can work for: those at the chosen locations.
  List<({String id, String name, Set<String> locationIds, List<String> departments})> get _assistable =>
      _options.doctorsAt(_chosenLocations);

  List<String> get _departments => _options.departmentsFor(_role, _chosenLocations, assists: _assists);

  /// The department shown: the one picked if still offered, else the first
  /// (the chosen doctor's department for an assistant).
  String? get _departmentValue {
    final opts = _departments;
    if (opts.isEmpty) return null;
    return opts.contains(_department) ? _department : opts.first;
  }

  void _setRole(String r) => setState(() {
    _role = r;
    _department = null; // the new role's own default
    // A practice manager runs every location.
    if (r == 'Practice manager') _locations = [for (final _ in _locations) true];
  });

  void _toggleLocation(int i) => setState(() {
    _locations[i] = !_locations[i];
    // An assistant can only assist doctors who work where they do.
    final ids = {for (final d in _assistable) d.id};
    _assists.removeWhere((id) => !ids.contains(id));
  });

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
    final ids = _chosenLocations.toList();
    if (ids.isEmpty) return toast(context, 'Choose at least one location');
    if (_role == "Doctor's assistant" && _assists.isEmpty && _options.doctors.isNotEmpty) {
      return toast(context, 'Choose the doctor they assist');
    }
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

    final doctor = _role == 'Doctor';
    final dep = _departmentValue;
    final body = <String, Object?>{
      'role': D9Roles.key(_role),
      'name': name,
      'phone': phone,
      // Made for the practice if it's a doctor's specialty not yet a department here.
      if (dep != null && dep != TeamOptions.noDepartment) 'departmentName': dep,
      'locationIds': ids,
      'allLocations': _allLocations,
      if (_role == "Doctor's assistant") 'assistsDoctorIds': _assists.toList(),
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
    final dep = placeholder == null ? _departmentValue : null;
    final assistable = placeholder == null ? _assistable : const <({String id, String name, Set<String> locationIds, List<String> departments})>[];
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
                      child: _RoleChip(r, selected: r == _role, onTap: () => _setRole(r)),
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

          // Locations
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Locations', bottom: 8),
              D9Locations(
                value: _locations,
                labels: [for (final l in _locationItems) l.$2],
                onToggle: _toggleLocation,
              ),
              if (_role == 'Practice manager') ...[
                const Gap(8),
                Text('A practice manager usually looks after every location.', style: tx(13, c: MP.ink3, h: 1.4)),
              ],
            ],
          ),

          // Doctor's assistant: who they work for (doctors at the chosen locations).
          if (_role == "Doctor's assistant")
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const D9FieldLabel('Assists', bottom: 4),
                Text('The doctor or doctors they work for', style: tx(13, c: MP.ink3, h: 1.4)),
                const Gap(8),
                if (assistable.isEmpty)
                  Text('No doctors practise at the chosen locations yet.', style: tx(14, c: MP.ink2, h: 1.4))
                else
                  D9Locations(
                    value: [for (final d in assistable) _assists.contains(d.id)],
                    labels: [
                      for (final d in assistable) d.departments.isEmpty ? d.name : '${d.name} · ${d.departments.join(', ')}',
                    ],
                    onToggle: (i) => setState(() {
                      final id = assistable[i].id;
                      if (!_assists.remove(id)) _assists.add(id);
                      _department = null; // follows the doctor(s) they assist
                    }),
                  ),
              ],
            ),

          // Department: only for roles where it means something.
          if (dep != null)
            D9Labeled(
              'Department',
              child: D9Select(
                title: 'Department',
                value: dep,
                options: _departments,
                onChanged: (v) => setState(() => _department = v),
              ),
            ),
          if (dep == null && _role == 'Dietician')
            Text('No doctors practise at the chosen locations yet, so there is no department to choose.', style: tx(13, c: MP.ink3, h: 1.4)),

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

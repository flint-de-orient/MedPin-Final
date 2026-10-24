import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../data/where.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Add-Patient.dc.html — "Add patient".
///
/// Editing the phone number replaces "Verified" with a Verify button (as in
/// the form behind Add-Patient-Existing). Verifying a number that already has
/// a MedPin account (+91 98765 43210) opens 'Add-Patient-Existing'.
/// Puts a patient into today's queue as a walk-in (POST /api/appointments/walk-in).
/// With several doctors here, the desk picks one. Returns the token number.
/// [reason] is the complaint typed at the desk; it becomes the visit's reason
/// so the doctor's queue shows why they came.
Future<int?> addWalkIn(BuildContext context, String patientId, {String? doctorId, String? locationId, String? reason}) async {
  final why = reason?.trim() ?? '';
  try {
    final a = await Api.I.post('/api/appointments/walk-in', {
      'patientId': patientId,
      if (doctorId != null) 'doctorId': doctorId,
      if (locationId != null) 'locationId': locationId,
      if (why.isNotEmpty) 'reason': why,
    }) as Map;
    return (a['tokenNo'] as num?)?.toInt();
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    if (e.code == 'CHOOSE_DOCTOR') {
      final choices = [for (final c in (e.details?['choices'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
      final pick = await openSheet<Map<String, dynamic>>(
        context,
        (ctx) => MpSheet(
          title: 'Which doctor will see them?',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in choices)
                Tap(
                  onTap: () => Navigator.pop(ctx, c),
                  radius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Row(
                    children: [
                      MpAvatar(F.initials('${c['doctorName'] ?? ''}'), size: 40, fontSize: 14, photo: c['doctorPhoto'] is String && '${c['doctorPhoto']}'.isNotEmpty ? '${c['doctorPhoto']}' : null),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['doctorName'] ?? 'Doctor'}', style: tx(16, w: w600)),
                            Text('${c['locationName'] ?? ''}', style: tx(13, c: MP.ink2)),
                          ],
                        ),
                      ),
                      const Ico(I.chevronRight, size: 18, color: MP.ink3),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
      if (pick == null || !context.mounted) return null;
      return addWalkIn(context, patientId, doctorId: '${pick['doctorId']}', locationId: '${pick['locationId']}', reason: why);
    }
    toast(context, e.message);
    return null;
  }
}

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

/// (label, value, unit, keyboard). Two per row; an odd last one (blood sugar)
/// takes the full row so its Fasting / Random / After food choice fits under it.
const _vitals = [
  ('Blood pressure', '128/84', 'mmHg', TextInputType.datetime),
  ('Pulse', '78', 'bpm', TextInputType.number),
  ('SpO₂', '98', '%', TextInputType.number),
  ('Temperature', '98.6', '°F', TextInputType.numberWithOptions(decimal: true)),
  ('Weight', '62', 'kg', TextInputType.numberWithOptions(decimal: true)),
  ('Height', '160', 'cm', TextInputType.number),
  ('Blood sugar', '112', 'mg/dL', TextInputType.number),
];

// Indexes into [_vitals] / the vitals controllers.
const _bp = 0, _pulse = 1, _spo2 = 2, _temp = 3, _weight = 4, _height = 5, _sugar = 6;

/// When the sugar was taken: label shown → the API's sugarType.
const _sugarTypes = [('Fasting', 'fasting'), ('Random', 'random'), ('After food', 'post_meal')];

/// Tap-to-add complaints the desk hears most; added to the text, comma separated.
const _commonComplaints = [
  'Fever', 'Cough', 'Cold', 'Headache', 'Body ache', 'Stomach pain', 'Loose motions',
  'Vomiting', 'Breathlessness', 'Chest pain', 'Dizziness', 'Weakness', 'Burning urination',
  'Joint pain', 'Back pain', 'Skin rash', 'Sugar check', 'BP check', 'Follow-up',
];

/// Numbers that already have a MedPin account (digits only).
const _existingAccounts = {'9876543210'};

/// Live: small sheet for the code sent to the patient's phone (the design
/// has no screen for it; POST /api/patients checks the code).
/// Sends a code to a new patient's phone and asks for it (the patient reads it
/// out). Returns the code, or null when cancelled. Used by Add-Patient and
/// Consult-QuickAdd: a clinic can only register a number the patient confirms.
Future<String?> verifyPatientPhone(BuildContext context, String digits) async {
  Future<Map?> send() async {
    final r = await runAction(context, () => Api.I.post('/api/patients/phone-otp', {'phone': digits}));
    if (r is Map && context.mounted) D5Live.devCode(context, r);
    return r is Map ? r : null;
  }

  final otp = await send();
  if (otp == null || !context.mounted) return null;
  return openSheet<String>(
    context,
    (_) => PatientOtpSheet(masked: '${otp['maskedPhone'] ?? D5Live.phone(digits)}', resendIn: (otp['resendInSec'] as num?)?.toInt() ?? 30, resend: send),
  );
}

/// "Enter the code" sheet for a phone being verified (patient or team member).
/// Resend counts down, then asks for a new code ([resend] → the API's answer).
class PatientOtpSheet extends StatefulWidget {
  final String masked;
  final String title;
  final int resendIn;
  final Future<Map?> Function()? resend;
  final String button;
  const PatientOtpSheet({super.key, required this.masked, this.title = 'Verify the number', this.resendIn = 30, this.resend, this.button = 'Verify'});

  @override
  State<PatientOtpSheet> createState() => PatientOtpSheetState();
}

class PatientOtpSheetState extends State<PatientOtpSheet> {
  final _c = TextEditingController();
  late int _left = widget.resendIn;
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (widget.resend == null || _left > 0 || _sending) return;
    setState(() => _sending = true);
    final r = await widget.resend!();
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (r != null) _left = (r['resendInSec'] as num?)?.toInt() ?? 30;
    });
    if (r != null) {
      toast(context, r['reused'] == true ? 'The code already sent still works' : 'New code sent');
      _tick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final code = _c.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      toast(context, 'Enter the 6-digit code');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => MpSheet(
    title: widget.title,
    subtitle: 'Enter the 6-digit code sent to ${widget.masked}.',
    showClose: true,
    child: VGap(
      gap: 16,
      children: [
        MpInput(controller: _c, hint: '6-digit code', keyboard: TextInputType.number, autofocus: true, tab: true),
        MpButton(widget.button, onTap: _save),
        if (widget.resend != null)
          Center(
            child: MpHitSlop(
              child: Tap(
                onTap: _left > 0 || _sending ? null : _resend,
                radius: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  _sending ? 'Sending…' : _left > 0 ? 'Resend code in 0:${_left.toString().padLeft(2, '0')}' : 'Resend code',
                  style: tx(15, w: w600, c: _left > 0 || _sending ? MP.ink3 : MP.primary, tab: true),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  /// Opened from "Register walk-in": the new patient goes straight into today's queue.
  bool get _walkIn => (Nav.args<Map>(context) ?? const {})['walkIn'] == true;

  // Live: the form starts empty; the design's sample values only in preview.
  final _phone = TextEditingController(text: isLive ? '' : '98301 22457');
  String? _verifiedNumber = isLive ? null : '98301 22457';
  final _name = TextEditingController(text: isLive ? '' : 'Farhana Islam');
  final _age = TextEditingController(text: isLive ? '' : '34');
  final _address = TextEditingController(text: isLive ? '' : '14/2 Beliaghata Main Road, Kolkata 700010');
  final _complaint = TextEditingController();
  final _vitalCtrls = [for (final v in _vitals) TextEditingController(text: isLive ? '' : v.$2)];
  int _gender = 0;
  int _sugarType = 0;
  bool _vitalsOpen = true;
  bool _complaintsOpen = false;

  /// Address search: suggestions for what's typed, and the one picked
  /// ({lat, lng, area, city, pincode}, sent as `place`). The pick is kept only
  /// while the address still reads as its label.
  Timer? _addrTimer;
  List<Map<String, dynamic>> _addrHits = const [];
  Map<String, dynamic>? _place;
  String? _placeLabel;

  /// Live: the code sent to the patient's phone (checked when registering).
  String? _otpCode;
  bool _busy = false;

  /// A family member on a phone that already has a record (a child on the mother's phone):
  /// their own record under the holder (POST /api/patients {asFamily, relation}).
  bool _asFamily = false;
  String _relation = 'child';

  /// The number is on MedPin: this person, or someone else in the family using it?
  Future<String?> _whoIsIt(String? holderName) => openSheet<String>(
        context,
        (c) => MpSheet(
          title: 'This number is on MedPin',
          subtitle: holderName == null
              ? 'Is this the same person, or a family member using their phone (a child, a parent)?'
              : trf(context, 'It belongs to {name}. Is this {name}, or a family member using their phone?', {'name': holderName}),
          showClose: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MpButton(holderName == null ? 'The same person' : trf(context, "It's {name}", {'name': holderName}), onTap: () => Navigator.pop(c, 'same')),
                const SizedBox(height: 10),
                MpButton('A family member on this phone', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'family')),
              ],
            ),
          ),
        ),
      );

  Future<String?> _pickRelation() => openSheet<String>(
        context,
        (c) => MpSheet(
          title: 'How are they related?',
          subtitle: "To the phone's owner",
          showClose: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in const [('child', 'Child'), ('parent', 'Parent'), ('spouse', 'Spouse'), ('sibling', 'Brother / sister'), ('grandparent', 'Grandparent'), ('other', 'Other')])
                MpChip(r.$2, onTap: () => Navigator.pop(c, r.$1)),
            ]),
          ),
        ),
      );

  bool get _verified => _phone.text == _verifiedNumber;
  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    // The complaint chips show as selected while their word is in the text.
    _complaint.addListener(_onComplaintChanged);
  }

  void _onComplaintChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _addrTimer?.cancel();
    _complaint.removeListener(_onComplaintChanged);
    for (final c in [_phone, _name, _age, _address, _complaint, ..._vitalCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- Complaints ----

  List<String> get _complaintParts => [
    for (final s in _complaint.text.split(',')) if (s.trim().isNotEmpty) s.trim(),
  ];

  bool _hasComplaint(String c) => _complaintParts.any((s) => s.toLowerCase() == c.toLowerCase());

  /// Chip tap: adds the complaint to the end of the text, or takes it out again.
  void _toggleComplaint(String c) {
    final parts = _complaintParts;
    if (_hasComplaint(c)) {
      parts.removeWhere((s) => s.toLowerCase() == c.toLowerCase());
    } else {
      parts.add(c);
    }
    _complaint.text = parts.join(', ');
    _complaint.selection = TextSelection.collapsed(offset: _complaint.text.length);
  }

  /// Mic on the complaints: Voice.dictate with the 'symptoms' purpose (so the
  /// words are read as symptoms), added after what's already there — as
  /// [dictateInto] does, which has no purpose of its own.
  Future<void> _speakComplaint() async {
    final said = await Voice.dictate(context, title: 'Complaints', purpose: 'symptoms');
    if (said == null || said.trim().isEmpty) return;
    final before = _complaint.text.trimRight();
    _complaint.text = before.isEmpty ? said.trim() : (before.endsWith(',') ? '$before ${said.trim()}' : '$before, ${said.trim()}');
    _complaint.selection = TextSelection.collapsed(offset: _complaint.text.length);
  }

  // ---- Address ----

  /// Typing in the address: a changed text drops the picked place (its map
  /// point no longer matches), and suggestions follow ~400 ms after typing stops.
  void _onAddressChanged(String text) {
    _addrTimer?.cancel();
    final q = text.trim();
    setState(() {
      if (_place != null && q != _placeLabel) {
        _place = null;
        _placeLabel = null;
      }
      if (q.length < 3) _addrHits = const [];
    });
    if (q.length < 3 || !isLive) return;
    _addrTimer = Timer(const Duration(milliseconds: 400), () => _searchAddress(q));
  }

  Future<void> _searchAddress(String q) async {
    try {
      final r = await Api.I.get('/api/geo/search', query: {'q': q}) as Map;
      // A reply for older text (they kept typing) is dropped.
      if (!mounted || _address.text.trim() != q) return;
      final items = [
        for (final x in (r['items'] as List? ?? const []))
          if (x is Map && x['lat'] is num && x['lng'] is num && '${x['label'] ?? ''}'.trim().isNotEmpty) x.cast<String, dynamic>(),
      ];
      setState(() => _addrHits = items.take(5).toList());
    } catch (_) {
      // Offline, or address search is down (503): just no suggestions.
      if (mounted && _addrHits.isNotEmpty) setState(() => _addrHits = const []);
    }
  }

  void _pickAddress(Map<String, dynamic> hit) {
    _addrTimer?.cancel();
    final label = '${hit['label']}'.trim();
    setState(() {
      _address.text = label;
      _address.selection = TextSelection.collapsed(offset: label.length);
      _placeLabel = label;
      _place = {
        'lat': hit['lat'],
        'lng': hit['lng'],
        for (final k in const ['area', 'city', 'pincode'])
          if ('${hit[k] ?? ''}'.trim().isNotEmpty) k: '${hit[k]}'.trim(),
      };
      _addrHits = const [];
    });
    FocusScope.of(context).unfocus();
  }

  /// "Use current location": the street from the phone's location, keeping a
  /// house number already typed, and its map point (as a picked suggestion).
  void _useHere(Map<String, dynamic> place) {
    _addrTimer?.cancel();
    final line = addressLine(place, typed: _address.text);
    setState(() {
      if (line.isNotEmpty) {
        _address.text = line;
        _address.selection = TextSelection.collapsed(offset: line.length);
      }
      _placeLabel = _address.text.trim();
      _place = {
        'lat': place['lat'],
        'lng': place['lng'],
        for (final k in const ['area', 'city', 'pincode'])
          if ('${place[k] ?? ''}'.trim().isNotEmpty) k: '${place[k]}'.trim(),
      };
      _addrHits = const [];
    });
  }

  Future<void> _speakAddress() async {
    final said = await dictateInto(context, _address, title: 'Address');
    if (said == null || !mounted) return;
    _onAddressChanged(_address.text);
  }

  Future<void> _verify() async {
    final digits = _digits;
    if (digits.length != 10) {
      toast(context, 'Enter a 10-digit mobile number');
      return;
    }
    if (!isLive) {
      if (_existingAccounts.contains(digits)) {
        Nav.go(context, 'Add-Patient-Existing');
        return;
      }
      setState(() => _verifiedNumber = _phone.text);
      toast(context, 'Number verified');
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      // Already on MedPin? GET /api/patients/lookup
      final look = await runAction(context, () => Api.I.get('/api/patients/lookup', query: {'phone': digits}));
      if (look is! Map || !mounted) return;
      if (look['exists'] == true) {
        final p = look['patient'];
        // Someone else in the family using this phone: a new record of their own (the phone's
        // owner confirms with the code sent to it).
        final who = await _whoIsIt(look['linked'] == true && p is Map ? '${p['name']}' : null);
        if (who == null || !mounted) return;
        if (who == 'family') {
          final rel = await _pickRelation();
          if (rel == null || !mounted) return;
          final code = await verifyPatientPhone(context, digits);
          if (code == null || !mounted) return;
          setState(() {
            _asFamily = true;
            _relation = rel;
            _otpCode = code;
            _verifiedNumber = _phone.text;
          });
          return;
        }
        if (look['linked'] == true && p is Map) {
          if (_walkIn) {
            final token = await addWalkIn(context, '${p['id']}', reason: _complaint.text);
            if (token == null || !mounted) return;
            toast(context, '${p['name']} added to today\'s queue · token ${'$token'.padLeft(2, '0')}');
            Nav.back(context);
            return;
          }
          toast(context, '${p['name']} is already your patient');
          Nav.go(context, 'Patient-Profile', args: {'patientId': '${p['id']}'});
        } else {
          Nav.go(context, 'Add-Patient-Existing', args: {'phone': digits});
        }
        return;
      }
      // New number: send a code to the patient's phone.
      final code = await verifyPatientPhone(context, digits);
      if (code == null || !mounted) return;
      setState(() {
        _otpCode = code;
        _verifiedNumber = _phone.text;
      });
    } finally {
      _busy = false;
    }
  }

  Map<String, dynamic> _vitalsJson() {
    final n = _num;
    final bp = RegExp(r'^(\d{2,3})\s*/\s*(\d{2,3})$').firstMatch(_vitalCtrls[_bp].text.trim());
    final note = _complaint.text.trim();
    return {
      if (bp != null) 'bpSystolic': int.parse(bp.group(1)!),
      if (bp != null) 'bpDiastolic': int.parse(bp.group(2)!),
      if (n(_pulse) != null) 'pulse': n(_pulse),
      if (n(_spo2) != null) 'spo2': n(_spo2),
      if (n(_temp) != null) 'temperatureF': n(_temp),
      if (n(_weight) != null) 'weightKg': n(_weight),
      if (n(_height) != null) 'heightCm': n(_height),
      if (n(_sugar) != null) 'bloodSugar': n(_sugar),
      if (n(_sugar) != null) 'sugarType': _sugarTypes[_sugarType].$2,
      // The complaint travels with the vitals as their note.
      if (note.isNotEmpty) 'note': note,
    };
  }

  /// The number in vital [i] (a decimal comma counts as a point), null when empty.
  num? _num(int i) => num.tryParse(_vitalCtrls[i].text.trim().replaceAll(',', '.'));

  /// First vital that's not a plausible reading, as the message to show.
  String? _vitalsProblem() {
    final bp = _vitalCtrls[_bp].text.trim();
    if (bp.isNotEmpty && !RegExp(r'^\d{2,3}\s*/\s*\d{2,3}$').hasMatch(bp)) return 'Enter the blood pressure like 120/80';
    // (index, min, max, message) — a typo like 9.8 °F or 1600 cm is caught here.
    const ranges = [
      (_spo2, 50, 100, 'Enter SpO₂ between 50 and 100%'),
      (_temp, 90, 110, 'Enter the temperature in °F, between 90 and 110'),
      (_height, 30, 250, 'Enter the height in cm, between 30 and 250'),
    ];
    for (final (i, lo, hi, msg) in ranges) {
      if (_vitalCtrls[i].text.trim().isEmpty) continue;
      final v = _num(i);
      if (v == null || v < lo || v > hi) return msg;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_verified) {
      _verify();
      return;
    }
    if (!isLive) {
      toast(context, 'Patient added');
      Nav.back(context);
      return;
    }
    final problem = _vitalsProblem();
    if (problem != null) {
      // Open the vitals so the field to fix is in view.
      setState(() => _vitalsOpen = true);
      toast(context, problem);
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final vitals = _vitalsJson();
      final complaint = _complaint.text.trim();
      final p = await Api.I.post('/api/patients', {
        'name': _name.text.trim(),
        'phone': _digits,
        'gender': const ['female', 'male', 'other'][_gender],
        if (_age.text.trim().isNotEmpty) 'ageYears': int.tryParse(_age.text.trim()),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
        // A searched address: its map point (and the patient's geo for distance).
        if (_place != null && _address.text.trim() == _placeLabel) 'place': _place,
        if (_otpCode != null) 'otpCode': _otpCode,
        if (_asFamily) ...{'asFamily': true, 'relation': _relation},
        if (vitals.isNotEmpty) 'vitals': vitals,
        if (complaint.isNotEmpty) 'complaint': complaint,
      });
      if (!mounted) return;
      final id = '${(p as Map)['id']}';
      if (_walkIn) {
        final token = await addWalkIn(context, id, reason: complaint);
        if (!mounted) return;
        toast(context, token == null ? 'Patient added. Add them to the queue from Appointments.' : 'Patient added to today\'s queue · token ${'$token'.padLeft(2, '0')}');
        Nav.back(context);
        return;
      }
      final nav = Navigator.of(context);
      toast(context, 'Patient added');
      nav.pop();
      Nav.go(nav.context, 'Patient-Profile', args: {'patientId': id});
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'PATIENT_EXISTS') {
        Nav.go(context, 'Add-Patient-Existing', args: {'phone': _digits});
      } else {
        // A wrong or expired code has to be requested again.
        if (e.code == 'WRONG_CODE' || e.code == 'CODE_EXPIRED' || e.code == 'TOO_MANY_ATTEMPTS') {
          setState(() => _verifiedNumber = null);
        }
        toast(context, e.message);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Add patient'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          _details(),
          _Collapsible(
            title: 'Vitals',
            subtitle: 'Optional · the doctor sees these before the visit',
            open: _vitalsOpen,
            onToggle: () => setState(() => _vitalsOpen = !_vitalsOpen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var r = 0; r < _vitals.length; r += 2) ...[
                  if (r > 0) const Gap(16),
                  if (r + 1 < _vitals.length)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _VitalField(_vitals[r], controller: _vitalCtrls[r])),
                        const Gap(12),
                        Expanded(child: _VitalField(_vitals[r + 1], controller: _vitalCtrls[r + 1])),
                      ],
                    )
                  else
                    _VitalField(_vitals[r], controller: _vitalCtrls[r]),
                ],
                // When the sugar was taken (the doctor reads 140 differently fasting vs after food).
                const Gap(8),
                MpSegmented(
                  options: [for (final t in _sugarTypes) t.$1],
                  index: _sugarType,
                  height: 36,
                  fontSize: 14,
                  onChanged: (i) => setState(() => _sugarType = i),
                ),
              ],
            ),
          ),
          _Collapsible(
            title: 'Complaints',
            subtitle: 'Optional · what brings them in today',
            open: _complaintsOpen,
            onToggle: () => setState(() => _complaintsOpen = !_complaintsOpen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _commonComplaints)
                      MpChip(c, selected: _hasComplaint(c), tonal: true, height: 36, onTap: () => _toggleComplaint(c)),
                  ],
                ),
                const Gap(12),
                MpInput(
                  controller: _complaint,
                  hint: 'Describe the complaints, e.g. fever for 3 days',
                  maxLines: 3,
                  trailing: _MicButton(label: 'Speak the complaints', onTap: _speakComplaint),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 8), child: MpButton('Add patient', onTap: _submit)),
        ],
      ),
    );
  }

  Widget _details() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patient details', style: tx(20, w: w700, h: 1.25)),
              const Gap(2),
              Text('Required to register the patient', style: tx(14, c: MP.ink2)),
            ],
          ),
          MpInput(label: 'Full name', controller: _name),
          MpInput(label: 'Age', controller: _age, width: 144, unit: 'years', keyboard: TextInputType.number, tab: true),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MpLabel('Gender'),
              const Gap(8),
              MpSegmented(
                options: const ['Female', 'Male', 'Other'],
                index: _gender,
                onChanged: (i) => setState(() => _gender = i),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MpLabel('Phone number'),
              const Gap(8),
              Row(
                children: [
                  Expanded(
                    child: MpInput(
                      controller: _phone,
                      prefixText: '+91',
                      keyboard: TextInputType.phone,
                      tab: true,
                      onChanged: (_) => setState(() {}),
                      trailing:
                          _verified
                              ? Padding(
                                // input padding-right 12 (MpInput gives 8) · span padding-right 16
                                padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Ico(I.check, size: 18, color: MP.green, stroke: 2.25),
                                    const Gap(6),
                                    Text('Verified', style: tx(14, w: w600, c: MP.green)),
                                  ],
                                ),
                              )
                              : null,
                    ),
                  ),
                  if (!_verified) ...[
                    const Gap(8),
                    SizedBox(
                      height: 56,
                      child: Tap(
                        onTap: _verify,
                        radius: 16,
                        color: MP.primarySoft,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(widthFactor: 1, child: Text('Verify', style: tx(15, w: w600, c: MP.primary))),
                      ),
                    ),
                  ],
                ],
              ),
              if (_verified) ...[
                const Gap(8),
                Text("OTP confirmed. The patient's app will use this number.", style: tx(13, c: MP.ink3)),
              ],
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MpInput(
                label: 'Address',
                controller: _address,
                maxLines: 2,
                height: 80,
                onChanged: _onAddressChanged,
                trailing: _MicButton(label: 'Speak the address', onTap: _speakAddress),
              ),
              Align(alignment: Alignment.centerLeft, child: UseHereLink(onPlace: _useHere)),
              // Matches from address search; picking one also saves its map point.
              if (_addrHits.isNotEmpty) ...[
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: MP.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MP.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final h in _addrHits)
                        Tap(
                          onTap: () => _pickAddress(h),
                          radius: 10,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.pin, size: 16, color: MP.ink3)),
                              const Gap(8),
                              Expanded(child: Text('${h['label']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, h: 1.35))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (_place != null) ...[
                const Gap(8),
                Row(
                  children: [
                    const Ico(I.check, size: 16, color: MP.green, stroke: 2.25),
                    const Gap(6),
                    Expanded(child: Text('Address found on the map', style: tx(13, c: MP.ink3))),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Mic in the top-right of a multi-line field (as on D5MicField).
class _MicButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MicButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
    child: MpIconButton(I.mic, label: label, iconSize: 20, color: MP.primary, background: MP.primarySoft, onTap: onTap),
  );
}

/// Optional section. Expanded: card (padding 20) whose 48px header button has
/// -4px vertical margins, then the body 16px below. Collapsed: a 72px card
/// button (padding 12 20) with a down chevron.
class _Collapsible extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  const _Collapsible({
    required this.title,
    required this.subtitle,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  Widget _titles() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(title, style: tx(20, w: w700, h: 1.25)), const Gap(2), Text(subtitle, style: tx(14, c: MP.ink2))],
  );

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return Semantics(
        button: true,
        expanded: false,
        // <button>: border-box, min-height 72 including the 1px border.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Tap(
            onTap: onToggle,
            radius: 24,
            color: MP.white,
            border: MP.line,
            shadow: MPShadow.card,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(child: _titles()),
                const Gap(12),
                const Ico(I.chevronDown, size: 20, color: MP.ink2),
              ],
            ),
          ),
        ),
      );
    }
    return MpCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: true,
            child: Tap(
              onTap: onToggle,
              radius: 12,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(child: _titles()),
                    const Gap(12),
                    const Ico(I.chevronUp, size: 20, color: MP.ink2),
                  ],
                ),
              ),
            ),
          ),
          const Gap(12),
          child,
        ],
      ),
    );
  }
}

/// Vital input: label 14/600, 56px box (padding 0 14, radius 16), value 16px
/// tabular + unit 13px #69738A. Focus → #003399 border with the 3px ring.
class _VitalField extends StatefulWidget {
  final (String, String, String, TextInputType) v;
  final TextEditingController? controller;
  const _VitalField(this.v, {this.controller});

  @override
  State<_VitalField> createState() => _VitalFieldState();
}

class _VitalFieldState extends State<_VitalField> {
  late final _c = widget.controller ?? TextEditingController(text: widget.v.$2);
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, _, unit, keyboard) = widget.v;
    final focused = _f.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: tx(14, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        const Gap(8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: MP.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: focused ? MP.primary : MP.lineStrong),
            boxShadow: focused ? MPShadow.focusRing : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: MpFieldArea(child: TextField(
                  textAlignVertical: TextAlignVertical.center,
                  controller: _c,
                  focusNode: _f,
                  keyboardType: keyboard,
                  style: tx(16, tab: true),
                  cursorColor: MP.primary,
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                )),
              ),
              const Gap(6),
              Text(unit, style: tx(13, c: MP.ink3)),
            ],
          ),
        ),
      ],
    );
  }
}

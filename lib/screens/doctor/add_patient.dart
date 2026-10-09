import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Add-Patient.dc.html — "Add patient".
///
/// Editing the phone number replaces "Verified" with a Verify button (as in
/// the form behind Add-Patient-Existing). Verifying a number that already has
/// a MedPin account (+91 98765 43210) opens 'Add-Patient-Existing'.
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

/// (label, value, unit, keyboard)
const _vitals = [
  ('Blood pressure', '128/84', 'mmHg', TextInputType.datetime),
  ('Pulse', '78', 'bpm', TextInputType.number),
  ('Weight', '62', 'kg', TextInputType.number),
  ('Fasting sugar', '112', 'mg/dL', TextInputType.number),
];

/// Numbers that already have a MedPin account (digits only).
const _existingAccounts = {'9876543210'};

/// Live: small sheet for the code sent to the patient's phone (the design
/// has no screen for it; POST /api/patients checks the code).
class _OtpSheet extends StatefulWidget {
  final String masked;
  const _OtpSheet({required this.masked});

  @override
  State<_OtpSheet> createState() => _OtpSheetState();
}

class _OtpSheetState extends State<_OtpSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
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
    title: 'Verify the number',
    subtitle: 'Enter the 6-digit code sent to ${widget.masked}.',
    showClose: true,
    child: VGap(
      gap: 16,
      children: [
        MpInput(controller: _c, hint: '6-digit code', keyboard: TextInputType.number, autofocus: true, tab: true),
        MpButton('Verify', onTap: _save),
      ],
    ),
  );
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  // Live: the form starts empty; the design's sample values only in preview.
  final _phone = TextEditingController(text: isLive ? '' : '98301 22457');
  String? _verifiedNumber = isLive ? null : '98301 22457';
  final _name = TextEditingController(text: isLive ? '' : 'Farhana Islam');
  final _age = TextEditingController(text: isLive ? '' : '34');
  final _address = TextEditingController(text: isLive ? '' : '14/2 Beliaghata Main Road, Kolkata 700010');
  final _complaint = TextEditingController();
  final _vitalCtrls = [for (final v in _vitals) TextEditingController(text: isLive ? '' : v.$2)];
  int _gender = 0;
  bool _vitalsOpen = true;
  bool _complaintsOpen = false;

  /// Live: the code sent to the patient's phone (checked when registering).
  String? _otpCode;
  bool _busy = false;

  bool get _verified => _phone.text == _verifiedNumber;
  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');

  @override
  void dispose() {
    for (final c in [_phone, _name, _age, _address, _complaint, ..._vitalCtrls]) {
      c.dispose();
    }
    super.dispose();
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
        if (look['linked'] == true && p is Map) {
          toast(context, '${p['name']} is already your patient');
          Nav.go(context, 'Patient-Profile', args: {'patientId': '${p['id']}'});
        } else {
          Nav.go(context, 'Add-Patient-Existing', args: {'phone': digits});
        }
        return;
      }
      // New number: send a code to the patient's phone.
      final otp = await runAction(context, () => Api.I.post('/api/patients/phone-otp', {'phone': digits}));
      if (otp is! Map || !mounted) return;
      D5Live.devCode(context, otp);
      final code = await openSheet<String>(
        context,
        (_) => _OtpSheet(masked: '${otp['maskedPhone'] ?? D5Live.phone(digits)}'),
      );
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
    num? n(int i) => num.tryParse(_vitalCtrls[i].text.trim());
    final bp = RegExp(r'^(\d{2,3})\s*/\s*(\d{2,3})$').firstMatch(_vitalCtrls[0].text.trim());
    final note = _complaint.text.trim();
    return {
      if (bp != null) 'bpSystolic': int.parse(bp.group(1)!),
      if (bp != null) 'bpDiastolic': int.parse(bp.group(2)!),
      if (n(1) != null) 'pulse': n(1),
      if (n(2) != null) 'weightKg': n(2),
      if (n(3) != null) 'bloodSugar': n(3),
      if (n(3) != null) 'sugarType': 'fasting',
      // The complaint travels with the vitals as their note.
      if (note.isNotEmpty) 'note': note,
    };
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
    final bp = _vitalCtrls[0].text.trim();
    if (bp.isNotEmpty && !RegExp(r'^\d{2,3}\s*/\s*\d{2,3}$').hasMatch(bp)) {
      toast(context, 'Enter the blood pressure like 120/80');
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final vitals = _vitalsJson();
      final p = await Api.I.post('/api/patients', {
        'name': _name.text.trim(),
        'phone': _digits,
        'gender': const ['female', 'male', 'other'][_gender],
        if (_age.text.trim().isNotEmpty) 'ageYears': int.tryParse(_age.text.trim()),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
        if (_otpCode != null) 'otpCode': _otpCode,
        if (vitals.isNotEmpty) 'vitals': vitals,
      });
      if (!mounted) return;
      final nav = Navigator.of(context);
      toast(context, 'Patient added');
      nav.pop();
      Nav.go(nav.context, 'Patient-Profile', args: {'patientId': '${(p as Map)['id']}'});
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
              children: [
                for (var r = 0; r < _vitals.length; r += 2) ...[
                  if (r > 0) const Gap(16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _VitalField(_vitals[r], controller: _vitalCtrls[r])),
                      const Gap(12),
                      Expanded(child: _VitalField(_vitals[r + 1], controller: _vitalCtrls[r + 1])),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _Collapsible(
            title: 'Complaints',
            subtitle: 'Optional · what brings them in today',
            open: _complaintsOpen,
            onToggle: () => setState(() => _complaintsOpen = !_complaintsOpen),
            child: MpInput(controller: _complaint, hint: 'Describe the complaints, e.g. fever for 3 days', maxLines: 3),
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
          MpInput(label: 'Address', controller: _address, maxLines: 2, height: 80),
        ],
      ),
    );
  }
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
                child: TextField(
                  controller: _c,
                  focusNode: _f,
                  keyboardType: keyboard,
                  style: tx(16, tab: true),
                  cursorColor: MP.primary,
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                ),
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

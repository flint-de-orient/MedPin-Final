import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'add_patient.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-QuickAdd.dc.html — "Consultation · add new patient".
/// Bottom sheet opened over Consult-NotFound.
class ConsultQuickaddSheet extends StatefulWidget {
  const ConsultQuickaddSheet({super.key});

  @override
  State<ConsultQuickaddSheet> createState() => _ConsultQuickaddSheetState();
}

class _ConsultQuickaddSheetState extends State<ConsultQuickaddSheet> {
  /// Number carried over from the search and verified by OTP.
  static const _verifiedPhone = '98300 71245';

  final _phone = TextEditingController(text: isLive ? '' : _verifiedPhone);
  final _name = TextEditingController(text: isLive ? '' : 'Ankit Ghosh');
  final _age = TextEditingController();
  int _gender = 1;

  /// Field drawn with the focused 2px border: 0 phone, 1 name, 2 age.
  int _active = 1;

  /// Live: the number carried over from the search (not OTP-verified here).
  String? _carried;
  bool _argsRead = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_refresh);
    _name.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead || !isLive) return;
    _argsRead = true;
    // Live: the search text becomes the phone number or the name.
    final q = '${(Nav.args<Map>(context) ?? const {})['query'] ?? ''}'.trim();
    final digits = D5Live.digits(q);
    if (q.isNotEmpty && RegExp(r'^[\d\s+()-]+$').hasMatch(q)) {
      _carried = digits.length == 10 ? '${digits.substring(0, 5)} ${digits.substring(5)}' : digits;
      _phone.text = _carried!;
    } else if (q.isNotEmpty) {
      _name.text = q;
      _active = 2;
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final nav = Navigator.of(context);
    if (!isLive) {
      nav.pop();
      Nav.go(nav.context, 'Consult-Blank');
      return;
    }
    if (_busy) return;
    final phone = D5Live.digits(_phone.text);
    final name = _name.text.trim();
    final age = int.tryParse(_age.text.trim());
    if (phone.length != 10) return toast(context, 'Enter a 10-digit mobile number');
    if (name.isEmpty) return toast(context, 'Enter the patient name');
    if (age == null) return toast(context, 'Enter the age');
    setState(() => _busy = true);
    try {
      // Already on MedPin? Link with the patient's consent code instead.
      final look = await Api.I.get('/api/patients/lookup', query: {'phone': phone});
      if (look is Map && look['exists'] == true && look['linked'] != true) {
        throw const ApiException(409, 'PATIENT_EXISTS', 'This number already has a MedPin record.');
      }
      if (!mounted) return;
      // New number: the patient confirms it with the code sent to their phone.
      final code = await verifyPatientPhone(context, phone);
      if (code == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final p = await Api.I.post('/api/patients', {
        'name': name,
        'phone': phone,
        'gender': const ['female', 'male', 'other'][_gender],
        'ageYears': age,
        'otpCode': code,
      });
      final c = await Api.I.post('/api/consultations', {'patientId': (p as Map)['id']});
      if (!mounted) return;
      nav.pop();
      Nav.go(
        nav.context,
        'Consult-Blank',
        args: {'consultationId': '${(c as Map)['id']}', 'patientId': '${p['id']}', 'justAdded': true},
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'PATIENT_EXISTS') {
        // Link the existing MedPin record with the patient's consent code.
        nav.pop();
        Nav.go(nav.context, 'Add-Patient-Existing', args: {'phone': phone, 'startConsult': true});
        return;
      }
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = !isLive && _phone.text.trim() == _verifiedPhone;
    final carried = isLive && _carried != null && _phone.text.trim() == _carried;
    final name = _name.text.trim();
    final first = name.isEmpty ? 'The patient' : name.split(RegExp(r'\s+')).first;

    return MpSheet(
      child: VGap(
        padding: const EdgeInsets.only(top: 18),
        gap: 18,
        children: [
          const D5SheetTitle('Add new patient', subtitle: 'Just the basics. Add history during the consultation.'),

          // Phone number
          VGap(
            gap: 6,
            children: [
              Text('Phone number', style: tx(14, w: w600)),
              D5Field(
                controller: _phone,
                highlight: _active == 0,
                onFocus: () => setState(() => _active = 0),
                tab: true,
                padLeft: 54,
                padRight: 100,
                keyboard: TextInputType.phone,
                action: TextInputAction.next,
                overlays: [
                  Positioned(left: 16, top: 0, bottom: 0, child: Center(child: Text('+91', style: tx(16, c: MP.ink2)))),
                  if (verified)
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Ico(I.check, size: 16, color: MP.green, stroke: 2.5),
                            const Gap(4),
                            Text('Verified', style: tx(14, w: w600, c: MP.green)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (!isLive)
                Text('Carried over from your search. Verified by OTP.', style: tx(13, c: MP.ink3))
              else if (carried)
                Text('Carried over from your search.', style: tx(13, c: MP.ink3)),
            ],
          ),

          // Full name
          VGap(
            gap: 6,
            children: [
              Text('Full name', style: tx(14, w: w600)),
              D5Field(
                controller: _name,
                highlight: _active == 1,
                onFocus: () => setState(() => _active = 1),
                keyboard: TextInputType.name,
                action: TextInputAction.next,
              ),
            ],
          ),

          // Age + gender (grid: 96px 1fr, gap 12)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: VGap(
                  gap: 6,
                  children: [
                    Text('Age', style: tx(14, w: w600)),
                    D5Field(
                      controller: _age,
                      hint: 'Years',
                      highlight: _active == 2,
                      onFocus: () => setState(() => _active = 2),
                      padLeft: 14,
                      padRight: 14,
                      keyboard: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Expanded(
                child: VGap(
                  gap: 6,
                  children: [
                    Text('Gender', style: tx(14, w: w600)),
                    D5Segmented(
                      options: const ['Female', 'Male', 'Other'],
                      index: _gender,
                      height: 48,
                      onChanged: (i) => setState(() => _gender = i),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Text(
            '$first gets an SMS to join MedPin and share past reports. You don\'t need to wait for it.',
            style: tx(13, c: MP.ink3, h: 1.45),
          ),
          D5Button('Add and start consultation', onTap: _start),
        ],
      ),
    );
  }
}

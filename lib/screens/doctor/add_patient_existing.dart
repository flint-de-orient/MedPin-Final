import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Add-Patient-Existing.dc.html — "Add patient · existing account".
/// Sheet over 'Add-Patient'.
class AddPatientExistingSheet extends StatefulWidget {
  const AddPatientExistingSheet({super.key});

  @override
  State<AddPatientExistingSheet> createState() => _AddPatientExistingSheetState();
}

class _AddPatientExistingSheetState extends State<AddPatientExistingSheet> {
  static const _length = 6;

  /// The design shows 4 · 8 · 2 entered, waiting for the 4th digit.
  final _code = TextEditingController(text: isLive ? '' : '482');
  final _focus = FocusNode();
  bool _busy = false;

  /// Live: args {'phone', 'startConsult'?} from Add-Patient / Consult-QuickAdd.
  Map get _args => Nav.args<Map>(context) ?? const {};
  String get _phone => isLive ? D5Live.digits('${_args['phone'] ?? ''}') : '9876543210';

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _link() {
    if (_code.text.length < _length) {
      toast(context, 'Enter the 6-digit consent code');
      _focus.requestFocus();
      return;
    }
    final nav = Navigator.of(context);
    if (!isLive) {
      nav.pop(); // the sheet
      nav.maybePop(); // the Add patient form
      toast(nav.context, 'Patient linked to your practice');
      return;
    }
    _linkLive(nav);
  }

  /// POST /api/patients/link, then the patient's profile (or, from
  /// Consult-QuickAdd, a consultation for them).
  Future<void> _linkLive(NavigatorState nav) async {
    if (_busy) return;
    _busy = true;
    final startConsult = _args['startConsult'] == true;
    try {
      final p = await runAction(context, () => Api.I.post('/api/patients/link', {'phone': _phone, 'consentCode': _code.text}));
      if (p is! Map || !mounted) return;
      final id = '${p['id']}';
      if (startConsult) {
        final c = await runAction(context, () => Api.I.post('/api/consultations', {'patientId': id}));
        if (c is! Map || !mounted) return;
        nav.pop(); // the sheet
        toast(nav.context, 'Patient linked to your practice');
        Nav.go(nav.context, 'Consult-Page', args: {'consultationId': '${c['id']}', 'patientId': id});
        return;
      }
      nav.pop(); // the sheet
      if (nav.canPop()) nav.pop(); // the Add patient form
      toast(nav.context, 'Patient linked to your practice');
      Nav.go(nav.context, 'Patient-Profile', args: {'patientId': id});
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code.text;
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This number already has a MedPin account', style: tx(20, w: w700, h: 1.25)),
                const Gap(8),
                Text(
                  "We won't create a duplicate. Ask the patient for the consent code shown in their MedPin app to link their record to your practice.",
                  style: tx(16, c: MP.ink2, h: 1.5),
                ),
              ],
            ),
          ),
          const Gap(24),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Consent code', style: tx(14, w: w600))),
          Stack(
            children: [
              // Invisible field that owns the keyboard and the value.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _code,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_length),
                    ],
                    decoration: const InputDecoration.collapsed(hintText: null),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _code.selection = TextSelection.collapsed(offset: _code.text.length);
                  _focus.requestFocus();
                },
                child: Row(
                  children: [
                    for (var i = 0; i < _length; i++) ...[
                      if (i > 0) const Gap(8),
                      Expanded(
                        child: Semantics(
                          label: 'Digit ${i + 1} of 6',
                          value: i < code.length ? code[i] : '',
                          child: _Box(i < code.length ? code[i] : '', active: i == code.length),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Gap(8),
          Text("6 digits, from the patient's phone for ${D5Live.phone(_phone)}", style: tx(13, c: MP.ink3)),
          const Gap(24),
          MpButton('Link patient', onTap: _link),
          const Gap(12),
          MpButton('Cancel', kind: MpBtn.secondary, onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

/// One code box: 56px, radius 12, 1px #D5DBE5 (2px #003399 for the next
/// digit), 24/700 tabular digit.
class _Box extends StatelessWidget {
  final String digit;
  final bool active;
  const _Box(this.digit, {required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? MP.primary : MP.lineStrong, width: active ? 2 : 1),
      ),
      child: Text(digit, style: tx(24, w: w700, tab: true)),
    );
  }
}

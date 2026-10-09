import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';

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
  final _code = TextEditingController(text: '482');
  final _focus = FocusNode();

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
    nav.pop(); // the sheet
    nav.maybePop(); // the Add patient form
    toast(nav.context, 'Patient linked to your practice');
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
          Text("6 digits, from the patient's phone for +91 98765 43210", style: tx(13, c: MP.ink3)),
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

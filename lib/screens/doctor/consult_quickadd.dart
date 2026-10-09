import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';
import 'common_d5.dart';

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

  final _phone = TextEditingController(text: _verifiedPhone);
  final _name = TextEditingController(text: 'Ankit Ghosh');
  final _age = TextEditingController();
  int _gender = 1;

  /// Field drawn with the focused 2px border: 0 phone, 1 name, 2 age.
  int _active = 1;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_refresh);
    _name.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  void _start() {
    final nav = Navigator.of(context);
    nav.pop();
    Nav.go(nav.context, 'Consult-Blank');
  }

  @override
  Widget build(BuildContext context) {
    final verified = _phone.text.trim() == _verifiedPhone;
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
              Text('Carried over from your search. Verified by OTP.', style: tx(13, c: MP.ink3)),
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

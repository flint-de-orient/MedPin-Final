import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Consult-Dosage.dc.html — "Consultation · set dosage".
/// Bottom sheet opened over Consult-Page; pops with a [D5MedResult].
class ConsultDosageSheet extends StatefulWidget {
  const ConsultDosageSheet({super.key});

  @override
  State<ConsultDosageSheet> createState() => _ConsultDosageSheetState();
}

class _ConsultDosageSheetState extends State<ConsultDosageSheet> {
  static const _strengths = ['1 mg', '2 mg', '4 mg'];
  static const _times = ['Morning', 'Afternoon', 'Night'];
  static const _foods = ['Before', 'After', 'With'];
  static const _durations = ['7 days', '15 days', '30 days', '90 days', 'Custom'];

  int _strength = 0;
  final _on = [true, false, false];
  int _food = 0;
  int _duration = 2;
  int? _customDays;

  String get _when => _on.map((v) => v ? '1' : '0').join('-');
  int get _perDay => _on.where((v) => v).length;
  bool get _custom => _duration == _durations.length - 1;
  int? get _days => _custom ? _customDays : int.parse(_durations[_duration].split(' ').first);
  bool get _ready => _perDay > 0 && (_days ?? 0) > 0;

  String get _quantity {
    final d = _days ?? 0;
    if (d == 0) return 'Quantity: enter the number of days';
    final q = _perDay * d;
    return 'Quantity: $q ${q == 1 ? 'tablet' : 'tablets'}';
  }

  String get _foodText {
    final morningOnly = _on[0] && !_on[1] && !_on[2];
    return '${const ['before', 'after', 'with'][_food]} ${morningOnly ? 'breakfast' : 'food'}';
  }

  void _add() {
    final d = _days ?? 0;
    toast(context, 'Added to prescription');
    Navigator.pop<D5MedResult>(context, (
      name: 'Glimepiride ${_strengths[_strength]}',
      dose: '$_when · $_foodText',
      duration: d == 1 ? '1 day' : '$d days',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: VGap(
        padding: const EdgeInsets.only(top: 18),
        gap: 18,
        children: [
          const D5SheetTitle(
            'Glimepiride',
            subtitle: 'Tablet · sulfonylurea · suggested for poorly controlled diabetes',
          ),
          const D5Note('Priya has a sulfa drug allergy. Confirm it\'s safe, or pick Vildagliptin instead.'),

          // Strength
          VGap(
            gap: 8,
            children: [
              Text('Strength', style: tx(14, w: w600)),
              Row(
                children: [
                  for (var i = 0; i < _strengths.length; i++) ...[
                    if (i > 0) const Gap(8),
                    D5Chip(
                      _strengths[i],
                      on: i == _strength,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onTap: () => setState(() => _strength = i),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // When
          VGap(
            gap: 8,
            children: [
              Row(
                children: [
                  Expanded(child: Text('When', style: tx(14, w: w600))),
                  Text(_when, style: tx(14, w: w700, c: MP.primary, tab: true)),
                ],
              ),
              Row(
                children: [
                  for (var i = 0; i < _times.length; i++) ...[
                    if (i > 0) const Gap(8),
                    Expanded(
                      child: _TimeButton(label: _times[i], on: _on[i], onTap: () => setState(() => _on[i] = !_on[i])),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // With food
          VGap(
            gap: 8,
            children: [
              Text('With food', style: tx(14, w: w600)),
              D5Segmented(options: _foods, index: _food, onChanged: (i) => setState(() => _food = i)),
            ],
          ),

          // Duration
          VGap(
            gap: 8,
            children: [
              Text('Duration', style: tx(14, w: w600)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _durations.length; i++)
                    D5Chip(
                      _durations[i],
                      on: i == _duration,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onTap: () => setState(() => _duration = i),
                    ),
                ],
              ),
              if (_custom)
                D5Field(
                  value: _customDays?.toString(),
                  hint: 'Number of days',
                  autofocus: true,
                  tab: true,
                  keyboard: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  onChanged: (v) => setState(() => _customDays = int.tryParse(v)),
                ),
              Text(_quantity, style: tx(13, c: MP.ink3)),
            ],
          ),

          if (_ready) D5Button('Add to prescription', onTap: _add) else const D5Button.disabled('Add to prescription'),
        ],
      ),
    );
  }
}

/// Morning / Afternoon / Night toggle: 56px, radius 12; on = #EBF1FB with a
/// 1.5px #003399 border, off = white with a 1px #D5DBE5 border.
class _TimeButton extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _TimeButton({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = on ? MP.primary : MP.ink2;
    // Border-box button: the SizedBox outside keeps it 56px with either border.
    return Semantics(
      button: true,
      selected: on,
      child: SizedBox(
        height: 56,
        child: Tap(
          onTap: onTap,
          radius: 12,
          color: on ? MP.primarySoft : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          borderWidth: on ? 1.5 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w700, c: fg)),
              const Gap(2),
              Text(on ? '1 tablet' : 'None', style: tx(12, c: fg, tab: true)),
            ],
          ),
        ),
      ),
    );
  }
}

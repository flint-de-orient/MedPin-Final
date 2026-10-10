import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-Dosage.dc.html — "Consultation · set dosage".
/// Bottom sheet opened over Consult-Page; pops with a [D5MedResult].
/// Live: args {'item': prescription line, 'reason'?, 'caution'?}; strengths,
/// form and drug class from GET /api/catalog/medicines?q=.
class ConsultDosageSheet extends StatefulWidget {
  const ConsultDosageSheet({super.key});

  @override
  State<ConsultDosageSheet> createState() => _ConsultDosageSheetState();
}

class _ConsultDosageSheetState extends State<ConsultDosageSheet> with LiveData {
  static const _sampleStrengths = ['1 mg', '2 mg', '4 mg'];
  static const _times = ['Morning', 'Afternoon', 'Night'];
  static const _foods = ['Before', 'After', 'With'];
  static const _foodKeys = ['before_food', 'after_food', 'with_food'];
  static const _durations = ['7 days', '15 days', '30 days', '90 days', 'Custom'];

  int _strength = 0;
  final _on = [true, false, false];
  int _food = 0;
  int _duration = 2;
  int? _customDays;

  /// Live: what the consultation asked for ({'item', 'reason', 'caution'}).
  Map<String, dynamic> _args = const {};
  Map<String, dynamic> get _item => _args.obj('item');

  /// Live: the catalog medicine, its strength labels and the dose per time.
  Map<String, dynamic>? _catalog;
  List<String> _liveStrengths = const [];
  final _doses = <num>[1, 1, 1];

  @override
  Future<Object?> fetch() async {
    await Future<void>.value(); // the route args are read after initState
    if (!mounted) return const {};
    _args = (Nav.args<Map>(context) ?? const {}).cast<String, dynamic>();
    final item = _item;
    final name = item.str('name');
    final found = name.isEmpty ? const [] : await Api.I.get('/api/catalog/medicines', query: {'q': name});
    final meds = D5Live.list(found);
    _catalog =
        meds.where((m) => m.str('genericName').toLowerCase() == name.toLowerCase()).firstOrNull ??
        (meds.length == 1 ? meds.first : null);
    final strengths = <String>[
      for (final s in _catalog?.list('strengths') ?? const <Map<String, dynamic>>[])
        '${D5Live.number(s['value'])} ${s.str('unit')}'.trim(),
    ];
    final wanted = item.str('strength');
    if (wanted.isNotEmpty && !strengths.contains(wanted)) strengths.add(wanted);
    _liveStrengths = strengths;
    _strength = wanted.isEmpty ? 0 : strengths.indexOf(wanted).clamp(0, strengths.length);
    final dose = item.obj('dose');
    if (dose.isNotEmpty) {
      const keys = ['morning', 'afternoon', 'night'];
      for (var i = 0; i < 3; i++) {
        final v = dose[keys[i]];
        _on[i] = v is num && v > 0;
        if (v is num && v > 0) _doses[i] = v;
      }
    }
    final f = _foodKeys.indexOf(item.str('foodRelation'));
    if (f >= 0) _food = f;
    final days = D5Live.days(item['duration']);
    if (days != null) {
      final chip = _durations.indexOf('$days days');
      _duration = chip >= 0 ? chip : _durations.length - 1;
      if (chip < 0) _customDays = days;
    }
    return {'catalog': _catalog};
  }

  List<String> get _strengths => isLive ? _liveStrengths : _sampleStrengths;
  String get _form => isLive ? (_catalog?.str('form') ?? _item.str('form')) : 'Tablet';
  String get _name => isLive ? (_catalog?.str('genericName') ?? _item.str('name')) : 'Glimepiride';

  String get _subtitle {
    if (!isLive) return 'Tablet · sulfonylurea · suggested for poorly controlled diabetes';
    final reason = _args.str('reason');
    final parts = [
      _form,
      _catalog?.str('drugClass') ?? '',
      if (reason.isNotEmpty) reason[0].toLowerCase() + reason.substring(1),
    ].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'Not in the medicine catalog' : parts.join(' · ');
  }

  String? get _caution {
    if (!isLive) return 'Priya has a sulfa drug allergy. Confirm it\'s safe, or pick Vildagliptin instead.';
    final c = _args.str('caution');
    return c.isEmpty ? null : c;
  }

  /// 'tablet', 'capsule' … for the dose buttons and the quantity.
  String get _unit => _form.isEmpty ? 'tablet' : _form.toLowerCase();
  String _units(num n) => n == 1 ? '1 $_unit' : '${D5Live.number(n)} ${_unit}s';

  String get _when =>
      isLive
          ? [for (var i = 0; i < 3; i++) _on[i] ? D5Live.number(_doses[i]) : '0'].join('-')
          : _on.map((v) => v ? '1' : '0').join('-');
  int get _perDay => _on.where((v) => v).length;
  num get _perDayUnits => [for (var i = 0; i < 3; i++) if (_on[i]) _doses[i]].fold<num>(0, (a, b) => a + b);
  bool get _weekly => isLive && _item['frequency'] == 'weekly';
  bool get _custom => _duration == _durations.length - 1;
  int? get _days => _custom ? _customDays : int.parse(_durations[_duration].split(' ').first);
  bool get _ready => _perDay > 0 && (_days ?? 0) > 0 && (!isLive || _name.isNotEmpty);

  String get _quantity {
    final d = _days ?? 0;
    if (d == 0) return 'Quantity: enter the number of days';
    if (isLive) return 'Quantity: ${_units(_weekly ? (d / 7).ceil() * _perDayUnits : _perDayUnits * d)}';
    final q = _perDay * d;
    return 'Quantity: $q ${q == 1 ? 'tablet' : 'tablets'}';
  }

  String get _foodText {
    final morningOnly = _on[0] && !_on[1] && !_on[2];
    return '${const ['before', 'after', 'with'][_food]} ${morningOnly ? 'breakfast' : 'food'}';
  }

  void _add() {
    final d = _days ?? 0;
    if (!isLive) {
      toast(context, 'Added to prescription');
      Navigator.pop<D5MedResult>(context, (
        name: 'Glimepiride ${_strengths[_strength]}',
        dose: '$_when · $_foodText',
        duration: d == 1 ? '1 day' : '$d days',
        item: null,
      ));
      return;
    }
    const keys = ['morning', 'afternoon', 'night'];
    final line = D5Live.item({
      ..._item,
      'name': _name,
      if (_strengths.isNotEmpty) 'strength': _strengths[_strength],
      if (_form.isNotEmpty) 'form': _form,
      if (_catalog?['id'] != null) 'medicineId': _catalog!['id'],
      'dose': {for (var i = 0; i < 3; i++) keys[i]: _on[i] ? _doses[i] : 0},
      'frequency': _weekly ? 'weekly' : 'daily',
      'foodRelation': _foodKeys[_food],
      'instructions': _foodText,
      'duration': {'value': d, 'unit': 'days'},
      // The server re-checks allergies for the saved line.
      'caution': null,
    });
    toast(context, 'Added to prescription');
    Navigator.pop<D5MedResult>(context, (
      name: D5Live.medName(line),
      dose: D5Live.doseText(line),
      duration: D5Live.durationText(line['duration']),
      item: line,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (placeholder != null) return MpSheet(child: placeholder);
    final caution = _caution;
    return MpSheet(
      child: VGap(
        padding: const EdgeInsets.only(top: 18),
        gap: 18,
        children: [
          D5SheetTitle(_name, subtitle: _subtitle),
          if (caution != null) D5Note(caution),

          // Strength
          VGap(
            gap: 8,
            children: [
              Text('Strength', style: tx(14, w: w600)),
              // One line in the design; live catalogs can list more strengths.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _strengths.length; i++)
                    D5Chip(
                      _strengths[i],
                      on: i == _strength,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onTap: () => setState(() => _strength = i),
                    ),
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
                      child: _TimeButton(
                        label: _times[i],
                        on: _on[i],
                        amount: isLive ? _units(_doses[i]) : '1 tablet',
                        onTap: () => setState(() => _on[i] = !_on[i]),
                      ),
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
  final String amount;
  final VoidCallback onTap;
  const _TimeButton({required this.label, required this.on, this.amount = '1 tablet', required this.onTap});

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
              Text(on ? amount : 'None', style: tx(12, c: fg, tab: true)),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart' hide Text;

import '../../data/live.dart';
import '../../data/voice.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-Voice.dc.html — "Consultation · medicine by voice".
/// Bottom sheet opened over Consult-Page; pops with a [D5MedResult].
class ConsultVoiceSheet extends StatefulWidget {
  const ConsultVoiceSheet({super.key});

  @override
  State<ConsultVoiceSheet> createState() => _ConsultVoiceSheetState();
}

class _ConsultVoiceSheetState extends State<ConsultVoiceSheet> with SingleTickerProviderStateMixin {
  static const _bars = <double>[
    8,
    14,
    22,
    30,
    18,
    26,
    36,
    24,
    16,
    28,
    38,
    30,
    20,
    12,
    24,
    32,
    18,
    10,
    14,
    8,
    6,
    6,
    6,
    6,
  ];

  /// Bars already heard (drawn in #003399); the rest are #D5DBE5.
  static const _heard = 18;

  static const _parsed = [
    ('Medicine', 'Glimepiride 1 mg'),
    ('When', '1-0-0'),
    ('Food', 'Before breakfast'),
    ('Duration', '30 days'),
  ];

  /// Replays the waveform when the doctor taps "Say again".
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// Live: the line the doctor said (or typed) in the medicine field
  /// (args {'text', 'caution'?}); "Say again" listens once more.
  Map<String, dynamic> get _args => (Nav.args<Map>(context) ?? const {}).cast<String, dynamic>();
  String? _said;
  String get _text => (_said ?? _args.str('text')).trim();
  Map<String, dynamic>? _parsedItem;
  Map<String, dynamic> get _item => _parsedItem ??= D5Live.parse(_text, source: 'voice');

  Future<void> _sayAgain() async {
    _wave.forward(from: 0);
    if (!isLive) return;
    final said = await Voice.dictate(context, title: 'Say the medicine', hint: 'e.g. “Metformin 500 twice daily after food”');
    if (said == null || !mounted) return;
    setState(() {
      _said = said;
      _parsedItem = null;
    });
  }

  List<(String, String)> get _items {
    if (!isLive) return _parsed;
    final food = D5Live.food(_item);
    final dur = D5Live.durationText(_item['duration']);
    return [
      ('Medicine', D5Live.medName(_item)),
      ('When', D5Live.when(_item)),
      ('Food', food.isEmpty ? '—' : food[0].toUpperCase() + food.substring(1)),
      ('Duration', dur.isEmpty ? '—' : dur),
    ];
  }

  void _add() {
    if (!isLive) {
      toast(context, 'Glimepiride 1 mg added');
      Navigator.pop<D5MedResult>(context, (
        name: 'Glimepiride 1 mg',
        dose: '1-0-0 · before breakfast',
        duration: '30 days',
        item: null,
      ));
      return;
    }
    if (_item.str('name').isEmpty) {
      toast(context, 'Say or type the medicine name first');
      return;
    }
    final line = D5Live.item(_item);
    toast(context, '${D5Live.medName(line)} added');
    Navigator.pop<D5MedResult>(context, (
      name: D5Live.medName(line),
      dose: D5Live.doseText(line),
      duration: D5Live.durationText(line['duration']),
      item: line,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return MpSheet(
      child: VGap(
        padding: const EdgeInsets.only(top: 20),
        gap: 20,
        children: [
          Row(
            children: [
              Expanded(child: Text('Add medicine by voice', style: tx(20, w: w700, h: 1.25))),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
              ),
              const Gap(6),
              Text('Listening', style: tx(13, w: w600, c: MP.primary)),
            ],
          ),
          Semantics(
            liveRegion: true,
            child: Text.rich(
              isLive
                  ? TextSpan(text: '“$_text”')
                  : TextSpan(
                    text: '“Glimepiride one mg, once in the morning before breakfast, ',
                    children: [TextSpan(text: 'for thirty days”', style: tx(20, w: w600, c: MP.ink3, h: 1.4))],
                  ),
              style: tx(20, w: w600, h: 1.4),
            ),
          ),
          ExcludeSemantics(
            child: SizedBox(
              height: 40,
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) {
                  final filled = (_wave.value * _heard).round();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _bars.length; i++) ...[
                        if (i > 0) const Gap(4),
                        Container(
                          width: 4,
                          height: _bars[i],
                          decoration: BoxDecoration(
                            color: i < filled ? MP.primary : MP.lineStrong,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
            child: VGap(
              gap: 12,
              children: [
                const D5Label('Understood as', color: MP.green, icon: I.check, stroke: 2.5),
                Column(
                  children: [
                    for (var r = 0; r < items.length; r += 2) ...[
                      if (r > 0) const Gap(12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _Parsed(items[r])),
                          const Gap(16),
                          Expanded(child: _Parsed(items[r + 1])),
                        ],
                      ),
                    ],
                  ],
                ),
                if (!isLive)
                  const D5Note('Sulfonylurea. Priya has a sulfa drug allergy.')
                else if (_args.str('caution').isNotEmpty)
                  D5Note(_args.str('caution')),
              ],
            ),
          ),
          Text('Try: “Atorvastatin 20 at night for 3 months”', style: tx(13, c: MP.ink3)),
          Row(
            children: [
              Expanded(child: D5Button.secondary('Say again', onTap: _sayAgain)),
              const Gap(8),
              Expanded(flex: 2, child: D5Button('Add medicine', onTap: _add)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One "Understood as" value: 12px label over a 16 / 700 value.
class _Parsed extends StatelessWidget {
  final (String, String) item;
  const _Parsed(this.item);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(item.$1, style: tx(12, c: MP.ink2)),
      const Gap(2),
      Text(item.$2, style: tx(16, w: w700, tab: true)),
    ],
  );
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Consult-Vitals.dc.html — "Consult 1 · Vitals".
class ConsultVitalsScreen extends StatefulWidget {
  const ConsultVitalsScreen({super.key});

  @override
  State<ConsultVitalsScreen> createState() => _ConsultVitalsScreenState();
}

class _ConsultVitalsScreenState extends State<ConsultVitalsScreen> {
  /// id, label, value, unit — renderVals().fields.
  static const _fields = [
    ('v-sys', 'BP systolic', '128', 'mmHg'),
    ('v-dia', 'BP diastolic', '82', 'mmHg'),
    ('v-pulse', 'Pulse', '78', 'bpm'),
    ('v-spo2', 'SpO2', '98', '%'),
    ('v-temp', 'Temperature', '98.4', '°F'),
    ('v-wt', 'Weight', '68.5', 'kg'),
    ('v-ht', 'Height', '158', 'cm'),
    ('v-fbs', 'Fasting sugar', '142', 'mg/dL'),
  ];

  final _values = {for (final f in _fields) f.$1: f.$3};
  bool _onPrescription = true;

  /// BMI from the weight (kg) and height (cm) fields — 27.4 for the design values.
  double? get _bmi {
    final w = double.tryParse(_values['v-wt']!.trim());
    final h = double.tryParse(_values['v-ht']!.trim());
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    final m = h / 100;
    return w / (m * m);
  }

  static (String, Color, Color) _band(double bmi) {
    if (bmi < 18.5) return ('Underweight', MP.amberSoft, MP.amber);
    if (bmi < 25) return ('Normal', MP.greenSoft, MP.green);
    if (bmi < 30) return ('Overweight', MP.amberSoft, MP.amber);
    return ('Obese', MP.redSoft, MP.red);
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Consultation'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D7ConsultTop(step: 0),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            gap: 16,
            children: [_vitalsCard(), _complaintCard()],
          ),
        ],
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: MpButton('Next: Diagnosis', onTap: () => Nav.go(context, 'Consult-Diagnosis')),
      ),
    );
  }

  Widget _vitalsCard() {
    final bmi = _bmi;
    final band = bmi == null ? null : _band(bmi);
    final rows = <Widget>[];
    for (var i = 0; i < _fields.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 16));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(_fields[i])),
            const SizedBox(width: 12),
            Expanded(child: _field(_fields[i + 1])),
          ],
        ),
      );
    }
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vitals', style: tx(20, w: w700, h: 1.25)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Ico(I.check, size: 16, color: MP.green, stroke: 2.25),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Recorded at the front desk, 8:52 AM', style: tx(14, c: MP.ink2, h: 1.45))),
                ],
              ),
            ],
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          // BMI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BMI', style: tx(16, w: w600)),
                      const SizedBox(height: 2),
                      Text('Calculated from height and weight', style: tx(13, c: MP.ink3)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(bmi == null ? '–' : bmi.toStringAsFixed(1), style: tx(20, w: w700, tab: true)),
                ),
                if (band != null) ...[const SizedBox(width: 12), MpBadge(band.$1, bg: band.$2, fg: band.$3)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field((String, String, String, String) f) {
    return D7Labeled(
      f.$2,
      child: D7Field(
        value: f.$3,
        tab: true,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        action: TextInputAction.next,
        padding: const EdgeInsets.only(left: 16, right: 64),
        onChanged: (v) => setState(() => _values[f.$1] = v),
        overlays: [Positioned(right: 16, top: 18, child: IgnorePointer(child: Text(f.$4, style: tx(14, c: MP.ink3))))],
      ),
    );
  }

  Widget _complaintCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Chief complaint'),
          const D7Field(
            value: 'Chest tightness since morning with mild sweating. Tired for about two weeks.',
            lines: 3,
            height: 104,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          D7Ruled(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Show on prescription', style: tx(16, w: w600)),
                      const SizedBox(height: 2),
                      Text('Vitals and complaint print on the PDF', style: tx(14, c: MP.ink2, h: 1.45)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  label: 'Show on prescription',
                  child: MpSwitch(value: _onPrescription, onChanged: (v) => setState(() => _onPrescription = v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

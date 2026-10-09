import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Consult-Advice.dc.html — "Consult 3 · Advice".
class ConsultAdviceScreen extends StatefulWidget {
  const ConsultAdviceScreen({super.key});

  @override
  State<ConsultAdviceScreen> createState() => _ConsultAdviceScreenState();
}

class _ConsultAdviceScreenState extends State<ConsultAdviceScreen> {
  /// Medicine, dosage line, catalog warning.
  static const List<(String, String, String?)> _meds = [
    ('Metformin 500 mg', '1-0-1 · After food · 30 days', null),
    (
      'Glimepiride 3 mg',
      '1-0-0 · Before breakfast · 30 days',
      'Catalog strengths for Glimepiride: 1, 2, 4 mg. Check the strength.',
    ),
    ('Atorvastatin 10 mg', '0-0-1 · At night · 30 days', null),
  ];

  /// Test categories: chip label, caption under each test, tests it adds.
  static const _panels = [
    ('Diabetes panel', 'Diabetes panel', ['HbA1c', 'Fasting glucose', 'Post-prandial glucose']),
    ('Lipid', 'Lipid panel', ['Lipid profile']),
    ('Thyroid', 'Thyroid panel', ['TSH', 'Free T4']),
    ('Kidney', 'Kidney panel', ['Serum creatinine', 'Urine albumin']),
  ];

  static const _presets = ['1 week', '2 weeks', '1 month', '3 months'];

  /// The design's "today" (Tue 29 Sep 2026); "1 month" → Thu, 29 Oct 2026.
  static final _today = DateTime(2026, 9, 29);

  /// Selected tests: name, panel index.
  final List<(String, int)> _tests = [('HbA1c', 0), ('Fasting glucose', 0), ('Post-prandial glucose', 0)];
  int _preset = 2;
  DateTime _next = DateTime(2026, 10, 29);

  static DateTime _presetDate(int i) => switch (i) {
    0 => _today.add(const Duration(days: 7)),
    1 => _today.add(const Duration(days: 14)),
    2 => DateTime(_today.year, _today.month + 1, _today.day),
    _ => DateTime(_today.year, _today.month + 3, _today.day),
  };

  bool _panelOn(int p) => _tests.any((t) => t.$2 == p);

  void _togglePanel(int p) {
    setState(() {
      if (_panelOn(p)) {
        _tests.removeWhere((t) => t.$2 == p);
      } else {
        for (final n in _panels[p].$3) {
          if (!_tests.any((t) => t.$1 == n)) _tests.add((n, p));
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _next,
      firstDate: _today,
      lastDate: DateTime(2027, 12, 31),
      helpText: 'Next visit',
    );
    if (d == null || !mounted) return;
    setState(() {
      _next = d;
      _preset = -1;
      for (var i = 0; i < _presets.length; i++) {
        if (DateUtils.isSameDay(_presetDate(i), d)) _preset = i;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Consultation'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D7ConsultTop(step: 2),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            gap: 16,
            children: [
              _medicinesCard(),
              _labCard(),
              MpCard(
                child: VGap(
                  gap: 16,
                  children: const [
                    D7Title('General advice'),
                    D7Field(
                      value:
                          'Walk 30 minutes daily. Avoid sweets and fried food. Come in at once if chest tightness returns.',
                      lines: 4,
                      height: 128,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ],
                ),
              ),
              _followUpCard(),
              _signatureCard(),
            ],
          ),
        ],
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: MpButton(
          'Generate prescription',
          onTap: () {
            toast(context, 'Prescription generated');
            Nav.go(context, 'Prescriptions');
          },
        ),
      ),
    );
  }

  Widget _medicinesCard() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: D7Title('Medicines', sub: '3 added · checked against the brand catalog'),
          ),
          for (var i = 0; i < _meds.length; i++)
            D7Ruled(
              bottom: i == _meds.length - 1,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child:
                  _meds[i].$3 == null
                      ? _medRow(_meds[i])
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_medRow(_meds[i]), const SizedBox(height: 12), _warning(_meds[i].$3!)],
                      ),
            ),
          const SizedBox(height: 16),
          MpButton.small('Add medicine', icon: I.plus, onTap: () => Nav.go(context, 'Consult-Voice')),
        ],
      ),
    );
  }

  Widget _medRow((String, String, String?) m) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.$1, style: tx(16, w: w600)),
              const SizedBox(height: 2),
              Text(m.$2, style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        MpIconButton(
          I.edit,
          label: 'Edit ${m.$1}',
          color: MP.primary,
          background: MP.primarySoft,
          iconSize: 18,
          onTap: () => Nav.go(context, 'Consult-Dosage'),
        ),
      ],
    );
  }

  Widget _warning(String text) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.alert, size: 18, color: MP.amber)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: tx(14, h: 1.45))),
          ],
        ),
      ),
    );
  }

  Widget _labCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          D7Title('Lab tests', sub: '${_tests.length} selected'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ADD BY CATEGORY', style: tx(12, w: w600, h: 1.35, em: 0.06, c: MP.ink3)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var p = 0; p < _panels.length; p++)
                    D7Pill(_panels[p].$1, on: _panelOn(p), check: true, onTap: () => _togglePanel(p)),
                ],
              ),
            ],
          ),
          if (_tests.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in _tests)
                  D7Ruled(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.$1, style: tx(16, w: w600)),
                              const SizedBox(height: 2),
                              Text(_panels[t.$2].$2, style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        MpIconButton(
                          I.close,
                          label: 'Remove ${t.$1}',
                          color: MP.ink2,
                          iconSize: 20,
                          onTap: () => setState(() => _tests.remove(t)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _followUpCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Follow-up'),
          Row(
            children: [
              for (var i = 0; i < _presets.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: D7Pill(
                    _presets[i],
                    on: _preset == i,
                    hPad: 0,
                    fill: true,
                    onTap:
                        () => setState(() {
                          _preset = i;
                          _next = _presetDate(i);
                        }),
                  ),
                ),
              ],
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Ico(I.calendar, size: 20, color: MP.ink2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next visit', style: tx(13, c: MP.ink3)),
                      const SizedBox(height: 2),
                      Text(d7Date(_next), style: tx(16, w: w600, tab: true)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                D7Btn('Change', size: 14, height: 44, radius: 8, padding: EdgeInsets.zero, onTap: _pickDate),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _signature =
      '<svg viewBox="0 0 180 56"><path d="M8 46c8-6 16-24 22-38 3 12 5 24 4 34M18 30c8-1 14-2 20-3M46 42c3-9 12-14 15-7 2 6-10 9-6 2 5-8 13-6 12 1-1 6 6 1 10-5 2 8 9 10 15 2 4-6 10-6 11 2 2 6 8 2 13-5" fill="none" stroke="#111827" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M40 50c30-3 70-6 124-8" fill="none" stroke="#111827" stroke-width="1.5" stroke-linecap="round"/></svg>';

  Widget _signatureCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Digital signature', sub: 'Prints at the foot of the prescription'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MP.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MP.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    label: 'Signature of Dr. Arjun Sen',
                    image: true,
                    child: const Svg(_signature, width: 180, height: 56),
                  ),
                ),
                const SizedBox(height: 12),
                D7Ruled(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dr. Arjun Sen', style: tx(16, w: w700)),
                      const SizedBox(height: 2),
                      Text('MBBS, MD · WBMC 64213', style: tx(14, c: MP.ink2, h: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

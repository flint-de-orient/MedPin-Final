import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Consult-Diagnosis.dc.html — "Consult 2 · Diagnosis".
class ConsultDiagnosisScreen extends StatefulWidget {
  const ConsultDiagnosisScreen({super.key});

  @override
  State<ConsultDiagnosisScreen> createState() => _ConsultDiagnosisScreenState();
}

class _ConsultDiagnosisScreenState extends State<ConsultDiagnosisScreen> {
  /// Previous diagnoses: label, note shown once reused (renderVals().previous).
  static const _previous = [
    ('Type 2 diabetes mellitus', 'Reused from 12 Mar 2026'),
    ('PCOS', 'Reused from 12 Jan 2026'),
    ('Obesity', 'Reused from 12 Jan 2026'),
  ];

  /// Condition catalog (name, ICD-10). The first three are the design's
  /// matches for "hyper", in the design's order.
  static const _catalog = [
    ('Essential hypertension', 'I10'),
    ('Hypertriglyceridaemia', 'E78.1'),
    ('Hyperthyroidism', 'E05.9'),
    ('Hypothyroidism', 'E03.9'),
    ('Type 2 diabetes mellitus', 'E11.9'),
    ('Polycystic ovary syndrome', 'E28.2'),
    ('Obesity', 'E66.9'),
    ('Dyslipidaemia', 'E78.5'),
    ('Iron deficiency anaemia', 'D50.9'),
    ('Gastro-oesophageal reflux disease', 'K21.9'),
    ('Migraine', 'G43.9'),
    ('Asthma', 'J45.9'),
  ];

  final _query = TextEditingController(text: 'hyper');

  /// Selected diagnoses (name, note) — the design starts with the two reused ones.
  final List<(String, String)> _selected = [_previous[0], _previous[1]];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _isSelected(String name) => _selected.any((s) => s.$1 == name);

  void _toggle(String name, String note) {
    setState(() {
      final i = _selected.indexWhere((s) => s.$1 == name);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add((name, note));
      }
    });
  }

  List<(String, String)> get _results {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final c in _catalog)
        if (c.$1.toLowerCase().contains(q)) c,
    ];
  }

  void _addCustom() {
    final q = _query.text.trim();
    if (q.isEmpty) {
      toast(context, 'Type the diagnosis in the search box first');
      return;
    }
    final name = q[0].toUpperCase() + q.substring(1);
    setState(() {
      if (!_isSelected(name)) _selected.add((name, 'Custom diagnosis'));
      _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Consultation'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D7ConsultTop(step: 1),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            gap: 16,
            children: [_previousCard(), _addCard(), _selectedCard()],
          ),
        ],
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            Expanded(child: MpButton('Back', kind: MpBtn.secondary, onTap: () => Nav.back(context))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: MpButton('Next: Advice', onTap: () => Nav.go(context, 'Consult-Advice'))),
          ],
        ),
      ),
    );
  }

  Widget _previousCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Previous diagnoses', sub: 'Tap to reuse on this prescription'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _previous)
                D7Pill(p.$1, on: _isSelected(p.$1), check: true, onTap: () => _toggle(p.$1, p.$2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addCard() {
    final results = _results;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 16), child: D7Title('Add a diagnosis')),
          D7Field(
            controller: _query,
            border: MP.primary,
            padding: const EdgeInsets.only(left: 48, right: 56),
            action: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            overlays: [
              const Positioned(left: 16, top: 18, child: IgnorePointer(child: Ico(I.search, size: 20, color: MP.ink2))),
              if (_query.text.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: MpIconButton(
                    I.close,
                    label: 'Clear search',
                    color: MP.ink2,
                    iconSize: 18,
                    onTap: () => setState(_query.clear),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in results) _result(r),
                if (results.isEmpty && _query.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('No match in the catalog', style: tx(13, c: MP.ink3)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: D7Btn(
                'Add custom diagnosis',
                icon: I.plus,
                iconStroke: 2,
                gap: 6,
                height: 44,
                radius: 8,
                padding: EdgeInsets.zero,
                onTap: _addCustom,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result((String, String) r) {
    final on = _isSelected(r.$1);
    return D7Ruled(
      top: false,
      bottom: true,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.$1, style: tx(16, w: w600)),
                const SizedBox(height: 2),
                Text('ICD-10 ${r.$2}', style: tx(13, c: MP.ink3)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MpIconButton(
            on ? I.check : I.plus,
            label: on ? 'Remove ${r.$1}' : 'Add ${r.$1}',
            color: MP.primary,
            background: MP.primarySoft,
            iconSize: 20,
            stroke: 2,
            onTap: () => _toggle(r.$1, 'ICD-10 ${r.$2}'),
          ),
        ],
      ),
    );
  }

  Widget _selectedCard() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [const D7Title('Selected'), const SizedBox(width: 10), MpBadge.blue('${_selected.length}')],
            ),
          ),
          for (final s in _selected)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.$1, style: tx(16, w: w600)),
                        const SizedBox(height: 2),
                        Text(s.$2, style: tx(14, c: MP.ink2, h: 1.45)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  MpIconButton(
                    I.close,
                    label: 'Remove ${s.$1}',
                    color: MP.ink2,
                    iconSize: 20,
                    onTap: () => _toggle(s.$1, s.$2),
                  ),
                ],
              ),
            ),
          if (_selected.isEmpty)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Reuse a previous diagnosis or add one from the catalog.',
                style: tx(14, c: MP.ink2, h: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

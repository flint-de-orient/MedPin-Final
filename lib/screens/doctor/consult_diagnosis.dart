import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-Diagnosis.dc.html — "Consult 2 · Diagnosis".
/// Live: args {'consultationId'} → GET /api/consultations/:id (draft
/// diagnoses, previousDiagnoses); search GET /api/catalog/icd?q=; "Next"
/// saves the full list with PATCH /api/consultations/:id {diagnoses}.
class ConsultDiagnosisScreen extends StatefulWidget {
  const ConsultDiagnosisScreen({super.key});

  @override
  State<ConsultDiagnosisScreen> createState() => _ConsultDiagnosisScreenState();
}

class _ConsultDiagnosisScreenState extends State<ConsultDiagnosisScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  /// Previous diagnoses: label, note shown once reused (renderVals().previous).
  static const _samplePrevious = [
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

  late final _query = TextEditingController(text: isLive ? '' : 'hyper');

  /// Selected diagnoses (name, note) — the design starts with the two reused ones.
  final List<(String, String)> _selected = [_samplePrevious[0], _samplePrevious[1]];

  /// Live: API fields of each selected diagnosis by name (icdCode, source, reusedFrom).
  final _meta = <String, Map<String, dynamic>>{};

  /// Live previous diagnoses (label, note) and their API records.
  List<(String, String)> _livePrevious = const [];
  List<Map<String, dynamic>> _previousRows = const [];

  /// Live ICD search results (name, code).
  List<(String, String)> _icd = const [];
  Timer? _debounce;
  int _searchSeq = 0;
  final _busy = ValueNotifier(false);

  String? get _consultationId => (Nav.args<Map>(context) ?? const {})['consultationId'] as String?;

  @override
  Future<Object?> fetch() async {
    final id = _consultationId;
    if (id == null) throw const ApiException(400, 'NO_CONSULTATION', 'Start the consultation first');
    final r = (await Api.I.get('/api/consultations/$id') as Map).cast<String, dynamic>();
    final at = F.date(r['previousVisitAt']);
    final reused = at == null ? 'Reused from the last visit' : 'Reused from ${d7Date(at).substring(5)}';
    _previousRows = r.list('previousDiagnoses');
    _livePrevious = [for (final d in _previousRows) (d.str('name'), reused)];
    if (data == null) {
      _selected.clear();
      _meta.clear();
      for (final d in r.obj('consultation').list('diagnoses')) {
        final name = d.str('name');
        if (name.isEmpty || _isSelected(name)) continue;
        _selected.add((name, _noteFor(d)));
        _meta[name] = {'icdCode': d['icdCode'], 'source': d['source'], 'reusedFrom': d['reusedFrom']};
      }
    }
    return r;
  }

  static String _noteFor(Map<String, dynamic> d) {
    final from = F.date(d['reusedFrom']);
    return switch (d.str('source')) {
      'reused' => from == null ? 'Reused from the last visit' : 'Reused from ${d7Date(from).substring(5)}',
      'custom' => 'Custom diagnosis',
      'ai' => d.str('reason', 'Suggested by MedPin AI'),
      _ => d['icdCode'] == null ? 'From the catalog' : 'ICD-10 ${d['icdCode']}',
    };
  }

  List<(String, String)> get _previous => data == null ? _samplePrevious : _livePrevious;

  void _search(String _) {
    setState(() {});
    if (!isLive) return;
    _debounce?.cancel();
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() => _icd = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final seq = ++_searchSeq;
      try {
        final res = await Api.I.get('/api/catalog/icd', query: {'q': q}) as List? ?? const [];
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _icd = [
            for (final x in res)
              if (x is Map) ('${x['name'] ?? ''}', '${x['code'] ?? ''}'),
          ];
        });
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message);
      }
    });
  }

  Future<void> _next() async {
    if (!isLive) {
      Nav.go(context, 'Consult-Advice');
      return;
    }
    final id = _consultationId;
    final diagnoses = [
      for (final s in _selected)
        {
          'name': s.$1,
          if (_meta[s.$1]?['icdCode'] != null) 'icdCode': _meta[s.$1]!['icdCode'],
          'source': _meta[s.$1]?['source'] ?? 'catalog',
          if (_meta[s.$1]?['reusedFrom'] != null) 'reusedFrom': _meta[s.$1]!['reusedFrom'],
        },
    ];
    final ok = await runAction(context, () => Api.I.patch('/api/consultations/$id', {'diagnoses': diagnoses}), busy: _busy);
    if (ok == null || !mounted) return;
    Nav.go(context, 'Consult-Advice', args: {'consultationId': id});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _busy.dispose();
    super.dispose();
  }

  bool _isSelected(String name) => _selected.any((s) => s.$1 == name);

  void _toggle(String name, String note, [Map<String, dynamic>? meta]) {
    setState(() {
      final i = _selected.indexWhere((s) => s.$1 == name);
      if (i >= 0) {
        _selected.removeAt(i);
        _meta.remove(name);
      } else {
        _selected.add((name, note));
        if (meta != null) _meta[name] = meta;
      }
    });
  }

  void _togglePrevious(int i) {
    final p = _previous[i];
    if (data == null || i >= _previousRows.length) {
      _toggle(p.$1, p.$2);
      return;
    }
    final d = _previousRows[i];
    _toggle(p.$1, p.$2, {'icdCode': d['icdCode'], 'source': 'reused', 'reusedFrom': data!['previousVisitAt']});
  }

  List<(String, String)> get _results {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    if (data != null) return _icd;
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
      if (!_isSelected(name)) {
        _selected.add((name, 'Custom diagnosis'));
        _meta[name] = {'source': 'custom'};
      }
      _query.clear();
      _icd = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: const MpHeader('Consultation'),
      body: placeholder ?? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D7ConsultTop(step: 1, summary: data?.obj('summary')),
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
            Expanded(flex: 2, child: MpButton('Next: Advice', onTap: _next)),
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
          if (_previous.isEmpty)
            Text('No previous diagnoses for this patient yet', style: tx(14, c: MP.ink2))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _previous.length; i++)
                  D7Pill(_previous[i].$1, on: _isSelected(_previous[i].$1), check: true, onTap: () => _togglePrevious(i)),
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
            onChanged: _search,
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
                    onTap: () => setState(() {
                      _query.clear();
                      _icd = const [];
                    }),
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
            onTap: () => _toggle(r.$1, 'ICD-10 ${r.$2}', {'icdCode': r.$2, 'source': 'catalog'}),
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

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';
import 'signature_gate.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-Advice.dc.html — "Consult 3 · Advice".
/// Live: args {'consultationId'} → GET /api/consultations/:id (+ /checks for
/// catalog warnings, GET /api/doctor/profile for the signature block).
/// "Generate prescription": PATCH /api/consultations/:id {labOrders, advice,
/// followUp}, then POST /api/consultations/:id/issue → Prescriptions.
class ConsultAdviceScreen extends StatefulWidget {
  const ConsultAdviceScreen({super.key});

  @override
  State<ConsultAdviceScreen> createState() => _ConsultAdviceScreenState();
}

class _ConsultAdviceScreenState extends State<ConsultAdviceScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  /// Medicine, dosage line, catalog warning.
  static const List<(String, String, String?)> _sampleMeds = [
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

  static const _presetKeys = ['1_week', '2_weeks', '1_month', '3_months'];

  /// The design's "today" (Tue 29 Sep 2026); "1 month" → Thu, 29 Oct 2026.
  /// Live: the real date.
  DateTime get _today {
    if (!isLive) return DateTime(2026, 9, 29);
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Selected tests: name, panel index (-1: not from a category).
  final List<(String, int)> _tests = [('HbA1c', 0), ('Fasting glucose', 0), ('Post-prandial glucose', 0)];

  /// Live: panel caption of tests that are not in a category.
  final _testPanels = <String, String>{};
  int _preset = 2;
  DateTime _next = DateTime(2026, 10, 29);
  final _advice = TextEditingController(
    text: 'Walk 30 minutes daily. Avoid sweets and fried food. Come in at once if chest tightness returns.',
  );
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _advice.dispose();
    _busy.dispose();
    super.dispose();
  }

  String? get _consultationId => (Nav.args<Map>(context) ?? const {})['consultationId'] as String?;

  @override
  Future<Object?> fetch() async {
    final id = _consultationId;
    if (id == null) throw const ApiException(400, 'NO_CONSULTATION', 'Start the consultation first');
    final r = await Future.wait([
      Api.I.get('/api/consultations/$id'),
      Api.I.get('/api/consultations/$id/checks').catchError((_) => const []),
      Api.I.get('/api/doctor/profile').catchError((_) => null),
    ]);
    final c = (r[0] as Map).cast<String, dynamic>();
    final consult = c.obj('consultation');
    if (data == null) {
      _tests.clear();
      _testPanels.clear();
      for (final t in consult.list('labOrders')) {
        if (t['selected'] == false) continue;
        final name = t.str('testName');
        if (name.isEmpty || _tests.any((x) => x.$1 == name)) continue;
        final p = _panels.indexWhere((p) => p.$3.contains(name));
        _tests.add((name, p));
        if (p < 0) _testPanels[name] = t.str('panel', 'Lab test');
      }
      _advice.text = consult.obj('advice').str('freeText');
      final f = consult.obj('followUp');
      final date = f['enabled'] == true ? F.date(f['date']) : null;
      _preset = date == null ? 2 : _presetKeys.indexOf(f.str('preset'));
      _next = date == null ? _presetDate(2) : DateTime(date.year, date.month, date.day);
      if (_preset < 0) {
        for (var i = 0; i < _presets.length; i++) {
          if (DateUtils.isSameDay(_presetDate(i), _next)) _preset = i;
        }
      }
    }
    return {...c, 'checks': r[1], 'profile': r[2]};
  }

  static const _food = {
    'before_food': 'Before food',
    'after_food': 'After food',
    'with_food': 'With food',
    'empty_stomach': 'Empty stomach',
    'bedtime': 'At bedtime',
  };

  /// 'Metformin 500 mg', '1-0-1 · After food · 30 days', catalog / allergy warning.
  List<(String, String, String?)> get _meds {
    final d = data;
    if (d == null) return _sampleMeds;
    final checks = [for (final x in (d['checks'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final meds = d.obj('consultation').list('medications');
    return [
      for (var i = 0; i < meds.length; i++) _medLine(meds[i], i < checks.length ? checks[i] : const {}),
    ];
  }

  static (String, String, String?) _medLine(Map<String, dynamic> m, Map<String, dynamic> check) {
    final dose = m.obj('dose');
    String n(String k) => _num(dose[k] ?? 0);
    final pattern = switch (m.str('frequency')) {
      'weekly' => 'Once a week${m['weekday'] == null ? '' : ' · ${_weekday(m.str('weekday'))}'}',
      'as_needed' => 'When needed',
      _ => '${n('morning')}-${n('afternoon')}-${n('night')}',
    };
    final when = m.str('instructions').isNotEmpty ? _cap(m.str('instructions')) : _food[m.str('foodRelation')];
    final dur = m.obj('duration');
    final unit = dur.str('unit', 'days');
    final v = dur['value'];
    final duration =
        unit == 'ongoing'
            ? 'Ongoing'
            : v is num
            ? '${_num(v)} ${v == 1 ? unit.substring(0, unit.length - 1) : unit}'
            : null;
    final warnings = <String>{
      if (m.str('caution').isNotEmpty) m.str('caution'),
      for (final w in (check['warnings'] as List? ?? const []))
        if (w is Map && w['text'] != null) '${w['text']}',
    };
    return (
      [m.str('name'), m.str('strength')].where((s) => s.isNotEmpty).join(' '),
      [pattern, if (when != null) when, if (duration != null) duration].join(' · '),
      warnings.isEmpty ? null : warnings.join('\n'),
    );
  }

  static String _num(Object v) => v is num && v == v.roundToDouble() ? '${v.round()}' : '$v';
  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  static String _weekday(String k) {
    final i = d7Weekdays.indexOf(k);
    return i < 0 ? k : d7WeekdayNames[i];
  }

  String _testCaption((String, int) t) => t.$2 >= 0 ? _panels[t.$2].$2 : (_testPanels[t.$1] ?? 'Lab test');

  Future<void> _openMedicine(String stem, [int? index]) async {
    if (!isLive) {
      Nav.go(context, stem);
      return;
    }
    await Nav.go(context, stem, args: {'consultationId': _consultationId, if (index != null) 'medicationIndex': index});
    if (mounted) reload(quiet: true);
  }

  Future<void> _generate() async {
    if (!isLive) {
      toast(context, 'Prescription generated');
      Nav.go(context, 'Prescriptions');
      return;
    }
    final d = data;
    final id = _consultationId;
    if (d == null || id == null) return;
    final consult = d.obj('consultation');
    final res = await withSignature(context, busy: _busy, () async {
      await Api.I.patch('/api/consultations/$id', {
        'labOrders': [
          for (final t in _tests)
            {
              'testName': t.$1,
              'panel': t.$2 >= 0 ? _panels[t.$2].$2 : _testPanels[t.$1],
              'source': t.$2 >= 0 ? 'panel' : 'typed',
              'selected': true,
            },
        ],
        'advice': {'items': consult.obj('advice').list('items'), 'freeText': _advice.text.trim()},
        'followUp': {
          ...consult.obj('followUp'),
          'enabled': true,
          'preset': _preset >= 0 ? _presetKeys[_preset] : 'custom',
          'date': _next.toUtc().toIso8601String(),
        },
      });
      return (await Api.I.post('/api/consultations/$id/issue', const {}) as Map).cast<String, dynamic>();
    });
    if (res == null || !mounted) return;
    final rx = res.obj('prescription');
    toast(context, 'Prescription generated');
    Nav.go(context, 'Prescriptions', args: {'prescriptionId': rx.str('id'), 'patientId': rx.str('patientId')});
  }

  DateTime _presetDate(int i) => switch (i) {
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
    final placeholder = livePlaceholder();
    return MpPage(
      header: const MpHeader('Consultation'),
      body: placeholder ?? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D7ConsultTop(step: 2, summary: data?.obj('summary')),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            gap: 16,
            children: [
              _medicinesCard(),
              _labCard(),
              MpCard(
                child: VGap(
                  gap: 16,
                  children: [
                    const D7Title('General advice'),
                    D7Field(
                      controller: _advice,
                      lines: 4,
                      height: 128,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        child: MpButton('Generate prescription', onTap: _generate),
      ),
    );
  }

  Widget _medicinesCard() {
    final meds = _meds;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: D7Title('Medicines', sub: '${meds.length} added · checked against the brand catalog'),
          ),
          for (var i = 0; i < meds.length; i++)
            D7Ruled(
              bottom: i == meds.length - 1,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child:
                  meds[i].$3 == null
                      ? _medRow(meds[i], i)
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_medRow(meds[i], i), const SizedBox(height: 12), _warning(meds[i].$3!)],
                      ),
            ),
          const SizedBox(height: 16),
          MpButton.small('Add medicine', icon: I.plus, onTap: () => _openMedicine('Consult-Voice')),
        ],
      ),
    );
  }

  Widget _medRow((String, String, String?) m, int i) {
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
          onTap: () => _openMedicine('Consult-Dosage', i),
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
                              Text(_testCaption(t), style: tx(13, c: MP.ink3)),
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

  /// Live: name and 'MBBS, MD · WBMC 64213' from the doctor profile, and the
  /// uploaded signature image (null url = none yet).
  (String, String, String?)? get _signer {
    final d = data;
    if (d == null) return null;
    final p = d['profile'] is Map ? d.obj('profile') : const <String, dynamic>{};
    final sig = p['signature'] is Map ? p.obj('signature') : const <String, dynamic>{};
    return (
      p.str('displayName', Session.I.name),
      [p.str('degreesSummary'), p.str('registrationDisplay')].where((s) => s.isNotEmpty).join(' · '),
      sig['url'] is String ? sig.str('url') : null,
    );
  }

  Widget _signatureCard() {
    final signer = _signer;
    final signature =
        signer == null
            ? const Svg(_signature, width: 180, height: 56)
            : signer.$3 != null
            ? Image.network(signer.$3!, width: 180, height: 56, fit: BoxFit.contain, alignment: Alignment.centerLeft)
            : SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No signature yet · add it in your profile', style: tx(14, c: MP.ink2)),
              ),
            );
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
                    label: 'Signature of ${signer?.$1 ?? 'Dr. Arjun Sen'}',
                    image: true,
                    child: signature,
                  ),
                ),
                const SizedBox(height: 12),
                D7Ruled(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(signer?.$1 ?? 'Dr. Arjun Sen', style: tx(16, w: w700)),
                      const SizedBox(height: 2),
                      Text(signer?.$2 ?? 'MBBS, MD · WBMC 64213', style: tx(14, c: MP.ink2, h: 1.45)),
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

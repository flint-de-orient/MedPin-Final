import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d6.dart';
import 'signature_gate.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-Profile.dc.html — "Patient profile".
/// Live data: GET /api/patients/:id with /vitals, /lab-results,
/// /trends/HbA1c, /visits and the patient's alerts. "Save draft" starts (or
/// resumes) today's consultation and saves it; "Send prescription" also
/// issues it and sends it to the patient.
class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> with LiveData {
  static const _meds = [
    ('Metformin 500 mg', '1-0-1 · After food · 30 days'),
    ('Atorvastatin 10 mg', '0-0-1 · At night · 30 days'),
  ];

  static const _tests = ['HbA1c', 'Lipid profile', 'Fasting glucose', 'Kidney function', 'Urine routine', 'TSH'];

  /// Follow-up presets and their distance (days) from today, Thu 1 Oct 2026.
  static const _presets = [('1 week', 7), ('2 weeks', 14), ('1 month', 28), ('3 months', 91)];

  final Set<int> _picked = {0, 1};
  int? _preset = 2;
  final _date = TextEditingController(text: 'Thu, 29 Oct 2026');
  final _dx = TextEditingController();
  final _advice = TextEditingController();
  bool _dxFilled = false;
  String? _consultationId;
  String? _issuedRxId;
  final _busy = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    if (isLive) {
      _picked.clear();
      _date.text = _fmt(_today.add(Duration(days: _presets[_preset!].$2)));
    }
  }

  @override
  Future<Object?> fetch() async {
    final b = await d6Load(context, {
      'vitals': '/vitals',
      'labs': '/lab-results',
      'trend': '/trends/HbA1c',
      'visits': '/visits',
      'alerts': '/api/alerts?status=all&patientId={id}',
    });
    if (!_dxFilled) {
      _dxFilled = true;
      _dx.text = D6Rec(b).conditions.join('; ');
    }
    return b;
  }

  @override
  void dispose() {
    _date.dispose();
    _dx.dispose();
    _advice.dispose();
    _busy.dispose();
    super.dispose();
  }

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _fmt(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Reads "Thu, 29 Oct 2026" / "29 Oct 2026" / "2026-10-29" back.
  static DateTime? _parse(String s) {
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final iso = DateTime.tryParse(s.trim());
    if (iso != null) return iso;
    final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})').firstMatch(s);
    if (m == null) return null;
    final mo = months.indexOf(m.group(2)!.toLowerCase());
    if (mo < 0) return null;
    return DateTime(int.parse(m.group(3)!), mo + 1, int.parse(m.group(1)!));
  }

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _pickPreset(int i) {
    setState(() {
      _preset = i;
      _date.text = isLive ? _fmt(_today.add(Duration(days: _presets[i].$2))) : _fmt(DateTime.utc(2026, 10, 1 + _presets[i].$2));
    });
  }

  /// "1-0-1" → {morning: 1, afternoon: 0, night: 1}
  static Map<String, num> _dose(String pattern) {
    final p = [for (final x in pattern.split('-')) num.tryParse(x.trim()) ?? 0];
    return {'morning': p.isNotEmpty ? p[0] : 0, 'afternoon': p.length > 1 ? p[1] : 0, 'night': p.length > 2 ? p[2] : 0};
  }

  /// Starts (or resumes) today's consultation and saves the draft.
  Future<String> _saveDraft(D6Rec r) async {
    var id = _consultationId;
    if (id == null) {
      final visit = r.nextVisit;
      final at = F.date(visit['startAt']);
      final today = at != null && F.sameDay(at, DateTime.now()) && visit.str('id').isNotEmpty;
      final c = await Api.I.post('/api/consultations', {'patientId': r.id, if (today) 'appointmentId': visit.str('id')});
      id = '${(c as Map)['id'] ?? c['_id']}';
      _consultationId = id;
    }
    final follow = _parse(_date.text);
    final dx = [for (final d in _dx.text.split(RegExp(r'[;\n]'))) if (d.trim().isNotEmpty) d.trim()];
    await Api.I.patch('/api/consultations/$id', {
      'diagnoses': [for (final d in dx) {'name': d, 'source': 'custom'}],
      'labOrders': [for (final i in _picked) {'testName': _tests[i], 'source': 'typed', 'selected': true}],
      'advice': {'items': const [], 'freeText': _advice.text.trim()},
      'followUp': follow == null ? {'enabled': false} : {'enabled': true, 'date': _day(follow), 'remindPatient': true},
      'medications': [
        for (final m in r.medicines)
          if (_dose(m.str('pattern')).values.any((v) => v > 0) || m['frequency'] == 'weekly' || m['frequency'] == 'as_needed')
            {
              'name': m.str('name'),
              if (m.str('strength').isNotEmpty) 'strength': m.str('strength'),
              'dose': _dose(m.str('pattern')),
              'frequency': m.str('frequency', 'daily'),
              'change': 'continued',
              'entrySource': 'typed',
            },
      ],
    });
    return id;
  }

  Future<void> _draftAction(BuildContext context, D6Rec r, {required bool send}) async {
    final ok = await withSignature(context, () async {
      // Issued but not sent yet (e.g. the send failed): just send it again.
      if (send && _issuedRxId != null) {
        await Api.I.post('/api/prescriptions/$_issuedRxId/send');
        _issuedRxId = null;
        return true;
      }
      final id = await _saveDraft(r);
      if (!send) return true;
      final issued = await Api.I.post('/api/consultations/$id/issue');
      final rx = (issued as Map)['prescription'] as Map?;
      // The draft is now a prescription; a retry must not edit it again.
      _consultationId = null;
      _issuedRxId = '${rx?['id'] ?? rx?['_id']}';
      await Api.I.post('/api/prescriptions/$_issuedRxId/send');
      _issuedRxId = null;
      return true;
    }, busy: _busy);
    if (ok != true || !context.mounted) return;
    toast(context, send ? 'Prescription sent to ${r.first}' : 'Draft saved');
    reload(quiet: true);
  }

  void _toggleTest(int i) {
    setState(() {
      if (!_picked.remove(i)) _picked.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rec = data == null ? null : D6Rec(data!);
    final placeholder = livePlaceholder();
    return D6Scope(
      rec: rec,
      onChanged: () => reload(quiet: true),
      child: Builder(
        builder: (context) => MpPage(
          header: MpHeader(
            'Patient profile',
            actions: [
              MpIconButton(I.moreVSmall, label: 'More options', filled: true, onTap: rec == null ? null : () => d6MoreOptions(context)),
            ],
          ),
          body: placeholder ?? VGap(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            gap: 16,
            children: [
              const D6ProfileHero(consult: true),
              if (D6ConsentNote.shown(context)) const D6ConsentNote(),
              const D6RecordCaption(),
              const D6OverviewCard(),
              if (D6MeasurementsCard.shown(context)) const D6MeasurementsCard(),
              if (rec == null || _Nutrition.dietician(rec) != null) const _Nutrition(),
              if (rec == null || _Hba1cHistory.points(rec).isNotEmpty) const _Hba1cHistory(),
              if (rec == null || _TestReports.rows(rec).isNotEmpty) const _TestReports(),
              if (rec == null || _Ecg.ecg(rec) != null) const _Ecg(),
              if (rec == null || _RecentAlerts.alerts(rec).isNotEmpty) const _RecentAlerts(),
              if (rec == null || _PastConsultations.visits(rec).isNotEmpty) const _PastConsultations(),
              if (rec == null || _AiContext.note(rec) != null) const _AiContext(),
              Padding(padding: const EdgeInsets.only(top: 8), child: _prescription(context, rec)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prescription(BuildContext context, D6Rec? rec) {
    final meds = rec == null
        ? _meds
        : [
            for (final m in rec.medicines)
              (
                '${m.str('name')} ${m.str('strength')}'.trim(),
                [
                  m.str('pattern'),
                  m.str('frequency').replaceAll('_', ' '),
                  if (F.date(m['endDate']) != null) 'until ${F.dayMonth(F.date(m['endDate'])!)}',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
          ];
    return MpCard(
      child: VGap(
        gap: 24,
        children: [
          D6Title("Today's prescription", sub: rec == null ? 'Draft · Dr. Arjun Sen' : 'Draft · ${Session.I.name}'),

          // Current medications
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Expanded(child: D6Caps('Current medications', weight: w600, h: 1.35)),
                    D6Link(
                      'Add medicine',
                      leading: I.plus,
                      minHeight: 44,
                      onTap: () => d6Go(context, 'Consult-Voice', {if (_consultationId != null) 'consultationId': _consultationId}),
                    ),
                  ],
                ),
              ),
              if (meds.isEmpty) Text('No current medicines', style: tx(14, c: MP.ink2)),
              for (final m in meds)
                D6Row(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$1, style: tx(16, w: w600)),
                            const Gap(2),
                            Text(m.$2, style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
                          ],
                        ),
                      ),
                      const Gap(12),
                      MpIconButton(
                        I.edit,
                        label: 'Edit ${m.$1}',
                        iconSize: 18,
                        color: MP.primary,
                        background: MP.primarySoft,
                        onTap: () => d6Go(context, 'Consult-Dosage', {if (_consultationId != null) 'consultationId': _consultationId}),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Lab tests
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: D6Caps('Lab tests', weight: w600, h: 1.35)),
                  Text('${_picked.length} selected', style: tx(13, c: MP.ink3)),
                ],
              ),
              const Gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _tests.length; i++)
                    _TestChip(_tests[i], on: _picked.contains(i), onTap: () => _toggleTest(i)),
                ],
              ),
            ],
          ),

          // Diagnosis and advice
          if (rec == null)
            const VGap(
              gap: 16,
              children: [
                MpInput(label: 'Diagnosis', value: 'Type 2 diabetes mellitus; PCOS'),
                MpInput(
                  label: 'Advice',
                  value:
                      'Walk 30 minutes daily. Avoid sweets and fried food. Come in at once if chest tightness returns.',
                  maxLines: 3,
                  height: 104,
                ),
              ],
            )
          else
            VGap(
              gap: 16,
              children: [
                MpInput(label: 'Diagnosis', controller: _dx),
                MpInput(label: 'Advice', controller: _advice, maxLines: 3, height: 104),
              ],
            ),

          // Follow-up
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D6Caps('Follow-up', weight: w600, h: 1.35),
              const Gap(12),
              Row(
                children: [
                  for (var i = 0; i < _presets.length; i++) ...[
                    if (i > 0) const Gap(8),
                    Expanded(child: _PresetChip(_presets[i].$1, on: _preset == i, onTap: () => _pickPreset(i))),
                  ],
                ],
              ),
              const Gap(12),
              _DateField(
                controller: _date,
                onChanged: (_) {
                  if (_preset != null) setState(() => _preset = null);
                },
              ),
            ],
          ),

          // Actions
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  'Save draft',
                  secondary: true,
                  onTap: rec == null ? () => toast(context, 'Draft saved') : () => _draftAction(context, rec, send: false),
                ),
              ),
              const Gap(12),
              Expanded(
                child: _ActionButton(
                  'Send prescription',
                  onTap: rec == null ? () => toast(context, 'Prescription sent to Priya') : () => _draftAction(context, rec, send: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Clinical record cards
// ─────────────────────────────────────────────────────────────────────────────

class _Nutrition extends StatelessWidget {
  const _Nutrition();

  static Map<String, dynamic>? dietician(D6Rec r) {
    for (final c in r.careTeam) {
      if (c['role'] == 'dietician' && c.str('name').isNotEmpty) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final d = r == null ? null : dietician(r);
    final name = d?.str('name') ?? 'Mou Banerjee';
    final where = r == null ? 'City Care Clinic' : D6Rec.practiceName;
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Text('Nutrition', style: tx(20, w: w700, h: 1.25)),
          Row(
            children: [
              MpAvatar(r == null ? 'MB' : F.initials(name), size: 40, fontSize: 14),
              const Gap(12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Covered by $name', style: tx(16, w: w600)),
                    const Gap(2),
                    Text(where.isEmpty ? 'Dietician' : 'Dietician, $where', style: tx(14, c: MP.ink2, h: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Hba1cHistory extends StatelessWidget {
  const _Hba1cHistory();

  static const _chart =
      r'''<svg xmlns="http://www.w3.org/2000/svg" width="310" height="150" viewBox="0 0 310 150" font-family="Figtree">
<rect x="24" y="84" width="286" height="36" fill="#E7F5EE"/>
<path d="M24 12H310M24 48H310M24 120H310" stroke="#E5E9F0" stroke-width="1"/>
<path d="M24 84H310" stroke="#076B3C" stroke-width="1.5" stroke-dasharray="4 4"/>
<text x="0" y="16" font-size="12" fill="#69738A">9</text>
<text x="0" y="52" font-size="12" fill="#69738A">8</text>
<text x="0" y="88" font-size="12" fill="#69738A">7</text>
<text x="0" y="124" font-size="12" fill="#69738A">6</text>
<text x="30" y="112" font-size="12" font-weight="600" fill="#076B3C">Target 7.0</text>
<polyline points="44,51.6 99.8,33.6 174.3,91.2 286,76.8" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
<circle cx="44" cy="51.6" r="4" fill="#FFFFFF" stroke="#003399" stroke-width="2"/>
<circle cx="99.8" cy="33.6" r="4" fill="#FFFFFF" stroke="#003399" stroke-width="2"/>
<circle cx="174.3" cy="91.2" r="4" fill="#FFFFFF" stroke="#003399" stroke-width="2"/>
<circle cx="286" cy="76.8" r="4.5" fill="#003399"/>
<text x="44" y="41" font-size="12" font-weight="600" fill="#111827" text-anchor="middle">7.9</text>
<text x="99.8" y="23" font-size="12" font-weight="600" fill="#111827" text-anchor="middle">8.4</text>
<text x="174.3" y="80" font-size="12" font-weight="600" fill="#111827" text-anchor="middle">6.8</text>
<text x="286" y="66" font-size="12" font-weight="700" fill="#111827" text-anchor="middle">7.2</text>
<text x="44" y="142" font-size="12" fill="#69738A" text-anchor="middle">Jun ’25</text>
<text x="99.8" y="142" font-size="12" fill="#69738A" text-anchor="middle">Sep ’25</text>
<text x="174.3" y="142" font-size="12" fill="#69738A" text-anchor="middle">Jan ’26</text>
<text x="286" y="142" font-size="12" fill="#69738A" text-anchor="middle">Jul ’26</text>
</svg>''';

  /// The last 6 HbA1c values, oldest first.
  static List<(DateTime, num)> points(D6Rec r) {
    final t = r.m['trend'];
    final pts = [
      for (final x in (t is List ? t : const []))
        if ((x as Map)['value'] is num && F.date(x['at']) != null) (F.date(x['at'])!, x['value'] as num),
    ];
    return pts.length > 6 ? pts.sublist(pts.length - 6) : pts;
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    if (r == null) return _card('Latest 7.2% · target below 7.0%', true, _chart, 'HbA1c: Jun 2025 7.9%, Sep 2025 8.4%, Jan 2026 6.8%, Jul 2026 7.2%. Target 7.0%.');
    final pts = points(r);
    final target = r.detail.obj('targets').numOr('hba1c', 7);
    final last = pts.last.$2;
    return _card(
      'Latest ${d6Num(last)}% · target below ${target.toStringAsFixed(1)}%',
      last >= target,
      d6HistorySvg(pts, target: target),
      'HbA1c: ${pts.map((p) => '${d6MonthYear(p.$1)} ${d6Num(p.$2)}%').join(', ')}. Target ${target.toStringAsFixed(1)}%.',
    );
  }

  Widget _card(String sub, bool above, String svg, String label) {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: D6Title('HbA1c history', sub: sub)),
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: above
                    ? const D6Pill('Above target', bg: MP.amberSoft, fg: MP.amber)
                    : const D6Pill('On target', bg: MP.greenSoft, fg: MP.green),
              ),
            ],
          ),
          Semantics(
            label: label,
            image: true,
            child: D6Chart(svg, width: 310, height: 150),
          ),
        ],
      ),
    );
  }
}

class _TestReports extends StatelessWidget {
  const _TestReports();

  static const _ldl = r'''<svg xmlns="http://www.w3.org/2000/svg" width="72" height="32" viewBox="0 0 72 32">
<polyline points="4,23.2 26,16.6 48,13 68,8.8" fill="none" stroke="#003399" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="68" cy="8.8" r="3" fill="#B45309"/>
</svg>''';

  static const _tsh = r'''<svg xmlns="http://www.w3.org/2000/svg" width="72" height="32" viewBox="0 0 72 32">
<polyline points="4,18 26,14 48,17 68,16" fill="none" stroke="#003399" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="68" cy="16" r="3" fill="#076B3C"/>
</svg>''';

  static const _rows = [
    (
      'Lipid profile',
      'High',
      MP.amberSoft,
      MP.amber,
      'LDL 162 mg/dL · 12 Mar 2026',
      _ldl,
      'LDL rising over the last four reports',
    ),
    (
      'Thyroid profile',
      'Normal',
      MP.greenSoft,
      MP.green,
      'TSH 2.4 mIU/L · 12 Mar 2026',
      _tsh,
      'TSH steady over the last four reports',
    ),
  ];

  /// The 3 most recent tests (one row per test name) with a sparkline of
  /// their key value — the first abnormal one, else the first — over time.
  static List<(String, String, Color, Color, String, String, String)> rows(D6Rec r) {
    final labs = r.m.obj('labs').list('items').where((l) => l.str('ecgInterpretation').isEmpty).toList();
    final byTest = <String, List<Map<String, dynamic>>>{};
    for (final l in labs) {
      byTest.putIfAbsent(l.str('testName'), () => []).add(l);
    }
    final out = <(String, String, Color, Color, String, String, String)>[];
    for (final e in byTest.entries.take(3)) {
      final latest = e.value.first;
      final values = latest.list('values');
      if (values.isEmpty) continue;
      final key = values.firstWhere((v) => v['flag'] != null && v['flag'] != 'normal', orElse: () => values.first);
      final analyte = key.str('analyte');
      final flag = key.str('flag', 'normal');
      final ok = flag == 'normal';
      final at = F.date(latest['collectedAt']);
      final unit = key.str('unit');
      final value = key['value'] != null ? d6Num(key['value']) : key.str('valueText');
      final history = [
        for (final l in e.value.reversed)
          for (final v in l.list('values'))
            if (v['analyte'] == analyte && v['value'] is num) v['value'] as num,
      ];
      final trend = history.length < 2
          ? 'one report so far'
          : history.last > history.first
              ? 'rising over the last ${history.length} reports'
              : history.last < history.first
                  ? 'falling over the last ${history.length} reports'
                  : 'steady over the last ${history.length} reports';
      out.add((
        e.key,
        ok ? 'Normal' : d6Cap(flag),
        ok ? MP.greenSoft : MP.amberSoft,
        ok ? MP.green : MP.amber,
        [
          '$analyte ${unit == '%' ? '$value%' : [value, unit].where((s) => s.isNotEmpty).join(' ')}',
          if (at != null) d6Date(at),
        ].join(' · '),
        d6Sparkline(history.isEmpty ? [0] : history, flagged: !ok),
        '$analyte $trend',
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rec = D6Scope.recOf(context);
    final rows = rec == null ? _rows : _TestReports.rows(rec);
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: D6TitleLink('Test reports', action: 'View all', onTap: () => d6Go(context, 'PP-Tests')),
          ),
          for (final r in rows)
            D6Row(
              onTap: () => d6Go(context, 'PP-Tests'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(r.$1, style: tx(16, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            const Gap(8),
                            D6Pill(r.$2, bg: r.$3, fg: r.$4, height: 22, padH: 8, weight: w600),
                          ],
                        ),
                        const Gap(2),
                        Text(
                          r.$5,
                          style: tx(14, c: MP.ink2, h: 1.45, tab: true),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  Semantics(label: r.$7, image: true, child: Svg(r.$6, width: 72, height: 32)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Ecg extends StatelessWidget {
  const _Ecg();

  /// The newest ECG result.
  static Map<String, dynamic>? ecg(D6Rec r) {
    for (final l in r.m.obj('labs').list('items')) {
      if (l.str('ecgInterpretation').isNotEmpty) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final e = r == null ? null : ecg(r);
    final at = F.date(e?['collectedAt']);
    final normal = e == null || e.numOr('abnormalCount') == 0;
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          D6TitleLink('ECG', action: 'View tracing', onTap: () => d6Go(context, 'PP-Tests')),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e == null ? 'Normal sinus rhythm' : e.str('ecgInterpretation'), style: tx(16, w: w600)),
                    const Gap(2),
                    Text(
                      e == null
                          ? '12 Aug 2026 · 12-lead'
                          : [if (at != null) d6Date(at), e.str('ecgNote', e.str('testName'))].where((s) => s.isNotEmpty).join(' · '),
                      style: tx(14, c: MP.ink2, h: 1.45),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              normal
                  ? const D6Pill('Normal', bg: MP.greenSoft, fg: MP.green)
                  : const D6Pill('Abnormal', bg: MP.amberSoft, fg: MP.amber),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentAlerts extends StatelessWidget {
  const _RecentAlerts();

  /// The patient's two most pressing alerts (the API sorts by severity).
  static List<Map<String, dynamic>> alerts(D6Rec r) => r.m.obj('alerts').list('items').take(2).toList();

  static const _sample = {
    'severity': 'emergency',
    'when': 'Today, 9:12 AM · Open',
    'detail': 'Emergency message: chest tightness and sweating since morning',
  };

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final rows = r == null
        ? [_sample]
        : [
            for (final a in alerts(r))
              {
                ...a,
                'when': [
                  if (F.date(a['createdAt']) != null) d6Cap(d6When(F.date(a['createdAt'])!)),
                  d6Cap(a.str('status')),
                ].join(' · '),
              },
          ];
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: D6TitleLink('Recent alerts', action: 'View all', onTap: () => d6Go(context, 'Alerts')),
          ),
          for (var i = 0; i < rows.length; i++)
            D6Row(
              padding: i == rows.length - 1 ? const EdgeInsets.only(top: 14) : const EdgeInsets.symmetric(vertical: 14),
              onTap: () {
                final a = rows[i];
                if (r == null) {
                  Nav.go(context, 'Patient-Thread');
                } else if (a['conversationId'] != null) {
                  Nav.go(context, 'Patient-Thread', args: {'conversationId': '${a['conversationId']}', 'patientId': r.id});
                } else {
                  Nav.go(context, 'Alerts', args: {'alertId': '${a['id']}', 'patientId': r.id});
                }
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            switch (rows[i]['severity']) {
                              'emergency' => const D6Pill('Emergency', bg: MP.redSoft, fg: MP.red),
                              'urgent' => const D6Pill('Urgent', bg: MP.amberSoft, fg: MP.amber),
                              _ => const D6Pill('Watch'),
                            },
                            const Gap(8),
                            Flexible(
                              child: Text(
                                '${rows[i]['when']}',
                                style: tx(13, c: MP.ink3, tab: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const Gap(6),
                        Text(
                          '${rows[i]['detail'] ?? ''}',
                          style: tx(14, c: MP.ink2, h: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PastConsultations extends StatelessWidget {
  const _PastConsultations();

  static const _visits = [
    ('12 Mar 2026', 'Type 2 diabetes, dyslipidaemia · Dr. Arjun Sen'),
    ('12 Jan 2026', 'Type 2 diabetes, PCOS review · Dr. Arjun Sen'),
    ('18 Sep 2025', 'Type 2 diabetes, HbA1c 8.4% · Dr. Arjun Sen'),
  ];

  static List<Map<String, dynamic>> visits(D6Rec r) {
    final v = r.m['visits'];
    return [for (final x in (v is List ? v : const []).take(3)) (x as Map).cast<String, dynamic>()];
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final live = r == null ? const <Map<String, dynamic>>[] : visits(r);
    final rows = r == null
        ? _visits
        : [
            for (final v in live)
              (
                F.date(v['startedAt']) == null ? '' : d6Date(F.date(v['startedAt'])!),
                [
                  [for (final d in v.list('diagnoses')) d.str('name')].where((s) => s.isNotEmpty).join(', '),
                  r.personName(v['doctorId']) ?? '',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
          ];
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: D6TitleLink('Past consultations', action: 'View all', onTap: () => d6Go(context, 'Prescriptions')),
          ),
          for (var i = 0; i < rows.length; i++)
            D6Row(
              onTap: () => r == null
                  ? Nav.go(context, 'Prescriptions')
                  : d6Go(context, 'Prescriptions', {
                      'consultationId': live[i].str('id'),
                      if (live[i]['prescriptionId'] != null) 'prescriptionId': '${live[i]['prescriptionId']}',
                    }),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].$1, style: tx(16, w: w600, tab: true)),
                        const Gap(2),
                        Text(rows[i].$2, style: tx(14, c: MP.ink2, h: 1.45), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AiContext extends StatelessWidget {
  const _AiContext();

  /// The AI brief's "asked about" note, split into lead-in and topics.
  static (String, String)? note(D6Rec r) {
    final n = r.detail.obj('aiSummary').str('contextNote').trim();
    if (n.isEmpty) return null;
    final i = n.indexOf(':');
    if (i > 0 && i < n.length - 1) return ('${n.substring(0, i + 1)} ', n.substring(i + 1).trim());
    return ('This week ${r.first} asked about: ', n);
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final n = r == null ? ('This week Priya asked about: ', 'missed doses, chest tightness') : note(r)!;
    return MpCard(
      child: VGap(
        gap: 12,
        children: [
          Row(
            children: [
              const Ico(I.sparkle, size: 20, color: MP.primary),
              const Gap(8),
              Expanded(child: Text('AI assistant context', style: tx(20, w: w700, h: 1.25))),
            ],
          ),
          Text.rich(
            TextSpan(
              style: tx(16, h: 1.5),
              children: [
                TextSpan(text: n.$1),
                TextSpan(text: n.$2, style: tx(16, w: w600, h: 1.5)),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: D6Link(
              'Open chat review',
              size: 15,
              icon: I.chevronRight,
              minHeight: 44,
              onTap: () => d6Go(context, 'Chat-Review'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prescribing controls
// ─────────────────────────────────────────────────────────────────────────────

/// Lab test toggle: 40px border-box pill (padding 0 16, 1px border), check
/// icon when selected.
class _TestChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _TestChip(this.label, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = on ? MP.white : MP.ink2;
    return Semantics(
      button: true,
      toggled: on,
      child: SizedBox(
        height: 40,
        child: Tap(
          onTap: onTap,
          radius: 999,
          color: on ? MP.primary : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[Ico(I.check, size: 16, color: fg, stroke: 2.25), const Gap(6)],
              Text(label, style: tx(14, w: w600, c: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Follow-up preset: equal-width 40px border-box pill (padding 0).
class _PresetChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _PresetChip(this.label, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: SizedBox(
        height: 40,
        child: Tap(
          onTap: onTap,
          radius: 999,
          color: on ? MP.primary : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: tx(14, w: w600, c: on ? MP.white : MP.ink2), maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Follow-up date input: 56px, calendar icon at 16px, text at 48px.
class _DateField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _DateField({required this.controller, required this.onChanged});

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Semantics(
      label: 'Follow-up date',
      textField: true,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? MP.primary : MP.lineStrong),
          boxShadow: focused ? MPShadow.focusRing : null,
        ),
        child: Row(
          children: [
            // Positions are measured from the outer edge; the 1px border is inside.
            const Gap(15),
            const Ico(I.calendar, size: 20, color: MP.ink2),
            const Gap(13),
            Expanded(
              child: MpFieldArea(child: TextField(
                textAlignVertical: TextAlignVertical.center,
                controller: widget.controller,
                focusNode: _focus,
                onChanged: widget.onChanged,
                keyboardType: TextInputType.datetime,
                style: tx(16, tab: true),
                cursorColor: MP.primary,
                decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
              )),
            ),
            const Gap(16),
          ],
        ),
      ),
    );
  }
}

/// 56px action button whose label may wrap to two lines on narrow phones
/// (CSS buttons wrap; padding is the UA default 6px).
class _ActionButton extends StatelessWidget {
  final String label;
  final bool secondary;
  final VoidCallback onTap;
  const _ActionButton(this.label, {this.secondary = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Tap(
        onTap: onTap,
        radius: 16,
        color: secondary ? MP.white : MP.primarySoft,
        border: secondary ? MP.lineStrong : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: tx(16, w: w600, c: secondary ? MP.ink : MP.primary),
            ),
          ),
        ),
      ),
    );
  }
}

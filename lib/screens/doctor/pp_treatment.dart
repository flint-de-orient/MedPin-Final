import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d6.dart';

/// Design: PP-Treatment.dc.html — "Patient profile · Treatment plan".
/// Live data: GET /api/patients/:id (plan, medicines) and /adherence; Edit
/// saves the plan with PUT /api/patients/:id/treatment-plan.
class PpTreatmentScreen extends StatefulWidget {
  const PpTreatmentScreen({super.key});

  @override
  State<PpTreatmentScreen> createState() => _PpTreatmentScreenState();
}

/// Plan sections in the design's order: category, label, label colour.
const _sections = [
  ('diet', 'Diet', MP.ink3),
  ('activity', 'Activity', MP.ink3),
  ('monitoring', 'Monitoring', MP.ink3),
  ('before_next_visit', 'Before next visit', MP.ink3),
  ('come_in_immediately', 'Come in immediately if', MP.red),
  ('general', 'Other advice', MP.ink3),
];

/// "Thu, 29 Oct"
String _dayDate(DateTime d) {
  final s = F.dateLong(d);
  return s.substring(0, s.lastIndexOf(' '));
}

class _PpTreatmentScreenState extends State<PpTreatmentScreen> with LiveData {
  @override
  Future<Object?> fetch() => d6Load(context, {'adh': '/adherence'});

  String get _me => '${Session.I.user['id']}';

  Map<String, dynamic> _plan(D6Rec r) => r.detail.obj('treatmentPlan');

  List<(String, String, Color)> _advice(D6Rec r) => [
        for (final s in _sections)
          for (final sec in _plan(r).list('sections'))
            if (sec['category'] == s.$1 && (sec['items'] as List? ?? const []).isNotEmpty)
              (s.$2, (sec['items'] as List).join('\n'), s.$3),
      ];

  Future<void> _editPlan(BuildContext context, D6Rec r) async {
    final current = {for (final sec in _plan(r).list('sections')) sec.str('category'): (sec['items'] as List? ?? const []).join('\n')};
    final edit = [for (final s in _sections) TextEditingController(text: current[s.$1] ?? '')];
    final save = await openSheet<bool>(
      context,
      (sc) => MpSheet(
        title: 'Treatment plan',
        subtitle: 'One instruction per line',
        child: VGap(
          gap: 16,
          children: [
            for (var i = 0; i < _sections.length; i++)
              MpInput(label: _sections[i].$2, controller: edit[i], maxLines: 3, height: 104),
            MpButton('Save plan', onTap: () => Navigator.pop(sc, true)),
          ],
        ),
      ),
    );
    final sections = [
      for (var i = 0; i < _sections.length; i++)
        if (edit[i].text.trim().isNotEmpty)
          {
            'category': _sections[i].$1,
            'items': [for (final l in edit[i].text.split('\n')) if (l.trim().isNotEmpty) l.trim()],
          },
    ];
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in edit) {
        c.dispose();
      }
    });
    if (save != true || !context.mounted) return;
    final res = await runAction(context, () => Api.I.put('/api/patients/${r.id}/treatment-plan', {'sections': sections}));
    if (res == null || !context.mounted) return;
    toast(context, 'Treatment plan saved');
    reload(quiet: true);
  }

  Widget _medRow(Map<String, dynamic> m, Map<String, dynamic>? a) {
    final since = F.date(m['since']);
    final end = F.date(m['endDate']);
    final freq = m.str('frequency').replaceAll('_', ' ');
    final start = since == null ? '' : (F.sameDay(since, DateTime.now()) ? 'Started today' : 'Since ${d6Date(since)}');
    final until = end == null ? 'ongoing' : 'until ${d6Date(end)}';
    final (String taken, Color color, double size) = a == null || a['tracked'] == false
        ? ('Not tracked', MP.ink3, 13.0)
        : a['isNew'] == true
            ? ('New', MP.ink3, 14.0)
            : (
                '${a.numOr('pct').round()}%',
                a.numOr('pct') >= 90 ? MP.green : a.numOr('pct') >= 60 ? MP.amber : MP.red,
                16.0,
              );
    return D6Row(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${m.str('name')} ${m.str('strength')}'.trim(), style: tx(16, w: w600)),
                const Gap(3),
                Text([m.str('pattern'), freq].where((s) => s.isNotEmpty).join(' · '), style: tx(14, tab: true)),
                const Gap(3),
                Text([start, until].where((s) => s.isNotEmpty).join(' · '), style: tx(13, c: MP.ink3)),
              ],
            ),
          ),
          const Gap(12),
          Text(taken, textAlign: TextAlign.right, style: tx(size, w: w700, c: color, tab: true)),
        ],
      ),
    );
  }

  List<Widget> _liveBody(BuildContext context, D6Rec r) {
    final plan = _plan(r);
    final owner = plan.isEmpty ? Session.I.name : (r.personName(plan['doctorId']) ?? Session.I.name);
    final mine = plan.isEmpty || '${plan['doctorId']}' == _me;
    final updated = F.date(plan['updatedAt']);
    final next = F.date(plan['nextVisitAt']) ?? F.date(r.nextVisit['startAt']);
    final sub = [if (updated != null) 'Updated ${d6Date(updated)}', if (next != null) 'Next visit ${_dayDate(next)}'].join(' · ');
    final adh = r.m.obj('adh');
    final perMed = {for (final a in adh.list('perMedicine')) '${a['courseId']}': a};
    final meds = [for (final m in r.medicines) if ('${m['doctorId']}' == _me) m];
    final others = <String, List<Map<String, dynamic>>>{};
    for (final m in r.medicines) {
      if ('${m['doctorId']}' == _me) continue;
      others.putIfAbsent(m.str('prescriber', 'Another doctor'), () => []).add(m);
    }
    final advice = _advice(r);
    return [
      // Plan owner
      MpCard(
        radius: 20,
        shadow: MPShadow.float,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  D6Caps(mine ? 'Your plan' : 'Plan'),
                  const Gap(4),
                  Text(owner, style: tx(20, w: w700, h: 1.25)),
                  const Gap(4),
                  Text(sub.isEmpty ? 'No plan saved yet' : sub, style: tx(14, c: MP.ink2)),
                ],
              ),
            ),
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: D6Link('Edit', onTap: () => _editPlan(context, r)),
            ),
          ],
        ),
      ),

      _Adherence(adh: adh, rec: r),

      // Current medications
      MpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('Current medications', style: tx(20, w: w700, h: 1.25))),
                  const Gap(12),
                  const D6Caps('Taken'),
                ],
              ),
            ),
            if (meds.isEmpty) Text('No medicines from you yet', style: tx(14, c: MP.ink2)),
            for (final m in meds) _medRow(m, perMed[m.str('id')]),
          ],
        ),
      ),

      // Instructions & advice
      MpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Instructions & advice', style: tx(20, w: w700, h: 1.25)),
            ),
            if (advice.isEmpty) Text('No instructions yet', style: tx(14, c: MP.ink2)),
            for (final a in advice)
              D6Row(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [D6Caps(a.$1, color: a.$3), const Gap(4), Text(a.$2, style: tx(15, h: 1.5))],
                ),
              ),
          ],
        ),
      ),

      // From other doctors
      if (others.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From other doctors', style: tx(20, w: w700, h: 1.25)),
              const Gap(4),
              Row(
                children: [
                  const Ico(I.lock, size: 16, color: MP.ink2),
                  const Gap(6),
                  Expanded(child: Text('Shared by ${r.first} · read only', style: tx(14, c: MP.ink2))),
                ],
              ),
            ],
          ),
        ),
        for (final e in others.entries)
          MpCard(
            child: VGap(
              gap: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key, style: tx(16, w: w700)),
                    if (F.date(e.value.first['since']) != null) ...[
                      const Gap(2),
                      Text('Since ${d6Date(F.date(e.value.first['since'])!)}', style: tx(14, c: MP.ink2)),
                    ],
                  ],
                ),
                for (final m in e.value)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${m.str('name')} ${m.str('strength')}'.trim(), style: tx(15, w: w600)),
                              const Gap(2),
                              Text(
                                [m.str('pattern'), m.str('frequency').replaceAll('_', ' ')].where((s) => s.isNotEmpty).join(' · '),
                                style: tx(13, c: MP.ink2),
                              ),
                            ],
                          ),
                        ),
                        const Gap(12),
                        () {
                          final a = perMed[m.str('id')];
                          if (a == null || a['tracked'] == false) {
                            return Text('Not tracked', textAlign: TextAlign.right, style: tx(13, w: w700, c: MP.ink3));
                          }
                          final pct = a.numOr('pct');
                          return Text(
                            a['isNew'] == true ? 'New' : '${pct.round()}%',
                            textAlign: TextAlign.right,
                            style: tx(16, w: w700, c: a['isNew'] == true ? MP.ink3 : pct >= 90 ? MP.green : pct >= 60 ? MP.amber : MP.red),
                          );
                        }(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rec = data == null ? null : D6Rec(data!);
    if (rec != null) {
      return D6PatientTabsPage(tab: 3, rec: rec, onChanged: () => reload(quiet: true), children: _liveBody(context, rec));
    }
    return _PpTreatmentDesign(placeholder: livePlaceholder());
  }
}

/// The design's sample treatment plan (preview), also the frame while loading.
class _PpTreatmentDesign extends StatelessWidget {
  final Widget? placeholder;
  const _PpTreatmentDesign({this.placeholder});

  /// name, dose, since, adherence, colour, font size.
  static const _meds = [
    ('Metformin 500 mg', '1-0-1 · after food', 'Since Jun 2025 · ongoing', '78%', MP.amber, 16.0),
    ('Glimepiride 2 mg', '1-0-0 · before breakfast', 'Started today · 30 days', 'New', MP.ink3, 14.0),
    ('Vitamin D3 60,000 IU', 'Once a week · Sunday', 'Since 20 Jul 2026 · 8 weeks', '100%', MP.green, 16.0),
  ];

  /// label, text, label colour.
  static const _advice = [
    (
      'Diet',
      'Cut refined carbs. Three meals and two small snacks a day. Food logs reviewed by Mou Banerjee, dietician.',
      MP.ink3,
    ),
    ('Activity', 'Brisk walk for 30 minutes, 5 days a week.', MP.ink3),
    ('Monitoring', 'Check fasting sugar 3 times a week and log it in the app.', MP.ink3),
    ('Before next visit', 'HbA1c, fasting and post-meal glucose.', MP.ink3),
    ('Come in immediately if', 'Chest pain, breathlessness, or sugar below 70 mg/dL.', MP.red),
  ];

  /// doctor, where, medicine, dose, adherence, colour, font size, advice.
  static const _others = [
    (
      'Dr. Rina Mitra',
      'Cardiology · City Care · 02 Feb 2026',
      'Atorvastatin 10 mg',
      '0-0-1 · at night',
      '91%',
      MP.green,
      16.0,
      'Walk 30 minutes daily. Limit salt and fried food.',
    ),
    (
      'Dr. Nandita Gupta',
      'Gynaecology · Apollo Clinic · 18 Nov 2025',
      'Myo-inositol 2 g',
      '1-0-1 · after food',
      'Not tracked',
      MP.ink3,
      13.0,
      'Aim to lose 5% body weight in 6 months.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return D6PatientTabsPage(
      tab: 3,
      placeholder: placeholder,
      children: [
        // Plan owner
        MpCard(
          radius: 20,
          shadow: MPShadow.float,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const D6Caps('Your plan'),
                    const Gap(4),
                    Text('Dr. Arjun Sen', style: tx(20, w: w700, h: 1.25)),
                    const Gap(4),
                    Text('Updated 29 Sep 2026 · Next visit Thu, 29 Oct', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: D6Link('Edit', onTap: () => Nav.go(context, 'Consult-Advice')),
              ),
            ],
          ),
        ),

        const _Adherence(),

        // Current medications
        MpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text('Current medications', style: tx(20, w: w700, h: 1.25))),
                    const Gap(12),
                    const D6Caps('Taken'),
                  ],
                ),
              ),
              for (final m in _meds)
                D6Row(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$1, style: tx(16, w: w600)),
                            const Gap(3),
                            Text(m.$2, style: tx(14, tab: true)),
                            const Gap(3),
                            Text(m.$3, style: tx(13, c: MP.ink3)),
                          ],
                        ),
                      ),
                      const Gap(12),
                      Text(m.$4, textAlign: TextAlign.right, style: tx(m.$6, w: w700, c: m.$5, tab: true)),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Instructions & advice
        MpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Instructions & advice', style: tx(20, w: w700, h: 1.25)),
              ),
              for (final a in _advice)
                D6Row(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [D6Caps(a.$1, color: a.$3), const Gap(4), Text(a.$2, style: tx(15, h: 1.5))],
                  ),
                ),
            ],
          ),
        ),

        // From other doctors
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From other doctors', style: tx(20, w: w700, h: 1.25)),
              const Gap(4),
              Row(
                children: [
                  const Ico(I.lock, size: 16, color: MP.ink2),
                  const Gap(6),
                  Expanded(child: Text('Shared by Priya · read only', style: tx(14, c: MP.ink2))),
                ],
              ),
            ],
          ),
        ),
        for (final o in _others)
          MpCard(
            child: VGap(
              gap: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(o.$1, style: tx(16, w: w700)), const Gap(2), Text(o.$2, style: tx(14, c: MP.ink2))],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.$3, style: tx(15, w: w600)),
                            const Gap(2),
                            Text(o.$4, style: tx(13, c: MP.ink2)),
                          ],
                        ),
                      ),
                      const Gap(12),
                      Text(o.$5, textAlign: TextAlign.right, style: tx(o.$7, w: w700, c: o.$6)),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: tx(14, h: 1.5),
                    children: [
                      TextSpan(text: 'Advice:', style: tx(14, w: w600, c: MP.ink2, h: 1.5)),
                      TextSpan(text: ' ${o.$8}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adherence
// ─────────────────────────────────────────────────────────────────────────────

class _Adherence extends StatelessWidget {
  /// Live: GET /api/patients/:id/adherence (null = the design's sample).
  final Map<String, dynamic>? adh;
  final D6Rec? rec;
  const _Adherence({this.adh, this.rec});

  static const _slots = [('morning', 'Morning'), ('afternoon', 'Afternoon'), ('night', 'Night')];

  /// Day labels and one row of cells per slot for the last 7 days.
  static (List<String>, List<(String, List<String>)>) _week(Map<String, dynamic> a) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day).subtract(Duration(days: i))];
    final rows = <(String, List<String>)>[];
    for (final s in _slots) {
      final doses = [for (final d in a.list('week')) if (d['slot'] == s.$1) d];
      if (doses.isEmpty) continue;
      rows.add((
        s.$2,
        [
          for (final day in days)
            () {
              final st = [
                for (final d in doses)
                  if (F.date(d['at']) != null && F.sameDay(F.date(d['at'])!, day)) d.str('status'),
              ];
              if (st.isEmpty) return '';
              if (st.any((x) => x == 'missed' || x == 'skipped')) return 'm';
              if (st.every((x) => x == 'taken')) return 't';
              return 'd';
            }(),
        ],
      ));
    }
    return ([for (final d in days) names[d.weekday - 1]], rows);
  }

  @override
  Widget build(BuildContext context) {
    final a = adh;
    var pctText = '86%';
    var pct = 0.86;
    String? delta = '−4 pts vs previous 30 days';
    var deltaColor = MP.amber;
    var weekLabel = 'Doses this week: morning doses all taken; evening doses missed Friday to Monday';
    (List<String>, List<(String, List<String>)>)? week;
    (String, String)? callout = ('4 evening doses missed', ' in a row (Fri–Mon), all Metformin.');
    if (a != null) {
      final p = a['overallPct'];
      pct = p is num ? p / 100 : 0;
      pctText = p is num ? '${p.round()}%' : '–';
      final prev = a['previousPct'];
      if (p is num && prev is num) {
        final d = (p - prev).round();
        delta = d == 0 ? 'Same as previous ${a.numOr('days', 30)} days' : '${d < 0 ? '−' : '+'}${d.abs()} pts vs previous ${a.numOr('days', 30)} days';
        deltaColor = d < 0 ? MP.amber : MP.green;
      } else {
        delta = null;
      }
      week = _week(a);
      final taken = a.list('week').where((d) => d['status'] == 'taken').length;
      final missed = a.list('week').where((d) => d['status'] == 'missed' || d['status'] == 'skipped').length;
      weekLabel = 'Doses this week: $taken taken, $missed missed';
      final mm = a.obj('mostMissedSlot');
      final n = mm.numOr('misses').toInt();
      callout = n > 0 ? ('$n ${mm.str('slot')} ${n == 1 ? 'dose' : 'doses'} missed', ' in the last ${a.numOr('days', 30)} days.') : null;
    }
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Adherence', style: tx(20, w: w700, h: 1.25))),
              Text(a == null ? 'Last 30 days' : 'Last ${a.numOr('days', 30)} days', style: tx(14, c: MP.ink2)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(pctText, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                  if (delta != null) ...[
                    const Gap(10),
                    Flexible(child: Text(delta, style: tx(14, w: w600, c: deltaColor))),
                  ],
                ],
              ),
              const Gap(10),
              Semantics(
                label: '${(pct * 100).round()} percent of doses taken',
                image: true,
                child: MpProgress(pct, height: 8, track: MP.line),
              ),
            ],
          ),
          if (week == null || week.$2.isNotEmpty) Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D6Caps('This week'),
              const Gap(8),
              Semantics(
                label: weekLabel,
                image: true,
                excludeSemantics: true,
                child: week == null ? const _WeekGrid() : _WeekGrid(days: week.$1, rows: week.$2),
              ),
              const Gap(8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _legend(
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MP.greenSoft,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: MP.green),
                        ),
                      ),
                      'Taken',
                    ),
                    _legend(
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MP.amberSoft,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: MP.amber),
                        ),
                      ),
                      'Missed',
                    ),
                    _legend(const CustomPaint(size: Size(14, 14), painter: _DashedRRect(radius: 4)), 'Due later'),
                  ],
                ),
              ),
            ],
          ),
          if (callout != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(
                style: tx(14, h: 1.45),
                children: [
                  TextSpan(text: callout.$1, style: tx(14, w: w700, c: MP.amber, h: 1.45)),
                  TextSpan(text: callout.$2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Widget swatch, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [swatch, const Gap(6), Text(label, style: tx(13, c: MP.ink2))]);
}

/// Grid: 64px label column + 7 equal day columns, 6px gaps, 28px rows.
class _WeekGrid extends StatelessWidget {
  /// Live: weekday labels and (slot label, 7 cells) rows; '' = no dose.
  final List<String> days;
  final List<(String, List<String>)> rows;
  const _WeekGrid({this.days = _days, this.rows = const [('Morning', _morning), ('Evening', _evening)]});

  static const _days = ['Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue'];

  // t = taken, m = missed, d = due later.
  static const _morning = ['t', 't', 't', 't', 't', 't', 't'];
  static const _evening = ['t', 't', 'm', 'm', 'm', 'm', 'd'];

  @override
  Widget build(BuildContext context) {
    final label = tx(12, w: w600, c: MP.ink2);
    return LayoutBuilder(
      builder: (context, c) {
        final col = math.max(0.0, (c.maxWidth - 64 - 6 * 7) / 7);
        final cell = math.min(28.0, col);

        Widget row(String name, List<Widget> cells) => SizedBox(
          height: 28,
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Align(alignment: Alignment.centerLeft, child: Text(name, style: label, maxLines: 1)),
              ),
              for (final w in cells) ...[const Gap(6), SizedBox(width: col, child: Center(child: w))],
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('', [for (final d in days) Text(d, style: label, maxLines: 1, softWrap: false)]),
            for (final r in rows) ...[
              const Gap(6),
              row(r.$1, [for (final k in r.$2) _Dose(k, size: cell)]),
            ],
          ],
        );
      },
    );
  }
}

class _Dose extends StatelessWidget {
  final String kind;
  final double size;
  const _Dose(this.kind, {required this.size});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case '':
        return SizedBox(width: size, height: size);
      case 't':
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(8)),
          child: const Ico(I.check, size: 14, color: MP.green, stroke: 2.5),
        );
      case 'm':
        // 26px content box + 1px border = 28px.
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MP.amberSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MP.amber),
          ),
          child: const Ico(I.close, size: 12, color: MP.amber, stroke: 2.5),
        );
      default:
        return CustomPaint(size: Size(size, size), painter: const _DashedRRect(radius: 8));
    }
  }
}

/// 1px dashed rounded-rect outline (#69738A), like a CSS `1px dashed` border
/// (3px dashes, 2px gaps).
class _DashedRRect extends CustomPainter {
  final double radius;
  const _DashedRRect({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = MP.ink3
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius - 0.5));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 3, metric.length)), paint);
        d += 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect oldDelegate) => oldDelegate.radius != radius;
}

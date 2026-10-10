import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';
import '../../widgets/i18n.dart';

/// Design: Cards-Clinical.dc.html — "Cards · queue & clinical".
/// Live data: GET /api/dashboard/cards (lab flags, BP control, condition
/// registry), /api/appointments?view=today, /api/alerts (critical labs),
/// /api/follow-ups. "Recent lab reports" and the BP "Needs attention" list
/// have no practice-wide endpoint yet, so they are hidden live.
class CardsClinicalScreen extends StatefulWidget {
  const CardsClinicalScreen({super.key});

  @override
  State<CardsClinicalScreen> createState() => _CardsClinicalScreenState();
}

class _CardsClinicalScreenState extends State<CardsClinicalScreen> with LiveData {
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/dashboard/cards'),
      Api.I.get('/api/appointments', query: {'view': 'today'}),
      Api.I.get('/api/alerts', query: {'status': 'open'}),
      Api.I.get('/api/follow-ups'),
    ]);
    return {'cards': r[0], 'appointments': r[1], 'alerts': r[2], 'followUps': r[3]};
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final d = data;
    return MpPage(
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        gap: 16,
        children: [
          _TodaysClinic(d),
          if (d == null || _criticalLabs(d).isNotEmpty) _CriticalLabs(d),
          if (d == null) const _RecentLabs(),
          _LabFlags(d),
          _BpControl(d),
          _FollowUps(d),
          _Conditions(d),
        ],
      ),
    );
  }
}

/// Open lab alerts flagged critical (live).
List<Map<String, dynamic>> _criticalLabs(Map<String, dynamic> d) => [
  for (final a in d.obj('alerts').list('items'))
    if (a['kind'] == 'lab' && (a['severity'] == 'emergency' || a.str('detail').toLowerCase().contains('critical'))) a,
];

/// "Sun, 20 Sep"
String _dayShort(DateTime d) => F.dateLong(d).replaceFirst(RegExp(r' \d{4}$'), '');

Map<String, Object?> _patientArgs(Object? id) => {'patientId': id};

// Status tones (bg, fg).
const _info = (MP.primarySoft, MP.primary);
const _warn = (MP.amberSoft, MP.amber);
const _neutral = (MP.fill, MP.ink2);
const _ok = (MP.greenSoft, MP.green);
const _danger = (MP.redSoft, MP.red);

(Color, Color) _visitTone(String status) => switch (status) {
  'In consult' => _info,
  'Waiting' => _warn,
  'Upcoming' || 'Missed' => _neutral,
  _ => _ok,
};

String _visitStatus(String s) => switch (s) {
  'in_consultation' => 'In consult',
  'waiting' => 'Waiting',
  'completed' => 'Done',
  'missed' => 'Missed',
  _ => 'Upcoming',
};

String _visitType(String t) => switch (t) {
  'new' => 'New visit',
  'follow_up' => 'Follow-up',
  '' => 'Visit',
  _ => '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}',
};

(Color, Color) _flagTone(String flag) => switch (flag) {
  'Critical' => _danger,
  'High' || 'Low' => _warn,
  _ => _ok,
};

// ─── A. Today's clinic ───────────────────────────────────────────────────────

// (time, name, meta, status)
const _sen = [
  ('8:45', 'Amit Pal', 'Follow-up · Salt Lake', 'Done'),
  ('9:00', 'Priya Sharma', 'Follow-up · Salt Lake', 'In consult'),
  ('9:30', 'Rahul Das', 'New visit · Salt Lake', 'Waiting'),
];
const _mitra = [
  ('9:15', 'Debasish Bose', 'ECG review · New Town', 'Waiting'),
  ('11:45', 'Moumita Roy', 'Cardiology review · New Town', 'Upcoming'),
];

class _TodaysClinic extends StatelessWidget {
  final Map<String, dynamic>? d;
  const _TodaysClinic(this.d);

  @override
  Widget build(BuildContext context) {
    final live = d;
    if (live == null) {
      return D9Card(
        children: [
          D9Head(
            "Today's clinic",
            sub: '14 visits · Dr. Sen, Dr. Mitra',
            bottom: 12,
            trailing: D9Link('View all', top: 3, onTap: () => Nav.go(context, 'Appointments')),
          ),
          const D9Label('Dr. Arjun Sen · 8 visits', padding: EdgeInsets.only(bottom: 8)),
          for (final v in _sen) _VisitRow(v),
          const D9Label('Dr. Rina Mitra · 6 visits', padding: EdgeInsets.fromLTRB(0, 16, 0, 8)),
          for (final v in _mitra) _VisitRow(v),
          D9More('+ 9 more today', onTap: () => Nav.go(context, 'Appointments')),
        ],
      );
    }
    final appts = live.obj('appointments');
    final items = appts.list('items');
    final total = appts.numOr('total', items.length).toInt();
    // Visits per doctor, in time order.
    final byDoctor = <String, List<Map<String, dynamic>>>{};
    for (final a in items) {
      byDoctor.putIfAbsent(a.obj('doctor').str('name', 'Doctor'), () => []).add(a);
    }
    var shown = 0;
    final rows = <Widget>[];
    for (final e in byDoctor.entries) {
      rows.add(D9Label(
        '${e.key} · ${D9Fmt.plural(e.value.length, 'visit')}',
        padding: EdgeInsets.fromLTRB(0, rows.isEmpty ? 0 : 16, 0, 8),
      ));
      for (final a in e.value.take(3)) {
        final at = F.date(a['startAt']);
        shown++;
        rows.add(_VisitRow(
          (
            at == null ? '' : F.timeShort(at),
            a.obj('patient').str('name'),
            [_visitType(a.str('visitType')), a.obj('location').str('name')].where((x) => x.isNotEmpty).join(' · '),
            _visitStatus(a.str('status')),
          ),
          patientId: a.obj('patient')['id'],
        ));
      }
    }
    final more = total - shown;
    return D9Card(
      children: [
        D9Head(
          "Today's clinic",
          sub: [
            D9Fmt.plural(total, 'visit'),
            if (byDoctor.isNotEmpty) byDoctor.keys.map(F.doctorShort).join(', '),
          ].join(' · '),
          bottom: 12,
          trailing: D9Link('View all', top: 3, onTap: () => Nav.go(context, 'Appointments')),
        ),
        ...rows,
        if (items.isEmpty) Text('No visits today', style: tx(14, c: MP.ink2)),
        if (more > 0) D9More('+ $more more today', onTap: () => Nav.go(context, 'Appointments')),
      ],
    );
  }
}

class _VisitRow extends StatelessWidget {
  final (String, String, String, String) v;
  final Object? patientId;
  const _VisitRow(this.v, {this.patientId});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _visitTone(v.$4);
    return D9Row(
      onTap: () => Nav.go(context, 'PP-Summary', args: _patientArgs(patientId)),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(v.$1, style: tx(15, w: w600, h: 20 / 15, tab: true), maxLines: 1, softWrap: false),
          ),
          const Gap(12),
          Expanded(child: D9Lines(v.$2, sub: v.$3)),
          const Gap(12),
          MpBadge(v.$4, bg: bg, fg: fg, weight: w600),
        ],
      ),
    );
  }
}

// ─── B. Critical lab results ─────────────────────────────────────────────────

class _CriticalLabs extends StatelessWidget {
  final Map<String, dynamic>? d;
  const _CriticalLabs(this.d);

  Widget _liveRow(BuildContext context, Map<String, dynamic> a) {
    final at = F.date(a['createdAt']);
    final p = a.obj('patient');
    // "Potassium 6.1 mmol/L · ref 3.5–5.1 (critical)."
    var detail = a.str('detail').trim();
    if (detail.endsWith('.')) detail = detail.substring(0, detail.length - 1);
    detail = detail.replaceFirst(RegExp(r'\s*\(critical\)$', caseSensitive: false), '');
    final cut = detail.indexOf(' · ');
    final value = cut < 0 ? detail : detail.substring(0, cut);
    final rest = cut < 0 ? '' : detail.substring(cut);
    final ageSex = [if (p['age'] != null) '${p['age']}', D9Fmt.gender(p['gender'])].where((x) => x.isNotEmpty).join(' ');
    final about = [if (ageSex.isNotEmpty) ageSex, ...(p['conditions'] as List? ?? const []).map((c) => '$c')].join(' · ');
    return D9Row(
      onTap: () => Nav.go(context, 'PP-Tests', args: _patientArgs(p['id'])),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MpBadge.red('Critical'),
                    if (at != null) ...[
                      const Gap(8),
                      Text(F.askedAt(at), style: tx(13, c: MP.ink3, h: 18 / 13, tab: true)),
                    ],
                  ],
                ),
                const Gap(4),
                Text(p.str('name'), style: tx(16, w: w600, h: 22 / 16)),
                const Gap(4),
                Text.rich(
                  TextSpan(
                    style: tx(14, h: 20 / 14, tab: true),
                    children: [
                      TextSpan(text: value, style: tx(14, w: w600, c: MP.red, h: 20 / 14, tab: true)),
                      if (rest.isNotEmpty) TextSpan(text: rest, style: tx(14, c: MP.ink2, h: 20 / 14, tab: true)),
                    ],
                  ),
                ),
                if (about.isNotEmpty) ...[
                  const Gap(4),
                  Text(about, style: tx(13, c: MP.ink3, h: 18 / 13)),
                ],
              ],
            ),
          ),
          const Gap(12),
          const D9Chevron(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = d;
    if (live != null) {
      final items = _criticalLabs(live);
      return D9Card(
        border: MP.redLine,
        children: [
          D9Head(
            'Critical lab results',
            sub: 'Unreviewed critical results',
            bottom: 12,
            trailing: Padding(padding: const EdgeInsets.only(top: 2), child: MpBadge.red('${items.length} critical')),
          ),
          for (final a in items) _liveRow(context, a),
        ],
      );
    }
    return D9Card(
      border: MP.redLine,
      children: [
        const D9Head(
          'Critical lab results',
          sub: 'Unreviewed critical results',
          bottom: 12,
          trailing: Padding(padding: EdgeInsets.only(top: 2), child: MpBadge.red('1 critical')),
        ),
        D9Row(
          onTap: () => Nav.go(context, 'PP-Tests'),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const MpBadge.red('Critical'),
                        const Gap(8),
                        Text('7:55 AM', style: tx(13, c: MP.ink3, h: 18 / 13, tab: true)),
                      ],
                    ),
                    const Gap(4),
                    Text('Amit Pal', style: tx(16, w: w600, h: 22 / 16)),
                    const Gap(4),
                    Text.rich(
                      TextSpan(
                        style: tx(14, h: 20 / 14, tab: true),
                        children: [
                          TextSpan(
                            text: 'Potassium 6.1 mmol/L',
                            style: tx(14, w: w600, c: MP.red, h: 20 / 14, tab: true),
                          ),
                          TextSpan(text: ' · ref 3.5–5.1', style: tx(14, c: MP.ink2, h: 20 / 14, tab: true)),
                        ],
                      ),
                    ),
                    const Gap(4),
                    Text('Renal function test · 55 M · T2DM, CKD 3', style: tx(13, c: MP.ink3, h: 18 / 13)),
                  ],
                ),
              ),
              const Gap(12),
              const D9Chevron(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── B. Recent lab reports ───────────────────────────────────────────────────

// (patient, test · when, worst flag)
const _reports = [
  ('Amit Pal', 'Renal function test · Today, 7:55 AM', 'Critical'),
  ('Aisha Khan', 'Thyroid profile · Yesterday', 'High'),
  ('Debasish Bose', 'HbA1c · Yesterday', 'High'),
  ('Farhana Islam', 'Complete blood count · Sun, 27 Sep', 'Low'),
  ('Priya Sharma', 'Lipid profile · Sat, 26 Sep', 'Normal'),
  ('Rahul Das', 'Kidney function test · Fri, 25 Sep', 'Normal'),
];

class _RecentLabs extends StatelessWidget {
  const _RecentLabs();

  @override
  Widget build(BuildContext context) {
    return D9Card(
      children: [
        D9Head(
          'Recent lab reports',
          sub: 'Newest 6 · worst flag shown',
          bottom: 12,
          trailing: D9Link('View all', top: 3, onTap: () => Nav.go(context, 'PP-Tests')),
        ),
        for (final r in _reports)
          D9Row(
            onTap: () => Nav.go(context, 'PP-Tests'),
            child: Row(
              children: [
                Expanded(child: D9Lines(r.$1, sub: r.$2)),
                const Gap(12),
                MpBadge(r.$3, bg: _flagTone(r.$3).$1, fg: _flagTone(r.$3).$2),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── B. Lab flag summary ─────────────────────────────────────────────────────

// (label, count, swatch, inset ring)
const List<(String, String, Color, Color?)> _flags = [
  ('Critical', '1', MP.red, null),
  ('High', '38', MP.amber, null),
  ('Low', '12', MP.amberSoft, MP.amber),
  ('Normal', '214', MP.green, null),
];

class _LabFlags extends StatelessWidget {
  final Map<String, dynamic>? d;
  const _LabFlags(this.d);

  @override
  Widget build(BuildContext context) {
    final live = d?.obj('cards').obj('labFlags30d');
    final flags = live == null
        ? _flags
        : [
            for (final f in _flags) (f.$1, F.count(live.numOr(f.$1.toLowerCase())), f.$3, f.$4),
          ];
    int n(String k) => live?.numOr(k).toInt() ?? 0;
    final total = live?.numOr('total').toInt() ?? 0;
    return D9Card(
      gap: 16,
      children: [
        live == null
            ? const D9Head('Lab flag summary', sub: 'Last 30 days · 265 results')
            : D9Head('Lab flag summary', sub: 'Last 30 days · ${D9Fmt.plural(total, 'result')}'),
        live == null
            ? const D9Bar([
                D9Seg(1, MP.red, width: 4),
                D9Seg(38, MP.amber),
                D9Seg(12, MP.amberSoft, ring: MP.amber),
                D9Seg(214, MP.green),
              ], label: 'Of 265 results: 1 critical, 38 high, 12 low, 214 normal')
            : D9Bar([
                // A sliver of critical results keeps the design's 4px minimum.
                D9Seg(n('critical'), MP.red, width: n('critical') > 0 && n('critical') * 50 < total ? 4 : null),
                D9Seg(n('high'), MP.amber),
                D9Seg(n('low'), MP.amberSoft, ring: MP.amber),
                D9Seg(n('normal'), MP.green),
              ], label: 'Of ${D9Fmt.plural(total, 'result')}: ${n('critical')} critical, ${n('high')} high, ${n('low')} low, ${n('normal')} normal'),
        MpGrid(
          columns: 2,
          gap: 8,
          children: [
            for (final f in flags)
              D9Tile(
                gap: 6,
                children: [
                  Row(
                    children: [
                      D9Swatch(f.$3, ring: f.$4),
                      const Gap(8),
                      Expanded(child: Text(f.$1, style: tx(14, c: MP.ink2, h: 20 / 14))),
                    ],
                  ),
                  Text(f.$2, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ─── B. BP control ───────────────────────────────────────────────────────────

// (band, range, count, swatch, opacity, inset ring)
const List<(String, String, String, Color, double, Color?)> _bands = [
  ('Normal', 'Below 120/80', '38', MP.green, 1, null),
  ('Elevated', '120–129 / below 80', '21', MP.amberSoft, 1, MP.amber),
  ('Stage 1', '130–139 / 80–89', '18', MP.amber, 0.6, null),
  ('Stage 2', '140+ / 90+', '9', MP.amber, 1, null),
];

// (name, latest reading, band)
const _bpNamed = [
  ('Rahul Das', '172/104 mmHg · today, 8:40 AM', 'Stage 2'),
  ('Debasish Bose', '158/96 mmHg · Thu, 24 Sep', 'Stage 2'),
  ('Moumita Roy', '136/88 mmHg · 3 readings above', 'Stage 1'),
];

class _BpControl extends StatelessWidget {
  final Map<String, dynamic>? d;
  const _BpControl(this.d);

  @override
  Widget build(BuildContext context) {
    final cards = d?.obj('cards');
    final live = cards?.obj('bpControl90d');
    int n(String k) => live?.numOr(k).toInt() ?? 0;
    const keys = ['normal', 'elevated', 'stage1', 'stage2'];
    final bands = live == null
        ? _bands
        : [for (var i = 0; i < _bands.length; i++) (_bands[i].$1, _bands[i].$2, F.count(n(keys[i])), _bands[i].$4, _bands[i].$5, _bands[i].$6)];
    final measured = keys.fold(0, (s, k) => s + n(k));
    final patients = cards?.numOr('patients').toInt() ?? 0;
    final noReading = n('noReading');
    return D9Card(
      gap: 16,
      children: [
        live == null
            ? const D9Head('BP control', sub: 'Last 90 days · 86 of 112 measured')
            : D9Head('BP control', sub: 'Last 90 days · ${F.count(measured)} of ${F.count(patients)} measured'),
        live == null
            ? const D9Bar([
                D9Seg(38, MP.green),
                D9Seg(21, MP.amberSoft, ring: MP.amber),
                D9Seg(18, MP.amber, opacity: 0.6),
                D9Seg(9, MP.amber),
              ], label: 'Latest BP of 86 patients: 38 normal, 21 elevated, 18 stage 1, 9 stage 2')
            : D9Bar([
                D9Seg(n('normal'), MP.green),
                D9Seg(n('elevated'), MP.amberSoft, ring: MP.amber),
                D9Seg(n('stage1'), MP.amber, opacity: 0.6),
                D9Seg(n('stage2'), MP.amber),
              ], label: 'Latest BP of ${D9Fmt.plural(measured, 'patient')}: ${n('normal')} normal, ${n('elevated')} elevated, ${n('stage1')} stage 1, ${n('stage2')} stage 2'),
        VGap(
          gap: 8,
          children: [
            for (final b in bands)
              Row(
                children: [
                  D9Swatch(b.$4, opacity: b.$5, ring: b.$6),
                  const Gap(8),
                  SizedBox(width: 72, child: Text(b.$1, style: tx(14, w: w600, h: 20 / 14))),
                  const Gap(8),
                  Expanded(child: Text(b.$2, style: tx(13, c: MP.ink3, h: 20 / 13, tab: true))),
                  const Gap(8),
                  Text(b.$3, style: tx(14, w: w700, h: 20 / 14, tab: true)),
                ],
              ),
            if (live == null)
              Text('26 patients have no reading in 90 days', style: tx(13, c: MP.ink3, h: 18 / 13))
            else if (noReading > 0)
              Text(
                '${D9Fmt.plural(noReading, 'patient')} ${noReading == 1 ? 'has' : 'have'} no reading in 90 days',
                style: tx(13, c: MP.ink3, h: 18 / 13),
              ),
          ],
        ),
        // Per-patient readings aren't in /api/dashboard/cards yet.
        if (live == null) Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const D9Label('Needs attention', padding: EdgeInsets.only(bottom: 8)),
            for (final p in _bpNamed)
              D9Row(
                onTap: () => Nav.go(context, 'PP-Summary'),
                child: Row(
                  children: [
                    Expanded(child: D9Lines(p.$1, sub: p.$2, clipTitle: false)),
                    const Gap(12),
                    MpBadge.amber(p.$3),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── B. Follow-ups due ───────────────────────────────────────────────────────

// (name, how late, detail)
const _overdue = [
  ('Debasish Bose', '9 days overdue', 'was due Sun, 20 Sep'),
  ('Sujit Mondal', '6 days overdue', 'was due Wed, 23 Sep'),
  ('Farhana Islam', '3 days overdue', 'was due Sat, 26 Sep'),
];
// (name, detail)
const _dueSoon = [
  ('Aisha Khan', 'Thu, 1 Oct · Thyroid review'),
  ('Moumita Roy', 'Fri, 2 Oct · Cardiology, Dr. Mitra'),
  ('Rahul Das', 'Sat, 3 Oct · BP review'),
];

class _FollowUps extends StatelessWidget {
  final Map<String, dynamic>? d;
  const _FollowUps(this.d);

  Widget _live(BuildContext context, Map<String, dynamic> live) {
    void openAll() => Nav.go(context, 'Doctor-FollowUps');
    final items = live.obj('followUps').list('items');
    final overdue = items.where((f) => f['group'] == 'overdue').toList();
    final week = items.where((f) => f['group'] == 'this_week').toList();
    String due(Map<String, dynamic> f) {
      final at = F.date(f['dueDate']);
      return at == null ? '' : _dayShort(at);
    }

    Widget row(Map<String, dynamic> f, Widget lines) => D9Row(
      onTap: () => Nav.go(context, 'PP-Summary', args: _patientArgs(f.obj('patient')['id'])),
      child: Row(children: [Expanded(child: lines), const Gap(12), const D9Chevron()]),
    );

    return D9Card(
      gap: 24,
      children: [
        const D9Head('Follow-ups due', sub: 'Overdue first, then this week'),
        if (overdue.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              D9Label('Overdue · ${overdue.length}', color: MP.amber, padding: const EdgeInsets.only(bottom: 8)),
              for (final f in overdue.take(3))
                row(
                  f,
                  D9Lines(
                    f.obj('patient').str('name'),
                    clipTitle: false,
                    subSpans: [
                      TextSpan(
                        text: '${D9Fmt.plural(f.numOr('overdueDays'), 'day')} overdue',
                        style: tx(14, w: w600, c: MP.amber, h: 20 / 14),
                      ),
                      if (due(f).isNotEmpty) TextSpan(text: ' · was due ${due(f)}'),
                    ],
                  ),
                ),
              if (overdue.length > 3) D9More('+ ${overdue.length - 3} more overdue', onTap: openAll),
            ],
          ),
        if (week.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              D9Label('Due this week · ${week.length}', padding: const EdgeInsets.only(bottom: 8)),
              for (final f in week.take(3))
                row(
                  f,
                  D9Lines(
                    f.obj('patient').str('name'),
                    clipTitle: false,
                    sub: [due(f), f.str('adviceText').replaceFirst(RegExp(r'\.$'), '')].where((x) => x.isNotEmpty).join(' · '),
                  ),
                ),
              if (week.length > 3) D9More('+ ${week.length - 3} more this week', onTap: openAll),
            ],
          ),
        if (overdue.isEmpty && week.isEmpty) Text('No follow-ups due this week', style: tx(14, c: MP.ink2)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (d != null) return _live(context, d!);
    void openPatient() => Nav.go(context, 'PP-Summary');
    void openAll() => Nav.go(context, 'Doctor-FollowUps');
    return D9Card(
      gap: 24,
      children: [
        const D9Head('Follow-ups due', sub: 'Overdue first, then this week'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const D9Label('Overdue · 7', color: MP.amber, padding: EdgeInsets.only(bottom: 8)),
            for (final o in _overdue)
              D9Row(
                onTap: openPatient,
                child: Row(
                  children: [
                    Expanded(
                      child: D9Lines(
                        o.$1,
                        clipTitle: false,
                        subSpans: [
                          TextSpan(text: o.$2, style: tx(14, w: w600, c: MP.amber, h: 20 / 14)),
                          TextSpan(text: ' · ${o.$3}'),
                        ],
                      ),
                    ),
                    const Gap(12),
                    const D9Chevron(),
                  ],
                ),
              ),
            D9More('+ 4 more overdue', onTap: openAll),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const D9Label('Due this week · 9', padding: EdgeInsets.only(bottom: 8)),
            for (final d in _dueSoon)
              D9Row(
                onTap: openPatient,
                child: Row(
                  children: [
                    Expanded(child: D9Lines(d.$1, sub: d.$2, clipTitle: false)),
                    const Gap(12),
                    const D9Chevron(),
                  ],
                ),
              ),
            D9More('+ 6 more this week', onTap: openAll),
          ],
        ),
      ],
    );
  }
}

// ─── B. Condition registry ───────────────────────────────────────────────────

const _caseload = 412;
const _conditions = [
  ('Type 2 diabetes', 148),
  ('Hypertension', 121),
  ('Dyslipidaemia', 96),
  ('Hypothyroidism', 44),
  ('Coronary artery disease', 27),
  ('Chronic kidney disease', 18),
];

class _Conditions extends StatelessWidget {
  final Map<String, dynamic>? d;
  const _Conditions(this.d);

  @override
  Widget build(BuildContext context) {
    void openPatients() => Nav.go(context, 'Doctor-Patients');
    final cards = d?.obj('cards');
    final caseload = cards == null ? _caseload : cards.numOr('patients').toInt();
    final conditions = cards == null
        ? _conditions
        : [for (final c in cards.list('conditionRegistry').take(6)) (c.str('key'), c.numOr('count').toInt())];
    final none = cards == null ? 31 : cards.numOr('noCondition').toInt();
    return D9Card(
      children: [
        D9Head(
          'Condition registry',
          sub: 'Practice-wide · ${D9Fmt.plural(caseload, 'patient')}',
          bottom: 12,
          trailing: D9Link('View all', top: 3, onTap: openPatients),
        ),
        if (conditions.isEmpty) Text('No conditions recorded yet', style: tx(14, c: MP.ink2)),
        for (final c in conditions)
          D9Row(
            padding: const EdgeInsets.symmetric(vertical: 12),
            onTap: openPatients,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.$1, style: tx(16, h: 22 / 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const Gap(12),
                    Text('${c.$2}', style: tx(16, w: w700, h: 22 / 16, tab: true)),
                  ],
                ),
                const Gap(8),
                MpProgress(caseload <= 0 ? 0 : c.$2 / caseload, height: 4),
              ],
            ),
          ),
        if (none > 0) ...[
          const Gap(16),
          D9Note(
            strong: F.count(none),
            text: none == 1 ? ' patient with no condition recorded' : ' patients with no condition recorded',
            action: 'Review',
            onAction: openPatients,
          ),
        ],
      ],
    );
  }
}

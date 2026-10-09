import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: Cards-Clinical.dc.html — "Cards · queue & clinical".
class CardsClinicalScreen extends StatelessWidget {
  const CardsClinicalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MpPage(
      body: VGap(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
        gap: 16,
        children: [
          _TodaysClinic(),
          _CriticalLabs(),
          _RecentLabs(),
          _LabFlags(),
          _BpControl(),
          _FollowUps(),
          _Conditions(),
        ],
      ),
    );
  }
}

// Status tones (bg, fg).
const _info = (MP.primarySoft, MP.primary);
const _warn = (MP.amberSoft, MP.amber);
const _neutral = (MP.fill, MP.ink2);
const _ok = (MP.greenSoft, MP.green);
const _danger = (MP.redSoft, MP.red);

(Color, Color) _visitTone(String status) => switch (status) {
  'In consult' => _info,
  'Waiting' => _warn,
  'Upcoming' => _neutral,
  _ => _ok,
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
  const _TodaysClinic();

  @override
  Widget build(BuildContext context) {
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
}

class _VisitRow extends StatelessWidget {
  final (String, String, String, String) v;
  const _VisitRow(this.v);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _visitTone(v.$4);
    return D9Row(
      onTap: () => Nav.go(context, 'PP-Summary'),
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
  const _CriticalLabs();

  @override
  Widget build(BuildContext context) {
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
  const _LabFlags();

  @override
  Widget build(BuildContext context) {
    return D9Card(
      gap: 16,
      children: [
        const D9Head('Lab flag summary', sub: 'Last 30 days · 265 results'),
        const D9Bar([
          D9Seg(1, MP.red, width: 4),
          D9Seg(38, MP.amber),
          D9Seg(12, MP.amberSoft, ring: MP.amber),
          D9Seg(214, MP.green),
        ], label: 'Of 265 results: 1 critical, 38 high, 12 low, 214 normal'),
        MpGrid(
          columns: 2,
          gap: 8,
          children: [
            for (final f in _flags)
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
  const _BpControl();

  @override
  Widget build(BuildContext context) {
    return D9Card(
      gap: 16,
      children: [
        const D9Head('BP control', sub: 'Last 90 days · 86 of 112 measured'),
        const D9Bar([
          D9Seg(38, MP.green),
          D9Seg(21, MP.amberSoft, ring: MP.amber),
          D9Seg(18, MP.amber, opacity: 0.6),
          D9Seg(9, MP.amber),
        ], label: 'Latest BP of 86 patients: 38 normal, 21 elevated, 18 stage 1, 9 stage 2'),
        VGap(
          gap: 8,
          children: [
            for (final b in _bands)
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
            Text('26 patients have no reading in 90 days', style: tx(13, c: MP.ink3, h: 18 / 13)),
          ],
        ),
        Column(
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
  const _FollowUps();

  @override
  Widget build(BuildContext context) {
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
  const _Conditions();

  @override
  Widget build(BuildContext context) {
    void openPatients() => Nav.go(context, 'Doctor-Patients');
    return D9Card(
      children: [
        D9Head(
          'Condition registry',
          sub: 'Practice-wide · 412 patients',
          bottom: 12,
          trailing: D9Link('View all', top: 3, onTap: openPatients),
        ),
        for (final c in _conditions)
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
                MpProgress(c.$2 / _caseload, height: 4),
              ],
            ),
          ),
        const Gap(16),
        D9Note(strong: '31', text: ' patients with no condition recorded', action: 'Review', onAction: openPatients),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d2.dart';

/// Design: Doctor-History.dc.html — "Doctor · History (all appointments)".
class DoctorHistoryScreen extends StatefulWidget {
  const DoctorHistoryScreen({super.key});

  @override
  State<DoctorHistoryScreen> createState() => _DoctorHistoryScreenState();
}

class _Appt {
  final String name;
  final String status;
  final String when;
  final String where;
  final String action;
  const _Appt(this.name, this.status, this.when, this.where, this.action);
}

class _Day {
  final String title;
  final String note;
  final List<_Appt> appts;
  final String? more;
  const _Day(this.title, this.note, this.appts, [this.more]);
}

const _today = _Day('Today, 1 Oct', '2 done so far', [
  _Appt(
    'Debasish Bose',
    'Completed',
    '9:10 AM · 62 M · Follow-up · Type 2 diabetes',
    'City Care · Salt Lake · 9 min',
    'Prescription',
  ),
  _Appt(
    'Farhana Islam',
    'Completed',
    '8:58 AM · 34 F · Report review · Anaemia',
    'City Care · Salt Lake · 12 min',
    'Prescription',
  ),
]);

const _earlier = [
  _Day('Wed, 30 Sep', '13 appointments', [
    _Appt(
      'Arijit Roy',
      'Completed',
      '5:15 PM · 35 M · New · Fever, cough',
      'City Care · New Town · 10 min',
      'Prescription',
    ),
    _Appt(
      'Ritam Sarkar',
      'Missed',
      '11:30 AM · 41 M · Follow-up · Type 2 diabetes',
      'City Care · Salt Lake',
      'Reschedule',
    ),
    _Appt(
      'Puja Saha',
      'Completed',
      '10:10 AM · 27 F · Report review · video',
      'City Care · Salt Lake · 7 min',
      'Prescription',
    ),
    _Appt(
      'Tapas Kar',
      'Completed',
      '9:46 AM · 63 M · Follow-up · Hypertension',
      'City Care · Salt Lake · 9 min',
      'Prescription',
    ),
    _Appt(
      'Sohini Bose',
      'Cancelled',
      '9:30 AM · 36 F · Follow-up · Hypothyroidism',
      'Cancelled by patient · 29 Sep',
      'Book again',
    ),
  ], 'Show 8 more from 30 Sep'),
  _Day('Tue, 29 Sep', '11 appointments', [
    _Appt(
      'Priya Sharma',
      'Completed',
      '9:14 AM · 29 F · Follow-up · Type 2 diabetes',
      'City Care · Salt Lake · 14 min',
      'Prescription',
    ),
    _Appt(
      'Partha Ghosh',
      'Rescheduled',
      '9:00 AM · 59 M · Follow-up · Hypertension',
      'Moved to 6 Oct by front desk',
      'View',
    ),
  ], 'Show more'),
];

const _statuses = ['All', 'Completed', 'Missed', 'Cancelled', 'Rescheduled'];

/// Period options (picker label, button label).
const _periods = [('This month', 'This month'), ('Last 3 months', '3 months'), ('This year', 'This year')];

/// Where each row link goes.
String _target(String action) => switch (action) {
  'Prescription' => 'Prescriptions',
  'Reschedule' || 'Book again' => 'Appointments-Manage',
  _ => 'Appointments',
};

class _DoctorHistoryScreenState extends State<DoctorHistoryScreen> {
  int _status = 0;
  int _period = 1;
  String _query = '';

  bool _show(_Appt a) {
    final q = _query.trim().toLowerCase();
    if (_status != 0 && a.status != _statuses[_status]) return false;
    return q.isEmpty || a.name.toLowerCase().contains(q);
  }

  Future<void> _pickPeriod() async {
    final v = await d2PickOption(
      context,
      title: 'Period',
      options: [for (final p in _periods) p.$1],
      value: _periods[_period].$1,
    );
    if (v != null && mounted) setState(() => _period = _periods.indexWhere((p) => p.$1 == v));
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var shown = 0;
    void addDay(_Day d) {
      final rows = d.appts.where(_show).toList();
      if (rows.isEmpty) return;
      shown += rows.length;
      children
        ..add(_DayHeader(d.title, d.note))
        ..add(_DayCard(rows));
      if (d.more != null) children.add(_ShowMore(d.more!));
    }

    addDay(_today);
    children.add(const _MonthCard());
    for (final d in _earlier) {
      addDay(d);
    }
    if (shown == 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No appointments found', textAlign: TextAlign.center, style: tx(14, c: MP.ink2)),
        ),
      );
    }

    return MpPage(
      header: D2TabHeader(
        title: 'History',
        subtitle: 'All your past appointments',
        action: D2PillButton(
          'Download',
          icon: I.downloadAlt,
          outlined: true,
          stroke: 1.75,
          onTap: () => Nav.go(context, 'History-Download'),
        ),
        search: Row(
          children: [
            Expanded(
              child: D2SearchField(
                hint: 'Search patient',
                height: 48,
                padH: 14,
                iconSize: 18,
                color: null,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Gap(8),
            D2PillButton(
              _periods[_period].$2,
              icon: I.calendar,
              outlined: true,
              height: 48,
              radius: 16,
              iconSize: 16,
              stroke: 1.75,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onTap: _pickPeriod,
            ),
          ],
        ),
        chips: [
          for (var i = 0; i < _statuses.length; i++)
            D2Chip(_statuses[i], selected: i == _status, onTap: () => setState(() => _status = i)),
        ],
      ),
      nav: const DoctorNav(current: 4),
      body: VGap(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), gap: 12, children: children),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String title;
  final String note;
  const _DayHeader(this.title, this.note);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [Expanded(child: D2Caps(title)), const Gap(8), Text(note, style: tx(13, c: MP.ink3))],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final List<_Appt> rows;
  const _DayCard(this.rows);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < rows.length; i++) _ApptRow(rows[i], first: i == 0)],
      ),
    );
  }
}

class _ApptRow extends StatelessWidget {
  final _Appt a;
  final bool first;
  const _ApptRow(this.a, {required this.first});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (a.status) {
      'Completed' => (MP.greenSoft, MP.green),
      'Missed' => (MP.redSoft, MP.red),
      'Rescheduled' => (MP.amberSoft, MP.amber),
      _ => (MP.fill, MP.ink2),
    };
    return Tap(
      onTap: () => Nav.go(context, 'PP-Summary'),
      radius: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(a.name, style: tx(15, w: w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const Gap(10),
                MpBadge(a.status, bg: bg, fg: fg, height: 22, padX: 8),
              ],
            ),
            const Gap(6),
            Text(a.when, style: tx(13, c: MP.ink2, h: 1.4)),
            const Gap(6),
            Row(
              children: [
                Expanded(child: Text(a.where, style: tx(13, c: MP.ink3))),
                const Gap(8),
                Tap(
                  onTap: () => Nav.go(context, _target(a.action)),
                  radius: 6,
                  child: Text(a.action, style: tx(14, w: w600, c: MP.primary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowMore extends StatelessWidget {
  final String label;
  const _ShowMore(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Tap(
        onTap: () => toast(context, 'No more appointments to show'),
        radius: 12,
        child: Center(child: Text(label, style: tx(15, w: w600, c: MP.primary))),
      ),
    );
  }
}

/// "September 2026" summary: 91 / 7 / 2 % stacked bar + legend.
class _MonthCard extends StatelessWidget {
  const _MonthCard();

  static const _legend = [
    ('Completed', '286', MP.primary),
    ('Missed', '21', MP.red),
    ('Cancelled', '7', MP.lineStrong),
  ];

  @override
  Widget build(BuildContext context) {
    return MpCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('September 2026', style: tx(17, w: w700))),
              const Gap(8),
              Text('314 appointments', style: tx(13, c: MP.ink3)),
            ],
          ),
          const Gap(10),
          Semantics(
            label: '314 appointments',
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 91,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: MP.primary,
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(999)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(flex: 7, child: Container(color: MP.red)),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: MP.lineStrong,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(999)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final l in _legend)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: l.$3, shape: BoxShape.circle)),
                    const Gap(6),
                    Text(l.$1, style: tx(13, c: MP.ink2)),
                    const Gap(6),
                    Text(l.$2, style: tx(13, w: w700)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

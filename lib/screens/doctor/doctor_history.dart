import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';

/// Design: Doctor-History.dc.html — "Doctor · History (all appointments)".
/// Live data: GET /api/history?period=this_month|last_3_months|this_year.
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

  /// Live: the appointment and patient ids (null in the design preview).
  final String? id;
  final String? patientId;
  const _Appt(this.name, this.status, this.when, this.where, this.action, [this.id, this.patientId]);

  Map<String, String>? get args => patientId == null ? null : {'patientId': patientId!, if (id != null) 'appointmentId': id!};
}

class _Day {
  final String title;
  final String note;
  final List<_Appt> appts;
  final String? more;

  /// Live: a key for "show more" (YYYY-M-D).
  final String? key;
  const _Day(this.title, this.note, this.appts, [this.more, this.key]);
}

const _periodKeys = ['this_month', 'last_3_months', 'this_year'];
const _pastStatuses = {'completed': 'Completed', 'missed': 'Missed', 'cancelled': 'Cancelled', 'rescheduled': 'Rescheduled'};
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// One past appointment from GET /api/history.
_Appt _liveAppt(Map<String, dynamic> a) {
  final p = a.obj('patient');
  final at = F.date(a['startAt']);
  final status = _pastStatuses[a['status']] ?? d2Role(a['status']);
  final type = switch (a['visitType']) { 'follow_up' => 'Follow-up', 'new' => 'New', 'report_review' => 'Report review', _ => d2Role(a['visitType']) };
  final conds = p['conditions'] as List? ?? const [];
  final when = [
    if (at != null) _clock(at),
    d2AgeSex(p),
    type,
    if (a['mode'] == 'video') 'video' else if (conds.isNotEmpty) '${conds.first}',
  ].where((s) => s.isNotEmpty).join(' · ');
  final practice = '${Session.I.activeMembership?['practiceName'] ?? ''}'.replaceFirst(RegExp(r'\s+Clinic$'), '');
  final place = [practice, a.obj('location').str('name')].where((s) => s.isNotEmpty).join(' · ');
  final started = F.date(a['consultStartedAt']), done = F.date(a['completedAt']);
  final mins = started != null && done != null ? done.difference(started).inMinutes : null;
  final cancelledAt = F.date(a['cancelledAt']);
  final where = switch (a['status']) {
    'cancelled' => ['Cancelled', if (a.str('cancelReason').isNotEmpty) a.str('cancelReason'), if (cancelledAt != null) d2DayMonth(cancelledAt)].join(' · '),
    'rescheduled' => 'Moved to a new time',
    _ => [place, if (mins != null && mins > 0) '$mins min'].where((s) => s.isNotEmpty).join(' · '),
  };
  final action = switch (a['status']) { 'completed' => 'Prescription', 'missed' => 'Reschedule', 'cancelled' => 'Book again', _ => 'View' };
  return _Appt(p.str('name'), status, when, where, action, a.str('id'), p.str('id', a.str('patientId')));
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

class _DoctorHistoryScreenState extends State<DoctorHistoryScreen> with LiveData {
  int _status = 0;
  int _period = 1;
  String _query = '';
  final _expanded = <String>{};

  @override
  Future<Object?> fetch() => Api.I.get('/api/history', query: {'period': _periodKeys[_period]});

  /// Live: today's and earlier days (newest first), five rows each until expanded.
  (_Day?, List<_Day>) get _liveDays {
    final byDay = <String, List<Map<String, dynamic>>>{};
    final dates = <String, DateTime>{};
    for (final a in data!.list('items')) {
      if (!_pastStatuses.containsKey(a['status'])) continue;
      final at = F.date(a['startAt']);
      if (at == null) continue;
      final k = '${at.year}-${at.month}-${at.day}';
      byDay.putIfAbsent(k, () => []).add(a);
      dates[k] = at;
    }
    final now = DateTime.now();
    _Day? today;
    final earlier = <_Day>[];
    for (final k in byDay.keys) {
      final d = dates[k]!;
      final appts = [for (final a in byDay[k]!) _liveAppt(a)];
      if (F.sameDay(d, now)) {
        final done = appts.where((a) => a.status == 'Completed').length;
        today = _Day('Today, ${d.day} ${_mon[d.month - 1]}', '$done done so far', appts, null, k);
        continue;
      }
      final open = _expanded.contains(k) || appts.length <= 5 || _status != 0 || _query.trim().isNotEmpty;
      earlier.add(_Day(
        '${_wd[d.weekday - 1]}, ${d.day} ${_mon[d.month - 1]}',
        '${appts.length} ${appts.length == 1 ? 'appointment' : 'appointments'}',
        open ? appts : appts.sublist(0, 5),
        open ? null : 'Show ${appts.length - 5} more from ${d.day} ${_mon[d.month - 1]}',
        k,
      ));
    }
    return (today, earlier);
  }

  /// Live month card: period title, total and the three counts.
  (String, int, int, int) get _liveSummary {
    final s = data!.obj('summary');
    final now = DateTime.now();
    final from = F.date(data!['from']);
    final title = switch (_period) {
      0 => '${_monthLong[now.month - 1]} ${now.year}',
      2 => '${now.year}',
      _ => from == null ? 'Last 3 months' : '${from.day} ${_mon[from.month - 1]} – ${now.day} ${_mon[now.month - 1]} ${now.year}',
    };
    return (title, s.numOr('completed').toInt(), s.numOr('missed').toInt(), s.numOr('cancelled').toInt());
  }

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
    if (v != null && mounted) {
      setState(() => _period = _periods.indexWhere((p) => p.$1 == v));
      if (isLive) reload(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final children = <Widget>[];
    var shown = 0;
    void addDay(_Day d) {
      final rows = d.appts.where(_show).toList();
      if (rows.isEmpty) return;
      shown += rows.length;
      children
        ..add(_DayHeader(d.title, d.note))
        ..add(_DayCard(rows));
      if (d.more != null) {
        children.add(_ShowMore(d.more!, onTap: d.key == null ? null : () => setState(() => _expanded.add(d.key!))));
      }
    }

    if (data == null) {
      addDay(_today);
      children.add(const _MonthCard());
      for (final d in _earlier) {
        addDay(d);
      }
    } else {
      final (today, earlier) = _liveDays;
      if (today != null) addDay(today);
      final s = _liveSummary;
      if (s.$2 + s.$3 + s.$4 > 0) children.add(_MonthCard(live: s));
      for (final d in earlier) {
        addDay(d);
      }
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
          onTap: () => Nav.go(context, 'History-Download', args: isLive ? {'period': _periodKeys[_period]} : null),
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
      body: placeholder ?? VGap(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), gap: 12, children: children),
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
      onTap: () => Nav.go(context, 'PP-Summary', args: a.args),
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
                  onTap: () => Nav.go(context, _target(a.action), args: a.args),
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
  final VoidCallback? onTap;
  const _ShowMore(this.label, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Tap(
        onTap: onTap ?? () => toast(context, 'No more appointments to show'),
        radius: 12,
        child: Center(child: Text(label, style: tx(15, w: w600, c: MP.primary))),
      ),
    );
  }
}

/// "September 2026" summary: 91 / 7 / 2 % stacked bar + legend.
class _MonthCard extends StatelessWidget {
  /// Live: (title, completed, missed, cancelled).
  final (String, int, int, int)? live;
  const _MonthCard({this.live});

  static const _sampleLegend = [
    ('Completed', '286', MP.primary),
    ('Missed', '21', MP.red),
    ('Cancelled', '7', MP.lineStrong),
  ];

  @override
  Widget build(BuildContext context) {
    final l = live;
    final title = l?.$1 ?? 'September 2026';
    final total = l == null ? 314 : l.$2 + l.$3 + l.$4;
    final flex = l == null ? (91, 7, 2) : (l.$2, l.$3, l.$4);
    final legend = l == null
        ? _sampleLegend
        : [('Completed', '${l.$2}', MP.primary), ('Missed', '${l.$3}', MP.red), ('Cancelled', '${l.$4}', MP.lineStrong)];
    final parts = [
      if (flex.$1 > 0) (flex.$1, MP.primary),
      if (flex.$2 > 0) (flex.$2, MP.red),
      if (flex.$3 > 0) (flex.$3, MP.lineStrong),
    ];
    final label = '$total ${total == 1 ? 'appointment' : 'appointments'}';
    return MpCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: tx(17, w: w700))),
              const Gap(8),
              Text(label, style: tx(13, c: MP.ink3)),
            ],
          ),
          const Gap(10),
          Semantics(
            label: label,
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: parts[i].$1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: parts[i].$2,
                          borderRadius: BorderRadius.horizontal(
                            left: i == 0 ? const Radius.circular(999) : Radius.zero,
                            right: i == parts.length - 1 ? const Radius.circular(999) : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Gap(10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final l in legend)
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

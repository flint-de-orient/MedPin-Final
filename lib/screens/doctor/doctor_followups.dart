import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-FollowUps.dc.html — "Doctor · Follow-ups (quick action)".
/// Live data: GET /api/follow-ups?doctorId=me&locationId&condition (tabs are
/// filtered here so the counts always match); Remind / Remind all.
class DoctorFollowupsScreen extends StatefulWidget {
  const DoctorFollowupsScreen({super.key});

  @override
  State<DoctorFollowupsScreen> createState() => _DoctorFollowupsScreenState();
}

/// One follow-up row.
class _Fu {
  final String name;
  final String status;
  final Color bg;
  final Color fg;
  final String meta;
  final String advice;
  final String when;
  final List<String> actions;
  final bool booked;
  final List<String> conditions;

  /// Live: follow-up, patient and booked appointment ids, phone, reminders sent.
  final String? id;
  final String? patientId;
  final String? appointmentId;
  final String phone;
  final int reminders;
  const _Fu(
    this.name,
    this.status,
    this.bg,
    this.fg,
    this.meta,
    this.advice,
    this.when,
    this.actions, {
    required this.booked,
    required this.conditions,
    this.id,
    this.patientId,
    this.appointmentId,
    this.phone = '',
    this.reminders = 0,
  });

  /// Not booked yet (a reminder can go out).
  bool get remindable => !booked;

  /// A row from GET /api/follow-ups.
  factory _Fu.fromApi(Map<String, dynamic> m) {
    final p = m.obj('patient');
    final status = m.str('status');
    final (label, bg, fg) = switch (status) {
      'no_reply' => ('No reply', MP.redSoft, MP.red),
      'booked' => ('Booked', MP.greenSoft, MP.green),
      'reports_in' => ('Reports in', MP.primarySoft, MP.primary),
      _ => ('Not booked', MP.amberSoft, MP.amber),
    };
    final booked = status == 'booked' || status == 'reports_in';
    final conditions = [for (final c in (p['conditions'] as List? ?? const [])) '$c'];
    final phone = p.str('phone');
    final meta = [d1AgeSex(p), conditions.join(', '), if (phone.isNotEmpty) d1Phone(phone)].where((x) => x.isNotEmpty).join(' · ');
    final advised = F.date(m['advisedOn']);
    final who = m.str('doctorId') == d1MyId ? 'You advised' : 'Advised';
    final text = m.str('adviceText').trim();
    final advice = [
      '$who${advised == null ? '' : ' on ${F.dayMonth(advised)}'}${text.isEmpty ? '.' : ':'}',
      if (text.isNotEmpty) '“$text”',
    ].join(' ');
    final appt = m['appointmentId'] is Map ? m.obj('appointmentId') : const <String, dynamic>{};
    final start = F.date(appt['startAt']);
    final due = F.date(m['dueDate']);
    final overdue = m.numOr('overdueDays').toInt();
    final place = m['locationId'] is Map ? m.obj('locationId').str('shortName', m.obj('locationId').str('name')) : '';
    final String when;
    if (booked && start != null) {
      when = [F.when(start), if (place.isNotEmpty) place].join(' · ');
    } else if (overdue > 0) {
      when = '${d1Count(overdue, 'day')} overdue';
    } else {
      when = due == null ? 'Due soon' : 'Due ${d1Day(due)}';
    }
    final actions = switch (status) {
      'booked' => ['View'],
      'no_reply' => ['Call', 'Remind'],
      'reports_in' => start != null ? ['View'] : ['Remind', 'Book'],
      _ => ['Remind', 'Book'],
    };
    return _Fu(
      p.str('name'),
      label,
      bg,
      fg,
      meta,
      advice,
      when,
      actions,
      booked: booked,
      conditions: conditions,
      id: m.str('id'),
      patientId: p.str('id', m.str('patientId')),
      appointmentId: appt.isEmpty ? (m['appointmentId'] is String ? m['appointmentId'] as String : null) : appt.str('id'),
      phone: phone,
      reminders: m.numOr('remindersSent').toInt(),
    );
  }
}

const _overdue = [
  _Fu(
    'Kaushik Paul',
    'No reply',
    MP.redSoft,
    MP.red,
    '47 M · Type 2 diabetes · +91 98307 44120',
    'You advised on 25 Aug: “Come back in 2 weeks with fasting sugar.”',
    '23 days overdue',
    ['Call', 'Remind'],
    booked: false,
    conditions: ['Type 2 diabetes'],
  ),
  _Fu(
    'Shreya Basu',
    'Not booked',
    MP.amberSoft,
    MP.amber,
    '33 F · Hypothyroidism · +91 90620 18834',
    'You advised on 14 Aug: “Repeat TSH after 4 weeks.”',
    '17 days overdue',
    ['Remind', 'Book'],
    booked: false,
    conditions: ['Hypothyroidism'],
  ),
];

const _thisWeek = [
  _Fu(
    'Moumita Roy',
    'Booked',
    MP.greenSoft,
    MP.green,
    '41 F · Cardiology review · +91 97480 62215',
    'You advised on 2 Sep: “Review after Dr. Mitra’s ECG.”',
    'Today, 11:00 AM · Salt Lake',
    ['View'],
    booked: true,
    conditions: ['Cardiology'],
  ),
  _Fu(
    'Amit Pal',
    'Booked',
    MP.greenSoft,
    MP.green,
    '55 M · Diabetes, CKD · +91 98303 11942',
    'You advised on 24 Sep: “Come fasting on Friday for KFT.”',
    'Fri, 2 Oct, 9:30 AM · Salt Lake',
    ['View'],
    booked: true,
    conditions: ['Type 2 diabetes', 'CKD'],
  ),
  _Fu(
    'Rina Dutta',
    'Reports in',
    MP.primarySoft,
    MP.primary,
    '44 F · Hypertension · +91 94330 27615',
    'You advised on 30 Sep: “Review with lipid profile and KFT.”',
    'Due Mon, 5 Oct',
    ['Remind', 'Book'],
    booked: false,
    conditions: ['Hypertension'],
  ),
  _Fu(
    'Tapas Kar',
    'Not booked',
    MP.amberSoft,
    MP.amber,
    '63 M · Hypertension, T2DM · +91 98312 60457',
    'You advised on 30 Sep: “BP check in one week.”',
    'Due Tue, 6 Oct',
    ['Remind', 'Book'],
    booked: false,
    conditions: ['Hypertension', 'Type 2 diabetes'],
  ),
];

const _tabs = ['All due · 35', 'Not booked · 18', 'Booked · 17'];
const _locations = [
  'All locations',
  'City Care Clinic · Salt Lake',
  'City Care · New Town',
  'Sen Diabetes Chamber · Gariahat',
];
const _conditions = ['All conditions', 'Type 2 diabetes', 'Hypertension', 'Hypothyroidism', 'Cardiology', 'CKD'];

class _DoctorFollowupsScreenState extends State<DoctorFollowupsScreen> with LiveData {
  int _tab = 0;
  String _loc = _locations.first;
  String _cond = _conditions.first;
  final _busy = ValueNotifier(false);

  /// Live filter values (null = all) and the picker options.
  String? _locId;
  String? _condLive;
  List<(String, String)>? _locOptions; // (id, name)
  List<String> _condOptions = const [];
  int _daysBefore = 3;

  @override
  Future<Object?> fetch() async {
    final res = await Future.wait([
      Api.I.get('/api/follow-ups', query: {'doctorId': 'me', 'locationId': _locId, 'condition': _condLive}),
      if (_locOptions == null) Api.I.get('/api/doctor/locations'),
      if (_locOptions == null) Api.I.get('/api/doctor/profile').catchError((_) => null),
    ]);
    final fu = (res[0] as Map).cast<String, dynamic>();
    if (_locOptions == null) {
      _locOptions = [
        for (final dl in res[1] as List? ?? const [])
          if ((dl as Map)['locationId'] is Map)
            ((dl['locationId'] as Map)['id'] as String? ?? '', (dl['locationId'] as Map)['name'] as String? ?? ''),
      ];
      final days = ((res[2] as Map?)?['followUpReminder'] as Map?)?['daysBefore'];
      if (days is num) _daysBefore = days.toInt();
    }
    if (_condLive == null) {
      _condOptions = {
        for (final m in fu.list('items'))
          for (final c in (m.obj('patient')['conditions'] as List? ?? const [])) '$c',
      }.toList()
        ..sort();
    }
    return fu;
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  List<_Fu> _liveRows(String group) => [
    for (final m in data!.list('items'))
      if (m['group'] == group) _Fu.fromApi(m),
  ].where(_showTab).toList();

  bool _showTab(_Fu r) {
    if (_tab == 1 && r.booked) return false;
    if (_tab == 2 && !r.booked) return false;
    return true;
  }

  List<String> get _tabLabels {
    final d = data;
    if (d == null) return _tabs;
    final c = d.obj('counts');
    return ['All due · ${c.numOr('all')}', 'Not booked · ${c.numOr('notBooked')}', 'Booked · ${c.numOr('booked')}'];
  }

  String get _locLabel {
    if (_locId == null) return _locations.first;
    for (final o in _locOptions ?? const <(String, String)>[]) {
      if (o.$1 == _locId) return o.$2;
    }
    return _locations.first;
  }

  bool _show(_Fu r) {
    if (_tab == 1 && r.booked) return false;
    if (_tab == 2 && !r.booked) return false;
    // Every follow-up listed here was advised at City Care Clinic · Salt Lake.
    if (_loc != _locations[0] && _loc != _locations[1]) return false;
    if (_cond != _conditions.first && !r.conditions.contains(_cond)) return false;
    return true;
  }

  Future<void> _pickLocation() async {
    if (isLive) {
      final opts = [_locations.first, for (final o in _locOptions ?? const <(String, String)>[]) o.$2];
      final v = await D1Picker.show(context, title: 'Location', options: opts, value: _locLabel);
      if (v == null || !mounted) return;
      String? id;
      for (final o in _locOptions ?? const <(String, String)>[]) {
        if (o.$2 == v) id = o.$1;
      }
      if (id == _locId) return;
      setState(() => _locId = id);
      reload(quiet: true);
      return;
    }
    final v = await D1Picker.show(context, title: 'Location', options: _locations, value: _loc);
    if (v != null && mounted) setState(() => _loc = v);
  }

  Future<void> _pickCondition() async {
    if (isLive) {
      final v = await D1Picker.show(context, title: 'Condition', options: [_conditions.first, ..._condOptions], value: _condLive ?? _conditions.first);
      if (v == null || !mounted) return;
      final c = v == _conditions.first ? null : v;
      if (c == _condLive) return;
      setState(() => _condLive = c);
      reload(quiet: true);
      return;
    }
    final v = await D1Picker.show(context, title: 'Condition', options: _conditions, value: _cond);
    if (v != null && mounted) setState(() => _cond = v);
  }

  Future<void> _act(String action, _Fu r) async {
    if (!isLive) {
      switch (action) {
        case 'Call':
          toast(context, 'Calling ${r.name}…');
        case 'Remind':
          toast(context, 'Reminder sent to ${r.name}');
        default: // Book, View
          Nav.go(context, 'Appointments-Manage');
      }
      return;
    }
    switch (action) {
      case 'Call':
        await d1Call(context, r.phone, r.name);
      case 'Remind':
        final ok = await runAction(context, () => Api.I.post('/api/follow-ups/${r.id}/remind'), busy: _busy);
        if (ok == null || !mounted) return;
        toast(context, 'Reminder sent to ${r.name}');
        reload(quiet: true);
      default: // Book, View
        await Nav.go(context, 'Appointments-Manage', args: {
          'patientId': r.patientId,
          'followUpId': r.id,
          if (r.appointmentId != null) 'appointmentId': r.appointmentId,
        });
        if (mounted) reload(quiet: true);
    }
  }

  Future<void> _remindAll(List<_Fu> rows) async {
    final ids = [for (final r in rows) if (r.remindable && r.id != null) r.id!];
    if (ids.isEmpty) return;
    final res = await runAction(context, () => Api.I.post('/api/follow-ups/remind', {'ids': ids}), busy: _busy);
    if (res == null || !mounted) return;
    final n = res is Map && res['reminded'] is num ? (res['reminded'] as num).toInt() : ids.length;
    toast(context, n == 0 ? 'No reminders to send' : 'Reminders sent to ${d1Count(n, 'patient')}');
    reload(quiet: true);
  }

  void _openPatient(_Fu r) {
    if (!isLive) {
      Nav.go(context, 'PP-Summary');
      return;
    }
    Nav.go(context, 'Patient-Profile', args: {'patientId': r.patientId});
  }

  /// "8 – 31 Oct" / "29 Oct – 6 Nov" for the later group.
  String _range(List<Map<String, dynamic>> later) {
    final days = [for (final m in later) F.date(m['dueDate'])].whereType<DateTime>().toList()..sort();
    if (days.isEmpty) return '';
    final a = days.first;
    final b = days.last;
    if (F.sameDay(a, b)) return F.dayMonth(a);
    if (a.month == b.month && a.year == b.year) return '${a.day} – ${F.dayMonth(b)}';
    return '${F.dayMonth(a)} – ${F.dayMonth(b)}';
  }

  @override
  Widget build(BuildContext context) {
    if (data != null) return _live(context);
    final placeholder = livePlaceholder();
    final overdue = _overdue.where(_show).toList();
    final week = _thisWeek.where(_show).toList();
    return MpPage(
      header: _header(context),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gap: 12,
        children: [
          if (overdue.isNotEmpty) ...[
            _SectionHead(
              'Overdue',
              '4 patients · reminders sent to 2',
              action: 'Remind all',
              onAction: () => toast(context, 'Reminders sent to 4 patients'),
            ),
            _card(overdue),
            _MoreButton('Show 2 more overdue', onTap: () => Nav.go(context, 'Report-FollowUps')),
          ],
          if (week.isNotEmpty) ...[
            _SectionHead(
              'This week',
              '9 patients · 5 not booked yet',
              action: 'Remind 5',
              onAction: () => toast(context, 'Reminders sent to 5 patients'),
            ),
            _card(week),
            _MoreButton('Show 5 more this week', onTap: () => Nav.go(context, 'Appointments')),
          ],
          if (overdue.isEmpty && week.isEmpty)
            MpCard(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No follow-ups match these filters.',
                textAlign: TextAlign.center,
                style: tx(15, c: MP.ink2, h: 1.45),
              ),
            ),
          const _SectionHead('Later this month', '22 patients'),
          _laterCard('8 – 31 Oct', 3),
        ],
      ),
      bottom: _bottom(context),
    );
  }

  /// The same page from live data.
  Widget _live(BuildContext context) {
    final overdue = _liveRows('overdue');
    final week = _liveRows('this_week');
    final laterItems = [
      for (final m in data!.list('items'))
        if (m['group'] == 'later' && _showTab(_Fu.fromApi(m))) m,
    ];
    final reminded = overdue.where((r) => r.reminders > 0).length;
    final overdueOpen = overdue.where((r) => r.remindable).length;
    final weekOpen = week.where((r) => r.remindable).length;
    return MpPage(
      header: _header(context),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gap: 12,
        children: [
          if (overdue.isNotEmpty) ...[
            _SectionHead(
              'Overdue',
              [d1Count(overdue.length, 'patient'), if (reminded > 0) 'reminders sent to $reminded'].join(' · '),
              action: overdueOpen > 0 ? 'Remind all' : null,
              onAction: () => _remindAll(overdue),
            ),
            _card(overdue),
          ],
          if (week.isNotEmpty) ...[
            _SectionHead(
              'This week',
              [d1Count(week.length, 'patient'), if (weekOpen > 0) '$weekOpen not booked yet'].join(' · '),
              action: weekOpen > 0 ? 'Remind $weekOpen' : null,
              onAction: () => _remindAll(week),
            ),
            _card(week),
          ],
          if (overdue.isEmpty && week.isEmpty && laterItems.isEmpty)
            MpCard(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No follow-ups match these filters.',
                textAlign: TextAlign.center,
                style: tx(15, c: MP.ink2, h: 1.45),
              ),
            ),
          if (laterItems.isNotEmpty) ...[
            _SectionHead('Later this month', d1Count(laterItems.length, 'patient')),
            _laterCard(_range(laterItems), _daysBefore),
          ],
        ],
      ),
      bottom: _bottom(context),
    );
  }

  Widget _laterCard(String range, int daysBefore) {
    return MpCard(
      onTap: () => Nav.go(context, 'Appointments'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(range, style: tx(15, w: w700)),
                const Gap(2),
                Text('Reminders go out automatically ${d1Count(daysBefore, 'day')} before', style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
        ],
      ),
    );
  }

  Widget _bottom(BuildContext context) {
    return MpBottomBar(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: MpButton(
        'Schedule a follow-up',
        icon: I.plus,
        iconStroke: 1.75,
        onTap: () => Nav.go(context, 'Appointments'),
      ),
    );
  }

  /// White header: title row, status tabs and the two filter buttons.
  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                  const Gap(4),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Follow-ups',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(20, w: w700, h: 1.25),
                        ),
                        const Gap(1),
                        Text(
                          'Patients you asked to come back',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(13, c: MP.ink2),
                        ),
                      ],
                    ),
                  ),
                  const Gap(4),
                  MpIconButton(
                    I.search,
                    label: 'Search follow-ups',
                    iconSize: 20,
                    onTap: () => Nav.go(context, 'Doctor-Patients-Search'),
                  ),
                ],
              ),
            ),
          ),
          const Gap(12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _Tabs(index: _tab, labels: _tabLabels, onChanged: (i) => setState(() => _tab = i)),
          ),
          const Gap(12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (isLive)
                  _FilterButton(_locLabel, active: _locId != null, onTap: _pickLocation)
                else
                  _FilterButton(_loc, active: _loc != _locations.first, onTap: _pickLocation),
                const Gap(8),
                if (isLive)
                  _FilterButton(_condLive ?? _conditions.first, active: _condLive != null, onTap: _pickCondition)
                else
                  _FilterButton(_cond, active: _cond != _conditions.first, onTap: _pickCondition),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<_Fu> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < rows.length; i++) _row(rows[i], first: i == 0)],
      ),
    );
  }

  Widget _row(_Fu r, {required bool first}) {
    return Tap(
      onTap: () => _openPatient(r),
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
                Expanded(child: Text(r.name, style: tx(15, w: w700))),
                const Gap(10),
                D1Pill(r.status, bg: r.bg, fg: r.fg),
              ],
            ),
            const Gap(6),
            Text(r.meta, style: tx(13, c: MP.ink2, h: 1.4)),
            const Gap(6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(10)),
              child: Text(r.advice, style: tx(13, h: 1.45)),
            ),
            const Gap(6),
            Row(
              children: [
                Expanded(child: Text(r.when, style: tx(13, w: w600, c: MP.ink2))),
                const Gap(8),
                for (var i = 0; i < r.actions.length; i++) ...[
                  if (i > 0) const Gap(16),
                  MpHitSlop(child: Tap(
                    onTap: () => _act(r.actions[i], r),
                    radius: 6,
                    child: Text(r.actions[i], style: tx(14, w: w600, c: MP.primary)),
                  )),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Status tabs: #F1F4F9 track (padding 4, radius 16); selected tab white,
/// radius 12, hairline shadow, 600 #111827; others 500 #545E72.
class _Tabs extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _Tabs({required this.index, required this.onChanged, this.labels = _tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: MpHitSlop(child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? MP.white : MP.white.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: i == index ? MPShadow.hairline : null,
                    ),
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(14, w: i == index ? w600 : w500, c: i == index ? MP.ink : MP.ink2),
                    ),
                  ),
                ),
              )),
            ),
        ],
      ),
    );
  }
}

/// 36px outlined filter button (radius 999, 14 / 600). Tonal when a filter is set.
class _FilterButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterButton(this.label, {required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Tap(
        onTap: onTap,
        radius: 999,
        color: active ? MP.primarySoft : MP.white,
        border: active ? MP.primary : MP.lineStrong,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(label, style: tx(14, w: w600, c: active ? MP.primary : MP.ink))],
          ),
        ),
      ),
    );
  }
}

/// Section heading (17 / 700 + 13px count line) with an optional pill action.
class _SectionHead extends StatelessWidget {
  final String title;
  final String sub;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHead(this.title, this.sub, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title, style: tx(17, w: w700)), const Gap(2), Text(sub, style: tx(13, c: MP.ink3))],
            ),
          ),
          if (action != null) ...[
            const Gap(8),
            SizedBox(
              height: 32,
              child: MpHitSlop(child: Tap(
                onTap: onAction,
                radius: 999,
                color: MP.primarySoft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(action!, style: tx(13, w: w600, c: MP.primary))],
                  ),
                ),
              )),
            ),
          ],
        ],
      ),
    );
  }
}

/// 44px transparent "Show N more" button (15 / 600 #003399).
class _MoreButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MoreButton(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      child: SizedBox(height: 44, child: Center(child: Text(label, style: tx(15, w: w600, c: MP.primary)))),
    );
  }
}

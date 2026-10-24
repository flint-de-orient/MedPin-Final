import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'queue_select.dart';
import '../../widgets/i18n.dart';
import '../../widgets/call_next.dart';
import '../../widgets/fee_actions.dart';
import '../../widgets/visit_status.dart';
import '../../data/session.dart';

/// Design: Queue-List.dc.html — "Patient queue".
/// Live data (args {'locationId'}; default: today's chosen / first open
/// location): GET /api/queue?locationId, refreshed every 15 s.
class QueueListScreen extends StatefulWidget {
  /// Index into [D1Location.all] of the location whose queue is shown.
  final int location;
  const QueueListScreen({super.key, this.location = 0});

  @override
  State<QueueListScreen> createState() => _QueueListScreenState();
}

enum _Kind { consult, waiting, booked, done, missed }

/// One patient in the queue.
class _Q {
  final _Kind kind;
  final String token;
  final String name;
  final String meta;
  final String time;
  final bool vitals;
  final int docs;
  final bool ai;
  final bool next;

  /// Waiting longer than usual (time shown in amber, 600).
  final bool long;
  final String? button;
  final MpBtn buttonKind;

  /// Live: the appointment and patient ids.
  final String? id;
  final String? patientId;

  /// Live: the visit fee (paid / to collect / refund due), null in the design preview.
  final VisitFee? fee;
  const _Q(
    this.kind,
    this.token,
    this.name,
    this.meta,
    this.time, {
    required this.vitals,
    required this.docs,
    this.ai = false,
    this.next = false,
    this.long = false,
    this.button,
    this.buttonKind = MpBtn.tonal,
    this.id,
    this.patientId,
    this.fee,
  });

  /// A queue row from GET /api/queue.
  factory _Q.fromApi(Map<String, dynamic> m) {
    final kind = switch (m.str('status')) {
      'in_consultation' => _Kind.consult,
      'waiting' => _Kind.waiting,
      'completed' => _Kind.done,
      'missed' => _Kind.missed,
      _ => _Kind.booked,
    };
    final p = m.obj('patient');
    final conditions = [for (final c in (p['conditions'] as List? ?? const [])) '$c'];
    final visit = switch (m.str('visitType')) {
      'new' => 'New',
      'follow_up' => 'Follow-up',
      'report_review' => 'Review reports',
      _ => '',
    };
    // Why they came today first (walk-in complaint / booking reason); their conditions when none was given.
    final about = m.str('reason').trim().isNotEmpty ? m.str('reason').trim() : conditions.join(', ');
    final meta = [d1AgeSex(p), visit, about].where((x) => x.isNotEmpty).join(' · ');
    String at(String k) {
      final d = F.date(m[k]);
      return d == null ? '' : F.time(d);
    }

    final mins = m['consultMin'] is num ? (m['consultMin'] as num).round() : null;
    final time = switch (kind) {
      _Kind.consult => [if (at('consultStartedAt').isNotEmpty) 'Started ${at('consultStartedAt')}', if (mins != null) '$mins min'].join(' · '),
      _Kind.waiting => [
          // Called ("Call next"): when, so nobody is called twice by mistake.
          if (F.date(m['calledAt']) != null) 'Called ${F.time(F.date(m['calledAt'])!)}',
          m['waitingMin'] is num ? 'Waiting ${(m['waitingMin'] as num).round()} min' : 'Waiting',
        ].join(' · '),
      _Kind.done => [if (at('completedAt').isNotEmpty) 'Done ${at('completedAt')}' else 'Done', if (mins != null) '$mins min'].join(' · '),
      _Kind.missed => at('startAt').isEmpty ? 'Missed' : 'Missed · booked for ${at('startAt')}',
      _Kind.booked => at('startAt').isEmpty ? 'Walk-in' : 'Booked for ${at('startAt')}',
    };
    return _Q(
      kind,
      m.str('token', '–'),
      p.str('name'),
      meta,
      time,
      vitals: m['hasVitals'] == true,
      docs: m.numOr('documents').toInt(),
      ai: m['aiBrief'] == true,
      next: m['isNext'] == true,
      long: m['longWait'] == true,
      button: switch (kind) {
        _Kind.consult => 'Resume',
        _Kind.waiting => 'Start consultation',
        _Kind.done => 'View prescription',
        _ => null,
      },
      buttonKind: kind == _Kind.done ? MpBtn.secondary : MpBtn.tonal,
      id: m.str('id'),
      patientId: m.str('patientId', p.str('id')),
      fee: VisitFee.of(m),
    );
  }
}

class _Group {
  final String title;
  final String count;
  final List<_Q> rows;
  final bool hero;
  final String? more;
  const _Group(this.title, this.count, this.rows, {this.hero = false, this.more});
}

// value, unit, label, colour
const _stats = [
  ('3', '', 'Waiting', MP.amber),
  ('1', '', 'In consult', MP.ink),
  ('6', '', 'Completed', MP.ink),
  ('14', ' min', 'Avg wait', MP.ink),
];

const _filters = ['All · 12', 'Waiting · 3', 'In consultation · 1', 'Completed · 6'];

const _groups = [
  _Group('In consultation', '1', hero: true, [
    _Q(
      _Kind.consult,
      '04',
      'Priya Sharma',
      '29 F · Follow-up · Diabetes',
      'Started 9:14 AM · 11 min',
      vitals: true,
      docs: 2,
      ai: true,
      button: 'Resume',
    ),
  ]),
  _Group('Waiting', '3', [
    _Q(
      _Kind.waiting,
      '05',
      'Rahul Das',
      '45 M · New · High BP',
      'Waiting 22 min',
      vitals: true,
      docs: 0,
      long: true,
      next: true,
      button: 'Start consultation',
    ),
    _Q(
      _Kind.waiting,
      '06',
      'Aisha Khan',
      '52 F · Follow-up · Thyroid',
      'Waiting 15 min',
      vitals: true,
      docs: 1,
      ai: true,
      button: 'Start consultation',
    ),
    _Q(
      _Kind.waiting,
      '07',
      'Sujit Mondal',
      '37 M · New · Fever, cough',
      'Waiting 6 min',
      vitals: false,
      docs: 0,
      button: 'Start consultation',
    ),
  ]),
  _Group('Not arrived yet', '2', [
    _Q(
      _Kind.booked,
      '08',
      'Moumita Roy',
      '41 F · Follow-up · Cardiology',
      'Booked for 11:00 AM',
      vitals: false,
      docs: 3,
      ai: true,
    ),
    _Q(
      _Kind.booked,
      '09',
      'Amit Pal',
      '55 M · Follow-up · Diabetes, CKD',
      'Booked for 11:30 AM',
      vitals: false,
      docs: 1,
      ai: true,
    ),
  ]),
  _Group('Completed', '6', more: 'Show 4 more', [
    _Q(
      _Kind.done,
      '03',
      'Debasish Bose',
      '62 M · Follow-up · Diabetes',
      'Done 9:10 AM · 9 min',
      vitals: true,
      docs: 1,
      button: 'View prescription',
      buttonKind: MpBtn.secondary,
    ),
    _Q(
      _Kind.done,
      '02',
      'Farhana Islam',
      '34 F · Review reports · Anaemia',
      'Done 8:58 AM · 12 min',
      vitals: true,
      docs: 2,
      button: 'View prescription',
      buttonKind: MpBtn.secondary,
    ),
  ]),
];

/// Dashed 9px circle ("no vitals" / "no documents"): butt caps like the design.
const _dashed = '<circle cx="12" cy="12" r="9" stroke-dasharray="3 3" stroke-linecap="butt" stroke-linejoin="miter"/>';

(String, Color, Color) _status(_Kind k) => switch (k) {
  _Kind.consult => ('With doctor', MP.primarySoft, MP.primary),
  _Kind.waiting => ('Waiting', MP.amberSoft, MP.amber),
  _Kind.booked => ('Not arrived', MP.fill, MP.ink2),
  _Kind.done => ('Completed', MP.greenSoft, MP.green),
  _Kind.missed => ('Missed', MP.redSoft, MP.red),
};

class _QueueListScreenState extends State<QueueListScreen> with LiveData {
  late int _loc = widget.location;
  int _filter = 0;

  /// Live: the location shown, and the Queue-Select cards (for its header).
  String? _locId;
  Map<String, dynamic>? _locs;
  DateTime? _locsAt;
  Timer? _clock;

  @override
  Duration? get refreshEvery => const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    // Keeps "Updated Ns ago" current.
    if (isLive) _clock = Timer.periodic(const Duration(seconds: 1), (_) => mounted && data != null ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    final argId = (await d1Args(this))['locationId'] as String?;
    // The places (with today's counts) are fetched again each minute, so the
    // "patients today at …" hint and the default place stay right.
    final stale = _locsAt == null || DateTime.now().difference(_locsAt!) > const Duration(minutes: 1);
    final locs = _locs == null || stale ? await d1QueueLocations() : _locs!;
    if (!identical(locs, _locs)) _locsAt = DateTime.now();
    _locs = locs;
    var id = _locId ?? argId;
    if (id == null || id.isEmpty) {
      final items = locs.list('items');
      final def = locs.str('defaultLocationId');
      Map<String, dynamic>? pick;
      int n(Map<String, dynamic> m, String k) => m.numOr(k).round();
      // Where the patients are: someone arrived or with the doctor, then the place
      // open now with visits, the place chosen for today, the next place with
      // visits still to come today (an evening clinic seen at night), then any open one.
      for (final m in items) {
        if (n(m, 'waiting') + n(m, 'inConsult') > 0) pick ??= m;
      }
      for (final m in items) {
        if (m['openNow'] == true && n(m, 'pending') > 0) pick ??= m;
      }
      for (final m in items) {
        if (m.str('locationId') == def) pick ??= m;
      }
      for (final m in items) {
        if (n(m, 'pending') > 0) pick ??= m;
      }
      for (final m in items) {
        if (m['openNow'] == true) pick ??= m;
      }
      for (final m in items) {
        if (m['closedReason'] == null) pick ??= m;
      }
      pick ??= items.firstOrNull;
      id = pick?.str('locationId');
    }
    _locId = id;
    final queue = id == null ? const {'stats': {}, 'items': []} : await Api.I.get('/api/queue', query: {'locationId': id});
    return {'queue': queue};
  }

  Map<String, dynamic> get _queue => data!.obj('queue');

  /// Other places with patients still to be seen today (shown under an empty queue).
  List<Map<String, dynamic>> get _elsewhere => data == null
      ? const []
      : [for (final m in _locs?.list('items') ?? const <Map<String, dynamic>>[]) if (m.str('locationId') != _locId && m.numOr('pending') > 0) m];

  D1Location get _location {
    if (data == null) return D1Location.all[_loc];
    for (final m in _locs?.list('items') ?? const <Map<String, dynamic>>[]) {
      if (m.str('locationId') == _locId) return D1Location.fromApi(m);
    }
    return const D1Location(name: 'No consulting location', a11y: 'No consulting location', kind: '', hours: '');
  }

  List<(String, String, String, Color)> get _liveStats {
    if (data == null) return _stats;
    final s = _queue.obj('stats');
    final avg = s['avgWaitMin'] is num ? (s['avgWaitMin'] as num).round() : null;
    return [
      ('${s.numOr('waiting')}', '', 'Waiting', MP.amber),
      ('${s.numOr('inConsultation')}', '', 'In consult', MP.ink),
      ('${s.numOr('completed')}', '', 'Completed', MP.ink),
      (avg == null ? '–' : '$avg', avg == null ? '' : ' min', 'Avg wait', MP.ink),
    ];
  }

  List<String> get _liveFilters {
    if (data == null) return _filters;
    final s = _queue.obj('stats');
    return [
      'All · ${s.numOr('all')}',
      'Waiting · ${s.numOr('waiting')}',
      'In consultation · ${s.numOr('inConsultation')}',
      'Completed · ${s.numOr('completed')}',
    ];
  }

  /// In consultation, waiting, not arrived, completed (latest first), missed.
  List<_Group> get _liveGroups {
    if (data == null) return _groups;
    final rows = [for (final m in _queue.list('items')) _Q.fromApi(m)];
    final done = _queue.list('items').where((m) => m['status'] == 'completed').toList()
      ..sort((a, b) => b.str('completedAt').compareTo(a.str('completedAt')));
    List<_Q> of(_Kind k) => rows.where((r) => r.kind == k).toList();
    _Group g(String title, List<_Q> rows, {bool hero = false}) => _Group(title, '${rows.length}', rows, hero: hero);
    return [
      g('In consultation', of(_Kind.consult), hero: true),
      g('Waiting', of(_Kind.waiting)),
      g('Not arrived yet', of(_Kind.booked)),
      g('Completed', [for (final m in done) _Q.fromApi(m)]),
      g('Missed', of(_Kind.missed)),
    ];
  }

  String get _updatedLine {
    final at = loadedAt;
    if (data == null || at == null) return 'Tue, 29 Sep · Updated 4s ago';
    final s = DateTime.now().difference(at).inSeconds;
    return '${d1Day(DateTime.now())} · Updated ${s < 60 ? '${s < 0 ? 0 : s}s' : '${s ~/ 60} min'} ago';
  }

  Future<void> _changeLocation() async {
    if (!isLive) {
      final r = await openSheet<int>(context, (_) => QueueSelectSheet(initial: _loc, pick: true));
      if (r != null && mounted) setState(() => _loc = r);
      return;
    }
    final r = await openSheet<Object>(context, (_) => QueueSelectSheet(initialId: _locId, pick: true));
    if (r is! String || !mounted || r == _locId) return;
    setState(() {
      _locId = r;
      _locs = null;
      _filter = 0;
      data = null;
    });
    reload();
  }

  Future<void> _onButton(_Q r) async {
    if (!isLive) {
      if (r.kind == _Kind.done) {
        Nav.go(context, 'Prescriptions');
      } else {
        Nav.go(context, 'Consult-Page');
      }
      return;
    }
    if (r.kind == _Kind.done) {
      await Nav.go(context, 'Prescriptions', args: {'patientId': r.patientId, 'appointmentId': r.id});
    } else {
      // Consult-Page starts or resumes the consultation itself.
      await Nav.go(context, 'Consult-Page', args: {'appointmentId': r.id, 'patientId': r.patientId});
    }
    if (mounted) reload(quiet: true);
  }

  /// No front desk at this clinic (GET /api/queue hasDesk): the doctor checks patients in here.
  bool get _noDesk => data != null && _queue['hasDesk'] == false;

  /// "Call next" is on for this clinic (a setting; the queue says so).
  bool get _callNextOn => data != null && _queue['callNext'] != false;

  bool _called(_Q r) => _queue.list('items').any((m) => m.str('id') == r.id && m['calledAt'] != null);

  /// Tells the next waiting patient (or [r]) it's their turn.
  /// Tells the next waiting patient (or [r]) it's their turn.
  Future<void> _call([_Q? r]) async {
    if (await callNextPatient(context, appointmentId: r?.id, locationId: _locId) && mounted) reload(quiet: true);
  }

  List<Widget> _deskActions(_Q r) {
    final fee = r.fee;
    Widget link(String text, VoidCallback onTap) => Tap(onTap: onTap, radius: 6, child: Text(text, style: tx(14, w: w600, c: MP.primary)));
    return [
      if (_callNextOn && r.kind == _Kind.waiting && r.id != null) link(tr(context, _called(r) ? 'Call again' : 'Call in'), () => _call(r)),
      if (_noDesk && r.kind == _Kind.booked && r.id != null) link(tr(context, 'Check in'), () => _checkIn(r)),
      if (fee != null && fee.due && Session.I.can('fees') && r.kind != _Kind.missed)
        link(tr(context, 'Collect ₹#1').replaceFirst('#1', '${fee.amount}'), () async {
          if (await collectFee(context, fee, patientName: r.name) && mounted) reload(quiet: true);
        }),
      if (r.id != null && isLive && Session.I.can('fees') && const {_Kind.waiting, _Kind.consult, _Kind.done}.contains(r.kind))
        link(tr(context, 'Add charge'), () async {
          if (await addVisitCharge(context, appointmentId: r.id!) && mounted) reload(quiet: true);
        }),
      if (fee != null && fee.refundDue && Session.I.can('fees'))
        link(tr(context, 'Refund ₹#1').replaceFirst('#1', '${fee.amount}'), () async {
          if (await handBackFee(context, fee) && mounted) reload(quiet: true);
        }),
    ];
  }

  Future<void> _changeStatus(_Q r) async {
    final status = switch (r.kind) {
      _Kind.consult => 'in_consultation',
      _Kind.waiting => 'waiting',
      _Kind.done => 'completed',
      _Kind.missed => 'missed',
      _Kind.booked => 'booked',
    };
    if (await changeVisitStatus(context, appointmentId: r.id!, status: status, patientName: r.name) && mounted) reload(quiet: true);
  }

  Future<void> _checkIn(_Q r) async {
    final ok = await runAction(context, () => Api.I.post('/api/appointments/${r.id}/status', {'status': 'waiting'}));
    if (ok == null || !mounted) return;
    toast(context, tr(context, '#1 checked in').replaceFirst('#1', r.name));
    reload(quiet: true);
  }

  Future<void> _recordVitals(_Q r) async {
    if (!isLive) {
      Nav.go(context, 'Consult-Vitals');
      return;
    }
    await Nav.go(context, 'Consult-Vitals', args: {'appointmentId': r.id, 'patientId': r.patientId});
    if (mounted) reload(quiet: true);
  }

  void _openPatient(_Q r) {
    if (!isLive) {
      Nav.go(context, 'PP-Summary');
      return;
    }
    Nav.go(context, 'Patient-Profile', args: {'patientId': r.patientId});
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final all = _liveGroups;
    final filters = _liveFilters;
    final groups = [
      for (final g in switch (_filter) {
        1 => [all[1]],
        2 => [all[0]],
        3 => [all[3]],
        _ => all,
      })
        if (data == null || g.rows.isNotEmpty) g,
    ];
    return MpPage(
      header: _header(context, _location),
      body: placeholder ?? Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _statsCard()),
            const Gap(16),
            // Chips run to the right edge (design: margin-right -20px, overflow hidden).
            MpChipRow(
              gap: 8,
              children: [
                for (var i = 0; i < filters.length; i++)
                  Semantics(
                    toggled: i == _filter,
                    child: MpChip(
                      filters[i],
                      selected: i == _filter,
                      onTap: () => setState(() => _filter = i),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
              ],
            ),
            for (final g in groups) ...[
              const Gap(16),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _group(g)),
            ],
            if (groups.isEmpty) ...[
              const Gap(16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_filter == 0 ? 'No patients in this queue yet' : 'No patients here right now', style: tx(14, c: MP.ink2)),
              ),
              // Patients booked today at another place: one tap to that queue.
              for (final m in _elsewhere)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Tap(
                    onTap: () {
                      setState(() => _locId = m.str('locationId'));
                      reload();
                    },
                    radius: 8,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      tr(context, m.numOr('pending').round() == 1 ? '1 patient today at #1 · Open' : '#2 patients today at #1 · Open')
                          .replaceFirst('#1', D1Location.fromApi(m).name)
                          .replaceFirst('#2', '${m.numOr('pending').round()}'),
                      style: tx(14, w: w600, c: MP.primary),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, D1Location loc) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
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
                    child: Text(
                      'Patient queue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(20, w: w700, h: 1.25),
                    ),
                  ),
                  const Gap(4),
                  MpIconButton(
                    I.search,
                    label: 'Search the queue',
                    onTap: () => Nav.go(context, 'Doctor-Patients-Search'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'Change location. Current: ${loc.a11y}',
                  // 56px border-box button: the height wraps the Tap.
                  child: SizedBox(
                    height: 56,
                    child: Tap(
                      onTap: _changeLocation,
                      radius: 16,
                      color: MP.white,
                      border: MP.lineStrong,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Ico(I.pin, size: 20, color: MP.primary),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(loc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                                  Text(
                                    loc.hours,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tx(13, c: MP.ink2),
                                  ),
                                ],
                              ),
                            ),
                            const Gap(12),
                            Text('Change', style: tx(14, w: w600, c: MP.primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Gap(10),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle),
                    ),
                    const Gap(8),
                    Expanded(child: Text(_updatedLine, style: tx(13, c: MP.ink2))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 4-up stats strip: white, 1px border, radius 16, cells split by 1px lines.
  /// Every cell has the same two lines, so the cells (and dividers) line up.
  Widget _statsCard() {
    final stats = _liveStats;
    return Container(
      decoration: MPDeco.card(radius: 16),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(left: BorderSide(color: MP.line))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: stats[i].$1,
                        style: tx(22, w: w800, h: 1.1, c: stats[i].$4, tab: true),
                        children: [
                          if (stats[i].$2.isNotEmpty)
                            TextSpan(text: stats[i].$2, style: tx(12, w: w600, c: MP.ink3, h: 1.1, tab: true)),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                    const Gap(2),
                    // On narrow phones a label may run into the cell's own
                    // 12px right padding rather than break mid-word.
                    Text(
                      stats[i].$3,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: tx(12, c: MP.ink2, h: 1.3),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _group(_Group g) {
    final label = tx(12, w: w700, c: MP.ink3, em: 0.06);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text(g.title.toUpperCase(), style: label)),
              Text(g.count, style: tx(12, w: w700, c: MP.ink3, em: 0.06, tab: true)),
              // The waiting patients: "Call next" tells the next one it's their turn.
              // Not arrived yet: tell them the doctor is running late.
              if (g.title == 'Not arrived yet' && g.rows.isNotEmpty && isLive) ...[
                const Gap(10),
                MpButton.small('Running late', kind: MpBtn.secondary, expand: false, onTap: () => tellRunningLate(context, locationId: _locId)),
              ],
              if (g.title == 'Waiting' && g.rows.isNotEmpty && _callNextOn && isLive) ...[
                const Gap(10),
                MpButton.small('Call next', expand: false, onTap: () => _call()),
              ],
            ],
          ),
        ),
        const Gap(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: MP.white,
            borderRadius: BorderRadius.circular(24),
            border: g.hero ? Border.all(color: MP.primary, width: 1.5) : Border.all(color: MP.line),
            boxShadow: g.hero ? MPShadow.float : MPShadow.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < g.rows.length; i++) _row(g.rows[i], first: i == 0),
              if (g.more != null)
                Tap(
                  onTap: () => Nav.go(context, 'Doctor-History'),
                  radius: 0,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Text(g.more!, style: tx(14, w: w600, c: MP.primary)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(_Q r, {required bool first}) {
    final s = _status(r.kind);
    final consult = r.kind == _Kind.consult;
    final tokenFg = consult ? MP.white : MP.ink;
    final recordVitals = !r.vitals && r.kind == _Kind.waiting;
    final timeColor = r.long ? MP.amber : MP.ink2;
    return Opacity(
      opacity: r.kind == _Kind.done ? 0.85 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'Token ${r.token}',
                  excludeSemantics: true,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: consult ? MP.primary : MP.fill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('NO.', style: tx(10, w: w700, c: tokenFg, em: 0.06, h: 1)),
                        Text(r.token, style: tx(17, w: w800, c: tokenFg, h: 1.1, tab: true)),
                      ],
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Tap(
                    onTap: () => _openPatient(r),
                    radius: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                            ),
                            if (r.next) ...[
                              const Gap(8),
                              const D1Pill('NEXT', bg: MP.primary, fg: MP.white, fontSize: 11, em: 0.06),
                            ],
                          ],
                        ),
                        const Gap(2),
                        Text(r.meta, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                ),
                const Gap(12),
                // Tap the status to change it (arrived, with doctor, done, missed…).
                Tap(
                  onTap: r.id == null ? null : () => _changeStatus(r),
                  radius: 12,
                  child: D1Pill(s.$1, bg: s.$2, fg: s.$3, height: 24, padding: 10),
                ),
              ],
            ),
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                    r.vitals ? 'Vitals' : 'No vitals',
                    icon: r.vitals ? I.check : _dashed,
                    stroke: r.vitals ? 2.5 : 2,
                    ok: r.vitals,
                  ),
                  _Chip(
                    r.docs == 0 ? 'No documents' : '${r.docs} ${r.docs == 1 ? 'document' : 'documents'}',
                    icon: r.docs > 0 ? I.file : _dashed,
                    stroke: 2,
                    ok: r.docs > 0,
                  ),
                  if (r.ai) const _Chip('AI brief', icon: I.sparkle, stroke: 2, ai: true),
                  if (r.fee != null && r.fee!.status != 'free') FeeChip(r.fee!),
                ],
              ),
            ),
            // Desk work on the row: collect the fee, hand back a refund, and — in a clinic
            // without a front desk — check the patient in.
            if (_deskActions(r).isNotEmpty) ...[
              const Gap(10),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Wrap(spacing: 16, runSpacing: 8, children: _deskActions(r)),
              ),
            ],
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Row(
                children: [
                  Ico(I.clock, size: 14, color: timeColor, stroke: 2),
                  const Gap(6),
                  Expanded(child: Text(r.time, style: tx(13, w: r.long ? w600 : w400, c: timeColor, tab: true))),
                  if (recordVitals) ...[
                    const Gap(12),
                    Tap(
                      onTap: () => _recordVitals(r),
                      radius: 6,
                      child: Text('Record vitals', style: tx(14, w: w600, c: MP.primary)),
                    ),
                  ],
                ],
              ),
            ),
            if (r.button != null) ...[
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: MpButton.small(r.button!, kind: r.buttonKind, onTap: () => _onButton(r)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 28px readiness chip (padding 0 10 0 8, radius 999, 13 / 600, 14px icon).
class _Chip extends StatelessWidget {
  final String label;
  final String icon;
  final double stroke;
  final bool ok;
  final bool ai;
  const _Chip(this.label, {required this.icon, required this.stroke, this.ok = false, this.ai = false});

  @override
  Widget build(BuildContext context) {
    final bg = ai ? MP.primarySoft : (ok ? MP.greenSoft : MP.fill);
    final fg = ai ? MP.primary : (ok ? MP.green : MP.ink2);
    return Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Ico(icon, size: 14, color: fg, stroke: stroke),
          const Gap(5),
          Text(label, style: tx(13, w: w600, c: fg)),
        ],
      ),
    );
  }
}

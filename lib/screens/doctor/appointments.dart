import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'appointments_manage.dart';
import 'common_d7.dart';
import '../../widgets/i18n.dart';
import 'visits_to_move.dart';
import '../../widgets/visit_status.dart';

/// Design: Appointments.dc.html — "Appointments".
/// Live data: GET /api/appointments?view=today|upcoming|past and
/// GET /api/appointment-requests (pending + declined). Manage / assign open
/// the Appointments-Manage sheet; decline: POST /api/appointment-requests/:id/decline.
class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

/// A booking request that has no slot yet.
class _Request {
  const _Request(this.initials, this.name, this.when, this.reason, this.pref, {this.id, this.patientId, this.photo});
  final String initials;
  final String name;
  final String when;
  final String reason;
  final String pref;

  /// Live record ids (null in the design preview).
  final String? id;
  final String? patientId;

  /// The patient's profile photo (live data only).
  final String? photo;
}

class _Appt {
  _Appt(this.day, this.time, this.name, this.where, this.status, {this.id, this.at, this.raw});
  String day;
  String time;
  final String name;
  final String where;
  final String status;

  /// Live appointment id and start (null in the design preview).
  final String? id;
  final DateTime? at;

  /// The appointment as the server sent it (status, patient) — live only.
  final Map<String, dynamic>? raw;
}

typedef _SheetResult = ({String action, String day, String time});

class _AppointmentsScreenState extends State<AppointmentsScreen> with LiveData {
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/appointments', query: {'view': 'today'}),
      Api.I.get('/api/appointments', query: {'view': 'upcoming'}),
      Api.I.get('/api/appointments', query: {'view': 'past'}),
      Api.I.get('/api/appointment-requests', query: {'status': 'pending'}),
      Api.I.get('/api/appointment-requests', query: {'status': 'declined'}),
      Api.I.get('/api/appointments/to-move').catchError((_) => null),
    ]);
    return {'today': r[0], 'upcoming': r[1], 'past': r[2], 'requests': r[3], 'declined': r[4], 'toMove': r[5]};
  }

  /// Visits on a day the doctor can't see them (leave, a closure, changed hours): move them all.
  Widget _toMoveCard() {
    final items = data?.obj('toMove').list('items') ?? const <Map<String, dynamic>>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return MpCard(
      onTap: () async {
        final moved = await openSheet<bool>(context, (_) => VisitsToMoveSheet(items: items));
        if (moved == true && mounted) reload(quiet: true);
      },
      child: Row(
        children: [
          const MpIconTile(I.calendar, size: 40, iconSize: 20, radius: 12),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, '#1 visits need a new time').replaceFirst('#1', '${items.length}'), style: tx(16, w: w700)),
                const Gap(2),
                Text('Doctor on leave, a closure or changed hours. Move them together.', style: tx(13, c: MP.ink2, h: 1.35)),
              ],
            ),
          ),
          const Ico(I.chevronRight, size: 18, color: MP.ink3),
        ],
      ),
    );
  }

  static const _statusLabels = {
    'booked': 'Booked',
    'confirmed': 'Confirmed',
    'waiting': 'Checked in',
    'in_consultation': 'In consultation',
    'completed': 'Completed',
    'missed': 'Missed',
    'cancelled': 'Cancelled',
    'rescheduled': 'Rescheduled',
  };

  /// "Today · Tue 29 Sep", "Wed 30 Sep".
  static String _dayLabel(DateTime d) {
    final label = d7DayShort(d);
    return F.sameDay(d, DateTime.now()) ? 'Today · $label' : label;
  }

  static List<Map<String, dynamic>> _rows(Object? v) => [
    for (final x in (v as List? ?? const [])) (x as Map).cast<String, dynamic>(),
  ];

  static _Appt _apptFrom(Map<String, dynamic> a) {
    final at = F.date(a['startAt']) ?? DateTime.now();
    final doctor = a.obj('doctor').str('name');
    final where = a.obj('location').str('name');
    return _Appt(
      _dayLabel(at),
      F.time(at),
      a.obj('patient').str('name', 'Patient'),
      [if (doctor.isNotEmpty) F.doctorShort(doctor), if (where.isNotEmpty) where].join(' · '),
      _statusLabels[a.str('status')] ?? a.str('status'),
      id: a.str('id'),
      at: at,
      raw: a,
    );
  }

  static _Request _requestFrom(Map<String, dynamic> q) {
    final p = q['patientId'] is Map ? q.obj('patientId') : const <String, dynamic>{};
    final name = p.str('name', 'Patient');
    final at = F.date(q['createdAt']);
    return _Request(
      F.initials(name),
      name,
      at == null ? '' : 'Asked ${d7DayTime(at)}',
      q.str('reason', 'Visit request'),
      q.str('preferredTime', 'Any time'),
      id: q.str('id'),
      patientId: p['id'] == null ? null : p.str('id'),
      photo: q.str('patientPhoto').isEmpty ? null : q.str('patientPhoto'),
    );
  }

  static (String, String, String, String) _declinedFrom(Map<String, dynamic> q) {
    final r = _requestFrom(q);
    final at = F.date(q['handledAt'] ?? q['updatedAt']);
    final why = q.str('declineReason');
    return (r.initials, r.name, at == null ? 'Declined' : 'Declined ${d7DayTime(at)}', why.isEmpty ? r.reason : why);
  }

  Map<String, dynamic>? _mappedFrom;
  List<_Appt> _liveToday = const [], _liveUpcoming = const [], _livePast = const [];
  List<_Request> _liveRequests = const [];
  List<(String, String, String, String)> _liveDeclined = const [];

  void _map() {
    final d = data;
    if (d == null || identical(d, _mappedFrom)) return;
    _mappedFrom = d;
    _liveToday = [for (final a in d.obj('today').list('items')) _apptFrom(a)];
    _liveUpcoming = [for (final a in d.obj('upcoming').list('items')) _apptFrom(a)];
    _livePast = [for (final a in d.obj('past').list('items')) _apptFrom(a)];
    _liveRequests = [for (final q in _rows(d['requests'])) _requestFrom(q)];
    _liveDeclined = [for (final q in _rows(d['declined'])) _declinedFrom(q)];
  }

  List<_Request> get _requests {
    _map();
    return data == null ? _sampleRequests : _liveRequests;
  }

  List<(String, String, String, String)> get _declined {
    _map();
    return data == null ? _sampleDeclined : _liveDeclined;
  }

  List<_Appt> get _appts {
    _map();
    if (data == null) return _sampleAppts;
    return switch (_range) {
      0 => _liveToday,
      1 => [..._liveToday, ..._liveUpcoming],
      _ => _livePast,
    };
  }

  /// Day sections of the live view, in list order (past: newest first).
  List<String> get _liveDays {
    final out = <String>[];
    for (final a in _appts) {
      if (!out.contains(a.day)) out.add(a.day);
    }
    return out;
  }
  /// Day sections, in order (the manage sheet offers Wed 30 – Sat 3 Oct).
  static const _days = ['Today · Tue 29 Sep', 'Wed 30 Sep', 'Thu 1 Oct', 'Fri 2 Oct', 'Sat 3 Oct'];

  /// Status pill: fill, text (renderVals() ST).
  static const _tones = {
    'Checked in': (MP.primarySoft, MP.primary),
    'Confirmed': (MP.greenSoft, MP.green),
    'Booked': (MP.fill, MP.ink2),
  };

  /// Oldest first. The card shows two until "View all" (badge: 3 waiting).
  final _sampleRequests = <_Request>[
    const _Request(
      'SM',
      'Sujit Mondal',
      'Asked yesterday, 6:40 PM',
      'New consultation: fever and body ache for 3 days',
      'Any morning this week',
    ),
    const _Request(
      'FI',
      'Farhana Islam',
      'Asked today, 8:15 AM',
      'Follow-up on her haemoglobin report',
      'Thu or Fri, after 5 PM',
    ),
    const _Request(
      'TB',
      'Tanmoy Banerjee',
      'Asked today, 9:05 AM',
      'Review of thyroid medicines after his latest report',
      'Saturday morning',
    ),
  ];

  /// Declined requests: initials, name, when, reason.
  final _sampleDeclined = <(String, String, String, String)>[
    ('KG', 'Kaushik Ghosh', 'Declined yesterday, 7:10 PM', 'Asked for a home visit'),
    ('NB', 'Nandini Basu', 'Declined 27 Sep, 11:00 AM', 'Duplicate of an existing booking'),
  ];

  final _sampleAppts = <_Appt>[
    _Appt('Today · Tue 29 Sep', '9:30 AM', 'Rahul Das', 'Dr. Sen · Salt Lake', 'Checked in'),
    _Appt('Today · Tue 29 Sep', '10:00 AM', 'Aisha Khan', 'Dr. Sen · Salt Lake', 'Confirmed'),
    _Appt('Today · Tue 29 Sep', '11:30 AM', 'Moumita Roy', 'Dr. Mitra · Salt Lake', 'Booked'),
    _Appt('Wed 30 Sep', '10:00 AM', 'Debasish Bose', 'Dr. Sen · New Town', 'Confirmed'),
    _Appt('Wed 30 Sep', '11:20 AM', 'Amit Pal', 'Dr. Sen · New Town', 'Booked'),
  ];

  int _range = 1; // Today · Upcoming · Past
  bool _allRequests = false;
  bool _showDeclined = false;
  int _booked = 18;
  int _freed = 2;

  static int _minutes(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(t.trim());
    if (m == null) return 0;
    var h = int.parse(m.group(1)!) % 12;
    if (m.group(3) == 'PM') h += 12;
    return h * 60 + int.parse(m.group(2)!);
  }

  static String _place(String where) =>
      where.endsWith('New Town') ? 'City Care — New Town' : 'City Care Clinic — Salt Lake';

  Future<void> _manage(_Appt a) async {
    if (isLive) {
      final r = await openSheet<Object>(context, (_) => AppointmentsManageSheet(appointmentId: a.id));
      if (r != null && mounted) reload(quiet: true);
      return;
    }
    final r = await openSheet<_SheetResult>(
      context,
      (_) => AppointmentsManageSheet(
        name: a.name,
        time: a.time,
        doctor: a.where.split(' · ').first,
        when: '${a.day.replaceFirst('Today · ', 'Today, ')} · ${_place(a.where)}',
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r.action == 'cancel') {
        _appts.remove(a);
        _booked--;
        _freed++;
      } else {
        a.day = r.day;
        a.time = r.time;
      }
    });
  }

  Future<void> _assign(_Request q) async {
    if (isLive) {
      final r = await openSheet<Object>(context, (_) => AppointmentsManageSheet(requestId: q.id));
      if (r != null && mounted) reload(quiet: true);
      return;
    }
    final r = await openSheet<_SheetResult>(
      context,
      (_) => AppointmentsManageSheet(name: q.name, when: 'Requested: ${q.pref}', assign: true),
    );
    if (r == null || !mounted) return;
    setState(() {
      _requests.remove(q);
      _appts.add(_Appt(r.day, r.time, q.name, 'Dr. Sen · Salt Lake', 'Booked'));
      _booked++;
    });
  }

  final _busy = ValueNotifier(false);

  /// The status can still move (not done, cancelled or moved).
  bool _canChange(_Appt a) => isLive && a.raw != null && !const ['completed', 'cancelled', 'rescheduled'].contains(a.raw!.str('status'));

  Future<void> _changeStatus(_Appt a) async {
    if (await changeVisitStatus(context, appointmentId: a.id!, status: a.raw!.str('status'), patientName: a.name) && mounted) reload(quiet: true);
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _decline(_Request q) async {
    if (isLive) {
      final ok = await runAction(
        context,
        () => Api.I.post('/api/appointment-requests/${q.id}/decline', const {}),
        busy: _busy,
      );
      if (ok == null || !mounted) return;
      toast(context, 'Request declined');
      reload(quiet: true);
      return;
    }
    setState(() {
      _requests.remove(q);
      _declined.insert(0, (q.initials, q.name, 'Declined just now', q.reason));
    });
    toast(context, 'Request declined');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final days =
        data != null
            ? _liveDays
            : switch (_range) {
              0 => [_days.first],
              1 => _days,
              _ => const <String>[],
            };
    final st = data?.obj('today').obj('stats');
    // The counts follow the tab: Today; Today + Upcoming (the list shows both); Past.
    Map<String, dynamic>? range(String k) => data?.obj(k)['rangeStats'] is Map ? data!.obj(k).obj('rangeStats') : null;
    num sum(String key, List<String> tabs) => tabs.fold<num>(0, (n, k) => n + (range(k)?.numOr(key) ?? 0));
    final hasRange = range('today') != null;
    final waiting = '${st?.numOr('waitingRequests', _requests.length) ?? _requests.length}';
    final stats = st == null
        ? [('$_booked', 'Booked'), ('${_requests.length}', 'Waiting'), ('$_freed', 'Freed up')]
        : !hasRange
            ? [('${st.numOr('booked')}', 'Booked'), (waiting, 'Waiting'), ('${st.numOr('freedUp')}', 'Freed up')]
            : switch (_range) {
                0 => [('${sum('booked', ['today'])}', 'Booked'), (waiting, 'Waiting'), ('${sum('freedUp', ['today'])}', 'Freed up')],
                1 => [('${sum('booked', ['today', 'upcoming'])}', 'Booked'), (waiting, 'Waiting'), ('${sum('freedUp', ['today', 'upcoming'])}', 'Freed up')],
                _ => [('${sum('completed', ['past'])}', 'Done'), ('${sum('missed', ['past'])}', 'Missed'), ('${sum('freedUp', ['past'])}', 'Cancelled')],
              };

    return MpPage(
      header: MpHeader(
        'Appointments',
        actions: [
          // Pick a patient, then a free time: a confirmed visit (Staff-Book).
          MpIconButton(
            I.plus,
            label: 'Book appointment',
            color: MP.primary,
            onTap: () async {
              await Nav.go(context, 'Staff-Book');
              if (mounted && isLive) reload(quiet: true);
            },
          ),
        ],
      ),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          _waitingCard(),
          _toMoveCard(),

          // Range
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MpSegmented(
              options: const ['Today', 'Upcoming', 'Past'],
              index: _range,
              onChanged: (i) => setState(() => _range = i),
            ),
          ),

          // Stats
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: MP.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MP.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stats[i].$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                        const SizedBox(height: 6),
                        Text(
                          stats[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(14, c: MP.ink2, h: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Day sections
          for (final day in days)
            if (_appts.any((a) => a.day == day)) _daySection(day),
          if (data == null ? _range == 2 : days.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _range == 2 ? 'No past appointments in this view.' : 'No appointments in this view.',
                style: tx(14, c: MP.ink2),
              ),
            ),

          // Declined requests (expandable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              expanded: _showDeclined,
              child: Tap(
                onTap: () => setState(() => _showDeclined = !_showDeclined),
                radius: 16,
                color: MP.white,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MP.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Declined requests (${_declined.length})', style: tx(16, w: w600, c: MP.ink2)),
                      ),
                      AnimatedRotation(
                        turns: _showDeclined ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Ico(I.chevronDown, size: 20, color: MP.ink2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showDeclined) _declinedCard(),
        ],
      ),
    );
  }

  Widget _waitingCard() {
    final shown = _allRequests ? _requests : _requests.take(2).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MPDeco.card(radius: 20, shadow: MPShadow.float),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text('Waiting for a time', style: tx(20, w: w700, h: 1.25))),
                          const SizedBox(width: 10),
                          MpBadge.amber('${_requests.length}'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Requests with no slot yet, oldest first', style: tx(14, c: MP.ink2)),
                    ],
                  ),
                ),
                if (_requests.length > 2)
                  MpHitSlop(child: Tap(
                    onTap: () => setState(() => _allRequests = !_allRequests),
                    radius: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(_allRequests ? 'Show less' : 'View all', style: tx(14, w: w600, c: MP.primary)),
                    ),
                  )),
              ],
            ),
          ),
          for (final q in shown) _request(q),
          if (_requests.isEmpty)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No requests waiting. Every request has a time.', style: tx(14, c: MP.ink2, h: 1.45)),
            ),
        ],
      ),
    );
  }

  Widget _request(_Request q) {
    return D7Ruled(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: VGap(
        gap: 12,
        children: [
          MpHitSlop(child: Tap(
            onTap: () => Nav.go(context, 'PP-Summary', args: q.patientId == null ? null : {'patientId': q.patientId}),
            radius: 12,
            child: Row(
              children: [
                MpAvatar(q.initials, size: 40, fontSize: 14, photo: q.photo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                      Text(q.when, style: tx(13, c: MP.ink3)),
                    ],
                  ),
                ),
              ],
            ),
          )),
          Text(q.reason, style: tx(15, h: 1.45)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Ico(I.clock, size: 16, color: MP.ink2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Requested: ',
                      style: tx(14, c: MP.ink2),
                      children: [TextSpan(text: q.pref, style: tx(14, w: w600))],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(child: D7Btn('Assign time', bg: MP.primarySoft, expand: true, onTap: () => _assign(q))),
              const SizedBox(width: 8),
              D7Btn('Decline', fg: MP.ink2, onTap: () => _decline(q)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _daySection(String day) {
    final rows =
        _appts.where((a) => a.day == day).toList()..sort(
          (a, b) => a.at != null && b.at != null ? a.at!.compareTo(b.at!) : _minutes(a.time).compareTo(_minutes(b.time)),
        );
    return Semantics(
      container: true,
      label: day,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(day.toUpperCase(), style: tx(12, w: w600, em: 0.06, c: MP.ink3)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: MPDeco.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < rows.length; i++) _apptRow(rows[i], first: i == 0)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apptRow(_Appt a, {required bool first}) {
    final tone = _tones[a.status] ?? (MP.fill, MP.ink2);
    return D7Ruled(
      top: !first,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 68px column; like the design, "10:00 AM" (68.9px in tabular
          // figures) wraps its "AM" to a second line.
          SizedBox(
            width: 68,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(a.time, style: tx(15, w: w600, tab: true)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                const SizedBox(height: 4),
                Text(a.where, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2)),
                const SizedBox(height: 6),
                // Tap the status to change it (arrived, with doctor, done, missed, cancel).
                Tap(
                  onTap: _canChange(a) ? () => _changeStatus(a) : null,
                  radius: 999,
                  child: Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(a.status, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(12, w: w600, c: tone.$2))),
                        if (_canChange(a)) ...[const SizedBox(width: 3), Ico(I.chevronDown, size: 12, color: tone.$2, stroke: 2.2)],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.translate(
            offset: const Offset(0, -12),
            child: Semantics(
              label: 'Manage appointment for ${a.name} at ${a.time}',
              excludeSemantics: true,
              button: true,
              child: D7Btn('Manage', padding: const EdgeInsets.fromLTRB(8, 0, 4, 0), onTap: () => _manage(a)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _declinedCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _declined.length; i++)
            D7Ruled(
              top: i > 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MpAvatar(_declined[i].$1, size: 40, fontSize: 14, bg: MP.fill, fg: MP.ink2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_declined[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                        Text(_declined[i].$3, style: tx(13, c: MP.ink3)),
                        const SizedBox(height: 4),
                        Text(_declined[i].$4, style: tx(14, c: MP.ink2, h: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_declined.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No declined requests.', style: tx(14, c: MP.ink2)),
            ),
        ],
      ),
    );
  }
}

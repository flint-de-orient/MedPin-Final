import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';
import '../../widgets/i18n.dart';

/// Design: Appointments-Manage.dc.html — "Appointments · manage" (sheet over
/// 'Appointments'). The optional parameters default to the design's
/// appointment (Rahul Das, 9:30 AM); the Appointments screen passes the
/// tapped row, or a waiting request with [assign] = true.
///
/// Pops with `(action: 'reschedule' | 'assign' | 'book' | 'cancel', day:, time:)`.
///
/// Live, the record comes from [appointmentId] (reschedule / cancel),
/// [requestId] (assign a waiting request) or [patientId] (book a visit), or
/// the same keys in the route arguments (`Nav.go(.., args: {..})`). Slots:
/// GET /api/doctors/:doctorId/slots for the next days with open sessions.
class AppointmentsManageSheet extends StatefulWidget {
  const AppointmentsManageSheet({
    super.key,
    this.name = 'Rahul Das',
    this.time = '9:30 AM',
    this.doctor = 'Dr. Sen',
    this.when = 'Today, Tue 29 Sep · City Care Clinic — Salt Lake',
    this.assign = false,
    this.appointmentId,
    this.requestId,
    this.patientId,
  });

  final String? appointmentId;
  final String? requestId;
  final String? patientId;

  final String name;
  final String time;
  final String doctor;

  /// Second detail line under the patient (date and location, or the request).
  final String when;

  /// Give a waiting request its first slot instead of rescheduling.
  final bool assign;

  @override
  State<AppointmentsManageSheet> createState() => _AppointmentsManageSheetState();
}

class _AppointmentsManageSheetState extends State<AppointmentsManageSheet> with LiveData {
  /// How many days ahead to look for open sessions, and how many chips to show.
  static const _lookAhead = 10;
  static const _chips = 4;

  @override
  Future<Object?> fetch() async {
    final args = Nav.args<Map>(context) ?? const {};
    final appointmentId = widget.appointmentId ?? args['appointmentId'] as String?;
    final requestId = widget.requestId ?? args['requestId'] as String?;
    final patientId = widget.patientId ?? args['patientId'] as String?;
    final me = Session.I.user['id'] as String?;
    final doctors = [
      for (final x in (await Api.I.get('/api/doctors') as List? ?? const [])) (x as Map).cast<String, dynamic>(),
    ];

    String mode;
    String name;
    String time = '';
    String? doctorId;
    String? locationId;
    String? when;
    Map<String, dynamic>? appt;
    if (appointmentId != null) {
      mode = 'reschedule';
      appt = (await Api.I.get('/api/appointments/$appointmentId') as Map).cast<String, dynamic>();
      name = appt.obj('patient').str('name', 'Patient');
      final at = F.date(appt['startAt']);
      if (at != null) time = F.time(at);
      doctorId = appt.str('doctorId');
      locationId = appt.str('locationId');
    } else if (requestId != null) {
      mode = 'assign';
      final reqs = await Api.I.get('/api/appointment-requests', query: {'status': 'pending'}) as List? ?? const [];
      final q = [
        for (final x in reqs) (x as Map).cast<String, dynamic>(),
      ].where((x) => x.str('id') == requestId).firstOrNull;
      if (q == null) throw const ApiException(404, 'NOT_FOUND', 'This request was already handled');
      name = q['patientId'] is Map ? q.obj('patientId').str('name', 'Patient') : 'Patient';
      doctorId = q['doctorId'] is Map ? q.obj('doctorId').str('id') : q['doctorId'] as String?;
      locationId = q['locationId'] is Map ? q.obj('locationId').str('id') : q['locationId'] as String?;
      when = 'Requested: ${q.str('preferredTime', 'Any time')}';
    } else if (patientId != null) {
      mode = 'book';
      final p = (await Api.I.get('/api/patients/$patientId') as Map).cast<String, dynamic>();
      name = p.obj('patient').str('name', 'Patient');
    } else {
      throw const ApiException(400, 'NO_RECORD', 'Choose an appointment first');
    }

    // Defaults: the signed-in doctor (or the practice's first) at their first location.
    Map<String, dynamic>? doctor =
        doctors.where((d) => d.str('userId') == (doctorId ?? me)).firstOrNull ?? (doctorId == null ? doctors.firstOrNull : null);
    doctorId ??= doctor?.str('userId');
    final locations = doctor?.list('locations') ?? const <Map<String, dynamic>>[];
    locationId ??= locations.firstOrNull?.str('id');
    if (doctorId == null || locationId == null) {
      throw const ApiException(400, 'NO_SCHEDULE', 'Set up a clinic schedule first');
    }
    final locName =
        appt?.obj('location').str('name') ?? locations.where((l) => l.str('id') == locationId).firstOrNull?.str('name') ?? '';
    final practice = Session.I.activeMembership?['practiceName'] as String? ?? '';
    final place = [practice, locName].where((s) => s.isNotEmpty).join(' — ');
    final doctorName = appt?.obj('doctor').str('name') ?? doctor?.str('name') ?? '';
    if (when == null) {
      final at = F.date(appt?['startAt']);
      final day = at == null ? '' : (F.sameDay(at, DateTime.now()) ? 'Today, ${d7DayShort(at)}' : d7DayShort(at));
      when = [day, place].where((s) => s.isNotEmpty).join(' · ');
    }

    // The next days with free slots.
    final today = DateTime.now();
    final days = [for (var i = 0; i < _lookAhead; i++) DateTime(today.year, today.month, today.day + i)];
    final res = await Future.wait([
      for (final d in days)
        Api.I.get('/api/doctors/$doctorId/slots', query: {'locationId': locationId, 'date': d7Key(d)}),
    ]);
    final open = <Map<String, dynamic>>[];
    for (var i = 0; i < days.length && open.length < _chips; i++) {
      final s = (res[i] as Map).cast<String, dynamic>();
      final slots = s.list('slots');
      if (s['open'] != true || !slots.any((x) => x['available'] == true)) continue;
      final d = days[i];
      final short = d7DayShort(d);
      open.add({
        'chip': d.month == today.month ? short.substring(0, short.lastIndexOf(' ')) : short,
        'long': short,
        'slots': slots,
      });
    }
    return {
      'mode': mode,
      'id': appointmentId ?? requestId ?? patientId,
      'name': name,
      'time': time,
      'doctor': doctorName.isEmpty ? '' : F.doctorShort(doctorName),
      'when': when,
      'doctorId': doctorId,
      'locationId': locationId,
      'visitType': args['visitType'] ?? 'follow_up',
      'days': open,
      'prefers': mode == 'assign' ? when.replaceFirst('Requested: ', '') : '',
    };
  }

  /// First free date + time matching the patient's wish ("Thu or Fri, after 5 PM",
  /// "morning", "Sat evening"); null when it says nothing usable.
  static (int, String)? preferredSlot(String wish, List<Map<String, dynamic>> days) {
    final w = wish.toLowerCase();
    if (w.isEmpty || w.contains('any')) return null;
    const names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final wantDays = {for (var i = 0; i < 7; i++) if (RegExp('\\b${names[i]}').hasMatch(w)) i + 1};
    int? toMin(String h, String? m, String? ap) {
      var hh = int.parse(h) % 12;
      if ((ap ?? (int.parse(h) < 8 ? 'pm' : 'am')) == 'pm') hh += 12;
      return hh * 60 + (m == null ? 0 : int.parse(m));
    }
    int? after;
    int? before;
    final a = RegExp(r'after\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(w);
    if (a != null) after = toMin(a.group(1)!, a.group(2), a.group(3));
    final b = RegExp(r'before\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(w);
    if (b != null) before = toMin(b.group(1)!, b.group(2), b.group(3));
    if (w.contains('morning')) before ??= 12 * 60;
    if (w.contains('afternoon')) {
      after ??= 12 * 60;
      before ??= 17 * 60;
    }
    if (w.contains('evening')) after ??= 17 * 60;
    if (wantDays.isEmpty && after == null && before == null) return null;
    for (var i = 0; i < days.length; i++) {
      for (final s in days[i].list('slots')) {
        if (s['available'] != true) continue;
        final at = F.date(s['startAt']);
        if (at == null) continue;
        final m = at.hour * 60 + at.minute;
        if (wantDays.isNotEmpty && !wantDays.contains(at.weekday)) break;
        if (after != null && m < after) continue;
        if (before != null && m >= before) continue;
        return (i, s.str('time'));
      }
    }
    return null;
  }

  /// Once the slots load, start on the time the patient asked for.
  bool _prefApplied = false;
  void _applyPreference() {
    if (_prefApplied || data == null) return;
    _prefApplied = true;
    final pick = preferredSlot(data!.str('prefers'), _liveDays);
    if (pick != null && _slot == null) {
      _date = pick.$1;
      _slot = pick.$2;
    }
  }

  bool get _assign => data == null ? widget.assign : data!['mode'] != 'reschedule';
  String get _name => data?.str('name') ?? widget.name;
  String get _time => data?.str('time') ?? widget.time;
  String get _doctor => data?.str('doctor') ?? widget.doctor;
  String get _when => data?.str('when') ?? widget.when;

  List<Map<String, dynamic>> get _liveDays => data?.list('days') ?? const [];

  /// Chip label, long label.
  List<(String, String)> get _dateList =>
      data == null ? _dates : [for (final d in _liveDays) (d.str('chip'), d.str('long'))];

  List<Map<String, dynamic>> get _daySlots => _date < _liveDays.length ? _liveDays[_date].list('slots') : const [];

  List<String> get _timeList => data == null ? _times : [for (final s in _daySlots) s.str('time')];

  Set<String> _takenOn(int i) {
    if (data == null) return _taken[i];
    if (i >= _liveDays.length) return const {};
    return {
      for (final s in _liveDays[i].list('slots'))
        if (s['available'] != true) s.str('time'),
    };
  }

  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }
  /// Chip label, long label (renderVals().dates).
  static const _dates = [
    ('Wed 30', 'Wed 30 Sep'),
    ('Thu 1 Oct', 'Thu 1 Oct'),
    ('Fri 2 Oct', 'Fri 2 Oct'),
    ('Sat 3 Oct', 'Sat 3 Oct'),
  ];

  static const _times = [
    '9:00 AM', '9:15 AM', '9:30 AM', //
    '9:45 AM', '10:00 AM', '10:15 AM',
    '10:30 AM', '10:45 AM', '11:00 AM',
  ];

  /// Already-booked slots per date; Wed 30 is the design's.
  static const _taken = [
    {'9:00 AM', '9:30 AM', '10:15 AM', '11:00 AM'},
    {'9:15 AM', '10:00 AM', '10:45 AM'},
    {'9:00 AM', '9:45 AM', '10:30 AM', '11:00 AM'},
    {'9:30 AM', '10:00 AM'},
  ];

  int _date = 0;
  late String? _slot = isLive ? null : '10:00 AM';

  void _pickDate(int i) {
    if (i == _date) return;
    setState(() {
      _date = i;
      if (isLive || (_slot != null && _takenOn(i).contains(_slot))) _slot = null;
    });
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (slot == null) {
      toast(context, 'Choose a time first');
      return;
    }
    final day = _dateList[_date].$2;
    var action = _assign ? 'assign' : 'reschedule';
    if (isLive) {
      final d = data!;
      final startAt = _daySlots.where((s) => s.str('time') == slot).firstOrNull?['startAt'];
      action = d.str('mode');
      final ok = await runAction(context, busy: _busy, () {
        final id = d.str('id');
        return switch (action) {
          'reschedule' => Api.I.post('/api/appointments/$id/reschedule', {'startAt': startAt}),
          'assign' => Api.I.post('/api/appointment-requests/$id/assign', {
            'startAt': startAt,
            'doctorId': d['doctorId'],
            'locationId': d['locationId'],
          }),
          _ => Api.I.post('/api/appointments', {
            'patientId': id,
            'doctorId': d['doctorId'],
            'locationId': d['locationId'],
            'startAt': startAt,
            'visitType': d['visitType'],
          }),
        };
      });
      if (ok == null || !mounted) return;
    }
    toast(context, action == 'reschedule' ? 'Rescheduled to $day, $slot' : 'Booked for $day, $slot');
    Navigator.pop(context, (action: action, day: day, time: slot));
  }

  Future<void> _cancel() async {
    if (isLive) {
      final ok = await runAction(
        context,
        () => Api.I.post('/api/appointments/${data!.str('id')}/cancel', const {}),
        busy: _busy,
      );
      if (ok == null || !mounted) return;
    }
    toast(context, 'Appointment cancelled');
    Navigator.pop(context, (action: 'cancel', day: '', time: ''));
  }

  @override
  Widget build(BuildContext context) {
    _applyPreference();
    final placeholder = livePlaceholder();
    final first = F.firstName(_name);
    final dates = _dateList;
    final times = _timeList;
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_assign ? 'Assign a time' : 'Manage appointment', style: tx(20, w: w700, h: 1.25)),
                      if (placeholder == null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [_name, if (!_assign && _time.isNotEmpty) _time, if (_doctor.isNotEmpty) _doctor].join(' · '),
                          style: tx(16, w: w600),
                        ),
                        const SizedBox(height: 4),
                        Text(_when, style: tx(14, c: MP.ink2)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 44×44 with CSS margin -8px -8px 0 0: takes 36×36 in the row
                // and reaches 8px up and 8px right.
                SizedBox(
                  width: 36,
                  height: 36,
                  child: OverflowBox(
                    alignment: Alignment.bottomLeft,
                    minWidth: 44,
                    maxWidth: 44,
                    minHeight: 44,
                    maxHeight: 44,
                    child: MpIconButton(I.close, label: 'Close', color: MP.ink2, onTap: () => Navigator.pop(context)),
                  ),
                ),
              ],
            ),
          ),

          if (placeholder != null) placeholder,
          if (placeholder == null && dates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('No free times in the next $_lookAhead days.', style: tx(14, c: MP.ink2)),
            ),

          // New date
          if (placeholder == null && dates.isNotEmpty) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_assign ? 'Date' : 'New date', style: tx(14, w: w600)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < dates.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  D7Pill(dates[i].$1, on: _date == i, borderOn: false, onTap: () => _pickDate(i)),
                ],
              ],
            ),
          ),

          // Time
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Time · ${dates[_date].$2}', style: tx(14, w: w600)),
                const SizedBox(height: 8),
                for (var r = 0; r < times.length; r += 3) ...[
                  if (r > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var c = 0; c < 3; c++) ...[
                        if (c > 0) const SizedBox(width: 8),
                        Expanded(child: r + c < times.length ? _slotCell(times[r + c]) : const SizedBox(height: 48)),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text('Crossed-out times are already booked.', style: tx(13, c: MP.ink3)),
                const SizedBox(height: 24),
                MpButton(_assign ? 'Assign time' : 'Reschedule', onTap: _confirm),
                if (!_assign) ...[
                  const SizedBox(height: 12),
                  MpButton.small('Cancel appointment', kind: MpBtn.dangerSoft, onTap: _cancel),
                  Text(
                    '$first will be notified and the slot opens for others.',
                    textAlign: TextAlign.center,
                    style: tx(13, c: MP.ink3),
                  ),
                ],
              ],
            ),
          ),
          ],
          if (placeholder == null && dates.isEmpty && !_assign)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: MpButton.small('Cancel appointment', kind: MpBtn.dangerSoft, onTap: _cancel),
            ),
        ],
      ),
    );
  }

  Widget _slotCell(String t) {
    final taken = _takenOn(_date).contains(t);
    final selected = !taken && _slot == t;
    final bg =
        selected
            ? MP.primarySoft
            : taken
            ? MP.fill
            : MP.white;
    final fg =
        selected
            ? MP.primary
            : taken
            ? MP.ink3
            : MP.ink;
    final border =
        selected ? Border.all(color: MP.primary, width: 2) : Border.all(color: taken ? MP.fill : MP.lineStrong);
    return Semantics(
      button: true,
      selected: selected,
      enabled: !taken,
      excludeSemantics: true,
      label:
          '$t${taken
              ? ', already booked'
              : selected
              ? ', selected'
              : ''}',
      child: Tap(
        onTap: taken ? null : () => setState(() => _slot = t),
        radius: 12,
        color: bg,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: border),
          child: Text(
            t,
            maxLines: 1,
            style: tx(15, w: selected ? w700 : w500, c: fg, tab: true, deco: taken ? TextDecoration.lineThrough : null),
          ),
        ),
      ),
    );
  }
}

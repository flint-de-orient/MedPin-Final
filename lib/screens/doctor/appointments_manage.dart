import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/booking_calendar.dart';
import '../../widgets/fee_actions.dart';
import '../../widgets/mp.dart';
import '../../widgets/visit_status.dart';
import 'common_d6.dart';
import 'common_d7.dart';
import '../../widgets/i18n.dart';

/// Design: Appointments-Manage.dc.html — "Appointments · manage" (sheet over
/// 'Appointments'). The optional parameters default to the design's
/// appointment (Rahul Das, 9:30 AM); the Appointments screen passes the
/// tapped row, or a waiting request with [assign] = true.
///
/// Pops with `(action: 'reschedule' | 'assign' | 'book' | 'cancel', day:, time:)`.
///
/// An appointment opens on "Manage appointment": the patient (photo, name,
/// phone), doctor, place, date and time, status and fee, and what can be done
/// from where it is — Reschedule (date and time here, the patient is told, a
/// payment moves with it), Change status (widgets/visit_status.dart), Collect
/// the fee / Hand back a refund due (widgets/fee_actions.dart), Call, Message
/// and Cancel visit (with the reason the patient is told). The server checks
/// who may act on which visit (their locations / doctors).
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
  static const _lookAhead = 14;
  static const _chips = 10;

  /// An appointment: the overview, or (after Reschedule) the date and time.
  bool _rescheduling = false;

  /// A day picked in "More dates" beyond the chips: (chip, long, slots).
  Map<String, dynamic>? _extraDay;

  /// The branch chosen in the sheet (null: the default below).
  String? _pickedLoc;
  bool _switching = false;

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
      // Start at the follow-up's branch, else the branch the patient usually visits.
      final start = args['locationId'] as String? ?? p.obj('branch').obj('usual').str('id');
      locationId = start.isEmpty ? null : start;
    } else {
      throw const ApiException(400, 'NO_RECORD', 'Choose an appointment first');
    }

    // Defaults: the signed-in doctor (or the practice's first) at their first location.
    Map<String, dynamic>? doctor =
        doctors.where((d) => d.str('userId') == (doctorId ?? me)).firstOrNull ?? (doctorId == null ? doctors.firstOrNull : null);
    doctorId ??= doctor?.str('userId');
    final locations = doctor?.list('locations') ?? const <Map<String, dynamic>>[];
    bool works(String? id) => id != null && locations.any((l) => l.str('id') == id);
    // The doctor's choice in the sheet wins; a default only counts if the doctor works there.
    if (works(_pickedLoc)) {
      locationId = _pickedLoc;
    } else if (!works(locationId) && mode == 'book') {
      locationId = null;
    }
    locationId ??= locations.firstOrNull?.str('id');
    // Manage appointment opens on the overview: times load once Reschedule is tapped.
    final needSlots = mode != 'reschedule' || _rescheduling;
    if (needSlots && (doctorId == null || locationId == null)) {
      throw const ApiException(400, 'NO_SCHEDULE', 'Set up a clinic schedule first');
    }
    final picked = locations.where((l) => l.str('id') == locationId).firstOrNull;
    final locName = picked?.str('name') ?? appt?.obj('location').str('name') ?? '';
    final practice = Session.I.activeMembership?['practiceName'] as String? ?? '';
    final place = [practice, locName].where((s) => s.isNotEmpty).join(' — ');
    final doctorName = appt?.obj('doctor').str('name') ?? doctor?.str('name') ?? '';
    if (when == null) {
      final at = F.date(appt?['startAt']);
      final day = at == null ? '' : (F.sameDay(at, DateTime.now()) ? 'Today, ${d7DayShort(at)}' : d7DayShort(at));
      when = [day, place].where((s) => s.isNotEmpty).join(' · ');
    }

    // The next days with free slots (past times today left out).
    final today = DateTime.now();
    final days = needSlots ? [for (var i = 0; i < _lookAhead; i++) DateTime(today.year, today.month, today.day + i)] : const <DateTime>[];
    final res = await Future.wait([
      for (final d in days)
        Api.I.get('/api/doctors/$doctorId/slots', query: {'locationId': locationId, 'date': d7Key(d)}),
    ]);
    final open = <Map<String, dynamic>>[];
    for (var i = 0; i < days.length && open.length < _chips; i++) {
      final s = (res[i] as Map).cast<String, dynamic>();
      final slots = [
        for (final x in s.list('slots'))
          if ((F.date(x['startAt']) ?? today).isAfter(today)) x,
      ];
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
      'locations': [for (final l in locations) {'id': l.str('id'), 'name': l.str('shortName', l.str('name'))}],
      'visitType': args['visitType'] ?? 'follow_up',
      'days': open,
      'prefers': mode == 'assign' ? when.replaceFirst('Requested: ', '') : '',
      if (appt != null) 'appt': appt,
    };
  }

  /// First free date + time matching the patient's wish ("Thu or Fri, after 5 PM",
  /// "morning", "Sat evening"); null when it says nothing usable.
  static (int, String)? preferredSlot(String wish, List<Map<String, dynamic>> days) {
    // Bengali (০-৯) and Devanagari (०-९) digits count like 0-9.
    var w = wish.toLowerCase().replaceAllMapped(RegExp('[০-৯०-९]'), (m) {
      final c = m.group(0)!.codeUnitAt(0);
      return '${c >= 0x09E6 && c <= 0x09EF ? c - 0x09E6 : c - 0x0966}';
    });
    if (w.isEmpty || w.contains('any') || w.contains('যেকোনো') || w.contains('कभी भी')) return null;
    // Day names in English, Bengali and Hindi (Mon = 1 … Sun = 7).
    const names = [
      ['mon', 'সোম', 'सोम'],
      ['tue', 'মঙ্গল', 'मंगल'],
      ['wed', 'বুধ', 'बुध'],
      ['thu', 'বৃহস্পতি', 'गुरु', 'बृहस्पति'],
      ['fri', 'শুক্র', 'शुक्र'],
      ['sat', 'শনি', 'शनि'],
      ['sun', 'রবি', 'रवि', 'इतवार'],
    ];
    final wantDays = {
      for (var i = 0; i < 7; i++)
        if (RegExp('\\b${names[i][0]}').hasMatch(w) || names[i].skip(1).any(w.contains)) i + 1,
    };
    // "5 টার পরে" / "5 बजे के बाद" → after 5; "আগে" / "से पहले" → before.
    w = w
        .replaceAllMapped(RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:টা|টার|টায়)?\s*(?:পরে|পর)'), (m) => 'after ${m.group(1)}${m.group(2) == null ? '' : ':${m.group(2)}'}')
        .replaceAllMapped(RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:বজে|बजे)?\s*(?:के बाद|बाद)'), (m) => 'after ${m.group(1)}${m.group(2) == null ? '' : ':${m.group(2)}'}')
        .replaceAllMapped(RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:টা|টার)?\s*(?:আগে)'), (m) => 'before ${m.group(1)}${m.group(2) == null ? '' : ':${m.group(2)}'}')
        .replaceAllMapped(RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:बजे)?\s*(?:से पहले|पहले)'), (m) => 'before ${m.group(1)}${m.group(2) == null ? '' : ':${m.group(2)}'}');
    if (w.contains('সকাল') || w.contains('सुबह')) w += ' morning';
    if (w.contains('দুপুর') || w.contains('दोपहर')) w += ' afternoon';
    if (w.contains('সন্ধ্যা') || w.contains('বিকেল') || w.contains('शाम')) w += ' evening';
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

  List<Map<String, dynamic>> get _liveDays {
    final days = data?.list('days') ?? const <Map<String, dynamic>>[];
    final extra = _extraDay;
    if (extra == null || days.any((d) => d.str('long') == extra.str('long'))) return days;
    return [...days, extra];
  }

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

  /// Another branch: its free days and times load.
  Future<void> _pickLocation(String id) async {
    if (id == data?.str('locationId') || _switching) return;
    setState(() {
      _pickedLoc = id;
      _switching = true;
      _date = 0;
      _slot = null;
    });
    await reload(quiet: true);
    if (mounted) setState(() => _switching = false);
  }

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
          'reschedule' => Api.I.post('/api/appointments/$id/reschedule', {'startAt': startAt, 'locationId': d['locationId']}),
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
            // "Book" on a follow-up: this visit closes that follow-up (not another doctor's).
            if ((Nav.args<Map>(context) ?? const {})['followUpId'] is String) 'followUpId': (Nav.args<Map>(context) ?? const {})['followUpId'],
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
      // The patient is told why (a quick reason, or one typed).
      final reason = await askCancelReason(context, patientName: _name);
      if (reason == null || !mounted) return;
      final ok = await runAction(
        context,
        () => Api.I.post('/api/appointments/${data!.str('id')}/cancel', {'reason': reason}),
        busy: _busy,
      );
      if (ok == null || !mounted) return;
    }
    toast(context, 'Appointment cancelled');
    Navigator.pop(context, (action: 'cancel', day: '', time: ''));
  }

  // ── Manage appointment (the overview) ──

  /// An appointment's overview (not a request to assign, not choosing a new time).
  bool get _overview => !_assign && !_rescheduling;

  /// The appointment as the server sent it; the design's sample in the preview.
  Map<String, dynamic> get _appt => data?.obj('appt') ??
      {
        'status': 'confirmed',
        'startAt': null,
        'token': '07',
        'visitType': 'follow_up',
        'reason': 'Sugar review',
        'fee': 600,
        'feeStatus': 'pending',
        'payAt': 'clinic',
        'payment': {'id': 'pay1', 'status': 'pending', 'amount': 600},
        'patient': {'id': 'p1', 'name': widget.name, 'phone': '9830012345'},
      };

  String get _status => _appt.str('status');

  /// Today or later (a past day's visit is marked missed, not cancelled).
  bool get _notPast {
    final at = F.date(_appt['startAt']);
    if (at == null) return true;
    final n = DateTime.now();
    return !DateTime(at.year, at.month, at.day).isBefore(DateTime(n.year, n.month, n.day));
  }

  Future<void> _startReschedule() async {
    setState(() {
      _rescheduling = true;
      _date = 0;
      _slot = isLive ? null : _slot;
    });
    if (isLive) {
      setState(() => _switching = true);
      await reload(quiet: true);
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _changeStatus() async {
    if (!isLive) return toast(context, 'Status: Arrived');
    final id = data!.str('id');
    if (await changeVisitStatus(context, appointmentId: id, status: _status, patientName: _name) && mounted) {
      // Cancelled from there: nothing more to manage.
      final now = (await Api.I.get('/api/appointments/$id').catchError((_) => const <String, dynamic>{}) as Map?) ?? const {};
      if (!mounted) return;
      if (now['status'] == 'cancelled') {
        Navigator.pop(context, (action: 'cancel', day: '', time: ''));
        return;
      }
      reload(quiet: true);
    }
  }

  Future<void> _collect(VisitFee fee) async {
    if (!isLive) return toast(context, tr(context, '₹#1 collected').replaceFirst('#1', '${fee.amount}'));
    if (await collectFee(context, fee, patientName: _name) && mounted) reload(quiet: true);
  }

  Future<void> _handBack(VisitFee fee) async {
    if (!isLive) return toast(context, 'Refund recorded');
    if (await handBackFee(context, fee) && mounted) reload(quiet: true);
  }

  /// "More dates": any day of the doctor's at this place, then its times.
  Future<void> _moreDates() async {
    final d = data;
    if (d == null) return;
    final picked = await pickBookingDay(context, doctorId: d.str('doctorId'), locationId: d.str('locationId'));
    if (picked == null || !mounted) return;
    final short = d7DayShort(picked);
    final i = _liveDays.indexWhere((x) => x.str('long') == short);
    if (i >= 0) return _pickDate(i);
    try {
      final s = (await Api.I.get('/api/doctors/${d.str('doctorId')}/slots', query: {'locationId': d.str('locationId'), 'date': d7Key(picked)}) as Map).cast<String, dynamic>();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _extraDay = {
          'chip': short,
          'long': short,
          'slots': [
            for (final x in s.list('slots'))
              if ((F.date(x['startAt']) ?? now).isAfter(now)) x,
          ],
        };
        _date = _liveDays.length - 1;
        _slot = null;
      });
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  static (Color, Color) _tone(String status) => switch (status) {
        'waiting' => (MP.amberSoft, MP.amber),
        'in_consultation' => (MP.primarySoft, MP.primary),
        'completed' => (MP.greenSoft, MP.green),
        'missed' => (MP.redSoft, MP.red),
        _ => (MP.fill, MP.ink2),
      };

  Widget _overviewBody() {
    final a = _appt;
    final p = a.obj('patient');
    final phone = p.str('phone');
    final photo = a.str('patientPhoto');
    final at = F.date(a['startAt']);
    final status = _status;
    final fee = isLive ? VisitFee.of(a) : const VisitFee(paymentId: 'pay1', amount: 600, status: 'pending', payAtClinic: true);
    final upcoming = status == 'booked' || status == 'confirmed';
    final canChange = !const ['completed', 'cancelled', 'rescheduled'].contains(status);
    final doctor = a.obj('doctor').str('name', _doctor);
    final practice = Session.I.activeMembership?['practiceName'] as String? ?? '';
    final loc = a.obj('location').str('name');
    final place = loc.isEmpty ? _when.split(' · ').last : [practice, loc].where((s) => s.isNotEmpty).join(' — ');
    final day = at == null ? _when.split(' · ').first : (F.sameDay(at, DateTime.now()) ? '${tr(context, 'Today')}, ${d7DayShort(at)}' : d7DayShort(at));
    final time = at == null ? _time : F.time(at);
    final token = a.str('token');
    final type = switch (a.str('visitType')) { 'new' => 'New visit', 'report_review' => 'Report review', _ => 'Follow-up' };
    final reason = a.str('reason');
    final tone = _tone(status);
    final label = status == 'rescheduled' ? 'Moved' : visitStatusLabel(status);
    final cancelled = status == 'cancelled'
        ? [
            if (a.str('cancelledByName').isNotEmpty) tr(context, 'Cancelled by #1').replaceFirst('#1', a.str('cancelledByName')),
            if (a.str('cancelReason').isNotEmpty) a.str('cancelReason'),
          ].join(' · ')
        : '';

    Widget info(String icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Ico(icon, size: 16, color: MP.ink3)),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: tx(15, h: 1.4))),
            ],
          ),
        );

    final actions = <(String, String, String?, VoidCallback, bool)>[
      if (upcoming) (I.calendar, 'Reschedule', 'Pick a new date and time · the patient is told', _startReschedule, false),
      if (canChange) (I.clock, 'Change status', 'Arrived, with doctor, done, missed', _changeStatus, false),
      if (fee != null && fee.due && canChange && status != 'missed')
        (I.wallet, tr(context, 'Collect ₹#1').replaceFirst('#1', '${fee.amount}'), 'Cash, UPI or card at the counter', () => _collect(fee), false),
      if (fee != null && fee.refundDue)
        (I.wallet, tr(context, 'Refund ₹#1').replaceFirst('#1', '${fee.amount}'), fee.method == 'online' ? 'Try the online refund again' : 'Mark it once handed back', () => _handBack(fee), false),
      if (phone.isNotEmpty) (I.phone, 'Call', d6Phone(phone), () => d6Call(context, phone, _name), false),
      if (isLive && p.str('id').isNotEmpty) (I.message, 'Message', 'Opens the patient’s chat', () => d6MessagePatient(context, p.str('id')), false),
      if (!isLive) (I.message, 'Message', 'Opens the patient’s chat', () => Nav.go(context, 'Patient-Thread'), false),
      if ((upcoming || status == 'waiting') && _notPast) (I.close, 'Cancel visit', 'The patient is told why; a fee paid is refunded', _cancel, true),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MpAvatar(F.initials(_name), size: 48, fontSize: 16, photo: photo.isEmpty ? null : photo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(17, w: w700)),
                    if (phone.isNotEmpty) ...[const SizedBox(height: 2), Text(d6Phone(phone), style: tx(14, c: MP.ink2, tab: true))],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info(I.clock, [day, time, if (token.isNotEmpty) tr(context, 'Token #1').replaceFirst('#1', token)].where((s) => s.isNotEmpty).join(' · ')),
                if (doctor.isNotEmpty) info(I.stethoscope, doctor),
                if (place.isNotEmpty) info(I.pin, place),
                info(I.file, [tr(context, type), if (reason.isNotEmpty) reason].join(' · ')),
                if (cancelled.isNotEmpty) info(I.close, cancelled),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Tap the status to change it.
              Semantics(
                button: canChange,
                label: tr(context, 'Status: #1').replaceFirst('#1', tr(context, label)),
                excludeSemantics: true,
                child: Tap(
                  onTap: canChange ? _changeStatus : null,
                  radius: 999,
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: tx(12, w: w600, c: tone.$2, h: 1)),
                        if (canChange) ...[const SizedBox(width: 3), Ico(I.chevronDown, size: 12, color: tone.$2, stroke: 2.2)],
                      ],
                    ),
                  ),
                ),
              ),
              if (fee != null && fee.status != 'free') FeeChip(fee),
            ],
          ),
          const SizedBox(height: 8),
          for (final (i, x) in actions.indexed)
            Tap(
              onTap: x.$4,
              radius: 12,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: x.$5 ? MP.redSoft : MP.primarySoft, borderRadius: BorderRadius.circular(10)),
                      child: Ico(x.$1, size: 18, color: x.$5 ? MP.red : MP.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(x.$2, style: tx(16, w: w600, c: x.$5 ? MP.red : MP.ink)),
                          if (x.$3 != null) ...[const SizedBox(height: 2), Text(x.$3!, style: tx(13, c: MP.ink2, h: 1.35))],
                        ],
                      ),
                    ),
                    const Ico(I.chevronRight, size: 18, color: MP.ink3),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
                      if (placeholder == null && !_overview) ...[
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
          if (placeholder == null && _overview) _overviewBody(),
          if (placeholder == null && _rescheduling)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MpHitSlop(
                  child: Tap(
                    onTap: () => setState(() => _rescheduling = false),
                    radius: 8,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Ico(I.chevronLeft, size: 16, color: MP.primary),
                        const SizedBox(width: 4),
                        Text('Back to the visit', style: tx(14, w: w600, c: MP.primary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Location: the doctor picks the branch; days and times follow it.
          if (placeholder == null && !_overview && (data?.list('locations').length ?? 0) > 1) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Location', style: tx(14, w: w600)),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final (i, l) in data!.list('locations').indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    D7Pill(l.str('name'), on: data!.str('locationId') == l.str('id'), borderOn: false, onTap: () => _pickLocation(l.str('id'))),
                  ],
                ],
              ),
            ),
          ],
          if (placeholder == null && !_overview && _switching)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))),
            ),
          if (placeholder == null && !_overview && !_switching && dates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('No free times in the next $_lookAhead days.', style: tx(14, c: MP.ink2)),
            ),

          // New date
          if (placeholder == null && !_overview && !_switching && dates.isNotEmpty) ...[
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
                // Any other day of the doctor's here (their hours, leave, closures).
                if (isLive && !_assign) ...[const SizedBox(width: 8), D7Pill('More dates', borderOn: false, onTap: _moreDates)],
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
          if (placeholder == null && !_overview && dates.isEmpty && !_assign)
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

/// First free (day index, time) matching a patient's wish like "Thu after 5 PM"
/// (English, বাংলা or हिन्दी). Exposed for tests.
@visibleForTesting
(int, String)? preferredSlotFor(String wish, List<Map<String, dynamic>> days) => _AppointmentsManageSheetState.preferredSlot(wish, days);

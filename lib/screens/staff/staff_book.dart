import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../widgets/booking_calendar.dart';
import '../../widgets/mp.dart';
import '../doctor/appointments_manage.dart';
import '../doctor/common_d7.dart';
import '../../widgets/i18n.dart';

/// "Book appointment" (front desk): pick the patient first, then the doctor,
/// place and visit type, then a free date and time. The visit is saved as
/// confirmed (the desk agreed it with the patient) and the patient gets a
/// "Visit confirmed" message in the app and on WhatsApp.
///
/// Smart for the desk on the phone: the patient's own story picks the doctor
/// and visit type (follow-up due → Follow-up, reports in → Report review, never
/// seen by this doctor → New visit) and offers reasons to tap (follow-up advice,
/// their conditions, the reports to review, last visit's reason, common ones);
/// a visit already booked shows with Manage. Days are the doctor's at that place
/// (weekly hours, leave, clinic closures) with "More dates" for the whole booking
/// window; times are the server's (taken ones crossed out, past ones gone) and
/// refresh live while the desk is on the call.
///
/// Live: GET /api/patients?q= (search), GET /api/appointments/booking/doctors
/// (doctors and places this person covers; an older server: /api/doctors),
/// /api/appointments/booking/context?patientId=, /api/appointments/booking/days,
/// GET /api/doctors/:id/slots for the chosen day, POST /api/appointments
/// {confirmed: true}. Opened with {'patientId'} the patient is chosen already.
class StaffBookScreen extends StatefulWidget {
  const StaffBookScreen({super.key});

  @override
  State<StaffBookScreen> createState() => _StaffBookScreenState();
}

const _visitTypes = [('new', 'New visit'), ('follow_up', 'Follow-up'), ('report_review', 'Report review')];

/// Days in the strip (the calendar reaches the rest of the booking window).
const _stripDays = 14;

/// Reasons the desk hears most, for each visit type.
const _commonReasons = {
  'new': ['Fever', 'Cough and cold', 'Stomach pain', 'Body ache', 'Headache', 'BP check', 'Sugar check', 'Skin problem', 'New problem'],
  'follow_up': ['Routine follow-up', 'Medicine review', 'Sugar review', 'BP review', 'Feeling better', 'Not improving'],
  'report_review': ['Report review', 'Blood test report', 'X-ray or scan report', 'ECG report'],
};

class _StaffBookScreenState extends State<StaffBookScreen> {
  // ── 1 · Patient ──
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _ctx; // booking context: visits, follow-ups, tests, upcoming
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  String _searched = '';

  // ── 2 · Doctor, place and visit ──
  List<Map<String, dynamic>> _doctors = const [];
  String? _doctorId;
  String? _locationId;
  bool _doctorTouched = false;
  int _visit = 1;
  bool _visitTouched = false;
  final _reason = TextEditingController();

  // ── 3 · Date and time ──
  List<BookingDay> _days = const [];
  bool _loadingDays = false;
  DateTime? _date;
  List<Map<String, dynamic>> _slots = const [];
  bool _loadingSlots = false;
  String? _slot; // startAt
  String? _error;
  bool _busy = false;
  bool _started = false;
  Timer? _tick;
  Timer? _changeDebounce;

  @override
  void initState() {
    super.initState();
    _reason.addListener(_onReason);
  }

  void _onReason() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!isLive) {
      _preview();
      return;
    }
    _loadDoctors();
    final id = (Nav.args<Map>(context) ?? const {})['patientId']?.toString();
    if (id != null) _loadPatient(id);
    _find('');
    // Times change while the desk is on the phone: others book, cancel, move.
    LiveBus.changes.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refreshTimes());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tick?.cancel();
    _changeDebounce?.cancel();
    if (isLive) LiveBus.changes.removeListener(_onChange);
    _search.dispose();
    _reason.removeListener(_onReason);
    _reason.dispose();
    super.dispose();
  }

  void _onChange() {
    _changeDebounce?.cancel();
    _changeDebounce = Timer(const Duration(milliseconds: 700), () {
      _refreshTimes();
      final id = _patient?.str('id');
      if (id != null && id.isNotEmpty) _loadContext(id, quiet: true);
    });
  }

  // ── Design preview ──
  void _preview() {
    _patient = {'id': 'p1', 'name': 'Amit Pal', 'age': 42, 'gender': 'male', 'phone': '9831120770', 'conditions': ['Type 2 diabetes']};
    final today = DateTime.now();
    _ctx = {
      'lastVisits': [
        {'doctorId': 'd1', 'at': today.subtract(const Duration(days: 30)).toIso8601String(), 'reason': 'Sugar review', 'diagnosis': 'Type 2 diabetes'},
      ],
      'followUps': [
        {'doctorId': 'd1', 'dueDate': DateTime(today.year, today.month, today.day + 2).toIso8601String(), 'status': 'not_booked', 'adviceText': 'Review with HbA1c'},
      ],
      'pendingTests': [
        {'name': 'HbA1c', 'doctorId': 'd1'},
      ],
      'reportsIn': const [],
      'upcoming': const [],
      'patient': {'conditions': ['Type 2 diabetes']},
    };
    _doctors = [
      {
        'userId': 'd1',
        'name': 'Dr. Arjun Sen',
        'locations': [
          {'id': 'l1', 'name': 'Salt Lake'},
          {'id': 'l2', 'name': 'New Town'},
        ],
      },
    ];
    _doctorId = 'd1';
    _locationId = 'l1';
    _days = [
      for (var i = 1; i <= 5; i++) BookingDay(DateTime(today.year, today.month, today.day + i), open: true, free: 5, total: 6),
    ];
    _date = _days.first.date;
    _slots = [
      for (final (i, t) in ['9:00 AM', '9:15 AM', '9:30 AM', '9:45 AM', '10:00 AM', '10:15 AM'].indexed)
        {'time': t, 'startAt': '1-$t', 'available': i != 1},
    ];
  }

  // ── Loading ──
  Future<void> _loadDoctors() async {
    try {
      List<Map<String, dynamic>> list;
      try {
        final r = (await Api.I.get('/api/appointments/booking/doctors') as Map).cast<String, dynamic>();
        list = r.list('items');
      } on ApiException catch (e) {
        if (e.status != 404) rethrow;
        // An older server: every doctor of the practice.
        list = [for (final x in (await Api.I.get('/api/doctors') as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      }
      if (!mounted) return;
      setState(() {
        _doctors = list;
        final withPlaces = _withPlaces;
        if (withPlaces.length == 1) {
          _pickDoctor(withPlaces.first.str('userId'), load: false);
        } else {
          // The signed-in doctor books for themselves first.
          final me = withPlaces.where((d) => d['me'] == true).firstOrNull;
          if (me != null) _pickDoctor(me.str('userId'), load: false);
        }
        _applySmart();
      });
      if (_doctorId != null) _loadDays();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadPatient(String id) async {
    try {
      final r = (await Api.I.get('/api/patients/$id') as Map).cast<String, dynamic>();
      final p = r.obj('patient');
      if (mounted && p.isNotEmpty) setState(() => _patient = {...p, 'id': p.str('id', id), 'conditions': [for (final c in r.list('conditions')) c.str('name')]});
      _loadContext(id);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  /// What this patient needs (follow-up due, reports, conditions, visits booked).
  Future<void> _loadContext(String id, {bool quiet = false}) async {
    try {
      final r = (await Api.I.get('/api/appointments/booking/context', query: {'patientId': id}) as Map).cast<String, dynamic>();
      if (!mounted || _patient?.str('id') != id) return;
      final before = _doctorId;
      setState(() {
        _ctx = r;
        // The photo comes with it (search rows may not have it yet).
        final photo = r.obj('patient').str('photo');
        if (photo.isNotEmpty && _patient!.str('photo').isEmpty) _patient = {..._patient!, 'photo': photo};
        if (!quiet) _applySmart();
      });
      if (_doctorId != before && _doctorId != null) _loadDays();
    } on ApiException catch (_) {
      // An older server: book without the suggestions.
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _find(v.trim()));
  }

  Future<void> _find(String q) async {
    if (!isLive) return;
    setState(() => _searching = true);
    try {
      final r = (await Api.I.get('/api/patients', query: {if (q.isNotEmpty) 'q': q, 'limit': '20'}) as Map).cast<String, dynamic>();
      if (!mounted || _search.text.trim() != q) return;
      setState(() {
        _results = r.list('items');
        _searched = q;
      });
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _choosePatient(Map<String, dynamic> p) {
    setState(() {
      _patient = p;
      _ctx = null;
      _visitTouched = false;
      _doctorTouched = false;
    });
    if (isLive) _loadContext(p.str('id'));
  }

  List<Map<String, dynamic>> get _withPlaces => _doctors.where((d) => d.list('locations').isNotEmpty).toList();

  List<Map<String, dynamic>> get _places =>
      _doctors.where((d) => d.str('userId') == _doctorId).firstOrNull?.list('locations') ?? const [];

  void _pickDoctor(String id, {bool load = true}) {
    _doctorId = id;
    final places = _places;
    _locationId = places.length == 1 ? places.first.str('id') : (places.any((l) => l.str('id') == _locationId) ? _locationId : places.firstOrNull?.str('id'));
    if (load) _loadDays();
  }

  // ── Smart defaults from the patient's story ──
  List<Map<String, dynamic>> _ctxList(String k) => _ctx?.list(k) ?? const [];
  bool _forDoctor(Map<String, dynamic> m) => m['doctorId'] == null || m.str('doctorId') == _doctorId;

  Map<String, dynamic>? get _dueFollowUp =>
      _ctxList('followUps').where((f) => const ['not_booked', 'no_reply'].contains(f.str('status')) && _forDoctor(f)).firstOrNull;

  Map<String, dynamic>? get _lastVisit => _ctxList('lastVisits').where((v) => v.str('doctorId') == _doctorId).firstOrNull;

  List<String> get _reportsIn => [
        for (final r in _ctxList('reportsIn'))
          if (_forDoctor(r)) r.str('name'),
        for (final f in _ctxList('followUps'))
          if (f.str('status') == 'reports_in' && _forDoctor(f) && _ctxList('reportsIn').isEmpty) 'Reports',
      ].where((s) => s.isNotEmpty).toSet().toList();

  /// New visit · Follow-up · Report review, from what's waiting for this doctor.
  int get _smartVisit {
    if (_ctx == null) return _visit;
    if (_reportsIn.isNotEmpty) return 2;
    if (_dueFollowUp != null) return 1;
    final seen = _ctxList('lastVisits').any((v) => v.str('doctorId') == _doctorId);
    return seen ? 1 : 0;
  }

  /// The doctor the patient is due back with, else the one they saw last; then the visit type.
  void _applySmart() {
    if (_ctx == null) return;
    if (!_doctorTouched && _withPlaces.length > 1) {
      final mine = {for (final d in _withPlaces) d.str('userId')};
      final due = _ctxList('followUps').where((f) => mine.contains(f.str('doctorId'))).firstOrNull;
      final last = _ctxList('lastVisits').where((v) => mine.contains(v.str('doctorId'))).firstOrNull;
      final pick = due?.str('doctorId') ?? last?.str('doctorId');
      if (pick != null && pick != _doctorId) _pickDoctor(pick, load: false);
    }
    if (!_visitTouched) _visit = _smartVisit;
  }

  /// Why the visit type was chosen, under it.
  String? _visitHint(BuildContext context) {
    if (_ctx == null || _patient == null) return null;
    final doctor = F.doctorShort(_doctors.where((d) => d.str('userId') == _doctorId).firstOrNull?.str('name') ?? '');
    final reports = _reportsIn;
    final due = _dueFollowUp;
    final last = _lastVisit;
    if (reports.isNotEmpty) return tr(context, 'Reports in to review: #1').replaceFirst('#1', reports.take(3).join(', '));
    if (due != null) {
      final at = F.date(due['dueDate']);
      final advice = due.str('adviceText');
      return [
        if (at != null) tr(context, 'Follow-up due #1').replaceFirst('#1', d7DayShort(at)),
        if (advice.isNotEmpty) advice,
      ].join(' · ');
    }
    if (last == null) return doctor.isEmpty ? 'First visit with this doctor' : tr(context, 'First visit with #1').replaceFirst('#1', doctor);
    final at = F.date(last['at']);
    final why = [last.str('reason'), last.str('diagnosis')].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    return [
      if (at != null) tr(context, 'Last visit #1').replaceFirst('#1', F.dayMonth(at)),
      if (why.isNotEmpty) why,
    ].join(' · ');
  }

  /// "Sugar review" for diabetes, "BP review" for hypertension…
  static String _conditionReason(BuildContext context, String c) {
    final l = c.toLowerCase();
    if (l.contains('diabet')) return tr(context, 'Sugar review');
    if (l.contains('hypertens') || l.contains('blood pressure')) return tr(context, 'BP review');
    if (l.contains('thyroid')) return tr(context, 'Thyroid review');
    if (l.contains('asthma') || l.contains('copd')) return tr(context, 'Breathing review');
    if (l.contains('kidney') || l.contains('ckd')) return tr(context, 'Kidney review');
    if (l.contains('heart') || l.contains('cardi')) return tr(context, 'Heart review');
    return tr(context, '#1 review').replaceFirst('#1', c);
  }

  /// Tap-to-add reasons: this patient's first, then the common ones for the visit type.
  List<String> _suggestions(BuildContext context) {
    final type = _visitTypes[_visit].$1;
    final out = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || t.length > 40 || out.any((x) => x.toLowerCase() == t.toLowerCase())) return;
      out.add(t);
    }

    if (_ctx != null || !isLive) {
      final conditions = [
        for (final c in (_patient?['conditions'] as List? ?? _ctx?.obj('patient')['conditions'] as List? ?? const [])) '$c',
      ];
      if (type == 'report_review') {
        for (final r in _reportsIn) {
          add(r == 'Reports' ? tr(context, 'Report review') : tr(context, '#1 report').replaceFirst('#1', r));
        }
        for (final t in _ctxList('pendingTests').where(_forDoctor).take(3)) {
          add(tr(context, '#1 report').replaceFirst('#1', t.str('name')));
        }
      }
      if (type == 'follow_up') {
        add(_dueFollowUp?.str('adviceText') ?? '');
        for (final c in conditions.take(3)) {
          add(_conditionReason(context, c));
        }
        add(_lastVisit?.str('reason') ?? '');
      }
    }
    for (final r in _commonReasons[type]!) {
      add(tr(context, r));
    }
    return out.take(12).toList();
  }

  List<String> get _reasonParts => [for (final s in _reason.text.split(',')) if (s.trim().isNotEmpty) s.trim()];

  bool _hasReason(String r) => _reasonParts.any((s) => s.toLowerCase() == r.toLowerCase());

  void _toggleReason(String r) {
    final parts = _reasonParts;
    if (_hasReason(r)) {
      parts.removeWhere((s) => s.toLowerCase() == r.toLowerCase());
    } else {
      parts.add(r);
    }
    _reason.text = parts.join(', ');
    _reason.selection = TextSelection.collapsed(offset: _reason.text.length);
  }

  Future<void> _speakReason() async {
    final said = await Voice.dictate(context, title: 'Reason for visit', purpose: 'symptoms');
    if (said == null || said.trim().isEmpty || !mounted) return;
    final before = _reason.text.trimRight();
    _reason.text = before.isEmpty ? said.trim() : (before.endsWith(',') ? '$before ${said.trim()}' : '$before, ${said.trim()}');
    _reason.selection = TextSelection.collapsed(offset: _reason.text.length);
  }

  // ── Days and times ──
  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// A follow-up due later than the booking window: those days are offered too.
  DateTime? get _until => F.date(_dueFollowUp?['dueDate']);

  /// The next [_stripDays] days the doctor sees patients here with free times.
  Future<void> _loadDays({bool quiet = false}) async {
    final doctor = _doctorId;
    final place = _locationId;
    if (!isLive || doctor == null || place == null) return;
    if (!quiet) {
      setState(() {
        _loadingDays = true;
        _days = const [];
        _slots = const [];
        _slot = null;
      });
    }
    try {
      final (days, _) = await loadBookingDays(doctorId: doctor, locationId: place, from: _today, days: _stripDays, until: _until);
      if (!mounted || doctor != _doctorId || place != _locationId) return;
      final open = days.where((d) => d.bookable).toList();
      setState(() {
        _days = open;
        // Keep the chosen day if it's still bookable (or chosen from the calendar); else
        // the follow-up's due day when it's in the strip, else the first free day.
        final keep = _date != null && (open.any((d) => F.sameDay(d.date, _date!)) || _date!.isAfter(open.isEmpty ? _today : open.last.date));
        if (!keep || !quiet) {
          final due = _visitTypes[_visit].$1 == 'follow_up' ? _until : null;
          final atDue = due == null ? null : open.where((d) => !d.date.isBefore(DateTime(due.year, due.month, due.day))).firstOrNull;
          _date = keep && quiet ? _date : (atDue ?? open.firstOrNull)?.date;
        }
      });
      await _loadSlots(quiet: quiet);
    } on ApiException catch (e) {
      if (mounted && !quiet) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingDays = false);
    }
  }

  /// The chosen day's times (already-booked crossed out; past ones today left out).
  Future<void> _loadSlots({bool quiet = false}) async {
    final doctor = _doctorId;
    final place = _locationId;
    final day = _date;
    if (!isLive || doctor == null || place == null || day == null) {
      if (mounted && !quiet) setState(() => _slots = const []);
      return;
    }
    if (!quiet) setState(() => _loadingSlots = true);
    try {
      final s = (await Api.I.get('/api/doctors/$doctor/slots', query: {'locationId': place, 'date': bookingDayKey(day)}) as Map).cast<String, dynamic>();
      if (!mounted || doctor != _doctorId || place != _locationId || day != _date) return;
      final now = DateTime.now();
      final slots = [
        for (final x in s.list('slots'))
          if ((F.date(x['startAt']) ?? now).isAfter(now)) x,
      ];
      setState(() {
        _slots = s['open'] == true ? slots : const [];
        // Someone else took the chosen time meanwhile.
        if (_slot != null && !_slots.any((x) => x.str('startAt') == _slot && x['available'] == true)) {
          _slot = null;
          if (quiet) toast(context, 'That time was just taken. Choose another.');
        }
      });
    } on ApiException catch (e) {
      if (mounted && !quiet) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  /// Quiet refresh while the screen is open (others booking at the same time).
  void _refreshTimes() {
    if (!mounted || _busy || _loadingDays || _loadingSlots || _doctorId == null) return;
    _loadDays(quiet: true);
  }

  void _pickDay(DateTime d) {
    setState(() {
      _date = d;
      _slot = null;
    });
    _loadSlots();
  }

  Future<void> _moreDates() async {
    final doctor = _doctorId;
    final place = _locationId;
    if (doctor == null || place == null) return;
    final due = _until;
    final d = await pickBookingDay(
      context,
      doctorId: doctor,
      locationId: place,
      selected: _date,
      until: due,
      mark: due,
      markLabel: due == null ? null : tr(context, 'Follow-up due #1').replaceFirst('#1', d7DayShort(due)),
    );
    if (d == null || !mounted) return;
    _pickDay(d);
  }

  // ── Booking ──
  Future<void> _book() async {
    if (_patient == null) return toast(context, 'Choose the patient first');
    if (_doctorId == null || _locationId == null) return toast(context, 'Choose the doctor and place');
    if (_slot == null || _date == null) return toast(context, 'Choose a time');
    final time = _slots.where((s) => s.str('startAt') == _slot).firstOrNull?.str('time') ?? '';
    final when = '${d7DayShort(_date!)}, $time';
    if (!isLive) return _done(when, '04');
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final appt = (await Api.I.post('/api/appointments', {
        'patientId': _patient!.str('id'),
        'doctorId': _doctorId,
        'locationId': _locationId,
        'startAt': _slot,
        'visitType': _visitTypes[_visit].$1,
        if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        'confirmed': true,
      }) as Map)
          .cast<String, dynamic>();
      if (mounted) await _done(when, appt.str('token'));
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message);
      if (e.code == 'SLOT_TAKEN') _loadDays(quiet: true); // someone else took it: show fresh times
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(String when, String token) async {
    final doctor = _doctors.where((d) => d.str('userId') == _doctorId).firstOrNull?.str('name') ?? '';
    final place = _places.where((l) => l.str('id') == _locationId).firstOrNull?.str('name') ?? '';
    final again = await openSheet<bool>(
      context,
      (sc) => _BookedSheet(
        name: _patient!.str('name', 'Patient'),
        when: when,
        detail: [if (doctor.isNotEmpty) F.doctorShort(doctor), if (place.isNotEmpty) place, if (token.isNotEmpty) 'Token $token'].join(' · '),
        hasApp: _patient!['hasApp'] == true || _ctx?.obj('patient')['hasApp'] == true,
      ),
    );
    if (!mounted) return;
    if (again == true) {
      setState(() {
        _patient = null;
        _ctx = null;
        _slot = null;
        _visitTouched = false;
        _doctorTouched = false;
        _reason.clear();
        _search.clear();
      });
      _find('');
      _loadDays();
    } else {
      Nav.back(context);
    }
  }

  Future<void> _manageExisting(String id) async {
    await openSheet<Object>(context, (_) => AppointmentsManageSheet(appointmentId: id));
    if (!mounted) return;
    final pid = _patient?.str('id');
    if (pid != null) _loadContext(pid, quiet: true);
    _loadDays(quiet: true);
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final canBook = _patient != null && _slot != null && !_busy;
    return MpPage(
      header: const MpHeader('Book appointment', subtitle: 'Confirmed visit for a patient'),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: MpButton(_busy ? 'Booking…' : 'Book confirmed visit', onTap: canBook ? _book : null),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[Text(_error!, style: tx(14, c: MP.red)), const Gap(16)],
            const _Step('1 · Patient'),
            const Gap(12),
            if (_patient == null) ..._patientPicker() else ...[_chosenPatient(), ..._alreadyBooked()],
            const Gap(28),
            _Step('2 · Doctor and visit', muted: _patient == null),
            const Gap(12),
            ..._doctorPicker(),
            const Gap(28),
            _Step('3 · Date and time', muted: _patient == null || _locationId == null),
            const Gap(12),
            ..._timePicker(),
          ],
        ),
      ),
    );
  }

  List<Widget> _patientPicker() {
    final q = _search.text.trim();
    return [
      MpInput(controller: _search, hint: 'Name or mobile number', leadingIcon: I.search, onChanged: _onSearch, autofillHints: const []),
      const Gap(12),
      if (_searching && _results.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
      else if (_results.isEmpty)
        MpCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.isEmpty ? 'No patients yet' : 'No patient matches “$q”', style: tx(15, w: w600)),
              const Gap(4),
              Text('Register them first, then book their visit.', style: tx(14, c: MP.ink2, h: 1.4)),
              const Gap(12),
              MpButton.small('Register patient', expand: false, onTap: () => Nav.go(context, 'Add-Patient')),
            ],
          ),
        )
      else ...[
        if (_searched.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Recent patients', style: tx(13, w: w600, c: MP.ink3))),
        MpCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < _results.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 72, color: MP.line),
                _PatientRow(_results[i], onTap: () => _choosePatient(_results[i])),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _chosenPatient() {
    final p = _patient!;
    return MpCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          MpAvatar(F.initials(p.str('name', 'P')), size: 44, fontSize: 15, photo: _photoOf(p)),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.str('name', 'Patient'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w700)),
                const Gap(2),
                Text(_facts(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2, tab: true)),
              ],
            ),
          ),
          D7Btn(
            'Change',
            bg: MP.white,
            fg: MP.primary,
            size: 14,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onTap: () => setState(() {
              _patient = null;
              _ctx = null;
            }),
          ),
        ],
      ),
    );
  }

  /// Visits this patient already has coming up (so the desk doesn't book twice).
  List<Widget> _alreadyBooked() {
    final up = _ctxList('upcoming');
    if (up.isEmpty) return const [];
    return [
      const Gap(8),
      for (final a in up.take(2))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Ico(I.calendar, size: 16, color: MP.amber),
                const Gap(8),
                Expanded(
                  child: Text(
                    () {
                      final at = F.date(a['startAt']);
                      final day = at == null ? '' : (F.sameDay(at, DateTime.now()) ? '${tr(context, 'Today')}, ${F.time(at)}' : '${d7DayShort(at)}, ${F.time(at)}');
                      return [
                        tr(context, 'Already booked: #1').replaceFirst('#1', day),
                        if (a.str('doctorName').isNotEmpty) F.doctorShort(a.str('doctorName')),
                        if (a.str('locationName').isNotEmpty) a.str('locationName'),
                      ].join(' · ');
                    }(),
                    style: tx(13, h: 1.4),
                  ),
                ),
                if (isLive)
                  MpHitSlop(
                    child: Tap(
                      onTap: () => _manageExisting(a.str('id')),
                      radius: 8,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('Manage', style: tx(13, w: w600, c: MP.primary)),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _doctorPicker() {
    final withPlaces = _withPlaces;
    if (isLive && _doctors.isNotEmpty && withPlaces.isEmpty) {
      return [Text('No doctor has a clinic schedule yet. Set up hours in Profile → Schedule.', style: tx(14, c: MP.ink2, h: 1.4))];
    }
    final hint = _visitHint(context);
    final reasons = _suggestions(context);
    return [
      if (withPlaces.length > 1) ...[
        Text('Doctor', style: tx(14, w: w600)),
        const Gap(8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in withPlaces)
            _DoctorChip(
              d,
              on: d.str('userId') == _doctorId,
              onTap: () {
                if (d.str('userId') == _doctorId) return;
                setState(() {
                  _doctorTouched = true;
                  _pickDoctor(d.str('userId'));
                  if (!_visitTouched) _visit = _smartVisit;
                });
              },
            ),
        ]),
        const Gap(16),
      ],
      if (_places.length > 1) ...[
        Text('Place', style: tx(14, w: w600)),
        const Gap(8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in _places)
            D7Pill(l.str('name'), on: l.str('id') == _locationId, onTap: () {
              if (l.str('id') == _locationId) return;
              setState(() => _locationId = l.str('id'));
              _loadDays();
            }),
        ]),
        const Gap(16),
      ] else if (_places.length == 1 && withPlaces.length == 1) ...[
        Text('${F.doctorShort(withPlaces.first.str('name'))} · ${_places.first.str('name')}', style: tx(15, w: w600)),
        const Gap(16),
      ],
      Text('Visit type', style: tx(14, w: w600)),
      const Gap(8),
      MpSegmented(
        options: [for (final v in _visitTypes) v.$2],
        index: _visit,
        onChanged: (i) => setState(() {
          _visit = i;
          _visitTouched = true;
        }),
      ),
      if (hint != null && hint.isNotEmpty) ...[
        const Gap(8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.clock, size: 14, color: MP.ink3)),
            const Gap(6),
            Expanded(child: Text(hint, style: tx(13, c: MP.ink2, h: 1.4))),
          ],
        ),
      ],
      const Gap(16),
      MpInput(
        controller: _reason,
        label: 'Reason',
        labelTrailing: 'optional',
        hint: 'e.g. Sugar review, report check',
        trailing: Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
          child: MpIconButton(I.mic, label: 'Speak the reason', iconSize: 20, color: MP.primary, background: MP.primarySoft, onTap: _speakReason),
        ),
      ),
      const Gap(10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in reasons) MpChip(r, selected: _hasReason(r), tonal: true, height: 36, onTap: () => _toggleReason(r)),
        ],
      ),
    ];
  }

  List<Widget> _timePicker() {
    if (_doctorId == null || _locationId == null) {
      return [Text('Choose the doctor and place to see free times.', style: tx(14, c: MP.ink3))];
    }
    if (_loadingDays) {
      return const [Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))];
    }
    final now = DateTime.now();
    final due = _visitTypes[_visit].$1 == 'follow_up' ? _until : null;
    final strip = [..._days.map((d) => d.date)];
    // A day picked in the calendar beyond the strip shows in it too.
    if (_date != null && !strip.any((d) => F.sameDay(d, _date!))) strip.add(_date!);
    final moreDates = D7Pill('More dates', borderOn: false, onTap: _moreDates);
    if (strip.isEmpty) {
      return [
        Text(tr(context, 'No free times in the next #1 days at this place.').replaceFirst('#1', '$_stripDays'), style: tx(14, c: MP.ink2, h: 1.4)),
        const Gap(12),
        Align(alignment: Alignment.centerLeft, child: moreDates),
      ];
    }
    final day = _days.where((d) => _date != null && F.sameDay(d.date, _date!)).firstOrNull;
    final free = _slots.where((s) => s['available'] == true).length;
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < strip.length; i++) ...[
            if (i > 0) const Gap(8),
            D7Pill(
              F.sameDay(strip[i], now) ? 'Today' : d7DayShort(strip[i]),
              on: _date != null && F.sameDay(strip[i], _date!),
              borderOn: false,
              dot: due != null && F.sameDay(strip[i], due) ? MP.amber : null,
              onTap: () => _pickDay(strip[i]),
            ),
          ],
          const Gap(8),
          moreDates,
        ]),
      ),
      const Gap(12),
      if (_date != null)
        Text(
          [
            d7Date(_date!),
            if (!_loadingSlots) tr(context, free == 1 ? '1 free time' : '#1 free times').replaceFirst('#1', '${day?.free ?? free}'),
            if (due != null && F.sameDay(_date!, due)) tr(context, 'Follow-up due'),
          ].join(' · '),
          style: tx(13, w: w600, c: MP.ink2),
        ),
      const Gap(12),
      if (_loadingSlots)
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
      else if (_slots.isEmpty)
        Text('No times left on this day. Choose another day.', style: tx(14, c: MP.ink2, h: 1.4))
      else
        ..._slotGroups(),
      const Gap(10),
      Text('Crossed-out times are already booked.', style: tx(13, c: MP.ink3)),
    ];
  }

  /// Times by part of the day when the day has more than one (Morning · Afternoon · Evening).
  List<Widget> _slotGroups() {
    int part(Map<String, dynamic> s) {
      final at = F.date(s['startAt']);
      final h = at?.hour ?? 9;
      return h < 12 ? 0 : (h < 17 ? 1 : 2);
    }

    const names = ['Morning', 'Afternoon', 'Evening'];
    final parts = <int, List<Map<String, dynamic>>>{};
    for (final s in _slots) {
      parts.putIfAbsent(part(s), () => []).add(s);
    }
    final keys = parts.keys.toList()..sort();
    Widget grid(List<Map<String, dynamic>> slots) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in slots)
            _TimeChip(
              s.str('time'),
              free: s['available'] == true,
              on: s.str('startAt') == _slot,
              onTap: () => setState(() => _slot = s.str('startAt')),
            ),
        ]);
    if (keys.length < 2) return [grid(_slots)];
    return [
      for (final (i, k) in keys.indexed) ...[
        if (i > 0) const Gap(14),
        Text(names[k], style: tx(13, w: w600, c: MP.ink3)),
        const Gap(8),
        grid(parts[k]!),
      ],
    ];
  }

  static String? _photoOf(Map<String, dynamic> p) {
    final s = p.str('photo', p.str('patientPhoto'));
    return s.isEmpty ? null : s;
  }

  static String _facts(Map<String, dynamic> p) {
    final g = p.str('gender');
    final phone = p.str('phone');
    return [
      if (p['age'] != null) '${p['age']} yrs',
      if (g.isNotEmpty) g[0].toUpperCase() + g.substring(1),
      if (phone.length == 10) '+91 ${phone.substring(0, 5)} ${phone.substring(5)}',
    ].join(' · ');
  }
}

/// "1 · PATIENT" step heading (greyed until the step before is done).
class _Step extends StatelessWidget {
  final String text;
  final bool muted;
  const _Step(this.text, {this.muted = false});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: tx(12, w: w700, c: muted ? MP.lineStrong : MP.ink3, h: 1.35, em: 0.06));
}

class _PatientRow extends StatelessWidget {
  final Map<String, dynamic> p;
  final VoidCallback onTap;
  const _PatientRow(this.p, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Conditions come as names ("Type 2 diabetes").
    final conditions = [for (final c in (p['conditions'] as List? ?? const [])) '$c'].where((c) => c.isNotEmpty).take(2).join(', ');
    return Semantics(
      button: true,
      child: Tap(
        onTap: onTap,
        radius: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            MpAvatar(F.initials(p.str('name', 'P')), size: 44, fontSize: 15, photo: _StaffBookScreenState._photoOf(p)),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.str('name', 'Patient'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                  const Gap(2),
                  Text(
                    [_StaffBookScreenState._facts(p), if (conditions.isNotEmpty) conditions].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tx(13, c: MP.ink2, tab: true),
                  ),
                ],
              ),
            ),
            const Ico(I.chevronRight, size: 18, color: MP.ink3),
          ],
        ),
      ),
    );
  }
}

/// A doctor to book with: photo (or initials) and short name, a pill like D7Pill.
class _DoctorChip extends StatelessWidget {
  final Map<String, dynamic> d;
  final bool on;
  final VoidCallback onTap;
  const _DoctorChip(this.d, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = d.str('name');
    final photo = d.str('photo');
    return MpHitSlop(
      child: Semantics(
        button: true,
        selected: on,
        label: name,
        excludeSemantics: true,
        child: Tap(
          onTap: onTap,
          radius: 999,
          color: on ? MP.primarySoft : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MpAvatar(F.initials(name), size: 32, fontSize: 12, photo: photo.isEmpty ? null : photo),
                const Gap(8),
                Flexible(
                  child: Text(F.doctorShort(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: w600, c: on ? MP.primary : MP.ink2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A time: white with a border when free, filled blue when chosen, grey and
/// crossed out when booked.
class _TimeChip extends StatelessWidget {
  final String time;
  final bool free;
  final bool on;
  final VoidCallback onTap;
  const _TimeChip(this.time, {required this.free, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      time,
      style: tx(14, w: w600, tab: true, c: on ? MP.white : (free ? MP.ink : MP.ink3), deco: free ? null : TextDecoration.lineThrough),
    );
    return MpHitSlop(
      child: Semantics(
        button: free,
        selected: on,
        label: free ? time : '$time, booked',
        excludeSemantics: true,
        child: Tap(
          onTap: free ? onTap : null,
          radius: 12,
          color: on ? MP.primary : (free ? MP.white : MP.fill),
          border: on ? MP.primary : (free ? MP.lineStrong : MP.line),
          child: SizedBox(width: 96, height: 44, child: Center(child: label)),
        ),
      ),
    );
  }
}

/// "Visit confirmed" sheet after booking: who, when, where; Done or Book another.
class _BookedSheet extends StatelessWidget {
  final String name;
  final String when;
  final String detail;
  final bool hasApp;
  const _BookedSheet({required this.name, required this.when, required this.detail, required this.hasApp});

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: MP.greenSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Ico(I.check, size: 28, color: MP.green, stroke: 2.5),
            ),
          ),
          const Gap(16),
          Text('Visit confirmed', textAlign: TextAlign.center, style: tx(22, w: w700, h: 1.25)),
          const Gap(6),
          Text('$name · $when', textAlign: TextAlign.center, style: tx(16, w: w600, h: 1.4)),
          if (detail.isNotEmpty) ...[
            const Gap(2),
            Text(detail, textAlign: TextAlign.center, style: tx(14, c: MP.ink2, h: 1.4)),
          ],
          const Gap(16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Text(
              hasApp
                  ? 'The patient has been told in the MedPin app and on WhatsApp.'
                  : 'The patient has been sent a WhatsApp message if their number is on WhatsApp.',
              style: tx(14, h: 1.45),
            ),
          ),
          const Gap(20),
          MpButton('Done', onTap: () => Navigator.pop(context, false)),
          const Gap(8),
          MpButton('Book another', kind: MpBtn.secondary, onTap: () => Navigator.pop(context, true)),
        ],
      ),
    );
  }
}

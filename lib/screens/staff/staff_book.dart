import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d7.dart';
import '../../widgets/i18n.dart';

/// "Book appointment" (front desk): pick the patient first, then the doctor,
/// place and visit type, then a free date and time. The visit is saved as
/// confirmed (the desk agreed it with the patient) and the patient gets a
/// "Visit confirmed" message in the app and on WhatsApp.
///
/// Live: GET /api/patients?q= (search), GET /api/doctors, GET
/// /api/doctors/:id/slots for the next days, POST /api/appointments
/// {confirmed: true}. Opened with {'patientId'} the patient is chosen already.
class StaffBookScreen extends StatefulWidget {
  const StaffBookScreen({super.key});

  @override
  State<StaffBookScreen> createState() => _StaffBookScreenState();
}

const _visitTypes = [('new', 'New visit'), ('follow_up', 'Follow-up'), ('report_review', 'Report review')];

/// How many days ahead to look for open sessions.
const _lookAhead = 14;

class _StaffBookScreenState extends State<StaffBookScreen> {
  // ── 1 · Patient ──
  Map<String, dynamic>? _patient;
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  String _searched = '';

  // ── 2 · Doctor, place and visit ──
  List<Map<String, dynamic>> _doctors = const [];
  String? _doctorId;
  String? _locationId;
  int _visit = 1;
  final _reason = TextEditingController();

  // ── 3 · Date and time ──
  List<(DateTime, List<Map<String, dynamic>>)> _days = const [];
  bool _loadingSlots = false;
  int _day = 0;
  String? _slot; // startAt
  String? _error;
  bool _busy = false;
  bool _started = false;

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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  // ── Design preview ──
  void _preview() {
    _patient = {'id': 'p1', 'name': 'Amit Pal', 'age': 42, 'gender': 'male', 'phone': '9831120770'};
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
    final today = DateTime.now();
    _days = [
      for (var i = 1; i <= 4; i++)
        (
          DateTime(today.year, today.month, today.day + i),
          [
            for (final t in ['9:00 AM', '9:15 AM', '9:30 AM', '9:45 AM', '10:00 AM', '10:15 AM'])
              {'time': t, 'startAt': '$i-$t', 'available': t != '9:15 AM'},
          ],
        ),
    ];
  }

  // ── Loading ──
  Future<void> _loadDoctors() async {
    try {
      final list = await Api.I.get('/api/doctors') as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _doctors = [for (final x in list) (x as Map).cast<String, dynamic>()];
        final withPlaces = _doctors.where((d) => d.list('locations').isNotEmpty).toList();
        if (withPlaces.length == 1) _pickDoctor(withPlaces.first.str('userId'), load: false);
      });
      if (_doctorId != null) _loadSlots();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadPatient(String id) async {
    try {
      final r = (await Api.I.get('/api/patients/$id') as Map).cast<String, dynamic>();
      final p = r.obj('patient');
      if (mounted && p.isNotEmpty) setState(() => _patient = {...p, 'id': p.str('id', id)});
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
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

  List<Map<String, dynamic>> get _places =>
      _doctors.where((d) => d.str('userId') == _doctorId).firstOrNull?.list('locations') ?? const [];

  void _pickDoctor(String id, {bool load = true}) {
    _doctorId = id;
    final places = _places;
    _locationId = places.length == 1 ? places.first.str('id') : (places.any((l) => l.str('id') == _locationId) ? _locationId : places.firstOrNull?.str('id'));
    if (load) _loadSlots();
  }

  /// The next [_lookAhead] days that have free times.
  Future<void> _loadSlots() async {
    final doctor = _doctorId;
    final place = _locationId;
    if (!isLive || doctor == null || place == null) return;
    setState(() {
      _loadingSlots = true;
      _days = const [];
      _slot = null;
      _day = 0;
    });
    final today = DateTime.now();
    final days = [for (var i = 0; i < _lookAhead; i++) DateTime(today.year, today.month, today.day + i)];
    try {
      final res = await Future.wait([
        for (final d in days) Api.I.get('/api/doctors/$doctor/slots', query: {'locationId': place, 'date': d7Key(d)}),
      ]);
      if (!mounted || doctor != _doctorId || place != _locationId) return;
      final open = <(DateTime, List<Map<String, dynamic>>)>[];
      for (var i = 0; i < days.length; i++) {
        final s = (res[i] as Map).cast<String, dynamic>();
        final slots = s.list('slots');
        if (s['open'] == true && slots.any((x) => x['available'] == true)) open.add((days[i], slots));
      }
      setState(() => _days = open);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  // ── Booking ──
  Future<void> _book() async {
    if (_patient == null) return toast(context, 'Choose the patient first');
    if (_doctorId == null || _locationId == null) return toast(context, 'Choose the doctor and place');
    if (_slot == null) return toast(context, 'Choose a time');
    final (day, slots) = _days[_day];
    final time = slots.where((s) => s.str('startAt') == _slot).firstOrNull?.str('time') ?? '';
    final when = '${d7DayShort(day)}, $time';
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
      if (e.code == 'SLOT_TAKEN') _loadSlots(); // someone else took it: show fresh times
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
        hasApp: _patient!['hasApp'] == true,
      ),
    );
    if (!mounted) return;
    if (again == true) {
      setState(() {
        _patient = null;
        _slot = null;
        _reason.clear();
        _search.clear();
      });
      _find('');
      _loadSlots();
    } else {
      Nav.back(context);
    }
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
            if (_patient == null) ..._patientPicker() else _chosenPatient(),
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
                _PatientRow(_results[i], onTap: () => setState(() => _patient = _results[i])),
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
          MpAvatar(F.initials(p.str('name', 'P')), size: 44, fontSize: 15),
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
          D7Btn('Change', bg: MP.white, fg: MP.primary, size: 14, height: 44, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => setState(() => _patient = null)),
        ],
      ),
    );
  }

  List<Widget> _doctorPicker() {
    final withPlaces = _doctors.where((d) => d.list('locations').isNotEmpty).toList();
    if (isLive && _doctors.isNotEmpty && withPlaces.isEmpty) {
      return [Text('No doctor has a clinic schedule yet. Set up hours in Profile → Schedule.', style: tx(14, c: MP.ink2, h: 1.4))];
    }
    return [
      if (withPlaces.length > 1) ...[
        Text('Doctor', style: tx(14, w: w600)),
        const Gap(8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in withPlaces)
            D7Pill(F.doctorShort(d.str('name')), on: d.str('userId') == _doctorId, onTap: () => setState(() => _pickDoctor(d.str('userId')))),
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
              _loadSlots();
            }),
        ]),
        const Gap(16),
      ] else if (_places.length == 1 && withPlaces.length == 1) ...[
        Text('${F.doctorShort(withPlaces.first.str('name'))} · ${_places.first.str('name')}', style: tx(15, w: w600)),
        const Gap(16),
      ],
      Text('Visit type', style: tx(14, w: w600)),
      const Gap(8),
      MpSegmented(options: [for (final v in _visitTypes) v.$2], index: _visit, onChanged: (i) => setState(() => _visit = i)),
      const Gap(16),
      MpInput(controller: _reason, label: 'Reason', labelTrailing: 'optional', hint: 'e.g. Sugar review, report check'),
    ];
  }

  List<Widget> _timePicker() {
    if (_doctorId == null || _locationId == null) {
      return [Text('Choose the doctor and place to see free times.', style: tx(14, c: MP.ink3))];
    }
    if (_loadingSlots) {
      return const [Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))];
    }
    if (_days.isEmpty) {
      return [Text('No free times in the next $_lookAhead days at this place.', style: tx(14, c: MP.ink2, h: 1.4))];
    }
    final (_, slots) = _days[_day];
    final now = DateTime.now();
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < _days.length; i++) ...[
            if (i > 0) const Gap(8),
            D7Pill(
              F.sameDay(_days[i].$1, now) ? 'Today' : d7DayShort(_days[i].$1),
              on: i == _day,
              borderOn: false,
              onTap: () => setState(() {
                _day = i;
                _slot = null;
              }),
            ),
          ],
        ]),
      ),
      const Gap(16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in slots)
          _TimeChip(
            s.str('time'),
            free: s['available'] == true,
            on: s.str('startAt') == _slot,
            onTap: () => setState(() => _slot = s.str('startAt')),
          ),
      ]),
      const Gap(10),
      Text('Crossed-out times are already booked.', style: tx(13, c: MP.ink3)),
    ];
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
            MpAvatar(F.initials(p.str('name', 'P')), size: 44, fontSize: 15),
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

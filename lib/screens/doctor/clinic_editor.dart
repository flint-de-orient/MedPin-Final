import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../data/where.dart';
import '../../widgets/clinic_map.dart';
import '../../widgets/file_view.dart';
import '../../widgets/mp.dart';
import 'common_d11.dart';
import 'common_d7.dart';
import '../../widgets/i18n.dart';

/// Design: Clinic-Editor.dc.html — "Location editor" (Edit location).
/// Live: args {'locationId'} → GET /api/locations/:id, saved with PATCH;
/// without it a new location is added (POST /api/locations). Closures:
/// POST / DELETE /api/locations/:id/closures; deactivate / activate:
/// POST /api/locations/:id/deactivate (409 HAS_UPCOMING → tap again to confirm).
/// Who may change what comes from the server (`can`: details / hours /
/// closures, and `canEdit` per doctor): the owner and practice manager change
/// everything, the front desk adds and removes closures, and the rest is
/// shown read-only with one line saying who changes it. A doctor's row opens
/// their hours here (PUT /api/locations/:id/doctors/:doctorId/hours), or the
/// doctor's own Profile-Schedule for themselves.
class ClinicEditorScreen extends StatefulWidget {
  const ClinicEditorScreen({super.key});

  @override
  State<ClinicEditorScreen> createState() => _ClinicEditorScreenState();
}

class _ClinicEditorScreenState extends State<ClinicEditorScreen> with LiveData {
  // A form for the owner / practice manager: don't refresh by itself while it's
  // being filled in. Others only see it (and add closures): it follows changes live.
  @override
  bool get autoRefresh => !_manager;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _name = TextEditingController(text: 'City Care Clinic — Salt Lake');
  final _address = TextEditingController(text: 'DD-24, Sector 1, Salt Lake, Kolkata 700064');
  final _phone = TextEditingController(text: '033 4012 5678');
  final _tagline = TextEditingController(text: 'Diabetes, thyroid and heart care');
  final _printedName = TextEditingController(text: 'Dr. Arjun Sen, MBBS, MD (Medicine)');
  final _regNo = TextEditingController(text: 'WBMC 64213');
  final _mapUrl = TextEditingController(text: 'https://maps.app.goo.gl/Qx7bR2mLk9');
  ({double lat, double lng})? _pinAt;

  // Address ↔ map: a typed address moves the pin; moving the map rewrites the address.
  Timer? _addrTimer;
  String? _addrNote; // "Pin moved to …" / "Couldn't find …"
  bool _addrNoteBad = false;

  /// Live: the location being edited (null = adding a new one).
  String? _locationId;

  /// Closure ids, parallel to [_closures] (live); closures added to a new
  /// location ({reason, startDate, endDate, allDay, fromMin, toMin}) are posted after it is created.
  final _closureIds = <String?>[];
  final _pendingClosures = <Map<String, Object?>>[];

  /// Opening / closing minute per day (live).
  final _mins = [for (var i = 0; i < 7; i++) (540, 1200)];

  bool _confirmDeactivate = false;
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _tagline, _printedName, _regNo, _mapUrl]) {
      c.dispose();
    }
    _busy.dispose();
    _previewing.dispose();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    final args = Nav.args<Map>(context) ?? const {};
    _locationId = args['locationId'] as String?;
    if (_locationId == null) {
      if (data == null) {
        for (final c in [_name, _address, _phone, _tagline, _printedName, _regNo, _mapUrl]) {
          c.clear();
        }
        _closures.clear();
        _closureIds.clear();
        _doctorsLive = const [];
        _doctorMaps = const [];
        for (var i = 0; i < 7; i++) {
          _open[i] = i < 6;
          _mins[i] = (540, 1200);
          _ranges[i] = '${d7Minutes(540)} – ${d7Minutes(1200)}';
        }
      }
      return {'new': true};
    }
    final r = await Future.wait([Api.I.get('/api/locations/$_locationId'), Api.I.get('/api/locations')]);
    final l = (r[0] as Map).cast<String, dynamic>();
    final row = (r[1] as Map).cast<String, dynamic>().list('items').where((x) => x.str('id') == _locationId).firstOrNull;
    final lh = l.obj('letterhead');
    _name.text = l.str('name');
    _address.text = l.str('address');
    _phone.text = l.str('phone');
    _tagline.text = lh.str('tagline');
    _printedName.text = lh.str('doctorNamePrinted');
    _regNo.text = lh.str('registrationNo');
    _mapUrl.text = l.str('googleMapsUrl');
    final hours = l.list('weeklyHours');
    for (var i = 0; i < 7; i++) {
      final h = hours.where((x) => x['weekday'] == d7Weekdays[i]).firstOrNull;
      _open[i] = h != null && h['isOpen'] != false;
      _mins[i] = (h?.numOr('opensAt', 540).toInt() ?? 540, h?.numOr('closesAt', 1200).toInt() ?? 1200);
      _ranges[i] = '${d7Minutes(_mins[i].$1)} – ${d7Minutes(_mins[i].$2)}';
    }
    _closures
      ..clear()
      ..addAll([for (final c in l.list('closures')) (_closureLabel(c), _closureNote(c))]);
    _closureIds
      ..clear()
      ..addAll([for (final c in l.list('closures')) c.str('id')]);
    _doctorMaps = l.list('doctors');
    _doctorsLive = [
      for (final d in _doctorMaps)
        (F.initials(d.str('name')), d.str('name'), _weekLine(d.list('week'))),
    ];
    _confirmDeactivate = false;
    return {...l, 'upcomingBookings': row?['upcomingBookings'] ?? 0};
  }

  /// 'Fri, 2 Oct 2026' or 'Tue 20 – Fri 23 Oct 2026'.
  static String _closureLabel(Map<String, dynamic> c) {
    final a = F.date(c['startDate']);
    final b = F.date(c['endDate']) ?? a;
    if (a == null || b == null) return '';
    if (F.sameDay(a, b)) return d7Date(a);
    final end = d7Date(b).replaceFirst(',', '');
    final start = a.month == b.month && a.year == b.year ? d7DayShort(a).substring(0, d7DayShort(a).lastIndexOf(' ')) : d7Date(a).replaceFirst(',', '');
    return '$start – $end';
  }

  /// 'Durga Puja · closed all day', 'Staff meeting · 2:00 – 4:00 PM' (part of the day).
  static String _closureNote(Map<String, dynamic> c) {
    final reason = c.str('reason', 'Closed all day');
    if (c['allDay'] != false || c['fromMin'] == null || c['toMin'] == null) return reason;
    return '$reason · ${d7Range(c.numOr('fromMin'), c.numOr('toMin'))}';
  }

  /// 'Mon–Sat · 9:00 AM – 1:00 PM', 'Tue · Thu · 5:00 – 8:00 PM'.
  static String _weekLine(List<Map<String, dynamic>> week) {
    final open = [
      for (final w in week)
        if ((w['sessions'] as List? ?? const []).isNotEmpty) {'weekday': w['weekday'], 'isOpen': true},
    ];
    if (open.isEmpty) return 'No hours here yet';
    // The most common session pattern.
    final counts = <String, int>{};
    for (final w in week) {
      final s = [for (final x in (w['sessions'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      if (s.isEmpty) continue;
      final label = s.map((x) => d7Range(x.numOr('startMin'), x.numOr('endMin'))).join(', ');
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final common = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return '${d7OpenDays(open)} · $common';
  }

  List<(String, String, String)>? _doctorsLive;

  /// The doctors' rows as the server sent them (photo, week, isMe, canEdit).
  List<Map<String, dynamic>> _doctorMaps = const [];

  List<(String, String, String)> get _doctorRows => _doctorsLive ?? _doctors;

  bool get _isNew => isLive && _locationId == null;

  /// Letterhead logo: url / name / "PNG · 48 KB" (live), or the design's sample.
  Map<String, Object?> get _logo {
    if (data == null) return const {};
    final l = data!.obj('letterhead').obj('logo');
    if (l.isEmpty) return {'name': 'No logo yet', 'meta': 'PNG or JPG, on a plain background'};
    final kb = (l.numOr('sizeBytes') / 1024).round();
    final type = l.str('mimeType').split('/').last.toUpperCase();
    final lh = data!.obj('letterhead');
    return {'url': l['url'], 'name': l.str('name', 'Logo'), 'meta': '$type · $kb KB', 'isDark': lh['logoIsDark'] == true, 'cleaned': lh['logoBackgroundRemoved']};
  }

  Future<void> _replaceLogo() async {
    if (!isLive) {
      toast(context, 'Choose a new logo file');
      return;
    }
    if (_locationId == null) {
      toast(context, 'Save the location first, then add its logo');
      return;
    }
    final file = await Files.chooseSource(context, title: 'Letterhead logo', allowPdf: false);
    if (file == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.upload('/api/locations/$_locationId/logo', files: {'file': [file]}));
    if (ok == null || !mounted) return;
    toast(context, (ok as Map)['backgroundRemoved'] == true ? 'Logo updated · background removed' : 'Logo updated');
    reload(quiet: true);
  }

  /// Hours per day (renderVals().hours). Sunday is closed; its range is the
  /// default used when it is switched on.
  final _ranges = [
    '9:00 AM – 8:00 PM',
    '9:00 AM – 8:00 PM',
    '9:00 AM – 8:00 PM',
    '9:00 AM – 8:00 PM',
    '9:00 AM – 8:00 PM',
    '9:00 AM – 2:00 PM',
    '9:00 AM – 2:00 PM',
  ];
  final _open = [true, true, true, true, true, true, false];

  /// Date, reason (renderVals().closures).
  final _closures = <(String, String)>[
    ('Fri, 2 Oct 2026', 'Gandhi Jayanti · closed all day'),
    ('Tue 20 – Fri 23 Oct 2026', 'Durga Puja · closed all day'),
  ];

  static const _doctors = [
    ('AS', 'Dr. Arjun Sen', 'Mon–Sat · 9:00 AM – 1:00 PM'),
    ('RM', 'Dr. Rina Mitra', 'Tue · Thu · 5:00 – 8:00 PM'),
  ];

  /// The saved pin (lat, lng), if any.
  (double, double)? get _savedPin {
    final c = data == null ? null : data!.obj('geo')['coordinates'] as List?;
    return c != null && c.length == 2 ? ((c[1] as num).toDouble(), (c[0] as num).toDouble()) : null;
  }

  /// A link MedPin made from the pin (not one the clinic pasted).
  static bool _isPinLink(String url) => url.contains('/maps/search/?api=1&query=');

  /// What the server says this person may change here (GET /api/locations/:id → can).
  Map<String, dynamic> get _can => data?.obj('can') ?? const {};

  /// Owners and practice managers run the clinic (manageClinic).
  static bool get _manager => Session.I.isOwner || Session.I.role == 'practice_manager';

  /// Details, letterhead, map and weekly hours; preview edits freely.
  bool get _canEdit => !isLive || _isNew ? (!isLive || _manager) : (_can.isEmpty ? _manager : _can['details'] == true);

  /// Holidays & closures (the front desk keeps them too).
  bool get _canClosures => !isLive || _isNew ? (!isLive || _manager) : (_can.isEmpty ? _manager || Session.I.can('closures') : _can['closures'] == true);

  /// One honest line about what this person can't change (null: they can change everything).
  String? get _lockNote {
    if (_canEdit) return null;
    final n = _can['note'];
    if (n is String && n.isNotEmpty) return n;
    return _canClosures
        ? 'You can add and remove holidays and closures. Details and weekly hours are changed by the owner or practice manager.'
        : 'Only the owner or practice manager can change these details. Ask them if something needs updating.';
  }

  Future<void> _save() async {
    if (isLive) {
      if (_name.text.trim().isEmpty) {
        toast(context, 'Enter the location name');
        return;
      }
      final d = data;
      if (d == null) return;
      final body = {
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'googleMapsUrl': _mapUrl.text.trim(),
        if (_pinAt != null) ...{'lat': _pinAt!.lat, 'lng': _pinAt!.lng},
        'letterhead': {
          ...d.obj('letterhead'),
          'tagline': _tagline.text.trim(),
          'doctorNamePrinted': _printedName.text.trim(),
          'registrationNo': _regNo.text.trim(),
        },
        'weeklyHours': [
          for (var i = 0; i < 7; i++)
            {'weekday': d7Weekdays[i], 'isOpen': _open[i], 'opensAt': _mins[i].$1, 'closesAt': _mins[i].$2},
        ],
      };
      final ok = await runAction(context, busy: _busy, () async {
        if (_locationId != null) return Api.I.patch('/api/locations/$_locationId', body);
        final created = (await Api.I.post('/api/locations', body) as Map).cast<String, dynamic>();
        for (final c in _pendingClosures) {
          await Api.I.post('/api/locations/${created.str('id')}/closures', c);
        }
        return created;
      });
      if (ok == null || !mounted) return;
      // Visits already booked outside new hours stay; the desk was told to move them.
      final outside = ok is Map ? (ok['outsideHours'] as num?)?.toInt() ?? 0 : 0;
      toast(
        context,
        _locationId == null
            ? 'Location added'
            : outside == 0
                ? 'Location saved'
                : tr(context, outside == 1 ? 'Location saved · 1 booked visit is outside the new hours' : 'Location saved · #1 booked visits are outside the new hours')
                    .replaceFirst('#1', '$outside'),
      );
      Nav.back(context);
      return;
    }
    toast(context, 'Location saved');
    Nav.back(context);
  }

  Future<void> _editHours(int i) async {
    final r = await openSheet<String>(context, (_) => _HoursSheet(day: _days[i], range: _ranges[i]));
    if (r == null || !mounted) return;
    setState(() {
      _ranges[i] = r;
      _open[i] = true;
      final parts = r.split(' – ');
      final from = d7ParseTime(parts.first);
      final to = d7ParseTime(parts.last);
      if (from != null && to != null) _mins[i] = (from, to);
    });
  }

  /// Dates, all day or part of the day, and the reason. Patients already
  /// booked then are told by the server (and the desk moves their visits).
  Future<void> _addClosure() async {
    final r = await openSheet<Map<String, Object?>>(context, (_) => _ClosureSheet(locationId: isLive ? _locationId : null));
    if (r == null || !mounted) return;
    if (isLive && _locationId != null) {
      final ok = await runAction(context, () => Api.I.post('/api/locations/$_locationId/closures', r), busy: _busy);
      if (ok is! Map || !mounted) return;
      final told = (ok['patientsTold'] as num?)?.toInt() ?? 0;
      toast(context, told == 0 ? 'Closure added' : 'Closure added · ${told == 1 ? '1 patient told' : '$told patients told'}');
      reload(quiet: true);
      return;
    }
    if (isLive) _pendingClosures.add(r);
    setState(() {
      _closures.add((_closureLabel({'startDate': r['startDate'], 'endDate': r['endDate']}), _closureNote(r.cast<String, dynamic>())));
      _closureIds.add(null);
    });
  }

  Future<void> _removeClosure((String, String) c) async {
    final i = _closures.indexOf(c);
    final id = isLive && i >= 0 && i < _closureIds.length ? _closureIds[i] : null;
    if (id != null) {
      final ok = await runAction(context, () => Api.I.delete('/api/locations/$_locationId/closures/$id'), busy: _busy);
      if (ok == null || !mounted) return;
      final told = ok is Map ? (ok['patientsTold'] as num?)?.toInt() ?? 0 : 0;
      toast(context, told == 0 ? 'Closure removed' : tr(context, 'Closure removed · #1 booked patients told their visit stands').replaceFirst('#1', '$told'));
      reload(quiet: true);
      return;
    }
    setState(() {
      // Adding a new location: every closure is still pending, in order.
      if (isLive && i >= 0 && i < _closureIds.length) _closureIds.removeAt(i);
      if (isLive && i >= 0 && i < _pendingClosures.length) _pendingClosures.removeAt(i);
      _closures.remove(c);
    });
  }

  /// A doctor's row: their own hours open Profile-Schedule; anyone else's open
  /// here — editable when the server says so, read-only otherwise.
  Future<void> _openDoctor(int i) async {
    final d = isLive && i < _doctorMaps.length ? _doctorMaps[i] : null;
    if (d == null || d['isMe'] == true) {
      await Nav.go(context, 'Profile-Schedule', args: _locationId == null ? null : {'locationId': _locationId});
      if (mounted && isLive) reload(quiet: true);
      return;
    }
    final week = await openSheet<List<List<(int, int)>>>(
      context,
      (_) => _DoctorHoursSheet(doctor: d, place: _name.text.trim(), editable: d['canEdit'] == true),
    );
    if (week == null || !mounted || _locationId == null) return;
    final body = {
      'week': [
        for (var k = 0; k < 7; k++)
          {
            'weekday': d7Weekdays[k],
            'sessions': [for (final (a, b) in week[k]) {'startMin': a, 'endMin': b}],
          },
      ],
    };
    final ok = await runAction(context, () => Api.I.put('/api/locations/$_locationId/doctors/${d.str('doctorId')}/hours', body), busy: _busy);
    if (ok is! Map || !mounted) return;
    final outside = (ok['outsideHours'] as num?)?.toInt() ?? 0;
    toast(
      context,
      outside == 0
          ? 'Hours saved'
          : tr(context, outside == 1 ? 'Hours saved · 1 booked visit is outside them' : 'Hours saved · #1 booked visits are outside them').replaceFirst('#1', '$outside'),
    );
    reload(quiet: true);
  }

  bool get _inactive => data?.str('status') == 'inactive';

  /// Doctors with hours here (a printed name would go on all their prescriptions).
  int get _doctorsHere => data == null ? 2 : data!.list('doctors').length;

  final _previewing = ValueNotifier(false);

  /// The real prescription PDF with this location's saved letterhead (sample patient).
  Future<void> _preview() async {
    if (_previewing.value || _locationId == null) return;
    _previewing.value = true;
    try {
      final r = await Api.I.get('/api/doctor/letterhead/preview', query: {'locationId': _locationId});
      final f = ReportFile.fromApi(r);
      if (!mounted) return;
      if (f == null) return toast(context, 'No file to open');
      await openFileView(context, f, title: 'Letterhead preview');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      _previewing.value = false;
    }
  }

  Future<void> _deactivate() async {
    if (!isLive) {
      toast(context, 'Location deactivated · history kept');
      Nav.back(context);
      return;
    }
    if (_busy.value) return;
    _busy.value = true;
    try {
      if (_inactive) {
        await Api.I.post('/api/locations/$_locationId/activate', const {});
        if (!mounted) return;
        toast(context, 'Location activated');
        reload(quiet: true);
        return;
      }
      await Api.I.post('/api/locations/$_locationId/deactivate', _confirmDeactivate ? const {'confirm': true} : const {});
      if (!mounted) return;
      toast(context, 'Location deactivated · history kept');
      Nav.back(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Upcoming bookings, or team members who work only here (they'd be suspended).
      if (e.code == 'HAS_UPCOMING' || e.code == 'MEMBERS_ONLY_HERE') {
        setState(() => _confirmDeactivate = true);
        toast(context, '${e.message}. Tap again to deactivate.');
      } else {
        toast(context, e.message);
      }
    } finally {
      _busy.value = false;
    }
  }

  String get _deactivateNote {
    final d = data;
    if (d == null) return '3 patients have upcoming bookings here. Deactivating keeps their history.';
    if (_inactive) return 'No new bookings here. Every patient\'s history is kept.';
    final n = d.numOr('upcomingBookings').toInt();
    if (n == 0) return "No upcoming bookings here. Deactivating keeps every patient's history.";
    return '$n ${n == 1 ? 'patient has an upcoming booking' : 'patients have upcoming bookings'} here. Deactivating keeps their history.';
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: MpHeader(
        _isNew ? 'Add location' : 'Edit location',
        actions: [
          if (_canEdit) D7Btn('Save', height: 44, size: 16, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: _save),
        ],
      ),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          // Who changes what: anything this person can't change is read-only, said in one line.
          if (_lockNote != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Ico(I.lock, size: 18, color: MP.primary),
                  const Gap(10),
                  Expanded(child: Text(_lockNote!, style: tx(14, c: MP.ink2, h: 1.4))),
                ],
              ),
            ),
          IgnorePointer(
            ignoring: !_canEdit,
            child: VGap(gap: 16, children: [_details(), _letterhead(), _mapLink(), _weeklyHours()]),
          ),
          IgnorePointer(ignoring: !_canClosures, child: _closuresCard()),
          _perDoctor(),
          if (_canEdit) Padding(padding: const EdgeInsets.only(top: 8), child: MpButton(_isNew ? 'Add location' : 'Save changes', onTap: _save)),
          if (!_isNew && _canEdit) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: D7Ruled(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  D7Btn(
                    _inactive ? 'Activate location' : 'Deactivate location',
                    fg: _inactive ? MP.primary : MP.red,
                    size: 16,
                    padding: EdgeInsets.zero,
                    onTap: _deactivate,
                  ),
                  const SizedBox(height: 4),
                  Text(_deactivateNote, style: tx(14, c: MP.ink2, h: 1.45)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Details'),
          D7Labeled('Location name', child: D7Field(controller: _name)),
          D7Labeled(
            'Address',
            help: _addrNote,
            helpColor: _addrNoteBad ? MP.amber : MP.green,
            child: D7Field(
              controller: _address,
              lines: 2,
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onChanged: _canEdit ? (_) => _onAddressTyped() : null,
            ),
          ),
          if (_canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: UseHereLink(onPlace: _useHere),
            ),
          D7Labeled('Clinic phone', child: D7Field(controller: _phone, tab: true, keyboard: TextInputType.phone)),
        ],
      ),
    );
  }

  Widget _letterhead() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Letterhead', sub: 'Printed on prescriptions from this location', subHeight: null),
          D7Labeled(
            'Tagline',
            help: 'Printed under the doctor’s name only when they have no qualifications on file',
            child: D7Field(controller: _tagline),
          ),
          D7Labeled(
            'Doctor name as printed',
            help: _doctorsHere > 1
                ? 'Printed on every doctor’s prescriptions here. Leave empty to print each doctor’s own name.'
                : 'Leave empty to print the doctor’s profile name',
            helpColor: _doctorsHere > 1 && _printedName.text.trim().isNotEmpty ? MP.amber : null,
            child: D7Field(controller: _printedName, ellipsis: true, onChanged: (_) => setState(() {})),
          ),
          D7Labeled(
            'Registration number',
            help: 'Printed only for a doctor with no registration number in their profile',
            child: D7Field(controller: _regNo, tab: true),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Logo', style: tx(14, w: w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_logo['url'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 72,
                        height: 72,
                        color: _logo['isDark'] == true && _logo['cleaned'] != true ? MP.ink : MP.white,
                        child: CustomPaint(
                          painter: _logo['cleaned'] == true ? const _Checker() : null,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.network('${_logo['url']}', fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                          ),
                        ),
                      ),
                    )
                  else Semantics(
                    image: true,
                    label: 'Logo preview: City Care Clinic mark on a dark background',
                    excludeSemantics: true,
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: MP.ink, borderRadius: BorderRadius.circular(12)),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: MP.lineStrong, width: 2),
                        ),
                        child: Text('CC', style: tx(16, w: w800, em: 0.02, c: MP.lineStrong)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_logo['name'] as String? ?? 'citycare-logo.png', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w600)),
                        const SizedBox(height: 2),
                        Text(_logo['meta'] as String? ?? 'PNG · 48 KB', style: tx(13, c: MP.ink3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_canEdit)
                    D7Btn(
                      'Replace',
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onTap: _replaceLogo,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (isLive && _locationId != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _previewing,
                    builder: (_, busy, _) => D7Btn(busy ? 'Preparing…' : 'Preview prescription', padding: EdgeInsets.zero, onTap: busy ? null : _preview),
                  ),
                ),
                Text('Shows the saved letterhead. Save first to see changes.', style: tx(13, c: MP.ink3)),
                const SizedBox(height: 12),
              ],
              if (data == null || _logo['url'] != null) Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Ico(I.check, size: 16, color: MP.primary, stroke: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          data == null
                              ? "Dark background detected — we'll print a light version"
                              : _logo['cleaned'] == true
                                  ? 'Background removed · the logo prints on a transparent background'
                                  : 'Printed as uploaded. For the cleanest print, use a logo on a plain background.',
                          style: tx(14, c: MP.ink2, h: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Use current location": the address where the phone is, and the map pin there.
  void _useHere(Map<String, dynamic> place) {
    _addrTimer?.cancel();
    setState(() {
      final line = addressLine(place, typed: _address.text);
      if (line.isNotEmpty) _address.text = line;
      final lat = place['lat'], lng = place['lng'];
      if (lat is num && lng is num) {
        _pinAt = (lat: lat.toDouble(), lng: lng.toDouble());
        if (_isPinLink(_mapUrl.text)) _mapUrl.clear();
      }
      _addrNote = 'Address and map pin set to where you are';
      _addrNoteBad = false;
    });
  }

  /// Typed address → pin, a moment after typing stops.
  void _onAddressTyped() {
    _addrTimer?.cancel();
    final q = _address.text.trim();
    if (q.length < 6) {
      if (_addrNote != null) setState(() => _addrNote = null);
      return;
    }
    _addrTimer = Timer(const Duration(milliseconds: 900), () => _findAddress(q));
  }

  Future<void> _findAddress(String q) async {
    if (!isLive) return;
    try {
      final near = _pinAt ?? (_savedPin == null ? null : (lat: _savedPin!.$1, lng: _savedPin!.$2));
      final r = await Api.I.get('/api/geo/search', query: {'q': q, if (near != null) 'lat': '${near.lat}', if (near != null) 'lng': '${near.lng}'}) as Map;
      if (!mounted || _address.text.trim() != q) return;
      final items = [for (final x in (r['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      final hit = items.where((x) => x['lat'] is num && x['lng'] is num).firstOrNull;
      setState(() {
        if (hit == null) {
          _addrNote = 'Couldn’t find this address on the map. Move the map to place the pin.';
          _addrNoteBad = true;
          return;
        }
        _pinAt = (lat: (hit['lat'] as num).toDouble(), lng: (hit['lng'] as num).toDouble());
        if (_isPinLink(_mapUrl.text)) _mapUrl.clear();
        final where = [hit['area'], hit['city']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
        _addrNote = where.isEmpty ? 'Pin moved to this address' : 'Pin moved to $where';
        _addrNoteBad = false;
      });
    } catch (_) {
      // Offline or the map search is busy: the pin stays where it is.
    }
  }

  /// The map's address for the pin, keeping the house / building number the
  /// doctor typed ("DD-24, …"), which the map doesn't know.
  String _addressFromPlace(Map<String, dynamic> place) {
    final label = '${place['label'] ?? ''}'.trim();
    if (label.isEmpty) return _address.text;
    final first = _address.text.split(',').first.trim();
    final house = RegExp(r'\d').hasMatch(first) && first.length <= 24 && !label.toLowerCase().contains(first.toLowerCase());
    return house ? '$first, $label' : label;
  }

  Widget _mapLink() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Map and link'),
          ClinicMap(
            lat: _pinAt?.lat ?? _savedPin?.$1,
            lng: _pinAt?.lng ?? _savedPin?.$2,
            label: _name.text,
            editable: _canEdit,
            onChanged: (p) => setState(() {
              _pinAt = (lat: p.lat, lng: p.lng);
              // A link made from the old pin follows the new one (the server makes it on save).
              if (_isPinLink(_mapUrl.text)) _mapUrl.clear();
            }),
            autoFillAddress: _address.text.trim().isEmpty,
            addressFollowsPin: true,
            onUseAddress: (place) => setState(() {
              _address.text = _addressFromPlace(place);
              _addrNote = 'Address updated from the map pin';
              _addrNoteBad = false;
            }),
          ),
          D7Labeled(
            'Google Maps link',
            help: _mapUrl.text.trim().isEmpty
                ? (_pinAt != null || _savedPin != null
                    ? "Made from the pin when you save. Or paste your clinic's link from Google Maps (Share → Copy link)."
                    : "Set the pin above, or paste your clinic's link from Google Maps (Share → Copy link).")
                : _isPinLink(_mapUrl.text)
                    ? 'Made from the pin. Patients get it with every booking confirmation.'
                    : 'Your Google Maps link. Patients get it with every booking confirmation; the pin follows it when you save.',
            child: D7Field(
              controller: _mapUrl,
              onChanged: (_) => setState(() {}),
              keyboard: TextInputType.url,
              ellipsis: true,
              padding: const EdgeInsets.only(left: 46, right: 16),
              overlays: const [
                Positioned(left: 17, top: 18, child: IgnorePointer(child: Ico(I.pin, size: 20, color: MP.ink3))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyHours() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: D7Title('Weekly hours', sub: 'When patients can book at this location', subHeight: null),
          ),
          for (var i = 0; i < _days.length; i++) _hoursRow(i),
        ],
      ),
    );
  }

  Widget _hoursRow(int i) {
    final open = _open[i];
    return D7Ruled(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(width: 44, child: Text(_days[i], style: tx(15, w: w600))),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: open ? 'Edit ${_days[i]} hours, ${_ranges[i]}' : '${_days[i]}, closed',
                child: Tap(
                  onTap: _canEdit ? () => _editHours(i) : null,
                  radius: 8,
                  child: SizedBox(
                    height: 48,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        open ? _ranges[i] : 'Closed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(15, c: open ? MP.ink : MP.ink3, tab: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: 'Open on ${_days[i]}',
              enabled: _canEdit,
              child: Opacity(
                opacity: _canEdit ? 1 : 0.45,
                child: MpSwitch(value: open, onChanged: _canEdit ? (v) => setState(() => _open[i] = v) : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closuresCard() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: D7Title('Holidays & closures')),
          if (_closures.isEmpty)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No holidays or closures coming up', style: tx(14, c: MP.ink2)),
            ),
          for (final c in _closures)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.$1, style: tx(16, w: w600, tab: true)),
                        const SizedBox(height: 2),
                        Text(c.$2, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                  if (_canClosures) const SizedBox(width: 12),
                  // 44×44 with CSS margin-right -10px: takes 34px in the row.
                  if (_canClosures) SizedBox(
                    width: 34,
                    height: 44,
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 44,
                      maxWidth: 44,
                      child: MpIconButton(
                        I.close,
                        label: 'Remove closure on ${c.$1}',
                        color: MP.ink2,
                        iconSize: 20,
                        onTap: () => _removeClosure(c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_canClosures)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: D7Btn('Add closure', icon: I.plus, iconSize: 20, padding: EdgeInsets.zero, onTap: _addClosure),
              ),
            ),
        ],
      ),
    );
  }

  Widget _perDoctor() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: D7Title('Per-doctor hours', sub: "Within the clinic's weekly hours", subHeight: null),
          ),
          if (_doctorRows.isEmpty)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No doctors practise here yet', style: tx(14, c: MP.ink2)),
            ),
          for (final (i, d) in _doctorRows.indexed)
            Tap(
              onTap: () => _openDoctor(i),
              radius: 12,
              child: D7Ruled(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    MpAvatar(d.$1, size: 40, fontSize: 14, photo: i < _doctorMaps.length ? _doctorMaps[i]['photo'] as String? : null),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                          const SizedBox(height: 2),
                          Text(
                            d.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx(14, c: MP.ink2, tab: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Ico(I.chevronRight, size: 18, color: MP.ink3),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opening hours for one weekday (opened from its hours row).
class _HoursSheet extends StatefulWidget {
  const _HoursSheet({required this.day, required this.range, this.subtitle = 'When patients can book at this location', this.removable = false});
  final String day;
  final String range;
  final String subtitle;

  /// Shows "Remove these hours" (resolves with '').
  final bool removable;

  @override
  State<_HoursSheet> createState() => _HoursSheetState();
}

class _HoursSheetState extends State<_HoursSheet> {
  /// Half-hour steps, 6:00 AM – 11:00 PM.
  static final _options = _halfHours;

  late String _from = _pick(widget.range.split(' – ').first, '9:00 AM');
  late String _to = _pick(widget.range.split(' – ').last, '8:00 PM');

  static String _label(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  static String _pick(String v, String fallback) => _options.contains(v.trim()) ? v.trim() : fallback;

  void _done() {
    if (_options.indexOf(_to) <= _options.indexOf(_from)) {
      toast(context, 'Closing time must be after opening time');
      return;
    }
    Navigator.pop(context, '$_from – $_to');
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: '${widget.day} hours',
      subtitle: widget.subtitle,
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MpSelect(
                  label: 'Opens',
                  value: _from,
                  options: _options,
                  onChanged: (v) => setState(() => _from = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MpSelect(
                  label: 'Closes',
                  value: _to,
                  options: _options,
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          MpButton('Save hours', onTap: _done),
          if (widget.removable) ...[
            const SizedBox(height: 12),
            MpButton('Remove these hours', kind: MpBtn.dangerSoft, height: 48, onTap: () => Navigator.pop(context, '')),
          ],
        ],
      ),
    );
  }
}

/// Light checkerboard behind a transparent logo (shows it has no background).
class _Checker extends CustomPainter {
  const _Checker();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFEFF2F7);
    const c = 8.0;
    for (var y = 0.0; y < size.height; y += c) {
      for (var x = 0.0; x < size.width; x += c) {
        if (((x / c).floor() + (y / c).floor()).isEven) canvas.drawRect(Rect.fromLTWH(x, y, c, c), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Checker old) => false;
}

/// Half-hour times, 6:00 AM – 11:00 PM ("9:00 AM").
final _halfHours = [for (var m = 6 * 60; m <= 23 * 60; m += 30) _HoursSheetState._label(m)];

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "Add closure": first and last day, all day or part of the day, and the
/// reason. Live, shows how many booked patients will be told (GET
/// /api/locations/:id/closures/preview). Resolves with the POST body.
class _ClosureSheet extends StatefulWidget {
  /// The saved location (live); null for a new location or the design preview.
  final String? locationId;
  const _ClosureSheet({this.locationId});

  @override
  State<_ClosureSheet> createState() => _ClosureSheetState();
}

class _ClosureSheetState extends State<_ClosureSheet> {
  final _reason = TextEditingController();
  late DateTime _from = _today;
  late DateTime _to = _today;
  bool _allDay = true;
  String _closedFrom = '2:00 PM';
  String _openAgain = '6:00 PM';

  /// Booked patients the closure touches (null: not known yet).
  int? _booked;
  Timer? _timer;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _count();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reason.dispose();
    super.dispose();
  }

  Map<String, Object?> get _body => {
        'startDate': _ymd(_from),
        'endDate': _ymd(_to),
        'allDay': _allDay,
        if (!_allDay) 'fromMin': d7ParseTime(_closedFrom),
        if (!_allDay) 'toMin': d7ParseTime(_openAgain),
      };

  /// Asks the server, a moment after the choice settles, who is booked then.
  void _count() {
    final id = widget.locationId;
    if (id == null) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () async {
      if (!_allDay && _halfHours.indexOf(_openAgain) <= _halfHours.indexOf(_closedFrom)) {
        if (mounted) setState(() => _booked = null);
        return;
      }
      try {
        final r = await Api.I.get('/api/locations/$id/closures/preview', query: _body);
        if (mounted) setState(() => _booked = ((r as Map)['booked'] as num?)?.toInt());
      } catch (_) {
        if (mounted) setState(() => _booked = null);
      }
    });
  }

  void _changed(VoidCallback f) {
    setState(f);
    _count();
  }

  Future<void> _pick(bool first) async {
    final d = await showDatePicker(
      context: context,
      initialDate: first ? _from : (_to.isBefore(_from) ? _from : _to),
      firstDate: first ? _today : _from,
      lastDate: DateTime(_today.year + 2, 12, 31),
      helpText: first ? 'Closed from' : 'Closed until',
    );
    if (d == null || !mounted) return;
    _changed(() {
      if (first) {
        _from = d;
        if (_to.isBefore(d)) _to = d;
      } else {
        _to = d;
      }
    });
  }

  void _done() {
    if (!_allDay && _halfHours.indexOf(_openAgain) <= _halfHours.indexOf(_closedFrom)) {
      return toast(context, 'Choose an end time after the start time');
    }
    final reason = _reason.text.trim();
    Navigator.pop(context, <String, Object?>{..._body, 'reason': reason.isEmpty ? (_allDay ? 'Closed all day' : 'Closed part of the day') : reason});
  }

  String? get _bookedLine {
    final n = _booked;
    if (n == null) return null;
    if (n == 0) return 'No patients are booked then';
    return n == 1 ? '1 booked patient will be told to choose another time' : '$n booked patients will be told to choose another time';
  }

  @override
  Widget build(BuildContext context) {
    final days = _to.difference(_from).inDays + 1;
    return MpSheet(
      title: 'Add closure',
      subtitle: 'No bookings at this location then, for every doctor',
      showClose: true,
      child: VGap(
        gap: 16,
        children: [
          MpInput(label: 'Reason', hint: 'e.g. Durga Puja, staff training', controller: _reason, autofocus: true),
          D11Group('Dates', [
            D11Row('From', value: F.dayMonth(_from), onTap: () => _pick(true)),
            D11Row('Until', value: F.dayMonth(_to), sub: days == 1 ? '1 day' : '$days days', onTap: () => _pick(false)),
          ]),
          MpSegmented(
            options: const ['All day', 'Part of the day'],
            index: _allDay ? 0 : 1,
            onChanged: (i) => _changed(() => _allDay = i == 0),
          ),
          if (!_allDay)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: MpSelect(label: 'Closed from', value: _closedFrom, options: _halfHours, onChanged: (v) => _changed(() => _closedFrom = v))),
                const SizedBox(width: 12),
                Expanded(child: MpSelect(label: 'Open again at', value: _openAgain, options: _halfHours, onChanged: (v) => _changed(() => _openAgain = v))),
              ],
            ),
          if (_bookedLine != null)
            Semantics(
              liveRegion: true,
              child: Text(_bookedLine!, style: tx(14, c: (_booked ?? 0) > 0 ? MP.amber : MP.ink2, h: 1.45)),
            ),
          MpButton('Add closure', onTap: _done),
        ],
      ),
    );
  }
}

/// A doctor's hours at this location, day by day (a day can have more than
/// one session). Editable for the doctor's assistant, the practice manager
/// and the owner; read-only for others, saying who changes them. Resolves
/// with the new week (Mon … Sun sessions) to save, or null.
class _DoctorHoursSheet extends StatefulWidget {
  final Map<String, dynamic> doctor;
  final String place;
  final bool editable;
  const _DoctorHoursSheet({required this.doctor, required this.place, required this.editable});

  @override
  State<_DoctorHoursSheet> createState() => _DoctorHoursSheetState();
}

class _DoctorHoursSheetState extends State<_DoctorHoursSheet> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late final List<List<(int, int)>> _week = [
    for (final wd in d7Weekdays)
      [
        for (final x in (widget.doctor.list('week').where((w) => w['weekday'] == wd).firstOrNull?.list('sessions') ?? const <Map<String, dynamic>>[]))
          (x.numOr('startMin').toInt(), x.numOr('endMin').toInt()),
      ]..sort((a, b) => a.$1.compareTo(b.$1)),
  ];
  bool _dirty = false;

  static String _range((int, int) s) => '${d7Minutes(s.$1)} – ${d7Minutes(s.$2)}';

  /// Edits (or with [at] null, adds) one session on day [d].
  Future<void> _edit(int d, [int? at]) async {
    final current = at == null ? (_week[d].isEmpty ? '9:00 AM – 1:00 PM' : '5:00 PM – 8:00 PM') : _range(_week[d][at]);
    final r = await openSheet<String>(
      context,
      (_) => _HoursSheet(day: _days[d], range: current, subtitle: widget.doctor.str('name'), removable: at != null),
    );
    if (r == null || !mounted) return;
    final next = [..._week[d]];
    if (at != null) next.removeAt(at);
    if (r.isNotEmpty) {
      final parts = r.split(' – ');
      final a = d7ParseTime(parts.first), b = d7ParseTime(parts.last);
      if (a == null || b == null) return;
      if (next.any((s) => a < s.$2 && b > s.$1)) return toast(context, 'These hours overlap another session that day');
      next.add((a, b));
      next.sort((x, y) => x.$1.compareTo(y.$1));
    }
    setState(() {
      _week[d] = next;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.doctor.str('name', 'The doctor');
    return MpSheet(
      title: name,
      subtitle: widget.place.isEmpty
          ? "Hours here, within the clinic's weekly hours"
          : tr(context, "Hours at #1, within the clinic's weekly hours").replaceFirst('#1', widget.place),
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var d = 0; d < 7; d++)
            D7Ruled(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    SizedBox(width: 44, child: Text(_days[d], style: tx(15, w: w600))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _week[d].isEmpty
                          ? Text('Off', style: tx(15, c: MP.ink3))
                          : Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (var k = 0; k < _week[d].length; k++)
                                  Semantics(
                                    button: widget.editable,
                                    label: widget.editable ? 'Edit ${_days[d]} ${_range(_week[d][k])}' : '${_days[d]} ${_range(_week[d][k])}',
                                    excludeSemantics: true,
                                    child: Tap(
                                      onTap: widget.editable ? () => _edit(d, k) : null,
                                      radius: 8,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Text(_range(_week[d][k]), style: tx(15, c: MP.ink, tab: true)),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (widget.editable && _week[d].length < 3)
                      MpIconButton(I.plus, label: 'Add hours on ${_days[d]}', color: MP.primary, iconSize: 20, onTap: () => _edit(d)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (widget.editable)
            MpButton(
              'Save hours',
              onTap: _dirty ? () => Navigator.pop(context, _week) : () => Navigator.pop(context),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.lock, size: 16, color: MP.ink3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(context, 'Only #1, the owner or the practice manager can change these hours.').replaceFirst('#1', name),
                    style: tx(14, c: MP.ink2, h: 1.45),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

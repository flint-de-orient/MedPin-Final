import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Clinic-Editor.dc.html — "Location editor" (Edit location).
/// Live: args {'locationId'} → GET /api/locations/:id, saved with PATCH;
/// without it a new location is added (POST /api/locations). Closures:
/// POST / DELETE /api/locations/:id/closures; deactivate / activate:
/// POST /api/locations/:id/deactivate (409 HAS_UPCOMING → tap again to confirm).
class ClinicEditorScreen extends StatefulWidget {
  const ClinicEditorScreen({super.key});

  @override
  State<ClinicEditorScreen> createState() => _ClinicEditorScreenState();
}

class _ClinicEditorScreenState extends State<ClinicEditorScreen> with LiveData {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _name = TextEditingController(text: 'City Care Clinic — Salt Lake');
  final _address = TextEditingController(text: 'DD-24, Sector 1, Salt Lake, Kolkata 700064');
  final _phone = TextEditingController(text: '033 4012 5678');
  final _tagline = TextEditingController(text: 'Diabetes, thyroid and heart care');
  final _printedName = TextEditingController(text: 'Dr. Arjun Sen, MBBS, MD (Medicine)');
  final _regNo = TextEditingController(text: 'WBMC 64213');
  final _mapUrl = TextEditingController(text: 'https://maps.app.goo.gl/Qx7bR2mLk9');

  /// Live: the location being edited (null = adding a new one).
  String? _locationId;

  /// Closure ids, parallel to [_closures] (live); dates picked for a new
  /// location are posted after it is created.
  final _closureIds = <String?>[];
  final _pendingClosures = <DateTime>[];

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
      ..addAll([for (final c in l.list('closures')) (_closureLabel(c), c.str('reason', 'Closed all day'))]);
    _closureIds
      ..clear()
      ..addAll([for (final c in l.list('closures')) c.str('id')]);
    _doctorsLive = [
      for (final d in l.list('doctors'))
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

  List<(String, String, String)> get _doctorRows => _doctorsLive ?? _doctors;

  bool get _isNew => isLive && _locationId == null;

  /// Letterhead logo: url / name / "PNG · 48 KB" (live), or the design's sample.
  Map<String, Object?> get _logo {
    if (data == null) return const {};
    final l = data!.obj('letterhead').obj('logo');
    if (l.isEmpty) return {'name': 'No logo yet', 'meta': 'PNG or JPG, on a plain background'};
    final kb = (l.numOr('sizeBytes') / 1024).round();
    final type = l.str('mimeType').split('/').last.toUpperCase();
    return {'url': l['url'], 'name': l.str('name', 'Logo'), 'meta': '$type · $kb KB', 'isDark': data!.obj('letterhead')['logoIsDark'] == true};
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
    toast(context, 'Logo updated');
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
        for (final day in _pendingClosures) {
          await Api.I.post('/api/locations/${created.str('id')}/closures', {
            'startDate': d7Key(day),
            'endDate': d7Key(day),
            'reason': 'Closed all day',
          });
        }
        return created;
      });
      if (ok == null || !mounted) return;
      toast(context, _locationId == null ? 'Location added' : 'Location saved');
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

  Future<void> _addClosure() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: isLive ? today : DateTime(2026, 10, 1),
      firstDate: isLive ? today : DateTime(2026, 9, 29),
      lastDate: isLive ? DateTime(today.year + 2, 12, 31) : DateTime(2027, 12, 31),
      helpText: 'Closed on',
    );
    if (d == null || !mounted) return;
    if (isLive && _locationId != null) {
      final ok = await runAction(
        context,
        () => Api.I.post('/api/locations/$_locationId/closures', {
          'startDate': d7Key(d),
          'endDate': d7Key(d),
          'reason': 'Closed all day',
        }),
        busy: _busy,
      );
      if (ok == null || !mounted) return;
      toast(context, 'Closure added');
      reload(quiet: true);
      return;
    }
    if (isLive) _pendingClosures.add(d);
    setState(() {
      _closures.add((d7Date(d), 'Closed all day'));
      _closureIds.add(null);
    });
  }

  Future<void> _removeClosure((String, String) c) async {
    final i = _closures.indexOf(c);
    final id = isLive && i >= 0 && i < _closureIds.length ? _closureIds[i] : null;
    if (id != null) {
      final ok = await runAction(context, () => Api.I.delete('/api/locations/$_locationId/closures/$id'), busy: _busy);
      if (ok == null || !mounted) return;
      toast(context, 'Closure removed');
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

  bool get _inactive => data?.str('status') == 'inactive';

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
      if (e.code == 'HAS_UPCOMING') {
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
          D7Btn('Save', height: 44, size: 16, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: _save),
        ],
      ),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          _details(),
          _letterhead(),
          _mapLink(),
          _weeklyHours(),
          _closuresCard(),
          _perDoctor(),
          Padding(padding: const EdgeInsets.only(top: 8), child: MpButton(_isNew ? 'Add location' : 'Save changes', onTap: _save)),
          if (!_isNew) Padding(
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
            child: D7Field(
              controller: _address,
              lines: 2,
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
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
          D7Labeled('Tagline', child: D7Field(controller: _tagline)),
          D7Labeled(
            'Doctor name as printed',
            child: D7Field(controller: _printedName, ellipsis: true),
          ),
          D7Labeled('Registration number', child: D7Field(controller: _regNo, tab: true)),
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
                        color: _logo['isDark'] == true ? MP.ink : MP.bg,
                        padding: const EdgeInsets.all(6),
                        child: Image.network('${_logo['url']}', fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
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
                  D7Btn(
                    'Replace',
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onTap: _replaceLogo,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
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
                          "Dark background detected — we'll print a light version",
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

  Widget _mapLink() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Map link'),
          D7Labeled(
            'Google Maps link',
            help: 'Patients get this with every booking confirmation.',
            child: D7Field(
              controller: _mapUrl,
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
                  onTap: () => _editHours(i),
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
              child: MpSwitch(value: open, onChanged: (v) => setState(() => _open[i] = v)),
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
                  const SizedBox(width: 12),
                  // 44×44 with CSS margin-right -10px: takes 34px in the row.
                  SizedBox(
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
          for (final d in _doctorRows)
            Tap(
              onTap: () => Nav.go(context, 'Profile-Schedule', args: _locationId == null ? null : {'locationId': _locationId}),
              radius: 12,
              child: D7Ruled(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    MpAvatar(d.$1, size: 40, fontSize: 14),
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
  const _HoursSheet({required this.day, required this.range});
  final String day;
  final String range;

  @override
  State<_HoursSheet> createState() => _HoursSheetState();
}

class _HoursSheetState extends State<_HoursSheet> {
  /// Half-hour steps, 6:00 AM – 11:00 PM.
  static final _options = [for (var m = 6 * 60; m <= 23 * 60; m += 30) _label(m)];

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
      subtitle: 'When patients can book at this location',
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
        ],
      ),
    );
  }
}

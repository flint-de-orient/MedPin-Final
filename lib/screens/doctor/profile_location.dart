import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../data/where.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import '../../widgets/i18n.dart';

/// Design: Profile-Location.dc.html — "Profile · location: map, address, fees".
class ProfileLocationScreen extends StatefulWidget {
  const ProfileLocationScreen({super.key});

  @override
  State<ProfileLocationScreen> createState() => _ProfileLocationScreenState();
}

/// The design's street map (viewBox 320×160, drawn with "slice" = cover).
const _mapSvg =
    '<svg viewBox="0 0 320 160">'
    '<rect width="320" height="160" fill="#EEF2F7"></rect>'
    '<path d="M0 52h320M0 112h320M72 0v160M196 0v160M268 0v160" stroke="#FFFFFF" stroke-width="10"></path>'
    '<path d="M0 18 320 142" stroke="#FFFFFF" stroke-width="6"></path>'
    '<rect x="88" y="66" width="92" height="34" rx="4" fill="#E2E8F0"></rect>'
    '<rect x="212" y="6" width="44" height="34" rx="4" fill="#DCEBDF"></rect>'
    '<rect x="8" y="124" width="54" height="30" rx="4" fill="#E2E8F0"></rect>'
    '</svg>';

class _ProfileLocationScreenState extends State<ProfileLocationScreen> with LiveData {
  static const _types = ['Clinic', 'Hospital', 'Nursing home', 'Diagnostic centre', 'Video consultation'];

  /// API values of [_types] (plus "chamber", which the design doesn't list).
  static const _typeKeys = {
    'Clinic': 'clinic',
    'Hospital': 'hospital',
    'Nursing home': 'nursing_home',
    'Diagnostic centre': 'diagnostic_centre',
    'Video consultation': 'video',
    'Chamber': 'chamber',
  };
  static const _paymentKeys = {'UPI': 'upi', 'Cash': 'cash', 'Card': 'card', 'Net banking': 'net_banking', 'Online': 'online'};

  /// Degrees per map pixel when the pin is dragged (≈2 m).
  static const _degPerPx = 0.00002;

  String? _pickedType;
  bool? _pickedCollect;
  bool _movingPin = false;

  /// Pin offset from the map centre (dragged while "Move pin" is on).
  Offset _pin = Offset.zero;

  /// Set with "Here" on the map (the phone's location); wins over a dragged pin.
  ({double lat, double lng})? _here;

  final List<(String, String, String)> _sampleFees = [
    ('New consultation', '15 min · in clinic', '₹600'),
    ('Follow-up', 'Repeat visit for the same problem', '₹600'),
    ('Report review', 'Within 7 days of a visit', 'Free'),
    ('Video consultation', '15 min', '₹600'),
  ];

  /// Edited location fields (PATCH /api/locations/:id) and services (PUT
  /// /api/doctor/locations/:locationId), saved together from the header.
  final Map<String, Object?> _changes = {};
  List<Map<String, dynamic>>? _services;

  /// The doctor's locations; this one from args `locationId` or the first.
  @override
  Future<Object?> fetch() async {
    final args = Nav.args<Map>(context) ?? const {};
    final dls = [for (final x in (await Api.I.get('/api/doctor/locations') as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    String idOf(Map<String, dynamic> dl) => dl['locationId'] is Map ? dl.obj('locationId').str('id') : dl.str('locationId');
    final active = [for (final d in dls) if (d['status'] != 'ended') d];
    final id = args['locationId'] as String? ?? (active.isEmpty ? null : idOf(active.first));
    if (id == null) return {'none': true};
    final loc = await Api.I.get('/api/locations/$id');
    final dl = dls.firstWhere((d) => idOf(d) == id, orElse: () => const <String, dynamic>{});
    return {'id': id, 'loc': loc, 'dl': dl};
  }

  Map<String, dynamic> get _loc => data!.obj('loc');
  Map<String, dynamic> get _dl => data!.obj('dl');
  String get _id => data!.str('id');

  String get _name => data == null ? 'City Care · Salt Lake' : d4LocationName(_loc);

  String get _type {
    if (_pickedType != null) return _pickedType!;
    if (data == null) return 'Clinic';
    final key = _loc.str('type', 'clinic');
    return _typeKeys.entries.firstWhere((e) => e.value == key, orElse: () => _typeKeys.entries.first).key;
  }

  List<String> get _typeOptions => [..._types, if (!_types.contains(_type)) _type];

  bool get _collectAtBooking => _pickedCollect ?? (data != null && _loc['collectFeeAtBooking'] == true);

  String _field(String sample, String key, [String? fallbackKey]) =>
      data == null ? sample : _loc.str(key, fallbackKey == null ? '' : _loc.str(fallbackKey));

  static String _feeText(num fee) => fee <= 0 ? 'Free' : '₹${F.count(fee)}';

  List<Map<String, dynamic>> get _liveServices => _services ?? _dl.list('services');

  List<(String, String, String)> get _fees => data == null
      ? _sampleFees
      : [for (final s in _liveServices) (s.str('name'), s.str('details'), _feeText(s.numOr('fee')))];

  void _setFee(int i, String text) {
    final t = text.replaceAll(RegExp(r'[₹,\s]'), '');
    final fee = t.isEmpty || t.toLowerCase() == 'free' ? 0 : num.tryParse(t);
    if (fee == null || data == null) return;
    _services ??= [for (final s in _dl.list('services')) {...s}];
    _services![i]['fee'] = fee;
  }

  List<String> get _payments {
    if (data == null) return const ['UPI', 'Cash', 'Card'];
    return [
      for (final p in (_loc['paymentMethods'] as List? ?? const []))
        _paymentKeys.entries.firstWhere((e) => e.value == '$p', orElse: () => MapEntry('$p', '$p')).key,
    ];
  }

  List<String> get _facilities => data == null
      ? const ['Wheelchair access', 'Parking', 'Lab sample collection', 'Pharmacy']
      : [for (final f in (_loc['facilities'] as List? ?? const [])) '$f'];

  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  static String _clock(int m) => F.time(DateTime(2000, 1, 1, m ~/ 60, m % 60));

  /// "Mon – Sat · 9:00 AM – 1:00 PM" / "15-min slots · up to 16 patients"
  (String, String?) get _scheduleSummary {
    if (data == null) return ('Mon – Sat · 9:00 AM – 1:00 PM', '15-min slots · up to 16 patients');
    final s = _dl.obj('schedule');
    final open = <int>[];
    final ranges = <(int, int), int>{};
    for (final day in s.list('week')) {
      final i = _weekdays.indexOf(day.str('weekday'));
      final sessions = day.list('sessions');
      if (i < 0 || sessions.isEmpty) continue;
      open.add(i);
      final r = (sessions.first.numOr('startMin').toInt(), sessions.first.numOr('endMin').toInt());
      ranges[r] = (ranges[r] ?? 0) + 1;
    }
    if (open.isEmpty) return ('No weekly hours yet', 'Add hours so patients can book');
    open.sort();
    final days = open.length >= 3 && open.last - open.first == open.length - 1
        ? '${_dayShort[open.first]} – ${_dayShort[open.last]}'
        : open.map((d) => _dayShort[d]).join(', ');
    final common = (ranges.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final slot = s.numOr('slotLengthMin', 15).toInt();
    final step = slot + s.numOr('breakBetweenMin').toInt();
    final n = (common.$2 - common.$1) ~/ (step <= 0 ? 15 : step) * s.numOr('patientsPerSlot', 1).toInt();
    return ('$days · ${_clock(common.$1)} – ${_clock(common.$2)}', '$slot-min slots · up to ${d4Plural(n, 'patient')}');
  }

  Future<bool> _linkHfr(String id) async {
    if (!isLive) return true;
    final ok = await runAction(context, () => Api.I.patch('/api/locations/$_id', {'hfrId': id}));
    return ok != null;
  }

  Future<void> _save() async {
    if (!isLive) {
      d4Save(context);
      return;
    }
    final body = {..._changes};
    if (body['paymentMethods'] is List) {
      final labels = body['paymentMethods'] as List;
      final keys = [for (final l in labels) _paymentKeys[l] ?? _paymentKeys.values.where((v) => v == '$l'.toLowerCase().replaceAll(' ', '_')).firstOrNull];
      if (keys.contains(null)) {
        toast(context, 'Payment methods can be UPI, cash, card, net banking or online');
        return;
      }
      body['paymentMethods'] = keys;
    }
    if (_here != null) {
      body['lat'] = _here!.lat;
      body['lng'] = _here!.lng;
    } else if (_pin != Offset.zero) {
      final c = _loc.obj('geo')['coordinates'] as List?;
      if (c != null && c.length == 2) {
        body['lat'] = (c[1] as num) - _pin.dy * _degPerPx;
        body['lng'] = (c[0] as num) + _pin.dx * _degPerPx;
      }
    }
    // Address, hours and payment details are the clinic owner's; a doctor here saves their own services.
    if (body.isNotEmpty && !Session.I.isOwner) {
      toast(context, 'Only the clinic owner can change the address and clinic details');
      if (_services == null) return;
    } else if (body.isNotEmpty) {
      final ok = await runAction(context, () => Api.I.patch('/api/locations/$_id', body));
      if (ok == null || !mounted) return;
    }
    if (_services != null) {
      final ok = await runAction(context, () => Api.I.put('/api/doctor/locations/$_id', {'services': _services}));
      if (ok == null || !mounted) return;
    }
    if (mounted) d4Save(context);
  }

  void _toggleMovePin() {
    setState(() => _movingPin = !_movingPin);
    if (_movingPin) toast(context, 'Drag on the map to move the pin');
  }

  /// Keeps the pin's tip inside a [w]×[h] map (offset from its centre).
  static Offset _clampPin(Offset p, double w, double h) =>
      Offset(p.dx.clamp(16 - w / 2, w / 2 - 16).toDouble(), p.dy.clamp(32 - h / 2, h / 2).toDouble());

  Future<void> _addService() async {
    final r = await d4FormSheet(
      context,
      title: 'Add service',
      fields: const [
        D4FormField('Service', hint: 'e.g. Diet consultation'),
        D4FormField('Details', hint: 'e.g. 20 min · in clinic'),
        D4FormField('Fee', hint: 'e.g. 500', keyboard: TextInputType.number),
      ],
      confirm: 'Add service',
    );
    if (!mounted || r == null || r.length < 3 || r[0].isEmpty) return;
    if (!isLive) {
      final fee = r[2].isEmpty ? 'Free' : (int.tryParse(r[2]) != null ? '₹${r[2]}' : r[2]);
      setState(() => _sampleFees.add((r[0], r[1], fee)));
      return;
    }
    final fee = r[2].isEmpty ? 0 : num.tryParse(r[2].replaceAll(RegExp(r'[₹,\s]'), ''));
    if (fee == null) {
      toast(context, 'Enter the fee in rupees, like 500');
      return;
    }
    final details = r[1].toLowerCase();
    final services = [
      for (final s in _liveServices) {...s},
      {'name': r[0], if (r[1].isNotEmpty) 'details': r[1], 'fee': fee, 'mode': details.contains('video') ? 'video' : 'in_clinic'},
    ];
    final ok = await runAction(context, () => Api.I.put('/api/doctor/locations/$_id', {'services': services}));
    if (ok == null || !mounted) return;
    toast(context, '${r[0]} added');
    _services = null;
    reload(quiet: true);
  }

  Future<void> _stopPractising() async {
    final ok = await d4Confirm(
      context,
      title: 'Stop practising here?',
      body: 'New bookings at $_name stop. Every patient’s history is kept.',
      confirm: 'Stop practising here',
    );
    if (!ok || !mounted) return;
    if (isLive) {
      final r = await runAction(context, () => Api.I.post('/api/doctor/locations/$_id/stop'));
      if (r == null || !mounted) return;
    }
    d4Save(context, 'You no longer practise at $_name');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (placeholder != null) return MpPage(header: const D4Header('Location'), body: placeholder);
    if (data?['none'] == true) {
      return MpPage(
        header: const D4Header('Location'),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Text('You don’t practise at any location yet.', style: tx(14, c: MP.ink2)),
        ),
      );
    }
    final schedule = _scheduleSummary;
    return MpPage(
      header: D4Header(_name, subtitle: 'Location', onSave: _save),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        gap: 16,
        children: [
          D4Card(
            children: [
              const D4CardTitle('Address'),
              _map(),
              VGap(
                gap: 12,
                children: [
                  D4Field(
                    'Location name',
                    _field('City Care Clinic · Salt Lake', 'name').replaceAll(' — ', ' · '),
                    onChanged: (v) => _changes['name'] = v.trim(),
                  ),
                  D4SelectField(
                    'Type',
                    _type,
                    options: _typeOptions,
                    onChanged: (v) => setState(() {
                      _pickedType = v;
                      _changes['type'] = _typeKeys[v];
                    }),
                  ),
                  D4Field(
                    'Address',
                    _field('DD-24, Sector 1, Salt Lake, Kolkata 700064', 'address'),
                    onChanged: (v) => _changes['address'] = v.trim(),
                  ),
                  D4Field(
                    'Landmark',
                    _field('Opposite Tank 9, near City Centre', 'landmark'),
                    onChanged: (v) => _changes['landmark'] = v.trim(),
                  ),
                  D4Field(
                    'Phone for patients',
                    _field('+91 33 4000 1234', 'patientPhone', 'phone'),
                    keyboard: TextInputType.phone,
                    onChanged: (v) => _changes['patientPhone'] = v.trim(),
                  ),
                ],
              ),
            ],
          ),
          D4Card(
            children: [
              D4CardTitle('Fees at this location', action: 'Add service', onAction: _addService),
              const D4Note('Patients see these before booking.'),
              VGap(
                gap: 14,
                children: [
                  for (var i = 0; i < _fees.length; i++)
                    Row(
                      key: ValueKey(i),
                      children: [
                        Expanded(child: D4TitleSub(_fees[i].$1, _fees[i].$2.isEmpty ? null : _fees[i].$2)),
                        const SizedBox(width: 12),
                        _FeeBox(_fees[i].$3, onChanged: (v) => _setFee(i, v)),
                      ],
                    ),
                ],
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Payments'),
              D4TagEditor(
                initial: _payments,
                addTitle: 'Add payment method',
                addLabel: 'Payment method',
                addHint: 'e.g. Net banking',
                onChanged: (v) => _changes['paymentMethods'] = v,
              ),
              D4SwitchRow(
                title: 'Collect fee at booking',
                sub: 'Patients pay online when they book a slot',
                value: _collectAtBooking,
                onChanged: (v) => setState(() {
                  _pickedCollect = v;
                  _changes['collectFeeAtBooking'] = v;
                }),
              ),
            ],
          ),
          D4AbdmCard(
            title: 'Health Facility Registry',
            body: 'Link this location’s HFR ID so records created here are recognised across ABDM.',
            idName: 'HFR ID',
            registerUrl: 'https://facility.abdm.gov.in/',
            pattern: RegExp(r'^IN\d{10}$'),
            hint: 'e.g. IN1910000123',
            linkedId: data == null ? null : _loc.str('hfrId'),
            onLink: isLive ? _linkHfr : null,
          ),
          D4Card(
            children: [
              const D4CardTitle('Facilities'),
              D4TagEditor(
                initial: _facilities,
                addTitle: 'Add facility',
                addLabel: 'Facility',
                addHint: 'e.g. ECG',
                onChanged: (v) => _changes['facilities'] = v,
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Schedule'),
              Tap(
                onTap: () => Nav.go(context, 'Profile-Schedule', args: data == null ? null : {'locationId': _id}),
                radius: 8,
                child: Row(
                  children: [
                    Expanded(child: D4TitleSub(schedule.$1, schedule.$2)),
                    const SizedBox(width: 12),
                    const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
                  ],
                ),
              ),
            ],
          ),
          D4OutlineButton('Stop practising here', onTap: _stopPractising),
        ],
      ),
    );
  }

  /// Map: 160px + 1px border, radius 16, pin at the centre, "Move pin" chip.
  Widget _map() {
    return Container(
      height: 162,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(color: MP.fill2, borderRadius: BorderRadius.circular(16)),
      foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
      child: Semantics(
        label: data == null ? 'Map showing City Care Clinic, Salt Lake' : 'Map showing $_name',
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            final p = _clampPin(_pin, w, h);
            final tip = Offset(w / 2 + p.dx, h / 2 + p.dy);
            return Stack(
              children: [
                Positioned.fill(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      if (_movingPin)
                        PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                          PanGestureRecognizer.new,
                          (r) =>
                              r
                                // Win over the page scroll as soon as the finger moves.
                                ..gestureSettings = const DeviceGestureSettings(touchSlop: 1)
                                ..onUpdate = (d) => setState(() => _pin = _clampPin(_pin + d.delta, w, h)),
                        ),
                    },
                    child: const Svg(_mapSvg, fit: BoxFit.cover),
                  ),
                ),
                // translate(-50%, -100%): the 32px pin box sits on top of the point.
                Positioned(left: tip.dx - 16, top: tip.dy - 32, child: const IgnorePointer(child: _Pin())),
                if (isLive)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Semantics(
                      button: true,
                      label: 'Put the pin where I am now',
                      child: Tap(
                        onTap: () async {
                          final p = await Where.pick(context);
                          if (p == null || !context.mounted) return;
                          setState(() {
                            _here = p;
                            _pin = Offset.zero;
                          });
                          toast(context, 'Pin set to your location · tap Save');
                        },
                        radius: 999,
                        color: _here == null ? MP.white : MP.primarySoft,
                        shadow: const [BoxShadow(color: Color(0x26111827), offset: Offset(0, 1), blurRadius: 3)],
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          height: 34,
                          child: Center(widthFactor: 1, child: Text(_here == null ? 'Use my location' : 'Pinned here', style: tx(13, w: w600, c: MP.primary))),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Tap(
                    onTap: _toggleMovePin,
                    radius: 999,
                    color: MP.white,
                    shadow: const [BoxShadow(color: Color(0x26111827), offset: Offset(0, 1), blurRadius: 3)],
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      height: 34,
                      child: Center(
                        widthFactor: 1,
                        child: Text(_movingPin ? 'Done' : 'Move pin', style: tx(13, w: w600, c: MP.primary)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Map pin: 32×32, radius 999 except bottom-left, rotated −45°, #003399 with
/// the button shadow and a 10px white dot.
class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 32,
    child: Transform.rotate(
      angle: -math.pi / 4,
      child: Container(
        decoration: const BoxDecoration(
          color: MP.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: MPShadow.button,
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: MP.white, shape: BoxShape.circle),
          ),
        ),
      ),
    ),
  );
}

/// Editable fee: 96×44 (border-box), padding 0 12, 1px #D5DBE5, radius 12,
/// right-aligned 15/700 tabular figures.
class _FeeBox extends StatefulWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  const _FeeBox(this.value, {this.onChanged});

  @override
  State<_FeeBox> createState() => _FeeBoxState();
}

class _FeeBoxState extends State<_FeeBox> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _f.hasFocus;
    return GestureDetector(
      onTap: _f.requestFocus,
      child: Container(
        width: 96,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: focused ? MP.primary : MP.lineStrong),
          boxShadow: focused ? MPShadow.focusRing : null,
        ),
        child: TextField(
          controller: _c,
          focusNode: _f,
          textAlign: TextAlign.right,
          textInputAction: TextInputAction.done,
          onChanged: widget.onChanged,
          style: tx(15, w: w700, tab: true),
          cursorColor: MP.primary,
          decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../data/where.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import '../../widgets/i18n.dart';

/// Profile → Home address. Its map point is where "km from you" to clinics is
/// measured from, so the sheet tries hard to get one: the phone's location, or
/// a suggestion picked while typing. A typed address with no point still saves
/// (the server keeps the last known point).
///
/// Live: GET /api/geo/reverse, GET /api/geo/search, PATCH /api/patient/me
/// {address: {line, area, city, pincode, lat, lng}}. Pops true once saved.
class AddressSheet extends StatefulWidget {
  /// The current default address, as in GET /api/patient/me `addresses`.
  final Map<String, dynamic>? initial;
  const AddressSheet({super.key, this.initial});

  @override
  State<AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<AddressSheet> {
  late final _line = TextEditingController(text: _str('line'));
  late final _area = TextEditingController(text: _str('area'));
  late final _city = TextEditingController(text: _str('city'));
  late final _pin = TextEditingController(text: _str('pincode'));
  final _busy = ValueNotifier(false);

  /// Map point sent with the address (distance origin).
  ({double lat, double lng})? _at;

  /// The address was edited after the point was set: still sent, flagged here.
  bool _approx = false;

  bool _locating = false;
  String? _note;
  bool _noteBad = false;
  String? _lineError;
  String? _pinError;

  List<Map<String, dynamic>> _hits = const [];
  Timer? _typing;

  String _str(String k) => '${widget.initial?[k] ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    // GeoJSON order: [lng, lat].
    final c = ((widget.initial?['geo'] as Map?)?['coordinates'] as List?) ?? const [];
    if (c.length == 2 && c[0] is num && c[1] is num) _at = (lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble());
  }

  @override
  void dispose() {
    _typing?.cancel();
    for (final c in [_line, _area, _city, _pin]) {
      c.dispose();
    }
    _busy.dispose();
    super.dispose();
  }

  /// "Use my current location": point first, then the address under it.
  Future<void> _useHere() async {
    if (_locating) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _locating = true;
      _note = null;
      _hits = const [];
    });
    if (!isLive) {
      // Design preview: no GPS, show a filled-in address.
      _fill({'label': '12 Lake Road', 'area': 'Salt Lake', 'city': 'Kolkata', 'pincode': '700064'}, (lat: 22.58, lng: 88.42));
      setState(() => _locating = false);
      return;
    }
    final p = await Where.here(fresh: true);
    if (!mounted) return;
    if (p == null) {
      final off = !await Geolocator.isLocationServiceEnabled().catchError((_) => false);
      if (!mounted) return;
      setState(() {
        _locating = false;
        _noteBad = true;
        _note = off
            ? 'Location is off on your phone. Turn it on and try again, or type your address below.'
            : 'MedPin can’t see your location. Allow location access and try again, or type your address below.';
      });
      return;
    }
    Map<String, dynamic>? place;
    try {
      final r = await Api.I.get('/api/geo/reverse', query: {'lat': '${p.lat}', 'lng': '${p.lng}'}) as Map;
      place = (r['place'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      // Offline or the map lookup is busy (503): the point alone is still useful.
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (place == null || '${place['label'] ?? ''}'.trim().isEmpty) {
        // Keep the point so distances work; the patient types the words.
        _at = p;
        _approx = false;
        _noteBad = true;
        _note = 'We found your location but not the address. Type your address below — distances will still be right.';
      }
    });
    if (place != null && '${place['label'] ?? ''}'.trim().isNotEmpty) {
      _fill(place, p);
      setState(() {
        _noteBad = false;
        _note = 'Filled from your location. Check it and add your house or flat number.';
      });
    }
  }

  /// Fills every field from a map place (reverse lookup or a picked suggestion).
  void _fill(Map<String, dynamic> place, ({double lat, double lng}) at) {
    String s(String k) => '${place[k] ?? ''}'.trim();
    final label = s('label').isNotEmpty ? s('label') : [s('road'), s('area')].where((x) => x.isNotEmpty).join(', ');
    // Keep a house / flat number the patient already typed ("DD-24, …"); the map doesn't know it.
    final first = _line.text.split(',').first.trim();
    final house = RegExp(r'\d').hasMatch(first) && first.length <= 24 && !label.toLowerCase().contains(first.toLowerCase());
    final pin = s('pincode').replaceAll(RegExp(r'\D'), '');
    setState(() {
      _line.text = house ? '$first, $label' : label;
      if (s('area').isNotEmpty) _area.text = s('area');
      if (s('city').isNotEmpty) _city.text = s('city');
      if (pin.length == 6) _pin.text = pin;
      _at = at;
      _approx = false;
      _hits = const [];
      _lineError = null;
      _pinError = null;
    });
  }

  /// Address typed: the point no longer matches exactly, and suggestions follow
  /// a moment after typing stops.
  void _onLineTyped(String v) {
    _edited();
    _typing?.cancel();
    final q = v.trim();
    if (q.length < 3 || !isLive) {
      if (_hits.isNotEmpty) setState(() => _hits = const []);
      return;
    }
    _typing = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  /// A hand edit after the point was set: keep the point, call it approximate.
  void _edited() {
    if (_at != null && !_approx) setState(() => _approx = true);
    if (_lineError != null || _note != null) {
      setState(() {
        _lineError = null;
        _note = null;
      });
    }
  }

  Future<void> _search(String q) async {
    try {
      final near = _at;
      final r = await Api.I.get('/api/geo/search', query: {'q': q, if (near != null) 'lat': '${near.lat}', if (near != null) 'lng': '${near.lng}'}) as Map;
      // Typed on since: a newer search is coming.
      if (!mounted || _line.text.trim() != q) return;
      final items = [
        for (final x in (r['items'] as List? ?? const []))
          if (x is Map && x['lat'] is num && x['lng'] is num) x.cast<String, dynamic>(),
      ];
      setState(() => _hits = items.take(5).toList());
    } catch (_) {
      // No suggestions (offline / busy): typing still works.
    }
  }

  Future<void> _speak() async {
    final said = await dictateInto(context, _line, title: 'Say your address');
    if (said == null || !mounted) return;
    _onLineTyped(_line.text);
  }

  Future<void> _save() async {
    final line = _line.text.trim();
    final pin = _pin.text.trim();
    setState(() {
      _lineError = line.isEmpty ? 'Enter your address' : null;
      _pinError = pin.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(pin) ? 'PIN code has 6 digits' : null;
    });
    if (_lineError != null || _pinError != null) return;
    final at = _at;
    final body = {
      'address': {
        'line': line,
        if (_area.text.trim().isNotEmpty) 'area': _area.text.trim(),
        if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        if (pin.isNotEmpty) 'pincode': pin,
        if (at != null) 'lat': at.lat,
        if (at != null) 'lng': at.lng,
      },
    };
    if (isLive) {
      final r = await runAction(context, () => Api.I.patch('/api/patient/me', body), busy: _busy);
      if (r == null || !mounted) return;
    }
    toast(context, 'Address saved');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: VGap(
        gap: 16,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: P2SheetHeader(title: 'Home address', subtitle: 'Distances to clinics are measured from here.'),
          ),
          MpButton(
            _locating ? 'Finding you…' : 'Use my current location',
            icon: I.pin,
            kind: MpBtn.secondary,
            onTap: _locating ? null : _useHere,
          ),
          if (_note != null) _Note(_note!, bad: _noteBad),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MpInput(
                label: 'Address',
                controller: _line,
                hint: 'House / flat, building, road',
                help: _lineError,
                helpColor: MP.red,
                borderColor: _lineError == null ? null : MP.red,
                onChanged: _onLineTyped,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: MpIconButton(I.mic, label: 'Speak your address', color: MP.primary, iconSize: 20, onTap: _speak),
                ),
              ),
              if (_hits.isNotEmpty) ...[
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
                  child: Column(
                    children: [
                      for (final h in _hits)
                        Tap(
                          onTap: () => _fill(h, (lat: (h['lat'] as num).toDouble(), lng: (h['lng'] as num).toDouble())),
                          radius: 10,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Row(children: [
                            const Ico(I.pin, size: 16, color: MP.ink3),
                            const Gap(8),
                            Expanded(child: Text('${h['label'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, h: 1.35))),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          MpInput(label: 'Area / locality', controller: _area, hint: 'e.g. Salt Lake Sector 1', onChanged: (_) => _edited()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MpInput(label: 'City', controller: _city, hint: 'e.g. Kolkata', onChanged: (_) => _edited())),
              const Gap(12),
              SizedBox(
                width: 132,
                child: MpInput(
                  label: 'PIN code',
                  controller: _pin,
                  hint: '6 digits',
                  keyboard: TextInputType.number,
                  tab: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  help: _pinError,
                  helpColor: MP.red,
                  borderColor: _pinError == null ? null : MP.red,
                  onChanged: (_) {
                    if (_pinError != null) setState(() => _pinError = null);
                  },
                ),
              ),
            ],
          ),
          _pointStatus(),
          const Gap(4),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, __) => MpButton(busy ? 'Saving…' : 'Save address', onTap: busy ? null : _save),
          ),
        ],
      ),
    );
  }

  /// Whether distances will be right: a point set, approximate, or none yet.
  Widget _pointStatus() {
    final (icon, color, text) = _at == null
        ? (I.alert, MP.amber, 'No map point yet. Use your current location or pick a suggestion so distances to clinics are right.')
        : _approx
            ? (I.alert, MP.amber, 'Map point is approximate — from before your edit. Distances may be a little off.')
            : (I.check, MP.green, 'Map point set. Distances to clinics are measured from here.');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Ico(icon, size: 16, color: color, stroke: 2)),
        const Gap(8),
        Expanded(child: Text(text, style: tx(13, c: MP.ink2, h: 1.4))),
      ],
    );
  }
}

/// A short message under "Use my current location" (amber when it didn't work).
class _Note extends StatelessWidget {
  final String text;
  final bool bad;
  const _Note(this.text, {required this.bad});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bad ? MP.amberSoft : MP.greenSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bad ? MP.amberLine : MP.greenLine),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Ico(bad ? I.alert : I.check, size: 16, color: bad ? MP.amber : MP.green, stroke: 2),
            ),
            const Gap(8),
            Expanded(child: Text(text, style: tx(14, c: MP.ink, h: 1.4))),
          ],
        ),
      );
}

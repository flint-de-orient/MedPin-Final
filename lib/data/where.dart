import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:geolocator/geolocator.dart';

import '../widgets/mp.dart';
import 'api.dart';
import 'config.dart';
import '../widgets/i18n.dart';

/// The phone's location: "doctors near me", distances, and the clinic pin
/// ("I'm at the clinic now"). Never blocks a screen for long, never asks twice
/// in a row after a refusal.
class Where {
  Where._();
  static ({double lat, double lng})? _last;
  static DateTime? _at;
  static bool _refused = false;

  /// Current position (cached 10 min). [ask]: show the permission prompt if needed.
  /// Returns null when location is off, refused, or slow.
  static Future<({double lat, double lng})?> here({bool ask = true, bool fresh = false}) async {
    if (AppMode.preview) return null;
    if (!fresh && _last != null && _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 10)) return _last;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask && !_refused) {
        p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied) _refused = true;
      }
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      } on TimeoutException {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return null;
      _last = (lat: pos.latitude, lng: pos.longitude);
      _at = DateTime.now();
      return _last;
    } catch (e) {
      debugPrint('location: $e');
      return null;
    }
  }

  /// Location for "Use my current location" buttons, with a toast when it fails.
  static Future<({double lat, double lng})?> pick(BuildContext context) async {
    final p = await here(fresh: true);
    if (p == null && context.mounted) {
      final off = !await Geolocator.isLocationServiceEnabled().catchError((_) => false);
      if (context.mounted) toast(context, off ? 'Turn on location on your phone and try again' : 'Allow location access for MedPin to set the pin');
    }
    return p;
  }
}

/// "Use my current location" link row; shows the pin once set.
class UseHereRow extends StatelessWidget {
  final ({double lat, double lng})? value;
  final ValueChanged<({double lat, double lng})> onPicked;
  final String label;
  const UseHereRow({super.key, required this.value, required this.onPicked, this.label = "I'm at the clinic now · use my location"});

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Semantics(
      button: true,
      label: v == null ? label : 'Clinic pin set. Tap to set again',
      child: Tap(
        onTap: () async {
          final p = await Where.pick(context);
          if (p != null) onPicked(p);
        },
        radius: 12,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Ico(v == null ? I.pin : I.check, size: 18, color: v == null ? MP.primary : MP.green, stroke: 2),
            const Gap(8),
            Expanded(
              child: Text(
                v == null ? label : 'Pin set here (${v.lat.toStringAsFixed(4)}, ${v.lng.toStringAsFixed(4)}) · tap to set again',
                style: tx(14, w: w600, c: v == null ? MP.primary : MP.ink2, h: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google Maps directions to a point.
String directionsUrl(double lat, double lng) => 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

/// The address at the phone's location, for every "Use current location"
/// (patient registration, a clinic's address, home address).
/// Returns {label, area, city, pincode, lat, lng} (label may be empty when the
/// map knows the point but not the street), or null with a toast when the
/// location is off / refused.
Future<Map<String, dynamic>?> addressHere(BuildContext context) async {
  if (AppMode.preview) return {'label': '12 Lake Road', 'area': 'Salt Lake', 'city': 'Kolkata', 'pincode': '700064', 'lat': 22.58, 'lng': 88.42};
  final p = await Where.pick(context);
  if (p == null) return null;
  Map<String, dynamic>? place;
  try {
    final r = await Api.I.get('/api/geo/reverse', query: {'lat': '${p.lat}', 'lng': '${p.lng}'}) as Map;
    place = (r['place'] as Map?)?.cast<String, dynamic>();
  } catch (_) {
    // Offline or the map lookup is busy: the point alone is still useful.
  }
  if ((place == null || '${place['label'] ?? ''}'.trim().isEmpty) && context.mounted) {
    toast(context, 'Found your location but not the street — type the address');
  }
  return {...?place, 'lat': p.lat, 'lng': p.lng};
}

/// One line for an address field from [addressHere]: "label, area, city pincode",
/// keeping a house / flat number already typed in [typed].
String addressLine(Map<String, dynamic> place, {String typed = ''}) {
  String s(String k) => '${place[k] ?? ''}'.trim();
  final parts = <String>[];
  final first = typed.split(',').first.trim();
  final label = s('label');
  if (RegExp(r'\d').hasMatch(first) && first.length <= 24 && !label.toLowerCase().contains(first.toLowerCase())) parts.add(first);
  if (label.isNotEmpty) parts.add(label);
  for (final k in ['area', 'city']) {
    final v = s(k);
    if (v.isNotEmpty && !parts.join(', ').toLowerCase().contains(v.toLowerCase())) parts.add(v);
  }
  final pin = s('pincode').replaceAll(RegExp(r'\D'), '');
  var line = parts.join(', ');
  if (pin.length == 6 && !line.contains(pin)) line = line.isEmpty ? pin : '$line $pin';
  return line;
}

/// "Use current location" link under an address field.
class UseHereLink extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onPlace;
  final String label;
  const UseHereLink({super.key, required this.onPlace, this.label = 'Use current location'});

  @override
  State<UseHereLink> createState() => _UseHereLinkState();
}

class _UseHereLinkState extends State<UseHereLink> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: Tap(
        onTap: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                final place = await addressHere(context);
                if (!mounted) return;
                setState(() => _busy = false);
                if (place != null) widget.onPlace(place);
              },
        radius: 12,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Ico(I.pin, size: 18, color: MP.primary, stroke: 2),
            const Gap(8),
            Text(_busy ? 'Finding your location…' : widget.label, style: tx(14, w: w600, c: MP.primary)),
          ],
        ),
      ),
    );
  }
}

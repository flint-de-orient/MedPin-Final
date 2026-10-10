import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:geolocator/geolocator.dart';

import '../widgets/mp.dart';
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/live.dart';
import '../data/where.dart';
import 'i18n.dart';
import 'mp.dart';

/// A pin set on the clinic map, with the address found there (if any).
typedef MapPin = ({double lat, double lng, Map<String, dynamic>? place});

/// The clinic's place on a real street map, picked like a ride app:
///
/// - Move the map freely: drag any way, pinch to zoom, turn with two fingers
///   (all the way round). The pin stays in the middle.
/// - When the map stops, that spot is the pin and the address below updates.
/// - 3D tilt or flat 2D; a compass appears once the map is turned (tap = north up).
/// - Without a saved pin it opens where the phone is; address search jumps there.
/// [onChanged] fires when the pin settles on a new spot.
class ClinicMap extends StatefulWidget {
  final double? lat;
  final double? lng;
  final String? label;
  final bool editable;
  final ValueChanged<MapPin>? onChanged;

  /// Fills the address fields from what was found under the pin.
  final ValueChanged<Map<String, dynamic>>? onUseAddress;

  /// Fill the address by itself when the pin settles (e.g. the field is empty).
  final bool autoFillAddress;

  /// Each time the user moves the map, [onUseAddress] gets the new place
  /// (the address follows the pin). Moves made from outside (lat/lng
  /// changed because the address was typed) don't call it.
  final bool addressFollowsPin;
  const ClinicMap({
    super.key,
    this.lat,
    this.lng,
    this.label,
    this.editable = true,
    this.onChanged,
    this.onUseAddress,
    this.autoFillAddress = false,
    this.addressFollowsPin = false,
  });

  /// Widget tests have no network: the map draws a plain backdrop instead of tiles.
  static bool offline = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<ClinicMap> createState() => _ClinicMapState();
}

class _ClinicMapState extends State<ClinicMap> {
  static const _kolkata = LatLng(22.5726, 88.3639);
  final _map = MapController();
  final _search = TextEditingController();
  late LatLng _pin = widget.lat != null && widget.lng != null ? LatLng(widget.lat!, widget.lng!) : _kolkata;
  late bool _hasPin = widget.lat != null && widget.lng != null;
  bool _tilt = true;
  bool _moving = false; // the map is being moved right now (pin lifted)
  bool _touched = false; // moved at least once (the hint then goes away)
  double _rotation = 0;
  bool _searching = false;
  Map<String, dynamic>? _place;
  List<Map<String, dynamic>> _results = const [];
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    if (_hasPin) {
      _lookup(_pin);
    } else if (widget.editable && isLive) {
      _startHere();
    }
  }

  /// No pin yet: open where the phone is (asks for location once).
  Future<void> _startHere() async {
    final p = await Where.here();
    if (p == null || !mounted || _hasPin) return;
    _goTo(LatLng(p.lat, p.lng));
  }

  @override
  void didUpdateWidget(ClinicMap old) {
    super.didUpdateWidget(old);
    if ((widget.lat != old.lat || widget.lng != old.lng) && widget.lat != null && widget.lng != null) {
      final p = LatLng(widget.lat!, widget.lng!);
      if (p != _pin) _goTo(p, notify: false);
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _goTo(LatLng p, {bool notify = true, double zoom = 17}) {
    setState(() {
      _pin = p;
      _hasPin = true;
      _results = const [];
    });
    if (!ClinicMap.offline) _map.move(p, zoom);
    _lookup(p);
    if (notify) widget.onChanged?.call((lat: p.latitude, lng: p.longitude, place: _place));
  }

  /// The address under the pin (backend → OpenStreetMap), quietly.
  Future<void> _lookup(LatLng p, {bool byUser = false}) async {
    if (!isLive) return;
    try {
      final r = await Api.I.get('/api/geo/reverse', query: {'lat': '${p.latitude}', 'lng': '${p.longitude}'}) as Map;
      if (!mounted || _pin != p) return;
      final place = (r['place'] as Map?)?.cast<String, dynamic>();
      setState(() => _place = place);
      if (place != null && widget.editable && (widget.autoFillAddress || (byUser && widget.addressFollowsPin))) widget.onUseAddress?.call(place);
    } catch (_) {}
  }

  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.length < 3) return toast(context, 'Type at least 3 letters of the address');
    if (!isLive) return;
    setState(() => _searching = true);
    try {
      final r = await Api.I.get('/api/geo/search', query: {'q': q, 'lat': '${_pin.latitude}', 'lng': '${_pin.longitude}'}) as Map;
      final items = [for (final x in (r['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      if (!mounted) return;
      if (items.isEmpty) toast(context, 'No place found. Try the area and city, e.g. “Sector 1, Salt Lake”');
      setState(() => _results = items);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onMapEvent(MapEvent e) {
    final rot = e.camera.rotation;
    if (rot != _rotation) setState(() => _rotation = rot);
    if (!widget.editable) return;
    final user = e.source != MapEventSource.mapController && e.source != MapEventSource.nonRotatedSizeChange;
    if (e is MapEventMove && user) {
      // The pin stays in the middle while the map moves under it.
      if (!_moving) setState(() => _moving = _touched = true);
      _pin = e.camera.center;
      _settle?.cancel();
    }
    final ended = e is MapEventMoveEnd || e is MapEventFlingAnimationEnd || e is MapEventRotateEnd || e is MapEventDoubleTapZoomEnd || e is MapEventScrollWheelZoom;
    if (ended && user) {
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        final c = _map.camera.center;
        setState(() {
          _moving = false;
          _pin = c;
          _hasPin = true;
          _place = null;
        });
        _lookup(c, byUser: true);
        widget.onChanged?.call((lat: c.latitude, lng: c.longitude, place: null));
      });
    }
  }

  Future<void> _openInMaps({bool directions = false}) async {
    final ll = '${_pin.latitude},${_pin.longitude}';
    final url = directions ? 'https://www.google.com/maps/dir/?api=1&destination=$ll' : 'https://www.google.com/maps/search/?api=1&query=$ll';
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) toast(context, "Couldn't open Google Maps");
  }

  Widget _chip(String text, VoidCallback onTap, {bool on = false, String? icon}) => MpHitSlop(child: Tap(
        onTap: onTap,
        radius: 999,
        color: on ? MP.primary : MP.white,
        shadow: const [BoxShadow(color: Color(0x26111827), offset: Offset(0, 2), blurRadius: 6)],
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 36,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Ico(icon, size: 16, color: on ? MP.white : MP.primary, stroke: 2), const Gap(6)],
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, w: w600, c: on ? MP.white : MP.primary))),
          ]),
        ),
      ));

  Widget _tiles() {
    if (ClinicMap.offline) {
      return Container(color: const Color(0xFFEAF0F6));
    }
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _pin,
        initialZoom: _hasPin ? 17 : 12,
        minZoom: 4,
        maxZoom: 19,
        backgroundColor: const Color(0xFFEAF0F6),
        // Drag any way, pinch to zoom, two-finger turn (all the way round).
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        onMapEvent: _onMapEvent,
      ),
      children: [
        TileLayer(
          // OpenStreetMap's own tiles (fine for testing and a small clinic app; use a
          // tile service with a key for heavy production traffic).
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.fdo.medpin',
          maxZoom: 19,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final place = _place;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editable) ...[
          Row(
            children: [
              Expanded(
                child: MpInput(
                  controller: _search,
                  hint: 'Search address or area',
                  leadingIcon: I.search,
                  height: 48,
                  onChanged: (_) {
                    if (_results.isNotEmpty) setState(() => _results = const []);
                  },
                ),
              ),
              const Gap(8),
              MpButton(_searching ? '…' : 'Find', expand: false, height: 48, onTap: _searching ? null : _find),
            ],
          ),
          for (final r in _results.take(5))
            Tap(
              onTap: () => _goTo(LatLng(r['lat'] as double, r['lng'] as double)),
              radius: 10,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(children: [
                const Ico(I.pin, size: 16, color: MP.ink3),
                const Gap(8),
                Expanded(child: Text('${r['label']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, h: 1.35))),
              ]),
            ),
          const Gap(12),
        ],
        // The map, tilted for a 3D look.
        Semantics(
          label: _hasPin ? 'Map of ${widget.label ?? 'the clinic'} with its pin' : 'Map. The clinic pin is not set yet',
          child: Container(
            height: 240,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0F6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: MP.line),
              boxShadow: const [BoxShadow(color: Color(0x14111827), offset: Offset(0, 6), blurRadius: 18)],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    transformAlignment: Alignment.center,
                    // Perspective tilt; scaled up so the tilted map still fills the frame.
                    transform: _tilt
                        ? (Matrix4.identity()
                          ..setEntry(3, 2, 0.0011)
                          ..rotateX(-0.55)
                          ..scaleByDouble(1.45, 1.45, 1, 1))
                        : Matrix4.identity(),
                    child: _tiles(),
                  ),
                ),
                // Soft sky at the far edge when tilted.
                if (_tilt)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 46,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE6F7F9FC), Color(0x00F7F9FC)]),
                        ),
                      ),
                    ),
                  ),
                // The pin, upright over the map centre (its tip on the point), in 2D and 3D.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: Transform.translate(offset: const Offset(0, -17), child: _Pin(lifted: _moving))),
                  ),
                ),
                Positioned(left: 10, top: 10, child: _chip(_tilt ? '3D' : '2D', () => setState(() => _tilt = !_tilt), on: _tilt)),
                if (!_hasPin)
                  Positioned(
                    left: 64,
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(999)),
                      child: Text('Pin not set yet', style: tx(12, w: w600, c: MP.amber)),
                    ),
                  ),
                if (_rotation.abs() > 0.5)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Semantics(
                      button: true,
                      label: 'Turn north up',
                      child: Tap(
                        onTap: () => ClinicMap.offline ? null : _map.rotate(0),
                        radius: 999,
                        color: MP.white,
                        shadow: const [BoxShadow(color: Color(0x26111827), offset: Offset(0, 2), blurRadius: 6)],
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(child: Transform.rotate(angle: -_rotation * 3.14159265 / 180, child: const _Compass())),
                        ),
                      ),
                    ),
                  ),
                if (widget.editable)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _moving || _touched ? 0 : 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(color: const Color(0xCC111827), borderRadius: BorderRadius.circular(999)),
                            child: Text('Move the map to place the pin', style: tx(12, w: w600, c: MP.white)),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: _rotation.abs() > 0.5 ? 56 : 12,
                  top: 12,
                  child: IgnorePointer(child: Text('© OpenStreetMap contributors', style: tx(9, c: MP.ink3))),
                ),
              ],
            ),
          ),
        ),
        const Gap(10),
        // What's at the pin, and the way there.
        if (_hasPin)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.pin, size: 16, color: MP.primary)),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      place?['label'] != null ? 'Near ${place!['label']}' : '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
                      style: tx(14, h: 1.4),
                    ),
                  ),
                ]),
                const Gap(8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (widget.onUseAddress != null && place != null) _chip('Use this address', () => widget.onUseAddress!(place)),
                  _chip('Directions', () => _openInMaps(directions: true)),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}

/// Map pin: navy drop with a white dot and a ground shadow.
class _Pin extends StatelessWidget {
  /// Raised while the map moves under it.
  final bool lifted;
  const _Pin({this.lifted = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 56,
        child: Stack(alignment: Alignment.topCenter, children: [
          Positioned(
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: lifted ? 12 : 18,
              height: 6,
              decoration: BoxDecoration(color: Color(lifted ? 0x26111827 : 0x40111827), borderRadius: BorderRadius.circular(999)),
            ),
          ),
          AnimatedSlide(
            duration: const Duration(milliseconds: 200),
            offset: Offset(0, lifted ? -0.18 : 0),
            child: Transform.rotate(
            angle: -0.785398,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: MP.primary,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(999), topRight: Radius.circular(999), bottomRight: Radius.circular(999)),
                boxShadow: [BoxShadow(color: Color(0x40003399), offset: Offset(0, 4), blurRadius: 8)],
              ),
              child: Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: MP.white, shape: BoxShape.circle))),
            ),
          ),
          ),
        ]),
      );
}

/// Compass needle: red north, grey south.
class _Compass extends StatelessWidget {
  const _Compass();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(18, 22), painter: _CompassPainter());
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final north = Path()
      ..moveTo(c.dx, 0)
      ..lineTo(c.dx + 5, c.dy)
      ..lineTo(c.dx - 5, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, size.height)
      ..lineTo(c.dx + 5, c.dy)
      ..lineTo(c.dx - 5, c.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = MP.red);
    canvas.drawPath(south, Paint()..color = MP.ink3);
  }

  @override
  bool shouldRepaint(_CompassPainter old) => false;
}

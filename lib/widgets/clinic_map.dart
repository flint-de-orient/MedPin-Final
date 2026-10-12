import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/live.dart';
import '../data/where.dart';
import 'i18n.dart';
import 'mp.dart';

/// A pin set on the clinic map, with the address found there (if any).
typedef MapPin = ({double lat, double lng, Map<String, dynamic>? place});

/// The clinic's place on a real street map.
///
/// - Street map (OpenStreetMap data, CARTO "Voyager" style) with a 3D tilt.
/// - Drag the map to put the pin on the entrance; zoom, recenter.
/// - "Use my location" and address search jump the map there.
/// - Shows the address found under the pin ("Use this address").
/// - Opens Google Maps / directions to the pin.
/// [onChanged] fires when the pin moves (after the map settles).
class ClinicMap extends StatefulWidget {
  final double? lat;
  final double? lng;
  final String? label;
  final bool editable;
  final ValueChanged<MapPin>? onChanged;

  /// Fills the address fields from what was found under the pin.
  final ValueChanged<Map<String, dynamic>>? onUseAddress;
  const ClinicMap({super.key, this.lat, this.lng, this.label, this.editable = true, this.onChanged, this.onUseAddress});

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
  bool _moving = false;
  bool _searching = false;
  Map<String, dynamic>? _place;
  List<Map<String, dynamic>> _results = const [];
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    if (_hasPin) _lookup(_pin);
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
  Future<void> _lookup(LatLng p) async {
    if (!isLive) return;
    try {
      final r = await Api.I.get('/api/geo/reverse', query: {'lat': '${p.latitude}', 'lng': '${p.longitude}'}) as Map;
      if (mounted && _pin == p) setState(() => _place = (r['place'] as Map?)?.cast<String, dynamic>());
    } catch (_) {}
  }

  Future<void> _useMyLocation() async {
    final p = await Where.pick(context);
    if (p == null || !mounted) return;
    _goTo(LatLng(p.lat, p.lng));
    toast(context, 'Pin set to where you are');
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
    if (!_moving || !widget.editable) return;
    // While "Move pin" is on, the pin stays in the middle and the map moves under it.
    if (e is MapEventMove || e is MapEventMoveEnd || e is MapEventFlingAnimationEnd) {
      final c = e.camera.center;
      setState(() => _pin = c);
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _hasPin = true;
        _lookup(c);
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

  Widget _round(String icon, String label, VoidCallback onTap, {bool on = false}) => Semantics(
        button: true,
        label: label,
        child: Tap(
          onTap: onTap,
          radius: 12,
          color: on ? MP.primary : MP.white,
          shadow: const [BoxShadow(color: Color(0x26111827), offset: Offset(0, 2), blurRadius: 6)],
          child: SizedBox(width: 40, height: 40, child: Center(child: Ico(icon, size: 18, color: on ? MP.white : MP.ink, stroke: 2))),
        ),
      );

  Widget _chip(String text, VoidCallback onTap, {bool on = false, String? icon}) => Tap(
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
      );

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
        interactionOptions: InteractionOptions(
          // The map stays centred on the pin. With "Move pin" the map moves under
          // it; otherwise the page scrolls past and the buttons zoom.
          flags: _moving ? InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.flingAnimation : InteractiveFlag.none,
        ),
        onMapEvent: _onMapEvent,
        onTap: widget.editable && _moving ? (_, p) => _goTo(p, zoom: _map.camera.zoom) : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: RetinaMode.isHighDensity(context),
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
                          ..rotateX(-0.62)
                          ..scaleByDouble(1.35, 1.35, 1, 1))
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
                Positioned(
                  right: 10,
                  top: 10,
                  child: Column(children: [
                    _round(I.plus, 'Zoom in', () => ClinicMap.offline ? null : _map.move(_map.camera.center, (_map.camera.zoom + 1).clamp(4, 19))),
                    const Gap(8),
                    _round(I.minus, 'Zoom out', () => ClinicMap.offline ? null : _map.move(_map.camera.center, (_map.camera.zoom - 1).clamp(4, 19))),
                    const Gap(8),
                    _round(I.pin, 'Back to the pin', () => ClinicMap.offline ? null : _map.move(_pin, 17)),
                  ]),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  right: 10,
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (widget.editable) ...[
                      Flexible(child: _chip('Use my location', _useMyLocation, icon: I.pin)),
                      const Gap(8),
                      Flexible(
                        child: _chip(_moving ? 'Done' : 'Move pin', () {
                          setState(() => _moving = !_moving);
                          if (_moving) toast(context, 'Drag the map to put the pin on the entrance');
                        }, on: _moving),
                      ),
                    ],
                  ]),
                ),
                Positioned(
                  right: 56,
                  top: 12,
                  child: IgnorePointer(child: Text('© OpenStreetMap · © CARTO', style: tx(9, c: MP.ink3))),
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
                  _chip('Open in Google Maps', () => _openInMaps()),
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

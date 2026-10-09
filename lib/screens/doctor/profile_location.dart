import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d4.dart';

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

class _ProfileLocationScreenState extends State<ProfileLocationScreen> {
  static const _types = ['Clinic', 'Hospital', 'Nursing home', 'Diagnostic centre', 'Video consultation'];

  String _type = 'Clinic';
  bool _collectAtBooking = false;
  bool _movingPin = false;

  /// Pin offset from the map centre (dragged while "Move pin" is on).
  Offset _pin = Offset.zero;

  final List<(String, String, String)> _fees = [
    ('New consultation', '15 min · in clinic', '₹600'),
    ('Follow-up', 'Repeat visit for the same problem', '₹600'),
    ('Report review', 'Within 7 days of a visit', 'Free'),
    ('Video consultation', '15 min', '₹600'),
  ];

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
    final fee = r[2].isEmpty ? 'Free' : (int.tryParse(r[2]) != null ? '₹${r[2]}' : r[2]);
    setState(() => _fees.add((r[0], r[1], fee)));
  }

  Future<void> _stopPractising() async {
    final ok = await d4Confirm(
      context,
      title: 'Stop practising here?',
      body: 'New bookings at City Care · Salt Lake stop. Every patient’s history is kept.',
      confirm: 'Stop practising here',
    );
    if (!ok || !mounted) return;
    d4Save(context, 'You no longer practise at City Care · Salt Lake');
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: D4Header('City Care · Salt Lake', subtitle: 'Location', onSave: () => d4Save(context)),
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
                  const D4Field('Location name', 'City Care Clinic · Salt Lake'),
                  D4SelectField('Type', _type, options: _types, onChanged: (v) => setState(() => _type = v)),
                  const D4Field('Address', 'DD-24, Sector 1, Salt Lake, Kolkata 700064'),
                  const D4Field('Landmark', 'Opposite Tank 9, near City Centre'),
                  const D4Field('Phone for patients', '+91 33 4000 1234', keyboard: TextInputType.phone),
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
                        _FeeBox(_fees[i].$3),
                      ],
                    ),
                ],
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Payments'),
              const D4TagEditor(
                initial: ['UPI', 'Cash', 'Card'],
                addTitle: 'Add payment method',
                addLabel: 'Payment method',
                addHint: 'e.g. Net banking',
              ),
              D4SwitchRow(
                title: 'Collect fee at booking',
                sub: 'Patients pay online when they book a slot',
                value: _collectAtBooking,
                onChanged: (v) => setState(() => _collectAtBooking = v),
              ),
            ],
          ),
          const D4AbdmCard(
            title: 'Health Facility Registry',
            body: 'Link this location’s HFR ID so records created here are recognised across ABDM.',
            idName: 'HFR ID',
            hint: 'e.g. IN1910000123',
          ),
          const D4Card(
            children: [
              D4CardTitle('Facilities'),
              D4TagEditor(
                initial: ['Wheelchair access', 'Parking', 'Lab sample collection', 'Pharmacy'],
                addTitle: 'Add facility',
                addLabel: 'Facility',
                addHint: 'e.g. ECG',
              ),
            ],
          ),
          D4Card(
            children: [
              const D4CardTitle('Schedule'),
              Tap(
                onTap: () => Nav.go(context, 'Profile-Schedule'),
                radius: 8,
                child: const Row(
                  children: [
                    Expanded(child: D4TitleSub('Mon – Sat · 9:00 AM – 1:00 PM', '15-min slots · up to 16 patients')),
                    SizedBox(width: 12),
                    Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
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
        label: 'Map showing City Care Clinic, Salt Lake',
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
  const _FeeBox(this.value);

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
          style: tx(15, w: w700, tab: true),
          cursorColor: MP.primary,
          decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Clinic-Editor.dc.html — "Location editor" (Edit location).
class ClinicEditorScreen extends StatefulWidget {
  const ClinicEditorScreen({super.key});

  @override
  State<ClinicEditorScreen> createState() => _ClinicEditorScreenState();
}

class _ClinicEditorScreenState extends State<ClinicEditorScreen> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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

  void _save() {
    toast(context, 'Location saved');
    Nav.back(context);
  }

  Future<void> _editHours(int i) async {
    final r = await openSheet<String>(context, (_) => _HoursSheet(day: _days[i], range: _ranges[i]));
    if (r == null || !mounted) return;
    setState(() {
      _ranges[i] = r;
      _open[i] = true;
    });
  }

  Future<void> _addClosure() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(2026, 10, 1),
      firstDate: DateTime(2026, 9, 29),
      lastDate: DateTime(2027, 12, 31),
      helpText: 'Closed on',
    );
    if (d == null || !mounted) return;
    setState(() => _closures.add((d7Date(d), 'Closed all day')));
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: MpHeader(
        'Edit location',
        actions: [
          D7Btn('Save', height: 44, size: 16, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: _save),
        ],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          _details(),
          _letterhead(),
          _mapLink(),
          _weeklyHours(),
          _closuresCard(),
          _perDoctor(),
          Padding(padding: const EdgeInsets.only(top: 8), child: MpButton('Save changes', onTap: _save)),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: D7Ruled(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  D7Btn(
                    'Deactivate location',
                    fg: MP.red,
                    size: 16,
                    padding: EdgeInsets.zero,
                    onTap: () {
                      toast(context, 'Location deactivated · history kept');
                      Nav.back(context);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '3 patients have upcoming bookings here. Deactivating keeps their history.',
                    style: tx(14, c: MP.ink2, h: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details() {
    return const MpCard(
      child: VGap(
        gap: 16,
        children: [
          D7Title('Details'),
          D7Labeled('Location name', child: D7Field(value: 'City Care Clinic — Salt Lake')),
          D7Labeled(
            'Address',
            child: D7Field(
              value: 'DD-24, Sector 1, Salt Lake, Kolkata 700064',
              lines: 2,
              height: 80,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          D7Labeled('Clinic phone', child: D7Field(value: '033 4012 5678', tab: true, keyboard: TextInputType.phone)),
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
          const D7Labeled('Tagline', child: D7Field(value: 'Diabetes, thyroid and heart care')),
          const D7Labeled(
            'Doctor name as printed',
            child: D7Field(value: 'Dr. Arjun Sen, MBBS, MD (Medicine)', ellipsis: true),
          ),
          const D7Labeled('Registration number', child: D7Field(value: 'WBMC 64213', tab: true)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Logo', style: tx(14, w: w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Semantics(
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
                        Text('citycare-logo.png', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w600)),
                        const SizedBox(height: 2),
                        Text('PNG · 48 KB', style: tx(13, c: MP.ink3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  D7Btn(
                    'Replace',
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onTap: () => toast(context, 'Choose a new logo file'),
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
    return const MpCard(
      child: VGap(
        gap: 16,
        children: [
          D7Title('Map link'),
          D7Labeled(
            'Google Maps link',
            help: 'Patients get this with every booking confirmation.',
            child: D7Field(
              value: 'https://maps.app.goo.gl/Qx7bR2mLk9',
              keyboard: TextInputType.url,
              ellipsis: true,
              padding: EdgeInsets.only(left: 46, right: 16),
              overlays: [
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
                        onTap: () => setState(() => _closures.remove(c)),
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
          for (final d in _doctors)
            Tap(
              onTap: () => Nav.go(context, 'Profile-Schedule'),
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

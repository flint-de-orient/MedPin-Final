import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Design: Profile-Schedule.dc.html — "Profile · schedules and slots".
class ProfileScheduleScreen extends StatefulWidget {
  const ProfileScheduleScreen({super.key});

  @override
  State<ProfileScheduleScreen> createState() => _ProfileScheduleScreenState();
}

/// One practice location's schedule. Times are minutes from midnight.
class _Loc {
  _Loc(this.name, this.week, {required this.slot, required this.walkIns});
  final String name;

  /// Mon … Sun; an empty list means closed.
  final List<List<(int, int)>> week;
  int slot;
  int walkIns;
  int perSlot = 1;
  int breakMin = 0;
  int ahead = 7;
  int cancel = 2;
  bool online = true;
  bool approve = false;
}

class _ProfileScheduleScreenState extends State<ProfileScheduleScreen> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static List<List<(int, int)>> _week(Set<int> open, (int, int) hours, {Map<int, (int, int)> except = const {}}) => [
    for (var d = 0; d < 7; d++) open.contains(d) ? [except[d] ?? hours] : <(int, int)>[],
  ];

  final List<_Loc> _locs = [
    _Loc('Salt Lake', _week({0, 1, 2, 3, 4, 5}, (540, 780), except: {5: (540, 690)}), slot: 15, walkIns: 4),
    _Loc('New Town', _week({1, 2, 3, 5}, (1080, 1230)), slot: 20, walkIns: 2),
    _Loc('Gariahat', _week({3, 5}, (840, 930)), slot: 15, walkIns: 2),
    _Loc('Video', _week({0, 1, 2, 3, 4}, (960, 1020)), slot: 15, walkIns: 0),
  ];
  int _sel = 0;

  final List<(String, String)> _leave = [('Durga Puja', '19 – 23 Oct · all locations · 14 patients will be told')];

  _Loc get _loc => _locs[_sel];

  // ── Time helpers ──────────────────────────────────────────────────────────

  /// 12-hour clock without AM/PM, as in the design ("9:00", "1:00").
  static String _t(int m) {
    final h = (m ~/ 60) % 12;
    return '${h == 0 ? 12 : h}:${(m % 60).toString().padLeft(2, '0')}';
  }

  static String _range((int, int) r) => '${_t(r.$1)} – ${_t(r.$2)}';

  /// Parses "9:00", "1:30", "6 pm". Without AM/PM, 1–6 o'clock means
  /// afternoon/evening; an end time at or before [after] is moved 12 h later.
  static int? _parse(String text, {int? after}) {
    final m = RegExp(r'^(\d{1,2})(?:[:.](\d{2}))?\s*([ap]m)?$', caseSensitive: false).firstMatch(text.trim());
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2) ?? '0');
    if (h > 23 || min > 59) return null;
    final ap = m.group(3)?.toLowerCase();
    if (ap != null) {
      if (h == 0 || h > 12) return null;
      h = h % 12 + (ap == 'pm' ? 12 : 0);
    } else if (h >= 1 && h <= 6) {
      h += 12;
    }
    var v = h * 60 + min;
    if (after != null && ap == null && v <= after && v + 720 < 24 * 60) v += 720;
    return v;
  }

  /// Chip subtitle: "Mon – Sat", "4 evenings", "Thu, Sat".
  static String _summary(_Loc l) {
    final open = [
      for (var d = 0; d < 7; d++)
        if (l.week[d].isNotEmpty) d,
    ];
    if (open.isEmpty) return 'Closed';
    if (open.every((d) => l.week[d].every((r) => r.$1 >= 17 * 60))) {
      return '${open.length} ${open.length == 1 ? 'evening' : 'evenings'}';
    }
    if (open.length >= 3 && open.last - open.first == open.length - 1) {
      return '${_days[open.first]} – ${_days[open.last]}';
    }
    return open.map((d) => _days[d]).join(', ');
  }

  /// First open day (index) of [l], or -1.
  static int _previewDay(_Loc l) => l.week.indexWhere((r) => r.isNotEmpty);

  /// Number of slots in the first session of the preview day.
  static int _slotCount(_Loc l) {
    final d = _previewDay(l);
    if (d < 0) return 0;
    final (s, e) = l.week[d].first;
    if (e - s < l.slot) return 0;
    return (e - s - l.slot) ~/ (l.slot + l.breakMin) + 1;
  }

  /// Applies [change] to the selected location, keeping walk-ins ≤ slots.
  void _update(void Function(_Loc l) change) {
    setState(() {
      change(_loc);
      _loc.walkIns = math.min(_loc.walkIns, _slotCount(_loc));
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _copyHours() async {
    final others = [
      for (final l in _locs)
        if (l != _loc) l.name,
    ];
    final r = await d4PickOne(context, title: 'Copy hours from', options: others);
    if (r == null || !mounted) return;
    final from = _locs.firstWhere((l) => l.name == r);
    _update((l) {
      for (var d = 0; d < 7; d++) {
        l.week[d] = [...from.week[d]];
      }
    });
    toast(context, 'Copied hours from $r');
  }

  Future<void> _editDay(int d) async {
    final l = _loc;
    final open = l.week[d].isNotEmpty;
    final (s, e) = open ? l.week[d].first : (540, 780);
    final r = await d4FormSheet(
      context,
      title: '${_dayNames[d]} hours',
      subtitle: l.name,
      fields: [
        D4FormField('From', value: _t(s), hint: 'e.g. 9:00'),
        D4FormField('To', value: _t(e), hint: 'e.g. 1:00'),
      ],
      confirm: open ? 'Save hours' : 'Add hours',
      removeLabel: open ? 'Closed on ${_dayNames[d]}s' : null,
    );
    if (r == null || !mounted) return;
    if (r.isEmpty) {
      _update((l) => l.week[d] = []);
      return;
    }
    final from = _parse(r[0]);
    final to = from == null ? null : _parse(r[1], after: from);
    if (from == null || to == null || to <= from) {
      toast(context, 'Enter times like 9:00 and 1:00');
      return;
    }
    _update((l) {
      if (l.week[d].isEmpty) {
        l.week[d] = [(from, to)];
      } else {
        l.week[d][0] = (from, to);
      }
    });
  }

  Future<void> _addLeave() async {
    final r = await d4FormSheet(
      context,
      title: 'Add leave',
      fields: const [
        D4FormField('Reason', hint: 'e.g. Medical conference'),
        D4FormField('Dates', hint: 'e.g. 12 – 14 Nov'),
      ],
      confirm: 'Add leave',
    );
    if (r == null || r.length < 2 || r[0].isEmpty || !mounted) return;
    setState(() => _leave.add((r[0], '${r[1].isEmpty ? 'Dates not set' : r[1]} · all locations')));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = _loc;
    return MpPage(
      header: D4Header(
        'Schedules and slots',
        subtitle: 'Set separately for each location',
        onSave: () => d4Save(context),
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Location chips: full-bleed row (margin 0 −16, padding 0 16).
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (var i = 0; i < _locs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    D4OptionCard(
                      title: _locs[i].name,
                      sub: _summary(_locs[i]),
                      selected: i == _sel,
                      titleSize: 14,
                      nowrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      onTap: () => setState(() => _sel = i),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            VGap(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gap: 16,
              children: [_hoursCard(l), _slotsCard(l), _previewCard(l), _rulesCard(l), _leaveCard()],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hoursCard(_Loc l) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D4CardTitle('Weekly hours · ${l.name}', action: 'Copy hours', onAction: _copyHours),
          // gap 14 with the list's margin-top −12
          const SizedBox(height: 2),
          for (var d = 0; d < 7; d++) _dayRow(l, d),
        ],
      ),
    );
  }

  Widget _dayRow(_Loc l, int d) {
    final ranges = l.week[d];
    final closed = ranges.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(_days[d], style: tx(15, w: w700, c: closed ? MP.ink3 : MP.ink))),
          const SizedBox(width: 12),
          Expanded(
            child:
                closed
                    ? Text('Closed', style: tx(14, c: MP.ink3))
                    : Wrap(spacing: 6, runSpacing: 6, children: [for (final r in ranges) _HoursPill(_range(r))]),
          ),
          const SizedBox(width: 12),
          if (closed)
            D4TextLink('Add hours', onTap: () => _editDay(d))
          else
            MpIconButton(
              I.pencil,
              label: 'Edit ${_days[d]}',
              size: 36,
              iconSize: 16,
              radius: 10,
              color: MP.ink2,
              onTap: () => _editDay(d),
            ),
        ],
      ),
    );
  }

  Widget _slotsCard(_Loc l) {
    final slots = _slotCount(l);
    return D4Card(
      children: [
        const D4CardTitle('Slots'),
        VGap(
          gap: 16,
          children: [
            D4StepperRow(
              title: 'Slot length',
              sub: 'Time you plan per patient',
              value: '${l.slot} min',
              onMinus: () => _update((l) => l.slot = math.max(5, l.slot - 5)),
              onPlus: () => _update((l) => l.slot = math.min(60, l.slot + 5)),
            ),
            D4StepperRow(
              title: 'Patients per slot',
              sub: 'More than 1 lets you double-book',
              value: '${l.perSlot}',
              onMinus: () => _update((l) => l.perSlot = math.max(1, l.perSlot - 1)),
              onPlus: () => _update((l) => l.perSlot = math.min(6, l.perSlot + 1)),
            ),
            D4StepperRow(
              title: 'Walk-in places',
              sub: 'Kept free each session',
              value: '${l.walkIns}',
              onMinus: () => _update((l) => l.walkIns = math.max(0, l.walkIns - 1)),
              onPlus: () => _update((l) => l.walkIns = math.min(slots, l.walkIns + 1)),
            ),
            D4StepperRow(
              title: 'Break between patients',
              sub: 'For notes and hand-wash',
              value: '${l.breakMin} min',
              onMinus: () => _update((l) => l.breakMin = math.max(0, l.breakMin - 5)),
              onPlus: () => _update((l) => l.breakMin = math.min(30, l.breakMin + 5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _previewCard(_Loc l) {
    final day = _previewDay(l);
    if (day < 0) {
      return const D4Card(
        children: [D4CardTitle('Slot preview'), D4Note('Add weekly hours to see the slots patients can book.')],
      );
    }
    final (start, _) = l.week[day].first;
    final step = l.slot + l.breakMin;
    final n = _slotCount(l);
    final w = math.min(l.walkIns, n);
    // Walk-in places are kept at the end of each half of the session.
    final half = (n + 1) ~/ 2, firstHalf = (w + 1) ~/ 2, secondHalf = w - firstHalf;
    bool walkIn(int i) => (i >= half - firstHalf && i < half) || i >= n - secondHalf;
    final part = start < 12 * 60 ? 'morning' : (start < 17 * 60 ? 'afternoon' : 'evening');
    final caption =
        n == 0
            ? 'No slots fit in these hours'
            : w == 0
            ? '$n slots each $part · all bookable online'
            : '$n slots each $part · ${n - w} bookable online, $w kept for walk-ins (grey)';
    return D4Card(
      children: [
        D4CardTitle('Slot preview · ${_dayNames[day]}'),
        if (n > 0)
          MpGrid(
            columns: 4,
            gap: 6,
            children: [for (var i = 0; i < math.min(n, 8); i++) _SlotCell(_t(start + i * step), walkIn: walkIn(i))],
          ),
        Text(caption, style: tx(13, c: MP.ink2)),
      ],
    );
  }

  Widget _rulesCard(_Loc l) {
    return D4Card(
      children: [
        const D4CardTitle('Booking rules'),
        VGap(
          gap: 16,
          children: [
            D4SwitchRow(
              title: 'Online booking',
              sub: 'Patients book from the MedPin app',
              value: l.online,
              onChanged: (v) => _update((l) => l.online = v),
            ),
            D4StepperRow(
              title: 'Open booking',
              sub: 'How far ahead patients can book',
              value: '${l.ahead} ${l.ahead == 1 ? 'day' : 'days'}',
              onMinus: () => _update((l) => l.ahead = math.max(1, l.ahead - 1)),
              onPlus: () => _update((l) => l.ahead = math.min(60, l.ahead + 1)),
            ),
            D4StepperRow(
              title: 'Cancel or reschedule',
              sub: 'Allowed until this long before',
              value: '${l.cancel} ${l.cancel == 1 ? 'hr' : 'hrs'}',
              onMinus: () => _update((l) => l.cancel = math.max(1, l.cancel - 1)),
              onPlus: () => _update((l) => l.cancel = math.min(48, l.cancel + 1)),
            ),
            D4SwitchRow(
              title: 'Approve each booking',
              sub: 'Front desk confirms before it’s final',
              value: l.approve,
              onChanged: (v) => _update((l) => l.approve = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _leaveCard() {
    return D4Card(
      children: [
        D4CardTitle('Leave and holidays', action: 'Add leave', onAction: _addLeave),
        for (final (name, detail) in _leave)
          Row(
            children: [
              Expanded(child: D4TitleSub(name, detail)),
              const SizedBox(width: 12),
              const D4Pill.blue('Planned'),
            ],
          ),
      ],
    );
  }
}

/// Hours pill: 34px + 1px border, padding 0 12, radius 10, #F7F9FC, 14/600.
class _HoursPill extends StatelessWidget {
  final String text;
  const _HoursPill(this.text);

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: MP.bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: MP.line),
    ),
    child: Center(widthFactor: 1, child: Text(text, style: tx(14, w: w600, tab: true))),
  );
}

/// Preview slot: 34px + 1px border, radius 10, 13/600 tabular. Walk-in places
/// are grey (#F1F4F9 on #E5E9F0, #69738A text).
class _SlotCell extends StatelessWidget {
  final String time;
  final bool walkIn;
  const _SlotCell(this.time, {required this.walkIn});

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: walkIn ? MP.fill : MP.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: walkIn ? MP.line : MP.lineStrong),
    ),
    child: Text(time, style: tx(13, w: w600, tab: true, c: walkIn ? MP.ink3 : MP.ink)),
  );
}

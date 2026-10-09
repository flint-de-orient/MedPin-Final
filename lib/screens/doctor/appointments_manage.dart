import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Appointments-Manage.dc.html — "Appointments · manage" (sheet over
/// 'Appointments'). The optional parameters default to the design's
/// appointment (Rahul Das, 9:30 AM); the Appointments screen passes the
/// tapped row, or a waiting request with [assign] = true.
///
/// Pops with `(action: 'reschedule' | 'assign' | 'cancel', day:, time:)`.
class AppointmentsManageSheet extends StatefulWidget {
  const AppointmentsManageSheet({
    super.key,
    this.name = 'Rahul Das',
    this.time = '9:30 AM',
    this.doctor = 'Dr. Sen',
    this.when = 'Today, Tue 29 Sep · City Care Clinic — Salt Lake',
    this.assign = false,
  });

  final String name;
  final String time;
  final String doctor;

  /// Second detail line under the patient (date and location, or the request).
  final String when;

  /// Give a waiting request its first slot instead of rescheduling.
  final bool assign;

  @override
  State<AppointmentsManageSheet> createState() => _AppointmentsManageSheetState();
}

class _AppointmentsManageSheetState extends State<AppointmentsManageSheet> {
  /// Chip label, long label (renderVals().dates).
  static const _dates = [
    ('Wed 30', 'Wed 30 Sep'),
    ('Thu 1 Oct', 'Thu 1 Oct'),
    ('Fri 2 Oct', 'Fri 2 Oct'),
    ('Sat 3 Oct', 'Sat 3 Oct'),
  ];

  static const _times = [
    '9:00 AM', '9:15 AM', '9:30 AM', //
    '9:45 AM', '10:00 AM', '10:15 AM',
    '10:30 AM', '10:45 AM', '11:00 AM',
  ];

  /// Already-booked slots per date; Wed 30 is the design's.
  static const _taken = [
    {'9:00 AM', '9:30 AM', '10:15 AM', '11:00 AM'},
    {'9:15 AM', '10:00 AM', '10:45 AM'},
    {'9:00 AM', '9:45 AM', '10:30 AM', '11:00 AM'},
    {'9:30 AM', '10:00 AM'},
  ];

  int _date = 0;
  String? _slot = '10:00 AM';

  void _pickDate(int i) {
    if (i == _date) return;
    setState(() {
      _date = i;
      if (_slot != null && _taken[i].contains(_slot)) _slot = null;
    });
  }

  void _confirm() {
    final slot = _slot;
    if (slot == null) {
      toast(context, 'Choose a time first');
      return;
    }
    final day = _dates[_date].$2;
    toast(context, widget.assign ? 'Booked for $day, $slot' : 'Rescheduled to $day, $slot');
    Navigator.pop(context, (action: widget.assign ? 'assign' : 'reschedule', day: day, time: slot));
  }

  void _cancel() {
    toast(context, 'Appointment cancelled');
    Navigator.pop(context, (action: 'cancel', day: '', time: ''));
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.name.split(' ').first;
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.assign ? 'Assign a time' : 'Manage appointment', style: tx(20, w: w700, h: 1.25)),
                      const SizedBox(height: 4),
                      Text(
                        widget.assign
                            ? '${widget.name} · ${widget.doctor}'
                            : '${widget.name} · ${widget.time} · ${widget.doctor}',
                        style: tx(16, w: w600),
                      ),
                      const SizedBox(height: 4),
                      Text(widget.when, style: tx(14, c: MP.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 44×44 with CSS margin -8px -8px 0 0: takes 36×36 in the row
                // and reaches 8px up and 8px right.
                SizedBox(
                  width: 36,
                  height: 36,
                  child: OverflowBox(
                    alignment: Alignment.bottomLeft,
                    minWidth: 44,
                    maxWidth: 44,
                    minHeight: 44,
                    maxHeight: 44,
                    child: MpIconButton(I.close, label: 'Close', color: MP.ink2, onTap: () => Navigator.pop(context)),
                  ),
                ),
              ],
            ),
          ),

          // New date
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(widget.assign ? 'Date' : 'New date', style: tx(14, w: w600)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < _dates.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  D7Pill(_dates[i].$1, on: _date == i, borderOn: false, onTap: () => _pickDate(i)),
                ],
              ],
            ),
          ),

          // Time
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Time · ${_dates[_date].$2}', style: tx(14, w: w600)),
                const SizedBox(height: 8),
                for (var r = 0; r < _times.length; r += 3) ...[
                  if (r > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var c = 0; c < 3; c++) ...[
                        if (c > 0) const SizedBox(width: 8),
                        Expanded(child: _slotCell(_times[r + c])),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text('Crossed-out times are already booked.', style: tx(13, c: MP.ink3)),
                const SizedBox(height: 24),
                MpButton(widget.assign ? 'Assign time' : 'Reschedule', onTap: _confirm),
                if (!widget.assign) ...[
                  const SizedBox(height: 12),
                  MpButton.small('Cancel appointment', kind: MpBtn.dangerSoft, onTap: _cancel),
                  Text(
                    '$first will be notified and the slot opens for others.',
                    textAlign: TextAlign.center,
                    style: tx(13, c: MP.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotCell(String t) {
    final taken = _taken[_date].contains(t);
    final selected = !taken && _slot == t;
    final bg =
        selected
            ? MP.primarySoft
            : taken
            ? MP.fill
            : MP.white;
    final fg =
        selected
            ? MP.primary
            : taken
            ? MP.ink3
            : MP.ink;
    final border =
        selected ? Border.all(color: MP.primary, width: 2) : Border.all(color: taken ? MP.fill : MP.lineStrong);
    return Semantics(
      button: true,
      selected: selected,
      enabled: !taken,
      excludeSemantics: true,
      label:
          '$t${taken
              ? ', already booked'
              : selected
              ? ', selected'
              : ''}',
      child: Tap(
        onTap: taken ? null : () => setState(() => _slot = t),
        radius: 12,
        color: bg,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: border),
          child: Text(
            t,
            maxLines: 1,
            style: tx(15, w: selected ? w700 : w500, c: fg, tab: true, deco: taken ? TextDecoration.lineThrough : null),
          ),
        ),
      ),
    );
  }
}

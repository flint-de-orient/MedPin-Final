import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';

/// Design: Staff-Today.dc.html — "Today" (front desk).
class StaffTodayScreen extends StatefulWidget {
  const StaffTodayScreen({super.key});

  @override
  State<StaffTodayScreen> createState() => _StaffTodayScreenState();
}

/// The canvas sets `line-height: 1.4` on the page; text without its own
/// line height inherits it.
const _lh = 1.4;

/// Status pill colours (bg, fg).
const _statusColors = <String, (Color, Color)>{
  'In consult': (MP.primarySoft, MP.primary),
  'Waiting': (MP.amberSoft, MP.amber),
  'Upcoming': (MP.fill, MP.ink2),
  'Done': (MP.greenSoft, MP.green),
};

/// (name, detail, meta)
const _requests = [
  ('Debasish Bose', 'Follow-up with Dr. Sen', 'Asked 8:20 AM · app'),
  ('Farhana Islam', 'New visit with Dr. Sen', 'Asked yesterday · WhatsApp'),
];

/// (time, name, status, doctor)
const _appts = [
  ('8:30', 'Amit Pal', 'Done', 'Dr. Sen'),
  ('9:00', 'Priya Sharma', 'In consult', 'Dr. Sen'),
  ('9:30', 'Rahul Das', 'Waiting', 'Dr. Sen'),
  ('10:00', 'Aisha Khan', 'Waiting', 'Dr. Sen'),
  ('10:30', 'Sujit Mondal', 'Upcoming', 'Dr. Sen'),
  ('11:00', 'Moumita Roy', 'Upcoming', 'Dr. Mitra'),
];

/// (icon, label, stem)
const _actions = [
  (I.userPlus, 'Register walk-in', 'Add-Patient'),
  (I.activity, 'Record vitals', 'Consult-Vitals'),
  (I.calendar, 'Book appointment', 'Appointments'),
];

class _StaffTodayScreenState extends State<StaffTodayScreen> {
  late final List<String> _status = [for (final a in _appts) a.$3];
  int _checkedIn = 7;

  void _checkIn(int i) {
    setState(() {
      _status[i] = 'Waiting';
      _checkedIn++;
    });
    toast(context, '${_appts[i].$2} checked in');
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      nav: const StaffNav(current: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D10StaffHeader(bellLabel: 'Notifications, 3 new', dot: MP.primary),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              // Greeting
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good morning, Tania', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                    const Gap(6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle),
                        ),
                        const Gap(8),
                        Flexible(
                          child: Text('Tue, 29 Sep 2026 · Updated 4s ago', style: tx(14, c: MP.ink2, h: _lh)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _requestsCard(context),
              Row(
                children: [
                  for (var i = 0; i < _actions.length; i++) ...[
                    if (i > 0) const Gap(8),
                    Expanded(child: _ActionTile(_actions[i])),
                  ],
                ],
              ),
              _appointmentsCard(context),
              _summaryCard(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _requestsCard(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requests waiting for a time', style: tx(20, w: w700, h: 1.25)),
                const Gap(2),
                Text('2 patients asked for a visit, no slot yet', style: tx(14, c: MP.ink2, h: _lh)),
              ],
            ),
          ),
          for (final r in _requests)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Tap(
                      onTap: () => Nav.go(context, 'Patient-Profile-Desk'),
                      radius: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _line(r.$1, tx(16, w: w600, h: _lh)),
                          const Gap(2),
                          _line(r.$2, tx(14, c: MP.ink2, h: _lh)),
                          const Gap(2),
                          _line(r.$3, tx(13, c: MP.ink3, h: _lh)),
                        ],
                      ),
                    ),
                  ),
                  const Gap(12),
                  MpButton.small(
                    'Assign time',
                    expand: false,
                    onTap: () => Nav.go(context, 'Appointments-Manage'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _appointmentsCard(BuildContext context) {
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Today's appointments", style: tx(20, w: w700, h: 1.25)),
                      const Gap(2),
                      Text('18 booked · Dr. Sen and Dr. Mitra', style: tx(14, c: MP.ink2, h: _lh)),
                    ],
                  ),
                ),
                Tap(
                  onTap: () => Nav.go(context, 'Appointments'),
                  radius: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('View all', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _appts.length; i++) _apptRow(context, i),
        ],
      ),
    );
  }

  Widget _apptRow(BuildContext context, int i) {
    final a = _appts[i];
    final status = _status[i];
    final (bg, fg) = _statusColors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Row(
        children: [
          Expanded(
            child: Tap(
              onTap: () => Nav.go(context, 'Patient-Profile-Desk'),
              radius: 8,
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text(a.$1, style: tx(15, w: w600, tab: true, h: _lh))),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _line(a.$2, tx(16, w: w600, h: _lh)),
                        const Gap(4),
                        Row(
                          children: [
                            Container(
                              height: 22,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [Text(status, style: tx(12, w: w600, c: fg, h: 1))],
                              ),
                            ),
                            const Gap(8),
                            Flexible(child: _line(a.$4, tx(13, c: MP.ink3, h: _lh))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (status == 'Upcoming') ...[
            const Gap(12),
            Semantics(
              label: 'Check in ${a.$2}',
              button: true,
              excludeSemantics: true,
              child: MpButton.small('Check in', expand: false, onTap: () => _checkIn(i)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final summary = [('18', 'Booked'), ('$_checkedIn', 'Checked in'), ('5', 'Done'), ('1', 'Missed appointments')];
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Day summary', style: tx(20, w: w700, h: 1.25)),
          const Gap(16),
          MpGrid(
            columns: 2,
            gap: 8,
            children: [
              for (final s in summary)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                      const Gap(6),
                      Text(s.$2, style: tx(14, c: MP.ink2, h: _lh)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _line(String text, TextStyle style) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}

/// Quick action: 84px tile, radius 12, 1px #E5E9F0, padding 14/12, icon on
/// top and the label at the bottom (space-between).
class _ActionTile extends StatelessWidget {
  final (String, String, String) a;
  const _ActionTile(this.a);

  @override
  Widget build(BuildContext context) {
    // height 84 is border-box; Tap insets the content by the 1px border.
    return SizedBox(
      height: 84,
      child: Tap(
        onTap: () => Nav.go(context, a.$3),
        radius: 12,
        color: MP.white,
        border: MP.line,
        shadow: MPShadow.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Ico(a.$1, size: 22, color: MP.primary),
              Flexible(child: _TileLabel(a.$2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 14/600/1.25 label laid out like CSS: two lines may run 3px into the
/// tile's bottom padding, and a word wider than the box overflows it
/// instead of being split mid-word.
class _TileLabel extends StatelessWidget {
  final String text;
  const _TileLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final style = tx(14, w: w600, h: 1.25);
    final label = Text(text, style: style, overflow: TextOverflow.visible);
    return LayoutBuilder(
      builder: (context, c) {
        final scaler = MediaQuery.textScalerOf(context);
        // Measure with the style Text actually paints with (inherited
        // DefaultTextStyle merged in).
        final effective = DefaultTextStyle.of(context).style.merge(style);
        var longest = 0.0;
        for (final word in text.split(' ')) {
          final tp = TextPainter(
            text: TextSpan(text: word, style: effective),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          if (tp.width > longest) longest = tp.width;
          tp.dispose();
        }
        if (longest <= c.maxWidth) return label;
        return OverflowBox(
          alignment: Alignment.topLeft,
          fit: OverflowBoxFit.deferToChild,
          minWidth: 0,
          maxWidth: longest.ceilToDouble(),
          minHeight: 0,
          maxHeight: double.infinity,
          child: label,
        );
      },
    );
  }
}

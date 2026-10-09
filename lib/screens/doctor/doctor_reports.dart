import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Doctor-Reports.dc.html — "Doctor · Reports (consultation MIS)".
class DoctorReportsScreen extends StatefulWidget {
  const DoctorReportsScreen({super.key});

  @override
  State<DoctorReportsScreen> createState() => _DoctorReportsScreenState();
}

const _up = MP.green;
const _down = MP.red;
const _flat = MP.ink2;

// (label, value, delta, delta colour, drill-down stem)
const _kpis = [
  ('Consultations', '286', '+12% vs August', _up, 'Report-Consultations'),
  ('New patients', '64', '+9 vs August', _up, 'Report-Consultations'),
  ('Avg. consult time', '11 min', 'Same as August', _flat, 'Report-Consultations'),
  ('Missed appointments', '21', 'Booked, didn’t come · 7%', _down, 'Doctor-History'),
  ('Prescriptions', '271', '95% of consultations', _flat, 'Report-Prescriptions'),
  ('Fees collected', '₹1.57L', '+10% vs August', _up, 'Report-Fees'),
];

const _total = 286;

// (title, note, rows of (label, count))
const _splits = [
  (
    'By location',
    '286 total',
    [('City Care · Salt Lake', 168), ('City Care · New Town', 84), ('Sen Diabetes Chamber · Gariahat', 34)],
  ),
  ('By visit type', '286 total', [('Follow-up', 196), ('New patient', 64), ('Report review', 26)]),
  (
    'Top diagnoses',
    'Share of consultations',
    [('Type 2 diabetes', 92), ('Hypertension', 58), ('Hypothyroidism', 31), ('Fever, cough', 27), ('Anaemia', 14)],
  ),
];

// (title, sub, stem)
const _detail = [
  ('Consultation register', 'Every visit with patient, diagnosis and time', 'Report-Consultations'),
  ('Prescription register', 'Medicines and tests you prescribed', 'Report-Prescriptions'),
  ('Fees and collections', 'By location, mode and payment method', 'Report-Fees'),
  ('Follow-up compliance', '72% came back on time · who missed', 'Report-FollowUps'),
  ('Referrals', 'Sent to and received from other doctors', 'Report-Referrals'),
];

int _pct(int n) => (n / _total * 100).round();

class _DoctorReportsScreenState extends State<DoctorReportsScreen> {
  static const _ranges = ['Today', '7 days', '30 days', 'Custom'];
  int _range = 2;

  void _filters() => Nav.go(context, 'Doctor-Reports-Filter');

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: _header(),
      nav: const DoctorNav(current: 3),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        gap: 16,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('1 – 30 Sep 2026 · compared with 1 – 31 Aug', style: tx(13, c: MP.ink2)),
          ),

          // Key numbers
          MpGrid(columns: 2, gap: 8, children: [for (final k in _kpis) _kpi(k)]),

          // Consultations per day
          const _DailyCard(),

          // Splits
          for (final g in _splits)
            D3BarCard(
              title: g.$1,
              note: g.$2,
              rows: [for (final r in g.$3) D3BarRow(r.$1, '${r.$2}', _pct(r.$2) / 100, suffix: '· ${_pct(r.$2)}%')],
            ),

          // Detailed reports
          VGap(
            gap: 12,
            children: [
              const D3SectionHead('Detailed reports', padding: EdgeInsets.symmetric(horizontal: 4)),
              D3ListCard(shadow: false, children: [for (final d in _detail) _detailRow(d)]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: VGap(
        gap: 14,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Reports', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                    const SizedBox(height: 2),
                    Text('Your consultation MIS', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: Tap(
                  onTap: () => Nav.go(context, 'Report-Download'),
                  radius: 12,
                  color: MP.white,
                  border: MP.lineStrong,
                  padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.downloadAlt, size: 18, color: MP.ink),
                      const SizedBox(width: 6),
                      Text('Export', style: tx(14, w: w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          D3Tabs(
            options: _ranges,
            index: _range,
            onChanged: (i) {
              setState(() => _range = i);
              if (i == 3) _filters();
            },
          ),
          Row(
            children: [
              SizedBox(
                height: 36,
                child: Tap(
                  onTap: _filters,
                  radius: 999,
                  color: MP.primarySoft,
                  border: MP.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.filter, size: 16, color: MP.primary, stroke: 2),
                      const SizedBox(width: 6),
                      Text('Filters', style: tx(14, w: w600, c: MP.primary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // A <span> with height 36 + 1px border (content-box) → 38px tall.
              GestureDetector(
                onTap: _filters,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MP.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MP.lineStrong),
                  ),
                  child: Text('All locations', maxLines: 1, softWrap: false, style: tx(14, w: w500)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi((String, String, String, Color, String) k) => MpCard(
    onTap: () => Nav.go(context, k.$5),
    radius: 20,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k.$1, style: tx(13, c: MP.ink2)),
        const SizedBox(height: 6),
        Text(k.$2, style: tx(26, w: w800, h: 1.1, em: -0.02, tab: true)),
        const SizedBox(height: 6),
        Text(k.$3, style: tx(12, w: w600, c: k.$4)),
      ],
    ),
  );

  Widget _detailRow((String, String, String) d) => Tap(
    onTap: () => Nav.go(context, d.$3),
    radius: 0,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.$1, style: tx(15, w: w600)),
              const SizedBox(height: 2),
              Text(d.$2, style: tx(13, c: MP.ink2)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
      ],
    ),
  );
}

/// "Consultations per day" bar chart. Tap or drag across the bars to move
/// the highlight and the tooltip (design state: Mon, 28 Sep).
class _DailyCard extends StatefulWidget {
  const _DailyCard();

  @override
  State<_DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends State<_DailyCard> {
  static const _vals = [
    10,
    12,
    12,
    9,
    13,
    0,
    12,
    10,
    11,
    13,
    8,
    12,
    0,
    13,
    9,
    10,
    12,
    9,
    11,
    0,
    12,
    10,
    11,
    13,
    8,
    11,
    0,
    14,
    10,
    11,
  ];

  // 1 Sep 2026 is a Tuesday.
  static const _week = ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon'];
  static const _plotH = 132.0;
  static const _gap = 3.0;

  int _sel = 27;

  void _pick(double dx, double w) {
    final step = (w + _gap) / _vals.length;
    final i = (dx / step).floor().clamp(0, _vals.length - 1);
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    return MpCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Consultations per day', style: tx(17, w: w700))),
              const SizedBox(width: 8),
              D3TextLink('Table', onTap: () => Nav.go(context, 'Report-Consultations')),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label:
                      'Daily consultations, 1 to 30 September. Highest 14 on Monday 28 September. Closed on Sundays.',
                  child: SizedBox(height: _plotH, child: LayoutBuilder(builder: (context, box) => _plot(box.maxWidth))),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final t in const ['1 Sep', '8', '15', '22', '30 Sep']) Text(t, style: tx(11, c: MP.ink3)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Busiest on Mondays and Thursdays. Closed on Sundays.', style: tx(13, h: 1.45, c: MP.ink2)),
        ],
      ),
    );
  }

  Widget _plot(double w) {
    final n = _vals.length;
    final bw = (w - _gap * (n - 1)) / n;
    // Tooltip box spans from the axis-label column (-24) to 6px past the plot.
    final anchor = 24 + _sel * (bw + _gap) + bw / 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _pick(d.localPosition.dx, w),
      onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, w),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: _vals[i] == 0 ? 2 : (_vals[i] / 14 * _plotH).roundToDouble(),
                      decoration: BoxDecoration(
                        color: _vals[i] == 0 ? MP.lineStrong : (i == _sel ? MP.primary : MP.primaryMid),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Y axis: 14 / 7 / 0 — 11px labels (13px line box) in a 132px
          // space-between column with -6px end margins.
          for (final (label, top) in const [('14', -6.0), ('7', 59.5), ('0', 125.0)])
            Positioned(left: -24, top: top, child: Text(label, style: tx(11, c: MP.ink3, tab: true))),
          Positioned(
            left: -24,
            right: -6,
            top: -54,
            height: 54,
            child: IgnorePointer(child: CustomSingleChildLayout(delegate: _TipLayout(anchor), child: _tip())),
          ),
        ],
      ),
    );
  }

  Widget _tip() {
    final v = _vals[_sel];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: MP.ink, borderRadius: BorderRadius.circular(12), boxShadow: MPShadow.float),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_week[_sel % 7]}, ${_sel + 1} Sep', style: tx(11, c: MP.white.withValues(alpha: 0.72))),
          const SizedBox(height: 1),
          Text(v == 0 ? 'Closed' : '$v consultations', style: tx(13, w: w700, c: MP.white)),
        ],
      ),
    );
  }
}

/// Centres the tooltip over the selected bar, clamped so it never passes the
/// box edges (for the last bars this gives the design's `right: -6px`).
class _TipLayout extends SingleChildLayoutDelegate {
  final double anchor;
  const _TipLayout(this.anchor);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: constraints.maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(0.0, size.width - childSize.width);
    return Offset((anchor - childSize.width / 2).clamp(0.0, maxX), 0);
  }

  @override
  bool shouldRelayout(_TipLayout oldDelegate) => oldDelegate.anchor != anchor;
}

/// Dashed 1px #E5E9F0 lines at 0 and 66px, solid 1px #D5DBE5 baseline.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dash =
        Paint()
          ..color = MP.line
          ..strokeWidth = 1;
    for (final y in const [0.5, 66.5]) {
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), dash);
      }
    }
    final base =
        Paint()
          ..color = MP.lineStrong
          ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), base);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

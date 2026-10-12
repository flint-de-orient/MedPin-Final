import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-Reports.dc.html — "Doctor · Reports (consultation MIS)".
/// Live data: GET /api/reports/summary (range + filters) and /api/locations.
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

int _pctOf(int n, int total) => total == 0 ? 0 : (n / total * 100).round();

class _DoctorReportsScreenState extends State<DoctorReportsScreen> with LiveData {
  static const _ranges = ['Today', '7 days', '30 days', 'Custom'];
  int _range = 2;

  /// Live filter state (the filter sheet returns a new one).
  D3Filters _f = const D3Filters();

  static int _tabOf(String range) => switch (range) {
    'today' => 0,
    '7_days' => 1,
    '30_days' => 2,
    _ => 3,
  };

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/reports/summary', query: _f.query),
      Api.I.get('/api/locations'),
    ]);
    return {'summary': r[0], 'locations': (r[1] as Map?)?['items'] ?? const []};
  }

  Future<void> _filters() async {
    if (!isLive) {
      Nav.go(context, 'Doctor-Reports-Filter');
      return;
    }
    final f = await Nav.go<D3Filters>(context, 'Doctor-Reports-Filter', args: {'filters': _f});
    if (!mounted) return;
    if (f == null) {
      setState(() => _range = _tabOf(_f.range));
      return;
    }
    setState(() {
      _f = f;
      _range = _tabOf(f.range);
    });
    reload();
  }

  void _pickRange(int i) {
    setState(() => _range = i);
    if (i == 3) {
      _filters();
      return;
    }
    if (!isLive) return;
    _f = _f.copyWith(range: const ['today', '7_days', '30_days'][i]);
    reload();
  }

  Map<String, dynamic> get _s => data!.obj('summary');
  Map<String, dynamic> get _k => _s.obj('kpis');
  int get _total => data == null ? 286 : _k.obj('consultations').numOr('value').toInt();

  /// "+12% vs August", "Same as August", "−3 vs previous 7 days".
  (String, Color) _delta(num? change, {String unit = '', bool pct = false, bool tone = true}) {
    if (!_f.compare || change == null) return ('', _flat);
    final vs = _f.previousName;
    if (change == 0) return (vs == 'yesterday' ? 'Same as yesterday' : 'Same as $vs', _flat);
    final sign = change > 0 ? '+' : '−';
    return ('$sign${F.count(change.abs())}${pct ? '%' : unit} vs $vs', !tone ? _flat : (change > 0 ? _up : _down));
  }

  List<(String, String, String, Color, String)> get _kpiRows {
    if (data == null) return _kpis;
    final k = _k;
    final c = k.obj('consultations');
    final cd = c['changePct'] is num
        ? _delta(c['changePct'] as num, pct: true)
        : _delta(c['previous'] is num ? c.numOr('value') - c.numOr('previous') : null);
    final n = k.obj('newPatients');
    final nd = _delta(n['change'] is num ? n['change'] as num : null);
    final a = k.obj('avgConsultMin');
    final ad = _delta(a['value'] is num && a['previous'] is num ? a.numOr('value') - a.numOr('previous') : null, unit: ' min', tone: false);
    final m = k.obj('missed');
    final p = k.obj('prescriptions');
    final fees = k.obj('feesCollected');
    final fd = fees['changePct'] is num
        ? _delta(fees['changePct'] as num, pct: true)
        : (fees['previous'] is num ? _delta(fees.numOr('value') - fees.numOr('previous')) : ('', _flat));
    return [
      ('Consultations', F.count(c.numOr('value')), cd.$1, cd.$2, 'Report-Consultations'),
      ('New patients', F.count(n.numOr('value')), nd.$1, nd.$2, 'Report-Consultations'),
      ('Avg. consult time', a['value'] is num ? '${a['value']} min' : '–', ad.$1, ad.$2, 'Report-Consultations'),
      (
        'Missed appointments',
        F.count(m.numOr('value')),
        'Booked, didn’t come · ${m.numOr('pct')}%',
        m.numOr('value') > 0 ? _down : _flat,
        'Doctor-History',
      ),
      ('Prescriptions', F.count(p.numOr('value')), '${p.numOr('pctOfConsultations')}% of consultations', _flat, 'Report-Prescriptions'),
      ('Fees collected', d3RupeesShort(fees.numOr('value')), fd.$1, fd.$2, 'Report-Fees'),
    ];
  }

  List<Map<String, dynamic>> get _locations => data == null ? const [] : data!.list('locations');

  String _locationLabel(String key) {
    for (final l in _locations) {
      if (l['shortName'] == key || l['name'] == key || l['id'] == key) return d3LocationName(l);
    }
    return key == 'other' ? 'Other' : key;
  }

  List<(String, String, List<(String, int)>)> get _splitRows {
    if (data == null) return _splits;
    final s = _s;
    final total = '${F.count(_total)} total';
    List<(String, int)> rows(String k, String Function(String) label, [int max = 8]) => [
      for (final r in s.list(k).take(max)) (label(r.str('key')), r.numOr('count').toInt()),
    ];
    return [
      ('By location', total, rows('byLocation', _locationLabel)),
      ('By visit type', total, rows('byVisitType', d3VisitType)),
      ('Top diagnoses', 'Share of consultations', rows('topDiagnoses', (k) => k, 5)),
    ];
  }

  List<(String, String, String)> get _detailRows {
    if (data == null) return _detail;
    final pct = _s['followUpCompliancePct'];
    return [
      for (final d in _detail)
        if (d.$3 == 'Report-FollowUps')
          (d.$1, pct is num ? '$pct% came back on time · who missed' : 'Who came back on time · who missed', d.$3)
        else
          d,
    ];
  }

  /// Weekdays (1 = Mon) on which no chosen location is open.
  Set<int> get _closedWeekdays {
    const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final locs = _locations.where((l) => l['status'] == 'active' && (_f.locationIds.isEmpty || _f.locationIds.contains(l['id']))).toList();
    if (locs.isEmpty) return const {};
    return {
      for (var i = 0; i < 7; i++)
        if (!locs.any((l) => l.list('weeklyHours').any((h) => h['weekday'] == keys[i] && h['isOpen'] == true))) i + 1,
    };
  }

  String get _dateLine => data == null ? '1 – 30 Sep 2026 · compared with 1 – 31 Aug' : _f.longLabel;

  void _open(String stem) {
    if (!isLive) {
      Nav.go(context, stem);
      return;
    }
    Nav.go(context, stem, args: stem == 'Doctor-History' ? null : {'filters': _f});
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: _header(),
      nav: const DoctorNav(current: 3),
      body:
          placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            gap: 16,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_dateLine, style: tx(13, c: MP.ink2)),
              ),

              // Key numbers
              MpGrid(columns: 2, gap: 8, children: [for (final k in _kpiRows) _kpi(k)]),

              // Consultations per day
              data == null
                  ? const _DailyCard()
                  : _DailyCard(
                    key: ValueKey(_f.query.toString()),
                    days: [
                      for (final d in _s.list('perDay'))
                        if (d3Day(d['date']) != null) (d3Day(d['date'])!, d.numOr('count').toInt()),
                    ],
                    closed: _closedWeekdays,
                    onTable: () => _open('Report-Consultations'),
                  ),

              // Splits
              for (final g in _splitRows)
                if (g.$3.isNotEmpty)
                  D3BarCard(
                    title: g.$1,
                    note: g.$2,
                    rows: [
                      for (final r in g.$3)
                        D3BarRow(
                          r.$1,
                          F.count(r.$2),
                          _pctOf(r.$2, _total) / 100,
                          suffix: '· ${_pctOf(r.$2, _total)}%',
                        ),
                    ],
                  ),

              // Detailed reports
              VGap(
                gap: 12,
                children: [
                  const D3SectionHead('Detailed reports', padding: EdgeInsets.symmetric(horizontal: 4)),
                  D3ListCard(shadow: false, children: [for (final d in _detailRows) _detailRow(d)]),
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
                  onTap: () => Nav.go(context, 'Report-Download', args: isLive ? _f.downloadArgs('consultations') : null),
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
            onChanged: _pickRange,
          ),
          Row(
            children: [
              SizedBox(
                height: 36,
                child: MpHitSlop(child: Tap(
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
                )),
              ),
              const SizedBox(width: 8),
              // A <span> with height 36 + 1px border (content-box) → 38px tall.
              MpHitSlop(child: GestureDetector(
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
                  child: Text(_f.locationLabel, maxLines: 1, softWrap: false, style: tx(14, w: w500)),
                ),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi((String, String, String, Color, String) k) => MpCard(
    onTap: () => _open(k.$5),
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
    onTap: () => _open(d.$3),
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
  /// Live: (IST day, completed consultations) for every day of the period.
  final List<(DateTime, int)>? days;

  /// Live: weekdays (1 = Mon) when no chosen location is open.
  final Set<int> closed;
  final VoidCallback? onTable;
  const _DailyCard({super.key, this.days, this.closed = const {}, this.onTable});

  @override
  State<_DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends State<_DailyCard> {
  List<int> get _vals => widget.days == null ? _sample : [for (final d in widget.days!) d.$2];

  /// Top of the y axis: 14 in the design; live the busiest day, rounded up
  /// to an even number so the middle line is a whole number.
  int get _top {
    if (widget.days == null) return 14;
    final m = _vals.fold<int>(0, math.max);
    return math.max(2, m.isOdd ? m + 1 : m);
  }

  @override
  void initState() {
    super.initState();
    _selectBusiest();
  }

  /// New data (another period or a refresh): start on the busiest day again.
  @override
  void didUpdateWidget(_DailyCard old) {
    super.didUpdateWidget(old);
    if (old.days?.length != widget.days?.length || old.days?.firstOrNull?.$1 != widget.days?.firstOrNull?.$1) _selectBusiest();
  }

  void _selectBusiest() {
    final v = _vals;
    if (widget.days != null && v.isNotEmpty) {
      final m = v.fold<int>(0, math.max);
      _sel = v.lastIndexOf(m);
    }
  }

  /// The highlighted day, always inside the data (a 1-day period has one bar).
  int get _at => _vals.isEmpty ? 0 : _sel.clamp(0, _vals.length - 1);

  bool _isClosed(int i) => widget.days != null && widget.closed.contains(widget.days![i].$1.weekday);

  String _dayLabel(int i) => widget.days == null ? '${_week[i % 7]}, ${i + 1} Sep' : d3DayHead(widget.days![i].$1);

  /// x-axis labels: first, last and three in between ("1 Sep", "8", … "30 Sep").
  List<String> get _ticks {
    final days = widget.days;
    if (days == null) return const ['1 Sep', '8', '15', '22', '30 Sep'];
    if (days.isEmpty) return const [];
    final idx = <int>{for (var k = 0; k <= 4; k++) ((days.length - 1) * k / 4).round()}.toList()..sort();
    final out = <String>[];
    for (var j = 0; j < idx.length; j++) {
      final d = days[idx[j]].$1;
      final edge = j == 0 || j == idx.length - 1 || d.month != days[idx[j - 1]].$1.month;
      out.add(edge ? F.dayMonth(d) : '${d.day}');
    }
    return out;
  }

  String _plural(int weekday) => '${d3WeekdayLong(DateTime(2026, 9, 6 + weekday))}s';

  String get _closedText {
    final c = widget.closed.toList()..sort();
    if (c.isEmpty || (widget.days?.length ?? 0) < 7) return '';
    return 'Closed on ${F.joinAnd([for (final w in c) _plural(w)])}.';
  }

  String get _semantics {
    final days = widget.days;
    if (days == null) {
      return 'Daily consultations, 1 to 30 September. Highest 14 on Monday 28 September. Closed on Sundays.';
    }
    if (days.isEmpty) return 'Daily consultations';
    String long(DateTime d) => '${d.day} ${d3MonthLong(d)}';
    final m = _vals.fold<int>(0, math.max);
    final at = days[_vals.lastIndexOf(m)].$1;
    return [
      'Daily consultations, ${long(days.first.$1)} to ${long(days.last.$1)}.',
      if (m > 0) 'Highest $m on ${d3WeekdayLong(at)} ${long(at)}.',
      if (_closedText.isNotEmpty) _closedText,
    ].join(' ');
  }

  String get _footer {
    final days = widget.days;
    if (days == null) return 'Busiest on Mondays and Thursdays. Closed on Sundays.';
    final total = _vals.fold<int>(0, (s, v) => s + v);
    if (total == 0) return 'No consultations in this period.';
    String busiest;
    if (days.length < 7) {
      final m = _vals.fold<int>(0, math.max);
      busiest = 'Busiest on ${d3DayHead(days[_vals.lastIndexOf(m)].$1)}.';
    } else {
      final byDay = List.filled(8, 0);
      for (final d in days) {
        byDay[d.$1.weekday] += d.$2;
      }
      final m = byDay.fold<int>(0, math.max);
      final top = [for (var w = 1; w <= 7; w++) if (byDay[w] == m) w];
      busiest = top.length <= 2 ? 'Busiest on ${F.joinAnd([for (final w in top) _plural(w)])}.' : '';
    }
    return [busiest, _closedText].where((s) => s.isNotEmpty).join(' ');
  }

  static const _sample = [
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
              D3TextLink('Table', onTap: widget.onTable ?? () => Nav.go(context, 'Report-Consultations')),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: _semantics,
                  child: SizedBox(height: _plotH, child: LayoutBuilder(builder: (context, box) => _plot(box.maxWidth))),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final t in _ticks) Text(t, style: tx(11, c: MP.ink3)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(_footer, style: tx(13, h: 1.45, c: MP.ink2)),
        ],
      ),
    );
  }

  Widget _plot(double w) {
    final n = _vals.length;
    if (n == 0) return const SizedBox();
    final top = _top;
    final bw = (w - _gap * (n - 1)) / n;
    // Tooltip box spans from the axis-label column (-24) to 6px past the plot.
    final anchor = 24 + _at * (bw + _gap) + bw / 2;
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
                      height: _vals[i] == 0 ? 2 : (_vals[i] / top * _plotH).roundToDouble(),
                      decoration: BoxDecoration(
                        color: _vals[i] == 0 ? MP.lineStrong : (i == _at ? MP.primary : MP.primaryMid),
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
          for (final (label, y) in [('$top', -6.0), ('${top ~/ 2}', 59.5), ('0', 125.0)])
            Positioned(left: -24, top: y, child: Text(label, style: tx(11, c: MP.ink3, tab: true))),
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
    final v = _vals[_at];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: MP.ink, borderRadius: BorderRadius.circular(12), boxShadow: MPShadow.float),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dayLabel(_at), style: tx(11, c: MP.white.withValues(alpha: 0.72))),
          const SizedBox(height: 1),
          Text(
            widget.days == null
                ? (v == 0 ? 'Closed' : '$v consultations')
                : (v == 0 ? (_isClosed(_at) ? 'Closed' : 'No consultations') : d3Plural(v, 'consultation')),
            style: tx(13, w: w700, c: MP.white),
          ),
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

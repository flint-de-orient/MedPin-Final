import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: Cards-Analytics.dc.html — "Cards · analytics".
/// Live data: GET /api/dashboard/cards (heart rate flags, ECGs, LDL),
/// /api/dashboard (nutrition reviews due), /api/inbox/summaries?date=today
/// (chat summaries). The clinic snapshot trend, live activity feed and the
/// per-patient lists (heart rate, highest LDL, meal logs) have no endpoint
/// yet, so they are hidden live.
class CardsAnalyticsScreen extends StatefulWidget {
  const CardsAnalyticsScreen({super.key});

  @override
  State<CardsAnalyticsScreen> createState() => _CardsAnalyticsScreenState();
}

class _CardsAnalyticsScreenState extends State<CardsAnalyticsScreen> with LiveData {
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/dashboard/cards'),
      Api.I.get('/api/dashboard'),
      // Needs the "chats" permission; the card is hidden without it.
      Api.I.get('/api/inbox/summaries', query: {'date': 'today'}).catchError((Object e) => e is ApiException && e.status == 403 ? null : throw e),
    ]);
    return {'cards': r[0], 'dashboard': r[1], 'summaries': r[2]};
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final d = data;
    if (d == null) {
      return MpPage(
        body: placeholder ??
            const VGap(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
              gap: 16,
              children: [_HeartRate(), _Ecgs(), _Lipids(), _Snapshot(), _Chats(), _Activity(), _NutritionReviews()],
            ),
      );
    }
    final cards = d.obj('cards');
    final ecgTotal = cards.obj('ecg180d').values.fold<num>(0, (s, v) => s + (v is num ? v : 0));
    final hr = cards.numOr('heartRateFlags30d');
    final nutrition = d.obj('dashboard').obj('actionQueue').numOr('nutritionReviewsDue');
    return MpPage(
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        gap: 16,
        children: [
          if (hr > 0) _HeartRate(live: hr.toInt()),
          if (ecgTotal > 0) _Ecgs(live: cards),
          _Lipids(live: cards),
          if (d['summaries'] is Map) _Chats(live: d.obj('summaries')),
          if (nutrition > 0) _NutritionReviews(due: nutrition.toInt()),
        ],
      ),
    );
  }
}

// ─── B. Heart rate flags ─────────────────────────────────────────────────────

// (name, detail, bpm, direction)
const _hr = [
  ('Moumita Roy', '3 readings above 100 · today, 9:04 AM', '112', 'Above range'),
  ('Debasish Bose', '1 reading above 100 · Tue, 22 Sep', '104', 'Above range'),
  ('Aisha Khan', '2 readings below 50 · Sat, 19 Sep', '48', 'Below range'),
  ('Rahul Das', '1 reading below 50 · Fri, 11 Sep', '47', 'Below range'),
];

class _HeartRate extends StatelessWidget {
  /// Live: readings outside range (per-patient rows aren't in the API yet).
  final int? live;
  const _HeartRate({this.live});

  @override
  Widget build(BuildContext context) {
    if (live != null) {
      return D9Card(
        children: [
          const D9Head('Heart rate flags', sub: 'Last 30 days · outside 50–100 bpm', bottom: 12),
          Text('${D9Fmt.plural(live!, 'reading')} outside 50–100 bpm', style: tx(14, c: MP.ink2)),
        ],
      );
    }
    return D9Card(
      children: [
        const D9Head('Heart rate flags', sub: 'Last 30 days · outside 50–100 bpm', bottom: 12),
        for (final h in _hr)
          D9Row(
            onTap: () => Nav.go(context, 'PP-Summary'),
            child: Row(
              children: [
                Expanded(child: D9Lines(h.$1, sub: h.$2, clipTitle: false)),
                const Gap(12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: h.$3,
                        style: tx(16, w: w700, h: 22 / 16, tab: true),
                        children: [TextSpan(text: ' bpm', style: tx(13, w: w500, c: MP.ink3, h: 22 / 13))],
                      ),
                    ),
                    const Gap(2),
                    Text(h.$4, style: tx(12, w: w600, c: MP.amber, h: 16 / 12)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── B. Recent ECGs ──────────────────────────────────────────────────────────

// (label, count, swatch, inset ring)
const List<(String, String, Color, Color?)> _ecg = [
  ('Normal', '41', MP.green, null),
  ('Borderline', '12', MP.amberSoft, MP.amber),
  ('Abnormal', '6', MP.amber, null),
  ('Unread', '5', MP.lineStrong, null),
];

class _Ecgs extends StatelessWidget {
  /// Live: the /api/dashboard/cards response.
  final Map<String, dynamic>? live;
  const _Ecgs({this.live});

  @override
  Widget build(BuildContext context) {
    void openTests() => Nav.go(context, 'PP-Tests');
    final ecg = live?.obj('ecg180d');
    int n(String k) => ecg?.numOr(k).toInt() ?? 0;
    final total = n('normal') + n('borderline') + n('abnormal') + n('unread');
    final rows = ecg == null ? _ecg : [for (final e in _ecg) (e.$1, F.count(n(e.$1.toLowerCase())), e.$3, e.$4)];
    final unread = ecg == null ? 5 : n('unread');
    return D9Card(
      gap: 16,
      children: [
        D9Head('Recent ECGs', sub: 'Last 180 days', trailing: D9Link('View all', top: 3, onTap: openTests)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const D9Label('ECGs on file'),
            const Gap(4),
            ecg == null
                ? const D9Big('64', suffix: ' of 412 patients in caseload', suffixH: 30 / 16)
                : D9Big(
                    F.count(total),
                    suffix: ' of ${D9Fmt.plural(live!.numOr('patients'), 'patient')} in caseload',
                    suffixH: 30 / 16,
                  ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ecg == null
                ? const D9Bar([
                    D9Seg(41, MP.green),
                    D9Seg(12, MP.amberSoft, ring: MP.amber),
                    D9Seg(6, MP.amber),
                    D9Seg(5, MP.lineStrong),
                  ], label: 'Of 64 ECGs: 41 normal, 12 borderline, 6 abnormal, 5 unread')
                : D9Bar([
                    D9Seg(n('normal'), MP.green),
                    D9Seg(n('borderline'), MP.amberSoft, ring: MP.amber),
                    D9Seg(n('abnormal'), MP.amber),
                    D9Seg(n('unread'), MP.lineStrong),
                  ], label: 'Of ${D9Fmt.plural(total, 'ECG')}: ${n('normal')} normal, ${n('borderline')} borderline, ${n('abnormal')} abnormal, ${n('unread')} unread'),
            const Gap(12),
            MpGrid(
              columns: 2,
              gap: 24,
              rowGap: 8,
              children: [
                for (final e in rows)
                  Row(
                    children: [
                      D9Swatch(e.$3, ring: e.$4),
                      const Gap(8),
                      Expanded(child: Text(e.$1, style: tx(14, c: MP.ink2, h: 20 / 14))),
                      const Gap(8),
                      Text(e.$2, style: tx(14, w: w700, h: 20 / 14, tab: true)),
                    ],
                  ),
              ],
            ),
          ],
        ),
        if (unread > 0)
          D9Note(
            strong: F.count(unread),
            text: unread == 1 ? ' ECG waiting for your read' : ' ECGs waiting for your read',
            action: 'Read now',
            onAction: openTests,
          ),
      ],
    );
  }
}

// ─── B. Lipid control ────────────────────────────────────────────────────────

// (band, count, swatch, opacity, inset ring)
const List<(String, String, Color, double, Color?)> _ldl = [
  ('Below 100 mg/dL', '112', MP.green, 1, null),
  ('100–129 mg/dL', '44', MP.amberSoft, 1, MP.amber),
  ('130–159 mg/dL', '21', MP.amber, 0.6, null),
  ('160 mg/dL and above', '11', MP.amber, 1, null),
];

// (name, value, when)
const _ldlNamed = [('Debasish Bose', 'LDL 182 mg/dL', 'Wed, 12 Aug'), ('Moumita Roy', 'LDL 168 mg/dL', 'Fri, 25 Sep')];

class _Lipids extends StatelessWidget {
  /// Live: the /api/dashboard/cards response.
  final Map<String, dynamic>? live;
  const _Lipids({this.live});

  Widget _stat(String n, String label) => D9Tile(
    children: [
      Text(n, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
      Text(label, style: tx(14, c: MP.ink2, h: 20 / 14)),
    ],
  );

  /// Live card: each patient's latest LDL (the API doesn't limit it to 365
  /// days, so the subtitle doesn't claim a period).
  Widget _live(BuildContext context, Map<String, dynamic> l, int patients) {
    int n(String k) => l.numOr(k).toInt();
    final target = F.count(l.numOr('target', 100));
    const keys = ['under_100', '100_129', '130_159', '160_plus'];
    final with_ = n('withResult');
    return D9Card(
      gap: 16,
      children: [
        D9Head('Lipid control', sub: 'Latest result · LDL target <$target mg/dL'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.fileText, size: 16, color: MP.ink3)),
            const Gap(8),
            Expanded(
              child: Text('Read automatically from uploaded lab reports', style: tx(13, c: MP.ink2, h: 18 / 13)),
            ),
          ],
        ),
        MpGrid(
          columns: 2,
          gap: 8,
          children: [
            _stat(F.count(with_), 'with an LDL result, of ${F.count(patients)}'),
            _stat(F.count(n('under_100')), 'at target, below $target mg/dL'),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            D9Bar(
              [
                D9Seg(n('under_100'), MP.green),
                D9Seg(n('100_129'), MP.amberSoft, ring: MP.amber),
                D9Seg(n('130_159'), MP.amber, opacity: 0.6),
                D9Seg(n('160_plus'), MP.amber),
              ],
              label:
                  'Latest LDL of ${D9Fmt.plural(with_, 'patient')}: ${n('under_100')} below 100, ${n('100_129')} at 100 to 129, '
                  '${n('130_159')} at 130 to 159, ${n('160_plus')} at 160 or above',
            ),
            const Gap(12),
            VGap(
              gap: 8,
              children: [
                for (var i = 0; i < _ldl.length; i++)
                  Row(
                    children: [
                      D9Swatch(_ldl[i].$3, opacity: _ldl[i].$4, ring: _ldl[i].$5),
                      const Gap(8),
                      Expanded(child: Text(_ldl[i].$1, style: tx(14, c: MP.ink2, h: 20 / 14, tab: true))),
                      const Gap(8),
                      Text(F.count(n(keys[i])), style: tx(14, w: w700, h: 20 / 14, tab: true)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = live?.obj('ldl');
    if (l != null) return _live(context, l, live!.numOr('patients').toInt());
    return D9Card(
      gap: 16,
      children: [
        const D9Head('Lipid control', sub: 'Last 365 days · LDL target <100 mg/dL'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.fileText, size: 16, color: MP.ink3)),
            const Gap(8),
            Expanded(
              child: Text('Read automatically from uploaded lab reports', style: tx(13, c: MP.ink2, h: 18 / 13)),
            ),
          ],
        ),
        MpGrid(
          columns: 2,
          gap: 8,
          children: [_stat('188', 'with an LDL result, of 412'), _stat('112', 'at target, below 100 mg/dL')],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const D9Bar(
              [
                D9Seg(112, MP.green),
                D9Seg(44, MP.amberSoft, ring: MP.amber),
                D9Seg(21, MP.amber, opacity: 0.6),
                D9Seg(11, MP.amber),
              ],
              label:
                  'Latest LDL of 188 patients: 112 below 100, 44 at 100 to 129, 21 at 130 to 159, 11 at 160 or above',
            ),
            const Gap(12),
            VGap(
              gap: 8,
              children: [
                for (final l in _ldl)
                  Row(
                    children: [
                      D9Swatch(l.$3, opacity: l.$4, ring: l.$5),
                      const Gap(8),
                      Expanded(child: Text(l.$1, style: tx(14, c: MP.ink2, h: 20 / 14, tab: true))),
                      const Gap(8),
                      Text(l.$2, style: tx(14, w: w700, h: 20 / 14, tab: true)),
                    ],
                  ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const D9Label('Highest LDL', padding: EdgeInsets.only(bottom: 8)),
            for (final p in _ldlNamed)
              D9Row(
                onTap: () => Nav.go(context, 'PP-Summary'),
                child: Row(
                  children: [
                    Expanded(
                      child: D9Lines(
                        p.$1,
                        clipTitle: false,
                        subSpans: [
                          TextSpan(text: p.$2, style: tx(14, w: w600, c: MP.amber, h: 20 / 14, tab: true)),
                          TextSpan(text: ' · ${p.$3}'),
                        ],
                      ),
                    ),
                    const Gap(12),
                    const D9Chevron(),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── C. Clinic snapshot ──────────────────────────────────────────────────────

class _Snapshot extends StatefulWidget {
  const _Snapshot();

  @override
  State<_Snapshot> createState() => _SnapshotState();
}

class _SnapshotState extends State<_Snapshot> {
  static const _ranges = ['7 days', '14 days', '30 days', '90 days'];
  int _range = 2;

  @override
  Widget build(BuildContext context) {
    final legend = tx(13, c: MP.ink2, h: 20 / 13);
    return D9Card(
      gap: 16,
      children: [
        const D9Head('Clinic snapshot', sub: 'Readings from all patients'),
        Semantics(
          label: 'Time range',
          child: MpSegmented(options: _ranges, index: _range, onChanged: (i) => setState(() => _range = i)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const D9Label('In target range'),
            const Gap(4),
            const D9Big('68%', suffix: ' of readings', suffixH: 30 / 16),
            const Gap(4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  text: '+4 pts ',
                  style: tx(14, w: w600, c: MP.green, h: 20 / 14, tab: true),
                  children: [TextSpan(text: 'vs previous ${_ranges[_range]}', style: tx(14, c: MP.ink2, h: 20 / 14))],
                ),
              ),
            ),
          ],
        ),
        Semantics(
          label:
              'Share of readings in target range over the last 30 days, rising from 61% to 68%, just under the 70% goal',
          image: true,
          child: const SizedBox(height: 176, child: CustomPaint(painter: _TrendPainter())),
        ),
        Row(
          children: [
            Container(
              width: 16,
              height: 2,
              decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(999)),
            ),
            const Gap(8),
            Text('In target', style: legend),
            const Gap(20),
            const D9Swatch(MP.greenSoft, ring: MP.green, width: 12),
            const Gap(8),
            Flexible(child: Text('Goal: 70% and above', style: legend)),
          ],
        ),
      ],
    );
  }
}

/// The design's 310×176 trend chart. The y axis (and its labels at x = 32) is
/// fixed; the plot (x 40 → width − 8) stretches with the card.
class _TrendPainter extends CustomPainter {
  const _TrendPainter();

  // Polyline y values from the SVG (148 = 0%, 12 = 100%).
  static const _ys = [65.0, 62.3, 63.7, 59.6, 61.0, 58.2, 56.9, 58.2, 54.2, 55.5];

  static void _label(Canvas canvas, String text, double x, double baseline, TextAlign anchor) {
    final tp = TextPainter(text: TextSpan(text: text, style: tx(11, c: MP.ink3)), textDirection: TextDirection.ltr)
      ..layout();
    final dx = switch (anchor) {
      TextAlign.right => x - tp.width,
      TextAlign.center => x - tp.width / 2,
      _ => x,
    };
    tp.paint(canvas, Offset(dx, baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0;
    final right = size.width - 8;
    final w = right - left;
    double x(double svgX) => left + (svgX - 40) / 262 * w;

    // Goal band, 70–100%.
    canvas.drawRect(Rect.fromLTRB(left, 12, right, 52.8), Paint()..color = MP.greenSoft);

    // Grid lines.
    final grid =
        Paint()
          ..color = MP.line
          ..strokeWidth = 1;
    for (final y in const [12.0, 46.0, 80.0, 114.0, 148.0]) {
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    // Axis labels.
    for (final (t, y) in const [('100%', 16.0), ('75%', 50.0), ('50%', 84.0), ('25%', 118.0), ('0%', 152.0)]) {
      _label(canvas, t, 32, y, TextAlign.right);
    }
    _label(canvas, '31 Aug', x(40), 170, TextAlign.left);
    _label(canvas, '7 Sep', x(105.5), 170, TextAlign.center);
    _label(canvas, '14 Sep', x(171), 170, TextAlign.center);
    _label(canvas, '22 Sep', x(236.5), 170, TextAlign.center);
    _label(canvas, '29 Sep', x(302), 170, TextAlign.right);

    // Trend line.
    final path = Path();
    for (var i = 0; i < _ys.length; i++) {
      final p = Offset(left + i * w / (_ys.length - 1), _ys[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = MP.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Latest point.
    final last = Offset(right, _ys.last);
    canvas.drawCircle(last, 4, Paint()..color = MP.primary);
    canvas.drawCircle(
      last,
      4,
      Paint()
        ..color = MP.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => false;
}

// ─── C. Chat summaries ───────────────────────────────────────────────────────

// (initials, name, time, preview)
const _chats = [
  ('PS', 'Priya Sharma', '9:12 AM', '“Chest feels tight since morning, should I come in?”'),
  ('FI', 'Farhana Islam', '8:52 AM', '“Can I take the iron tablets with my morning tea?”'),
  ('RD', 'Rahul Das', '8:40 AM', '“BP was 172/104 this morning, checked twice.”'),
];

class _Chats extends StatelessWidget {
  /// Live: GET /api/inbox/summaries?date=today.
  final Map<String, dynamic>? live;
  const _Chats({this.live});

  @override
  Widget build(BuildContext context) {
    final s = live;
    // (initials, name, time, preview, needs reply, conversation id)
    final rows = s == null
        ? [for (final c in _chats) (c.$1, c.$2, c.$3, c.$4, true, null)]
        : [
            for (final i in s.list('items').take(3))
              () {
                final name = i.obj('patientId').str('name');
                final at = F.date(i['lastMessageAt']);
                return (F.initials(name), name, at == null ? '' : F.askedAt(at), i.str('summary'), i['needsReply'] == true, i['conversationId']);
              }(),
          ];
    final wrote = s == null ? 9 : s.numOr('patientsWrote').toInt();
    final needReply = s == null ? 3 : s.numOr('needReply').toInt();
    final more = wrote - rows.length;
    return D9Card(
      gap: 16,
      children: [
        D9Head(
          'Chat summaries',
          sub: "Today's conversations",
          trailing: D9Link('View all', top: 3, onTap: () => Nav.go(context, 'Chat-Summaries')),
        ),
        MpGrid(
          columns: 2,
          gap: 8,
          children: [
            D9Tile(
              children: [
                Text(F.count(wrote), style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                Text(wrote == 1 ? 'patient wrote' : 'patients wrote', style: tx(14, c: MP.ink2, h: 20 / 14)),
              ],
            ),
            D9Tile(
              children: [
                Text(F.count(needReply), style: tx(30, w: w800, h: 1, em: -0.02, tab: true, c: MP.amber)),
                Text(needReply == 1 ? 'needs a reply' : 'need a reply', style: tx(14, c: MP.ink2, h: 20 / 14)),
              ],
            ),
          ],
        ),
        if (rows.isNotEmpty) Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in rows)
              D9Row(
                onTap: () => Nav.go(context, 'Patient-Thread', args: c.$6 == null ? null : {'conversationId': c.$6}),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MpAvatar(c.$1, size: 40, fontSize: 14),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  c.$2,
                                  style: tx(16, w: w600, h: 22 / 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Gap(8),
                              Text(c.$3, style: tx(13, c: MP.ink3, h: 18 / 13, tab: true)),
                            ],
                          ),
                          const Gap(2),
                          Text(
                            c.$4,
                            style: tx(14, c: MP.ink2, h: 20 / 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (c.$5) ...[
                            const Gap(2),
                            const Padding(padding: EdgeInsets.only(top: 4), child: MpBadge.amber('Needs reply')),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (more > 0) D9More('+ $more more who wrote today', onTap: () => Nav.go(context, 'Doctor-Messages')),
          ],
        ),
      ],
    );
  }
}

// ─── C. Live activity ────────────────────────────────────────────────────────

// (time, kind, name, detail)
const _activity = [
  ('9:12', 'Message', 'Priya Sharma', '“Chest feels tight since morning, should I come in?”'),
  ('9:04', 'Reading', 'Moumita Roy', 'Pulse 112 bpm'),
  ('8:58', 'Food log', 'Debasish Bose', 'Breakfast · 2 rotis, moong dal, curd'),
  ('8:52', 'Message', 'Farhana Islam', '“Can I take the iron tablets with my morning tea?”'),
  ('8:40', 'Reading', 'Rahul Das', 'BP 172/104 mmHg'),
  ('8:31', 'Food log', 'Priya Sharma', 'Breakfast · vegetable poha with peanuts'),
];

String _activityStem(String kind) => switch (kind) {
  'Message' => 'Patient-Thread',
  'Food log' => 'Nutrition',
  _ => 'PP-Summary',
};

class _Activity extends StatelessWidget {
  const _Activity();

  @override
  Widget build(BuildContext context) {
    return D9Card(
      children: [
        const D9Head('Live activity', sub: 'From data already on this screen', bottom: 12),
        for (final a in _activity)
          D9Row(
            onTap: () => Nav.go(context, _activityStem(a.$2)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Text(a.$1, style: tx(15, w: w600, h: 20 / 15, tab: true), maxLines: 1, softWrap: false),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      D9Label(a.$2, padding: const EdgeInsets.only(bottom: 4)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(a.$3, style: tx(16, w: w600, h: 22 / 16)),
                      ),
                      Text(a.$4, style: tx(14, c: MP.ink2, h: 20 / 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── C. Nutrition reviews ────────────────────────────────────────────────────

// (name, meal, when, photo label)
const _nutrition = [
  (
    'Debasish Bose',
    'Breakfast · 2 rotis, moong dal, curd',
    'Logged today, 8:58 AM',
    'Meal photo: breakfast logged by Debasish Bose',
  ),
  (
    'Priya Sharma',
    'Lunch · brown rice, rajma, cucumber salad',
    'Logged yesterday, 1:40 PM',
    'Meal photo: lunch logged by Priya Sharma',
  ),
];

class _NutritionReviews extends StatelessWidget {
  /// Live: meal logs waiting for review (the logs themselves aren't in the API).
  final int? due;
  const _NutritionReviews({this.due});

  @override
  Widget build(BuildContext context) {
    void openNutrition() => Nav.go(context, 'Nutrition');
    if (due != null) {
      return D9Card(
        children: [
          D9Head(
            'Nutrition reviews',
            sub: 'Review cadence due',
            bottom: 12,
            trailing: D9Link('View all', top: 3, onTap: openNutrition),
          ),
          Text(
            '${D9Fmt.plural(due!, 'meal log')} from the last 7 days ${due == 1 ? 'needs' : 'need'} a review',
            style: tx(14, c: MP.ink2),
          ),
        ],
      );
    }
    return D9Card(
      children: [
        D9Head(
          'Nutrition reviews',
          sub: 'Review cadence due',
          bottom: 12,
          trailing: D9Link('View all', top: 3, onTap: openNutrition),
        ),
        for (final n in _nutrition)
          D9Row(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: n.$4,
                      image: true,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Ico(I.image, size: 20, color: MP.ink3),
                            const Gap(4),
                            Text('Meal photo', style: tx(11, w: w600, c: MP.ink3, h: 14 / 11)),
                          ],
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.$1, style: tx(16, w: w600, h: 22 / 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const Gap(2),
                          Text(
                            n.$2,
                            style: tx(14, c: MP.ink2, h: 20 / 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Gap(2),
                          Text(n.$3, style: tx(13, c: MP.ink3, h: 18 / 13, tab: true)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(child: Text('Review due today', style: tx(14, w: w600, c: MP.amber, h: 20 / 14))),
                    const Gap(12),
                    MpButton.small('Review', expand: false, onTap: openNutrition),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

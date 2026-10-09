import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: Daily-Report.dc.html — "Daily report".
/// Live data (args `{'date'}` optional): GET /api/reports/daily?date=;
/// Download PDF / share → POST /api/exports {kind: report, reportType: daily}.
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

const _dates = [
  'Today · Tue, 29 Sep 2026',
  'Yesterday · Mon, 28 Sep 2026',
  'Sun, 27 Sep 2026',
  'Sat, 26 Sep 2026',
  'Fri, 25 Sep 2026',
];

const _vitalLabels = ['BP mmHg', 'Pulse', 'SpO₂', 'Weight'];

typedef _Visit =
    ({
      String name,
      String meta,
      bool isNew,
      String complaint,
      String diagnosis,
      List<String> vitals,
      List<(String, String)> rx,
      String advice,
      String followUp,
    });

const List<_Visit> _visits = [
  (
    name: 'Priya Sharma',
    meta: '29 F · Seen 9:04 AM',
    isNew: false,
    complaint: 'Tiredness and excess thirst, 2 weeks',
    diagnosis: 'Type 2 diabetes (uncontrolled), PCOS',
    vitals: ['118/76', '82', '99%', '68 kg'],
    rx: [
      ('Metformin 500 mg', '1-0-1 · after food · 3 months'),
      ('Glimepiride 1 mg', '1-0-0 · before breakfast · 3 months'),
      ('Vitamin D3 60,000 IU', 'Once a week · after food · 8 weeks'),
    ],
    advice: 'Walk 30 minutes daily and cut sugary drinks. Repeat HbA1c before the next visit.',
    followUp: 'Tue, 27 Oct 2026',
  ),
  (
    name: 'Rahul Das',
    meta: '45 M · Seen 9:38 AM',
    isNew: true,
    complaint: 'Headaches, home BP over 160/100',
    diagnosis: 'Essential hypertension, stage 2',
    vitals: ['158/98', '88', '98%', '82 kg'],
    rx: [
      ('Telmisartan 40 mg', '1-0-0 · after breakfast · 1 month'),
      ('Amlodipine 5 mg', '0-0-1 · after dinner · 1 month'),
    ],
    advice: 'Keep salt under 5 g a day. Log home BP twice daily in the app.',
    followUp: 'Tue, 13 Oct 2026',
  ),
  (
    name: 'Aisha Khan',
    meta: '52 F · Seen 10:06 AM',
    isNew: false,
    complaint: 'Weight gain, feels cold all the time',
    diagnosis: 'Hypothyroidism, under-replaced',
    vitals: ['124/80', '64', '98%', '71 kg'],
    rx: [('Levothyroxine 75 mcg', '1-0-0 · empty stomach · 6 weeks')],
    advice: 'Take it 30 minutes before breakfast or tea. Repeat TSH in 6 weeks.',
    followUp: 'Tue, 10 Nov 2026',
  ),
];

class _DailyReportScreenState extends State<DailyReportScreen> with LiveData {
  String _date = _dates.first;
  final _busy = ValueNotifier(false);

  /// Live: the picker's labels → days (the last 5, plus a day passed in args).
  Map<String, DateTime> _days = const {};
  bool _argsRead = false;

  static String _label(DateTime d, DateTime today) {
    if (F.sameDay(d, today)) return 'Today · ${F.dateLong(d)}';
    if (F.sameDay(d, today.subtract(const Duration(days: 1)))) return 'Yesterday · ${F.dateLong(d)}';
    return F.dateLong(d);
  }

  @override
  Future<Object?> fetch() async {
    if (!_argsRead) {
      _argsRead = true;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final days = {for (var i = 0; i < 5; i++) _label(today.subtract(Duration(days: i)), today): today.subtract(Duration(days: i))};
      final a = Nav.args<Map>(context) ?? const {};
      final asked = a['date'] is String ? D9Fmt.parseDate(a['date'] as String) : null;
      var pick = days.keys.first;
      if (asked != null) {
        final label = _label(asked, today);
        if (!days.containsKey(label)) days[label] = asked;
        pick = label;
      }
      _days = days;
      _date = pick;
    }
    return Api.I.get('/api/reports/daily', query: {'date': D9Fmt.dayKey(_days[_date]!)});
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  List<String> get _options => data == null && !isLive ? _dates : _days.keys.toList();

  (String, String, String) get _summary {
    if (data == null) return ('14', '3', '11');
    final s = data!.obj('summary');
    return ('${s.numOr('consultations')}', '${s.numOr('new')}', '${s.numOr('followUp')}');
  }

  static String _food(String v) => switch (v) {
    'before_food' => 'before food',
    'after_food' => 'after food',
    'with_food' => 'with food',
    'empty_stomach' => 'empty stomach',
    'bedtime' => 'at bedtime',
    _ => v.replaceAll('_', ' '),
  };

  static String _duration(Map<String, dynamic> d) {
    final unit = d.str('unit');
    if (unit == 'ongoing') return 'ongoing';
    final n = d.numOr('value');
    if (n <= 0 || unit.isEmpty) return '';
    return '${F.count(n)} ${n == 1 ? unit.replaceFirst(RegExp(r's$'), '') : unit}';
  }

  List<_Visit> get _liveVisits {
    if (data == null) return _visits;
    return [
      for (final c in data!.list('items'))
        () {
          final p = c.obj('patient');
          final seen = F.date(c['seenAt']);
          final v = c.obj('vitals');
          final follow = F.date(c['followUpDate']);
          final ageSex = [if (p['age'] != null) '${p['age']}', D9Fmt.gender(p['gender'])].where((x) => x.isNotEmpty).join(' ');
          return (
            name: p.str('name'),
            meta: [if (ageSex.isNotEmpty) ageSex, if (seen != null) 'Seen ${F.time(seen)}'].join(' · '),
            isNew: c['isNew'] == true,
            complaint: c.str('complaint'),
            diagnosis: c.str('diagnosis'),
            vitals: c['vitals'] == null
                ? const <String>[]
                : [
                    v.str('bp', '—'),
                    v.str('pulse', '—'),
                    v['spo2'] == null ? '—' : '${v['spo2']}%',
                    v['weightKg'] == null ? '—' : '${v['weightKg']} kg',
                  ],
            rx: [
              for (final m in c.list('medicines'))
                (
                  m.str('name'),
                  [
                    switch (m.str('frequency')) {
                      'weekly' => 'Once a week',
                      'as_needed' => 'As needed',
                      _ => m.str('pattern'),
                    },
                    _food(m.str('foodRelation')),
                    _duration(m.obj('duration')),
                  ].where((x) => x.isNotEmpty).join(' · '),
                ),
            ],
            advice: c.str('advice'),
            followUp: follow == null ? '' : F.dateLong(follow),
          );
        }(),
    ];
  }

  void _pickDate(String v) {
    setState(() => _date = v);
    if (isLive) reload();
  }

  /// PDF of the day via POST /api/exports, opened outside the app.
  Future<void> _pdf(String done) async {
    if (!isLive) {
      toast(context, done);
      return;
    }
    final picked = _days[_date];
    if (picked == null) return;
    final day = D9Fmt.dayKey(picked);
    final res = await runAction(
      context,
      () => Api.I.post('/api/exports', {
        'kind': 'report',
        'reportType': 'daily',
        'format': 'pdf',
        'filters': {'from': day, 'to': day},
      }),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    await D9Open.url(context, res['url'], failed: "Couldn't open the report");
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final visits = _liveVisits;
    final options = _options;
    return MpPage(
      header: MpHeader(
        'Daily report',
        actions: [MpIconButton(I.share, label: 'Share report', onTap: () => _pdf('Report shared'))],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          if (options.isNotEmpty) D9Labeled(
            'Report date',
            h: 20 / 14,
            child: D9Select(
              title: 'Report date',
              value: _date,
              options: options,
              leading: I.calendar,
              leadingColor: MP.ink2,
              chevronColor: MP.ink3,
              right: 17,
              onChanged: _pickDate,
            ),
          ),
          if (placeholder != null) placeholder else ...[
          _DaySummary(_summary),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: D9Label('Consultations')),
                  Text('In visit order', style: tx(13, c: MP.ink3)),
                ],
              ),
            ),
          ),
          for (final v in visits) _VisitCard(v),
          if (visits.isEmpty) Text('No consultations on this day', style: tx(14, c: MP.ink2)),
          // Live, every consultation of the day is listed above.
          if (data == null) SizedBox(
            height: 48,
            child: Tap(
              onTap: () => Nav.go(context, 'Report-Consultations'),
              radius: 12,
              child: Center(child: Text('Show 11 more consultations', style: tx(15, w: w600, c: MP.primary))),
            ),
          ),
          ],
        ],
      ),
      bottom: MpBottomBar(
        child: MpButton(
          'Download PDF',
          icon: I.download,
          iconStroke: 1.75,
          onTap: () => _pdf('PDF downloaded'),
        ),
      ),
    );
  }
}

/// White card with a 1.3fr / 1fr / 1fr grid of day totals.
class _DaySummary extends StatelessWidget {
  /// (consultations, new, follow-up)
  final (String, String, String) n;
  const _DaySummary(this.n);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Day summary',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: MPDeco.card(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 13, child: _SummaryCell(n.$1, 'Consultations', pad: 20, divider: false)),
            Expanded(flex: 10, child: _SummaryCell(n.$2, 'New')),
            Expanded(flex: 10, child: _SummaryCell(n.$3, 'Follow-up')),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String n;
  final String label;
  final double pad;
  final bool divider;
  const _SummaryCell(this.n, this.label, {this.pad = 16, this.divider = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad),
      decoration: divider ? const BoxDecoration(border: Border(left: BorderSide(color: MP.line))) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
          const Gap(4),
          // CSS grid keeps the label on one line (min-content track); scale
          // down instead of wrapping on the narrowest phones.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: tx(14, c: MP.ink2, h: 20 / 14), maxLines: 1),
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final _Visit v;
  const _VisitCard(this.v);

  Widget _block(String label, Widget child, {double gap = 4}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [D9Label(label), Gap(gap), child]);

  @override
  Widget build(BuildContext context) {
    return D9Card(
      gap: 16,
      children: [
        D9Head(
          v.name,
          sub: v.meta,
          subTab: true,
          trailing: v.isNew ? const MpBadge.blue('New', weight: w600) : const MpBadge.grey('Follow-up', weight: w600),
        ),
        if (v.complaint.isNotEmpty) _block('Complaint', Text(v.complaint, style: tx(16, h: 1.5))),
        if (v.diagnosis.isNotEmpty) _block('Diagnosis', Text(v.diagnosis, style: tx(16, w: w600, h: 1.5))),
        if (v.vitals.length == _vitalLabels.length) _block(
          'Vitals',
          gap: 8,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _vitalLabels.length; i++) ...[
                  if (i > 0) const Gap(8),
                  Expanded(
                    flex: i == 0 ? 125 : 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _vitalLabels[i],
                          style: tx(12, c: MP.ink3, h: 16 / 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Gap(2),
                        Text(
                          v.vitals[i],
                          style: tx(15, w: w600, h: 20 / 15, tab: true),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (v.rx.isNotEmpty) _block(
          'Prescription',
          gap: 8,
          VGap(
            gap: 12,
            cross: CrossAxisAlignment.start,
            children: [
              for (final (drug, detail) in v.rx)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drug, style: tx(16, w: w600, h: 24 / 16)),
                    Text(detail, style: tx(14, c: MP.ink2, h: 20 / 14, tab: true)),
                  ],
                ),
            ],
          ),
        ),
        if (v.advice.isNotEmpty) _block('Advice', Text(v.advice, style: tx(16, h: 1.5))),
        if (v.followUp.isNotEmpty) Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
          child: Row(
            children: [
              const Ico(I.calendar, size: 18, color: MP.ink2),
              const Gap(8),
              Text('Follow-up', style: tx(14, c: MP.ink2)),
              const Gap(12),
              Expanded(
                child: Text(v.followUp, textAlign: TextAlign.right, style: tx(16, w: w600, h: 24 / 16, tab: true)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

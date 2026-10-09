import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Report-FollowUps.dc.html — "Report · Follow-up compliance".
/// Live data: GET /api/reports/follow-ups; "Send reminder" POST
/// /api/follow-ups/:id/remind; "Call" dials the patient (tel:).
class ReportFollowupsScreen extends StatefulWidget {
  const ReportFollowupsScreen({super.key});

  @override
  State<ReportFollowupsScreen> createState() => _ReportFollowupsScreenState();
}

const _byCondition = [
  D3BarRow('Type 2 diabetes', '78%', 0.78),
  D3BarRow('Hypertension', '70%', 0.70),
  D3BarRow('Hypothyroidism', '65%', 0.65),
];

// (patient, days late, detail)
const _missed = [
  ('Kaushik Paul', '23 days late', '47 M · Type 2 diabetes · due 8 Sep'),
  ('Shreya Basu', '17 days late', '33 F · Hypothyroidism · due 14 Sep'),
  ('Gopal Mitra', '12 days late', '66 M · Hypertension · due 19 Sep'),
  ('Ananya Chatterjee', '7 days late', '39 F · Type 2 diabetes · due 24 Sep'),
];

/// Revealed by "Show 20 more" (24 missed in all; today is 1 Oct).
const _missedMore = [
  ('Rakhi Sen', '7 days late', '52 F · Hypertension · due 24 Sep'),
  ('Pranab Das', '6 days late', '60 M · Type 2 diabetes · due 25 Sep'),
  ('Sumita Ghosh', '6 days late', '44 F · Hypothyroidism · due 25 Sep'),
  ('Dipak Mondal', '6 days late', '58 M · Hypertension · due 25 Sep'),
  ('Rupa Dey', '5 days late', '36 F · Type 2 diabetes · due 26 Sep'),
  ('Haripada Saha', '5 days late', '69 M · Hypertension · due 26 Sep'),
  ('Moni Begum', '5 days late', '41 F · Hypothyroidism · due 26 Sep'),
  ('Sukanta Roy', '4 days late', '50 M · Type 2 diabetes · due 27 Sep'),
  ('Jayeeta Bose', '4 days late', '29 F · Hypothyroidism · due 27 Sep'),
  ('Tarun Kundu', '3 days late', '63 M · Type 2 diabetes · due 28 Sep'),
  ('Shampa Nag', '3 days late', '47 F · Hypertension · due 28 Sep'),
  ('Arup Biswas', '3 days late', '55 M · Type 2 diabetes · due 28 Sep'),
  ('Mahua Pal', '2 days late', '38 F · Hypothyroidism · due 29 Sep'),
  ('Nirmal Dutta', '2 days late', '71 M · Hypertension · due 29 Sep'),
  ('Rubina Khatun', '2 days late', '33 F · Type 2 diabetes · due 29 Sep'),
  ('Kartik Majhi', '2 days late', '46 M · Hypertension · due 29 Sep'),
  ('Ritam Sarkar', '1 day late', '41 M · Type 2 diabetes · due 30 Sep'),
  ('Sohini Bose', '1 day late', '36 F · Hypothyroidism · due 30 Sep'),
  ('Bapi Hazra', '1 day late', '52 M · Type 2 diabetes · due 30 Sep'),
  ('Ankita Ghosh', '1 day late', '27 F · Hypothyroidism · due 30 Sep'),
];

class _ReportFollowupsScreenState extends State<ReportFollowupsScreen> with LiveData, D3FilterState {
  bool _more = false;
  static const _shown = 4;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final f = await loadFilters();
    return await Api.I.get('/api/reports/follow-ups', query: f.query);
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _remind(Map<String, dynamic> m) async {
    final name = m.obj('patient').str('name', 'the patient');
    final res = await runAction(context, () => Api.I.post('/api/follow-ups/${m['id']}/remind'), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, 'Reminder sent to $name');
    reload(quiet: true);
  }

  /// Calls the patient (the number comes with the row, or from their record).
  Future<void> _call(Map<String, dynamic> m) async {
    final p = m.obj('patient');
    var phone = p.str('phone');
    if (phone.isEmpty && p['id'] != null) {
      final res = await runAction(context, () => Api.I.get('/api/patients/${p['id']}'));
      if (res is Map) phone = (res['patient'] as Map?)?['phone']?.toString() ?? '';
    }
    if (!mounted) return;
    if (phone.isEmpty) {
      toast(context, 'No mobile number for ${p.str('name', 'this patient')}');
      return;
    }
    final ok = await d3Launch(Uri(scheme: 'tel', path: phone));
    if (!ok && mounted) toast(context, "Couldn't start the call");
  }

  Widget _liveBody() {
    final d = data!;
    final missed = d.list('missedList')..sort((a, b) => b.numOr('daysLate').compareTo(a.numOr('daysLate')));
    final visible = _more ? missed : missed.take(_shown).toList();
    final byCondition = [
      for (final c in d.list('byCondition').take(5))
        D3BarRow(c.str('condition'), '${c.numOr('onTimePct')}%', c.numOr('onTimePct') / 100),
    ];
    return VGap(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
      gap: 12,
      children: [
        _Summary(
          pct: d['onTimePct'] is num ? '${d['onTimePct']}%' : '–',
          onTime: d.numOr('onTime').toInt(),
          late: d.numOr('late').toInt(),
          missed: d.numOr('missed').toInt(),
        ),
        if (byCondition.isNotEmpty) D3BarCard(title: 'On time by condition', rows: byCondition),
        D3SectionHead('Missed follow-ups', trailing: d3Plural(missed.length, 'patient')),
        if (visible.isNotEmpty) D3ListCard(children: [for (final m in visible) _liveRow(m)]),
        if (!_more && missed.length > _shown)
          D3ShowMore('Show ${missed.length - _shown} more', onTap: () => setState(() => _more = true)),
      ],
    );
  }

  Widget _liveRow(Map<String, dynamic> m) {
    final p = m.obj('patient');
    final late = m.numOr('daysLate').toInt();
    final due = d3Day(m['dueDate']);
    final detail = [
      d3AgeSex(p['age'], p['gender']),
      p.str('condition'),
      if (due != null) 'due ${F.dayMonth(due)}',
    ].where((s) => s.isNotEmpty).join(' · ');
    return D3RegisterRow(
      name: p.str('name', 'Patient'),
      trailing: D3Badge(late == 1 ? '1 day late' : '$late days late', tone: D3Tone.red),
      detail: detail,
      footer: D3LinkRow([
        ('Send reminder', () => _remind(m)),
        ('Call', () => _call(m)),
      ]),
      onTap: () => Nav.go(context, 'PP-Summary', args: {'patientId': p['id'], 'followUpId': m['id']}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = isLive;
    final rows = [..._missed, if (_more) ..._missedMore];
    return MpPage(
      header: live
          ? D3ReportHeader(
            title: 'Follow-up compliance',
            subtitle: data == null ? filters.label : '${d3Plural(data!.numOr('due'), 'follow-up')} due · ${filters.label}',
            rangeLabel: filters.label,
            locationLabel: filters.locationLabel,
            onFilters: pickFilters,
          )
          : const D3ReportHeader(title: 'Follow-up compliance', subtitle: '150 follow-ups due · 1 – 30 Sep'),
      bottom: live
          ? D3DownloadBar('Download report', reportType: 'follow_ups', filters: filters)
          : const D3DownloadBar('Download report'),
      body: placeholder ?? (data != null ? _liveBody() : VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          const _Summary(),
          const D3BarCard(title: 'On time by condition', rows: _byCondition),
          const D3SectionHead('Missed follow-ups', trailing: '24 patients'),
          D3ListCard(children: [for (final r in rows) _row(r)]),
          if (!_more) D3ShowMore('Show ${_missedMore.length} more', onTap: () => setState(() => _more = true)),
        ],
      )),
    );
  }

  Widget _row((String, String, String) r) => D3RegisterRow(
    name: r.$1,
    trailing: D3Badge(r.$2, tone: D3Tone.red),
    detail: r.$3,
    footer: D3LinkRow([
      ('Send reminder', () => toast(context, 'Reminder sent to ${r.$1}')),
      ('Call', () => toast(context, 'Calling ${r.$1}')),
    ]),
    onTap: () => Nav.go(context, 'PP-Summary'),
  );
}

/// 72% headline, stacked on-time / late / missed bar and its legend.
class _Summary extends StatelessWidget {
  final String pct;
  final int onTime;
  final int late;
  final int missed;
  const _Summary({this.pct = '72%', this.onTime = 108, this.late = 18, this.missed = 24});

  @override
  Widget build(BuildContext context) {
    final total = onTime + late + missed;
    // Stacked bar segments (flex = share); empty segments are left out.
    final segs = [
      if (onTime > 0) (MP.primary, onTime),
      if (late > 0) (MP.primaryMid, late),
      if (missed > 0) (MP.lineStrong, missed),
    ];
    const pill = Radius.circular(999);
    return MpCard(
      padding: const EdgeInsets.all(20),
      child: VGap(
        gap: 14,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(pct, style: tx(36, w: w800, h: 1, em: -0.02)),
              const SizedBox(width: 10),
              Flexible(child: Text('came back on time', style: tx(14, c: MP.ink2))),
            ],
          ),
          Semantics(
            label: '$onTime on time, $late late, $missed missed',
            child: SizedBox(
              height: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (segs.isEmpty)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  for (var i = 0; i < segs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, (segs[i].$2 / total * 100).round()),
                      child: Container(
                        decoration: BoxDecoration(
                          color: segs[i].$1,
                          borderRadius: BorderRadius.horizontal(
                            left: i == 0 ? pill : Radius.zero,
                            right: i == segs.length - 1 ? pill : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _legend(MP.primary, 'On time', F.count(onTime))),
              const SizedBox(width: 8),
              Expanded(child: _legend(MP.primaryMid, 'Late', F.count(late))),
              const SizedBox(width: 8),
              Expanded(child: _legend(MP.lineStrong, 'Missed', F.count(missed))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color dot, String label, String n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2))),
        ],
      ),
      const SizedBox(height: 2),
      Text(n, style: tx(17, w: w700)),
    ],
  );
}

import 'package:flutter/material.dart' hide Text;

import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d6.dart';
import '../../widgets/i18n.dart';

/// Design: PP-Tests.dc.html — "Patient profile · Test results".
/// Live data: GET /api/patients/:id, /lab-results and /records. Opening a
/// result opens Lab-Report, where the doctor marks it reviewed.
class PpTestsScreen extends StatefulWidget {
  const PpTestsScreen({super.key});

  @override
  State<PpTestsScreen> createState() => _PpTestsScreenState();
}

class _PpTestsScreenState extends State<PpTestsScreen> with LiveData {
  @override
  Future<Object?> fetch() => d6Load(context, {'labs': '/lab-results', 'records': '/records'});

  static String _flagPill(Map<String, dynamic> r) {
    final flags = [for (final v in r.list('values')) if (v['flag'] != null && v['flag'] != 'normal') v.str('flag')];
    if (flags.isEmpty) return 'Abnormal';
    if (flags.contains('critical')) return 'Critical';
    if (flags.toSet().length == 1) return flags.length == 1 ? d6Cap(flags.first) : '${flags.length} ${flags.first}';
    return '${flags.length} abnormal';
  }

  static String _value(Map<String, dynamic> v) {
    final unit = v.str('unit');
    final val = v['value'] != null ? d6Num(v['value']) : v.str('valueText');
    return unit.isEmpty ? val : unit == '%' ? '$val%' : '$val $unit';
  }

  /// "LDL cholesterol 162 mg/dL · Triglycerides 210 mg/dL" / "14 ng/mL · ref 30–100"
  static String _finding(Map<String, dynamic> r) {
    final bad = [for (final v in r.list('values')) if (v['flag'] != null && v['flag'] != 'normal') v];
    if (bad.isEmpty) return r.str('ecgInterpretation');
    if (bad.length == 1) {
      final ref = bad.first.str('refText');
      final name = bad.first.str('analyte');
      final single = name.toLowerCase() == r.str('testName').toLowerCase();
      return [if (!single) name, _value(bad.first)].join(' ') + (ref.isEmpty ? '' : ' · ref $ref');
    }
    return bad.map((v) => '${v.str('analyte')} ${_value(v)}').join(' · ');
  }

  static String _when(Map<String, dynamic> r) {
    final at = F.date(r['collectedAt']);
    return [if (at != null) d6Date(at), r.str('labName', 'Lab report')].join(' · ');
  }

  Future<void> _openLive(BuildContext context, D6Rec rec, Map<String, dynamic> r) async {
    // Opening a result is not reviewing it: the doctor marks it on the report ("Mark as
    // reviewed"), so a stray tap never tells the patient their doctor has seen it.
    await Nav.go(context, 'Lab-Report', args: {'labResultId': r.str('id'), 'patientId': rec.m.str('id')});
    if (context.mounted) reload(quiet: true);
  }

  Widget _liveBody(BuildContext context, D6Rec rec) {
    final all = rec.m.obj('labs').list('items');
    final abnormal = [for (final r in all) if (r.numOr('abnormalCount') > 0) r];
    final normal = [for (final r in all) if (r.numOr('abnormalCount') == 0) r];
    final labels = ['All · ${all.length}', 'Abnormal · ${abnormal.length}', 'Normal · ${normal.length}'];
    return VGap(
      gap: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < labels.length; i++)
              D6FilterChip(labels[i], selected: _filter == i, onTap: () => setState(() => _filter = i)),
          ],
        ),
        D6ShieldNote('Reports ${rec.first} has shared with you. Abnormal first.'),
        if (all.isEmpty) Text('No test results yet', style: tx(14, c: MP.ink2)),
        if (_filter != 2 && abnormal.isNotEmpty)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: D6Caps('Abnormal findings', color: MP.amber),
                ),
                for (final t in abnormal)
                  D6Row(
                    onTap: () => _openLive(context, rec, t),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(t.str('testName'), style: tx(16, w: w600))),
                                  const Gap(8),
                                  D6Pill(_flagPill(t), bg: MP.amberSoft, fg: MP.amber),
                                ],
                              ),
                              const Gap(3),
                              Text(_finding(t), style: tx(14, w: w600, c: MP.amber, tab: true)),
                              const Gap(3),
                              Text(_when(t), style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (_filter != 1 && normal.isNotEmpty)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(padding: EdgeInsets.only(bottom: 12), child: D6Caps('Within normal range')),
                for (final t in normal)
                  D6Row(
                    onTap: () => _openLive(context, rec, t),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.str('testName'), style: tx(16, w: w600)),
                              const Gap(3),
                              Text(_when(t), style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const D6Pill('Normal', bg: MP.greenSoft, fg: MP.green),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// name, flag, finding, date, source.
  static const _abnormal = [
    ('Lipid profile', '2 high', 'LDL 162 · Triglycerides 210 mg/dL', '12 Mar 2026', 'SRL Diagnostics'),
    ('Diabetes panel', '2 high', 'HbA1c 7.2% · Fasting glucose 138', '18 Jul 2026', 'City Care lab'),
    ('Vitamin D (25-OH)', 'Low', '14 ng/mL · ref 30–100', '18 Jul 2026', 'Uploaded by Priya'),
  ];

  /// name, date, source.
  static const _normal = [
    ('ECG', '12 Aug 2026', 'City Care'),
    ('Kidney function test', '18 Jul 2026', 'City Care lab'),
    ('Complete blood count', '18 Jul 2026', 'City Care lab'),
    ('Thyroid profile', '10 Jan 2026', 'Uploaded by Priya'),
    ('Urine routine', '10 Jan 2026', 'City Care lab'),
  ];

  static const _filters = ['All · 8', 'Abnormal · 3', 'Normal · 5'];

  int _filter = 0;

  void _open(BuildContext context) => Nav.go(context, 'Lab-Report');

  @override
  Widget build(BuildContext context) {
    final rec = data == null ? null : D6Rec(data!);
    if (rec != null) {
      return D6PatientTabsPage(tab: 2, gap: 12, rec: rec, onChanged: () => reload(quiet: true), children: [_liveBody(context, rec)]);
    }
    return D6PatientTabsPage(
      tab: 2,
      gap: 12,
      placeholder: livePlaceholder(),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _filters.length; i++)
              D6FilterChip(_filters[i], selected: _filter == i, onTap: () => setState(() => _filter = i)),
          ],
        ),
        const D6ShieldNote('Reports Priya has shared with you. Abnormal first.'),
        if (_filter != 2)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: D6Caps('Abnormal findings', color: MP.amber),
                ),
                for (final t in _abnormal)
                  D6Row(
                    onTap: () => _open(context),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(t.$1, style: tx(16, w: w600))),
                                  const Gap(8),
                                  D6Pill(t.$2, bg: MP.amberSoft, fg: MP.amber),
                                ],
                              ),
                              const Gap(3),
                              Text(t.$3, style: tx(14, w: w600, c: MP.amber, tab: true)),
                              const Gap(3),
                              Text('${t.$4} · ${t.$5}', style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (_filter != 1)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(padding: EdgeInsets.only(bottom: 12), child: D6Caps('Within normal range')),
                for (final t in _normal)
                  D6Row(
                    onTap: () => _open(context),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.$1, style: tx(16, w: w600)),
                              const Gap(3),
                              Text('${t.$2} · ${t.$3}', style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const D6Pill('Normal', bg: MP.greenSoft, fg: MP.green),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
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

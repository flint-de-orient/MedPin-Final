import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../data/downloads.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d6.dart';
import '../../widgets/i18n.dart';

/// Doctor · Lab report — one test result: values with reference ranges and
/// flags, the previous reading of each value, the report file, and "Mark as
/// reviewed". Opened from the patient's Tests tab with {'labResultId'}.
/// Live data: GET /api/lab-results/:id, POST /api/lab-results/:id/reviewed.
class LabReportScreen extends StatefulWidget {
  const LabReportScreen({super.key});

  @override
  State<LabReportScreen> createState() => _LabReportScreenState();
}

class _LabReportScreenState extends State<LabReportScreen> with LiveData {
  static final Map<String, dynamic> _sample = {
    'testName': 'Lipid profile',
    'labName': 'SRL Diagnostics',
    'collectedAt': null,
    'abnormalCount': 2,
    'patient': {'name': 'Priya Sharma', 'age': 29, 'gender': 'female'},
    'values': [
      {'analyte': 'LDL cholesterol', 'value': 162, 'unit': 'mg/dL', 'refText': 'below 100', 'flag': 'high', 'previous': {'value': 158, 'collectedAt': null}},
      {'analyte': 'Triglycerides', 'value': 210, 'unit': 'mg/dL', 'refText': 'below 150', 'flag': 'high', 'previous': {'value': 205, 'collectedAt': null}},
      {'analyte': 'HDL cholesterol', 'value': 46, 'unit': 'mg/dL', 'refText': 'above 40', 'flag': 'normal', 'previous': null},
      {'analyte': 'Total cholesterol', 'value': 196, 'unit': 'mg/dL', 'refText': 'below 200', 'flag': 'normal', 'previous': null},
    ],
    'record': {
      'aiSummary': 'LDL and triglycerides are high and slightly up since March. HDL is in range.',
      'files': [
        {'name': 'Lipid profile.pdf', 'pages': 2},
      ],
    },
  };

  bool _busy = false;

  @override
  Future<Object?> fetch() {
    final a = Nav.args<Map>(context) ?? const {};
    final id = a['labResultId'];
    if (id == null) throw const ApiException(400, 'NO_REPORT', 'Choose a report from the Tests tab.');
    return Api.I.get('/api/lab-results/$id');
  }

  Map<String, dynamic> get _r => data ?? _sample;

  static (Color, Color, String) _flagStyle(String? flag) => switch (flag) {
    'critical' => (MP.redSoft, MP.red, 'Critical'),
    'high' => (MP.amberSoft, MP.amber, 'High'),
    'low' => (MP.amberSoft, MP.amber, 'Low'),
    _ => (MP.greenSoft, MP.green, 'Normal'),
  };

  static String _num(Object? v) {
    if (v is num) return v % 1 == 0 ? v.toInt().toString() : v.toString();
    return v == null ? '–' : '$v';
  }

  String _change(Map<String, dynamic> v) {
    final prev = v.obj('previous');
    if (prev.isEmpty) return '';
    final now = v['value'];
    final before = prev['value'];
    final at = F.date(prev['collectedAt']);
    final when = at == null ? '' : ' · ${F.dayMonth(at)}';
    if (now is num && before is num) {
      final arrow = now > before ? '↑' : now < before ? '↓' : '→';
      return '$arrow from ${_num(before)}$when';
    }
    return 'was ${_num(before)}$when';
  }

  Future<void> _openFile(Map<String, dynamic> f) async {
    final url = f['url'] as String?;
    if (url == null) {
      toast(context, isLive ? 'This report has no file' : 'Opening ${f.str('name', 'report')}');
      return;
    }
    await Downloads.open(context, url, name: f.str('name', 'Lab report'));
  }

  Future<void> _review() async {
    if (!isLive) {
      toast(context, 'Marked as reviewed');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => Api.I.post('/api/lab-results/${_r['id']}/reviewed'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == null) return;
    toast(context, 'Marked as reviewed');
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final r = _r;
    final p = r.obj('patient');
    final collected = F.date(r['collectedAt']);
    final values = r.list('values');
    final record = r.obj('record');
    final files = record.list('files');
    final n = r.numOr('abnormalCount').toInt();
    final reviewed = r.obj('reviewed');
    final reviewedAt = F.date(reviewed['at']);
    final reviewer = reviewed.obj('by').str('name');
    final ecg = r['ecgInterpretation'] as String?;
    final patientLine = [
      p.str('name'),
      if (p['age'] != null) '${p['age']}${p.str('gender').isEmpty ? '' : ' ${p.str('gender')[0].toUpperCase()}'}',
    ].where((x) => x.isNotEmpty).join(' · ');
    return MpPage(
      header: D4Header(r.str('testName', 'Lab report'), subtitle: patientLine.isEmpty ? null : patientLine),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              D4Card(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: D4TitleSub(
                          r.str('testName'),
                          [r.str('labName'), if (collected != null) 'Collected ${F.dayMonth(collected)} ${collected.year}'].where((x) => x.isNotEmpty).join(' · '),
                          weight: w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (ecg != null)
                        D6Pill(ecg[0].toUpperCase() + ecg.substring(1), bg: ecg == 'normal' ? MP.greenSoft : MP.amberSoft, fg: ecg == 'normal' ? MP.green : MP.amber)
                      else
                        D6Pill(n == 0 ? 'Normal' : '$n ${n == 1 ? 'value' : 'values'} out of range', bg: n == 0 ? MP.greenSoft : MP.amberSoft, fg: n == 0 ? MP.green : MP.amber),
                    ],
                  ),
                  if (record.str('aiSummary').isNotEmpty || r.str('ecgNote').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Ico(I.sparkle, size: 18, color: MP.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r.str('ecgNote').isNotEmpty ? r.str('ecgNote') : record.str('aiSummary'), style: tx(14, h: 1.5))),
                        ],
                      ),
                    ),
                ],
              ),
              if (values.isNotEmpty)
                MpCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(padding: EdgeInsets.only(bottom: 12), child: D6Caps('Values')),
                      for (final v in values)
                        () {
                          final (bg, fg, label) = _flagStyle(v['flag'] as String?);
                          final change = _change(v);
                          return D6Row(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(v.str('analyte'), style: tx(16, w: w600)),
                                      const SizedBox(height: 3),
                                      Text(
                                        [if (v.str('refText').isNotEmpty) 'Normal ${v.str('refText')}', if (change.isNotEmpty) change].join(' · '),
                                        style: tx(13, c: MP.ink3, tab: true),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        text: _num(v['value'] ?? v['valueText']),
                                        children: [if (v.str('unit').isNotEmpty) TextSpan(text: ' ${v.str('unit')}', style: tx(12, w: w600, c: MP.ink3))],
                                      ),
                                      style: tx(18, w: w800, c: v['flag'] == 'normal' || v['flag'] == null ? MP.ink : fg, tab: true),
                                    ),
                                    const SizedBox(height: 4),
                                    D6Pill(label, bg: bg, fg: fg, height: 22, padH: 8),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }(),
                    ],
                  ),
                ),
              if (files.isNotEmpty)
                D4Card(
                  children: [
                    const D4CardTitle('Report file'),
                    for (final f in files)
                      Tap(
                        onTap: () => _openFile(f),
                        radius: 16,
                        color: MP.white,
                        border: MP.line,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const MpIconTile(I.fileText, size: 40, iconSize: 20, radius: 12),
                            const SizedBox(width: 12),
                            Expanded(
                              child: D4TitleSub(
                                f.str('name', 'Report'),
                                [
                                  if (f['pages'] != null) '${f['pages']} ${f['pages'] == 1 ? 'page' : 'pages'}',
                                  if (record['pageFrom'] != null) 'this test on pages ${record['pageFrom']}–${record['pageTo']}',
                                ].join(' · ').ifEmpty('Tap to open'),
                              ),
                            ),
                            const Ico(I.download, size: 18, color: MP.primary),
                          ],
                        ),
                      ),
                  ],
                ),
              if (reviewedAt != null)
                Center(child: Text('Reviewed${reviewer.isEmpty ? '' : ' by $reviewer'} · ${F.dayMonth(reviewedAt)}, ${F.time(reviewedAt)}', style: tx(13, c: MP.ink2)))
              else if (!isLive || Session.I.role == 'doctor') // a doctor's review (the patient is told)
                MpButton(_busy ? 'Saving…' : 'Mark as reviewed', onTap: _busy ? null : _review),
            ],
          ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

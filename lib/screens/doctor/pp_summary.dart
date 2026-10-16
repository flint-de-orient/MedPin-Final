import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d6.dart';
import '../../widgets/i18n.dart';

/// Design: PP-Summary.dc.html — "Patient profile · Summary".
/// Live data: GET /api/patients/:id, /vitals and /lab-results.
class PpSummaryScreen extends StatefulWidget {
  const PpSummaryScreen({super.key});

  @override
  State<PpSummaryScreen> createState() => _PpSummaryScreenState();
}

class _PpSummaryScreenState extends State<PpSummaryScreen> with LiveData {
  @override
  Future<Object?> fetch() => d6Load(context, {'vitals': '/vitals', 'labs': '/lab-results'});

  @override
  Widget build(BuildContext context) {
    final rec = data == null ? null : D6Rec(data!);
    return D6PatientTabsPage(
      tab: 0,
      rec: rec,
      placeholder: livePlaceholder(),
      onChanged: () => reload(quiet: true),
      children: [
        if (rec == null || _AiSummary.shown(rec)) const _AiSummary(),
        if (rec == null || _Vitals.live(rec).isNotEmpty) const _Vitals(),
        if (rec == null || _FastingSugar.live(rec).isNotEmpty) const _FastingSugar(),
        if (rec != null && !_AiSummary.shown(rec) && _Vitals.live(rec).isEmpty)
          Row(
            children: [
              Expanded(child: Text('No readings or test results yet', style: tx(14, c: MP.ink2))),
              const Gap(12),
              // With nothing on record the Vitals card is hidden; its Record action stays here.
              Builder(builder: (c) => D6Link('Record vitals', onTap: () => _Vitals.record(c))),
            ],
          ),
      ],
    );
  }
}

class _AiSummary extends StatelessWidget {
  const _AiSummary();

  /// name, value, flag, reference range, source.
  static const _findings = [
    ('LDL cholesterol', '162 mg/dL', 'High', '< 100', 'Lipid profile, 12 Mar 2026'),
    ('Triglycerides', '210 mg/dL', 'High', '< 150', 'Lipid profile, 12 Mar 2026'),
    ('HbA1c', '7.2%', 'High', '< 7.0', 'Diabetes panel, 18 Jul 2026'),
    ('Fasting glucose', '138 mg/dL', 'High', '70–99', 'Diabetes panel, 18 Jul 2026'),
    ('Vitamin D', '14 ng/mL', 'Low', '30–100', 'Vitamin D, 18 Jul 2026'),
  ];

  static Map<String, dynamic> _ai(D6Rec r) => r.detail.obj('aiSummary');
  static bool _hasAi(D6Rec r) => _ai(r).str('body').isNotEmpty;
  static bool shown(D6Rec r) => _hasAi(r) || r.detail.list('abnormalResults').isNotEmpty;

  /// Abnormal values from the record, with the reference range from the report.
  static List<(String, String, String, String, String)> _live(D6Rec r) {
    final labs = r.m.obj('labs').list('items');
    String ref(Map<String, dynamic> f) {
      for (final l in labs) {
        if ('${l['id']}' != '${f['labResultId']}') continue;
        for (final v in l.list('values')) {
          if (v['analyte'] == f['analyte']) return v.str('refText');
        }
      }
      return '';
    }

    return [
      for (final f in r.detail.list('abnormalResults'))
        (
          f.str('analyte'),
          [d6Num(f['value']), f.str('unit')].where((s) => s.isNotEmpty).join(f.str('unit') == '%' ? '' : ' '),
          d6Cap(f.str('flag')),
          ref(f),
          [f.str('test'), if (F.date(f['collectedAt']) != null) d6Date(F.date(f['collectedAt'])!)].where((s) => s.isNotEmpty).join(', '),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final ai = r == null ? null : _ai(r);
    final hasAi = r == null || _hasAi(r);
    final findings = r == null ? _findings : _live(r);
    final reports = r == null ? 3 : {for (final f in r.detail.list('abnormalResults')) '${f['labResultId']}'}.length;
    final updatedAt = F.date(ai?['generatedAt'] ?? ai?['createdAt']);
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: VGap(
        gap: 16,
        children: [
          if (hasAi) Row(
            children: [
              const Ico(I.sparkle, size: 16, color: MP.primary),
              const Gap(6),
              const Expanded(child: D6Caps('AI summary', color: MP.primary)),
              if (r == null || updatedAt != null)
                Text(r == null ? 'Updated today, 8:55 AM' : 'Updated ${d6When(updatedAt!)}', style: tx(13, c: MP.ink3)),
            ],
          ),
          if (r == null) Text.rich(
            TextSpan(
              style: tx(16, h: 1.55),
              children: [
                const TextSpan(
                  text:
                      'Type 2 diabetes since Jun 2025, with PCOS. Sugar control improved on Metformin '
                      '(HbA1c 8.4% → 6.8%) but has drifted back to 7.2%. LDL stays high on Atorvastatin. '
                      'Adherence is 86% with 4 missed doses this week. ',
                ),
                TextSpan(text: 'Reported chest tightness this morning.', style: tx(16, w: w700, h: 1.55)),
              ],
            ),
          ) else if (hasAi) Text(ai!.str('body'), style: tx(16, h: 1.55)),

          // Abnormal findings
          if (findings.isNotEmpty) Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text('Abnormal findings', style: tx(16, w: w700))),
                    Text('${findings.length} from $reports ${reports == 1 ? 'report' : 'reports'}', style: tx(13, c: MP.ink3)),
                  ],
                ),
              ),
              for (final f in findings) _finding(context, f),
            ],
          ),

          // Source note
          if (hasAi) Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Written by AI from ${r?.first ?? 'Priya'}'s shared records. Check the source before acting.",
                    style: tx(13, c: MP.ink3, h: 1.4),
                  ),
                ),
                const Gap(12),
                D6Link('Sources', onTap: () => d6Tab(context, 'PP-Tests')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _finding(BuildContext context, (String, String, String, String, String) f) {
    final name = tx(15, w: w600);
    final ref = tx(13, c: MP.ink3);
    final value = tx(15, w: w700, tab: true);
    final flag = tx(12, w: w700, c: MP.amber);
    final refText = f.$4.isEmpty ? f.$5 : 'Ref ${f.$4} · ${f.$5}';
    // Like Chrome, only break "138 mg/dL" at the space, not after the slash.
    final valueText = f.$2.replaceAll('/', '/\u2060');
    return D6Row(
      padding: const EdgeInsets.symmetric(vertical: 12),
      onTap: () => d6Tab(context, 'PP-Tests'),
      child: LayoutBuilder(
        builder: (context, c) {
          // Both columns are flex items: when they don't fit side by side they
          // shrink together (e.g. "Fasting glucose": "138 / mg/dL" wraps).
          final (wl, wr) = D6Flex.pair(
            context,
            avail: c.maxWidth - 12,
            a: [(f.$1, name), (refText, ref)],
            b: [(valueText, value), (f.$3, flag)],
            aMinZero: true,
          );
          return Row(
            children: [
              SizedBox(
                width: wl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(f.$1, style: name), const Gap(2), Text(refText, style: ref)],
                ),
              ),
              const Gap(12),
              SizedBox(
                width: wr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [Text(valueText, style: value), const Gap(2), Text(f.$3, style: flag)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Vitals extends StatelessWidget {
  const _Vitals();

  /// "Record": a vitals sheet saved with POST /api/patients/:id/vitals, then
  /// the summary reloads with the new readings.
  static Future<void> record(BuildContext context) async {
    final scope = D6Scope.maybeOf(context);
    final id = scope?.rec?.id;
    if (!isLive || id == null) {
      d6Go(context, 'Consult-Vitals');
      return;
    }
    final saved = await openSheet<bool>(context, (_) => _RecordVitalsSheet(patientId: id));
    if (saved == true) await scope?.onChanged?.call();
  }

  /// label, value, unit, band, band colour.
  static const _vitals = [
    ('Blood pressure', '128/82', 'mmHg', 'Normal', MP.green),
    ('Pulse', '78', 'bpm', 'Normal', MP.green),
    ('SpO₂', '98', '%', 'Normal', MP.green),
    ('Temperature', '98.4', '°F', 'Normal', MP.green),
    ('Fasting sugar', '142', 'mg/dL', 'High · home reading', MP.amber),
    ('BMI', '27.4', '', 'Overweight', MP.amber),
    ('Weight', '68.5', 'kg', '−0.8 kg since Aug', MP.ink2),
    ('Height', '158', 'cm', 'Recorded Jun 2025', MP.ink2),
  ];

  /// The newest value of each vital in the last 90 days.
  static List<(String, String, String, String, Color)> live(D6Rec r) {
    Color c(D6Band? b) => b == null ? MP.ink2 : b.$3;
    final out = <(String, String, String, String, Color)>[];
    final bp = r.latestWith('bpSystolic');
    if (bp != null && bp['bpDiastolic'] != null) {
      final b = d6BpBand(bp['bpSystolic'] as num?, bp['bpDiastolic'] as num?);
      out.add(('Blood pressure', '${d6Num(bp['bpSystolic'])}/${d6Num(bp['bpDiastolic'])}', 'mmHg', b?.$1 ?? '', c(b)));
    }
    final pulse = r.latestWith('pulse');
    if (pulse != null) {
      final b = d6PulseBand(pulse['pulse'] as num?);
      out.add(('Pulse', d6Num(pulse['pulse']), 'bpm', b?.$1 ?? '', c(b)));
    }
    final spo2 = r.latestWith('spo2');
    if (spo2 != null) {
      final b = d6Spo2Band(spo2['spo2'] as num?);
      out.add(('SpO₂', d6Num(spo2['spo2']), '%', b?.$1 ?? '', c(b)));
    }
    final temp = r.latestWith('temperatureF');
    if (temp != null) {
      final b = d6TempBand(temp['temperatureF'] as num?);
      out.add(('Temperature', d6Num(temp['temperatureF']), '°F', b?.$1 ?? '', c(b)));
    }
    final sugar = r.fastingSugar;
    if (sugar != null && sugar['bloodSugar'] is num) {
      final v = sugar['bloodSugar'] as num;
      final target = r.detail.obj('targets').numOr('sugarFasting', 130);
      final band = v > target ? 'High' : v < 70 ? 'Low' : 'In range';
      final home = sugar['source'] == 'home' ? ' · home reading' : '';
      out.add(('Fasting sugar', d6Num(v), 'mg/dL', '$band$home', band == 'In range' ? MP.green : MP.amber));
    }
    final clinic = r.clinicVitals ?? const <String, dynamic>{};
    final bmi = clinic['bmi'] ?? r.p['bmi'];
    if (bmi is num) {
      final b = d6BmiBand(bmi);
      out.add(('BMI', d6Num(bmi), '', b?.$1 ?? '', c(b)));
    }
    final weights = [for (final v in r.vitals) if (v['weightKg'] is num) v];
    final weight = weights.isEmpty ? r.p['weightKg'] : weights.first['weightKg'];
    if (weight is num) {
      var note = 'On record';
      if (weights.length > 1) {
        final old = weights.last;
        final diff = (weight - (old['weightKg'] as num)).toDouble();
        final since = F.date(old['recordedAt']);
        final when = since == null ? '' : ' since ${F.dayMonth(since).split(' ').last}';
        note = diff.abs() < 0.05 ? 'No change$when' : '${diff < 0 ? '−' : '+'}${d6Num(double.parse(diff.abs().toStringAsFixed(1)))} kg$when';
      } else if (weights.isNotEmpty && F.date(weights.first['recordedAt']) != null) {
        note = 'Recorded ${d6MonthYear(F.date(weights.first['recordedAt'])!)}';
      }
      out.add(('Weight', d6Num(weight), 'kg', note, MP.ink2));
    }
    final h = r.latestWith('heightCm');
    final height = h?['heightCm'] ?? r.p['heightCm'];
    if (height is num) {
      final at = F.date(h?['recordedAt']);
      out.add(('Height', d6Num(height), 'cm', at == null ? 'On record' : 'Recorded ${d6MonthYear(at)}', MP.ink2));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final vitals = r == null ? _vitals : live(r);
    var sub = 'Today, 8:52 AM · front desk';
    if (r != null) {
      final last = r.vitals.isEmpty ? null : r.vitals.first;
      final at = F.date(last?['recordedAt']);
      sub = last == null || at == null ? 'From the patient record' : '${d6Cap(d6When(at))} · ${d6RecordedBy(last)}';
    }
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: D6Title('Vitals', sub: sub, subH: null)),
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                // Record = enter today's vitals only. Consult-Vitals is step 1 of a
                // consultation (it starts one and goes on to Diagnosis), which is
                // what "Start consultation" is for.
                child: D6Link('Record', onTap: () => record(context)),
              ),
            ],
          ),
          MpGrid(
            columns: 2,
            children: [
              for (final v in vitals)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.$1, style: tx(13, c: MP.ink2)),
                      const Gap(4),
                      Text.rich(
                        TextSpan(
                          text: v.$2,
                          style: tx(22, w: w800, h: 1.15, em: -0.01, tab: true),
                          // Inherits line-height 1.15 and -0.01em of 22px in CSS.
                          children: [
                            TextSpan(
                              text: ' ${v.$3}',
                              style: tx(13, w: w500, c: MP.ink3, h: 1.15).copyWith(letterSpacing: -0.22),
                            ),
                          ],
                        ),
                      ),
                      const Gap(4),
                      Text(v.$4, style: tx(12, w: w700, c: v.$5)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FastingSugar extends StatelessWidget {
  const _FastingSugar();

  static const _chart =
      r'''<svg xmlns="http://www.w3.org/2000/svg" width="310" height="140" viewBox="0 0 310 140" font-family="Figtree">
<g stroke="#E5E9F0" stroke-width="1"><line x1="34" y1="10" x2="306" y2="10"/><line x1="34" y1="50" x2="306" y2="50"/><line x1="34" y1="90" x2="306" y2="90"/><line x1="34" y1="118" x2="306" y2="118"/></g>
<g font-size="11" fill="#69738A" text-anchor="end"><text x="26" y="14">200</text><text x="26" y="54">150</text><text x="26" y="94">100</text><text x="26" y="122">70</text></g>
<line x1="34" y1="66" x2="306" y2="66" stroke="#076B3C" stroke-width="1" stroke-dasharray="4 3"/>
<text x="306" y="80" font-size="11" fill="#076B3C" text-anchor="end">Target 130</text>
<polyline points="40,50 84,54.8 128,58.8 172,57.2 216,53.2 260,59.6 302,56.4" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
<g fill="#FFFFFF" stroke="#003399" stroke-width="2"><circle cx="40" cy="50" r="3"/><circle cx="84" cy="54.8" r="3"/><circle cx="128" cy="58.8" r="3"/><circle cx="172" cy="57.2" r="3"/><circle cx="216" cy="53.2" r="3"/><circle cx="260" cy="59.6" r="3"/><circle cx="302" cy="56.4" r="3.5" fill="#003399"/></g>
<g font-size="11" fill="#69738A" text-anchor="middle"><text x="40" y="136">Wed</text><text x="84" y="136">Thu</text><text x="128" y="136">Fri</text><text x="172" y="136">Sat</text><text x="216" y="136">Sun</text><text x="260" y="136">Mon</text><text x="298" y="136">Tue</text></g>
</svg>''';

  /// Fasting readings of the last 7 days, one per day (the newest), oldest first.
  static List<(DateTime, num)> live(D6Rec r) {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final byDay = <String, (DateTime, num)>{};
    for (final v in r.vitals) {
      final at = F.date(v['recordedAt']);
      if (at == null || at.isBefore(since) || v['sugarType'] != 'fasting' || v['bloodSugar'] is! num) continue;
      byDay.putIfAbsent('${at.year}-${at.month}-${at.day}', () => (at, v['bloodSugar'] as num));
    }
    return byDay.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    var svg = _chart;
    var avg = '143';
    var label = 'Fasting sugar between 138 and 150 mg/dL over 7 days, above the 130 target';
    if (r != null) {
      final pts = live(r);
      final target = r.detail.obj('targets').numOr('sugarFasting', 130);
      final vals = [for (final p in pts) p.$2];
      final lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
      svg = d6DailySvg(pts, target: target);
      avg = '${(vals.reduce((a, b) => a + b) / vals.length).round()}';
      final vs = lo > target ? 'above' : hi <= target ? 'within' : 'around';
      label = 'Fasting sugar between ${d6Num(lo)} and ${d6Num(hi)} mg/dL over ${pts.length} days, $vs the ${d6Num(target)} target';
    }
    return MpCard(
      child: VGap(
        gap: 12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Fasting sugar', style: tx(20, w: w700, h: 1.25))),
              const Gap(8),
              Text.rich(
                TextSpan(
                  style: tx(14, c: MP.ink2),
                  children: [
                    const TextSpan(text: 'Last 7 days · avg '),
                    TextSpan(text: avg, style: tx(14, w: w700, tab: true)),
                  ],
                ),
              ),
            ],
          ),
          Semantics(
            label: label,
            image: true,
            child: D6Chart(svg, width: 310, height: 140),
          ),
        ],
      ),
    );
  }
}

/// "Record vitals" from the Summary tab: today's clinic readings for the
/// patient, without starting a consultation.
class _RecordVitalsSheet extends StatefulWidget {
  final String patientId;
  const _RecordVitalsSheet({required this.patientId});

  @override
  State<_RecordVitalsSheet> createState() => _RecordVitalsSheetState();
}

class _RecordVitalsSheetState extends State<_RecordVitalsSheet> {
  /// API field, label, unit.
  static const _fields = [
    ('bpSystolic', 'BP systolic', 'mmHg'),
    ('bpDiastolic', 'BP diastolic', 'mmHg'),
    ('pulse', 'Pulse', 'bpm'),
    ('spo2', 'SpO₂', '%'),
    ('temperatureF', 'Temperature', '°F'),
    ('weightKg', 'Weight', 'kg'),
    ('heightCm', 'Height', 'cm'),
    ('bloodSugar', 'Fasting sugar', 'mg/dL'),
  ];

  final _ctrls = {for (final f in _fields) f.$1: TextEditingController()};
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, Object>{};
    for (final f in _fields) {
      final n = num.tryParse(_ctrls[f.$1]!.text.trim().replaceAll(',', '.'));
      if (n != null) body[f.$1] = n;
    }
    if (body.isEmpty) {
      toast(context, 'Enter at least one vital');
      return;
    }
    // Both halves of the BP, or neither (one alone reads as a wrong value).
    if (body.containsKey('bpSystolic') != body.containsKey('bpDiastolic')) {
      toast(context, 'Enter the blood pressure like 120/80');
      return;
    }
    if (body.containsKey('bloodSugar')) body['sugarType'] = 'fasting';
    final res = await runAction(context, () => Api.I.post('/api/patients/${widget.patientId}/vitals', body), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, 'Vitals saved');
    Navigator.pop(context, true);
  }

  Widget _field((String, String, String) f) => MpInput(
        label: f.$2,
        unit: f.$3,
        controller: _ctrls[f.$1],
        tab: true,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      );

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Record vitals',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _fields.length; i += 2) ...[
            if (i > 0) const Gap(12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field(_fields[i])),
                const Gap(12),
                Expanded(child: _field(_fields[i + 1])),
              ],
            ),
          ],
          const Gap(20),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, _) => MpButton(busy ? 'Saving…' : 'Save', onTap: busy ? null : _save),
          ),
        ],
      ),
    );
  }
}

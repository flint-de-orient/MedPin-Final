import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Report-Consultations.dc.html — "Report · Consultation register".
/// Live data: GET /api/reports/consultations (range, filters, q).
class ReportConsultationsScreen extends StatefulWidget {
  const ReportConsultationsScreen({super.key});

  @override
  State<ReportConsultationsScreen> createState() => _ReportConsultationsScreenState();
}

class _Visit {
  final String name;
  final String fee;
  final String detail;
  final String meta;
  final String? badge;
  final D3Tone tone;
  const _Visit(this.name, this.fee, this.detail, this.meta, [this.badge, this.tone = D3Tone.blue]);
}

const _day30 = [
  _Visit('Sanjay Ghosh', '₹600', '9:05 AM · 58 M · Follow-up · Type 2 diabetes', 'Salt Lake · In clinic · 12 min'),
  _Visit('Rina Dutta', '₹600', '9:22 AM · 44 F · New · Hypertension', 'Salt Lake · In clinic · 16 min', 'New patient'),
  _Visit('Tapas Kar', '₹600', '9:46 AM · 63 M · Follow-up · Hypertension, T2DM', 'Salt Lake · In clinic · 9 min'),
  _Visit(
    'Puja Saha',
    'Free',
    '10:10 AM · 27 F · Report review · Hypothyroidism',
    'Salt Lake · Video · 7 min',
    'Free review',
    D3Tone.grey,
  ),
  _Visit('Arijit Roy', '₹500', '5:15 PM · 35 M · New · Fever, cough', 'New Town · In clinic · 10 min', 'New patient'),
];

/// Revealed by "Show 6 more from 30 Sep" (evening chamber at New Town).
const _day30More = [
  _Visit('Kakoli Das', '₹500', '5:32 PM · 48 F · Follow-up · Type 2 diabetes', 'New Town · In clinic · 11 min'),
  _Visit('Biswajit Halder', '₹500', '5:50 PM · 56 M · Follow-up · Hypertension', 'New Town · In clinic · 9 min'),
  _Visit(
    'Payel Mukherjee',
    '₹500',
    '6:08 PM · 31 F · New · Hypothyroidism',
    'New Town · In clinic · 15 min',
    'New patient',
  ),
  _Visit(
    'Rajesh Nandi',
    'Free',
    '6:30 PM · 62 M · Report review · Type 2 diabetes',
    'New Town · In clinic · 6 min',
    'Free review',
    D3Tone.grey,
  ),
  _Visit('Soma Banerjee', '₹500', '6:44 PM · 45 F · Follow-up · Anaemia', 'New Town · Video · 8 min'),
  _Visit('Anirban Sil', '₹500', '7:05 PM · 39 M · Follow-up · Hypertension', 'New Town · In clinic · 10 min'),
];

const _day29 = [
  _Visit(
    'Priya Sharma',
    '₹600',
    '9:14 AM · 29 F · Follow-up · Type 2 diabetes, PCOS',
    'Salt Lake · In clinic · 14 min',
  ),
  _Visit(
    'Nasreen Begum',
    '₹600',
    '9:40 AM · 51 F · Follow-up · Hypothyroidism',
    'Salt Lake · In clinic · 8 min',
    'Fee pending',
    D3Tone.amber,
  ),
];

class _ReportConsultationsScreenState extends State<ReportConsultationsScreen> with LiveData, D3FilterState {
  String _q = '';
  bool _more = false;

  /// Live: days whose rows are all shown ("Show 6 more from 30 Sep").
  final _open = <String>{};
  static const _perDay = 5;
  Timer? _debounce;

  @override
  Future<Object?> fetch() async {
    final f = await loadFilters();
    final q = _q.trim();
    return await Api.I.get('/api/reports/consultations', query: {...f.query, if (q.isNotEmpty) 'q': q});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String s) {
    setState(() => _q = s);
    if (!isLive) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => reload(quiet: true));
  }

  bool _hit(_Visit v, String q) =>
      q.isEmpty ||
      v.name.toLowerCase().contains(q) ||
      v.detail.toLowerCase().contains(q) ||
      v.meta.toLowerCase().contains(q);

  _Visit _visit(Map<String, dynamic> a) {
    final p = a.obj('patient');
    final at = F.date(a['startAt']);
    final type = a.str('visitType');
    final fee = a.numOr('fee');
    final free = fee == 0 || a['feeStatus'] == 'free';
    final dx = [for (final d in (a['diagnoses'] as List? ?? const [])) '$d'];
    final detail = [
      if (at != null) F.time(at),
      d3AgeSex(p['age'], p['gender']),
      type == 'new' ? 'New' : d3VisitType(type),
      if (dx.isNotEmpty) dx.join(', '),
    ].where((s) => s.isNotEmpty).join(' · ');
    final meta = [
      a.str('location'),
      d3Mode(a.str('mode')),
      if (a['durationMin'] is num) '${a['durationMin']} min',
    ].where((s) => s.isNotEmpty).join(' · ');
    final (String?, D3Tone) badge = a['feeStatus'] == 'pending'
        ? ('Fee pending', D3Tone.amber)
        : type == 'new'
        ? ('New patient', D3Tone.blue)
        : free
        ? (type == 'report_review' ? 'Free review' : 'Free visit', D3Tone.grey)
        : (null, D3Tone.blue);
    return _Visit(p.str('name', 'Patient'), free ? 'Free' : d3Rupees(fee.round()), detail, meta, badge.$1, badge.$2);
  }

  /// Live rows grouped by IST day, newest first.
  List<(DateTime, List<(_Visit, Map<String, dynamic>)>)> get _days {
    final out = <(DateTime, List<(_Visit, Map<String, dynamic>)>)>[];
    for (final a in data!.list('items')) {
      final d = d3Day(a['date']) ?? d3Day(a['startAt']);
      if (d == null) continue;
      if (out.isEmpty || !F.sameDay(out.last.$1, d)) out.add((d, []));
      out.last.$2.add((_visit(a), a));
    }
    return out;
  }

  Widget _liveBody() {
    final t = data!.obj('totals');
    final q = _q.trim();
    final days = _days;
    return VGap(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
      gap: 12,
      children: [
        D3StatTiles([
          (F.count(t.numOr('consultations')), 'Consultations', MP.ink),
          (t['avgMin'] is num ? '${t['avgMin']} min' : '–', 'Average time', MP.ink),
          (d3RupeesShort(t.numOr('feesBilled')), 'Fees billed', MP.ink),
        ]),
        for (final (day, rows) in days) ...[
          D3SectionHead(d3DayHead(day), trailing: d3Plural(rows.length, 'consultation')),
          D3ListCard(
            children: [
              for (final r in (q.isNotEmpty || _open.contains(d3DayKey(day)) ? rows : rows.take(_perDay)))
                _row(r.$1, r.$2),
            ],
          ),
          if (q.isEmpty && !_open.contains(d3DayKey(day)) && rows.length > _perDay)
            D3ShowMore(
              'Show ${rows.length - _perDay} more from ${F.dayMonth(day)}',
              onTap: () => setState(() => _open.add(d3DayKey(day))),
            ),
        ],
        if (days.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              q.isEmpty ? 'No consultations in this period' : 'No consultations match “$q”',
              textAlign: TextAlign.center,
              style: tx(15, c: MP.ink2),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = isLive;
    final q = _q.trim().toLowerCase();
    final d30 = [..._day30, if (_more || q.isNotEmpty) ..._day30More].where((v) => _hit(v, q)).toList();
    final d29 = _day29.where((v) => _hit(v, q)).toList();
    final total = data?.obj('totals').numOr('consultations') ?? 0;
    return MpPage(
      header: D3ReportHeader(
        title: 'Consultation register',
        subtitle: !live
            ? '286 consultations · 1 – 30 Sep'
            : (data == null ? filters.label : '${d3Plural(total, 'consultation')} · ${filters.label}'),
        searchHint: 'Search patient, diagnosis or mobile',
        onSearch: _search,
        rangeLabel: live ? filters.label : '1 – 30 Sep',
        locationLabel: live ? filters.locationLabel : 'All locations',
        onFilters: live ? pickFilters : null,
      ),
      bottom: live
          ? D3DownloadBar('Download register', reportType: 'consultations', filters: filters)
          : const D3DownloadBar('Download register'),
      body: placeholder ?? (data != null ? _liveBody() : VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          const D3StatTiles([
            ('286', 'Consultations', MP.ink),
            ('11 min', 'Average time', MP.ink),
            ('₹1.61L', 'Fees billed', MP.ink),
          ]),
          if (d30.isNotEmpty) ...[
            const D3SectionHead('Wed, 30 Sep', trailing: '11 consultations'),
            D3ListCard(children: [for (final v in d30) _row(v)]),
          ],
          if (!_more && q.isEmpty) D3ShowMore('Show 6 more from 30 Sep', onTap: () => setState(() => _more = true)),
          if (d29.isNotEmpty) ...[
            const D3SectionHead('Tue, 29 Sep', trailing: '10 consultations'),
            D3ListCard(children: [for (final v in d29) _row(v)]),
          ],
          if (d30.isEmpty && d29.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No consultations match “${_q.trim()}”',
                textAlign: TextAlign.center,
                style: tx(15, c: MP.ink2),
              ),
            ),
        ],
      )),
    );
  }

  Widget _row(_Visit v, [Map<String, dynamic>? a]) => D3RegisterRow(
    name: v.name,
    trailing: D3Amount(v.fee),
    detail: v.detail,
    footer: Row(
      children: [
        Expanded(child: Text(v.meta, style: tx(13, c: MP.ink3))),
        if (v.badge != null) ...[const SizedBox(width: 8), D3Badge(v.badge!, tone: v.tone)],
      ],
    ),
    onTap: () => Nav.go(
      context,
      'PP-Summary',
      args: a == null ? null : {'patientId': a.obj('patient')['id'], 'appointmentId': a['appointmentId']},
    ),
  );
}

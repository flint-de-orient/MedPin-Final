import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/fee_actions.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';
import '../../widgets/i18n.dart';

/// Design: Report-Fees.dc.html — "Report · Fees and collections".
/// Live data: GET /api/reports/fees (+ /api/locations, /api/payments for
/// names and patient ids); actions POST /api/payments/:id/mark-paid, /link,
/// and /refund on fees to give back.
class ReportFeesScreen extends StatefulWidget {
  const ReportFeesScreen({super.key});

  @override
  State<ReportFeesScreen> createState() => _ReportFeesScreenState();
}

const _byLocation = [
  D3BarRow('City Care · Salt Lake', '₹97,200', 0.60),
  D3BarRow('City Care · New Town', '₹40,000', 0.25),
  D3BarRow('Sen Diabetes Chamber · Gariahat', '₹23,800', 0.15),
];

const _byMethod = [
  D3BarRow('UPI', '₹98,400', 0.63),
  D3BarRow('Cash', '₹41,600', 0.27),
  D3BarRow('Card', '₹16,800', 0.11),
];

// (patient, visit) — every pending fee is ₹600; the first three are shown,
// the rest are revealed by "Show 4 more" (7 patients · ₹4,200 in all).
const _pending = [
  ('Nasreen Begum', '29 Sep · Salt Lake · in clinic'),
  ('Kaushik Paul', '26 Sep · Salt Lake · video'),
  ('Shreya Basu', '22 Sep · Salt Lake · in clinic'),
  ('Partha Ghosh', '18 Sep · Salt Lake · video'),
  ('Sohini Bose', '15 Sep · Salt Lake · in clinic'),
  ('Subrata Pal', '11 Sep · Salt Lake · video'),
  ('Mousumi Dey', '4 Sep · Salt Lake · in clinic'),
];
const _shown = 3;
const _fee = 600;
const _collected = 156800;

class _ReportFeesScreenState extends State<ReportFeesScreen> with LiveData, D3FilterState {
  final _paid = <int>{};
  bool _more = false;
  bool _moreCollected = false;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final f = await loadFilters();
    final r = await Future.wait([
      Api.I.get('/api/reports/fees', query: f.query),
      Api.I.get('/api/locations'),
      Api.I.get('/api/payments', query: {'status': 'pending'}),
    ]);
    // The fees report names the patient; the payments list has their id.
    final patientOf = <String, Object?>{
      for (final p in (r[2] as List? ?? const []))
        if (p is Map) '${p['id']}': (p['patientId'] is Map ? p['patientId']['id'] : p['patientId']),
    };
    final fees = (r[0] as Map).cast<String, dynamic>();
    return {
      ...fees,
      'pending': [
        for (final p in fees.list('pending')) {...p, if (p['patientId'] == null) 'patientId': patientOf['${p['id']}']},
      ],
      'locations': (r[1] as Map?)?['items'] ?? const [],
    };
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  void _markPaid(int i) {
    setState(() => _paid.add(i));
    toast(context, '${_pending[i].$1} marked as paid');
  }

  /// "Mark as paid": how it was paid (cash, UPI or card), so collections by method are right.
  Future<void> _markPaidLive(Map<String, dynamic> p) async {
    const methods = [('cash', 'Cash'), ('upi', 'UPI'), ('card', 'Card')];
    final method = await openSheet<String>(
      context,
      (c) => MpSheet(
        title: 'How was it paid?',
        subtitle: '${p.str('patient', 'Patient')} · ₹${F.count(p.numOr('amount'))}',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: VGap(gap: 12, children: [for (final m in methods) MpButton(m.$2, kind: MpBtn.secondary, onTap: () => Navigator.pop(c, m.$1))]),
        ),
      ),
    );
    if (method == null || !mounted) return;
    final res = await runAction(context, () => Api.I.post('/api/payments/${p['id']}/mark-paid', {'method': method}), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, '${p.str('patient', 'Patient')} marked as paid');
    reload(quiet: true);
  }

  Future<void> _sendLink(Map<String, dynamic> p) async {
    final res = await runAction(context, () => Api.I.post('/api/payments/${p['id']}/link'), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, 'Payment link sent to ${p.str('patient', 'the patient')}');
    reload(quiet: true);
  }

  /// "Refund": handed back at the desk, or an online refund tried again
  /// (POST /api/payments/:id/refund, through the shared fee sheet).
  Future<void> _refund(Map<String, dynamic> p) async {
    final fee = VisitFee(
      paymentId: p['id'] as String?,
      amount: p.numOr('amount').round(),
      status: 'paid',
      method: p['method'] as String?,
      refundDue: true,
    );
    if (await handBackFee(context, fee) && mounted) reload(quiet: true);
  }

  /// "16 Oct, 9:11 AM"
  static String _at(Object? v) {
    final t = F.date(v);
    return t == null ? '' : '${F.dayMonth(t)}, ${F.time(t)}';
  }

  /// "Visit 16 Oct · in clinic"
  String _visitLine(Map<String, dynamic> p) {
    final day = d3Day(p['visitDate']);
    return [
      if (day != null) '${tr(context, 'Visit')} ${F.dayMonth(day)}',
      if (p['mode'] != null) d3Mode(p.str('mode')).toLowerCase(),
    ].join(' · ');
  }

  String _locationLabel(String key) {
    for (final l in data!.list('locations')) {
      if (l['shortName'] == key || l['name'] == key) return d3LocationName(l);
    }
    return key == 'other' ? 'Other' : key;
  }

  static List<D3BarRow> _bars(List<Map<String, dynamic>> rows, num total, String Function(String) label) {
    final sorted = [...rows]..sort((a, b) => b.numOr('amount').compareTo(a.numOr('amount')));
    return [
      for (final r in sorted)
        D3BarRow(label(r.str('key')), d3Rupees(r.numOr('amount').round()), total <= 0 ? 0 : r.numOr('amount') / total),
    ];
  }

  Widget _liveBody() {
    final d = data!;
    final pending = d.list('pending');
    final visible = _more ? pending : pending.take(_shown).toList();
    final byLocation = _bars(d.list('billedByLocation'), d.numOr('billed'), _locationLabel);
    final byMethod = _bars(d.list('collectedByMethod'), d.numOr('collected'), d3Method);
    return VGap(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
      gap: 12,
      children: [
        D3StatTiles([
          (d3RupeesShort(d.numOr('billed')), 'Billed', MP.ink),
          (d3RupeesShort(d.numOr('collected')), 'Collected', MP.green),
          (d3Rupees(d.numOr('pendingAmount').round()), 'Pending', MP.amber),
        ]),
        if (byLocation.isNotEmpty) D3BarCard(title: 'By location', note: 'Billed', rows: byLocation),
        if (byMethod.isNotEmpty) D3BarCard(title: 'By payment method', note: 'Collected', rows: byMethod),
        _freeVisits(F.count(d.numOr('freeVisits'))),
        D3SectionHead('Pending payments', trailing: d3Plural(pending.length, 'patient')),
        if (visible.isNotEmpty) D3ListCard(children: [for (final p in visible) _liveRow(p)]),
        if (!_more && pending.length > _shown)
          D3ShowMore('Show ${pending.length - _shown} more', onTap: () => setState(() => _more = true)),
        ..._collectedSection(d.list('collectedList')),
        ..._refundSection(d.list('refundsDue'), d.list('refunded')),
      ],
    );
  }

  /// Each fee collected in the period: who paid, how and when, where, for which visit.
  List<Widget> _collectedSection(List<Map<String, dynamic>> paid) {
    if (paid.isEmpty) return const [];
    final shown = _moreCollected ? paid : paid.take(_shown).toList();
    return [
      D3SectionHead('Collected', trailing: d3Plural(paid.length, 'payment')),
      D3ListCard(children: [for (final p in shown) _collectedRow(p)]),
      if (!_moreCollected && paid.length > _shown)
        D3ShowMore('Show ${paid.length - _shown} more', onTap: () => setState(() => _moreCollected = true)),
    ];
  }

  Widget _collectedRow(Map<String, dynamic> p) {
    final detail = [
      if (p['method'] != null) d3Method(p.str('method')),
      if (_at(p['paidAt']).isNotEmpty) '${tr(context, 'Paid')} ${_at(p['paidAt'])}',
      p.str('location'),
    ].where((s) => s.isNotEmpty).join(' · ');
    final visit = _visitLine(p);
    return D3RegisterRow(
      name: p.str('patient', 'Patient'),
      trailing: D3Amount(d3Rupees(p.numOr('amount').round())),
      detail: detail,
      footer: visit.isEmpty && p['refundDue'] != true
          ? null
          : Row(
            children: [
              Expanded(child: Text(visit, style: tx(13, c: MP.ink3))),
              if (p['refundDue'] == true) ...[const SizedBox(width: 8), const D3Badge('Refund due', tone: D3Tone.red)],
            ],
          ),
      onTap: () => Nav.go(context, 'PP-Summary', args: {if (p['patientId'] != null) 'patientId': p['patientId']}),
    );
  }

  /// Money to give back (a cancelled visit paid at the desk, or an online
  /// refund that didn't go through), then fees refunded in the period.
  List<Widget> _refundSection(List<Map<String, dynamic>> due, List<Map<String, dynamic>> done) {
    if (due.isEmpty && done.isEmpty) return const [];
    final owed = due.fold<num>(0, (s, p) => s + p.numOr('amount'));
    final back = done.fold<num>(0, (s, p) => s + p.numOr('amount'));
    return [
      D3SectionHead(
        'Refunds',
        trailing: due.isNotEmpty
            ? '${d3Rupees(owed.round())} ${tr(context, 'to hand back')}'
            : '${d3Rupees(back.round())} ${tr(context, 'refunded')}',
      ),
      D3ListCard(children: [for (final p in due) _refundRow(p, due: true), for (final p in done) _refundRow(p, due: false)]),
    ];
  }

  Widget _refundRow(Map<String, dynamic> p, {required bool due}) {
    final online = p['method'] == 'online';
    final when = due ? _at(p['paidAt']) : _at(p['refundedAt']);
    final detail = [
      if (p['method'] != null) d3Method(p.str('method')),
      if (when.isNotEmpty) '${tr(context, due ? 'Paid' : 'Refunded')} $when',
      p.str('location'),
    ].where((s) => s.isNotEmpty).join(' · ');
    final visit = _visitLine(p);
    return D3RegisterRow(
      name: p.str('patient', 'Patient'),
      trailing: D3Amount(d3Rupees(p.numOr('amount').round())),
      detail: detail,
      footer: Row(
        children: [
          Expanded(
            child: due
                ? D3LinkRow([(online ? 'Retry refund' : 'Refund', () => _refund(p))])
                : Text(visit, style: tx(13, c: MP.ink3)),
          ),
          const SizedBox(width: 8),
          due
              ? D3Badge(online ? 'Online refund failed' : 'To hand back', tone: D3Tone.amber)
              : const D3Badge('Refunded', tone: D3Tone.grey),
        ],
      ),
      onTap: () => Nav.go(context, 'PP-Summary', args: {if (p['patientId'] != null) 'patientId': p['patientId']}),
    );
  }

  Widget _liveRow(Map<String, dynamic> p) {
    final day = d3Day(p['date']);
    final detail = [
      if (day != null) F.dayMonth(day),
      p.str('location'),
      if (p['mode'] != null) d3Mode(p.str('mode')).toLowerCase(),
    ].where((s) => s.isNotEmpty).join(' · ');
    return D3RegisterRow(
      name: p.str('patient', 'Patient'),
      trailing: D3Amount(d3Rupees(p.numOr('amount').round())),
      detail: detail,
      footer: Row(
        children: [
          Expanded(
            child: D3LinkRow([
              ('Send payment link', () => _sendLink(p)),
              ('Mark as paid', () => _markPaidLive(p)),
            ]),
          ),
          // The patient chose to pay at the clinic: the desk collects it.
          if (p['payAt'] == 'clinic') ...[const SizedBox(width: 8), const D3Badge('Pay at clinic', tone: D3Tone.amber)],
        ],
      ),
      onTap: () => Nav.go(context, 'PP-Summary', args: {if (p['patientId'] != null) 'patientId': p['patientId']}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = isLive;
    final left = _pending.length - _paid.length;
    final visible = [
      for (var i = 0; i < (_more ? _pending.length : _shown); i++)
        if (!_paid.contains(i)) i,
    ];
    final collected = (_collected + _fee * _paid.length) / 100000;
    return MpPage(
      header: live
          ? D3ReportHeader(
            title: 'Fees and collections',
            subtitle: data == null ? filters.label :'${d3Rupees(data!.numOr('billed').round())} billed · ${filters.label}',
            rangeLabel: filters.label,
            locationLabel: filters.locationLabel,
            onFilters: pickFilters,
          )
          : const D3ReportHeader(title: 'Fees and collections', subtitle: '₹1,61,000 billed · 1 – 30 Sep'),
      bottom: live
          ? D3DownloadBar('Download report', reportType: 'fees', filters: filters)
          : const D3DownloadBar('Download report'),
      body: placeholder ?? (data != null ? _liveBody() : VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          D3StatTiles([
            ('₹1.61L', 'Billed', MP.ink),
            ('₹${collected.toStringAsFixed(2)}L', 'Collected', MP.green),
            (d3Rupees(left * _fee), 'Pending', MP.amber),
          ]),
          const D3BarCard(title: 'By location', note: 'Billed', rows: _byLocation),
          const D3BarCard(title: 'By payment method', note: 'Collected', rows: _byMethod),

          // Free visits
          _freeVisits('10'),

          D3SectionHead('Pending payments', trailing: '$left patient${left == 1 ? '' : 's'}'),
          if (visible.isNotEmpty) D3ListCard(children: [for (final i in visible) _row(i)]),
          if (!_more) D3ShowMore('Show ${_pending.length - _shown} more', onTap: () => setState(() => _more = true)),
        ],
      )),
    );
  }

  Widget _freeVisits(String n) => MpCard(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Free visits', style: tx(15, w: w700)),
              const SizedBox(height: 2),
              Text('Report reviews within 7 days of a visit', style: tx(13, c: MP.ink2)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(n, style: tx(20, w: w800, tab: true)),
      ],
    ),
  );

  Widget _row(int i) {
    final p = _pending[i];
    return D3RegisterRow(
      name: p.$1,
      trailing: D3Amount(d3Rupees(_fee)),
      detail: p.$2,
      footer: D3LinkRow([
        ('Send payment link', () => toast(context, 'Payment link sent to ${p.$1}')),
        ('Mark as paid', () => _markPaid(i)),
      ]),
      onTap: () => Nav.go(context, 'PP-Summary'),
    );
  }
}

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/fee_actions.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d3.dart';

/// "Payments" (front desk, practice manager, doctor's assistant — the 'fees'
/// permission): every visit fee of the practice, not just Today's first rows.
/// Tabs: To collect · Collected · Refunds due.
///
/// Live: GET /api/payments?status=pending and ?status=paid (patient, location
/// and visit filled in); refunds due are paid fees with `refundDue`. Actions:
/// Collect / Refund (widgets/fee_actions.dart), POST /api/payments/:id/link.
class StaffPaymentsScreen extends StatefulWidget {
  const StaffPaymentsScreen({super.key});

  @override
  State<StaffPaymentsScreen> createState() => _StaffPaymentsScreenState();
}

/// One fee row, from the API or the design sample.
class _Pay {
  final String? id;
  final String patient;
  final String? patientId;
  final int amount;
  final String? method;
  final bool payAtClinic;
  final bool refundDue;
  final bool missed;
  final DateTime? visitAt;
  final DateTime? paidAt;
  final String location;

  /// When a payment link was last sent (shown on the row; asking again re-sends the same link).
  final DateTime? linkSentAt;
  const _Pay({
    this.id,
    required this.patient,
    this.patientId,
    required this.amount,
    this.method,
    this.payAtClinic = false,
    this.refundDue = false,
    this.missed = false,
    this.visitAt,
    this.paidAt,
    this.location = '',
    this.linkSentAt,
  });

  factory _Pay.of(Map<String, dynamic> p) {
    final pt = p.obj('patientId');
    final loc = p.obj('locationId');
    final appt = p.obj('appointmentId');
    return _Pay(
      id: p['id'] as String?,
      patient: pt.str('name', 'Patient'),
      patientId: pt['id'] as String? ?? (p['patientId'] is String ? p['patientId'] as String : null),
      amount: p.numOr('amount').round(),
      method: p['method'] as String?,
      // The patient's choice is on the visit (payAt), when the server sends it.
      payAtClinic: (p['payAt'] ?? appt['payAt']) == 'clinic',
      refundDue: p['refundDue'] == true,
      missed: appt['status'] == 'missed',
      visitAt: F.date(appt['startAt']),
      paidAt: F.date(p['paidAt']),
      location: loc.str('shortName', loc.str('name')),
      linkSentAt: F.date(p['paymentLinkSentAt']),
    );
  }

  VisitFee fee(String status) =>
      VisitFee(paymentId: id, amount: amount, status: status, method: method, payAtClinic: payAtClinic, refundDue: refundDue);
}

// Design preview rows.
final _sampleDue = [
  _Pay(patient: 'Nasreen Begum', amount: 600, payAtClinic: true, visitAt: DateTime(2026, 9, 29, 10, 30), location: 'Salt Lake'),
  _Pay(patient: 'Kaushik Paul', amount: 600, visitAt: DateTime(2026, 9, 29, 11, 0), location: 'Salt Lake'),
  _Pay(patient: 'Shreya Basu', amount: 800, payAtClinic: true, missed: true, visitAt: DateTime(2026, 9, 28, 17, 30), location: 'New Town'),
];
final _samplePaid = [
  _Pay(patient: 'Amit Pal', amount: 600, method: 'cash', paidAt: DateTime(2026, 9, 29, 8, 52), location: 'Salt Lake'),
  _Pay(patient: 'Priya Sharma', amount: 600, method: 'online', paidAt: DateTime(2026, 9, 28, 21, 14), location: 'Salt Lake'),
  _Pay(patient: 'Rahul Das', amount: 800, method: 'upi', paidAt: DateTime(2026, 9, 28, 18, 5), location: 'New Town'),
];
final _sampleRefunds = [
  _Pay(patient: 'Moumita Roy', amount: 600, method: 'cash', refundDue: true, paidAt: DateTime(2026, 9, 27, 10, 2), location: 'Salt Lake'),
];

const _tabs = ['To collect', 'Collected', 'Refunds due'];
const _pageSize = 30;

class _StaffPaymentsScreenState extends State<StaffPaymentsScreen> with LiveData {
  int _tab = 0;
  int _limit = _pageSize;
  int _day = 0; // Day's collections: 0 today, 1 yesterday
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final d = DateTime.now().subtract(Duration(days: _day));
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = await Future.wait([
      Api.I.get('/api/payments', query: {'status': 'pending'}),
      Api.I.get('/api/payments', query: {'status': 'paid'}),
      Api.I.get('/api/payments/summary', query: {'date': key}).catchError((_) => null),
    ]);
    List<Map<String, dynamic>> rows(Object? x) => [for (final p in (x as List? ?? const [])) if (p is Map) p.cast<String, dynamic>()];
    final paid = rows(r[1]);
    return {
      'pending': rows(r[0]),
      'paid': [for (final p in paid) if (p['refundDue'] != true) p],
      'refunds': [for (final p in paid) if (p['refundDue'] == true) p],
      'summary': r[2],
    };
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  List<_Pay> _rows(String key, List<_Pay> sample) {
    final d = data;
    if (d == null) return sample;
    final out = [for (final p in d.list(key)) _Pay.of(p)];
    // Collected: the latest payment first (the list comes in by when the fee was raised).
    if (key == 'paid') out.sort((a, b) => (b.paidAt ?? DateTime(0)).compareTo(a.paidAt ?? DateTime(0)));
    return out;
  }

  List<_Pay> get _due => _rows('pending', _sampleDue);
  List<_Pay> get _paid => _rows('paid', _samplePaid);
  List<_Pay> get _refunds => _rows('refunds', _sampleRefunds);

  void _openPatient(_Pay p) {
    if (!isLive) return;
    if (p.patientId != null) Nav.go(context, 'Patient-Profile-Desk', args: {'patientId': p.patientId});
  }

  Future<void> _collect(_Pay p) async {
    if (!isLive) return toast(context, tr(context, '₹#1 collected').replaceFirst('#1', '${p.amount}'));
    if (await collectFee(context, p.fee('pending'), patientName: p.patient) && mounted) reload(quiet: true);
  }

  Future<void> _refund(_Pay p) async {
    if (!isLive) return toast(context, 'Refund recorded');
    if (await handBackFee(context, p.fee('paid')) && mounted) reload(quiet: true);
  }

  Future<void> _sendLink(_Pay p) async {
    final sent = tr(context, 'Payment link sent to #1').replaceFirst('#1', p.patient);
    if (!isLive) return toast(context, sent);
    final res = await runAction(context, () => Api.I.post('/api/payments/${p.id}/link'), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, linkSentNote(context, p.patient, res));
    reload(quiet: true);
  }

  String _how(String? method) => tr(context, d3Method(method ?? 'cash'));

  /// "Day's collections": in by method, handed back, the cash the drawer should hold, and
  /// who took what — for closing the day at the desk.
  Widget _summary() {
    final s = data?.obj('summary') ?? const <String, dynamic>{};
    if (data == null || s.isEmpty) return const SizedBox.shrink();
    Widget line(String label, String value, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: tx(15, w: strong ? w700 : w400, c: color ?? MP.ink))),
              Text(value, style: tx(15, w: strong ? w700 : w600, c: color ?? MP.ink, tab: true)),
            ],
          ),
        );
    final back = s.obj('refunds').obj('handedBack');
    final online = s.obj('refunds').obj('online');
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text("Day's collections", maxLines: 2, style: tx(18, w: w700, h: 1.25))),
              const Gap(12),
              // A compact two-way switch of its own width (in a Row it would squeeze to nothing).
              SizedBox(
                width: 200,
                child: MpSegmented(
                  options: const ['Today', 'Yesterday'],
                  index: _day,
                  height: 36,
                  fontSize: 14,
                  selectedShadow: MPShadow.hairline,
                  onChanged: (i) {
                    if (i == _day) return;
                    setState(() => _day = i);
                    reload();
                  },
                ),
              ),
            ],
          ),
          const Gap(10),
          for (final m in s.list('byMethod')) line('${_how(m.str('method'))} · ${m.numOr('count').toInt()}', d3Rupees(m.numOr('amount').toInt())),
          if (s.list('byMethod').isEmpty) Text('Nothing collected yet', style: tx(15, c: MP.ink2)),
          if (back.numOr('count') > 0) line(tr(context, 'Handed back at the desk'), '− ${d3Rupees(back.numOr('amount').toInt())}', color: MP.red),
          if (online.numOr('count') > 0) line(tr(context, 'Refunded online'), d3Rupees(online.numOr('amount').toInt()), color: MP.ink2),
          const Divider(height: 20, color: MP.line),
          line(tr(context, 'Collected'), d3Rupees(s.obj('collected').numOr('amount').toInt()), strong: true),
          line(tr(context, 'Cash in the drawer'), d3Rupees(s.numOr('cashInDrawer').toInt()), strong: true, color: MP.primary),
          if (s.obj('stillToCollect').numOr('count') > 0)
            line(tr(context, 'Still to collect'), d3Rupees(s.obj('stillToCollect').numOr('amount').toInt()), color: MP.amber),
          if (s.list('byPerson').length > 1 || s.list('byPerson').any((p) => p['userId'] == null && p.str('name') != 'Paid online')) ...[
            const Gap(10),
            Text('BY WHO TOOK IT', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
            const Gap(4),
            for (final p in s.list('byPerson'))
              line(
                '${p['userId'] == null ? tr(context, p.str('name')) : p.str('name')} · ${p.numOr('count').toInt()}',
                [if (p.numOr('cash') > 0) '${tr(context, 'Cash')} ${d3Rupees(p.numOr('cash').toInt())}', if (p.numOr('other') > 0) d3Rupees(p.numOr('other').toInt())].join(' + '),
              ),
          ],
        ],
      ),
    );
  }

  /// "Today, 10:30 AM · Salt Lake · Pay at clinic"
  String _dueDetail(_Pay p) => [
    if (p.visitAt != null) F.when(p.visitAt!),
    p.location,
    if (p.payAtClinic) tr(context, 'Pay at clinic'),
    if (p.missed) tr(context, 'Missed visit'),
    if (p.linkSentAt != null) tr(context, 'Link sent #1').replaceFirst('#1', F.when(p.linkSentAt!)),
  ].where((s) => s.isNotEmpty).join(' · ');

  /// "Cash · paid Today, 8:52 AM · Salt Lake"
  String _paidDetail(_Pay p) => [
    _how(p.method),
    if (p.paidAt != null) tr(context, 'paid #1').replaceFirst('#1', F.when(p.paidAt!)),
    p.location,
  ].where((s) => s.isNotEmpty).join(' · ');

  Widget _row(_Pay p) {
    final amount = D3Amount(d3Rupees(p.amount));
    return switch (_tab) {
      0 => D3RegisterRow(
        name: p.patient,
        trailing: amount,
        detail: _dueDetail(p),
        footer: D3LinkRow([
          ('Collect', () => _collect(p)),
          ('Send payment link', () => _sendLink(p)),
        ]),
        onTap: () => _openPatient(p),
      ),
      1 => D3RegisterRow(name: p.patient, trailing: amount, detail: _paidDetail(p), onTap: () => _openPatient(p)),
      _ => D3RegisterRow(
        name: p.patient,
        trailing: amount,
        detail: _paidDetail(p),
        footer: D3LinkRow([('Refund', () => _refund(p))]),
        onTap: () => _openPatient(p),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final rows = switch (_tab) { 0 => _due, 1 => _paid, _ => _refunds };
    final shown = rows.take(_limit).toList();
    final total = rows.fold<int>(0, (s, p) => s + p.amount);
    const empty = ['No fees to collect', 'No fees collected yet', 'No refunds due'];
    return MpPage(
      header: const MpHeader('Payments', subtitle: 'Visit fees at your clinic', showBack: false),
      nav: const StaffNav(stem: 'Staff-Payments'),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            gap: 12,
            children: [
              D3Tabs(
                options: _tabs,
                index: _tab,
                onChanged: (i) => setState(() {
                  _tab = i;
                  _limit = _pageSize;
                }),
              ),
              if (_tab == 1) _summary(),
              D3SectionHead(tr(context, _tabs[_tab]), trailing: rows.isEmpty ? null : '${d3Rupees(total)} · ${d3Plural(rows.length, 'patient')}'),
              if (shown.isEmpty)
                MpCard(child: Text(empty[_tab], style: tx(15, c: MP.ink2, h: 1.4)))
              else
                D3ListCard(children: [for (final p in shown) _row(p)]),
              if (rows.length > shown.length)
                D3ShowMore('Show ${rows.length - shown.length} more', onTap: () => setState(() => _limit += _pageSize)),
            ],
          ),
    );
  }
}

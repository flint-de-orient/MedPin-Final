import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import '../data/checkout.dart';
import '../data/downloads.dart';
import '../data/format.dart';
import '../data/live.dart';
import 'i18n.dart';
import 'mp.dart';

/// Fee payments as a list, like a clinic's receipt book for one patient: each visit's fee
/// (and extra charges) with its date, doctor and clinic, Paid / Due / Refunded, the receipt
/// number; a paid one opens or shares its receipt (PDF), a due one can be paid online
/// (patient). Totals on top: paid and still due.
/// Live data: GET /api/patient/payments (the patient) or /api/payments/history?patientId=
/// (desk / doctor); receipts: GET …/payments/:id/receipt.
class PaymentHistory extends StatefulWidget {
  /// null: the patient's own (this profile); else that patient, at this clinic.
  final String? patientId;
  const PaymentHistory({super.key, this.patientId});

  @override
  State<PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<PaymentHistory> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String? _busyId;

  bool get _patient => widget.patientId == null;
  String get _base => _patient ? '/api/patient/payments' : '/api/payments';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!isLive) {
      setState(() => _items = _sample);
      return;
    }
    try {
      final res = await (_patient ? Api.I.get(_base) : Api.I.get('/api/payments/history', query: {'patientId': widget.patientId}));
      if (!mounted) return;
      setState(() {
        _items = res is Map ? res.cast<String, dynamic>().list('items') : const [];
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static final _sample = <Map<String, dynamic>>[
    {'id': 's1', 'amount': 500, 'status': 'paid', 'method': 'online', 'paidAt': '2026-10-24T08:39:00Z', 'receiptNo': 'R-0042', 'hasReceipt': true, 'doctorName': 'Dr. Arjun Sen', 'clinicName': 'City Care — New Town', 'items': [{'label': 'Consultation', 'amount': 500}]},
    {'id': 's2', 'amount': 650, 'status': 'paid', 'method': 'cash', 'paidAt': '2026-09-12T05:10:00Z', 'receiptNo': 'R-0031', 'hasReceipt': true, 'doctorName': 'Dr. Arjun Sen', 'clinicName': 'City Care — New Town', 'items': [{'label': 'Follow-up consultation', 'amount': 500}, {'label': 'ECG', 'amount': 150}]},
  ];

  (String, Color, Color) _status(Map<String, dynamic> p) => switch (p.str('status')) {
        'paid' when p['refundDue'] == true => ('Refund due', MP.amberSoft, MP.amber),
        'paid' => ('Paid', MP.greenSoft, MP.green),
        'refunded' => ('Refunded', MP.fill, MP.ink2),
        'waived' => ('Waived', MP.fill, MP.ink2),
        'free' => ('No fee', MP.fill, MP.ink2),
        _ => ('Due', MP.amberSoft, MP.amber),
      };

  String _how(String? method) => switch (method) {
        'online' => 'Online',
        'cash' => 'Cash',
        'upi' => 'UPI',
        'card' => 'Card',
        'net_banking' => 'Net banking',
        _ => '',
      };

  /// The receipt file (made by the server), named by its number.
  Future<(String?, String)?> _receipt(Map<String, dynamic> p) async {
    if (!isLive) {
      toast(context, 'Receipt downloaded');
      return null;
    }
    setState(() => _busyId = p.str('id'));
    try {
      final res = await runAction(context, () => Api.I.get('$_base/${p.str('id')}/receipt'));
      if (res is! Map) return null;
      return (res['url'] as String?, 'Receipt-${p.str('receiptNo', 'MedPin')}.pdf');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _open(Map<String, dynamic> p) async {
    final r = await _receipt(p);
    if (r != null && mounted) await Downloads.open(context, r.$1, name: r.$2);
  }

  Future<void> _share(Map<String, dynamic> p) async {
    final r = await _receipt(p);
    if (r != null && mounted) await Downloads.share(context, r.$1, name: r.$2);
  }

  Future<void> _pay(Map<String, dynamic> p) async {
    final id = p.str('appointmentId');
    if (!isLive || id.isEmpty) return;
    final paid = await Checkout.pay(context, kind: 'fee', id: id);
    if (paid && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_error != null) {
      return Column(
        children: [
          const Gap(24),
          Text(_error!, textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.45)),
          const Gap(12),
          MpButton.small('Try again', kind: MpBtn.secondary, expand: false, onTap: () {
            setState(() => _error = null);
            _load();
          }),
        ],
      );
    }
    if (items == null) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(_patient ? 'No payments yet. Visit fees you pay show here, with their receipts.' : 'No payments from this patient yet.', textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.45)),
      );
    }
    num sum(bool Function(Map<String, dynamic>) f) => items.where(f).fold<num>(0, (a, p) => a + p.numOr('amount'));
    final paid = sum((p) => p.str('status') == 'paid');
    final due = sum((p) => p.str('status') == 'pending');
    return VGap(
      gap: 12,
      children: [
        Row(
          children: [
            Expanded(child: _Total(label: 'Paid', amount: paid, color: MP.green)),
            const Gap(12),
            Expanded(child: _Total(label: 'Still to pay', amount: due, color: due > 0 ? MP.amber : MP.ink2)),
          ],
        ),
        for (final p in items) _row(p),
      ],
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final (label, bg, fg) = _status(p);
    final at = F.date(p['paidAt']) ?? F.date(p['visitAt']) ?? F.date(p['createdAt']);
    final what = [for (final i in p.list('items')) i.str('label')].where((s) => s.isNotEmpty).join(' + ');
    final who = [p.str('doctorName'), p.str('clinicName')].where((s) => s.isNotEmpty).join(' · ');
    final how = [
      if (p.str('status') == 'paid' || p.str('status') == 'refunded') _how(p['method'] as String?),
      if (p.str('receiptNo').isNotEmpty) trf(context, 'Receipt {no}', {'no': p.str('receiptNo')}),
    ].where((s) => s.isNotEmpty).join(' · ');
    final busy = _busyId == p.str('id');
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(at == null ? '' : F.dateLong(at), style: tx(16, w: w600, h: 1.4, tab: true)),
                    if (what.isNotEmpty) ...[const Gap(2), UserText(what, style: tx(14, c: MP.ink2, h: 1.45))],
                    if (who.isNotEmpty) ...[const Gap(2), UserText(who, style: tx(13, c: MP.ink3, h: 1.4))],
                  ],
                ),
              ),
              const Gap(12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${F.count(p.numOr('amount'))}', style: tx(16, w: w700, h: 1.4, tab: true)),
                  const Gap(4),
                  MpBadge(label, bg: bg, fg: fg, weight: w600),
                ],
              ),
            ],
          ),
          if (how.isNotEmpty) ...[const Gap(8), Text(how, style: tx(13, c: MP.ink2, h: 1.4, tab: true))],
          if (p['hasReceipt'] == true || p['canPayOnline'] == true && _patient) ...[
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p['hasReceipt'] == true) ...[
                  MpButton.small(busy ? 'Getting the file ready…' : 'Open receipt', kind: MpBtn.secondary, expand: false, onTap: busy ? null : () => _open(p)),
                  MpButton.small('Share', kind: MpBtn.secondary, expand: false, onTap: busy ? null : () => _share(p)),
                ],
                if (p['canPayOnline'] == true && _patient) MpButton.small('Pay online', expand: false, onTap: () => _pay(p)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final num amount;
  final Color color;
  const _Total({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) => MpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: tx(13, c: MP.ink2, h: 1.4)),
            const Gap(4),
            Text('₹${F.count(amount)}', style: tx(20, w: w700, c: color, h: 1.25, tab: true)),
          ],
        ),
      );
}

/// Patient · Payments and receipts (Me → Payments and receipts; the "Paid" notice opens it).
class PatientPaymentsScreen extends StatelessWidget {
  const PatientPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const MpPage(
        header: MpHeader('Payments and receipts'),
        body: Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 32), child: PaymentHistory()),
      );
}

/// The desk (or the doctor) · a patient's payments at this clinic, from their profile.
Future<void> showPatientPayments(BuildContext context, {required String patientId, String? name}) => openSheet<void>(
      context,
      (_) => MpSheet(
        title: 'Payments',
        subtitle: name == null ? null : trf(context, '{name} · fees and receipts', {'name': name}),
        showClose: true,
        child: Padding(padding: const EdgeInsets.only(top: 16), child: PaymentHistory(patientId: patientId)),
      ),
    );

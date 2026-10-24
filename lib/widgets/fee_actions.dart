import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import '../data/checkout.dart';
import '../data/live.dart';
import 'i18n.dart';
import 'mp.dart';

/// A visit's fee, as the desk and the doctor see it on their lists (queue,
/// Today), from the appointment's `payment` ({id, status, method, amount,
/// refundDue}), `fee`, `feeStatus` and `payAt` (the patient's choice).
class VisitFee {
  final String? paymentId;
  final int amount;
  final String status; // pending · paid · refunded · free · waived
  final String? method; // online · cash · upi · card · net_banking
  final bool payAtClinic;
  final bool refundDue;
  const VisitFee({this.paymentId, required this.amount, required this.status, this.method, this.payAtClinic = false, this.refundDue = false});

  static VisitFee? of(Map<String, dynamic> appt) {
    final p = appt['payment'] is Map ? (appt['payment'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final fee = ((p['amount'] ?? appt['fee']) as num? ?? 0).round();
    final status = '${p['status'] ?? appt['feeStatus'] ?? 'pending'}';
    if (fee == 0 && status != 'paid') return VisitFee(amount: 0, status: 'free');
    return VisitFee(
      paymentId: p['id'] as String?,
      amount: fee,
      status: status,
      method: p['method'] as String?,
      payAtClinic: appt['payAt'] == 'clinic',
      refundDue: p['refundDue'] == true,
    );
  }

  bool get due => status == 'pending' && amount > 0 && paymentId != null;

  static const _how = {'online': 'online', 'cash': 'cash', 'upi': 'UPI', 'card': 'card', 'net_banking': 'net banking'};

  /// "₹600 paid online", "Collect ₹600 · pay at clinic", "Refund ₹600 due", "Free".
  (String, Color, Color) label(BuildContext context) {
    String t(String s) => tr(context, s).replaceFirst('#1', '$amount').replaceFirst('#2', tr(context, _how[method] ?? method ?? ''));
    if (refundDue) return (t('Refund ₹#1 due'), MP.redSoft, MP.red);
    return switch (status) {
      'paid' => (t('₹#1 paid · #2'), MP.greenSoft, MP.green),
      'refunded' => (t('₹#1 refunded'), MP.fill, MP.ink2),
      'free' || 'waived' => (tr(context, 'No fee'), MP.fill, MP.ink2),
      _ => (payAtClinic ? t('Collect ₹#1 · pay at clinic') : t('₹#1 not paid'), MP.amberSoft, MP.amber),
    };
  }
}

/// Small rounded fee chip for list rows.
class FeeChip extends StatelessWidget {
  final VisitFee fee;
  const FeeChip(this.fee, {super.key});

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = fee.label(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Ico(I.wallet, size: 13, color: fg, stroke: 2),
          const Gap(5),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(12, w: w600, c: fg, h: 1))),
        ],
      ),
    );
  }
}

/// "Collect ₹600": how it was paid (Cash / UPI / Card) → marked paid; the patient
/// gets a receipt. True when collected.
Future<bool> collectFee(BuildContext context, VisitFee fee, {String? patientName}) async {
  if (fee.paymentId == null) return false;
  final method = await openSheet<String>(
    context,
    (c) => MpSheet(
      title: tr(context, 'Collect ₹#1').replaceFirst('#1', '${fee.amount}'),
      subtitle: patientName == null ? 'How did the patient pay?' : tr(context, 'How did #1 pay?').replaceFirst('#1', patientName),
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VGap(
          gap: 8,
          children: [
            MpButton('Cash', onTap: () => Navigator.pop(c, 'cash')),
            MpButton('UPI', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'upi')),
            MpButton('Card', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'card')),
          ],
        ),
      ),
    ),
  );
  if (method == null || !context.mounted) return false;
  final ok = await runAction(context, () => Api.I.post('/api/payments/${fee.paymentId}/mark-paid', {'method': method}));
  if (ok == null || !context.mounted) return false;
  // Marked on the wrong patient? "Undo" (within 15 minutes; the screens refresh by themselves).
  final id = fee.paymentId;
  toast(context, tr(context, '₹#1 collected').replaceFirst('#1', '${fee.amount}'), action: tr(context, 'Undo'), onAction: () async {
    try {
      await Api.I.post('/api/payments/$id/undo-paid', const {});
      if (context.mounted) toast(context, tr(context, 'Undone · the fee is to collect again'));
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  });
  return true;
}

/// A cancelled visit paid at the desk: the money was handed back. True when marked.
Future<bool> handBackFee(BuildContext context, VisitFee fee) async {
  if (fee.paymentId == null) return false;
  // 'online': send the refund through Razorpay again; 'cash': handed back at the desk.
  final how = await openSheet<String>(
    context,
    (c) => MpSheet(
      title: tr(context, 'Refund ₹#1').replaceFirst('#1', '${fee.amount}'),
      subtitle: fee.method == 'online'
          ? 'The online refund didn’t go through. Try it again, or give the money back at the desk.'
          : 'The visit was cancelled. Mark it once you have handed the money back.',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VGap(
          gap: 8,
          children: [
            if (fee.method == 'online') MpButton('Refund online again', onTap: () => Navigator.pop(c, 'online')),
            MpButton('Handed back at the desk', kind: fee.method == 'online' ? MpBtn.secondary : MpBtn.primary, onTap: () => Navigator.pop(c, 'cash')),
          ],
        ),
      ),
    ),
  );
  if (how == null || !context.mounted) return false;
  final ok = await runAction(context, () => Api.I.post('/api/payments/${fee.paymentId}/refund', {'handedBack': how == 'cash'}));
  if (ok == null || !context.mounted) return false;
  toast(context, 'Refund recorded');
  return true;
}

/// The toast after "Send payment link" (POST /api/payments/:id/link → `sentTo`):
/// in the patient's MedPin app (and WhatsApp), or by SMS when they don't use the app.
String linkSentNote(BuildContext context, String patient, Object? res) {
  final to = res is Map ? res['sentTo'] : null;
  final s = to == 'sms' ? 'Payment link sent to #1 by SMS' : to == 'app' ? 'Payment link sent to #1 in the MedPin app' : 'Payment link sent to #1';
  return tr(context, s).replaceFirst('#1', patient);
}

/// The clinic's "please pay" message in the chat (a payment link sent by the desk or the
/// doctor): the amount and whether it's paid, live from the server. The patient pays right
/// there in the app; the doctor and desk see the same card turn "Paid".
class PaymentRequestCard extends StatefulWidget {
  /// The message's `payment`: {id, amount, status, method, appointmentId, url}.
  final Map<String, dynamic> payment;

  /// The patient's chat (shows Pay); the clinic's thread shows the status only.
  final bool forPatient;
  final VoidCallback? onPaid;
  const PaymentRequestCard({super.key, required this.payment, this.forPatient = false, this.onPaid});

  @override
  State<PaymentRequestCard> createState() => _PaymentRequestCardState();
}

class _PaymentRequestCardState extends State<PaymentRequestCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final amount = ((p['amount'] as num?) ?? 0).round();
    final status = '${p['status'] ?? 'pending'}';
    final paid = status == 'paid';
    final closed = !paid && status != 'pending'; // refunded / waived / cancelled
    final (bg, fg, label) = paid
        ? (MP.greenSoft, MP.green, tr(context, '₹#1 paid').replaceFirst('#1', '$amount'))
        : closed
            ? (MP.fill, MP.ink2, tr(context, status == 'refunded' ? '₹#1 refunded' : 'No payment needed').replaceFirst('#1', '$amount'))
            : (MP.amberSoft, MP.amber, tr(context, '₹#1 to pay').replaceFirst('#1', '$amount'));
    final canPay = widget.forPatient && !paid && !closed && '${p['appointmentId'] ?? ''}'.isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 310),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: MP.white, border: Border.all(color: MP.line), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Ico(paid ? I.check : I.wallet, size: 16, color: fg, stroke: 2),
                const Gap(8),
                Expanded(child: Text('Visit fee', style: tx(14, w: w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                  child: Text(label, style: tx(12, w: w600, c: fg, h: 1)),
                ),
              ],
            ),
            if (canPay) ...[
              const Gap(10),
              MpButton(
                tr(context, 'Pay ₹#1').replaceFirst('#1', '$amount'),
                onTap: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final ok = await Checkout.pay(context, kind: 'fee', id: '${p['appointmentId']}');
                        if (!mounted) return;
                        setState(() => _busy = false);
                        if (ok) widget.onPaid?.call();
                      },
              ),
            ] else if (!widget.forPatient && !paid && !closed) ...[
              const Gap(6),
              Text('Not paid yet · the card turns Paid when they pay', style: tx(12, c: MP.ink3, h: 1.35)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Add charge" on a visit: a dressing, an injection, an ECG… on top of the visit fee (added
/// to what is still to pay, or a new amount to collect). True when added.
/// POST /api/payments/extra.
Future<bool> addVisitCharge(BuildContext context, {required String appointmentId}) async {
  final added = await openSheet<bool>(context, (_) => _ChargeSheet(appointmentId: appointmentId));
  return added == true;
}

class _ChargeSheet extends StatefulWidget {
  final String appointmentId;
  const _ChargeSheet({required this.appointmentId});

  @override
  State<_ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends State<_ChargeSheet> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;
  static const _common = ['Dressing', 'Injection', 'ECG', 'Nebulisation', 'Blood sugar test', 'Procedure'];

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.trim());
    if (_label.text.trim().isEmpty) return toast(context, 'Say what the charge is for');
    if (amount == null || amount <= 0) return toast(context, 'Enter the amount in rupees');
    setState(() => _busy = true);
    final ok = await runAction(context, () => Api.I.post('/api/payments/extra', {'appointmentId': widget.appointmentId, 'label': _label.text.trim(), 'amount': amount}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == null) return;
    toast(context, tr(context, '₹#1 added to the bill').replaceFirst('#1', '$amount'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Add charge',
      subtitle: 'On top of the visit fee. The patient pays it with the fee.',
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _common) MpChip(c, selected: _label.text == c, onTap: () => setState(() => _label.text = c)),
          ]),
          const SizedBox(height: 12),
          MpInput(controller: _label, label: 'What for', hint: 'E.g. Dressing', height: 52, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          MpInput(controller: _amount, label: 'Amount', prefixText: '₹ ', hint: 'E.g. 200', keyboard: TextInputType.number, height: 52),
          const SizedBox(height: 16),
          MpButton(_busy ? 'Adding…' : 'Add to the bill', onTap: _busy ? null : _save),
        ],
      ),
    );
  }
}

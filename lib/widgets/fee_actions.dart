import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
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
  toast(context, tr(context, '₹#1 collected').replaceFirst('#1', '${fee.amount}'));
  return true;
}

/// A cancelled visit paid at the desk: the money was handed back. True when marked.
Future<bool> handBackFee(BuildContext context, VisitFee fee) async {
  if (fee.paymentId == null) return false;
  final yes = await openSheet<bool>(
    context,
    (c) => MpSheet(
      title: tr(context, 'Refund ₹#1').replaceFirst('#1', '${fee.amount}'),
      subtitle: fee.method == 'online'
          ? 'The online refund didn’t go through. Try it again now.'
          : 'The visit was cancelled. Mark it once you have handed the money back.',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: MpButton(fee.method == 'online' ? 'Refund now' : 'Handed back', onTap: () => Navigator.pop(c, true)),
      ),
    ),
  );
  if (yes != true || !context.mounted) return false;
  final ok = await runAction(context, () => Api.I.post('/api/payments/${fee.paymentId}/refund', {'handedBack': fee.method != 'online'}));
  if (ok == null || !context.mounted) return false;
  toast(context, 'Refund recorded');
  return true;
}

import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../widgets/i18n.dart';
import '../widgets/mp.dart';
import 'api.dart';
import 'format.dart';

/// How an in-app payment ended (Checkout.payOutcome).
enum PayOutcome { paid, later, notPaid, unconfirmed }

/// In-app payments (Razorpay Checkout) for a visit fee or a medicine order.
///
/// 1. POST /api/patient/checkout {kind, id}: what is due and a Razorpay order.
/// 2. MedPin's "Pay ₹…" sheet: what it's for, the ways to pay, Pay.
/// 3. Razorpay Checkout opens over the app with every method the account
///    has on (UPI apps and UPI ID, cards, net banking, wallets, pay later, EMI).
/// 4. POST /api/patient/checkout/confirm with Razorpay's signed result; the
///    server checks the signature before anything is marked paid.
/// 5. A "Payment successful" sheet with the reference.
///
/// Without Razorpay keys (development only) step 3 is a clearly marked test
/// checkout and no money moves.
class Checkout {
  Checkout._();

  /// kind: 'fee' (id = the appointment) or 'order' (id = the medicine order).
  /// [laterLabel]: a second choice on the sheet ("Pay at the clinic"); picking
  /// it returns false without paying. Returns true once paid.
  ///
  /// [optional]: offered right after booking; if the clinic only takes cash
  /// or nothing is due, return quietly instead of showing an error.
  static Future<bool> pay(BuildContext context, {required String kind, required String id, String? laterLabel, bool optional = false}) async =>
      await payOutcome(context, kind: kind, id: id, laterLabel: laterLabel, optional: optional) == PayOutcome.paid;

  /// How it went: paid; the patient chose [laterLabel] ("Pay at the clinic"); closed or
  /// failed (nothing charged); or charged but not confirmed yet (the server checks it —
  /// never treated as "pay at the clinic", so nobody is asked to pay twice).
  static Future<PayOutcome> payOutcome(BuildContext context, {required String kind, required String id, String? laterLabel, bool optional = false}) async {
    Object? start;
    try {
      start = await Api.I.post('/api/patient/checkout', {'kind': kind, 'id': id});
    } on ApiException catch (e) {
      const skip = {'ONLINE_PAY_OFF', 'NOT_PENDING', 'NOTHING_DUE', 'PAYMENTS_OFF'};
      if (context.mounted && !(optional && skip.contains(e.code))) toast(context, e.message);
      // Online pay isn't possible here: the fee is paid at the clinic (as the patient was going to).
      return skip.contains(e.code) && optional ? PayOutcome.later : PayOutcome.notPaid;
    }
    if (start is! Map || !context.mounted) return PayOutcome.notPaid;
    final info = start.cast<String, dynamic>();
    final go = await openSheet<bool>(context, (_) => _PaySheet(info: info, laterLabel: laterLabel));
    if (!context.mounted) return PayOutcome.notPaid;
    if (go == false) return PayOutcome.later; // tapped "Pay at the clinic"
    if (go != true) return PayOutcome.notPaid; // closed the sheet

    final _Result? result;
    if (info['test'] == true) {
      result = await _testCheckout(context, info);
    } else {
      result = await _razorpay(info);
    }
    if (!context.mounted || result == null) return PayOutcome.notPaid;
    final r = result;
    if (r.error != null) {
      toast(context, r.error!);
      return PayOutcome.notPaid;
    }
    // Razorpay took the money: confirm it with MedPin (a few tries on a weak network).
    Map? done;
    for (var i = 0; i < 3 && done == null; i++) {
      try {
        final res = await Api.I.post('/api/patient/checkout/confirm', {
          'kind': kind,
          'id': id,
          'orderId': r.orderId,
          if (r.paymentId != null) 'paymentId': r.paymentId,
          if (r.signature != null) 'signature': r.signature,
        });
        done = res is Map ? res : const {};
      } on ApiException catch (e) {
        if (!e.isNetwork) {
          if (context.mounted) toast(context, e.message);
          return PayOutcome.notPaid;
        }
        await Future<void>.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    if (!context.mounted) return PayOutcome.unconfirmed;
    if (done == null) {
      toast(context, "We're checking your payment with the bank. It will show as paid in a few minutes — no need to pay again.");
      return PayOutcome.unconfirmed;
    }
    // Already paid another way meanwhile: this payment is being refunded.
    if (done['refunded'] == true) {
      toast(context, '${done['message'] ?? 'This was already paid, so your payment is being refunded.'}');
      return PayOutcome.paid;
    }
    await openSheet<void>(context, (_) => _PaidSheet(info: info, reference: done!['paymentId'] as String?));
    return PayOutcome.paid;
  }

  /// Razorpay Checkout over the app; completes when it closes.
  static Future<_Result?> _razorpay(Map<String, dynamic> info) {
    final done = Completer<_Result?>();
    final rp = Razorpay();
    void finish(_Result? r) {
      if (!done.isCompleted) done.complete(r);
      rp.clear();
    }

    rp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(_Result(orderId: r.orderId ?? info['orderId'] as String, paymentId: r.paymentId, signature: r.signature));
    });
    rp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      finish(_Result.failed(r.code == Razorpay.PAYMENT_CANCELLED
          ? 'Payment cancelled. Nothing was charged.'
          : r.code == Razorpay.NETWORK_ERROR
              ? 'No internet connection. Nothing was charged; please try again.'
              : 'The payment didn’t go through. Nothing was charged; please try again.'));
    });
    rp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      finish(_Result.failed('Finish paying in ${r.walletName ?? 'your wallet app'}, then come back.'));
    });
    final prefill = (info['prefill'] as Map?)?.cast<String, dynamic>() ?? const {};
    try {
      rp.open({
        'key': info['keyId'],
        'order_id': info['orderId'],
        'amount': ((info['amount'] as num) * 100).round(),
        'currency': info['currency'] ?? 'INR',
        'name': 'MedPin',
        'description': [info['title'], info['detail']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        'prefill': {if (prefill['contact'] != null) 'contact': prefill['contact'], if (prefill['name'] != null) 'name': prefill['name']},
        'theme': {'color': '#003399'},
        'retry': {'enabled': true, 'max_count': 3},
        'send_sms_hash': true,
        'remember_customer': false,
        'readonly': {'contact': prefill['contact'] != null},
      });
    } catch (_) {
      finish(_Result.failed('Couldn’t open the payment screen. Please try again.'));
    }
    return done.future;
  }

  /// Development only (no Razorpay keys): a stand-in that looks like the real
  /// thing, says so, and lets the flow finish.
  static Future<_Result?> _testCheckout(BuildContext context, Map<String, dynamic> info) async {
    final ok = await openSheet<bool>(context, (_) => _TestCheckoutSheet(info: info));
    return ok == true ? _Result(orderId: info['orderId'] as String) : _Result.failed('Payment cancelled. Nothing was charged.');
  }
}

class _Result {
  final String? orderId;
  final String? paymentId;
  final String? signature;
  final String? error;
  const _Result({required this.orderId, this.paymentId, this.signature}) : error = null;
  const _Result.failed(this.error)
      : orderId = null,
        paymentId = null,
        signature = null;
}

String _rupees(num n) => n == n.roundToDouble() ? '₹${n.toInt()}' : '₹${n.toStringAsFixed(2)}';

/// The ways to pay shown on the sheet (Razorpay offers all of them).
const _ways = [
  (I.phone, 'UPI', 'Google Pay, PhonePe, Paytm, BHIM or any UPI ID'),
  (I.creditCard, 'Cards', 'Debit and credit cards, RuPay, Visa, Mastercard'),
  (I.home, 'Net banking', 'All major Indian banks'),
  (I.wallet, 'Wallets and pay later', 'Paytm, Mobikwik, Amazon Pay, Simpl, LazyPay'),
];

/// "Pay ₹600": what it's for, how you can pay, Pay / Pay later.
class _PaySheet extends StatelessWidget {
  final Map<String, dynamic> info;
  final String? laterLabel;
  const _PaySheet({required this.info, this.laterLabel});

  @override
  Widget build(BuildContext context) {
    final amount = info['amount'] as num;
    final when = F.date(info['when']);
    final detail = [info['detail'] as String?, if (when != null) F.when(when)].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info['test'] == true) ...[
            Align(alignment: Alignment.centerLeft, child: _Badge('Test mode · no money moves', fg: MP.amber, bg: MP.amberSoft)),
            const Gap(12),
          ],
          Text(info['title'] as String? ?? 'Payment', style: tx(15, w: w600, c: MP.ink2)),
          const Gap(2),
          Text(_rupees(amount), style: tx(36, w: w800, h: 1.15, em: -0.02, tab: true)),
          if (detail.isNotEmpty) ...[const Gap(4), Text(detail, style: tx(14, c: MP.ink2, h: 1.4))],
          const Gap(20),
          Container(
            decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
            child: Column(
              children: [
                for (var i = 0; i < _ways.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 60, color: MP.line),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: Ico(_ways[i].$1, size: 18, color: MP.primary),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_ways[i].$2, style: tx(15, w: w600)),
                              Text(_ways[i].$3, style: tx(13, c: MP.ink2, h: 1.35)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(20),
          MpButton('Pay ${_rupees(amount)}', onTap: () => Navigator.pop(context, true)),
          if (laterLabel != null) ...[
            const Gap(8),
            MpButton(laterLabel!, kind: MpBtn.secondary, onTap: () => Navigator.pop(context, false)),
          ],
          const Gap(14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Ico(I.lock, size: 14, color: MP.ink3),
              const Gap(6),
              Flexible(child: Text('Secured by Razorpay · MedPin never sees your card or UPI PIN', textAlign: TextAlign.center, style: tx(12, c: MP.ink3, h: 1.4))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Development stand-in for Razorpay Checkout.
class _TestCheckoutSheet extends StatefulWidget {
  final Map<String, dynamic> info;
  const _TestCheckoutSheet({required this.info});

  @override
  State<_TestCheckoutSheet> createState() => _TestCheckoutSheetState();
}

class _TestCheckoutSheetState extends State<_TestCheckoutSheet> {
  int _way = 0;

  @override
  Widget build(BuildContext context) {
    final amount = widget.info['amount'] as num;
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Test checkout', style: tx(20, w: w700, h: 1.25))),
              _Badge('No money moves', fg: MP.amber, bg: MP.amberSoft),
            ],
          ),
          const Gap(6),
          Text(
            'Razorpay isn’t connected on this server yet, so this stands in for its payment screen. With Razorpay keys, the real one opens here.',
            style: tx(14, c: MP.ink2, h: 1.45),
          ),
          const Gap(16),
          for (var i = 0; i < _ways.length; i++) ...[
            if (i > 0) const Gap(8),
            MpHitSlop(
              child: Semantics(
                selected: i == _way,
                button: true,
                child: Tap(
                  onTap: () => setState(() => _way = i),
                  radius: 14,
                  color: i == _way ? MP.primarySoft : MP.white,
                  border: i == _way ? MP.primary : MP.line,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Ico(_ways[i].$1, size: 18, color: i == _way ? MP.primary : MP.ink2),
                      const Gap(12),
                      Expanded(child: Text(_ways[i].$2, style: tx(15, w: w600))),
                      if (i == _way) const Ico(I.check, size: 18, color: MP.primary, stroke: 2.5),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const Gap(20),
          MpButton('Pay ${_rupees(amount)} (test)', onTap: () => Navigator.pop(context, true)),
          const Gap(8),
          MpButton('Cancel', kind: MpBtn.secondary, onTap: () => Navigator.pop(context, false)),
        ],
      ),
    );
  }
}

/// "Payment successful ✓ ₹600" with the reference.
class _PaidSheet extends StatelessWidget {
  final Map<String, dynamic> info;
  final String? reference;
  const _PaidSheet({required this.info, this.reference});

  @override
  Widget build(BuildContext context) {
    final amount = info['amount'] as num;
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: MP.greenSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Ico(I.check, size: 32, color: MP.green, stroke: 2.5),
            ),
          ),
          const Gap(16),
          Text('Payment successful', textAlign: TextAlign.center, style: tx(22, w: w700, h: 1.25)),
          const Gap(4),
          Text('${_rupees(amount)} · ${info['title'] ?? ''}', textAlign: TextAlign.center, style: tx(16, w: w600, h: 1.4, tab: true)),
          if ((info['detail'] as String?)?.isNotEmpty ?? false) ...[
            const Gap(2),
            Text(info['detail'] as String, textAlign: TextAlign.center, style: tx(14, c: MP.ink2, h: 1.4)),
          ],
          if (reference != null) ...[
            const Gap(12),
            Text('Reference $reference', textAlign: TextAlign.center, style: tx(13, c: MP.ink3, tab: true)),
          ],
          const Gap(20),
          MpButton('Done', onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Badge(this.text, {required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: tx(12, w: w700, c: fg)),
      );
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: Billing.dc.html — "Plan & billing".
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

// (label, used, cap, used text, cap text)
const _meters = [
  ('Seats', 7, 8, '7', '8'),
  ('Active patients', 412, 500, '412', '500'),
  ('AI chats this month', 1860, 3000, '1,860', '3,000'),
];

const _invoices = ['14 Sep 2026', '14 Aug 2026', '14 Jul 2026'];
const _olderInvoices = ['14 Jun 2026', '14 May 2026', '14 Apr 2026'];

// (name, price, features, note)
const List<(String, String, String, String?)> _plans = [
  (
    'Starter',
    '₹999',
    '3 seats · 150 active patients · 1,000 AI chats a month',
    'Your team has 7 people, so 4 would need to be removed first',
  ),
  ('Clinic', '₹2,499', '8 seats · 500 active patients · 3,000 AI chats a month', null),
  ('Hospital', '₹7,999', '25 seats · 2,000 active patients · 12,000 AI chats a month', null),
];
const _currentPlan = 'Clinic';

class _BillingScreenState extends State<BillingScreen> {
  bool _allInvoices = false;

  void _switchTo(String plan, String? note) {
    toast(context, note != null ? 'Remove 4 people first' : 'Switching to $plan on 14 Oct 2026');
  }

  @override
  Widget build(BuildContext context) {
    final invoices = [..._invoices, if (_allInvoices) ..._olderInvoices];
    return MpPage(
      header: const MpHeader('Plan & billing'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          // Current plan (hero)
          D9Card(
            radius: 20,
            shadow: MPShadow.float,
            gap: 12,
            children: [
              const D9Label('Current plan', h: 1.35),
              Row(
                children: [
                  Expanded(child: Text('Clinic plan', style: tx(20, w: w700, h: 1.25))),
                  const Gap(12),
                  const MpBadge.green('Active', weight: w600),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const D9Big('₹2,499', suffix: ' / month'),
                  const Gap(8),
                  Text('Renews 14 Oct 2026', style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
                ],
              ),
            ],
          ),

          // Usage
          D9Card(
            gap: 20,
            children: [
              const D9Head('Usage', sub: 'This billing cycle · resets 14 Oct 2026', subH: 1.45, subTab: true),
              for (final m in _meters) _Meter(m),
            ],
          ),

          // Billing history
          D9Card(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(child: Text('Billing history', style: tx(20, w: w700, h: 1.25))),
                    const Gap(12),
                    D9Link(
                      _allInvoices ? 'Show less' : 'View all',
                      h: null,
                      onTap: () => setState(() => _allInvoices = !_allInvoices),
                    ),
                  ],
                ),
              ),
              for (final d in invoices) _InvoiceRow(d),
            ],
          ),

          // Plans
          D9Card(
            children: [
              const D9Head('Plans', sub: 'Changes apply from your next billing cycle', subH: 1.45, bottom: 12),
              for (final p in _plans)
                D9Row(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _PlanRow(p, onSwitch: () => _switchTo(p.$1, p.$4)),
                ),
              Container(
                padding: const EdgeInsets.only(top: 14),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Row(
                  children: [
                    const Ico(I.lock, size: 16, color: MP.ink3),
                    const Gap(8),
                    Expanded(child: Text('Secure checkout via Razorpay', style: tx(13, c: MP.ink3, h: 1.4))),
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

class _Meter extends StatelessWidget {
  final (String, int, int, String, String) m;
  const _Meter(this.m);

  @override
  Widget build(BuildContext context) {
    final (label, used, cap, usedText, capText) = m;
    final pct = (used / cap * 100).round();
    return Semantics(
      label: '$label: $usedText of $capText used',
      value: '$pct%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(label, style: tx(15, w: w600, h: 1.45))),
              const Gap(12),
              Text.rich(
                TextSpan(
                  style: tx(14, c: MP.ink2, h: 1.45, tab: true),
                  children: [
                    TextSpan(text: usedText, style: tx(14, w: w600, c: MP.ink, h: 1.45, tab: true)),
                    TextSpan(text: ' of $capText'),
                  ],
                ),
              ),
            ],
          ),
          const Gap(8),
          MpProgress(pct / 100, height: 6, color: pct >= 90 ? MP.amber : MP.primary),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final String date;
  const _InvoiceRow(this.date);

  @override
  Widget build(BuildContext context) {
    return D9Row(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: tx(16, w: w600, h: 1.5, tab: true)),
                const Gap(2),
                Text('Clinic plan · monthly', style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
          ),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹2,499', style: tx(16, w: w600, h: 1.5, tab: true)),
              const Gap(4),
              const MpBadge.green('Paid', weight: w600),
            ],
          ),
          const Gap(12),
          MpIconButton(
            I.download,
            label: 'Download invoice for $date',
            color: MP.primary,
            iconSize: 20,
            onTap: () => toast(context, 'Invoice downloaded'),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final (String, String, String, String?) plan;
  final VoidCallback onSwitch;
  const _PlanRow(this.plan, {required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final (name, price, features, note) = plan;
    final current = name == _currentPlan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(name, style: tx(16, w: w600, h: 1.5)),
            if (current) ...[const Gap(8), const MpBadge.blue('Current', weight: w600)],
            const Gap(8),
            const Spacer(),
            Text.rich(
              TextSpan(
                text: price,
                style: tx(16, w: w600, h: 1.5, tab: true),
                children: [TextSpan(text: ' / month', style: tx(14, c: MP.ink2, h: 1.5))],
              ),
            ),
          ],
        ),
        const Gap(4),
        Text(features, style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
        if (note != null) ...[const Gap(4), Text(note, style: tx(13, c: MP.ink3, h: 1.4))],
        if (!current) ...[
          // gap 4 + margin-top 8
          const Gap(12),
          Semantics(
            label: 'Switch to $name plan',
            child: MpButton.small('Switch plan', expand: false, onTap: onSwitch),
          ),
        ],
      ],
    );
  }
}

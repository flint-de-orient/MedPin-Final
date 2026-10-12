import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';
import '../../widgets/i18n.dart';

/// Design: Billing.dc.html — "Plan & billing".
/// Live data: GET /api/billing (`?invoices=50` for "View all"); actions:
/// POST /api/billing/switch, GET /api/billing/invoices/:id/download.
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

// (date, description, amount, status, invoice id)
typedef _Invoice = (String, String, String, String, String?);

class _BillingScreenState extends State<BillingScreen> with LiveData {
  bool _allInvoices = false;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() => Api.I.get('/api/billing', query: {'invoices': _allInvoices ? 50 : null});

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _sub => data!.obj('subscription');
  Map<String, dynamic> get _plan => data!.obj('plan');

  String _date(Object? iso) {
    final d = F.date(iso);
    return d == null ? '' : D9Fmt.date(d);
  }

  String get _planName => data == null ? 'Clinic' : _plan.str('name', _sub.str('planKey'));

  (String, Color, Color) get _status {
    final s = data == null ? 'active' : _sub.str('status', 'active');
    return switch (s) {
      'trialing' => ('Trial', MP.primarySoft, MP.primary),
      'past_due' => ('Payment due', MP.amberSoft, MP.amber),
      'cancelled' => ('Cancelled', MP.fill, MP.ink2),
      _ => ('Active', MP.greenSoft, MP.green),
    };
  }

  String get _price => data == null ? '₹2,499' : D9Fmt.money(_sub.numOr('price', _plan.numOr('priceMonthly')));

  String get _renews {
    if (data == null) return 'Renews 14 Oct 2026';
    final end = _date(_sub['currentPeriodEnd']);
    final pendingKey = _sub.str('pendingPlanKey');
    final pending = data!.list('plans').where((p) => p['key'] == pendingKey).map((p) => p.str('name')).firstOrNull;
    if (end.isEmpty) return '';
    if (_sub.str('status') == 'cancelled') return 'Ends $end';
    return pending == null ? 'Renews $end' : 'Renews $end on the $pending plan';
  }

  String get _usageSub {
    if (data == null) return 'This billing cycle · resets 14 Oct 2026';
    final reset = _date(data!.obj('usage')['resetsAt']);
    return reset.isEmpty ? 'This billing cycle' : 'This billing cycle · resets $reset';
  }

  List<(String, int, int, String, String)> get _liveMeters {
    if (data == null) return _meters;
    final u = data!.obj('usage');
    (String, int, int, String, String) m(String label, Map<String, dynamic> x) {
      final used = x.numOr('used').toInt();
      final cap = x.numOr('limit').toInt();
      return (label, used, cap, F.count(used), x['limit'] == null ? '—' : F.count(cap));
    }

    return [
      m('Seats', u.obj('seats')),
      m('Active patients', u.obj('activePatients')),
      m('AI chats this month', u.obj('aiChats')),
    ];
  }

  List<_Invoice> get _invoiceRows {
    if (data == null) {
      return [
        for (final d in [..._invoices, if (_allInvoices) ..._olderInvoices]) (d, 'Clinic plan · monthly', '₹2,499', 'paid', null),
      ];
    }
    return [
      for (final i in data!.list('invoices'))
        (_date(i['issuedAt']), i.str('description'), D9Fmt.money(i.numOr('amount')), i.str('status'), i['id'] as String?),
    ];
  }

  /// (name, price, features, note, key)
  List<(String, String, String, String?, String)> get _planRows {
    if (data == null) return [for (final p in _plans) (p.$1, p.$2, p.$3, p.$4, p.$1)];
    final team = data!.obj('usage').obj('seats').numOr('used').toInt();
    return [
      for (final p in data!.list('plans'))
        (
          p.str('name'),
          D9Fmt.money(p.numOr('priceMonthly')),
          '${D9Fmt.plural(p.numOr('seats'), 'seat')} · ${F.count(p.numOr('activePatients'))} active patients · '
              '${F.count(p.numOr('aiChatsPerMonth'))} AI chats a month',
          team > p.numOr('seats')
              ? 'Your team has $team people, so ${team - p.numOr('seats').toInt()} would need to be removed first'
              : null,
          p.str('key'),
        ),
    ];
  }

  String get _currentKey => data == null ? _currentPlan : _sub.str('planKey');

  Future<void> _switchTo(String plan, String? note, String key) async {
    if (!isLive) {
      toast(context, note != null ? 'Remove 4 people first' : 'Switching to $plan on 14 Oct 2026');
      return;
    }
    final res = await runAction(context, () => Api.I.post('/api/billing/switch', {'planKey': key}), busy: _busy);
    if (res is! Map || !mounted) return;
    if (res['checkoutUrl'] is String) {
      // Paid upgrade: the plan changes once the payment goes through.
      await D9Open.url(context, res['checkoutUrl'], failed: "Couldn't open the payment page");
      if (mounted) toast(context, 'Your plan changes to $plan as soon as the payment is done');
      return;
    }
    final from = _date(res['pendingFrom']);
    toast(context, res['planKey'] == key || from.isEmpty ? 'Switched to the $plan plan' : 'Switching to $plan on $from');
    reload(quiet: true);
  }

  Future<void> _download(String? id) async {
    if (!isLive || id == null) {
      toast(context, 'Invoice downloaded');
      return;
    }
    final res = await runAction(context, () => Api.I.get('/api/billing/invoices/$id/download'), busy: _busy);
    if (res is! Map || !mounted) return;
    await D9Open.url(context, res['url'], failed: "Couldn't open the invoice");
  }

  void _toggleInvoices() {
    setState(() => _allInvoices = !_allInvoices);
    if (isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final invoices = _invoiceRows;
    final status = _status;
    final renews = _renews;
    return MpPage(
      header: const MpHeader('Plan & billing'),
      body: placeholder ?? VGap(
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
                  Expanded(child: Text('$_planName plan', style: tx(20, w: w700, h: 1.25))),
                  const Gap(12),
                  MpBadge(status.$1, bg: status.$2, fg: status.$3, weight: w600),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  D9Big(_price, suffix: data != null && _sub.str('interval') == 'yearly' ? ' / year' : ' / month'),
                  if (renews.isNotEmpty) ...[
                    const Gap(8),
                    Text(renews, style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
                  ],
                ],
              ),
            ],
          ),

          // Usage
          D9Card(
            gap: 20,
            children: [
              D9Head('Usage', sub: _usageSub, subH: 1.45, subTab: true),
              for (final m in _liveMeters) _Meter(m),
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
                      onTap: _toggleInvoices,
                    ),
                  ],
                ),
              ),
              for (final d in invoices) _InvoiceRow(d, onDownload: () => _download(d.$5)),
              if (invoices.isEmpty) Text('No invoices yet', style: tx(14, c: MP.ink2)),
            ],
          ),

          // Plans
          D9Card(
            children: [
              const D9Head('Plans', sub: 'Changes apply from your next billing cycle', subH: 1.45, bottom: 12),
              for (final p in _planRows)
                D9Row(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _PlanRow(
                    (p.$1, p.$2, p.$3, p.$4),
                    current: p.$5 == _currentKey,
                    onSwitch: () => _switchTo(p.$1, p.$4, p.$5),
                  ),
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
    final pct = cap <= 0 ? 0 : (used / cap * 100).round().clamp(0, 100);
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
  final _Invoice invoice;
  final VoidCallback onDownload;
  const _InvoiceRow(this.invoice, {required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final (date, description, amount, status, _) = invoice;
    final (bg, fg) = switch (status) {
      'paid' => (MP.greenSoft, MP.green),
      'refunded' => (MP.fill, MP.ink2),
      'failed' => (MP.redSoft, MP.red),
      _ => (MP.amberSoft, MP.amber),
    };
    final statusLabel = status.isEmpty ? '' : '${status[0].toUpperCase()}${status.substring(1)}';
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
                Text(description, style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
          ),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: tx(16, w: w600, h: 1.5, tab: true)),
              const Gap(4),
              MpBadge(statusLabel, bg: bg, fg: fg, weight: w600),
            ],
          ),
          const Gap(12),
          MpIconButton(
            I.download,
            label: 'Download invoice for $date',
            color: MP.primary,
            iconSize: 20,
            onTap: onDownload,
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final (String, String, String, String?) plan;
  final VoidCallback onSwitch;
  final bool current;
  const _PlanRow(this.plan, {required this.current, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final (name, price, features, note) = plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600, h: 1.5))),
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

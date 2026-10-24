import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/checkout.dart';
import '../../data/downloads.dart';
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

  String get _planName {
    if (data == null) return 'Clinic';
    final key = _sub.str('planKey');
    return _plan.str('name', key.isEmpty ? '' : '${key[0].toUpperCase()}${key.substring(1)}');
  }

  Map<String, dynamic> get _renewal => data == null ? const {} : data!.obj('renewal');

  /// "City Care Clinic LLP · GSTIN 19AAACC1234C1Z5" (empty: nothing added yet).
  String get _billing {
    final b = data?.obj('billingDetails') ?? const <String, dynamic>{};
    return [b.str('name'), if (b.str('gstin').isNotEmpty) 'GSTIN ${b.str('gstin')}' else if (b.str('state').isNotEmpty) b.str('state')].where((s) => s.isNotEmpty).join(' · ');
  }

  /// The owner (or manager) pays and switches plans; others see the plan.
  bool get _canManage => data == null || data!['canManage'] != false;

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
    return switch (_sub.str('status')) {
      'cancelled' => 'Ends $end',
      'past_due' => trf(context, _renewal['trialEnded'] == true ? 'Free trial ended {date}' : 'Paid until {date} · the next month is due', {'date': end}),
      'trialing' => trf(context, 'Free trial until {date}', {'date': end}),
      _ => pending == null ? trf(context, 'Paid until {date}', {'date': end}) : trf(context, 'Paid until {date} · then the {plan} plan', {'date': end, 'plan': pending}),
    };
  }

  String get _usageSub {
    if (data == null) return 'This billing cycle · resets 14 Oct 2026';
    final reset = _date(data!.obj('usage')['resetsAt']);
    if (_sub.str('status') == 'past_due') return 'Since the last month began · resets when the next month is paid';
    return reset.isEmpty ? 'This billing cycle' : 'This billing cycle · resets $reset';
  }

  List<(String, int, int, String, String)> get _liveMeters {
    if (data == null) return _meters;
    final u = data!.obj('usage');
    (String, int, int, String, String) m(String label, Map<String, dynamic> x) {
      final used = x.numOr('used').toInt();
      final cap = x.numOr('limit').toInt();
      return (label, used, cap, F.count(used), x['limit'] == null ? '' : F.count(cap));
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
        (_date(i['issuedAt']), [i.str('number'), i.str('description')].where((s) => s.isNotEmpty).join(' · '), D9Fmt.money(i.numOr('amount')), i.str('status'), i['id'] as String?),
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
    if (res['awaitingPayment'] == true) {
      // A bigger plan starts once paid: Razorpay Checkout in the app (UPI, card, net banking).
      final paid = await Checkout.payPlan(context, planKey: '${res['payPlanKey'] ?? key}');
      if (paid && mounted) toast(context, trf(context, 'You are on the {plan} plan now', {'plan': plan}));
      if (mounted) reload(quiet: true);
      return;
    }
    if (res['checkoutUrl'] is String) {
      await D9Open.url(context, res['checkoutUrl'], failed: "Couldn't open the payment page");
      if (mounted) toast(context, 'Your plan changes to $plan as soon as the payment is done');
      return;
    }
    final from = _date(res['pendingFrom']);
    toast(context, res['planKey'] == key || from.isEmpty ? 'Switched to the $plan plan' : 'Switching to $plan on $from');
    reload(quiet: true);
  }

  /// Pay for the next month (due, or ending within 7 days): the payment page opens.
  Future<void> _renew() async {
    if (!isLive) {
      toast(context, 'Paid · your plan is renewed');
      return;
    }
    // In the app (Razorpay Checkout): the plan moves on as soon as Razorpay confirms it.
    _busy.value = true;
    try {
      final paid = await Checkout.payPlan(context, renew: true);
      if (paid && mounted) toast(context, 'Paid · your plan is renewed');
    } finally {
      _busy.value = false;
    }
    if (mounted) reload(quiet: true);
  }

  /// Paid by a link (or the app closed during payment) but still shows due: ask Razorpay now.
  Future<void> _checkPayment() async {
    final res = await runAction(context, () => Api.I.post('/api/billing/check-payment', const {}), busy: _busy);
    if (res is! Map || !mounted) return;
    toast(context, (res['applied'] as num? ?? 0) > 0 ? 'Payment found · your plan is renewed' : 'No payment found yet. If money was taken, it shows here within 15 minutes.');
    reload(quiet: true);
  }

  Widget _renewCard() {
    final r = _renewal;
    final due = r['due'] == true;
    final amount = D9Fmt.money(r.numOr('amount'));
    final plan = r.str('planName', _planName);
    return D9Card(
      gap: 12,
      children: [
        Row(
          children: [
            Expanded(child: Text(due ? (r['trialEnded'] == true ? 'Your free trial has ended' : 'Payment due') : 'Pay for next month', style: tx(18, w: w700, h: 1.3))),
            if (due) const MpBadge('Due', bg: MP.amberSoft, fg: MP.amber, weight: w600),
          ],
        ),
        Text(
          due
              ? trf(context, 'Pay {amount} for a month of the {plan} plan. It starts the day you pay. Nothing is switched off meanwhile.', {'amount': amount, 'plan': plan})
              : trf(context, 'Pay {amount} now and the next month of the {plan} plan starts on {date}.', {'amount': amount, 'plan': plan, 'date': _date(r['from'])}),
          style: tx(14, c: MP.ink2, h: 1.45),
        ),
        if (_canManage) ...[
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, _) => MpButton(trf(context, 'Pay {amount}', {'amount': amount}), onTap: busy ? null : _renew),
          ),
          if (isLive) Center(child: D9Link('Already paid? Check payment', h: null, onTap: _checkPayment)),
        ] else
          Text('Ask the clinic owner to pay.', style: tx(14, w: w600, c: MP.ink2, h: 1.45)),
      ],
    );
  }

  /// Download: the invoice PDF is made, then saved to Downloads › MedPin with its number
  /// ("MedPin-Invoice-MP-26-27-0001.pdf"), with "Saved · Open"; Share sends it (to an accountant).
  Future<void> _download(String? id, {bool share = false}) async {
    if (!isLive || id == null) {
      toast(context, 'Invoice downloaded');
      return;
    }
    toast(context, 'Getting the invoice ready…');
    final res = await runAction(context, () => Api.I.get('/api/billing/invoices/$id/download'), busy: _busy);
    if (res is! Map || !mounted) return;
    final name = res['name'] as String?;
    if (share) {
      await Downloads.share(context, res['url'] as String?, name: name);
    } else {
      await Downloads.save(context, res['url'] as String?, name: name, title: 'Invoice downloaded');
    }
  }

  Future<void> _invoiceActions(String? id, String label) async {
    final pick = await openSheet<String>(
      context,
      (c) => MpSheet(
        title: label,
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: VGap(
            gap: 8,
            children: [
              MpButton('Download PDF', onTap: () => Navigator.pop(c, 'download')),
              MpButton('Share', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'share')),
            ],
          ),
        ),
      ),
    );
    if (pick != null && mounted) await _download(id, share: pick == 'share');
  }

  /// Billing details: who the invoices are made out to (for the clinic's accounts and GST).
  Future<void> _editDetails() async {
    if (!isLive) return;
    final saved = await openSheet<bool>(context, (_) => const _DetailsSheet());
    if (saved == true && mounted) {
      toast(context, 'Billing details saved · they show on your invoices');
      reload(quiet: true);
    }
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

          if (data != null && _renewal['canPay'] == true) _renewCard(),

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
                    if (_allInvoices || data == null || data!.numOr('invoicesTotal') > invoices.length)
                      D9Link(
                        _allInvoices ? 'Show less' : 'View all',
                        h: null,
                        onTap: _toggleInvoices,
                      ),
                  ],
                ),
              ),
              for (final d in invoices) _InvoiceRow(d, onDownload: () => _download(d.$5), onMore: () => _invoiceActions(d.$5, d.$2.split(' · ').first)),
              if (invoices.isEmpty) Text('No invoices yet', style: tx(14, c: MP.ink2)),
            ],
          ),

          // Billing details (owner / manager): the name, address and GSTIN on the invoices.
          if (data != null && _canManage)
            D9Card(
              children: [
                D9Head(
                  'Billing details',
                  sub: _billing.isEmpty ? 'Add your clinic\'s legal name, address and GSTIN for your invoices' : _billing,
                  subH: 1.45,
                  trailing: D9Link(_billing.isEmpty ? 'Add' : 'Edit', h: null, onTap: _editDetails),
                ),
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
                    onSwitch: _canManage ? () => _switchTo(p.$1, p.$4, p.$5) : null,
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
                    if (capText.isNotEmpty) TextSpan(text: ' of $capText'),
                  ],
                ),
              ),
            ],
          ),
          if (capText.isNotEmpty) ...[
            const Gap(8),
            MpProgress(pct / 100, height: 6, color: pct >= 90 ? MP.amber : MP.primary),
          ],
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final _Invoice invoice;
  final VoidCallback onDownload;
  final VoidCallback? onMore;
  const _InvoiceRow(this.invoice, {required this.onDownload, this.onMore});

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
      onTap: onMore, // the row: Download PDF or Share
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
  final VoidCallback? onSwitch;
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
        if (!current && onSwitch != null) ...[
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

/// Billing details: the clinic's legal name, address, state and GSTIN for MedPin's invoices.
/// GET / PUT /api/billing/details.
class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet();

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _gstin = TextEditingController();
  String _state = '';
  List<String> _states = const [];
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = ((await Api.I.get('/api/billing/details')) as Map).cast<String, dynamic>();
      if (!mounted) return;
      final d = r.obj('defaults');
      setState(() {
        _name.text = r.str('name').isEmpty ? d.str('name') : r.str('name');
        _address.text = r.str('address').isEmpty ? d.str('address') : r.str('address');
        _gstin.text = r.str('gstin');
        _state = r.str('state');
        _states = [for (final s in (r['states'] as List? ?? const [])) '$s'];
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) {
        toast(context, e.message);
        Navigator.pop(context);
      }
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, 'Write the name the invoices are made out to');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await runAction(context, () => Api.I.put('/api/billing/details', {'name': _name.text.trim(), 'address': _address.text.trim(), 'state': _state, 'gstin': _gstin.text.trim()}));
      if (ok != null && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Billing details',
      subtitle: 'Shown on your MedPin invoices',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: !_loaded
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : VGap(
                gap: 14,
                children: [
                  MpInput(controller: _name, label: 'Legal or trade name'),
                  MpInput(controller: _address, label: 'Billing address', maxLines: 3, height: 96),
                  MpSelect(label: 'State', value: _state.isEmpty ? tr(context, 'Choose') : _state, options: _states, onChanged: (v) => setState(() => _state = v)),
                  MpInput(controller: _gstin, label: 'GSTIN (if registered)', hint: '19ABCDE1234F1Z5', help: 'For input tax credit. The state is read from it.'),
                  MpButton(_busy ? 'Saving…' : 'Save', onTap: _busy ? null : _save),
                ],
              ),
      ),
    );
  }
}

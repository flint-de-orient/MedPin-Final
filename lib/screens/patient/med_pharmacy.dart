import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';
import '../../data/checkout.dart';
import '../../widgets/i18n.dart';

/// Design: Med-Pharmacy.dc.html — "Medicines · choose pharmacy".
class MedPharmacyScreen extends StatefulWidget {
  const MedPharmacyScreen({super.key});

  @override
  State<MedPharmacyScreen> createState() => _MedPharmacyScreenState();
}

class _Shop {
  final String name;
  final String price;
  final String when;
  final String stock;
  final bool inStock;
  const _Shop(this.name, this.price, this.when, this.stock, this.inStock);
}

const _online = [
  _Shop('CarePlus Online', '₹138', 'Delivers tomorrow by 11 AM · free delivery', 'All items in stock', true),
  _Shop('QuickMeds', '₹152', 'Delivers today in 2 hours · ₹15 delivery', 'All items in stock', true),
  _Shop(
    'City Care Clinic pharmacy',
    '₹144',
    'Delivers today by 7 PM · your clinic',
    'Atorvastatin 10 mg: only 1 strip',
    false,
  ),
];

// "Nearby · pick up" is not drawn in the design: same cards, nearby shops.
const _nearby = [
  _Shop('Salt Lake Medicals', '₹136', 'Ready in 30 min · 0.8 km away', 'All items in stock', true),
  _Shop(
    'City Care Clinic pharmacy',
    '₹144',
    'Pick up at your 5 PM visit · your clinic',
    'Atorvastatin 10 mg: only 1 strip',
    false,
  ),
  _Shop('Purbachal Pharmacy', '₹140', 'Ready in 1 hour · 1.4 km away', 'All items in stock', true),
];

/// Live data: GET /api/patient/cart and /api/patient/pharmacies/quotes for
/// delivery and pick up. Place order asks how to pay (online now through
/// Razorpay, or cash on delivery / at the pharmacy) and posts /api/patient/orders.
/// Args (optional): {'addressId'} from Med-Cart.
class _MedPharmacyScreenState extends State<MedPharmacyScreen> with LiveData {
  int _tab = 0;
  final _selected = [0, 0];
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/patient/cart'),
      Api.I.get('/api/patient/pharmacies/quotes', query: {'mode': 'delivery'}),
      Api.I.get('/api/patient/pharmacies/quotes', query: {'mode': 'pickup'}),
    ]);
    return {'cart': r[0], 'delivery': r[1], 'pickup': r[2]};
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  List<_Shop> get _shops => _tab == 0 ? _online : _nearby;

  List<Map<String, dynamic>> get _quotes => data!.obj(_tab == 0 ? 'delivery' : 'pickup').list('items');

  _Shop _shopFrom(Map<String, dynamic> q) {
    final ph = q.obj('pharmacy');
    final fee = q.numOr('deliveryFee');
    final String when;
    if (_tab == 0) {
      final eta = ph.str('etaText', 'Home delivery');
      when = fee > 0 ? '$eta · ${p3Rupees(fee)} delivery' : (eta.contains('free delivery') ? eta : '$eta · free delivery');
    } else {
      when = [
        if (ph['pickupEtaMin'] != null) 'Ready in ${ph.numOr('pickupEtaMin').toInt()} min',
        if (ph['km'] != null) '${ph['km']} km away',
        if (ph.str('type') == 'clinic') 'your clinic',
      ].join(' · ');
    }
    final lines = q.list('lines');
    final missing = [for (final l in lines) if (l['inStock'] == false) l.str('name')];
    final priced = q['priced'] != false;
    return _Shop(
      ph.str('name'),
      priced ? p3Rupees(q.numOr('total')) : (q.numOr('total') > 0 ? '${p3Rupees(q.numOr('total'))}+' : 'At shop'),
      when.isEmpty ? (_tab == 0 ? 'Home delivery' : 'Pick up') : when,
      missing.isEmpty ? (priced ? 'All items in stock' : 'Some prices are set at the shop') : 'Not in stock: ${missing.join(', ')}',
      missing.isEmpty && priced,
    );
  }

  /// "For 3 strips Metformin, 2 strips Atorvastatin"
  String get _forLine {
    if (data == null) return 'For 3 strips Metformin, 2 strips Atorvastatin';
    final items = data!.obj('cart').list('items');
    if (items.isEmpty) return 'Your cart is empty';
    return 'For ${[
      for (final i in items)
        '${i.numOr('strips', 1).toInt()} ${i.numOr('strips', 1) == 1 ? 'strip' : 'strips'} ${i.str('name').replaceFirst(RegExp(r'\s+\d.*$'), '')}',
    ].join(', ')}';
  }

  Future<void> _placeOrder() async {
    if (data == null) {
      if (isLive) return;
      final shop = _shops[_selected[_tab]];
      toast(context, 'Order placed with ${shop.name}');
      _backToStart();
      return;
    }
    final quotes = _quotes;
    if (quotes.isEmpty) {
      toast(context, 'No pharmacy to order from yet');
      return;
    }
    final q = quotes[_selected[_tab].clamp(0, quotes.length - 1)];
    final args = (Nav.args<Map>(context) ?? const {}).cast<String, dynamic>();
    final mode = _tab == 0 ? 'delivery' : 'pickup';
    final name = q.obj('pharmacy').str('name');
    final cashLabel = mode == 'delivery' ? 'Pay on delivery' : 'Pay at the pharmacy';
    // How to pay: online now (UPI, card, net banking) or cash at delivery / the counter.
    final how = await openSheet<String>(
      context,
      (ctx) => MpSheet(
        title: 'How would you like to pay?',
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MpButton('Pay ₹${q.numOr('total').round()} online now', onTap: () => Navigator.pop(ctx, 'online')),
          const Gap(10),
          MpButton(cashLabel, kind: MpBtn.secondary, onTap: () => Navigator.pop(ctx, 'cash')),
          const Gap(8),
          Text('UPI, card or net banking through Razorpay. A paid order that is cancelled is refunded.', textAlign: TextAlign.center, style: tx(13, c: MP.ink3, h: 1.4)),
        ]),
      ),
    );
    if (how == null || !mounted) return;
    final res = await runAction(
      context,
      () => Api.I.post('/api/patient/orders', {
        'pharmacyId': q.obj('pharmacy').str('id'),
        'mode': mode,
        if (args['addressId'] != null) 'addressId': args['addressId'],
        if (how == 'online') 'payOnline': true,
      }),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    p3CartChanged.value++;
    if (how == 'online' && res['payment'] == 'online') {
      // Pay now in the app; if it's closed, the order waits and can be paid from Orders.
      final paid = await Checkout.pay(context, kind: 'order', id: '${res['id']}');
      if (!mounted) return;
      toast(context, paid ? 'Order placed with $name · paid' : 'Order placed with $name · pay any time from Orders in Medicines');
    } else {
      toast(context, 'Order placed with $name · ${cashLabel.toLowerCase()}');
    }
    if (mounted) _backToStart();
  }

  /// Back past the cart to wherever the order started (Medicines).
  void _backToStart() {
    Navigator.of(
      context,
    ).popUntil((r) => r.isFirst || (r.settings.name != 'Med-Pharmacy' && r.settings.name != 'Med-Cart'));
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = data != null;
    final shops = live ? [for (final q in _quotes) _shopFrom(q)] : _shops;
    final sel = shops.isEmpty ? 0 : _selected[_tab].clamp(0, shops.length - 1);

    return MpPage(
        header: Container(
          padding: const EdgeInsets.only(bottom: 16),
          decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MpHeader('Choose a pharmacy', background: MP.white),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: P2Segmented(
                  options: const ['Online · delivery', 'Nearby · pick up'],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
            ],
          ),
        ),
        bottom: placeholder != null
            ? null
            : MpBottomBar(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total', style: tx(12, c: MP.ink2)),
                        Text(shops.isEmpty ? '—' : shops[sel].price, style: tx(20, w: w800, tab: true)),
                      ],
                    ),
                    const Gap(16),
                    Expanded(child: MpButton('Place order', onTap: _placeOrder)),
                  ],
                ),
              ),
        // main: padding 16 20 120 — the pinned bar (97px) takes the rest.
        body: placeholder ?? VGap(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 23),
          gap: 10,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text(_forLine, style: tx(13, c: MP.ink2)),
            ),
            if (shops.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: MPDeco.card(),
                child: Text(
                  _tab == 0 ? 'No pharmacy delivers here yet' : 'No pharmacy nearby yet',
                  style: tx(15, w: w600, c: MP.ink2),
                ),
              ),
            for (var i = 0; i < shops.length; i++)
              _ShopCard(shops[i], on: i == sel, onTap: () => setState(() => _selected[_tab] = i)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Ico(I.fileText, size: 18, color: MP.ink2),
                    const Gap(12),
                    Expanded(child: Text('Prescriptions go with your order automatically.', style: tx(13, h: 1.4))),
                    const Gap(12),
                    const P2Pill('Coming soon', bg: MP.white, fontSize: 11),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }
}

class _ShopCard extends StatelessWidget {
  final _Shop s;
  final bool on;
  final VoidCallback onTap;
  const _ShopCard(this.s, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    child: P2Box(
      onTap: onTap,
      label: s.name,
      padding: const EdgeInsets.all(16),
      radius: 20,
      color: MP.white,
      border: on ? MP.primary : MP.line,
      borderWidth: on ? 1.5 : 1,
      shadow: MPShadow.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: P2Radio(on)),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text(s.name, style: tx(16, w: w700))),
                    const Gap(8),
                    Text(s.price, style: tx(17, w: w800, tab: true)),
                  ],
                ),
                const Gap(4),
                Text(s.when, style: tx(13, c: MP.ink2)),
                const Gap(4),
                Text(s.stock, style: tx(13, w: w600, c: s.inStock ? MP.green : MP.amber)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

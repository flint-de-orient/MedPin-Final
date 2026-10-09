import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

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

class _MedPharmacyScreenState extends State<MedPharmacyScreen> {
  int _tab = 0;
  final _selected = [0, 0];

  List<_Shop> get _shops => _tab == 0 ? _online : _nearby;

  void _placeOrder() {
    final shop = _shops[_selected[_tab]];
    toast(context, 'Order placed with ${shop.name}');
    // Back past the cart to wherever the order started (Medicines).
    Navigator.of(
      context,
    ).popUntil((r) => r.isFirst || (r.settings.name != 'Med-Pharmacy' && r.settings.name != 'Med-Cart'));
  }

  @override
  Widget build(BuildContext context) {
    final shops = _shops;
    final sel = _selected[_tab];

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
        bottom: MpBottomBar(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total', style: tx(12, c: MP.ink2)),
                  Text(shops[sel].price, style: tx(20, w: w800, tab: true)),
                ],
              ),
              const Gap(16),
              Expanded(child: MpButton('Place order', onTap: _placeOrder)),
            ],
          ),
        ),
        // main: padding 16 20 120 — the pinned bar (97px) takes the rest.
        body: VGap(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 23),
          gap: 10,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text('For 3 strips Metformin, 2 strips Atorvastatin', style: tx(13, c: MP.ink2)),
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

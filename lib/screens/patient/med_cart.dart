import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Med-Cart.dc.html — "Medicines · cart".
class MedCartScreen extends StatefulWidget {
  const MedCartScreen({super.key});

  @override
  State<MedCartScreen> createState() => _MedCartScreenState();
}

class _Item {
  final String name;
  final String sub;

  /// Tablets a day and tablets already at home (10 a strip).
  final int perDay;
  final int stock;
  const _Item(this.name, this.sub, this.perDay, this.stock);
}

const _metformin = _Item('Metformin 500 mg', 'Dr. Arjun Sen · strip of 10', 2, 6);
const _atorvastatin = _Item('Atorvastatin 10 mg', 'Dr. Rina Mitra · strip of 10', 1, 12);
const _glimepiride = _Item('Glimepiride 1 mg', 'Dr. Arjun Sen · strip of 10', 1, 28);

class _MedCartScreenState extends State<MedCartScreen> {
  final _items = <_Item>[_metformin, _atorvastatin];
  final _qty = <int>[3, 2];

  String _lastsTill(int i) => p2Day(p2FromToday((_items[i].stock + 10 * _qty[i]) ~/ _items[i].perDay - 1));

  void _remove(int i) => setState(() {
    _items.removeAt(i);
    _qty.removeAt(i);
  });

  void _change(int i, int by) {
    final q = _qty[i] + by;
    if (q < 1 || q > 99) return;
    setState(() => _qty[i] = q);
  }

  @override
  Widget build(BuildContext context) {
    final n = _items.length;
    final suggest = !_items.contains(_glimepiride);

    return MpPage(
        header: P2WhiteHeader(n == 1 ? 'Cart · 1 medicine' : 'Cart · $n medicines'),
        bottom: MpBottomBar(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: MpButton(
            'Choose a pharmacy',
            onTap: n == 0 ? () => toast(context, 'Your cart is empty') : () => Nav.go(context, 'Med-Pharmacy'),
          ),
        ),
        // main: padding 16 20 120 — the pinned bar (97px) takes the rest.
        body: VGap(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 23),
          gap: 16,
          children: [
            if (n == 0)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: MPDeco.card(),
                child: Text('Your cart is empty', style: tx(15, w: w600, c: MP.ink2)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: MPDeco.card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var i = 0; i < n; i++) _itemRow(i)],
                ),
              ),

            if (suggest)
              P2Box(
                onTap:
                    () => setState(() {
                      _items.add(_glimepiride);
                      _qty.add(1);
                    }),
                dashed: true,
                border: MP.lineStrong,
                radius: 16,
                color: MP.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Ico(I.plus, size: 18, color: MP.primary, stroke: 2),
                    const Gap(12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: tx(14, w: w600),
                          children: [
                            const TextSpan(text: 'Add Glimepiride too? '),
                            TextSpan(text: 'Runs out 28 Oct', style: tx(14, c: MP.ink2)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Prescriptions attached
            Container(
              padding: const EdgeInsets.all(20),
              decoration: MPDeco.card(shadow: null),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Prescriptions attached', style: tx(15, w: w700)),
                            const Gap(2),
                            Text(
                              "We'll attach Dr. Sen's 29 Sep and Dr. Mitra's 02 Feb prescriptions automatically.",
                              style: tx(13, h: 1.4, c: MP.ink2),
                            ),
                          ],
                        ),
                      ),
                      const Gap(12),
                      const P2Pill('Coming soon', height: 24, padX: 10),
                    ],
                  ),
                  const Gap(14),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Nav.go(context, 'Records-Add'),
                    child: Text('Attach prescriptions yourself for now', style: tx(14, w: w600, c: MP.primary)),
                  ),
                ],
              ),
            ),

            // Deliver to home
            Container(
              padding: const EdgeInsets.all(20),
              decoration: MPDeco.card(shadow: null),
              child: Row(
                children: [
                  const Ico(I.pin, size: 20, color: MP.ink2),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Deliver to home', style: tx(15, w: w700)),
                        const Gap(2),
                        Text('Flat 3B, 12 Purbachal Rd, Salt Lake', style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => p2Missing(context, 'Changing the address'),
                    child: Text('Change', style: tx(14, w: w600, c: MP.primary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _itemRow(int i) {
    final it = _items[i];
    final q = _qty[i];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.name, style: tx(16, w: w700)),
                    const Gap(2),
                    Text(it.sub, style: tx(13, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              // 40px remove button, margin: -8px -8px 0 0.
              P2Bleed(
                width: 40,
                height: 40,
                top: 8,
                right: 8,
                child: MpIconButton(
                  I.close,
                  label: 'Remove ${it.name}',
                  size: 40,
                  iconSize: 18,
                  color: MP.ink2,
                  onTap: () => _remove(i),
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(child: Text('Lasts till ${_lastsTill(i)}', style: tx(13, c: MP.ink2))),
              P2Stepper(
                value: q == 1 ? '1 strip' : '$q strips',
                button: 40,
                valueWidth: 64,
                iconSize: 16,
                style: tx(14, w: w700, tab: true),
                label: 'Strips of ${it.name}',
                onMinus: () => _change(i, -1),
                onPlus: () => _change(i, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

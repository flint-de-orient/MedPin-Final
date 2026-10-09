import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Med-AddToCart.dc.html — "Medicines · add to cart" (sheet over Patient-Medicines).
/// Pops with the number of strips added.
class MedAddtocartSheet extends StatefulWidget {
  const MedAddtocartSheet({super.key});

  @override
  State<MedAddtocartSheet> createState() => _MedAddtocartSheetState();
}

/// (title, sub, strips, tag)
const _options = [
  ('Till my next visit', '2 strips · lasts till 1 Nov', 2, 'Suggested'),
  ('1 month', '3 strips · 30 days', 3, ''),
  ('3 months', '9 strips · 90 days', 9, ''),
];

class _MedAddtocartSheetState extends State<MedAddtocartSheet> {
  int _strips = 2;

  /// Atorvastatin: 12 tablets at home, 1 a day, 10 a strip.
  String get _covers => p2Day(p2FromToday(12 + 10 * _strips - 1));

  void _add() {
    toast(context, _strips == 1 ? 'Added 1 strip to cart' : 'Added $_strips strips to cart');
    Navigator.of(context).pop(_strips);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(20),
            const P2SheetHeader(title: 'Atorvastatin 10 mg', subtitle: 'Strip of 10 tablets · you take 1 a day'),
            const Gap(20),

            // How much do you need?
            Text('How much do you need?', style: tx(14, w: w600)),
            for (final o in _options) ...[
              const Gap(8),
              _Option(
                title: o.$1,
                sub: o.$2,
                tag: o.$4,
                on: _strips == o.$3,
                onTap: () => setState(() => _strips = o.$3),
              ),
            ],
            const Gap(20),

            // Or pick strips
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Or pick strips', style: tx(14, w: w600)),
                      const Gap(2),
                      Text('Covers till $_covers with what you have', style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
                const Gap(12),
                P2Stepper(
                  value: '$_strips',
                  button: 44,
                  valueWidth: 40,
                  iconSize: 18,
                  style: tx(17, w: w800, tab: true),
                  label: 'Number of strips',
                  minusLabel: 'One less strip',
                  plusLabel: 'One more strip',
                  onMinus: () {
                    if (_strips > 1) setState(() => _strips--);
                  },
                  onPlus: () {
                    if (_strips < 99) setState(() => _strips++);
                  },
                ),
              ],
            ),
            const Gap(20),

            Text('Final price depends on the pharmacy you pick at checkout.', style: tx(13, h: 1.45, c: MP.ink3)),
            const Gap(20),

            MpButton(_strips == 1 ? 'Add 1 strip to cart' : 'Add $_strips strips to cart', onTap: _add),
          ],
        ),
      );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String sub;
  final String tag;
  final bool on;
  final VoidCallback onTap;
  const _Option({required this.title, required this.sub, required this.tag, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    child: P2Box(
      onTap: onTap,
      label: title,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 16,
      color: on ? MP.primarySoft : MP.white,
      border: on ? MP.primary : MP.lineStrong,
      borderWidth: on ? 1.5 : 1,
      child: Row(
        children: [
          P2Radio(on),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title, style: tx(16, w: w700)), const Gap(2), Text(sub, style: tx(13, c: MP.ink2))],
            ),
          ),
          if (tag.isNotEmpty) ...[const Gap(14), P2Pill(tag, bg: MP.primary, fg: MP.white, fontSize: 11)],
        ],
      ),
    ),
  );
}

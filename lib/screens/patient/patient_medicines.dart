import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Patient-Medicines.dc.html — "Patient · Medicines tab".
class PatientMedicinesScreen extends StatefulWidget {
  const PatientMedicinesScreen({super.key});

  @override
  State<PatientMedicinesScreen> createState() => _PatientMedicinesScreenState();
}

/// (slot, [(medicine, when, taken at — null while due)])
const List<(String, List<(String, String, String?)>)> _slots = [
  (
    'Morning',
    [
      ('Glimepiride 1 mg', 'Before breakfast', '7:32 AM'),
      ('Metformin 500 mg', 'After breakfast', '8:40 AM'),
      ('Myo-inositol 2 g', 'After breakfast', '8:41 AM'),
    ],
  ),
  (
    'Night',
    [('Metformin 500 mg', '8:30 PM · after dinner', null), ('Atorvastatin 10 mg', '10:00 PM · at bedtime', null)],
  ),
];

class _Med {
  final String name;
  final String dose;
  final String day;
  final String taken;
  final Color takenColor;
  final String stock;
  final Color stockColor;
  final String by;

  /// Strips already in the cart.
  final int? inCart;
  const _Med(
    this.name,
    this.dose,
    this.day,
    this.taken,
    this.takenColor,
    this.stock,
    this.stockColor,
    this.by, [
    this.inCart,
  ]);
}

const _meds = [
  _Med(
    'Metformin 500 mg',
    '1-0-1 · after food',
    'Day 468',
    '78%',
    MP.amber,
    '6 · 3 days',
    MP.amber,
    'Dr. Arjun Sen · 29 Sep 2026 · ongoing',
    3,
  ),
  _Med(
    'Glimepiride 1 mg',
    '1-0-0 · before breakfast',
    'Day 2 of 30',
    'New',
    MP.ink3,
    '28 · 28 days',
    MP.ink,
    'Dr. Arjun Sen · 29 Sep 2026',
  ),
  _Med(
    'Atorvastatin 10 mg',
    '0-0-1 · at bedtime',
    'Day 241',
    '91%',
    MP.green,
    '12 · 12 days',
    MP.ink,
    'Dr. Rina Mitra · 02 Feb 2026 · ongoing',
  ),
  _Med(
    'Myo-inositol 2 g',
    '1-0-1 · after food',
    'Day 316',
    'Not tracked',
    MP.ink3,
    '40 · 20 days',
    MP.ink,
    'Dr. Nandita Gupta · 18 Nov 2025',
  ),
  _Med(
    'Vitamin D3 60,000 IU',
    'Once a week · Sunday',
    'Week 7 of 8',
    '100%',
    MP.green,
    '2 · 2 weeks',
    MP.ink,
    'Dr. Arjun Sen · 11 Aug 2026',
  ),
];

const _more = [
  ('Reminder times', 'Morning 7:30 AM · Night 8:30 PM', 'Editing reminder times'),
  ('Orders', '1 delivered · 12 Sep', 'Order history'),
  ('Past medicines', '3 completed courses', 'The past medicines list'),
  ('Share medicine list', 'PDF for a new doctor or pharmacy', ''),
];

/// Shield with a check (safety check).
const _shieldCheck = '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>';

class _PatientMedicinesScreenState extends State<PatientMedicinesScreen> {
  /// Per dose: null = due, '' = skipped, otherwise the time it was taken.
  late final List<List<String?>> _status = [
    for (final s in _slots) [for (final d in s.$2) d.$3],
  ];
  late final List<int?> _cart = [for (final m in _meds) m.inCart];

  Future<void> _addToCart(int i) async {
    final strips = await Nav.go<int>(context, 'Med-AddToCart');
    if (!mounted || strips == null) return;
    setState(() => _cart[i] = strips);
  }

  @override
  Widget build(BuildContext context) {
    final all = _status.expand((s) => s);
    final taken = all.where((v) => v != null && v.isNotEmpty).length;
    final inCart = _cart.where((c) => c != null).length;

    return MpPage(
        nav: const PatientNav(current: 2),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: title + cart button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Medicines', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                        const Gap(4),
                        Text('5 running · from 3 doctors', style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  _CartButton(count: inCart, onTap: () => Nav.go(context, 'Med-Cart')),
                ],
              ),
            ),
            VGap(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              gap: 16,
              children: [_todaysDoses(taken, all.length), _refill(), _runningNow(), _safety(), _moreList()],
            ),
          ],
        ),
      );
  }

  Widget _todaysDoses(int taken, int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      decoration: MPDeco.card(radius: 20, shadow: MPShadow.float),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text("Today's doses", style: tx(20, w: w700, h: 1.25))),
                Text('$taken of $total taken', style: tx(14, c: MP.ink2, tab: true)),
              ],
            ),
          ),
          for (var s = 0; s < _slots.length; s++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: s == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_slots[s].$1.toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                  for (var d = 0; d < _slots[s].$2.length; d++) ...[const Gap(10), _doseRow(s, d)],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _doseRow(int s, int d) {
    final dose = _slots[s].$2[d];
    final status = _status[s][d];
    final due = status == null;
    void set(String? v) => setState(() => _status[s][d] = v);

    Widget trailing;
    if (due) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          P2Box(
            onTap: () => set(''),
            label: 'Skip ${dose.$1}',
            height: 40,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: MP.white,
            border: MP.lineStrong,
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Skip', style: tx(14, w: w600, c: MP.ink2))]),
          ),
          const Gap(6),
          P2Box(
            onTap: () => set(p2Now()),
            label: 'Taken ${dose.$1}',
            height: 40,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: MP.primarySoft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('Taken', style: tx(14, w: w700, c: MP.primary))],
            ),
          ),
        ],
      );
    } else if (status.isEmpty) {
      // Skipped (not drawn in the design): grey pill, tap to undo.
      trailing = GestureDetector(
        onTap: () => set(null),
        child: const P2Pill('Skipped', height: 28, padX: 10, fontSize: 13),
      );
    } else {
      trailing = Semantics(
        button: true,
        label: 'Taken at $status, tap to undo',
        child: GestureDetector(
          onTap: () => set(null),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Ico(I.check, size: 14, color: MP.green, stroke: 2.5),
                const Gap(4),
                Text(status, style: tx(13, w: w700, c: MP.green)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dose.$1, style: tx(16, w: w600, c: due ? MP.ink : MP.ink2)),
              const Gap(1),
              Text(dose.$2, style: tx(13, c: MP.ink2)),
            ],
          ),
        ),
        const Gap(12),
        trailing,
      ],
    );
  }

  Widget _refill() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MP.amberSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.amberLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Metformin runs out on Friday', style: tx(15, w: w700)),
                const Gap(2),
                Text('6 tablets left · 3 days', style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Gap(12),
          P2Box(
            onTap: () => Nav.go(context, 'Med-Cart'),
            height: 44,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: MP.white,
            shadow: MPShadow.hairline,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('Reorder', style: tx(14, w: w700, c: MP.primary))],
            ),
          ),
        ],
      ),
    );
  }

  Widget _runningNow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Running now', style: tx(20, w: w700, h: 1.25))),
              const Gap(8),
              Text('Sorted by what runs out first', style: tx(13, c: MP.ink3)),
            ],
          ),
        ),
        for (var i = 0; i < _meds.length; i++) ...[
          const Gap(12),
          _MedCard(
            _meds[i],
            inCart: _cart[i],
            onCart: _cart[i] == null ? () => _addToCart(i) : () => Nav.go(context, 'Med-Cart'),
          ),
        ],
      ],
    );
  }

  Widget _safety() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: Ico(_shieldCheck, size: 20, color: MP.green)),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No clashes found', style: tx(15, w: w700)),
                const Gap(2),
                Text(
                  'Your 5 medicines from 3 doctors were checked against each other and your sulfa allergy.',
                  style: tx(13, h: 1.45, c: MP.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moreList() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: MPDeco.card(shadow: null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _more.length; i++)
            P2Box(
              onTap:
                  _more[i].$3.isEmpty
                      ? () => toast(context, 'Medicine list saved as PDF')
                      : () => p2Missing(context, _more[i].$3),
              label: _more[i].$1,
              topBorder: i == 0 ? null : const BorderSide(color: MP.line),
              minHeight: i == 0 ? 60 : 61,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_more[i].$1, style: tx(15, w: w600)),
                        const Gap(2),
                        Text(_more[i].$2, style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 44px round cart link (+1px border, content-box) with the item count badge.
class _CartButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CartButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        P2Box(
          onTap: onTap,
          label: count == 1 ? 'Cart, 1 item' : 'Cart, $count items',
          width: 46,
          height: 46,
          radius: 999,
          color: MP.white,
          border: MP.line,
          alignment: Alignment.center,
          child: const Ico(I.cart, size: 20, color: MP.ink),
        ),
        if (count > 0)
          Positioned(
            top: -1,
            right: -1,
            child: IgnorePointer(
              child: Container(
                height: 20,
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MP.primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MP.bg, width: 2),
                ),
                child: Text('$count', style: tx(11, w: w800, c: MP.white)),
              ),
            ),
          ),
      ],
    );
  }
}

class _MedCard extends StatelessWidget {
  final _Med m;
  final int? inCart;
  final VoidCallback onCart;
  const _MedCard(this.m, {required this.inCart, required this.onCart});

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tx(12, c: MP.ink2)),
          const Gap(2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(17, w: w800, c: color, tab: true)),
        ],
      ),
    );

    final carted = inCart != null;
    final cartFg = carted ? MP.green : MP.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MPDeco.card(),
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
                    Text(m.name, style: tx(18, w: w700)),
                    const Gap(3),
                    Text(m.dose, style: tx(14, tab: true)),
                  ],
                ),
              ),
              const Gap(12),
              P2Pill(m.day, height: 24, padX: 10, tab: true),
            ],
          ),
          const Gap(14),
          Row(
            children: [
              Expanded(child: stat('Taken · 30 days', m.taken, m.takenColor)),
              const Gap(8),
              Expanded(child: stat('In stock', m.stock, m.stockColor)),
            ],
          ),
          const Gap(14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Nav.go(context, 'Patient-Records'),
            child: Row(
              children: [
                const Ico(I.fileText, size: 18, color: MP.ink2),
                const Gap(10),
                Expanded(child: Text(m.by, style: tx(13, h: 1.4, c: MP.ink2))),
                const Gap(10),
                Text('Prescription', style: tx(14, w: w700, c: MP.primary)),
              ],
            ),
          ),
          const Gap(14),
          Row(
            children: [
              Expanded(
                child: P2Box(
                  onTap: () => p2Missing(context, 'Updating stock'),
                  height: 48,
                  radius: 12,
                  color: MP.white,
                  border: MP.lineStrong,
                  alignment: Alignment.center,
                  child: Text('Update stock', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: w700)),
                ),
              ),
              const Gap(8),
              Expanded(
                flex: 2,
                child: P2Box(
                  onTap: onCart,
                  height: 48,
                  radius: 12,
                  color: carted ? MP.greenSoft : MP.primarySoft,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Ico(I.cart, size: 16, color: cartFg),
                      const Gap(6),
                      Flexible(
                        child: Text(
                          carted ? 'In cart · $inCart ${inCart == 1 ? 'strip' : 'strips'}' : 'Add to cart',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(14, w: w700, c: cartFg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

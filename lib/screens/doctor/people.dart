import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: People.dc.html — "People".
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void addSomeone() => Nav.go(context, 'People-Add');
    return MpPage(
      header: MpHeader(
        'People',
        actions: [MpIconButton(I.userPlus, label: 'Add someone', color: MP.primary, onTap: addSomeone)],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          const _SeatBanner(),
          D9Card(gap: 20, children: [for (final g in _groups) _Group(g.$1, g.$2)]),
          MpButton('Add someone', icon: I.plus, iconStroke: 1.75, onTap: addSomeone),
        ],
      ),
    );
  }
}

// (name, initials, meta, pill, suspended)
typedef _Person = (String, String, String, String?, bool);

const List<(String, List<_Person>)> _groups = [
  (
    'Doctors',
    [
      ('Dr. Arjun Sen', 'AS', 'Endocrinology · All locations', 'Owner', false),
      ('Dr. Rina Mitra', 'RM', 'Cardiology · Salt Lake', null, false),
    ],
  ),
  (
    'Front desk',
    [
      ('Tania Ghosh', 'TG', 'Endocrinology · Salt Lake', null, false),
      ('Payel Dey', 'PD', 'Cardiology · New Town', null, false),
    ],
  ),
  ('Dieticians', [('Mou Banerjee', 'MB', 'Diabetology · All locations', null, false)]),
  ("Doctor's assistant", [('Rohit Saha', 'RS', 'Endocrinology · Salt Lake', null, false)]),
  ('Lab manager', [('Sanjay Kar', 'SK', 'Diabetology · Salt Lake', 'Suspended', true)]),
];

class _SeatBanner extends StatelessWidget {
  const _SeatBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '7 of 8 seats used on the Clinic plan',
              style: tx(14, w: w600, c: MP.primary, h: 1.45, tab: true),
            ),
          ),
          const Gap(12),
          D9Link('Upgrade', weight: w700, h: null, underline: true, onTap: () => Nav.go(context, 'Billing')),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String label;
  final List<_Person> people;
  const _Group(this.label, this.people);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        D9Label(label, h: 1.35, padding: const EdgeInsets.only(bottom: 4)),
        for (var i = 0; i < people.length; i++) _PersonRow(people[i], first: i == 0),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  final _Person p;
  final bool first;
  const _PersonRow(this.p, {required this.first});

  @override
  Widget build(BuildContext context) {
    final (name, initials, meta, pill, suspended) = p;
    final owner = pill == 'Owner';
    return D9Row(
      border: !first,
      padding: const EdgeInsets.symmetric(vertical: 12),
      onTap: () => Nav.go(context, 'People-Member'),
      child: Row(
        children: [
          MpAvatar(
            initials,
            size: 40,
            fontSize: 14,
            bg: suspended ? MP.fill : MP.primarySoft,
            fg: suspended ? MP.ink3 : MP.primary,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: tx(16, w: w600, h: 1.5, c: suspended ? MP.ink2 : MP.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (pill != null) ...[
                      const Gap(8),
                      MpBadge(
                        pill,
                        bg: owner ? MP.primarySoft : MP.fill,
                        fg: owner ? MP.primary : MP.ink2,
                        weight: w600,
                      ),
                    ],
                  ],
                ),
                const Gap(2),
                Text(meta, style: tx(14, c: MP.ink2, h: 1.45), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Gap(12),
          const D9Chevron(),
        ],
      ),
    );
  }
}

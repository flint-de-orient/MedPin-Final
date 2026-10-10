import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';
import '../../widgets/i18n.dart';

/// Design: People.dc.html — "People".
/// Live data: GET /api/members (+ GET /api/locations for short names).
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

/// Group headings, in the design's order.
const _groupLabels = {
  'doctor': 'Doctors',
  'front_desk': 'Front desk',
  'dietician': 'Dieticians',
  'doctor_assistant': "Doctor's assistant",
  'lab_manager': 'Lab manager',
  'lab_technician': 'Lab technician',
  'practice_manager': 'Practice manager',
};

class _PeopleScreenState extends State<PeopleScreen> with LiveData {
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([Api.I.get('/api/members'), Api.I.get('/api/locations')]);
    return {'members': r[0], 'locations': r[1]};
  }

  String get _seatLine {
    if (data == null) return '7 of 8 seats used on the Clinic plan';
    final s = data!.obj('members').obj('seats');
    final plan = s.str('plan');
    if (s['limit'] == null) return '${D9Fmt.plural(s.numOr('used'), 'seat')} used';
    return '${F.count(s.numOr('used'))} of ${D9Fmt.plural(s.numOr('limit'), 'seat')} used${plan.isEmpty ? '' : ' on the $plan plan'}';
  }

  List<(String, List<_Person>)> get _liveGroups {
    if (data == null) return _groups;
    final short = {
      for (final l in data!.obj('locations').list('items')) l.str('id'): l.str('shortName', l.str('name')),
    };
    final members = data!.obj('members').list('items');
    return [
      for (final role in _groupLabels.keys)
        if (members.any((m) => m['role'] == role))
          (
            _groupLabels[role]!,
            [
              for (final m in members.where((m) => m['role'] == role))
                () {
                  final suspended = m['status'] == 'suspended';
                  final locs = m['allLocations'] == true
                      ? 'All locations'
                      : m.list('locations').map((l) => short[l.str('id')] ?? l.str('name')).join(', ');
                  final meta = [m.obj('department').str('name'), locs.isEmpty ? 'No locations' : locs]
                      .where((x) => x.isNotEmpty)
                      .join(' · ');
                  final name = m.str('name', D9Fmt.phone(m.str('phone')));
                  return (
                    name,
                    F.initials(name),
                    meta,
                    m['isOwner'] == true ? 'Owner' : (suspended ? 'Suspended' : null),
                    suspended,
                    m['id'] as String?,
                  );
                }(),
            ],
          ),
    ];
  }

  Future<void> _open(String stem, [Object? args]) async {
    await Nav.go(context, stem, args: args);
    if (mounted && isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    void addSomeone() => _open('People-Add');
    final placeholder = livePlaceholder();
    return MpPage(
      header: MpHeader(
        'People',
        actions: [MpIconButton(I.userPlus, label: 'Add someone', color: MP.primary, onTap: addSomeone)],
      ),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          _SeatBanner(_seatLine),
          D9Card(
            gap: 20,
            children: [for (final g in _liveGroups) _Group(g.$1, g.$2, onOpen: (id) => _open('People-Member', {'memberId': id}))],
          ),
          MpButton('Add someone', icon: I.plus, iconStroke: 1.75, onTap: addSomeone),
        ],
      ),
    );
  }
}

// (name, initials, meta, pill, suspended, member id)
typedef _Person = (String, String, String, String?, bool, String?);

const List<(String, List<_Person>)> _groups = [
  (
    'Doctors',
    [
      ('Dr. Arjun Sen', 'AS', 'Endocrinology · All locations', 'Owner', false, null),
      ('Dr. Rina Mitra', 'RM', 'Cardiology · Salt Lake', null, false, null),
    ],
  ),
  (
    'Front desk',
    [
      ('Tania Ghosh', 'TG', 'Endocrinology · Salt Lake', null, false, null),
      ('Payel Dey', 'PD', 'Cardiology · New Town', null, false, null),
    ],
  ),
  ('Dieticians', [('Mou Banerjee', 'MB', 'Diabetology · All locations', null, false, null)]),
  ("Doctor's assistant", [('Rohit Saha', 'RS', 'Endocrinology · Salt Lake', null, false, null)]),
  ('Lab manager', [('Sanjay Kar', 'SK', 'Diabetology · Salt Lake', 'Suspended', true, null)]),
];

class _SeatBanner extends StatelessWidget {
  final String text;
  const _SeatBanner(this.text);

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
              text,
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
  final ValueChanged<String?> onOpen;
  const _Group(this.label, this.people, {required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        D9Label(label, h: 1.35, padding: const EdgeInsets.only(bottom: 4)),
        for (var i = 0; i < people.length; i++) _PersonRow(people[i], first: i == 0, onTap: () => onOpen(people[i].$6)),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  final _Person p;
  final bool first;
  final VoidCallback onTap;
  const _PersonRow(this.p, {required this.first, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (name, initials, meta, pill, suspended, _) = p;
    final owner = pill == 'Owner';
    return D9Row(
      border: !first,
      padding: const EdgeInsets.symmetric(vertical: 12),
      onTap: onTap,
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

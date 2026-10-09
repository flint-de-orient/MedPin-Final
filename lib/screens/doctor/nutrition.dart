import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d8.dart';

/// Design: Nutrition.dc.html — "Nutrition" (Clinician · tabs): food logs and
/// dietician conversations.
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _Conv {
  final String initials;
  final String name;
  final String time;
  final int unread;
  final String who;
  final String text;
  final String chip;
  final String meta;
  const _Conv(this.initials, this.name, this.time, this.unread, this.who, this.text, this.chip, this.meta);
}

const _rows = [
  _Conv(
    'PS',
    'Priya Sharma',
    '8:14 AM',
    2,
    'AI',
    'Good pick. Add a bowl of curd to balance the carbs.',
    'Review due',
    'Meal logged 8:10 AM',
  ),
  _Conv(
    'AP',
    'Amit Pal',
    '7:52 AM',
    1,
    'AI',
    'Go easy on salt today and skip the papad and pickle.',
    '',
    'Meal logged 7:40 AM',
  ),
  _Conv(
    'DB',
    'Debasish Bose',
    '7:30 AM',
    1,
    'Dietician',
    'Swap white rice for one cup of brown rice at lunch.',
    'Review due',
    'Meal logged 7:05 AM',
  ),
  _Conv(
    'FI',
    'Farhana Islam',
    'Yesterday',
    0,
    'Clinic',
    'Please log dinner too so Mou can check your iron intake.',
    '',
    'Meal logged yesterday 1:20 PM',
  ),
  _Conv(
    'AK',
    'Aisha Khan',
    'Yesterday',
    0,
    'Dietician',
    'Great week. Keep soy foods apart from your thyroid tablet.',
    '',
    'Meal logged yesterday 9:45 AM',
  ),
  _Conv(
    'MR',
    'Moumita Roy',
    'Sun',
    0,
    'AI',
    'Steamed fish with vegetables fits your heart-healthy plan.',
    '',
    'Meal logged Sun 1:30 PM',
  ),
  _Conv(
    'RD',
    'Rahul Das',
    'Sat',
    0,
    'Dietician',
    'Aim for under 5 g salt a day, about one teaspoon.',
    '',
    'Meal logged Sat 8:20 PM',
  ),
];

class _NutritionScreenState extends State<NutritionScreen> {
  /// 0 = "Unread (3)", 1 = "All" (selected in the design).
  int _filter = 1;
  String _query = '';

  List<_Conv> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final r in _rows)
        if ((_filter == 1 || r.unread > 0) && (q.isEmpty || '${r.name} ${r.who} ${r.text}'.toLowerCase().contains(q)))
          r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return MpPage(
      nav: const ClinicianNav(current: 2),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D8TabHeader(),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nutrition', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                  const Gap(4),
                  Text('Food logs and dietician conversations', style: tx(14, c: MP.ink2, h: 1.45)),
                ],
              ),
              Semantics(
                container: true,
                label: 'Filter conversations',
                child: MpSegmented(
                  options: const ['Unread (3)', 'All'],
                  index: _filter,
                  onChanged: (i) => setState(() => _filter = i),
                ),
              ),
              D8SearchField(hint: 'Search patients or messages', onChanged: (v) => setState(() => _query = v)),
              MpCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows.length; i++) _NutritionRow(rows[i], first: i == 0),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text('No conversations found', style: tx(14, c: MP.ink3, h: 20 / 14)),
                      ),
                  ],
                ),
              ),
              MpButton('Show more', kind: MpBtn.secondary, onTap: () => toast(context, 'No more conversations')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Conversation row: avatar pinned to the top, name/time, preview/unread,
/// chip + meal-log meta, chevron centred on the row.
class _NutritionRow extends StatelessWidget {
  final _Conv r;
  final bool first;
  const _NutritionRow(this.r, {required this.first});

  @override
  Widget build(BuildContext context) {
    final aria = '${r.name}${r.unread > 0 ? ', ${r.unread} unread' : ''}, ${r.time}, open chat review';
    return Semantics(
      button: true,
      label: aria,
      excludeSemantics: true,
      child: Tap(
        onTap: () => Nav.go(context, 'Chat-Review-Detail'),
        radius: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
          child: Stack(
            children: [
              Row(
                children: [
                  // Space for the avatar (`align-self: flex-start`), drawn below.
                  const SizedBox(width: 48, height: 48),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        D8ConvHead(name: r.name, time: r.time, who: r.who, text: r.text, unread: r.unread),
                        // Column gap 2px + `margin-top: 4px`.
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 24,
                          child: Row(
                            children: [
                              if (r.chip.isNotEmpty) ...[
                                MpBadge(r.chip, bg: MP.fill, fg: MP.ink2, weight: w600),
                                const Gap(8),
                              ],
                              Flexible(
                                child: Text(
                                  r.meta,
                                  style: tx(13, c: MP.ink3, tab: true),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
              Positioned(left: 0, top: 0, child: MpAvatar(r.initials, size: 48, fontSize: 16, weight: w600)),
            ],
          ),
        ),
      ),
    );
  }
}

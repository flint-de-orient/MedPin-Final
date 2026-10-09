import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';

/// Design: Staff-Patients.dc.html — "Patients" (front desk).
class StaffPatientsScreen extends StatefulWidget {
  const StaffPatientsScreen({super.key});

  @override
  State<StaffPatientsScreen> createState() => _StaffPatientsScreenState();
}

/// Chip colours (bg, fg).
const _chipColors = <String, (Color, Color)>{
  'Needs attention': (MP.amberSoft, MP.amber),
  'Check-in due': (MP.fill, MP.ink2),
};

/// (initials, name, time, unread, who, text, chip ('' = none))
typedef _Conv = (String, String, String, int, String, String, String);

const List<_Conv> _rows = [
  ('PS', 'Priya Sharma', '9:12 AM', 2, 'Priya', 'Chest feels tight since morning, should I come in?', 'Needs attention'),
  ('RD', 'Rahul Das', '8:40 AM', 1, 'Rahul', 'BP was 172/104 this morning, feeling a bit dizzy', 'Needs attention'),
  ('SM', 'Sujit Mondal', '8:22 AM', 1, 'Sujit', 'Should I take the tablet before or after breakfast?', ''),
  ('AK', 'Aisha Khan', '7:50 AM', 1, 'AI', 'Your TSH report is in. Dr. Sen will review it today.', 'Check-in due'),
  ('FI', 'Farhana Islam', '7:15 AM', 1, 'You', 'Your appointment is confirmed for Thu, 1 Oct at 11:00 AM.', ''),
  ('AP', 'Amit Pal', 'Yesterday', 1, 'Amit', 'Missed my evening Metformin again, will restart today', 'Needs attention'),
  ('MR', 'Moumita Roy', 'Yesterday', 0, 'Dr. Sen', 'Keep Ecosprin going and walk 20 minutes daily.', 'Check-in due'),
  ('DB', 'Debasish Bose', 'Sun', 0, 'Dr. Sen', 'Please repeat HbA1c before your next visit.', 'Check-in due'),
];

/// Front-desk tabs with the unread count on Patients (as in this design).
const _nav = FloatingNav(
  items: [
    NavItem('Today', I.calendar, 'Staff-Today'),
    NavItem('Patients', I.users, 'Staff-Patients', badge: 6),
    NavItem('Profile', I.user, 'Staff-Profile'),
  ],
  current: 1,
  fontSize: 12,
  gap: 4,
  badgeTop: 4,
);

class _StaffPatientsScreenState extends State<StaffPatientsScreen> {
  int _tab = 1;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final r in _rows)
        if ((_tab == 1 || r.$4 > 0) &&
            (q.isEmpty || '${r.$2} ${r.$5} ${r.$6}'.toLowerCase().contains(q)))
          r,
    ];
    return MpPage(
      nav: _nav,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D10StaffHeader(bellLabel: 'Notifications, 2 new', dot: MP.red),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              Text('Patients', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              MpSegmented(
                options: const ['Unread (6)', 'All'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              D10SearchField(
                hint: 'Search patients or messages',
                padLeft: 48,
                onChanged: (v) => setState(() => _query = v),
              ),
              _EnrolmentBanner(onView: () => Nav.go(context, 'Add-Patient-Existing')),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No conversations match “${_query.trim()}”',
                    textAlign: TextAlign.center,
                    style: tx(14, c: MP.ink3, h: 20 / 14),
                  ),
                )
              else
                Semantics(
                  label: 'Conversations',
                  container: true,
                  child: D10ListCard(
                    children: [
                      for (var i = 0; i < shown.length; i++) _ConvRow(shown[i], divider: i > 0),
                    ],
                  ),
                ),
              MpButton(
                'Show more',
                kind: MpBtn.secondary,
                onTap: () => toast(context, 'No more conversations'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// #EBF1FB note: pending enrolments + "View".
class _EnrolmentBanner extends StatelessWidget {
  final VoidCallback onView;
  const _EnrolmentBanner({required this.onView});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Ico(I.clock, size: 20, color: MP.primary),
          const Gap(12),
          Expanded(
            child: Text(
              "2 enrolments waiting on the patient's confirmation code",
              style: tx(14, h: 1.45),
            ),
          ),
          const Gap(12),
          Tap(
            onTap: onView,
            radius: 8,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              child: Text('View', style: tx(14, w: w600, c: MP.primary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConvRow extends StatelessWidget {
  final _Conv r;
  final bool divider;
  const _ConvRow(this.r, {required this.divider});

  @override
  Widget build(BuildContext context) {
    final unread = r.$4 > 0;
    final chip = _chipColors[r.$7];
    final label = '${r.$2}${unread ? ', ${r.$4} unread' : ''}, ${r.$3}';
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: D10ListRow(
        divider: divider,
        vPad: 14,
        onTap: () => Nav.go(context, 'Patient-Thread'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: MP.primarySoft, shape: BoxShape.circle),
              child: Text(r.$1, style: tx(16, w: w600, c: MP.primary, h: 1)),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(16, w: w600, h: 24 / 16),
                        ),
                      ),
                      const Gap(8),
                      Text(
                        r.$3,
                        style: tx(
                          13,
                          w: unread ? w600 : w400,
                          c: unread ? MP.primary : MP.ink3,
                          h: 24 / 13,
                          tab: true,
                        ),
                      ),
                    ],
                  ),
                  const Gap(2),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${r.$5}:', style: tx(14, w: w600, c: unread ? MP.ink : MP.ink2, h: 20 / 14)),
                              TextSpan(text: ' ${r.$6}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(14, c: unread ? MP.ink : MP.ink2, h: 20 / 14),
                        ),
                      ),
                      if (unread) ...[
                        const Gap(8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(999)),
                          child: Text('${r.$4}', style: tx(12, w: w700, c: MP.white, h: 1, tab: true)),
                        ),
                      ],
                    ],
                  ),
                  if (chip != null) ...[
                    const Gap(8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MpBadge(r.$7, bg: chip.$1, fg: chip.$2, weight: w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

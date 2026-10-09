import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d8.dart';

/// Design: Care.dc.html — "Care" (Clinician · tabs): the care inbox.
class CareScreen extends StatefulWidget {
  const CareScreen({super.key});

  @override
  State<CareScreen> createState() => _CareScreenState();
}

class _Conv {
  final String initials;
  final String name;
  final String time;
  final int unread;
  final String who;
  final String text;
  final String chip;
  const _Conv(this.initials, this.name, this.time, this.unread, this.who, this.text, this.chip);
}

const _rows = [
  _Conv(
    'PS',
    'Priya Sharma',
    '9:12 AM',
    2,
    'Priya',
    'Chest feels tight since morning, should I come in?',
    'Needs attention',
  ),
  _Conv(
    'RD',
    'Rahul Das',
    '8:40 AM',
    1,
    'Rahul',
    'BP was 172/104 this morning, feeling a bit dizzy',
    'Needs attention',
  ),
  _Conv('SM', 'Sujit Mondal', '8:22 AM', 1, 'Sujit', 'Should I take the tablet before or after breakfast?', ''),
  _Conv('AK', 'Aisha Khan', '7:50 AM', 1, 'AI', 'Your TSH report is in. Dr. Sen will review it today.', 'Check-in due'),
  _Conv('FI', 'Farhana Islam', '7:15 AM', 1, 'Tania', 'Your appointment is confirmed for Thu, 1 Oct at 11:00 AM.', ''),
  _Conv(
    'AP',
    'Amit Pal',
    'Yesterday',
    1,
    'Amit',
    'Missed my evening Metformin again, will restart today',
    'Needs attention',
  ),
  _Conv('MR', 'Moumita Roy', 'Yesterday', 0, 'You', 'Keep Ecosprin going and walk 20 minutes daily.', 'Check-in due'),
  _Conv('DB', 'Debasish Bose', 'Sun', 0, 'You', 'Please repeat HbA1c before your next visit.', 'Check-in due'),
];

/// CHIP tones from renderVals(): (background, foreground).
(Color, Color) _chipTone(String chip) => switch (chip) {
  'Needs attention' => (MP.amberSoft, MP.amber),
  _ => (MP.fill, MP.ink2),
};

class _CareScreenState extends State<CareScreen> {
  /// 0 = "Unread (6)", 1 = "All" (selected in the design).
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
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final rows = _visible;
    return MpPage(
      nav: const ClinicianNav(current: 1),
      overlays: [Positioned(right: 20, bottom: 104 + safeBottom, child: const _AddPatientButton())],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D8TabHeader(),
          VGap(
            // Design bottom padding is 176px; MpPage already reserves 112px.
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
            gap: 16,
            children: [
              Text('Care', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              Semantics(
                container: true,
                label: 'Filter conversations',
                child: MpSegmented(
                  options: const ['Unread (6)', 'All'],
                  index: _filter,
                  onChanged: (i) => setState(() => _filter = i),
                ),
              ),
              D8SearchField(hint: 'Search patients or messages', onChanged: (v) => setState(() => _query = v)),
              _enrolmentBanner(context),
              MpCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows.length; i++) _CareRow(rows[i], first: i == 0),
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

  Widget _enrolmentBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Ico(I.clock, size: 20, color: MP.primary),
          const Gap(12),
          Expanded(child: Text("2 enrolments waiting on the patient's confirmation code", style: tx(14, h: 1.45))),
          const Gap(12),
          D8Link(
            'View',
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onTap: () => Nav.go(context, 'Add-Patient-Existing'),
          ),
        ],
      ),
    );
  }
}

/// Conversation row: 48px avatar, name/time, preview/unread, optional chip.
class _CareRow extends StatelessWidget {
  final _Conv r;
  final bool first;
  const _CareRow(this.r, {required this.first});

  @override
  Widget build(BuildContext context) {
    final aria = '${r.name}${r.unread > 0 ? ', ${r.unread} unread' : ''}, ${r.time}';
    final tone = _chipTone(r.chip);
    return Semantics(
      button: true,
      label: aria,
      excludeSemantics: true,
      child: Tap(
        onTap: () => Nav.go(context, 'Patient-Thread'),
        radius: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MpAvatar(r.initials, size: 48, fontSize: 16, weight: w600),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    D8ConvHead(name: r.name, time: r.time, who: r.who, text: r.text, unread: r.unread),
                    if (r.chip.isNotEmpty)
                      Padding(
                        // Column gap 2px + `padding-top: 6px`.
                        padding: const EdgeInsets.only(top: 8),
                        child: MpBadge(r.chip, bg: tone.$1, fg: tone.$2, weight: w600),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating "Add patient" button: 56px, radius 16, padding 0 20 0 16.
class _AddPatientButton extends StatelessWidget {
  const _AddPatientButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Tap(
        onTap: () => Nav.go(context, 'Add-Patient'),
        radius: 16,
        color: MP.primary,
        shadow: MPShadow.button,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Ico(I.plus, size: 22, color: MP.white),
                const Gap(8),
                Text('Add patient', style: tx(16, w: w600, c: MP.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

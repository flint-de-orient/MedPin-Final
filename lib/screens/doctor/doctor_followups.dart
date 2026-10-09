import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d1.dart';

/// Design: Doctor-FollowUps.dc.html — "Doctor · Follow-ups (quick action)".
class DoctorFollowupsScreen extends StatefulWidget {
  const DoctorFollowupsScreen({super.key});

  @override
  State<DoctorFollowupsScreen> createState() => _DoctorFollowupsScreenState();
}

/// One follow-up row.
class _Fu {
  final String name;
  final String status;
  final Color bg;
  final Color fg;
  final String meta;
  final String advice;
  final String when;
  final List<String> actions;
  final bool booked;
  final List<String> conditions;
  const _Fu(
    this.name,
    this.status,
    this.bg,
    this.fg,
    this.meta,
    this.advice,
    this.when,
    this.actions, {
    required this.booked,
    required this.conditions,
  });
}

const _overdue = [
  _Fu(
    'Kaushik Paul',
    'No reply',
    MP.redSoft,
    MP.red,
    '47 M · Type 2 diabetes · +91 98307 44120',
    'You advised on 25 Aug: “Come back in 2 weeks with fasting sugar.”',
    '23 days overdue',
    ['Call', 'Remind'],
    booked: false,
    conditions: ['Type 2 diabetes'],
  ),
  _Fu(
    'Shreya Basu',
    'Not booked',
    MP.amberSoft,
    MP.amber,
    '33 F · Hypothyroidism · +91 90620 18834',
    'You advised on 14 Aug: “Repeat TSH after 4 weeks.”',
    '17 days overdue',
    ['Remind', 'Book'],
    booked: false,
    conditions: ['Hypothyroidism'],
  ),
];

const _thisWeek = [
  _Fu(
    'Moumita Roy',
    'Booked',
    MP.greenSoft,
    MP.green,
    '41 F · Cardiology review · +91 97480 62215',
    'You advised on 2 Sep: “Review after Dr. Mitra’s ECG.”',
    'Today, 11:00 AM · Salt Lake',
    ['View'],
    booked: true,
    conditions: ['Cardiology'],
  ),
  _Fu(
    'Amit Pal',
    'Booked',
    MP.greenSoft,
    MP.green,
    '55 M · Diabetes, CKD · +91 98303 11942',
    'You advised on 24 Sep: “Come fasting on Friday for KFT.”',
    'Fri, 2 Oct, 9:30 AM · Salt Lake',
    ['View'],
    booked: true,
    conditions: ['Type 2 diabetes', 'CKD'],
  ),
  _Fu(
    'Rina Dutta',
    'Reports in',
    MP.primarySoft,
    MP.primary,
    '44 F · Hypertension · +91 94330 27615',
    'You advised on 30 Sep: “Review with lipid profile and KFT.”',
    'Due Mon, 5 Oct',
    ['Remind', 'Book'],
    booked: false,
    conditions: ['Hypertension'],
  ),
  _Fu(
    'Tapas Kar',
    'Not booked',
    MP.amberSoft,
    MP.amber,
    '63 M · Hypertension, T2DM · +91 98312 60457',
    'You advised on 30 Sep: “BP check in one week.”',
    'Due Tue, 6 Oct',
    ['Remind', 'Book'],
    booked: false,
    conditions: ['Hypertension', 'Type 2 diabetes'],
  ),
];

const _tabs = ['All due · 35', 'Not booked · 18', 'Booked · 17'];
const _locations = [
  'All locations',
  'City Care Clinic · Salt Lake',
  'City Care · New Town',
  'Sen Diabetes Chamber · Gariahat',
];
const _conditions = ['All conditions', 'Type 2 diabetes', 'Hypertension', 'Hypothyroidism', 'Cardiology', 'CKD'];

class _DoctorFollowupsScreenState extends State<DoctorFollowupsScreen> {
  int _tab = 0;
  String _loc = _locations.first;
  String _cond = _conditions.first;

  bool _show(_Fu r) {
    if (_tab == 1 && r.booked) return false;
    if (_tab == 2 && !r.booked) return false;
    // Every follow-up listed here was advised at City Care Clinic · Salt Lake.
    if (_loc != _locations[0] && _loc != _locations[1]) return false;
    if (_cond != _conditions.first && !r.conditions.contains(_cond)) return false;
    return true;
  }

  Future<void> _pickLocation() async {
    final v = await D1Picker.show(context, title: 'Location', options: _locations, value: _loc);
    if (v != null && mounted) setState(() => _loc = v);
  }

  Future<void> _pickCondition() async {
    final v = await D1Picker.show(context, title: 'Condition', options: _conditions, value: _cond);
    if (v != null && mounted) setState(() => _cond = v);
  }

  void _act(String action, _Fu r) {
    switch (action) {
      case 'Call':
        toast(context, 'Calling ${r.name}…');
      case 'Remind':
        toast(context, 'Reminder sent to ${r.name}');
      default: // Book, View
        Nav.go(context, 'Appointments-Manage');
    }
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _overdue.where(_show).toList();
    final week = _thisWeek.where(_show).toList();
    return MpPage(
      header: _header(context),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gap: 12,
        children: [
          if (overdue.isNotEmpty) ...[
            _SectionHead(
              'Overdue',
              '4 patients · reminders sent to 2',
              action: 'Remind all',
              onAction: () => toast(context, 'Reminders sent to 4 patients'),
            ),
            _card(overdue),
            _MoreButton('Show 2 more overdue', onTap: () => Nav.go(context, 'Report-FollowUps')),
          ],
          if (week.isNotEmpty) ...[
            _SectionHead(
              'This week',
              '9 patients · 5 not booked yet',
              action: 'Remind 5',
              onAction: () => toast(context, 'Reminders sent to 5 patients'),
            ),
            _card(week),
            _MoreButton('Show 5 more this week', onTap: () => Nav.go(context, 'Appointments')),
          ],
          if (overdue.isEmpty && week.isEmpty)
            MpCard(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No follow-ups match these filters.',
                textAlign: TextAlign.center,
                style: tx(15, c: MP.ink2, h: 1.45),
              ),
            ),
          const _SectionHead('Later this month', '22 patients'),
          MpCard(
            onTap: () => Nav.go(context, 'Appointments'),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('8 – 31 Oct', style: tx(15, w: w700)),
                      const Gap(2),
                      Text('Reminders go out automatically 3 days before', style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
                const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
              ],
            ),
          ),
        ],
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: MpButton(
          'Schedule a follow-up',
          icon: I.plus,
          iconStroke: 1.75,
          onTap: () => Nav.go(context, 'Appointments'),
        ),
      ),
    );
  }

  /// White header: title row, status tabs and the two filter buttons.
  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                  const Gap(4),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Follow-ups',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(20, w: w700, h: 1.25),
                        ),
                        const Gap(1),
                        Text(
                          'Patients you asked to come back',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(13, c: MP.ink2),
                        ),
                      ],
                    ),
                  ),
                  const Gap(4),
                  MpIconButton(
                    I.search,
                    label: 'Search follow-ups',
                    iconSize: 20,
                    onTap: () => Nav.go(context, 'Doctor-Patients-Search'),
                  ),
                ],
              ),
            ),
          ),
          const Gap(12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _Tabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          const Gap(12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _FilterButton(_loc, active: _loc != _locations.first, onTap: _pickLocation),
                const Gap(8),
                _FilterButton(_cond, active: _cond != _conditions.first, onTap: _pickCondition),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<_Fu> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < rows.length; i++) _row(rows[i], first: i == 0)],
      ),
    );
  }

  Widget _row(_Fu r, {required bool first}) {
    return Tap(
      onTap: () => Nav.go(context, 'PP-Summary'),
      radius: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(r.name, style: tx(15, w: w700))),
                const Gap(10),
                D1Pill(r.status, bg: r.bg, fg: r.fg),
              ],
            ),
            const Gap(6),
            Text(r.meta, style: tx(13, c: MP.ink2, h: 1.4)),
            const Gap(6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(10)),
              child: Text(r.advice, style: tx(13, h: 1.45)),
            ),
            const Gap(6),
            Row(
              children: [
                Expanded(child: Text(r.when, style: tx(13, w: w600, c: MP.ink2))),
                const Gap(8),
                for (var i = 0; i < r.actions.length; i++) ...[
                  if (i > 0) const Gap(16),
                  Tap(
                    onTap: () => _act(r.actions[i], r),
                    radius: 6,
                    child: Text(r.actions[i], style: tx(14, w: w600, c: MP.primary)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Status tabs: #F1F4F9 track (padding 4, radius 16); selected tab white,
/// radius 12, hairline shadow, 600 #111827; others 500 #545E72.
class _Tabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _Tabs({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? MP.white : MP.white.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: i == index ? MPShadow.hairline : null,
                    ),
                    child: Text(
                      _tabs[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(14, w: i == index ? w600 : w500, c: i == index ? MP.ink : MP.ink2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 36px outlined filter button (radius 999, 14 / 600). Tonal when a filter is set.
class _FilterButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterButton(this.label, {required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Tap(
        onTap: onTap,
        radius: 999,
        color: active ? MP.primarySoft : MP.white,
        border: active ? MP.primary : MP.lineStrong,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(label, style: tx(14, w: w600, c: active ? MP.primary : MP.ink))],
          ),
        ),
      ),
    );
  }
}

/// Section heading (17 / 700 + 13px count line) with an optional pill action.
class _SectionHead extends StatelessWidget {
  final String title;
  final String sub;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHead(this.title, this.sub, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title, style: tx(17, w: w700)), const Gap(2), Text(sub, style: tx(13, c: MP.ink3))],
            ),
          ),
          if (action != null) ...[
            const Gap(8),
            SizedBox(
              height: 32,
              child: Tap(
                onTap: onAction,
                radius: 999,
                color: MP.primarySoft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(action!, style: tx(13, w: w600, c: MP.primary))],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 44px transparent "Show N more" button (15 / 600 #003399).
class _MoreButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MoreButton(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      child: SizedBox(height: 44, child: Center(child: Text(label, style: tx(15, w: w600, c: MP.primary)))),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d8.dart';

/// Design: Doctor-Home.dc.html — "Home" (Clinician · tabs).
class DoctorHomeScreen extends StatelessWidget {
  const DoctorHomeScreen({super.key});

  // Tones from renderVals(): (background, foreground).
  static const _danger = (MP.redSoft, MP.red);
  static const _warn = (MP.amberSoft, MP.amber);
  static const _neutral = (MP.fill, MP.ink2);
  static const _info = (MP.primarySoft, MP.primary);
  static const _ok = (MP.greenSoft, MP.green);

  static (Color, Color) _statusTone(String s) => switch (s) {
    'In consult' => _info,
    'Waiting' => _warn,
    'Done' => _ok,
    _ => _neutral,
  };

  static (Color, Color) _bandTone(String b) => switch (b) {
    'Critical' => _danger,
    'High' => _warn,
    'Low' => _ok,
    _ => _neutral,
  };

  static const _quick = [
    (I.stethoscope, 'Start consultation', 'Consult-Pick'),
    (I.activity, 'Record vitals', 'Consult-Vitals'),
    (I.fileText, 'Write prescription', 'Prescriptions'),
  ];

  static const _alerts = [
    _Alert(
      'Emergency',
      '9:12 AM',
      'Priya Sharma',
      'Emergency message: chest tightness and sweating since morning',
      _danger,
      'Patient-Thread',
    ),
    _Alert('Urgent', '8:40 AM', 'Rahul Das', 'Home BP reading 172/104 mmHg', _warn, 'PP-Summary'),
  ];

  static const _queue = [
    _Visit('9:00', 'Priya Sharma', 'In consult', '29 F · Follow-up', true, true),
    _Visit('9:30', 'Rahul Das', 'Waiting', '45 M · New', true, false),
    _Visit('10:00', 'Aisha Khan', 'Waiting', '52 F · Follow-up', true, false),
    _Visit('10:30', 'Sujit Mondal', 'Upcoming', '37 M · New', false, false),
    _Visit('11:00', 'Moumita Roy', 'Upcoming', '41 F · Follow-up', false, true),
  ];

  static const _review = [
    _Review('Critical lab', MP.red, '7:55 AM', 'Amit Pal', 'Potassium 6.1 mmol/L (critical high)', 'PP-Tests'),
    _Review(
      'Urgent message',
      MP.amber,
      '9:12 AM',
      'Priya Sharma',
      '“Chest feels tight since morning, should I come in?”',
      'Patient-Thread',
    ),
    _Review('Abnormal lab', MP.amber, 'Yesterday', 'Aisha Khan', 'TSH 8.9 mIU/L (high)', 'PP-Tests'),
    _Review(
      'Flagged chat',
      MP.ink2,
      'Yesterday',
      'Sujit Mondal',
      'AI answer about dosage timing flagged for review',
      'Chat-Review-Detail',
    ),
  ];

  static const _worse = [
    ('MR', 'Moumita Roy', 'Risk band Moderate → High', 'Changed 3 days ago'),
    ('AP', 'Amit Pal', '4 missed Metformin doses in a row', 'Last dose taken Fri, 25 Sep'),
    ('DB', 'Debasish Bose', 'Follow-up overdue by 9 days', 'Was due Sun, 20 Sep · no visit since'),
  ];

  static const _triage = [
    ('Amit Pal', 'Critical lab: potassium 6.1 mmol/L', 'Critical'),
    ('Priya Sharma', 'Open emergency alert', 'High'),
    ('Debasish Bose', 'HbA1c 9.4%, up from 8.1%', 'High'),
    ('Moumita Roy', 'Risk trend worsening', 'Moderate'),
  ];

  /// (count, label, stem, is a clinician tab).
  static const _actions = [
    ('6', 'Unread messages', 'Care', true),
    ('4', 'Check-ins overdue 7+ days', 'Doctor-FollowUps', false),
    ('3', 'Pending action items', 'Alerts', false),
    ('2', 'Nutrition reviews due', 'Nutrition', true),
  ];

  @override
  Widget build(BuildContext context) {
    return MpPage(
      nav: const ClinicianNav(current: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D8TabHeader(),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              _greeting(),
              _quickActions(context),
              _openAlerts(context),
              _opdQueue(context),
              _needsReview(context),
              _worsening(context),
              _triageQueue(context),
              _actionQueue(context),
              _weeklyImpact(),
            ],
          ),
        ],
      ),
    );
  }

  // ── Greeting ──────────────────────────────────────────────────────────────

  Widget _greeting() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good morning, Dr. Sen', style: tx(28, w: w800, h: 1.15, em: -0.02)),
          const Gap(6),
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle)),
              const Gap(8),
              Flexible(child: Text('Tue, 29 Sep 2026 · Updated 4s ago', style: tx(14, c: MP.ink2))),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick actions ─────────────────────────────────────────────────────────

  Widget _quickActions(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Quick actions',
      child: Row(
        children: [
          for (var i = 0; i < _quick.length; i++) ...[
            if (i > 0) const Gap(8),
            Expanded(
              child: _QuickTile(icon: _quick[i].$1, label: _quick[i].$2, onTap: () => Nav.go(context, _quick[i].$3)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Open alerts ───────────────────────────────────────────────────────────

  Widget _openAlerts(BuildContext context) {
    return MpCard(
      border: MP.redLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Open alerts',
                          style: tx(20, w: w700, h: 1.25),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Gap(10),
                      const MpBadge.red('2 open'),
                    ],
                  ),
                ),
                D8Link('View all', onTap: () => Nav.go(context, 'Alerts')),
              ],
            ),
          ),
          for (final a in _alerts) ...[
            const Gap(4),
            _RowLink(
              onTap: () => Nav.go(context, a.stem),
              padding: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            MpBadge(a.severity, bg: a.tone.$1, fg: a.tone.$2),
                            const Gap(8),
                            Flexible(child: Text(a.time, style: tx(13, c: MP.ink3, tab: true))),
                          ],
                        ),
                        const Gap(6),
                        Text(a.name, style: tx(16, w: w600)),
                        const Gap(6),
                        Text(a.detail, style: tx(14, c: MP.ink2, h: 1.45)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Today's OPD queue (hero) ──────────────────────────────────────────────

  Widget _opdQueue(BuildContext context) {
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: "Today's OPD queue",
            sub: '12 visits · 3 waiting · 4 done',
            trailing: _viewAll(context, 'Queue-List'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final l in const ['Vitals', 'Docs'])
                  SizedBox(
                    width: 44,
                    child: Text(
                      l.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: tx(11, w: w600, c: MP.ink3, em: 0.06),
                    ),
                  ),
              ],
            ),
          ),
          for (final q in _queue) _visitRow(context, q),
        ],
      ),
    );
  }

  Widget _visitRow(BuildContext context, _Visit q) {
    final tone = _statusTone(q.status);
    Widget mark(bool done, String label) => Semantics(
      label: label,
      child: SizedBox(
        width: 44,
        child: Center(
          child: done ? const Ico(I.check, size: 18, color: MP.green, stroke: 2.25) : const D8PendingIcon(),
        ),
      ),
    );
    return _RowLink(
      onTap: () => Nav.go(context, 'PP-Summary'),
      padding: 12,
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(q.time, style: tx(15, w: w600, tab: true), maxLines: 1)),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.name, style: tx(16, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Gap(4),
                LayoutBuilder(
                  builder:
                      (context, c) => Row(
                        children: [
                          // Full size normally; only scales down if very large
                          // text would leave the meta no room.
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: math.max(0, c.maxWidth - 40)),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: MpBadge(q.status, bg: tone.$1, fg: tone.$2, height: 22, padX: 8, weight: w600),
                            ),
                          ),
                          const Gap(8),
                          // Wraps (e.g. "29 F · Follow-" / "up") as in the design.
                          Flexible(child: Text(q.meta, style: tx(13, c: MP.ink3))),
                        ],
                      ),
                ),
              ],
            ),
          ),
          const Gap(12),
          mark(q.vitals, q.vitals ? 'Vitals on file today' : 'Vitals not yet recorded'),
          const Gap(12),
          mark(q.docs, q.docs ? 'Reports uploaded for this visit' : 'No reports for this visit'),
        ],
      ),
    );
  }

  // ── Needs review ──────────────────────────────────────────────────────────

  Widget _needsReview(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: 'Needs review',
            sub: '4 items since yesterday, most urgent first',
            trailing: _viewAll(context, 'Alerts'),
          ),
          for (final r in _review)
            _RowLink(
              onTap: () => Nav.go(context, r.stem),
              padding: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SectionLabel(r.kind, color: r.kindColor),
                            const Gap(8),
                            Flexible(
                              child: Text(
                                '· ${r.time}',
                                style: tx(13, c: MP.ink3, tab: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const Gap(4),
                        Text(r.name, style: tx(16, w: w600)),
                        const Gap(4),
                        Text(r.detail, style: tx(14, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
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

  // ── Worsening or off-track ────────────────────────────────────────────────

  Widget _worsening(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: 'Worsening or off-track',
            sub: 'Trends worth a look this week',
            trailing: const Padding(padding: EdgeInsets.only(top: 2), child: MpBadge.amber('3 patients')),
          ),
          for (final w in _worse)
            _RowLink(
              onTap: () => Nav.go(context, 'PP-Summary'),
              padding: 14,
              child: Row(
                children: [
                  MpAvatar(w.$1, size: 40, fontSize: 14),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.$2, style: tx(16, w: w600)),
                        const Gap(2),
                        Text(w.$3, style: tx(14, w: w600, c: MP.amber)),
                        const Gap(2),
                        Text(w.$4, style: tx(13, c: MP.ink3)),
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

  // ── Triage queue ──────────────────────────────────────────────────────────

  Widget _triageQueue(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: 'Triage queue',
            sub: 'Patients ranked by who needs you first',
            trailing: _viewAll(context, 'Queue-List'),
          ),
          for (final t in _triage)
            _RowLink(
              onTap: () => Nav.go(context, 'PP-Summary'),
              padding: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$1, style: tx(16, w: w600)),
                        const Gap(2),
                        Text(t.$2, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  MpBadge(t.$3, bg: _bandTone(t.$3).$1, fg: _bandTone(t.$3).$2),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Action queue ──────────────────────────────────────────────────────────

  Widget _actionQueue(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Action queue', style: tx(20, w: w700, h: 1.25)),
          const Gap(16),
          MpGrid(
            columns: 2,
            gap: 8,
            children: [
              for (final x in _actions)
                Tap(
                  onTap: () => x.$4 ? Nav.tab(context, x.$3) : Nav.go(context, x.$3),
                  radius: 12,
                  color: MP.bg,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(x.$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                      const Gap(6),
                      Text(x.$2, style: tx(14, c: MP.ink2, h: 1.35)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Weekly impact ─────────────────────────────────────────────────────────

  Widget _weeklyImpact() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weekly impact', style: tx(20, w: w700, h: 1.25)),
              const Gap(2),
              Text('Last 7 days · 64 consultations', style: tx(14, c: MP.ink2)),
            ],
          ),
          const Gap(20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Avg consultation time'),
              const Gap(4),
              Text.rich(
                TextSpan(
                  text: '9',
                  // " min" inherits the parent's computed -0.6px letter-spacing.
                  children: [TextSpan(text: ' min', style: tx(16, w: w600, c: MP.ink2, h: 1, em: -0.6 / 16))],
                ),
                style: tx(30, w: w800, h: 1, em: -0.02, tab: true),
              ),
            ],
          ),
          const Gap(20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Patient chats'),
              const Gap(10),
              const _ChatSplitBar(),
              const Gap(10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _legend(MP.primary, '142', 'handled by AI'),
                  const Gap(8),
                  _legend(MP.primaryLine, '18', 'escalated'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color swatch, String n, String text) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(2)),
          ),
          const Gap(6),
          Text(n, style: tx(14, w: w700, tab: true)),
          const Gap(6),
          Flexible(child: Text(text, style: tx(14, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  static Widget _viewAll(BuildContext context, String stem) =>
      D8Link('View all', padding: const EdgeInsets.only(top: 3), onTap: () => Nav.go(context, stem));
}

// ─────────────────────────────────────────────────────────────────────────────

class _Alert {
  final String severity;
  final String time;
  final String name;
  final String detail;
  final (Color, Color) tone;
  final String stem;
  const _Alert(this.severity, this.time, this.name, this.detail, this.tone, this.stem);
}

class _Visit {
  final String time;
  final String name;
  final String status;
  final String meta;
  final bool vitals;
  final bool docs;
  const _Visit(this.time, this.name, this.status, this.meta, this.vitals, this.docs);
}

class _Review {
  final String kind;
  final Color kindColor;
  final String time;
  final String name;
  final String detail;
  final String stem;
  const _Review(this.kind, this.kindColor, this.time, this.name, this.detail, this.stem);
}

/// Card heading: 20/700 title + 14px subtitle on the left, [trailing] on the
/// right (`align-items: flex-start; padding-bottom: 12px`).
class _CardHead extends StatelessWidget {
  final String title;
  final String sub;
  final Widget trailing;
  const _CardHead({required this.title, required this.sub, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(20, w: w700, h: 1.25)),
                const Gap(2),
                Text(sub, style: tx(14, c: MP.ink2)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// A list row inside a card: `padding: Npx 0; border-top: 1px solid #E5E9F0`.
class _RowLink extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double padding;
  const _RowLink({required this.child, required this.onTap, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 0,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: padding),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: child,
      ),
    );
  }
}

/// 84px quick-action tile: icon on top, label at the bottom
/// (`justify-content: space-between`). As in the design's flexbox, a two-line
/// label that doesn't fit next to the 22px icon makes the icon shrink
/// (`flex-shrink: 1`) instead of overflowing.
class _QuickTile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _QuickTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: 84,
      child: Tap(
        onTap: onTap,
        radius: 12,
        color: MP.white,
        border: MP.line,
        shadow: MPShadow.card,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: LayoutBuilder(
          builder: (context, c) {
            final style = _fitLongestWord(tx(14, w: w600, h: 1.25), c.maxWidth, scaler);
            final tp = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
            )..layout(maxWidth: c.maxWidth);
            final iconHeight = (c.maxHeight - tp.height).clamp(0.0, 22.0);
            tp.dispose();
            return OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    height: iconHeight,
                    child: FittedBox(child: Ico(icon, size: 22, color: MP.primary)),
                  ),
                  Text(label, style: style),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Shrinks the font just enough for the longest word to fit (narrow
  /// phones), instead of breaking a word in the middle.
  TextStyle _fitLongestWord(TextStyle style, double maxWidth, TextScaler scaler) {
    var widest = 0.0;
    for (final word in label.split(' ')) {
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }
    if (widest <= maxWidth || widest == 0) return style;
    final size = style.fontSize ?? 14;
    return style.copyWith(fontSize: (size * maxWidth / widest * 4).floorToDouble() / 4);
  }
}

/// 10px split bar: 88.75% #003399, 2px gap, rest #B8C6E3, radius 999.
class _ChatSplitBar extends StatelessWidget {
  const _ChatSplitBar();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '142 handled by AI, 18 escalated to the clinic',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder:
                (context, c) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: c.maxWidth * 0.8875, child: const ColoredBox(color: MP.primary)),
                    const SizedBox(width: 2),
                    const Expanded(child: ColoredBox(color: MP.primaryLine)),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

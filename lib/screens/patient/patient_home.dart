import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';
import 'patient_log.dart';

/// Design: Main.dc.html — "Patient · Home".
class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

typedef _Task = ({String icon, String title, String sub, String action, String later, String doneLabel});

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  static const List<_Task> _tasks = [
    (icon: I.pill, title: 'Glimepiride 1 mg', sub: '7:30 AM · before breakfast', action: '', later: '', doneLabel: 'Taken'),
    (icon: I.pill, title: 'Metformin 500 mg', sub: '8:30 AM · after breakfast', action: '', later: '', doneLabel: 'Taken'),
    (icon: I.drop, title: 'Log fasting sugar', sub: 'Best before breakfast', action: 'Log', later: '', doneLabel: 'Logged'),
    (icon: I.upload, title: 'Upload HbA1c report', sub: 'Dr. Sen needs it before 5 PM', action: 'Upload', later: '', doneLabel: 'Uploaded'),
    (icon: I.pill, title: 'Metformin 500 mg', sub: '8:30 PM · after dinner', action: '', later: 'Tonight', doneLabel: 'Taken'),
  ];

  /// Watch / wearable icon (smartwatch and ring sync).
  static const _watch = '<rect x="6" y="6" width="12" height="12" rx="3"/><path d="M9 6V3h6v3M9 18v3h6v-3M12 10v2l1 1"/>';

  final Set<int> _done = {0, 1};
  bool _walkDone = false;

  void _taskAction(BuildContext context, int i) {
    if (_tasks[i].action == 'Upload') {
      Nav.go(context, 'Records-Add');
    } else {
      setState(() => _done.add(i));
    }
  }

  void _openLog(BuildContext context, int tab) {
    if (tab == 0) {
      Nav.go(context, 'Patient-Log');
    } else {
      openSheet<void>(context, (_) => PatientLogSheet(initialTab: tab));
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return MpPage(
      nav: const PatientNav(current: 0),
      overlays: [
        Positioned(
          right: 20,
          bottom: 108 + safeBottom,
          child: _AskFab(onTap: () => Nav.go(context, 'Patient-AskAI')),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const Gap(20),
          // The slide row bleeds into the right gutter (margin-right: -20px).
          const Padding(padding: EdgeInsets.only(left: 20), child: _HeroCarousel()),
          const Gap(16),
          _pad(_emergency(context)),
          const Gap(16),
          _pad(_today(context)),
          const Gap(16),
          _pad(_dailyLog(context)),
          const Gap(16),
          _pad(_health(context)),
          const Gap(16),
          _pad(_summary(context)),
          const Gap(16),
          _pad(_tracking(context)),
          const Gap(16),
          _pad(_fromDoctor(context)),
          // main has 184px below it; MpPage already leaves 112 for the nav.
          const Gap(72),
        ],
      ),
    );
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  Widget _card({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    return Container(padding: padding, decoration: MPDeco.card(), child: child);
  }

  Widget _cardTitle(String text) => Text(text, style: tx(20, w: w700, h: 1.25));

  /// Card heading with a link on the right, baseline-aligned.
  Widget _cardHeading(String text, String link, VoidCallback onLink) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: _cardTitle(text)),
        const Gap(12),
        _TextLink(link, onTap: onLink),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Good morning,', style: tx(15, c: MP.ink2)),
                const Gap(2),
                Text('Priya', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              ],
            ),
          ),
          const Gap(12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              MpIconButton(
                I.bell,
                label: 'Notifications, 1 new',
                iconSize: 20,
                radius: 999,
                background: MP.white,
                borderColor: MP.line,
                onTap: () => toast(context, 'Notifications are coming soon'),
              ),
              // 8px dot + 2px white ring, top 9 / right 10 inside the border.
              Positioned(
                top: 10,
                right: 11,
                child: IgnorePointer(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: MP.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: MP.white, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Gap(8),
          Semantics(
            button: true,
            label: 'Profile',
            child: Tap(
              onTap: () => Nav.tab(context, 'Patient-Me'),
              radius: 999,
              child: const MpAvatar('PS', size: 44, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ── Emergency link ────────────────────────────────────────────────────────

  Widget _emergency(BuildContext context) {
    // <a> is content-box: 52px + the 1px border = 54px.
    return Tap(
      onTap: () => Nav.go(context, 'Patient-Emergency'),
      radius: 16,
      color: MP.white,
      border: MP.redLine,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Ico(I.messageAlert, size: 18, color: MP.red),
              const Gap(12),
              Expanded(
                child: Text(
                  'Emergency? Chat with your doctor',
                  style: tx(15, w: w600, c: MP.red),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Gap(12),
              const Ico(I.chevronRight, size: 18, color: MP.red),
            ],
          ),
        ),
      ),
    );
  }

  // ── Today's checklist ─────────────────────────────────────────────────────

  Widget _today(BuildContext context) {
    final n = _done.length;
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: _cardTitle('Today')),
                    Text('$n of ${_tasks.length} done', style: tx(14, c: MP.ink2, tab: true)),
                  ],
                ),
                const Gap(10),
                Semantics(
                  label: '$n of ${_tasks.length} tasks done',
                  child: MpProgress(n / _tasks.length, height: 6, color: MP.green, track: MP.line),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _tasks.length; i++) _taskRow(context, i),
        ],
      ),
    );
  }

  Widget _taskRow(BuildContext context, int i) {
    final t = _tasks[i];
    final done = _done.contains(i);
    final Widget trailing;
    if (done) {
      trailing = _DoneBadge(t.doneLabel);
    } else if (t.action.isNotEmpty) {
      trailing = P1SoftButton(t.action, onTap: () => _taskAction(context, i));
    } else {
      trailing = Text(t.later, style: tx(13, w: w600, c: MP.ink3));
    }
    return _ListRow(
      first: i == 0,
      child: Row(
        children: [
          MpIconTile(t.icon, size: 40, iconSize: 20, radius: 12, bg: MP.fill, fg: MP.ink2),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: tx(16, w: w600, c: done ? MP.ink2 : MP.ink)),
                const Gap(2),
                Text(t.sub, style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Gap(12),
          trailing,
        ],
      ),
    );
  }

  // ── Daily log ─────────────────────────────────────────────────────────────

  Widget _dailyLog(BuildContext context) {
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _cardHeading('Daily log', 'History', () => toast(context, 'Log history is coming soon')),
          ),
          _ListRow(
            first: true,
            child: _LogLine(
              title: const Text('Meals'),
              sub: 'Breakfast logged · lunch next',
              trailing: P1SoftButton('Log meal', icon: I.camera, onTap: () => _openLog(context, 0)),
            ),
          ),
          _ListRow(
            child: _LogLine(
              title: const Text('Evening walk · 30 min'),
              sub: 'Planned 6:00 PM · ${_walkDone ? 4 : 3} of 5 this week',
              trailing: _walkDone
                  ? const _DoneBadge('Done')
                  : P1SoftButton('Mark done', onTap: () => setState(() => _walkDone = true)),
            ),
          ),
          _ListRow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LogLine(
                  title: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '4,820', style: tx(16, w: w600, tab: true)),
                      const TextSpan(text: ' steps'),
                    ]),
                  ),
                  sub: 'Goal 8,000 · entered by you',
                  trailing: P1SoftButton('Add', onTap: () => _openLog(context, 2)),
                ),
                const Gap(8),
                Semantics(
                  label: '4,820 of 8,000 steps',
                  child: const MpProgress(0.6, height: 6, color: MP.primary, track: MP.line),
                ),
              ],
            ),
          ),
          Tap(
            onTap: () => Nav.go(context, 'Patient-DoctorDetail'),
            radius: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  const Ico(I.share, size: 16, color: MP.ink2),
                  const Gap(10),
                  Expanded(child: Text('Shared with Dr. Sen and Mou (dietician)', style: tx(13, c: MP.ink2))),
                  const Gap(10),
                  Text('Change', style: tx(14, w: w600, c: MP.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Your health: scores ───────────────────────────────────────────────────

  Widget _health(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle('Your health'),
          const Gap(16),
          MpGrid(
            columns: 2,
            children: [
              _Tile(
                onTap: () => toast(context, 'Health score details are coming soon'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CustomPaint(
                            painter: const _RingPainter(111.6 / (2 * math.pi * 24)),
                            child: Center(child: Text('74', style: tx(18, w: w800, tab: true))),
                          ),
                        ),
                        const Gap(12),
                        Expanded(child: Text('+3 this week', style: tx(13, w: w700, c: MP.green))),
                      ],
                    ),
                    const Gap(10),
                    Text('Health score', style: tx(15, w: w700)),
                    const Gap(2),
                    Text('out of 100', style: tx(13, c: MP.ink2)),
                  ],
                ),
              ),
              _Tile(
                onTap: () => Nav.go(context, 'Patient-Adherence'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 56,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('86%', style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                      ),
                    ),
                    const Gap(10),
                    Text('Adherence', style: tx(15, w: w700)),
                    const Gap(2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('3 doctors', style: tx(13, w: w600, c: MP.primary)),
                        const Gap(2),
                        const Ico(I.chevronRight, size: 14, color: MP.primary, stroke: 2),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── AI health summary ─────────────────────────────────────────────────────

  Widget _summary(BuildContext context) {
    Widget focus(String n, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n, style: tx(15, w: w800, h: 1.45, c: MP.primary)),
            const Gap(10),
            Expanded(child: Text(text, style: tx(15, h: 1.45))),
          ],
        );
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Ico(I.sparkle, size: 20, color: MP.primary),
              const Gap(8),
              Expanded(child: _cardTitle('Health summary')),
              const Gap(12),
              Text('Updated today', style: tx(13, c: MP.ink3)),
            ],
          ),
          const Gap(14),
          Text(
            'Your sugar has crept up a little since July (HbA1c 7.2%) and bad cholesterol (LDL) is still high. '
            'You missed 4 evening doses of Metformin this week. Taking it every evening is the biggest help right now.',
            style: tx(16, h: 1.55),
          ),
          const Gap(14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('FOCUS THIS WEEK', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                const Gap(8),
                focus('1', 'Take Metformin after dinner, every day'),
                const Gap(8),
                focus('2', 'Walk 30 minutes, 5 days a week'),
              ],
            ),
          ),
          const Gap(14),
          Row(
            children: [
              Expanded(child: Text('From your reports and medicines. Not a diagnosis.', style: tx(13, c: MP.ink3))),
              const Gap(12),
              _TextLink('Read more', onTap: () => toast(context, 'The full summary is coming soon')),
            ],
          ),
        ],
      ),
    );
  }

  // ── What you track ────────────────────────────────────────────────────────

  Widget _tracking(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeading('What you track', 'Customize', () => Nav.go(context, 'Patient-Track')),
          const Gap(14),
          MpGrid(
            columns: 2,
            children: [
              _TrackTile(
                label: 'Fasting sugar',
                value: '142',
                unit: ' mg/dL',
                points: '2,10 22,15 43,19 64,17 85,13 106,20 128,16',
                note: 'Above target',
                noteColor: MP.amber,
                onTap: () => toast(context, 'Fasting sugar trend is coming soon'),
              ),
              _TrackTile(
                label: 'Blood pressure',
                value: '128/82',
                points: '2,18 22,16 43,20 64,15 85,17 106,14 128,16',
                note: 'Normal',
                noteColor: MP.green,
                onTap: () => toast(context, 'Blood pressure trend is coming soon'),
              ),
            ],
          ),
          const Gap(14),
          Tap(
            onTap: () => toast(context, 'Device sync is coming soon'),
            radius: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  const Ico(_watch, size: 20, color: MP.ink2),
                  const Gap(12),
                  Expanded(child: Text('Smartwatch and ring sync', style: tx(14, c: MP.ink2))),
                  const Gap(12),
                  const MpBadge.grey('Coming soon'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── From your doctor ──────────────────────────────────────────────────────

  Widget _fromDoctor(BuildContext context) {
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _cardHeading('From your doctor', 'All records', () => Nav.go(context, 'Patient-Records')),
          ),
          _ListRow(
            first: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prescription · 29 Sep', style: tx(16, w: w600)),
                      const Gap(3),
                      Text('Dr. Arjun Sen · 3 medicines · valid till 29 Oct', style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
                const Gap(12),
                MpIconButton(
                  I.download,
                  label: 'Download prescription',
                  iconSize: 18,
                  color: MP.primary,
                  background: MP.white,
                  borderColor: MP.lineStrong,
                  onTap: () => toast(context, 'Prescription downloaded'),
                ),
              ],
            ),
          ),
          _ListRow(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Diabetes panel · 18 Jul', style: tx(16, w: w600)),
                      const Gap(4),
                      Row(
                        children: [
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(999)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [Text('2 values high', style: tx(12, w: w700, c: MP.amber))],
                            ),
                          ),
                          const Gap(8),
                          Flexible(child: Text('HbA1c, fasting sugar', style: tx(13, c: MP.ink2))),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                P1SoftButton(
                  'Explain',
                  icon: I.sparkle,
                  iconStroke: 2,
                  padding: 14,
                  onTap: () => Nav.go(context, 'Patient-AskAI'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero carousel: 4 slides, slide 1 shown, the next one peeks 36px.
// Swipe or auto-advance every 6 s.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel();

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  PageController? _pc;
  double _fraction = 0;
  int _page = 0;
  bool _dragging = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _advance());
  }

  void _advance() {
    final pc = _pc;
    if (!mounted || _dragging || pc == null || !pc.hasClients) return;
    pc.animateToPage(
      (_page + 1) % P1.slides.length,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// One page = slide + 12px gap, leaving a 36px peek of the next slide.
  PageController _controllerFor(double fraction) {
    final current = _pc;
    if (current != null && (fraction - _fraction).abs() < 0.0005) return current;
    _fraction = fraction;
    final next = PageController(viewportFraction: fraction, initialPage: _page);
    if (current != null) WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    return _pc = next;
  }

  /// Scroll position in slides. With padEnds off the last slide is fully in
  /// view at page n − 1/fraction (≈2.89), so that stretch is mapped to n − 1.
  double _position(PageController pc) {
    final n = P1.slides.length;
    var p = pc.hasClients ? (pc.page ?? _page.toDouble()) : _page.toDouble();
    final last = _fraction > 0 ? n - 1 / _fraction : n - 1.0;
    if (p > n - 2 && last > n - 2) p = n - 2 + (p - (n - 2)) / (last - (n - 2));
    return p.clamp(0.0, n - 1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const slides = P1.slides;
    return Semantics(
      label: 'Highlights, slide ${_page + 1} of ${slides.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 212,
            child: LayoutBuilder(
              builder: (context, c) {
                final pc = _controllerFor((c.maxWidth - 36) / c.maxWidth);
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification && n.dragDetails != null) _dragging = true;
                    if (n is ScrollEndNotification) _dragging = false;
                    return false;
                  },
                  child: PageView.builder(
                    controller: pc,
                    padEnds: false,
                    itemCount: slides.length,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      _schedule();
                    },
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AnimatedBuilder(
                        animation: pc,
                        builder: (context, _) {
                          // As drawn on the home artboard, the peeking slide is #002470
                          // with only its tag; the current one is the full #003399 slide.
                          final t = (1 - (_position(pc) - i).abs()).clamp(0.0, 1.0);
                          return P1HeroSlide(
                            slide: slides[i],
                            imageWidth: 200,
                            stops: const [0.42, 0.64, 0.88],
                            textMaxWidth: 200,
                            background: Color.lerp(MP.primaryDark, MP.primary, t)!,
                            contentOpacity: t,
                            onTap: () => i == _page
                                ? P1.openSlide(context, slides[i])
                                : pc.animateToPage(i, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Gap(12),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? MP.primary : MP.lineStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pieces
// ─────────────────────────────────────────────────────────────────────────────

/// A list row inside a card: 14px top/bottom, 1px #E5E9F0 rule above (not on the first).
class _ListRow extends StatelessWidget {
  final Widget child;
  final bool first;
  const _ListRow({required this.child, this.first = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: child,
    );
  }
}

/// Title (16/600) + sub (13, #545E72) with a trailing control.
class _LogLine extends StatelessWidget {
  final Widget title;
  final String sub;
  final Widget trailing;
  const _LogLine({required this.title, required this.sub, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(style: tx(16, w: w600), child: title),
              const Gap(2),
              Text(sub, style: tx(13, c: MP.ink2)),
            ],
          ),
        ),
        const Gap(12),
        trailing,
      ],
    );
  }
}

/// Green "✓ Taken" pill: 28px, #E7F5EE, 13/700 #076B3C.
class _DoneBadge extends StatelessWidget {
  final String label;
  const _DoneBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Ico(I.check, size: 14, color: MP.green, stroke: 2.5),
          const Gap(4),
          Text(label, style: tx(13, w: w700, c: MP.green)),
        ],
      ),
    );
  }
}

/// Plain text link (14/600 #003399), no extra height.
class _TextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TextLink(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(label, style: tx(14, w: w600, c: MP.primary)),
      ),
    );
  }
}

/// #F7F9FC tile, radius 16, padding 14.
class _Tile extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Tile({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(onTap: onTap, radius: 16, color: MP.bg, padding: const EdgeInsets.all(14), child: child);
  }
}

/// A tracked measure: label, value (+unit), 130×32 sparkline, status note.
class _TrackTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String points;
  final String note;
  final Color noteColor;
  final VoidCallback onTap;
  const _TrackTile({
    required this.label,
    required this.value,
    this.unit,
    required this.points,
    required this.note,
    required this.noteColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Tile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tx(13, c: MP.ink2)),
          const Gap(4),
          Text.rich(
            TextSpan(
              text: value,
              children: [if (unit != null) TextSpan(text: unit, style: tx(12, w: w600, c: MP.ink3))],
            ),
            style: tx(22, w: w800, tab: true),
          ),
          const Gap(4),
          CustomSingleChildLayout(
            delegate: const _SparkLayout(),
            child: Svg(
              '<svg viewBox="0 0 130 32"><polyline points="$points" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>',
              fit: BoxFit.fill,
            ),
          ),
          const Gap(4),
          Text(note, style: tx(12, w: w700, c: noteColor)),
        ],
      ),
    );
  }
}

/// The sparkline is 130×32 and, as in the design, runs 8px into the tile's
/// right padding; on narrower phones it narrows instead of spilling out.
class _SparkLayout extends SingleChildLayoutDelegate {
  const _SparkLayout();

  @override
  Size getSize(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth, 32));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = constraints.maxWidth.isFinite ? math.min(130.0, constraints.maxWidth + 8) : 130.0;
    return BoxConstraints.tightFor(width: w, height: 32);
  }

  @override
  bool shouldRelayout(_SparkLayout oldDelegate) => false;
}

/// Health score ring: r 24, 6px #E5E9F0 track, #076B3C arc from 12 o'clock.
class _RingPainter extends CustomPainter {
  final double value;
  const _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 24.0;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = MP.line,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = MP.green,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.value != value;
}

/// "Ask MedPin AI" floating button: 56px, radius 16, #003399, strong shadow.
class _AskFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AskFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 16,
      color: MP.primary,
      shadow: MPShadow.buttonStrong,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Ico(I.sparkle, size: 22, color: MP.white),
              const Gap(8),
              Text('Ask MedPin AI', style: tx(16, w: w700, c: MP.white)),
            ],
          ),
        ),
      ),
    );
  }
}

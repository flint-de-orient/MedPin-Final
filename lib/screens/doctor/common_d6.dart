import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';

// Shared pieces for batch D6: Patient-Profile, Patient-Profile-Desk and the
// four doctor-view profile tabs (PP-Summary, PP-Prescriptions, PP-Tests,
// PP-Treatment).

/// Actions on the patient shown in these screens (Priya Sharma).
class D6Patient {
  D6Patient._();

  static void phone(BuildContext context) => toast(context, 'Calling Priya · +91 98765 43210');
  static void message(BuildContext context) => Nav.go(context, 'Patient-Thread');
  static void prescriptions(BuildContext context) => Nav.go(context, 'Prescriptions');
  static void startConsult(BuildContext context) => Nav.go(context, 'Consult-Page');
}

/// CSS flexbox sizing for a row of two content-sized items `a` and `b`
/// (each a column of text lines). `a` has flex-grow 1 and takes the spare
/// room; when the content no longer fits, both shrink in proportion to their
/// max-content width (flex-shrink 1), never below their min-content width
/// (widest word) — or 0 for `a` when [aMinZero] (CSS `min-width: 0`).
class D6Flex {
  D6Flex._();

  static (double, double) pair(
    BuildContext context, {
    required double avail,
    required List<(String, TextStyle)> a,
    required List<(String, TextStyle)> b,
    bool aMinZero = false,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    (double, double) measure(List<(String, TextStyle)> lines) {
      var maxW = 0.0, minW = 0.0;
      for (final (s, st) in lines) {
        final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
        maxW = math.max(maxW, tp.maxIntrinsicWidth);
        minW = math.max(minW, tp.minIntrinsicWidth);
        tp.dispose();
      }
      return (maxW.ceilToDouble(), minW.ceilToDouble());
    }

    final (baseA, minContentA) = measure(a);
    final (baseB, minB) = measure(b);
    final minA = aMinZero ? 0.0 : minContentA;
    if (avail <= 0) return (0, 0);
    if (baseA + baseB <= avail) return (avail - baseB, baseB);
    var wa = baseA * avail / (baseA + baseB);
    var wb = avail - wa;
    if (wa < minA) {
      wa = minA;
      wb = math.max(0, avail - wa);
    } else if (wb < minB) {
      wb = minB;
      wa = math.max(0, avail - wb);
    }
    return (wa, wb);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Pill / badge with 12px text. Height, padding, weight and colours vary per
/// design (24px · 0 10 · 700 is the common one).
class D6Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double height;
  final double padH;
  final FontWeight weight;
  final Color? border;
  final String? icon;
  const D6Pill(
    this.text, {
    super.key,
    this.bg = MP.fill,
    this.fg = MP.ink2,
    this.height = 24,
    this.padH = 10,
    this.weight = w700,
    this.border,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: padH),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Ico(icon!, size: 14, color: fg, stroke: 2), const Gap(4)],
          Text(text, style: tx(12, w: weight, c: fg), maxLines: 1),
        ],
      ),
    );
  }
}

/// Inline text link (#003399 / 600) with an optional leading or trailing
/// chevron-style icon (stroke 2). [minHeight] mirrors CSS `min-height`.
class D6Link extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double size;
  final String? icon;
  final String? leading;
  final double iconSize;
  final double minHeight;
  const D6Link(
    this.label, {
    super.key,
    this.onTap,
    this.size = 14,
    this.icon,
    this.leading,
    this.iconSize = 16,
    this.minHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: Tap(
        onTap: onTap ?? () {},
        radius: 8,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[Ico(leading!, size: iconSize, color: MP.primary, stroke: 2), const Gap(4)],
              Text(label, style: tx(size, w: w600, c: MP.primary)),
              if (icon != null) ...[const Gap(4), Ico(icon!, size: iconSize, color: MP.primary, stroke: 2)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Card heading: 20/700 title with an optional 14px #545E72 subtitle (gap 2).
class D6Title extends StatelessWidget {
  final String title;
  final String? sub;

  /// Subtitle line-height (CSS 1.45); pass null for `normal`.
  final double? subH;
  const D6Title(this.title, {super.key, this.sub, this.subH = 1.45});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: tx(20, w: w700, h: 1.25)),
        if (sub != null) ...[const Gap(2), Text(sub!, style: tx(14, c: MP.ink2, h: subH))],
      ],
    );
  }
}

/// Card heading row: title on the left, a compact link on the right.
class D6TitleLink extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback? onTap;
  const D6TitleLink(this.title, {super.key, required this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: tx(20, w: w700, h: 1.25))),
        const Gap(12),
        D6Link(action, onTap: onTap),
      ],
    );
  }
}

/// List row inside a card: 1px #E5E9F0 top border + vertical padding,
/// optionally tappable (ripple across the row).
class D6Row extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const D6Row({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.symmetric(vertical: 14)});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: padding,
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: child,
    );
    if (onTap == null) return row;
    return Tap(onTap: onTap, radius: 0, child: row);
  }
}

/// Uppercase caption (12px, .06em).
class D6Caps extends StatelessWidget {
  final String text;
  final Color color;
  final FontWeight weight;
  final double? h;
  const D6Caps(this.text, {super.key, this.color = MP.ink3, this.weight = w700, this.h});

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: tx(12, w: weight, c: color, em: 0.06, h: h));
}

/// An SVG chart drawn verbatim from the design at its natural size
/// ([width]×[height]); scales down only when the card is narrower.
class D6Chart extends StatelessWidget {
  final String svg;
  final double width;
  final double height;
  const D6Chart(this.svg, {super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = math.min(width, c.maxWidth);
        return Align(alignment: Alignment.centerLeft, child: Svg(svg, width: w, height: w * height / width));
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patient-Profile / Patient-Profile-Desk
// ─────────────────────────────────────────────────────────────────────────────

/// Identity hero: avatar, risk, name, conditions, quick actions, chief
/// complaint and (doctor view) the Start consultation button.
class D6ProfileHero extends StatelessWidget {
  final bool consult;
  const D6ProfileHero({super.key, this.consult = false});

  @override
  Widget build(BuildContext context) {
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: VGap(
        gap: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [MpAvatar('PS', size: 72, fontSize: 24), D6Pill('High risk', bg: MP.amberSoft, fg: MP.amber)],
              ),
              const Gap(12),
              Text('Priya Sharma', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              const Gap(4),
              Text('29 yrs · Female · +91 98765 43210', style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
            ],
          ),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              D6Pill('Type 2 diabetes', weight: w600),
              D6Pill('PCOS', weight: w600),
              D6Pill('Allergy: Sulfa drugs', bg: MP.white, fg: MP.amber, border: MP.amber, weight: w600, icon: I.alert),
            ],
          ),
          Row(
            children: [
              Expanded(flex: 4, child: _QuickAction(I.phone, 'Call', onTap: () => D6Patient.phone(context))),
              const Gap(8),
              Expanded(flex: 4, child: _QuickAction(I.message, 'Message', onTap: () => D6Patient.message(context))),
              const Gap(8),
              Expanded(
                flex: 5,
                child: _QuickAction(I.fileText, 'Prescriptions', onTap: () => D6Patient.prescriptions(context)),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(
                style: tx(14, c: MP.ink2, h: 1.45),
                children: [
                  TextSpan(text: 'Chief complaint:', style: tx(14, w: w600, h: 1.45)),
                  const TextSpan(text: ' chest tightness, fatigue'),
                ],
              ),
            ),
          ),
          if (consult) MpButton('Start consultation', onTap: () => D6Patient.startConsult(context)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      color: MP.primarySoft,
      child: SizedBox(
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Ico(icon, size: 20, color: MP.primary),
            const Gap(4),
            Text(label, style: tx(14, w: w600, c: MP.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// "Priya shares her full record…" consent note.
class D6ConsentNote extends StatelessWidget {
  const D6ConsentNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Ico(I.shield, size: 20, color: MP.primary),
          const Gap(10),
          Expanded(
            child: Text(
              'Priya shares her full record with City Care Clinic. She controls this.',
              style: tx(14, h: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// "CLINICAL RECORD" caption (padding-top 8).
class D6RecordCaption extends StatelessWidget {
  const D6RecordCaption({super.key});

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.only(top: 8), child: D6Caps('Clinical record', weight: w600, h: 1.35));
}

/// Overview metrics (health score, adherence, medicines, fasting sugar).
class D6OverviewCard extends StatelessWidget {
  const D6OverviewCard({super.key});

  // The unit span inherits the number's line-height (1) and computed
  // letter-spacing (-0.02em of 30px = -0.6px) in CSS.
  static Widget _value(String n, [String? unit]) => Text.rich(
        TextSpan(
          text: n,
          style: tx(30, w: w800, h: 1, em: -0.02, tab: true),
          children: [
            if (unit != null) TextSpan(text: unit, style: tx(14, w: w600, c: MP.ink2, h: 1).copyWith(letterSpacing: -0.6)),
          ],
        ),
      );

  static Widget _label(String s) => Text(s, style: tx(14, c: MP.ink2, h: 1.35));

  static Widget _tile(Widget value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [value, const Gap(6), _label(label)]),
      );

  @override
  Widget build(BuildContext context) {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D6Title('Overview', sub: 'Last 30 days · updated 8:52 AM today'),
          MpGrid(
            columns: 2,
            children: [
              _tile(_value('74', '/100'), 'Health score'),
              Semantics(
                label: 'Adherence 86 percent, view details',
                button: true,
                excludeSemantics: true,
                child: Tap(
                  onTap: () => Nav.go(context, 'PP-Treatment'),
                  radius: 12,
                  color: MP.bg,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _value('86%')),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('View', style: tx(14, w: w600, c: MP.primary)),
                              const Gap(2),
                              const Ico(I.chevronRight, size: 14, color: MP.primary, stroke: 2),
                            ],
                          ),
                        ],
                      ),
                      const Gap(6),
                      _label('Adherence'),
                    ],
                  ),
                ),
              ),
              _tile(_value('3'), 'Medicines'),
              _tile(_value('142', ' mg/dL'), 'Latest fasting sugar'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Measurements recorded at the front desk (label · value · band).
class D6MeasurementsCard extends StatelessWidget {
  const D6MeasurementsCard({super.key});

  static const _ok = (MP.greenSoft, MP.green);
  static const _warn = (MP.amberSoft, MP.amber);

  static const List<(String, String, String?, (Color, Color)?)> _rows = [
    ('Height', '158 cm', null, null),
    ('Weight', '68.5 kg', null, null),
    ('BMI', '27.4', 'Overweight', _warn),
    ('Blood pressure', '128/82 mmHg', 'Normal', _ok),
    ('Pulse', '78 bpm', 'Normal', _ok),
    ('SpO2', '98%', 'Normal', _ok),
  ];

  @override
  Widget build(BuildContext context) {
    final ls = tx(15, c: MP.ink2);
    final vs = tx(16, w: w600, tab: true);
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: D6Title('Measurements', sub: 'Recorded today, 8:52 AM · front desk'),
          ),
          for (final m in _rows)
            D6Row(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: LayoutBuilder(
                  builder: (context, c) {
                    // Label and value are flex items that shrink (and wrap)
                    // together when they don't fit, e.g. "Blood pressure".
                    // The value only breaks at spaces, as in Chrome.
                    final value = m.$2.replaceAll('/', '/\u2060');
                    final (wl, wv) = D6Flex.pair(
                      context,
                      avail: c.maxWidth - 12 - 12 - 80,
                      a: [(m.$1, ls)],
                      b: [(value, vs)],
                    );
                    return Row(
                      children: [
                        SizedBox(width: wl, child: Text(m.$1, style: ls)),
                        const Gap(12),
                        SizedBox(width: wv, child: Text(value, style: vs)),
                        const Gap(12),
                        // 80px band slot, right-aligned; like CSS flex-end, a
                        // pill wider than the slot ("Overweight") spills left.
                        SizedBox(
                          width: 80,
                          height: 22,
                          child: m.$3 == null
                              ? null
                              : OverflowBox(
                                  minWidth: 0,
                                  maxWidth: double.infinity,
                                  minHeight: 0,
                                  maxHeight: 22,
                                  alignment: Alignment.centerRight,
                                  child: D6Pill(m.$3!, bg: m.$4!.$1, fg: m.$4!.$2, height: 22, padH: 8, weight: w600),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile tabs (PP-Summary · PP-Prescriptions · PP-Tests · PP-Treatment)
// ─────────────────────────────────────────────────────────────────────────────

/// Page frame shared by the four doctor-view profile tabs: white top bar
/// (back · call · message · more), identity block, tab strip with a 1px
/// bottom border, the tab's [children] (20px gutters, [gap] apart) and the
/// pinned "Start consultation" bar. The identity scrolls away; the tab strip
/// stays under the top bar.
class D6PatientTabsPage extends StatefulWidget {
  /// 0 Summary · 1 Prescriptions · 2 Test results · 3 Treatment plan.
  final int tab;
  final List<Widget> children;
  final double gap;
  const D6PatientTabsPage({super.key, required this.tab, required this.children, this.gap = 16});

  static const tabs = [
    ('Summary', 'PP-Summary'),
    ('Prescriptions', 'PP-Prescriptions'),
    ('Test results', 'PP-Tests'),
    ('Treatment plan', 'PP-Treatment'),
  ];

  @override
  State<D6PatientTabsPage> createState() => _D6PatientTabsPageState();
}

class _D6PatientTabsPageState extends State<D6PatientTabsPage> {
  /// The design shows the tab strip shifted 100px left when the last tab is
  /// selected (margin-left: -100px).
  double get _designOffset => widget.tab == 3 ? 100 : 0;

  late final ScrollController _strip = ScrollController(initialScrollOffset: _designOffset);

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const _TabsTopBar(),
      scroll: false,
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _TabsIdentity()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabStripDelegate(tab: widget.tab, controller: _strip, offset: _designOffset),
          ),
          SliverPadding(
            // The design pads the bottom by 112px to clear the absolute action
            // bar; here the bar is pinned below the scroll view.
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            sliver: SliverToBoxAdapter(child: VGap(gap: widget.gap, children: widget.children)),
          ),
        ],
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: MpButton('Start consultation', onTap: () => D6Patient.startConsult(context)),
      ),
    );
  }
}

class _TabsTopBar extends StatelessWidget {
  const _TabsTopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: MP.white,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Spacer(),
          MpIconButton(I.phone, label: 'Call Priya', color: MP.primary, onTap: () => D6Patient.phone(context)),
          const Gap(4),
          MpIconButton(I.message, label: 'Message Priya', color: MP.primary, onTap: () => D6Patient.message(context)),
          const Gap(4),
          const MpIconButton(I.moreV, label: 'More options', filled: true),
        ],
      ),
    );
  }
}

class _TabsIdentity extends StatelessWidget {
  const _TabsIdentity();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MP.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MpAvatar('PS', size: 56, fontSize: 19),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Priya Sharma', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                    const Gap(2),
                    Text('29 yrs · Female · +91 98765 43210', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              D6Pill('High risk', bg: MP.amberSoft, fg: MP.amber, height: 26),
              D6Pill('Type 2 diabetes', height: 26, weight: w600),
              D6Pill('PCOS', height: 26, weight: w600),
              // 24px content box + 1px border (content-box sizing) = 26px.
              D6Pill(
                'Allergy: Sulfa drugs',
                bg: Colors.transparent,
                fg: MP.amber,
                border: MP.amberLine,
                height: 26,
                weight: w600,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabStripDelegate extends SliverPersistentHeaderDelegate {
  final int tab;
  final ScrollController controller;
  final double offset;
  _TabStripDelegate({required this.tab, required this.controller, required this.offset});

  @override
  double get minExtent => 49;

  @override
  double get maxExtent => 49;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      _TabStrip(tab: tab, controller: controller, offset: offset);

  @override
  bool shouldRebuild(_TabStripDelegate oldDelegate) =>
      oldDelegate.tab != tab || oldDelegate.controller != controller || oldDelegate.offset != offset;
}

class _TabStrip extends StatelessWidget {
  final int tab;
  final ScrollController controller;
  final double offset;
  const _TabStrip({required this.tab, required this.controller, required this.offset});

  TextStyle _style(bool on) => tx(15, w: on ? w700 : w600, c: on ? MP.primary : MP.ink2);

  @override
  Widget build(BuildContext context) {
    const tabs = D6PatientTabsPage.tabs;
    return Container(
      height: 49,
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: LayoutBuilder(
        builder: (context, c) {
          // Natural strip width, so the designed offset can always be reached.
          final scaler = MediaQuery.textScalerOf(context);
          var natural = 40.0 + 24.0 * (tabs.length - 1);
          for (var i = 0; i < tabs.length; i++) {
            final tp = TextPainter(
              text: TextSpan(text: tabs[i].$1, style: _style(i == tab)),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            natural += tp.width;
            tp.dispose();
          }
          final extra = offset > 0 ? math.max(0.0, offset + 1 - (natural - c.maxWidth)) : 0.0;
          return SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(left: 20, right: 20 + extra),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const Gap(24),
                  Semantics(
                    selected: i == tab,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Nav.tab(context, tabs[i].$2),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: i == tab ? MP.primary : Colors.transparent, width: 2),
                          ),
                        ),
                        child: Text(tabs[i].$1, style: _style(i == tab), maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Filter pill used on the profile tabs (40px border-box, 14/600). Selected:
/// #003399 fill, no border; unselected: white with a 1px #D5DBE5 border.
class D6FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double padH;
  const D6FilterChip(this.label, {super.key, required this.selected, required this.onTap, this.padH = 16});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        height: 40,
        child: Tap(
          onTap: onTap,
          radius: 999,
          color: selected ? MP.primary : MP.white,
          border: selected ? null : MP.lineStrong,
          padding: EdgeInsets.symmetric(horizontal: padH),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: tx(14, w: w600, c: selected ? MP.white : MP.ink2), maxLines: 1),
          ),
        ),
      ),
    );
  }
}

/// 13px #69738A note with a leading 16px shield (filter explanations).
class D6ShieldNote extends StatelessWidget {
  final String text;
  const D6ShieldNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Ico(I.shield, size: 16, color: MP.ink3),
          const Gap(8),
          Expanded(child: Text(text, style: tx(13, c: MP.ink3))),
        ],
      ),
    );
  }
}

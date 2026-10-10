import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../data/downloads.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';
import 'patient_picker.dart';

// Shared pieces for batch D6: Patient-Profile, Patient-Profile-Desk and the
// four doctor-view profile tabs (PP-Summary, PP-Prescriptions, PP-Tests,
// PP-Treatment).

/// Actions on the patient shown in these screens (Priya Sharma in the design;
/// live, the patient in the nearest [D6Scope]).
class D6Patient {
  D6Patient._();

  static void phone(BuildContext context) {
    final r = D6Scope.recOf(context);
    if (!isLive || r == null) {
      toast(context, 'Calling Priya · +91 98765 43210');
      return;
    }
    d6Call(context, r.phone, r.name);
  }

  static void message(BuildContext context) {
    final r = D6Scope.recOf(context);
    if (!isLive || r == null) {
      Nav.go(context, 'Patient-Thread');
      return;
    }
    d6MessagePatient(context, r.id);
  }

  static void prescriptions(BuildContext context) => d6Go(context, 'Prescriptions');
  static void startConsult(BuildContext context) => d6Go(context, 'Consult-Page');
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
    final r = D6Scope.recOf(context);
    final risk = r == null ? ('High risk', MP.amberSoft, MP.amber) : r.risk;
    final conditions = r == null ? const ['Type 2 diabetes', 'PCOS'] : r.conditions;
    final allergies = r == null ? const ['Sulfa drugs'] : r.allergies;
    final complaint = r == null ? 'chest tightness, fatigue' : r.chiefComplaint;
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: VGap(
        gap: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MpAvatar(r?.initials ?? 'PS', size: 72, fontSize: 24),
                  if (risk != null) D6Pill(risk.$1, bg: risk.$2, fg: risk.$3),
                ],
              ),
              const Gap(12),
              Text(r?.name ?? 'Priya Sharma', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              const Gap(4),
              Text(r?.metaLine ?? '29 yrs · Female · +91 98765 43210', style: tx(14, c: MP.ink2, h: 1.45, tab: true)),
            ],
          ),
          if (conditions.isNotEmpty || allergies.isNotEmpty) Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in conditions) D6Pill(c, weight: w600),
              if (allergies.isNotEmpty)
                D6Pill('Allergy: ${allergies.join(', ')}', bg: MP.white, fg: MP.amber, border: MP.amber, weight: w600, icon: I.alert),
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
          if (complaint != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(
                style: tx(14, c: MP.ink2, h: 1.45),
                children: [
                  TextSpan(text: 'Chief complaint:', style: tx(14, w: w600, h: 1.45)),
                  TextSpan(text: ' $complaint'),
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

  /// Whether there is a consent note to show (live: the record's share scope).
  static bool shown(BuildContext context) {
    final r = D6Scope.recOf(context);
    return r == null || r.consent != null;
  }

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
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
              r == null ? 'Priya shares her full record with City Care Clinic. She controls this.' : r.consent ?? '',
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
    final r = D6Scope.recOf(context);
    var sub = 'Last 30 days · updated 8:52 AM today';
    var score = '74';
    var adherence = '86';
    var meds = '3';
    String? sugar = '142';
    if (r != null) {
      final hs = r.p.obj('healthScore');
      final at = F.date(hs['computedAt']);
      sub = at == null ? 'Last 30 days' : 'Last 30 days · updated ${F.sameDay(at, DateTime.now()) ? '${F.time(at)} today' : F.dayMonth(at)}';
      score = hs['value'] is num ? d6Num(hs['value']) : '–';
      final pct = r.adherence['overallPct'];
      adherence = pct is num ? '${pct.round()}' : '–';
      meds = '${r.medicines.length}';
      final lv = r.detail.obj('latestVitals');
      final s = r.fastingSugar ?? (lv['sugarType'] == 'fasting' ? lv : const <String, dynamic>{});
      sugar = s['bloodSugar'] is num ? d6Num(s['bloodSugar']) : null;
    }
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          D6Title('Overview', sub: sub),
          MpGrid(
            columns: 2,
            children: [
              _tile(_value(score, '/100'), 'Health score'),
              Semantics(
                label: 'Adherence $adherence percent, view details',
                button: true,
                excludeSemantics: true,
                child: Tap(
                  onTap: () => d6Go(context, 'PP-Treatment'),
                  radius: 12,
                  color: MP.bg,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _value(adherence == '–' ? adherence : '$adherence%')),
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
              _tile(_value(meds), 'Medicines'),
              _tile(sugar == null ? _value('–') : _value(sugar, ' mg/dL'), 'Latest fasting sugar'),
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

  /// Live rows from the newest clinic reading (height / weight / BMI fall
  /// back to the patient's record).
  static List<(String, String, String?, (Color, Color)?)> _live(D6Rec r) {
    final v = r.clinicVitals ?? const <String, dynamic>{};
    (String?, (Color, Color)?) band(D6Band? b) => b == null ? (null, null) : (b.$1, (b.$2, b.$3));
    final h = v['heightCm'] ?? r.p['heightCm'];
    final w = v['weightKg'] ?? r.p['weightKg'];
    final bmi = v['bmi'] ?? r.p['bmi'];
    final s = v['bpSystolic'] as num?;
    final d = v['bpDiastolic'] as num?;
    final bmiB = band(d6BmiBand(bmi is num ? bmi : null));
    final bpB = band(d6BpBand(s, d));
    final pB = band(d6PulseBand(v['pulse'] as num?));
    final oB = band(d6Spo2Band(v['spo2'] as num?));
    return [
      if (h != null) ('Height', '${d6Num(h)} cm', null, null),
      if (w != null) ('Weight', '${d6Num(w)} kg', null, null),
      if (bmi != null) ('BMI', d6Num(bmi), bmiB.$1, bmiB.$2),
      if (s != null && d != null) ('Blood pressure', '${d6Num(s)}/${d6Num(d)} mmHg', bpB.$1, bpB.$2),
      if (v['pulse'] != null) ('Pulse', '${d6Num(v['pulse'])} bpm', pB.$1, pB.$2),
      if (v['spo2'] != null) ('SpO2', '${d6Num(v['spo2'])}%', oB.$1, oB.$2),
    ];
  }

  /// Whether there is anything to show (live: any reading or height/weight).
  static bool shown(BuildContext context) {
    final r = D6Scope.recOf(context);
    return r == null || _live(r).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final ls = tx(15, c: MP.ink2);
    final vs = tx(16, w: w600, tab: true);
    final r = D6Scope.recOf(context);
    final rows = r == null ? _rows : _live(r);
    var sub = 'Recorded today, 8:52 AM · front desk';
    if (r != null) {
      final v = r.clinicVitals;
      final at = F.date(v?['recordedAt']);
      sub = v == null || at == null ? 'From the patient record' : 'Recorded ${d6When(at)} · ${d6RecordedBy(v)}';
    }
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: D6Title('Measurements', sub: sub),
          ),
          for (final m in rows)
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

  /// Live: the patient (null while loading → [placeholder] instead of the
  /// identity and [children]). Ignored in the design preview.
  final D6Rec? rec;
  final Widget? placeholder;
  final Future<void> Function()? onChanged;
  const D6PatientTabsPage({
    super.key,
    required this.tab,
    required this.children,
    this.gap = 16,
    this.rec,
    this.placeholder,
    this.onChanged,
  });

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
    final live = isLive;
    final rec = live ? widget.rec : null;
    final loading = live && rec == null;
    return D6Scope(
      rec: rec,
      onChanged: widget.onChanged,
      child: MpPage(
        header: const _TabsTopBar(),
        scroll: false,
        body: CustomScrollView(
          slivers: [
            if (!loading) const SliverToBoxAdapter(child: _TabsIdentity()),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabStripDelegate(tab: widget.tab, controller: _strip, offset: _designOffset),
            ),
            if (loading || (live && widget.placeholder != null))
              SliverToBoxAdapter(child: widget.placeholder ?? const SizedBox.shrink())
            else
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
          child: Builder(builder: (c) => MpButton('Start consultation', onTap: () => D6Patient.startConsult(c))),
        ),
      ),
    );
  }
}

class _TabsTopBar extends StatelessWidget {
  const _TabsTopBar();

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final who = r == null ? 'Priya' : r.first;
    return Container(
      height: 64,
      color: MP.white,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Spacer(),
          MpIconButton(I.phone, label: 'Call $who', color: MP.primary, onTap: () => D6Patient.phone(context)),
          const Gap(4),
          MpIconButton(I.message, label: 'Message $who', color: MP.primary, onTap: () => D6Patient.message(context)),
          const Gap(4),
          MpIconButton(I.moreV, label: 'More options', filled: true, onTap: r == null ? null : () => d6MoreOptions(context)),
        ],
      ),
    );
  }
}

class _TabsIdentity extends StatelessWidget {
  const _TabsIdentity();

  @override
  Widget build(BuildContext context) {
    final r = D6Scope.recOf(context);
    final risk = r == null ? ('High risk', MP.amberSoft, MP.amber) : r.risk;
    final conditions = r == null ? const ['Type 2 diabetes', 'PCOS'] : r.conditions;
    final allergies = r == null ? const ['Sulfa drugs'] : r.allergies;
    return Container(
      color: MP.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MpAvatar(r?.initials ?? 'PS', size: 56, fontSize: 19),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r?.name ?? 'Priya Sharma', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                    const Gap(2),
                    Text(r?.metaLine ?? '29 yrs · Female · +91 98765 43210', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
            ],
          ),
          if (risk != null || conditions.isNotEmpty || allergies.isNotEmpty) ...[
            const Gap(14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (risk != null) D6Pill(risk.$1, bg: risk.$2, fg: risk.$3, height: 26),
                for (final c in conditions) D6Pill(c, height: 26, weight: w600),
                // 24px content box + 1px border (content-box sizing) = 26px.
                if (allergies.isNotEmpty)
                  D6Pill(
                    'Allergy: ${allergies.join(', ')}',
                    bg: Colors.transparent,
                    fg: MP.amber,
                    border: MP.amberLine,
                    height: 26,
                    weight: w600,
                  ),
              ],
            ),
          ],
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
                      onTap: () => d6Tab(context, tabs[i].$2),
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

// ─────────────────────────────────────────────────────────────────────────────
// Live data (GET /api/patients/:id and friends)
// ─────────────────────────────────────────────────────────────────────────────

/// The patient last opened on these screens, for a screen opened without one.

/// Route arguments as a map. A bare id string comes back as `{'id': …}`.
/// Waits a microtask first: route arguments are an inherited lookup, which
/// isn't allowed while [State.initState] (where [LiveData] first fetches) runs.
Future<Map<String, dynamic>> d6Args(BuildContext context) async {
  await Future<void>.microtask(() {});
  if (!context.mounted) return const {};
  final a = ModalRoute.of(context)?.settings.arguments;
  if (a is Map) return a.cast<String, dynamic>();
  if (a is String && a.isNotEmpty) return {'id': a};
  return const {};
}

/// The patient a profile screen is about: the `patientId` it was opened
/// with; otherwise the doctor chooses one (never a guess — a wrong patient's
/// record must not appear).
Future<String> d6PatientId(BuildContext context) async {
  final a = await d6Args(context);
  final id = (a['patientId'] ?? a['id'])?.toString();
  if (!context.mounted) throw const ApiException(400, 'NO_PATIENT', 'Choose a patient');
  return patientOrPick(context, id);
}

/// Loads GET /api/patients/:id plus [extra] resources (key → path under
/// /api/patients/:id, e.g. `{'vitals': '/vitals'}`, or a full `/api/…` path
/// where `{id}` is the patient id) into one bundle.
Future<Map<String, dynamic>> d6Load(BuildContext context, [Map<String, String> extra = const {}]) async {
  final id = await d6PatientId(context);
  final keys = extra.keys.toList();
  Future<dynamic> get(String path) {
    final full = path.startsWith('/api/') ? path.replaceAll('{id}', id) : '/api/patients/$id$path';
    final q = full.indexOf('?');
    if (q < 0) return Api.I.get(full);
    return Api.I.get(full.substring(0, q), query: Uri.splitQueryString(full.substring(q + 1)));
  }

  final res = await Future.wait([
    Api.I.get('/api/patients/$id'),
    for (final k in keys) get(extra[k]!),
  ]);
  return {'id': id, 'detail': res[0], for (var i = 0; i < keys.length; i++) keys[i]: res[i + 1]};
}

/// "02 Feb 2026" (the profile tabs pad the day).
String d6Date(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${F.dayMonth(d).split(' ').last} ${d.year}';

/// "Jun 2025"
String d6MonthYear(DateTime d) => '${F.dayMonth(d).split(' ').last} ${d.year}';

/// "today, 8:52 AM" · "yesterday, 9:10 AM" · "29 Sep, 9:26 AM"
String d6When(DateTime d) {
  final n = DateTime.now();
  final day = F.sameDay(d, n)
      ? 'today'
      : F.sameDay(d, n.subtract(const Duration(days: 1)))
          ? 'yesterday'
          : F.dayMonth(d);
  return '$day, ${F.time(d)}';
}

/// "9876543210" → "+91 98765 43210"
String d6Phone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length == 10) return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
  return phone.isEmpty ? '' : (phone.startsWith('+') ? phone : '+91 $phone');
}

/// 7.2 → "7.2", 162.0 → "162"
String d6Num(Object? v) {
  if (v is! num) return v == null ? '' : '$v';
  return v == v.roundToDouble() ? '${v.round()}' : '$v';
}

String d6Cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Opens a signed file link (prescription PDF, report, export).
Future<void> d6OpenUrl(BuildContext context, String? url, {String fail = "Couldn't open the file"}) async {
  if (url == null || url.isEmpty) {
    toast(context, 'There is no file for this yet');
    return;
  }
  if (Downloads.isFile(url)) {
    await Downloads.open(context, url);
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) toast(context, fail);
}

typedef D6Band = (String, Color, Color);
const D6Band _bandOk = ('Normal', MP.greenSoft, MP.green);
D6Band _warn(String s) => (s, MP.amberSoft, MP.amber);

D6Band? d6BpBand(num? s, num? d) {
  if (s == null || d == null) return null;
  if (s >= 140 || d >= 90) return _warn('High');
  if (s >= 130 || d >= 85) return _warn('Elevated');
  if (s < 90 || d < 60) return _warn('Low');
  return _bandOk;
}

D6Band? d6PulseBand(num? v) => v == null ? null : v > 100 ? _warn('High') : v < 60 ? _warn('Low') : _bandOk;
D6Band? d6Spo2Band(num? v) => v == null ? null : v < 95 ? _warn('Low') : _bandOk;
D6Band? d6TempBand(num? v) => v == null ? null : v >= 99.5 ? _warn('Fever') : v < 97 ? _warn('Low') : _bandOk;
D6Band? d6BmiBand(num? v) => v == null
    ? null
    : v < 18.5
        ? _warn('Underweight')
        : v < 25
            ? _bandOk
            : v < 30
                ? _warn('Overweight')
                : _warn('Obese');

/// Who recorded a vitals reading: "front desk", "doctor", "home reading".
String d6RecordedBy(Map<String, dynamic> v) {
  if (v['source'] == 'home' || v['recordedByRole'] == 'patient') return 'home reading';
  final r = v.str('recordedByRole');
  return r.isEmpty ? 'clinic' : r.replaceAll('_', ' ');
}

/// Read access to one patient's live record bundle (see [d6Load]).
class D6Rec {
  final Map<String, dynamic> m;
  const D6Rec(this.m);

  Map<String, dynamic> get detail => m.obj('detail');
  Map<String, dynamic> get p => detail.obj('patient');
  String get id => m.str('id', p.str('id'));
  String get name => p.str('name');
  String get first => F.firstName(name);
  String get initials => F.initials(name);
  String get phone => p.str('phone');
  String get phoneText => d6Phone(phone);
  String get gender => switch (p['gender']) { 'female' => 'Female', 'male' => 'Male', 'other' => 'Other', _ => '' };
  String get her => switch (p['gender']) { 'female' => 'her', 'male' => 'his', _ => 'their' };
  String get she => switch (p['gender']) { 'female' => 'She', 'male' => 'He', _ => 'They' };

  /// "29 yrs · Female · +91 98765 43210"
  String get metaLine => [if (p['age'] is num) '${p['age']} yrs', gender, phoneText].where((s) => s.isNotEmpty).join(' · ');

  /// Risk pill, when the record has a risk level.
  D6Band? get risk => switch (p['riskLevel']) {
        'high' => ('High risk', MP.amberSoft, MP.amber),
        'moderate' => ('Moderate risk', MP.amberSoft, MP.amber),
        'low' => ('Low risk', MP.greenSoft, MP.green),
        _ => null,
      };

  List<String> get conditions => [for (final c in detail.list('conditions')) c.str('name')].where((s) => s.isNotEmpty).toList();
  List<String> get allergies => [for (final a in detail.list('allergies')) a.str('allergen')].where((s) => s.isNotEmpty).toList();

  Map<String, dynamic> get nextVisit => detail.obj('nextVisit');

  /// Today's visit reason, when there is a visit today with one.
  String? get chiefComplaint {
    final at = F.date(nextVisit['startAt']);
    final reason = nextVisit.str('reason');
    if (at == null || reason.isEmpty || !F.sameDay(at, DateTime.now())) return null;
    return reason[0].toLowerCase() + reason.substring(1);
  }

  static String get practiceName => '${Session.I.activeMembership?['practiceName'] ?? ''}';

  /// "Priya shares her full record with City Care Clinic. She controls this."
  String? get consent {
    final scope = detail['shareScope'];
    final practice = practiceName.isEmpty ? 'this clinic' : practiceName;
    if (scope == null) return null;
    final what = scope == 'full' ? '$her full record' : 'part of $her record';
    return '$first shares $what with $practice.${p['hasApp'] == true ? ' $she controls this.' : ''}';
  }

  List<Map<String, dynamic>> get careTeam => detail.list('careTeam');
  Map<String, dynamic> get adherence => detail.obj('adherence');
  List<Map<String, dynamic>> get medicines => detail.list('currentMedicines');

  /// Name of a care-team member (or the signed-in doctor) by user id.
  String? personName(Object? userId) {
    if (userId == null) return null;
    if ('$userId' == '${Session.I.user['id']}') return Session.I.name;
    for (final c in careTeam) {
      if ('${c['userId']}' == '$userId') return c.str('name');
    }
    return null;
  }

  List<Map<String, dynamic>> get vitals {
    final v = m['vitals'];
    return [for (final x in (v is List ? v : const [])) (x as Map).cast<String, dynamic>()];
  }

  /// Newest reading that has [field].
  Map<String, dynamic>? latestWith(String field, {bool Function(Map<String, dynamic>)? where}) {
    for (final v in vitals) {
      if (v[field] != null && (where == null || where(v))) return v;
    }
    return null;
  }

  /// The newest clinic reading (front desk / doctor), else the newest one.
  Map<String, dynamic>? get clinicVitals {
    for (final v in vitals) {
      if (v['source'] == 'clinic') return v;
    }
    return vitals.isEmpty ? null : vitals.first;
  }

  Map<String, dynamic>? get fastingSugar => latestWith('bloodSugar', where: (v) => v['sugarType'] == 'fasting');
}

/// The live patient record for the D6 widgets below it. Without one (the
/// design preview) they draw the design's sample patient.
class D6Scope extends InheritedWidget {
  final D6Rec? rec;

  /// Reloads the screen quietly after an action.
  final Future<void> Function()? onChanged;
  const D6Scope({super.key, required this.rec, this.onChanged, required super.child});

  static D6Scope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<D6Scope>();
  static D6Rec? recOf(BuildContext context) => maybeOf(context)?.rec;

  @override
  bool updateShouldNotify(D6Scope oldWidget) => oldWidget.rec != rec;
}

/// Switches profile tab, keeping the patient (Nav.tab drops route arguments).
void d6Tab(BuildContext context, String stem) {
  final rec = D6Scope.recOf(context);
  final s = Nav.spec(stem);
  if (!isLive || rec == null || s == null) {
    Nav.tab(context, stem);
    return;
  }
  if (ModalRoute.of(context)?.settings.name == stem) return;
  Navigator.of(context).pushReplacement(PageRouteBuilder(
    settings: RouteSettings(name: stem, arguments: {'patientId': rec.id}),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (c, _, __) => s.builder(c),
  ));
}

/// Opens [stem] about this patient (`{'patientId': …}` plus [more]).
void d6Go(BuildContext context, String stem, [Map<String, Object?> more = const {}]) {
  final rec = D6Scope.recOf(context);
  if (!isLive || rec == null) {
    Nav.go(context, stem);
    return;
  }
  Nav.go(context, stem, args: {'patientId': rec.id, ...more});
}

/// Opens (or creates) the patient's care thread and shows it.
Future<void> d6MessagePatient(BuildContext context, String patientId) async {
  final res = await runAction(context, () => Api.I.post('/api/inbox', {'patientId': patientId}));
  if (res is! Map || !context.mounted) return;
  Nav.go(context, 'Patient-Thread', args: {'conversationId': '${res['id'] ?? res['_id']}', 'patientId': patientId});
}

/// Starts a phone call to the patient.
Future<void> d6Call(BuildContext context, String phone, String name) async {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) {
    toast(context, 'No mobile number on record');
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri(scheme: 'tel', path: digits.startsWith('+') ? digits : '+91$digits'));
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) toast(context, 'Calling $name · ${d6Phone(phone)}');
}

/// "More options" on the profile: add an allergy or a condition.
Future<void> d6MoreOptions(BuildContext context) async {
  final scope = D6Scope.maybeOf(context);
  final rec = scope?.rec;
  if (rec == null) return;
  final choice = await d2PickOption(context, title: 'More options', options: const ['Add allergy', 'Add condition'], value: '');
  if (choice == null || !context.mounted) return;
  final allergy = choice == 'Add allergy';
  final text = await d6AskText(
    context,
    title: allergy ? 'Add allergy' : 'Add condition',
    label: allergy ? 'Allergies' : 'Condition',
    hint: allergy ? 'e.g. Penicillin, peanuts' : 'e.g. Hypertension',
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final res = await runAction(
    context,
    () => Api.I.post('/api/patients/${rec.id}/${allergy ? 'allergies' : 'conditions'}', allergy ? {'allergens': text.trim()} : {'name': text.trim()}),
  );
  if (res == null || !context.mounted) return;
  toast(context, allergy ? 'Allergy added' : 'Condition added');
  await scope?.onChanged?.call();
}

// ── Charts drawn from live readings, in the design's SVG style ──

String _svgNum(num v) => v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');

/// "Jun ’25"
String d6MonthTick(DateTime d) => "${F.dayMonth(d).split(' ').last} ’${(d.year % 100).toString().padLeft(2, '0')}";

/// HbA1c history (310×150): value labels, month ticks and the target band.
/// [points] oldest first: (date, value).
String d6HistorySvg(List<(DateTime, num)> points, {num? target}) {
  final vals = [for (final p in points) p.$2, if (target != null) target];
  var lo = vals.reduce(math.min).floor().toDouble();
  var hi = vals.reduce(math.max).ceil().toDouble();
  if (hi - lo < 3) {
    lo = math.min(lo, hi - 3);
  }
  if (hi == lo) hi = lo + 3;
  final span = hi - lo;
  double y(num v) => 12 + (hi - v) * 108 / span;
  final n = points.length;
  double x(int i) => n == 1 ? 286 : 44 + (286 - 44) * i / (n - 1);
  final b = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" width="310" height="150" viewBox="0 0 310 150" font-family="Figtree">');
  if (target != null) {
    final ty = y(target);
    b.write('<rect x="24" y="${_svgNum(ty)}" width="286" height="${_svgNum(120 - ty)}" fill="#E7F5EE"/>');
  }
  b.write('<path d="M24 12H310M24 48H310M24 84H310M24 120H310" stroke="#E5E9F0" stroke-width="1"/>');
  for (var k = 0; k < 4; k++) {
    final v = hi - span * k / 3;
    b.write('<text x="0" y="${16 + 36 * k}" font-size="12" fill="#69738A">${_svgNum(v)}</text>');
  }
  if (target != null) {
    final ty = y(target);
    b.write('<path d="M24 ${_svgNum(ty)}H310" stroke="#076B3C" stroke-width="1.5" stroke-dasharray="4 4"/>');
    b.write('<text x="30" y="${_svgNum(math.min(ty + 28, 116))}" font-size="12" font-weight="600" fill="#076B3C">Target ${target.toStringAsFixed(1)}</text>');
  }
  b.write('<polyline points="${[for (var i = 0; i < n; i++) '${_svgNum(x(i))},${_svgNum(y(points[i].$2))}'].join(' ')}" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>');
  for (var i = 0; i < n; i++) {
    final last = i == n - 1;
    final cx = _svgNum(x(i)), cy = _svgNum(y(points[i].$2));
    b.write(last
        ? '<circle cx="$cx" cy="$cy" r="4.5" fill="#003399"/>'
        : '<circle cx="$cx" cy="$cy" r="4" fill="#FFFFFF" stroke="#003399" stroke-width="2"/>');
    b.write('<text x="$cx" y="${_svgNum(y(points[i].$2) - 10.5)}" font-size="12" font-weight="${last ? 700 : 600}" fill="#111827" text-anchor="middle">${d6Num(points[i].$2)}</text>');
    b.write('<text x="$cx" y="142" font-size="12" fill="#69738A" text-anchor="middle">${d6MonthTick(points[i].$1)}</text>');
  }
  b.write('</svg>');
  return b.toString();
}

/// Daily readings (310×140) on the design's fixed 70–200 mg/dL scale, with
/// the target line and weekday ticks. [points] oldest first.
String d6DailySvg(List<(DateTime, num)> points, {num target = 130}) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  double y(num v) => (10 + (200 - v) * 0.8).clamp(4, 124).toDouble();
  final n = points.length;
  double x(int i) => n == 1 ? 302 : 40 + (302 - 40) * i / (n - 1);
  final b = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" width="310" height="140" viewBox="0 0 310 140" font-family="Figtree">')
    ..write('<g stroke="#E5E9F0" stroke-width="1"><line x1="34" y1="10" x2="306" y2="10"/><line x1="34" y1="50" x2="306" y2="50"/><line x1="34" y1="90" x2="306" y2="90"/><line x1="34" y1="118" x2="306" y2="118"/></g>')
    ..write('<g font-size="11" fill="#69738A" text-anchor="end"><text x="26" y="14">200</text><text x="26" y="54">150</text><text x="26" y="94">100</text><text x="26" y="122">70</text></g>')
    ..write('<line x1="34" y1="${_svgNum(y(target))}" x2="306" y2="${_svgNum(y(target))}" stroke="#076B3C" stroke-width="1" stroke-dasharray="4 3"/>')
    ..write('<text x="306" y="${_svgNum(y(target) + 14)}" font-size="11" fill="#076B3C" text-anchor="end">Target ${d6Num(target)}</text>')
    ..write('<polyline points="${[for (var i = 0; i < n; i++) '${_svgNum(x(i))},${_svgNum(y(points[i].$2))}'].join(' ')}" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>')
    ..write('<g fill="#FFFFFF" stroke="#003399" stroke-width="2">');
  for (var i = 0; i < n; i++) {
    final last = i == n - 1;
    b.write('<circle cx="${_svgNum(x(i))}" cy="${_svgNum(y(points[i].$2))}" r="${last ? 3.5 : 3}"${last ? ' fill="#003399"' : ''}/>');
  }
  b.write('</g><g font-size="11" fill="#69738A" text-anchor="middle">');
  for (var i = 0; i < n; i++) {
    b.write('<text x="${_svgNum(i == n - 1 && n > 1 ? x(i) - 4 : x(i))}" y="136">${days[points[i].$1.weekday - 1]}</text>');
  }
  b.write('</g></svg>');
  return b.toString();
}

/// 72×32 sparkline; the last dot is amber when [flagged], else green.
String d6Sparkline(List<num> values, {required bool flagged}) {
  final lo = values.reduce(math.min), hi = values.reduce(math.max);
  final span = hi - lo;
  final n = values.length;
  double x(int i) => n == 1 ? 68 : 4 + 64 * i / (n - 1);
  double y(num v) => span == 0 ? 16 : 26 - (v - lo) * 20 / span;
  final pts = n == 1 ? '4,16 68,16' : [for (var i = 0; i < n; i++) '${_svgNum(x(i))},${_svgNum(y(values[i]))}'].join(' ');
  return '<svg xmlns="http://www.w3.org/2000/svg" width="72" height="32" viewBox="0 0 72 32">'
      '<polyline points="$pts" fill="none" stroke="#003399" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>'
      '<circle cx="68" cy="${_svgNum(y(values.last))}" r="3" fill="${flagged ? '#B45309' : '#076B3C'}"/></svg>';
}

/// A one-field sheet (MpInput + Save). Returns the text, or null.
Future<String?> d6AskText(BuildContext context, {required String title, required String label, String? hint, String value = '', int maxLines = 1}) async {
  final c = TextEditingController(text: value);
  try {
    return await openSheet<String>(
      context,
      (sc) => MpSheet(
        title: title,
        child: VGap(
          gap: 16,
          children: [
            MpInput(label: label, hint: hint, controller: c, autofocus: true, maxLines: maxLines, height: maxLines > 1 ? 104 : 56),
            MpButton('Save', onTap: () => Navigator.pop(sc, c.text)),
          ],
        ),
      ),
    );
  } finally {
    // The sheet's closing animation still uses the controller for a moment.
    Future<void>.delayed(const Duration(seconds: 1), c.dispose);
  }
}

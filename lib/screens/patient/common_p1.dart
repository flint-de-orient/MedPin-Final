import 'package:flutter/material.dart' hide Text;

import 'package:url_launcher/url_launcher.dart';

import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'p1_sheets.dart';
import '../../widgets/i18n.dart';

/// Shared pieces for batch P1 (patient home, its sheets and the carousel).
class P1 {
  P1._();

  /// Chrome's default placeholder colour, which the design's empty fields show.
  static const placeholder = Color(0xFF757575);

  /// The four home-carousel slides (Hero-Carousel.dc.html), most urgent first.
  static const slides = [
    P1Slide(
      spec: '1 · Opens appointment details',
      tag: 'Today · 5:00 PM',
      title: 'Visit with Dr. Sen',
      sub: 'City Care Clinic, Salt Lake · Token 04',
      cta: 'View details',
      stem: 'Patient-DoctorDetail',
    ),
    P1Slide(
      spec: '2 · Opens the report in Health records',
      tag: 'New report',
      title: 'Your HbA1c is in',
      sub: '7.4%, a little above your target',
      cta: 'See what it means',
      icon: I.fileText,
      image: 'assets/images/hero_report.jpg',
      stem: 'Patient-Records',
    ),
    P1Slide(
      spec: '3 · Opens Medicines, refill',
      tag: 'Refill soon',
      title: 'Metformin runs out in 3 days',
      sub: '6 tablets left',
      cta: 'Order a refill',
      icon: I.pill,
      image: 'assets/images/hero_refill.jpg',
      stem: 'Patient-Medicines',
    ),
    P1Slide(
      spec: '4 · Opens health score details',
      tag: 'This week',
      title: 'Health score up by 3',
      sub: 'You walked 4 of 5 planned days',
      cta: 'See your progress',
      icon: I.activity,
      image: 'assets/images/hero_health.jpg',
    ),
  ];

  /// Opens a slide's destination (the health score opens its details sheet).
  static void openSlide(BuildContext context, P1Slide slide) {
    if (slide.stem == null || slide.stem == 'Patient-Home') {
      openSheet<void>(context, (_) => const P1HealthScoreSheet());
    } else {
      Nav.go(context, slide.stem!, args: slide.args);
    }
  }

  /// The carousel slides from GET /api/patient/home, most urgent first:
  /// next visit, a new report, a refill running out, the health score.
  static List<P1Slide> slidesFrom(Map<String, dynamic> d) {
    final out = <P1Slide>[];
    final v = d.obj('nextVisit');
    final at = F.date(v['startAt']);
    if (at != null) {
      final token = v['tokenNo'] == null ? '' : ' · Token ${'${v['tokenNo']}'.padLeft(2, '0')}';
      out.add(P1Slide(
        spec: '',
        tag: F.sameDay(at, DateTime.now()) ? 'Today · ${F.time(at)}' : F.when(at),
        title: 'Visit with ${F.doctorShort(v.obj('doctorId').str('name'))}',
        sub: '${v.obj('locationId').str('name')}$token',
        cta: 'View details',
        stem: 'Patient-DoctorDetail',
        args: {'doctorId': v.obj('doctorId')['id'], 'appointmentId': v['id']},
      ));
    }
    final report = d.list('slides').where((x) => x['kind'] == 'report').firstOrNull;
    if (report != null) {
      final n = report.numOr('abnormalCount').toInt();
      final names = [for (final a in (report['abnormal'] as List? ?? const [])) '$a'];
      out.add(P1Slide(
        spec: '',
        tag: 'New report',
        title: report['testName'] == null ? report.str('title') : 'Your ${report.str('testName')} is in',
        sub: n == 0
            ? 'All values in the normal range'
            : names.isEmpty
                ? '$n ${n == 1 ? 'value' : 'values'} outside the range'
                : '${names.take(2).join(', ')} ${names.length == 1 ? 'is' : 'are'} ${report.str('abnormalDirection', 'high')}',
        cta: 'See what it means',
        icon: I.fileText,
        image: 'assets/images/hero_report.jpg',
        stem: 'Patient-Records',
        args: report['recordId'] == null ? null : {'recordId': report['recordId']},
      ));
    }
    final refills = d.list('refills');
    if (refills.isNotEmpty) {
      final r = refills.first;
      final days = r.numOr('daysLeft').toInt();
      out.add(P1Slide(
        spec: '',
        tag: 'Refill soon',
        title: '${r.str('name')} runs out ${days <= 0 ? 'today' : days == 1 ? 'tomorrow' : 'in $days days'}',
        sub: Session.I.pharmacyOrdering ? '${r.numOr('tabletsLeft').toInt()} tablets left' : '${r.numOr('tabletsLeft').toInt()} tablets left · buy a refill from your chemist',
        // No partner pharmacy: the medicines (stock, the list to show the chemist), not a cart.
        cta: Session.I.pharmacyOrdering ? 'Order a refill' : 'See medicines',
        icon: I.pill,
        image: 'assets/images/hero_refill.jpg',
        stem: 'Patient-Medicines',
        args: Session.I.pharmacyOrdering ? {'courseId': r['courseId']} : null,
      ));
    }
    final score = d.obj('healthScore');
    if (score['value'] != null) {
      final delta = score.numOr('weeklyDelta').toInt();
      final plan = d.obj('activityPlan');
      out.add(P1Slide(
        spec: '',
        tag: 'This week',
        title: delta > 0 ? 'Health score up by $delta' : delta < 0 ? 'Health score down by ${-delta}' : 'Health score ${score['value']}',
        sub: plan.isEmpty ? 'Out of 100' : 'You did ${plan['doneThisWeek']} of ${plan['daysPerWeek']} planned days',
        cta: 'See your progress',
        icon: I.activity,
        image: 'assets/images/hero_health.jpg',
      ));
    }
    return out;
  }

  /// Phones [number] (108, the clinic).
  static Future<void> dial(BuildContext context, String number) async {
    final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final ok = await launchUrl(Uri(scheme: 'tel', path: digits));
    if (!ok && context.mounted) toast(context, 'Call $number');
  }

  /// "Diabetes & thyroid · City Care Clinic" (either part may be missing).
  static String dept(Map<String, dynamic> d) =>
      [d.str('specialty'), d.str('clinic')].where((s) => s.isNotEmpty).join(' · ');

  /// A doctor's presence line and dot: "Available now" / "In clinic · usually
  /// replies in 15 min" / "Away · his clinic team will see it".
  static ({String status, Color color, Color dot}) presence(Map<String, dynamic> d) {
    final note = d['presenceNote'] is String ? d['presenceNote'] as String : '';
    switch (d['presence']) {
      case 'available':
        return (status: note.isEmpty ? 'Available now' : 'Available now · $note', color: MP.green, dot: MP.green);
      case 'in_clinic':
        final mins = d['avgReplyMinutes'] as num?;
        return (
          status: note.isNotEmpty ? 'In clinic · $note' : (mins == null ? 'In clinic' : 'In clinic · usually replies in ${mins.round()} min'),
          color: MP.ink2,
          dot: MP.amber,
        );
      default:
        final pron = d['gender'] == 'female' ? 'her' : d['gender'] == 'male' ? 'his' : 'their';
        return (status: note.isNotEmpty ? 'Away · $note' : 'Away · $pron clinic team will see it', color: MP.ink2, dot: MP.lineStrong);
    }
  }

  /// 'HH:MM' → '8:30 PM'.
  static String clock(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return F.time(DateTime(2000, 1, 1, h, m));
  }

  /// Closes the open sheet, then opens [stem] from the screen underneath.
  static void closeThen(BuildContext context, String stem, {Object? args}) {
    final nav = Navigator.of(context);
    nav.pop();
    Nav.go(nav.context, stem, args: args);
  }

  /// Closes the open sheet and confirms [message] on the screen underneath.
  static void closeWithToast(BuildContext context, String message, [Object? result]) {
    final nav = Navigator.of(context);
    nav.pop(result);
    toast(nav.context, message);
  }

  /// A tappable link inside running text (sits on the line's baseline).
  static InlineSpan link(String text, {required TextStyle style, required VoidCallback onTap}) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(text, style: style),
      ),
    );
  }
}

/// One home-carousel slide. [icon] is null for the photo slide.
class P1Slide {
  final String spec;
  final String tag;
  final String title;
  final String sub;
  final String cta;
  final String? icon;
  final String? stem;

  /// Route arguments for [stem] (the appointment, record or medicine).
  final Object? args;

  /// A full-card background photo (its left side fades into blue already).
  final String? image;
  const P1Slide({
    required this.spec,
    required this.tag,
    required this.title,
    required this.sub,
    required this.cta,
    this.icon,
    this.stem,
    this.args,
    this.image,
  });
}

/// A 212px home-carousel slide: radius 20, #003399, white tag pill, 26px
/// title, white "CTA →" pill. The photo slide (no icon) has the patient image
/// on the right under a blue gradient; the others have a 48px icon tile.
class P1HeroSlide extends StatelessWidget {
  final P1Slide slide;

  /// Photo slide: image width, gradient stops and text column max width.
  final double imageWidth;
  final List<double> stops;
  final double textMaxWidth;

  /// Card colour of an icon slide (the home peek uses #002470).
  final Color background;

  /// Opacity of everything but the tag pill. The home carousel's peeking
  /// slide shows only its tag (0), the current slide everything (1).
  final double contentOpacity;
  final VoidCallback? onTap;

  const P1HeroSlide({
    super.key,
    required this.slide,
    this.imageWidth = 212,
    this.stops = const [0.40, 0.62, 0.85],
    this.textMaxWidth = 210,
    this.background = MP.primary,
    this.contentOpacity = 1,
    this.onTap,
  });

  Widget _fade(Widget child) => contentOpacity >= 1 ? child : Opacity(opacity: contentOpacity, child: child);

  static const _tagBg = Color(0x29FFFFFF); // rgba(255,255,255,.16)
  static const _tagLine = Color(0x47FFFFFF); // rgba(255,255,255,.28)
  static const _subColor = Color(0xDBFFFFFF); // rgba(255,255,255,.86)
  static const _tileBg = Color(0x24FFFFFF); // rgba(255,255,255,.14)

  Widget _text() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _tagBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _tagLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(slide.tag.toUpperCase(), style: tx(12, w: w700, c: MP.white, em: 0.06))],
          ),
        ),
        const Gap(8),
        _fade(
          Text(
            slide.title,
            style: tx(26, w: w800, h: 1.15, em: -0.02, c: MP.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Gap(8),
        _fade(Text(slide.sub, style: tx(14, h: 1.4, c: _subColor), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  /// The white pill. It keeps 44px when there is room and gives way (as the
  /// browser's flex-shrink does) when the copy above runs to two lines.
  Widget _cta() {
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 44),
        child: _fade(
          MpHitSlop(child: Tap(
            onTap: onTap,
            radius: 999,
            color: MP.white,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(slide.cta, style: tx(15, w: w700, c: MP.primary)),
                    const Gap(8),
                    const Ico(I.arrowRight, size: 18, color: MP.primary, stroke: 2),
                  ],
                ),
              ),
            ),
          )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = slide.icon == null;
    final backdrop = slide.image;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Photo cards: no icon tile, the photo says it.
        if (photo || backdrop != null)
          ConstrainedBox(constraints: BoxConstraints(maxWidth: textMaxWidth), child: _text())
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // On a photo the text keeps to the blue side.
              Expanded(
                child: backdrop == null
                    ? _text()
                    : Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: textMaxWidth), child: _text())),
              ),
              const Gap(12),
              _fade(
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  // On a photo the tile gets a soft blue so the icon stays clear.
                  decoration: BoxDecoration(color: backdrop != null ? const Color(0x8C003399) : _tileBg, borderRadius: BorderRadius.circular(14)),
                  child: Ico(slide.icon!, size: 24, color: MP.white),
                ),
              ),
            ],
          ),
        _cta(),
      ],
    );
    return Semantics(
      container: true,
      label: '${slide.tag}. ${slide.title}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 212,
          decoration: BoxDecoration(
            color: photo ? MP.primary : background,
            borderRadius: BorderRadius.circular(20),
            boxShadow: MPShadow.floatStrong,
          ),
          clipBehavior: Clip.antiAlias,
          child: backdrop != null
              ? Stack(
                  children: [
                    // The whole card is the photo; the person is on its right.
                    Positioned.fill(
                      child: _fade(Image.asset(backdrop, fit: BoxFit.cover, alignment: Alignment.centerRight, filterQuality: FilterQuality.high)),
                    ),
                    // A light blue wash on the left keeps the white text easy to read.
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xF2003399), Color(0x99003399), Color(0x00003399)],
                            stops: [0.0, 0.45, 0.72],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(child: Padding(padding: const EdgeInsets.all(20), child: content)),
                  ],
                )
              : photo
              ? Stack(
                  children: [
                    Positioned(
                      top: 0,
                      right: 0,
                      width: imageWidth,
                      height: 212,
                      child: Image.asset('assets/images/hero_patient.jpg', fit: BoxFit.cover, filterQuality: FilterQuality.high),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: const [MP.primary, Color(0x8C003399), Color(0x00003399)],
                            stops: stops,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(child: Padding(padding: const EdgeInsets.all(20), child: content)),
                  ],
                )
              : Padding(padding: const EdgeInsets.all(20), child: content),
        ),
      ),
    );
  }
}

/// Sheet title row with the design's close button (44×44, ×, #545E72).
///
/// Place it 12px below the sheet handle, outside the sheet's side padding (it
/// adds the 20px left gutter itself). It reproduces the browser layout of
/// `gap: 8px` + a button with `margin: -6px -10px 0 0`: the button hangs 6px
/// above the title and 10px into the right gutter. [closeWidth] is the width
/// the button really got in the design (flex-shrink squeezes it below 44 when
/// the subtitle is long), so the title wraps and the × sits exactly as drawn.
/// With [center] the row is vertically centred and the button has no top
/// offset (`align-items: center; margin-right: -10px`).
class P1SheetHeader extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final double closeWidth;
  final bool center;
  const P1SheetHeader({super.key, required this.title, this.subtitle, this.closeWidth = 44, this.center = false});

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        if (subtitle != null) ...[const Gap(4), subtitle!],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(left: 20, top: center ? 6 : 0),
      child: Row(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Expanded(child: center ? text : Padding(padding: const EdgeInsets.only(top: 6), child: text)),
          SizedBox(
            width: closeWidth + 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: closeWidth / 2 - 14),
                child: MpIconButton(
                  I.close,
                  label: 'Close',
                  iconSize: 20,
                  color: MP.ink2,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined pill button: 40px, radius 999, 1px #D5DBE5, white, 14/600 ink.
class P1Pill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const P1Pill(this.label, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Border-box button: 40px tall including the 1px border.
    return MpHitSlop(child: SizedBox(
      height: 40,
      child: Tap(
        onTap: onTap ?? () {},
        radius: 999,
        color: MP.white,
        border: MP.lineStrong,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(widthFactor: 1, child: Text(label, style: tx(14, w: w600))),
        ),
      ),
    ));
  }
}

/// Soft action button: 40px, radius 12, #EBF1FB, 14/700 #003399, optional
/// leading icon with a 6px gap.
class P1SoftButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final double iconSize;
  final double iconStroke;
  final double padding;
  final Color background;
  const P1SoftButton(
    this.label, {
    super.key,
    this.onTap,
    this.icon,
    this.iconSize = 16,
    this.iconStroke = 1.75,
    this.padding = 16,
    this.background = MP.primarySoft,
  });

  @override
  Widget build(BuildContext context) {
    return MpHitSlop(child: Tap(
      onTap: onTap ?? () {},
      radius: 12,
      color: background,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Ico(icon!, size: iconSize, color: MP.primary, stroke: iconStroke), const Gap(6)],
              Text(label, style: tx(14, w: w700, c: MP.primary)),
            ],
          ),
        ),
      ),
    ));
  }
}

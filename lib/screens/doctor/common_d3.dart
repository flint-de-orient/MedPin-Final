import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/downloads.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D3 — Doctor · Reports tab (report registers).

/// Badge colour pair (background, text).
class D3Tone {
  final Color bg;
  final Color fg;
  const D3Tone(this.bg, this.fg);

  static const blue = D3Tone(MP.primarySoft, MP.primary);
  static const grey = D3Tone(MP.fill, MP.ink2);
  static const amber = D3Tone(MP.amberSoft, MP.amber);
  static const red = D3Tone(MP.redSoft, MP.red);
  static const green = D3Tone(MP.greenSoft, MP.green);
}

/// Status pill in report rows: 22px, padding 0 8, radius 999, 12/700.
class D3Badge extends StatelessWidget {
  final String text;
  final D3Tone tone;
  const D3Badge(this.text, {super.key, this.tone = D3Tone.blue});

  @override
  Widget build(BuildContext context) => Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
    child: Text(text, maxLines: 1, softWrap: false, style: tx(12, w: w700, c: tone.fg)),
  );
}

/// Segmented tabs: #F1F4F9 track (padding 4, radius 16), 40px tabs with no
/// gap (radius 12). Selected = white + hairline shadow, 14/600 ink;
/// others 14/500 #545E72.
class D3Tabs extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const D3Tabs({super.key, required this.options, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
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
                      boxShadow: i == index ? MPShadow.hairline : const [],
                    ),
                    child: Text(
                      options[i],
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

/// White pill button of the report filter row: 36px, padding 0 12,
/// 1px #D5DBE5 border, radius 999, 14/600.
class _Pill extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pill({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Tap(
      onTap: onTap,
      radius: 999,
      color: MP.white,
      border: MP.lineStrong,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(widthFactor: 1, child: child),
    ),
  );
}

/// Report register top bar: white, 1px bottom border; 64px back + title +
/// subtitle row, the date / location / filter row and an optional search.
class D3ReportHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? searchHint;
  final ValueChanged<String>? onSearch;

  /// Live: the period and location shown in the pills, and what the pills
  /// do (open the filter sheet with the current filters).
  final String rangeLabel;
  final String locationLabel;
  final VoidCallback? onFilters;
  const D3ReportHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.searchHint,
    this.onSearch,
    this.rangeLabel = '1 – 30 Sep',
    this.locationLabel = 'All locations',
    this.onFilters,
  });

  @override
  Widget build(BuildContext context) {
    void filters() => onFilters != null ? onFilters!() : Nav.go(context, 'Doctor-Reports-Filter');
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(20, w: w700, h: 1.25)),
                      const SizedBox(height: 1),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _Pill(
                  onTap: filters,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.calendar, size: 16, color: MP.ink),
                      const SizedBox(width: 6),
                      Text(rangeLabel, style: tx(14, w: w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: _Pill(
                    onTap: filters,
                    child: Text(locationLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: w600)),
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                const SizedBox(width: 8),
                MpIconButton(
                  I.filter,
                  label: 'Filters',
                  size: 36,
                  iconSize: 16,
                  stroke: 2,
                  radius: 999,
                  background: MP.white,
                  borderColor: MP.lineStrong,
                  onTap: filters,
                ),
              ],
            ),
          ),
          if (searchHint != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MP.lineStrong),
                ),
                child: Row(
                  children: [
                    const Ico(I.search, size: 18, color: MP.ink3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: onSearch,
                        style: tx(15),
                        cursorColor: MP.primary,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: searchHint,
                          hintStyle: tx(15, c: MP.ink3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Three summary tiles: padding 14/12, radius 16, white, 1px border (no
/// shadow); value 22/800 tabular, label 12/1.3 #545E72.
class D3StatTiles extends StatelessWidget {
  final List<(String, String, Color)> items;
  const D3StatTiles(this.items, {super.key});

  @override
  Widget build(BuildContext context) => MpGrid(
    columns: 3,
    gap: 8,
    children: [
      for (final s in items)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: MP.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MP.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.$1, textAlign: TextAlign.center, style: tx(22, w: w800, h: 1.1, em: -0.02, tab: true, c: s.$3)),
              const SizedBox(height: 4),
              Text(s.$2, textAlign: TextAlign.center, style: tx(12, h: 1.3, c: MP.ink2)),
            ],
          ),
        ),
    ],
  );
}

/// One labelled bar: label 14/500, value 14/700 tabular (+ optional grey
/// suffix such as "· 59%"), then an 8px #F1F4F9 track with a blue fill.
class D3BarRow {
  final String label;
  final String value;
  final double fraction;
  final String? suffix;
  const D3BarRow(this.label, this.value, this.fraction, {this.suffix});
}

/// Card of labelled bars: padding 20, radius 24, gap 14; heading 17/700
/// with a 13px #69738A note on the right.
class D3BarCard extends StatelessWidget {
  final String title;
  final String note;
  final List<D3BarRow> rows;
  const D3BarCard({super.key, required this.title, this.note = '', required this.rows});

  @override
  Widget build(BuildContext context) {
    return MpCard(
      padding: const EdgeInsets.all(20),
      child: VGap(
        gap: 14,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: tx(17, w: w700))),
              if (note.isNotEmpty) ...[const SizedBox(width: 8), Text(note, style: tx(13, c: MP.ink3))],
            ],
          ),
          for (final r in rows)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text(r.label, style: tx(14, w: w500))),
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(
                        style: tx(14, tab: true),
                        children: [
                          TextSpan(text: r.value, style: tx(14, w: w700, tab: true)),
                          if (r.suffix != null) ...[
                            const TextSpan(text: ' '),
                            TextSpan(text: r.suffix, style: tx(14, c: MP.ink3, tab: true)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                MpProgress(r.fraction, height: 8, color: MP.primary, track: MP.fill),
              ],
            ),
        ],
      ),
    );
  }
}

/// Uppercase list heading (13/700/.06em #69738A) with an optional 13px note.
class D3SectionHead extends StatelessWidget {
  final String title;
  final String? trailing;
  final EdgeInsetsGeometry padding;
  const D3SectionHead(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 4, 4, 0)});

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title.toUpperCase(), style: tx(13, w: w700, em: 0.06, c: MP.ink3))),
        if (trailing != null) ...[const SizedBox(width: 8), Text(trailing!, style: tx(13, c: MP.ink3))],
      ],
    ),
  );
}

/// White list card (radius 24, 1px border, optional card shadow). Rows carry
/// their own 16px side padding; 1px #E5E9F0 separators are inset 16px.
class D3ListCard extends StatelessWidget {
  final List<Widget> children;
  final bool shadow;
  const D3ListCard({super.key, required this.children, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: MPDeco.card(shadow: shadow ? MPShadow.card : null),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: MpDivider()),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Register row: name 15/700 with a trailing amount / date / badge, a
/// 13/1.4 #545E72 detail line and an optional footer (gap 6, padding 14/16).
class D3RegisterRow extends StatelessWidget {
  final String name;
  final Widget? trailing;
  final String detail;
  final Widget? footer;
  final VoidCallback? onTap;
  const D3RegisterRow({super.key, required this.name, this.trailing, required this.detail, this.footer, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(name, style: tx(15, w: w700))),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
          const SizedBox(height: 6),
          Text(detail, style: tx(13, h: 1.4, c: MP.ink2)),
          if (footer != null) ...[const SizedBox(height: 6), footer!],
        ],
      ),
    );
  }
}

/// Amount at the right of a register row (15/700 tabular).
class D3Amount extends StatelessWidget {
  final String text;
  const D3Amount(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: tx(15, w: w700, tab: true));
}

/// Inline text link (14/600 #003399).
class D3TextLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double size;
  const D3TextLink(this.label, {super.key, this.onTap, this.size = 14});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(label, style: tx(size, w: w600, c: MP.primary)),
    ),
  );
}

/// Row of inline links with a 16px gap ("Send reminder   Call").
class D3LinkRow extends StatelessWidget {
  final List<(String, VoidCallback)> links;
  const D3LinkRow(this.links, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < links.length; i++) ...[
        if (i > 0) const SizedBox(width: 16),
        Flexible(child: D3TextLink(links[i].$1, onTap: links[i].$2)),
      ],
    ],
  );
}

/// "Show N more" text button: 44px, 15/600 #003399, centred.
class D3ShowMore extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const D3ShowMore(this.label, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Tap(onTap: onTap, radius: 12, child: Center(child: Text(label, style: tx(15, w: w600, c: MP.primary)))),
  );
}

/// Pinned report action bar: email (56×56 outline) + "Download …" primary.
/// Download opens the 'Report-Download' sheet.
class D3DownloadBar extends StatelessWidget {
  final String label;

  /// Live: the report being shown (`reportType` + its filters), passed to
  /// the 'Report-Download' sheet and used by the email button.
  final String? reportType;
  final D3Filters? filters;
  const D3DownloadBar(this.label, {super.key, this.reportType, this.filters});

  Future<void> _email(BuildContext context) async {
    if (!isLive || reportType == null) {
      toast(context, 'Report sent to your email');
      return;
    }
    final f = filters ?? const D3Filters();
    final res = await runAction(
      context,
      () => Api.I.post('/api/exports', {
        'kind': 'report',
        'reportType': reportType,
        'format': 'pdf',
        'filters': f.exportFilters,
        'includeMobiles': false,
        'emailCopy': true,
      }),
    );
    if (res is! Map || !context.mounted) return;
    if (res['emailed'] == true) {
      toast(context, 'Report sent to your email');
      return;
    }
    // Not emailed (no email on the account, or email isn't set up): open it instead.
    toast(context, d3EmailNote(res));
    final url = res['url'] as String?;
    if (url != null) await d3Launch(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) => MpBottomBar(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    child: Row(
      children: [
        MpIconButton(
          I.mail,
          label: 'Email this report',
          size: 56,
          iconSize: 20,
          radius: 16,
          background: MP.white,
          borderColor: MP.lineStrong,
          onTap: () => _email(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MpButton(
            label,
            icon: I.downloadAlt,
            iconStroke: 1.75,
            onTap: () => Nav.go(
              context,
              'Report-Download',
              args: reportType == null ? null : (filters ?? const D3Filters()).downloadArgs(reportType!),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Rupees with Indian digit grouping (₹4,200 · ₹1,61,000).
String d3Rupees(int v) {
  final s = v.abs().toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

/// Short rupees for tiles: ₹1.57L from one lakh up, else ₹4,300.
String d3RupeesShort(num v) => v.abs() >= 100000 ? '₹${(v / 100000).toStringAsFixed(2)}L' : d3Rupees(v.round());

// ── Live report helpers ──

/// What happened to the "email me a copy" part of an export.
String d3EmailNote(Map res) {
  if (res['emailed'] == true) return 'copy sent to your email';
  if (res['emailMissing'] == true) return 'add your email in My profile to get a copy';
  return "email isn't set up yet, so no copy was sent";
}

/// Opens a link outside the app (tests replace it).
Future<bool> Function(Uri uri) d3Launch = (uri) async {
  final ctx = Nav.key.currentContext;
  if (Downloads.isFile('$uri') && ctx != null && ctx.mounted) {
    await Downloads.open(ctx, '$uri');
    return true;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
};

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _wdLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Today as an IST calendar day (the practice's day, as the API counts it).
DateTime d3Today() {
  final n = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(n.year, n.month, n.day);
}

/// API timestamp → its IST calendar day ("2026-09-29T18:30:00Z" → 30 Sep);
/// a plain "2026-09-30" is taken as is.
DateTime? d3Day(Object? v) {
  if (v is! String) return null;
  final t = DateTime.tryParse(v);
  if (t == null) return null;
  if (!v.contains('T')) return DateTime(t.year, t.month, t.day);
  final n = t.toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(n.year, n.month, n.day);
}

DateTime d3AddDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// "2026-09-30"
String d3DayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "Wed, 30 Sep"
String d3DayHead(DateTime d) => '${_wd[d.weekday - 1]}, ${F.dayMonth(d)}';

String d3Weekday(DateTime d) => _wd[d.weekday - 1];
String d3WeekdayLong(DateTime d) => _wdLong[d.weekday - 1];
String d3MonthLong(DateTime d) => _monthsLong[d.month - 1];

/// "1 – 30 Sep", "10 Sep – 9 Oct", "28 Dec 2025 – 3 Jan 2026" (optionally
/// with the year: "1 – 30 Sep 2026").
String d3RangeLabel(DateTime from, DateTime to, {bool year = false}) {
  final y = year ? ' ${to.year}' : '';
  if (F.sameDay(from, to)) return '${F.dayMonth(to)}$y';
  if (from.year != to.year) return '${F.dayMonth(from)} ${from.year} – ${F.dayMonth(to)} ${to.year}';
  if (from.month == to.month) return '${from.day} – ${F.dayMonth(to)}$y';
  return '${F.dayMonth(from)} – ${F.dayMonth(to)}$y';
}

/// "58 M", "29 F", "58", ""
String d3AgeSex(Object? age, Object? gender) {
  final g = switch (gender) {
    'male' => 'M',
    'female' => 'F',
    _ => '',
  };
  return [if (age != null) '$age', if (g.isNotEmpty) g].join(' ');
}

String d3VisitType(String k) => switch (k) {
  'follow_up' => 'Follow-up',
  'new' => 'New patient',
  'report_review' => 'Report review',
  _ => k,
};

String d3Mode(String k) => switch (k) {
  'in_clinic' => 'In clinic',
  'video' => 'Video',
  _ => k,
};

String d3AgeGroup(String k) => switch (k) {
  'under_18' => 'Under 18',
  '18_40' => '18 – 40',
  '41_60' => '41 – 60',
  'over_60' => 'Over 60',
  _ => k,
};

String d3Method(String k) => switch (k) {
  'upi' => 'UPI',
  'cash' => 'Cash',
  'card' => 'Card',
  'net_banking' => 'Net banking',
  'online' => 'Online',
  _ => k,
};

/// "City Care Clinic — Salt Lake" → "City Care Clinic · Salt Lake".
String d3LocationName(Map<String, dynamic> l) => l.str('name', l.str('shortName')).replaceAll(' — ', ' · ');

/// "1 consultation", "1,204 consultations"
String d3Plural(num n, String one, [String? many]) => '${F.count(n)} ${n == 1 ? one : (many ?? '${one}s')}';

/// The report period and filters (Doctor-Reports-Filter). Doctor-Reports
/// keeps them and passes them on as `args: {'filters': f}`; the filter
/// sheet returns a new one with `Navigator.pop`.
class D3Filters {
  /// today / 7_days / 30_days / this_month / this_year / custom
  final String range;

  /// Custom range (IST calendar days, both inclusive).
  final DateTime? from;
  final DateTime? to;
  final List<String> locationIds;
  final List<String> visitTypes;
  final List<String> modes;
  final List<String> ageGroups;
  final bool compare;
  final String locationLabel;

  const D3Filters({
    this.range = '30_days',
    this.from,
    this.to,
    this.locationIds = const [],
    this.visitTypes = const [],
    this.modes = const [],
    this.ageGroups = const [],
    this.compare = true,
    this.locationLabel = 'All locations',
  });

  /// From screen args: `{'filters': D3Filters}` or `{'from', 'to'}` days.
  static D3Filters of(Object? args) {
    if (args is D3Filters) return args;
    if (args is Map) {
      final f = args['filters'];
      if (f is D3Filters) return f;
      final from = d3Day(args['from']);
      final to = d3Day(args['to']);
      if (from != null && to != null) return D3Filters(range: 'custom', from: from, to: to);
    }
    return const D3Filters();
  }

  /// The sheet's date chips, in order.
  static const presets = ['today', '7_days', '30_days', 'this_month', 'this_year'];

  D3Filters copyWith({String? range, DateTime? from, DateTime? to}) => D3Filters(
    range: range ?? this.range,
    from: from ?? this.from,
    to: to ?? this.to,
    locationIds: locationIds,
    visitTypes: visitTypes,
    modes: modes,
    ageGroups: ageGroups,
    compare: compare,
    locationLabel: locationLabel,
  );

  /// The period as IST days, both inclusive (as the API's rangeOf).
  (DateTime, DateTime) get days {
    final t = d3Today();
    if (range == 'custom' && from != null) return (from!, to ?? t);
    return switch (range) {
      'today' => (t, t),
      '7_days' => (d3AddDays(t, -6), t),
      'this_month' => (DateTime(t.year, t.month, 1), t),
      'this_year' => (DateTime(t.year, 1, 1), t),
      _ => (d3AddDays(t, -29), t),
    };
  }

  /// Days in the period.
  int get length {
    final (a, b) = days;
    return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;
  }

  /// The previous period of the same length (what "compare" uses).
  (DateTime, DateTime) get previousDays => (d3AddDays(days.$1, -length), d3AddDays(days.$1, -1));

  /// "1 – 30 Sep"
  String get label => d3RangeLabel(days.$1, days.$2);

  /// "1 – 30 Sep 2026 · compared with 1 – 31 Aug"
  String get longLabel {
    final now = d3RangeLabel(days.$1, days.$2, year: true);
    if (!compare) return now;
    final (a, b) = previousDays;
    return '$now · compared with ${d3RangeLabel(a, b, year: a.year != days.$2.year)}';
  }

  /// What "vs …" refers to: "August", "yesterday", "previous 30 days".
  String get previousName {
    final (a, b) = previousDays;
    if (a.day == 1 && a.month == b.month && d3AddDays(b, 1).day == 1) return d3MonthLong(a);
    if (length == 1) return range == 'today' ? 'yesterday' : 'previous day';
    return 'previous $length days';
  }

  /// Query for the /api/reports/* endpoints.
  Map<String, Object?> get query => {
    if (range == 'custom' && from != null) ...{'from': d3DayKey(days.$1), 'to': d3DayKey(days.$2)} else 'range': range,
    if (locationIds.isNotEmpty) 'locationIds': locationIds.join(','),
    if (visitTypes.isNotEmpty) 'visitTypes': visitTypes.join(','),
    if (modes.isNotEmpty) 'modes': modes.join(','),
    if (ageGroups.isNotEmpty) 'ageGroups': ageGroups.join(','),
    if (!compare) 'compare': 'false',
  };

  /// `filters` for POST /api/exports.
  Map<String, Object?> get exportFilters => {
    'from': d3DayKey(days.$1),
    'to': d3DayKey(days.$2),
    if (locationIds.isNotEmpty) 'locationIds': locationIds,
    if (visitTypes.isNotEmpty) 'visitTypes': visitTypes,
    if (modes.isNotEmpty) 'modes': modes,
    if (ageGroups.isNotEmpty) 'ageGroups': ageGroups,
  };

  /// Args for the 'Report-Download' sheet.
  Map<String, Object?> downloadArgs(String reportType) => {
    'reportType': reportType,
    'from': d3DayKey(days.$1),
    'to': d3DayKey(days.$2),
    'filters': this,
  };
}

/// Live register screens: the filters come from the args and are changed
/// with the header pills (which open the filter sheet, then re-fetch).
mixin D3FilterState<W extends StatefulWidget> on LiveData<W> {
  D3Filters? _filters;
  D3Filters get filters => _filters ??= D3Filters.of(Nav.args<Object>(context));

  /// Call first in fetch(): the first fetch starts inside initState, where
  /// the route args can't be read yet.
  Future<D3Filters> loadFilters() async {
    if (_filters == null) await Future<void>.value();
    return filters;
  }

  Future<void> pickFilters() async {
    final f = await Nav.go<D3Filters>(context, 'Doctor-Reports-Filter', args: {'filters': filters});
    if (f == null || !mounted) return;
    setState(() => _filters = f);
    reload();
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';

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
  const D3ReportHeader({super.key, required this.title, required this.subtitle, this.searchHint, this.onSearch});

  @override
  Widget build(BuildContext context) {
    void filters() => Nav.go(context, 'Doctor-Reports-Filter');
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
                      Text('1 – 30 Sep', style: tx(14, w: w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Pill(onTap: filters, child: Text('All locations', style: tx(14, w: w600))),
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
  const D3DownloadBar(this.label, {super.key});

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
          onTap: () => toast(context, 'Report sent to your email'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MpButton(
            label,
            icon: I.downloadAlt,
            iconStroke: 1.75,
            onTap: () => Nav.go(context, 'Report-Download'),
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

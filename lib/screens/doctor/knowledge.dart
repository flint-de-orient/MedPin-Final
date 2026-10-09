import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Knowledge.dc.html — "Knowledge base".
/// Live data: GET /api/knowledge (practice + adopted) and
/// GET /api/knowledge?shared=true; chip counts are of the merged list.
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

/// Status pill colours (bg, fg).
const _status = <String, (Color, Color)>{
  'Approved': (MP.greenSoft, MP.green),
  'Pending': (MP.amberSoft, MP.amber),
  'Draft': (MP.fill, MP.ink2),
  'Retired': (MP.fill, MP.ink3),
};

/// (title, status, excerpt, meta, shared by MedPin)
typedef _Entry = (String, String, String, String, bool);

const List<_Entry> _entries = [
  (
    'Metformin timing',
    'Approved',
    'Take with meals to reduce stomach upset; split doses morning and night.',
    'English · Medicines · Updated 2 days ago',
    false,
  ),
  (
    'Home BP: when to call us',
    'Pending',
    'Call the clinic the same day if BP is above 180/110 or with chest pain.',
    'English · Hypertension · Updated today',
    false,
  ),
  (
    'Iron tablets and tea',
    'Draft',
    'Keep tea and coffee 2 hours away from iron tablets for better absorption.',
    'English · Medicines · Updated yesterday',
    false,
  ),
  (
    'When to repeat HbA1c',
    'Approved',
    'Every 3 months until on target, then every 6 months if stable.',
    'English · Diabetes · Updated 3 weeks ago',
    false,
  ),
  (
    'Thyroid tablet on an empty stomach',
    'Approved',
    'Take levothyroxine with water, 30 to 60 minutes before breakfast or tea.',
    'English · Medicines · Updated 1 Sep',
    true,
  ),
  (
    'Fasting days with diabetes',
    'Approved',
    'Check sugar more often while fasting and break the fast if it drops below 70.',
    'English · Diabetes · Updated 18 Aug',
    true,
  ),
  (
    'Monsoon fever: dengue checks',
    'Retired',
    'Superseded by the 2026 clinic fever protocol.',
    'English · Infections · Retired 2 Sep',
    false,
  ),
];

/// Filter chips: (label, status or null for all).
const _filters = [
  ('All · 7', null),
  ('Approved · 4', 'Approved'),
  ('Pending · 1', 'Pending'),
  ('Draft · 1', 'Draft'),
  ('Retired · 1', 'Retired'),
];

class _KnowledgeScreenState extends State<KnowledgeScreen> with LiveData {
  int _filter = 0;

  /// The practice's entries (with adopted MedPin ones) plus every shared
  /// MedPin entry, so shared ones can be found and adopted.
  @override
  Future<Object?> fetch() async {
    final res = await Future.wait([
      Api.I.get('/api/knowledge'),
      Api.I.get('/api/knowledge', query: {'shared': 'true'}),
    ]);
    final seen = <String>{};
    final items = <Map<String, dynamic>>[
      for (final r in res)
        for (final e in (r as Map).cast<String, dynamic>().list('items'))
          if (seen.add(e.str('id'))) e,
    ]..sort((a, b) => b.str('updatedAt').compareTo(a.str('updatedAt')));
    return {'items': items};
  }

  static _Entry _entryOf(Map<String, dynamic> e) {
    final status = d10Cap(e.str('status', 'draft'));
    final updated = F.date(e['updatedAt']);
    final retired = F.date(e['retiredAt']);
    final when = e['status'] == 'retired' && retired != null
        ? 'Retired ${F.dayMonth(retired)}'
        : (updated == null ? '' : 'Updated ${d10Since(updated)}');
    final summary = e.str('summary').trim();
    return (
      e.str('title'),
      status,
      e['status'] == 'retired' && e.str('retiredNote').isNotEmpty ? e.str('retiredNote') : (summary.isEmpty ? e.str('content') : summary),
      [
        d10Languages[e.str('language')] ?? 'English',
        d10Categories[e.str('category')] ?? d10Cap(e.str('category')),
        if (when.isNotEmpty) when,
      ].where((x) => x.isNotEmpty).join(' · '),
      e['shared'] == true,
    );
  }

  Future<void> _open(Map<String, dynamic>? e) async {
    if (!isLive) {
      Nav.go(context, 'Knowledge-Editor');
      return;
    }
    final shared = e?['shared'] == true;
    await Nav.go(context, shared ? 'Knowledge-Shared' : 'Knowledge-Editor', args: e == null ? null : {'knowledgeId': e.str('id')});
    if (mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final d = data;
    final live = d == null ? null : [for (final e in d.list('items')) (e, _entryOf(e))];
    final filters = live == null
        ? _filters
        : [
            for (final f in _filters)
              (
                '${f.$1.split(' · ').first} · ${f.$2 == null ? live.length : live.where((x) => x.$2.$2 == f.$2).length}',
                f.$2,
              ),
          ];
    final status = filters[_filter].$2;
    final shown = [
      for (final e in _entries)
        if (status == null || e.$2 == status) e,
    ];
    final liveShown = [
      for (final x in live ?? const <(Map<String, dynamic>, _Entry)>[])
        if (status == null || x.$2.$2 == status) x,
    ];
    return MpPage(
      header: MpHeader(
        'Knowledge base',
        actions: [MpIconButton(I.plus, label: 'Add entry', onTap: () => _open(null))],
      ),
      body: placeholder ?? Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Approved entries ground the AI assistant's answers to your patients.",
                style: tx(14, c: MP.ink2, h: 20 / 14),
              ),
            ),
            const Gap(16),
            MpChipRow(
              gap: 8,
              children: [
                for (var i = 0; i < filters.length; i++)
                  D10FilterChip(filters[i].$1, selected: i == _filter, onTap: () => setState(() => _filter = i)),
              ],
            ),
            const Gap(16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: live != null && liveShown.isEmpty
                  ? Text('No entries here yet', style: tx(14, c: MP.ink2))
                  : Semantics(
                label: 'Entries',
                container: true,
                child: D10ListCard(
                  children: live == null
                      ? [for (var i = 0; i < shown.length; i++) _EntryRow(shown[i], divider: i > 0)]
                      : [
                          for (var i = 0; i < liveShown.length; i++)
                            _EntryRow(liveShown[i].$2, divider: i > 0, onOpen: () => _open(liveShown[i].$1)),
                        ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottom: MpBottomBar(child: MpButton('Add entry', icon: I.plus, onTap: () => _open(null))),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final _Entry e;
  final bool divider;
  final VoidCallback? onOpen;
  const _EntryRow(this.e, {required this.divider, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _status[e.$2] ?? _status['Draft']!;
    final retired = e.$2 == 'Retired';
    final titleColor = retired ? MP.ink3 : MP.ink;
    final bodyColor = retired ? MP.ink3 : MP.ink2;
    return D10ListRow(
      divider: divider,
      vPad: 16,
      onTap: onOpen ?? () => Nav.go(context, e.$5 ? 'Knowledge-Shared' : 'Knowledge-Editor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tx(16, w: w600, c: titleColor),
                  ),
                ),
                const Gap(12),
                MpBadge(e.$2, bg: bg, fg: fg, weight: w600),
              ],
            ),
          ),
          const Gap(4),
          Text(e.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: bodyColor, h: 20 / 14)),
          const Gap(4),
          Text(e.$4, style: tx(13, c: MP.ink3, h: 18 / 13)),
          if (e.$5) ...[
            const Gap(4),
            Row(
              children: [
                const Ico(I.lock, size: 14, color: MP.ink2, stroke: 2),
                const Gap(6),
                Text('Shared by MedPin', style: tx(13, w: w600, c: MP.ink2, h: 18 / 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

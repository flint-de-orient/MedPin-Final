import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Knowledge.dc.html — "Knowledge base".
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

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final status = _filters[_filter].$2;
    final shown = [
      for (final e in _entries)
        if (status == null || e.$2 == status) e,
    ];
    return MpPage(
      header: MpHeader(
        'Knowledge base',
        actions: [MpIconButton(I.plus, label: 'Add entry', onTap: () => Nav.go(context, 'Knowledge-Editor'))],
      ),
      body: Padding(
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
                for (var i = 0; i < _filters.length; i++)
                  D10FilterChip(_filters[i].$1, selected: i == _filter, onTap: () => setState(() => _filter = i)),
              ],
            ),
            const Gap(16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Semantics(
                label: 'Entries',
                container: true,
                child: D10ListCard(
                  children: [for (var i = 0; i < shown.length; i++) _EntryRow(shown[i], divider: i > 0)],
                ),
              ),
            ),
          ],
        ),
      ),
      bottom: MpBottomBar(child: MpButton('Add entry', icon: I.plus, onTap: () => Nav.go(context, 'Knowledge-Editor'))),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final _Entry e;
  final bool divider;
  const _EntryRow(this.e, {required this.divider});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _status[e.$2]!;
    final retired = e.$2 == 'Retired';
    final titleColor = retired ? MP.ink3 : MP.ink;
    final bodyColor = retired ? MP.ink3 : MP.ink2;
    return D10ListRow(
      divider: divider,
      vPad: 16,
      onTap: () => Nav.go(context, e.$5 ? 'Knowledge-Shared' : 'Knowledge-Editor'),
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

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Chat-Review.dc.html — "Chat review".
class ChatReviewScreen extends StatefulWidget {
  const ChatReviewScreen({super.key});

  @override
  State<ChatReviewScreen> createState() => _ChatReviewScreenState();
}

/// Urgency pill colours (bg, fg).
const _urgency = <String, (Color, Color)>{
  'High': (MP.amberSoft, MP.amber),
  'Medium': (MP.fill, MP.ink2),
  'Low': (MP.greenSoft, MP.green),
};

/// (initials, name, time, reason, urgency, preview) — most urgent first.
typedef _Flag = (String, String, String, String, String, String);

const List<_Flag> _flagged = [
  (
    'RD',
    'Rahul Das',
    '8:52 AM',
    'Symptom question: BP with headache',
    'High',
    'AI: A reading of 172/104 with a headache needs checking today. Please visit the clinic or call us at…',
  ),
  (
    'SM',
    'Sujit Mondal',
    '9:44 AM',
    'Dosage question answered by AI',
    'Medium',
    'AI: You can take Metformin with dinner instead of breakfast. Since your plan is 1-0-1, take both tablets…',
  ),
  (
    'FI',
    'Farhana Islam',
    'Yesterday',
    'Low-confidence answer',
    'Low',
    'AI: Iron tablets can turn stools dark, which is usually harmless. If you also feel dizzy or breathless…',
  ),
];

/// (initials, name, time, reason, preview)
const _reviewed = (
  'DB',
  'Debasish Bose',
  '7:20 AM',
  'Diet advice outside knowledge base',
  'Reviewed by Dr. Sen at 8:15 AM. AI: Brown rice in small portions is fine; pair it with dal and vegetables.',
);

class _ChatReviewScreenState extends State<ChatReviewScreen> {
  int _tab = 0;
  String _query = '';

  bool _matches(List<String> fields) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final flagged = [
      for (final r in _flagged)
        if (_matches([r.$2, r.$4, r.$6])) r,
    ];
    final showReviewed = _matches([_reviewed.$2, _reviewed.$4, _reviewed.$5]);

    return MpPage(
      header: const MpHeader('Chat review'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          MpSegmented(options: const ['Flagged (3)', 'All'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          D10SearchField(hint: 'Search patient or message', padLeft: 46, onChanged: (v) => setState(() => _query = v)),
          if (flagged.isNotEmpty)
            _Section(
              title: 'Needs review · most urgent first',
              rows: [for (var i = 0; i < flagged.length; i++) _FlaggedRow(flagged[i], divider: i > 0)],
            ),
          if (showReviewed) const _Section(title: 'Reviewed today', rows: [_ReviewedRow()]),
          if (flagged.isEmpty && !showReviewed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No conversations match “${_query.trim()}”',
                textAlign: TextAlign.center,
                style: tx(14, c: MP.ink3, h: 20 / 14),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uppercase heading (12/16) + list card, 8px apart.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => VGap(gap: 8, children: [D10Caps(title), D10ListCard(children: rows)]);
}

class _FlaggedRow extends StatelessWidget {
  final _Flag r;
  final bool divider;
  const _FlaggedRow(this.r, {required this.divider});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _urgency[r.$5]!;
    return D10ListRow(
      divider: divider,
      vPad: 16,
      onTap: () => Nav.go(context, 'Chat-Review-Detail'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MpAvatar(r.$1, size: 40, fontSize: 14),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      Expanded(child: Text(r.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600))),
                      const Gap(8),
                      Text(r.$3, style: tx(13, c: MP.ink3, tab: true)),
                    ],
                  ),
                ),
                const Gap(4),
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      Expanded(child: Text(r.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: w600))),
                      const Gap(8),
                      MpBadge(r.$5, bg: bg, fg: fg, weight: w600),
                    ],
                  ),
                ),
                const Gap(4),
                Text(r.$6, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2, h: 20 / 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Already-reviewed conversation: everything in #69738A.
class _ReviewedRow extends StatelessWidget {
  const _ReviewedRow();

  @override
  Widget build(BuildContext context) {
    return D10ListRow(
      vPad: 16,
      onTap: () => Nav.go(context, 'Chat-Review-Detail'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MpAvatar(_reviewed.$1, size: 40, fontSize: 14, bg: MP.fill, fg: MP.ink3),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _reviewed.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(16, w: w600, c: MP.ink3),
                        ),
                      ),
                      const Gap(8),
                      Text(_reviewed.$3, style: tx(13, c: MP.ink3, tab: true)),
                    ],
                  ),
                ),
                const Gap(4),
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _reviewed.$4,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(14, w: w600, c: MP.ink3),
                        ),
                      ),
                      const Gap(8),
                      const Ico(I.check, size: 16, color: MP.green, stroke: 2.25),
                      const Gap(4),
                      Text('Reviewed', style: tx(13, w: w600, c: MP.green)),
                    ],
                  ),
                ),
                const Gap(4),
                Text(_reviewed.$5, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink3, h: 20 / 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

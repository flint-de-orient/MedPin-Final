import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Chat-Review.dc.html — "Chat review".
/// Live data: GET /api/inbox/reviews?status=all (flagged count, urgency
/// order); rows open Chat-Review-Detail {'reviewId', 'conversationId'}.
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

class _ChatReviewScreenState extends State<ChatReviewScreen> with LiveData {
  int _tab = 0;
  String _query = '';

  /// Every review (needing review first, most urgent first); the search and
  /// the tabs filter it here.
  @override
  Future<Object?> fetch() => Api.I.get('/api/inbox/reviews', query: {'status': 'all'});

  bool _matches(List<String> fields) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  static _Flag _flagOf(Map<String, dynamic> m) {
    final name = m.obj('patientId').str('name', 'Patient');
    final at = F.date(m['createdAt']);
    final excerpt = m.str('excerpt').trim();
    return (
      F.initials(name),
      name,
      at == null ? '' : F.askedAt(at),
      m.str('title', 'Flagged: ${d10Reason(m.str('reason'))}'),
      d10Cap(m.str('urgency', 'medium')),
      excerpt.isEmpty ? '' : 'AI: $excerpt',
    );
  }

  static (String, String, String, String, String) _reviewedOf(Map<String, dynamic> m) {
    final f = _flagOf(m);
    final rv = m.obj('reviewed');
    final by = d10Person(rv['by'] is Map ? rv.obj('by').str('name') : '');
    final at = F.date(rv['at']);
    final when = at == null ? '' : (F.sameDay(at, DateTime.now()) ? ' at ${F.time(at)}' : ' on ${F.dayMonth(at)}');
    final line = by.isEmpty ? 'Reviewed$when.' : 'Reviewed by $by$when.';
    return (f.$1, f.$2, f.$3, f.$4, f.$6.isEmpty ? line : '$line ${f.$6}');
  }

  Future<void> _open(Map<String, dynamic>? m) async {
    if (m == null) {
      Nav.go(context, 'Chat-Review-Detail');
      return;
    }
    await Nav.go(context, 'Chat-Review-Detail', args: {
      'reviewId': m.str('id'),
      'conversationId': m.str('conversationId'),
      'patientId': m.obj('patientId').str('id'),
    });
    if (mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (data != null) return _live(context);
    final flagged = [
      for (final r in _flagged)
        if (_matches([r.$2, r.$4, r.$6])) r,
    ];
    final showReviewed = _matches([_reviewed.$2, _reviewed.$4, _reviewed.$5]);

    return MpPage(
      header: const MpHeader('Chat review'),
      body: placeholder ?? VGap(
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

  /// The same page from GET /api/inbox/reviews.
  Widget _live(BuildContext context) {
    final items = data!.list('items');
    bool match(Map<String, dynamic> m) => _matches([m.obj('patientId').str('name'), m.str('title'), m.str('excerpt')]);
    final flagged = [for (final m in items) if (m['status'] == 'needs_review' && match(m)) m];
    final now = DateTime.now();
    final reviewed = [
      for (final m in items)
        if (m['status'] == 'reviewed' && match(m))
          if (_tab == 1 || (F.date(m.obj('reviewed')['at']) != null && F.sameDay(F.date(m.obj('reviewed')['at'])!, now))) m,
    ];
    final q = _query.trim();
    return MpPage(
      header: const MpHeader('Chat review'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          MpSegmented(
            options: ['Flagged (${data!.numOr('flagged')})', 'All'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          D10SearchField(hint: 'Search patient or message', padLeft: 46, onChanged: (v) => setState(() => _query = v)),
          if (flagged.isNotEmpty)
            _Section(
              title: 'Needs review · most urgent first',
              rows: [
                for (var i = 0; i < flagged.length; i++)
                  _FlaggedRow(_flagOf(flagged[i]), divider: i > 0, onOpen: () => _open(flagged[i])),
              ],
            ),
          if (reviewed.isNotEmpty)
            _Section(
              title: _tab == 1 ? 'Reviewed' : 'Reviewed today',
              rows: [
                for (var i = 0; i < reviewed.length; i++)
                  _ReviewedRow(r: _reviewedOf(reviewed[i]), divider: i > 0, onOpen: () => _open(reviewed[i])),
              ],
            ),
          if (flagged.isEmpty && reviewed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                q.isEmpty ? 'No AI answers to review' : 'No conversations match “$q”',
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
  final VoidCallback? onOpen;
  const _FlaggedRow(this.r, {required this.divider, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _urgency[r.$5] ?? _urgency['Medium']!;
    return D10ListRow(
      divider: divider,
      vPad: 16,
      onTap: onOpen ?? () => Nav.go(context, 'Chat-Review-Detail'),
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
  final (String, String, String, String, String) r;
  final bool divider;
  final VoidCallback? onOpen;
  const _ReviewedRow({this.r = _reviewed, this.divider = false, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return D10ListRow(
      divider: divider,
      vPad: 16,
      onTap: onOpen ?? () => Nav.go(context, 'Chat-Review-Detail'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MpAvatar(r.$1, size: 40, fontSize: 14, bg: MP.fill, fg: MP.ink3),
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
                          r.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(16, w: w600, c: MP.ink3),
                        ),
                      ),
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
                      Expanded(
                        child: Text(
                          r.$4,
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
                Text(r.$5, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink3, h: 20 / 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

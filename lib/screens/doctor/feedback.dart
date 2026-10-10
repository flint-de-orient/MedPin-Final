import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Feedback.dc.html — "Feedback".
/// Live data: GET /api/feedback (counts per category); opening the page marks
/// unread items read (POST /api/feedback/:id/read); Reply opens the patient's
/// care thread (POST /api/inbox {patientId} → Patient-Thread).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

/// (name, date, rating, kind, message, readBy, reply, replyMeta)
typedef _Fb = (String, String, int, String, String, String, String, String);

/// Reply is offered only to people holding the chat-reply permission.
const _hasChatReply = true;

const List<_Fb> _items = [
  (
    'Moumita Roy',
    '28 Sep',
    5,
    'Care',
    'Dr. Sen explained my reports patiently, and the reminders in the app help me stay on track.',
    'Read by Dr. Sen, Tania',
    'Thank you, Moumita. See you at your follow-up on Mon, 12 Oct.',
    'Clinic replied · Tania Ghosh · 28 Sep',
  ),
  (
    'Debasish Bose',
    '27 Sep',
    2,
    'App',
    'The app logs me out every few days and I have to enter the OTP again. Very tiring.',
    'Read by Tania',
    '',
    '',
  ),
  (
    'Aisha Khan',
    '25 Sep',
    4,
    'Care',
    'Waiting time was long on Saturday, but the doctor was very thorough.',
    'Read by Dr. Sen',
    '',
    '',
  ),
  (
    'Rahul Das',
    '22 Sep',
    5,
    'Care',
    'Got my BP medicine adjusted over chat without an extra visit. Very convenient.',
    'Read by Dr. Sen, Tania',
    'Glad it helped, Rahul. Keep logging your BP every morning.',
    'Clinic replied · Dr. Sen · 23 Sep',
  ),
];

/// Filter chips: (label, kind or null for all).
const _filters = [('All · 4', null), ('Care · 3', 'Care'), ('App · 1', 'App')];

class _FeedbackScreenState extends State<FeedbackScreen> with LiveData {
  int _filter = 0;
  final _marked = <String>{};
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() => Api.I.get('/api/feedback');

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Future<void> reload({bool quiet = false}) async {
    await super.reload(quiet: quiet);
    if (mounted && data != null) _markRead();
  }

  /// Opening the page reads the feedback: POST /api/feedback/:id/read for
  /// every item the signed-in user hasn't read yet.
  Future<void> _markRead() async {
    final me = d1MyId;
    final ids = [
      for (final f in data!.list('items'))
        if (!_marked.contains(f.str('id')) &&
            !f.list('readBy').any((r) => (r['userId'] is Map ? r.obj('userId').str('id') : r.str('userId')) == me))
          f.str('id'),
    ];
    if (ids.isEmpty) return;
    _marked.addAll(ids);
    try {
      await Future.wait([for (final id in ids) Api.I.post('/api/feedback/$id/read')]);
    } on ApiException {
      return;
    }
    if (mounted) reload(quiet: true);
  }

  static _Fb _fbOf(Map<String, dynamic> f) {
    final at = F.date(f['createdAt']);
    final readers = [
      for (final r in f.list('readBy'))
        d10Person(r['userId'] is Map ? r.obj('userId').str('name') : ''),
    ].where((x) => x.isNotEmpty).toList();
    final reply = f.obj('reply');
    final replyAt = F.date(reply['at']);
    final by = reply['by'] is Map ? reply.obj('by').str('name') : '';
    return (
      f.obj('patientId').str('name', 'Patient'),
      at == null ? '' : F.dayMonth(at),
      f.numOr('rating').round().clamp(0, 5),
      d10Cap(f.str('category', 'care')),
      f.str('comment'),
      readers.isEmpty ? 'Not read yet' : 'Read by ${readers.join(', ')}',
      reply.str('text'),
      ['Clinic replied', if (by.isNotEmpty) by, if (replyAt != null) F.dayMonth(replyAt)].join(' · '),
    );
  }

  /// Replies go out over the patient's care thread.
  Future<void> _reply(Map<String, dynamic> f) async {
    final pid = f.obj('patientId').str('id');
    final convo = await runAction(context, () => Api.I.post('/api/inbox', {'patientId': pid}), busy: _busy);
    if (convo is! Map || !mounted) return;
    await Nav.go(context, 'Patient-Thread', args: {'conversationId': convo['id'], 'patientId': pid});
    if (mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    if (data != null) return _live(context);
    final placeholder = livePlaceholder();
    final kind = _filters[_filter].$2;
    return MpPage(
      header: const MpHeader('Patient feedback'),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          Semantics(
            label: 'Filter feedback',
            container: true,
            child: Row(
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0) const Gap(8),
                  D10FilterChip(_filters[i].$1, selected: i == _filter, onTap: () => setState(() => _filter = i)),
                ],
              ],
            ),
          ),
          for (final f in _items)
            if (kind == null || f.$4 == kind) _FeedbackCard(f),
        ],
      ),
    );
  }

  /// The same page from GET /api/feedback.
  Widget _live(BuildContext context) {
    final c = data!.obj('counts');
    final filters = [
      ('All · ${c.numOr('all')}', null),
      ('Care · ${c.numOr('care')}', 'care'),
      ('App · ${c.numOr('app')}', 'app'),
    ];
    final cat = filters[_filter].$2;
    final items = [for (final f in data!.list('items')) if (cat == null || f['category'] == cat) f];
    // Replying needs the chat permission (every role except the lab's).
    final canChat = !const {'lab_manager', 'lab_technician'}.contains(Session.I.role);
    return MpPage(
      header: const MpHeader('Patient feedback'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          Semantics(
            label: 'Filter feedback',
            container: true,
            child: Row(
              children: [
                for (var i = 0; i < filters.length; i++) ...[
                  if (i > 0) const Gap(8),
                  D10FilterChip(filters[i].$1, selected: i == _filter, onTap: () => setState(() => _filter = i)),
                ],
              ],
            ),
          ),
          if (items.isEmpty) Text('No feedback yet', style: tx(14, c: MP.ink2)),
          for (final f in items) _FeedbackCard(_fbOf(f), canReply: canChat, onReply: () => _reply(f)),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final _Fb f;
  final bool canReply;
  final VoidCallback? onReply;
  const _FeedbackCard(this.f, {this.canReply = _hasChatReply, this.onReply});

  @override
  Widget build(BuildContext context) {
    final hasReply = f.$7.isNotEmpty;
    final canReply = !hasReply && this.canReply;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(child: Text(f.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600))),
                const Gap(12),
                Text(f.$2, style: tx(13, c: MP.ink3, tab: true)),
              ],
            ),
          ),
          const Gap(8),
          SizedBox(height: 24, child: Row(children: [_Stars(f.$3), const Gap(12), MpBadge(f.$4, weight: w600)])),
          const Gap(12),
          Text(f.$5, style: tx(16, h: 1.5)),
          const Gap(12),
          Row(
            children: [
              const Ico(I.eye, size: 14, color: MP.ink3),
              const Gap(6),
              Expanded(child: Text(f.$6, style: tx(13, c: MP.ink3, h: 18 / 13))),
            ],
          ),
          if (hasReply) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(f.$8, style: tx(13, w: w600, c: MP.ink2, h: 18 / 13)),
                  const Gap(4),
                  Text(f.$7, style: tx(14, c: MP.ink2, h: 20 / 14)),
                ],
              ),
            ),
          ],
          if (canReply) ...[
            const Gap(12),
            Align(
              alignment: Alignment.centerLeft,
              child: Tap(
                // Replies go out over the patient's chat thread.
                onTap: onReply ?? () => Nav.go(context, 'Patient-Thread'),
                radius: 12,
                color: MP.primarySoft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Ico(I.message, size: 18, color: MP.primary),
                        const Gap(8),
                        Text('Reply', style: tx(15, w: w600, c: MP.primary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Five 16px stars, 2px apart: #003399 up to [rating], #D5DBE5 after.
class _Stars extends StatelessWidget {
  final int rating;
  const _Stars(this.rating);

  static String _star(String c) =>
      '<svg viewBox="0 0 24 24"><path d="m12 2 3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z" '
      'fill="$c" stroke="$c" stroke-width="1.5" stroke-linejoin="round"/></svg>';

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Rated $rating out of 5',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++) ...[
          if (i > 1) const Gap(2),
          Svg(_star(i <= rating ? '#003399' : '#D5DBE5'), width: 16, height: 16),
        ],
      ],
    ),
  );
}

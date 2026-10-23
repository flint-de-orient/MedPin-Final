import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Chat-Review-Detail.dc.html — "Chat review · detail".
/// Live (args {'reviewId'} and/or {'conversationId'}): the review from
/// GET /api/inbox/reviews, the thread from GET /api/conversations/:id/messages
/// (AI turn meta: flagged, urgency, citations, latency); reply
/// POST /api/conversations/:id/messages; POST /api/inbox/reviews/:id/reviewed.
class ChatReviewDetailScreen extends StatefulWidget {
  const ChatReviewDetailScreen({super.key});

  @override
  State<ChatReviewDetailScreen> createState() => _ChatReviewDetailScreenState();
}

const _audit = ['Urgency: Medium', 'Model-driven', 'No scripted fallback', '2 citations', '1.4 s'];
const _citations = ['ADA Standards of Care 2026 §9', 'Clinic knowledge base: “Metformin timing”'];

class _ChatReviewDetailScreenState extends State<ChatReviewDetailScreen> with LiveData {
  // The patient's new messages and MedPin AI's next answer appear here too (the reply
  // being typed is kept: it lives in its own field).
  @override
  Duration? get refreshEvery => const Duration(seconds: 15);

  bool _readSent = false;

  final _reply = TextEditingController();
  final _pinnedKey = GlobalKey();
  final _endKey = GlobalKey();
  final _busy = ValueNotifier(false);

  /// Replies sent from this screen: (time, text).
  final _sent = <(String, String)>[];

  /// Live: which review / conversation this is.
  bool _argsRead = false;
  String? _reviewId;
  String? _conversationId;

  @override
  void dispose() {
    _reply.dispose();
    _busy.dispose();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    if (!_argsRead) {
      final a = await d1Args(this);
      _argsRead = true;
      _reviewId = a['reviewId'] as String?;
      _conversationId = a['conversationId'] as String?;
    }
    final reviews = ((await Api.I.get('/api/inbox/reviews', query: {'status': 'all'})) as Map).cast<String, dynamic>();
    Map<String, dynamic>? review;
    for (final r in reviews.list('items')) {
      if (_reviewId != null ? r.str('id') == _reviewId : r.str('conversationId') == _conversationId) {
        // Prefer the one still waiting for review.
        if (review == null || (review['status'] != 'needs_review' && r['status'] == 'needs_review')) review = r;
      }
    }
    _reviewId ??= review?.str('id');
    final cid = _conversationId ?? review?.str('conversationId');
    if (cid == null || cid.isEmpty) throw const ApiException(404, 'NOT_FOUND', 'Choose a conversation first');
    _conversationId = cid;
    final thread = ((await Api.I.get('/api/conversations/$cid/messages')) as Map).cast<String, dynamic>();
    // Opening the review reads the chat (its unread and bell notice clear).
    if (!_readSent) {
      _readSent = true;
      Api.I.post('/api/conversations/$cid/read', const {'pauseAi': false}).catchError((_) => null);
    }
    final pid = thread.obj('conversation').obj('patient').str('id');
    Object? patient;
    if (pid.isNotEmpty) {
      try {
        patient = await Api.I.get('/api/patients/$pid');
      } on ApiException {
        patient = null;
      }
    }
    return {'review': review, 'thread': thread, 'patient': patient};
  }

  Map<String, dynamic> get _thread => data!.obj('thread');
  Map<String, dynamic> get _review => data!.obj('review');
  String get _me => isLive ? F.doctorShort(Session.I.name) : 'Dr. Sen';

  String _who(Map<String, dynamic> m) {
    switch (m.str('senderType')) {
      case 'patient':
        return 'Patient';
      case 'ai':
        return 'AI assistant';
      case 'system':
        return 'MedPin';
    }
    final name = m['senderId'] is Map ? m.obj('senderId').str('name') : '';
    if (m['mine'] == true) return name.isEmpty ? _me : F.doctorShort(name);
    return name.isEmpty ? 'Care team' : d10Person(name);
  }

  static String _textOf(Map<String, dynamic> m) {
    if (m['deleted'] == true) return 'This message was deleted';
    final t = m.str('text').trim();
    if (t.isNotEmpty) return t;
    return switch (m.str('kind')) {
      'voice' => 'Voice message',
      'attachment' => m.obj('attachment').str('name', 'Attachment'),
      'record' => 'Shared a record',
      'prescription' => 'Prescription',
      _ => '',
    };
  }

  /// "Urgency: High", "Model-driven", "No scripted fallback", "2 citations", "1.2 s".
  static List<String> _auditOf(Map<String, dynamic> ai) {
    final n = ai.list('citations').length;
    final ms = ai['latencyMs'];
    return [
      if (ai.str('urgency').isNotEmpty) 'Urgency: ${d10Cap(ai.str('urgency'))}',
      ai.str('responseSource') == 'scripted' ? 'Scripted answer' : 'Model-driven',
      ai['fallbackUsed'] == true ? 'Scripted fallback used' : 'No scripted fallback',
      n == 0 ? 'No citations' : (n == 1 ? '1 citation' : '$n citations'),
      if (ms is num) '${(ms / 1000).toStringAsFixed(1)} s',
    ];
  }

  Future<void> _sendLive(String text) async {
    final cid = _conversationId;
    if (cid == null) return;
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$cid/messages', {'text': text}), busy: _busy);
    if (ok == null || !mounted) return;
    _reply.clear();
    await reload(quiet: true);
    _scrollToEnd();
  }

  Future<void> _markReviewed() async {
    if (!isLive) {
      toast(context, 'Marked as reviewed');
      Nav.back(context);
      return;
    }
    final id = _reviewId;
    if (id == null || id.isEmpty) {
      toast(context, 'This conversation has no flagged answer');
      return;
    }
    final ok = await runAction(context, () => Api.I.post('/api/inbox/reviews/$id/reviewed'), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Marked as reviewed');
    Nav.back(context);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _endKey.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(
          c,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _send() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    if (isLive) {
      _sendLive(text);
      return;
    }
    setState(() => _sent.add((TimeOfDay.now().format(context), text)));
    _reply.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _endKey.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(
          c,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _jumpToPinned() {
    final c = _pinnedKey.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data != null) return _live(context);
    final placeholder = livePlaceholder();
    if (placeholder != null) {
      return MpPage(header: const MpHeader('Chat review'), body: placeholder, bottom: _bottomBar());
    }
    return MpPage(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const _Header(), _PinnedBar(onTap: _jumpToPinned)],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        gap: 16,
        children: [
          const D10Caps('Sat, 12 Sep', align: TextAlign.center),
          _Bubble(
            key: _pinnedKey,
            who: 'Dr. Sen',
            time: '7:10 PM',
            kind: _Kind.doctor,
            text:
                'Start Metformin 500 mg, one tablet after breakfast and one after dinner. Check fasting sugar twice a week.',
          ),
          const D10Caps('Today', align: TextAlign.center),
          const _Bubble(
            who: 'Patient',
            time: '9:41 AM',
            kind: _Kind.patient,
            text: 'Can I take my Metformin at night instead? I keep missing the morning dose in the office rush.',
          ),
          const _FlaggedTurn(),
          const _Bubble(
            who: 'Patient',
            time: '9:44 AM',
            kind: _Kind.patient,
            text: 'Okay, so 2 tablets with dinner from today?',
          ),
          const _Bubble(
            who: 'AI assistant',
            time: '9:44 AM',
            kind: _Kind.ai,
            text:
                "I've asked Dr. Sen to confirm before you change anything. Until then, please keep your current timing.",
          ),
          for (final m in _sent) _Bubble(who: 'Dr. Sen', time: m.$1, kind: _Kind.doctor, text: m.$2),
          Row(
            key: _endKey,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Ico(I.sparkle, size: 14, color: MP.ink3),
              const Gap(6),
              Flexible(
                child: Text(
                  "AI assistant paused while you're in this thread",
                  textAlign: TextAlign.center,
                  style: tx(13, c: MP.ink3, h: 18 / 13),
                ),
              ),
            ],
          ),
        ],
      ),
      bottom: _bottomBar(),
    );
  }

  /// The same page from live data.
  Widget _live(BuildContext context) {
    final convo = _thread.obj('conversation');
    final review = _review;
    final name = convo.obj('patient').str('name', 'Patient');
    final reason = d10Reason(review.str('reason'));
    final subtitle = review.isEmpty
        ? 'Patient conversation'
        : (review['status'] == 'reviewed' ? 'Reviewed · $reason' : 'Flagged · $reason');
    final pinned = _thread['pinned'] is Map ? _thread.obj('pinned') : null;
    final phone = (data!['patient'] is Map ? data!.obj('patient').obj('patient').str('phone') : '');
    final children = <Widget>[];
    DateTime? lastDay;
    for (final m in _thread.list('items')) {
      final at = F.date(m['createdAt']);
      if (at != null && (lastDay == null || !F.sameDay(at, lastDay))) {
        children.add(D10Caps(d10DayCaption(at), align: TextAlign.center));
        lastDay = at;
      }
      final time = at == null ? '' : F.time(at);
      final key = pinned != null && pinned.str('id') == m.str('id') ? _pinnedKey : null;
      final ai = m.obj('ai');
      if (m['senderType'] == 'ai' && ai['flagged'] == true) {
        children.add(_FlaggedTurn(
          key: key,
          time: time,
          text: _textOf(m),
          audit: _auditOf(ai),
          citations: [for (final c in ai.list('citations')) c.str('label')].where((x) => x.isNotEmpty).toList(),
        ));
        continue;
      }
      final kind = switch (m.str('senderType')) {
        'patient' => _Kind.patient,
        'ai' || 'system' => _Kind.ai,
        _ => _Kind.doctor,
      };
      children.add(_Bubble(key: key, who: _who(m), time: time, kind: kind, text: _textOf(m)));
    }
    if (children.isEmpty) children.add(Text('No messages yet', textAlign: TextAlign.center, style: tx(14, c: MP.ink2)));
    final paused = convo['aiPaused'] == true;
    return MpPage(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(name: name, subtitle: subtitle, onCall: () => d1Call(context, phone, name)),
          if (pinned != null)
            _PinnedBar(
              onTap: _jumpToPinned,
              who: pinned['senderType'] == 'ai' ? 'AI assistant' : (pinned['senderType'] == 'patient' ? 'Patient' : _who(pinned)),
              text: _textOf(pinned),
            ),
        ],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        gap: 16,
        children: [
          ...children,
          Row(
            key: _endKey,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (paused) ...[
                const Ico(I.sparkle, size: 14, color: MP.ink3),
                const Gap(6),
                Flexible(
                  child: Text(
                    "AI assistant paused while you're in this thread",
                    textAlign: TextAlign.center,
                    style: tx(13, c: MP.ink3, h: 18 / 13),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      bottom: _bottomBar(),
    );
  }

  Widget _bottomBar() {
    return MpBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: MpInput(controller: _reply, hint: 'Reply as $_me', height: 48)),
                const Gap(8),
                Semantics(
                  button: true,
                  label: 'Send reply',
                  child: Tap(
                    onTap: _send,
                    radius: 16,
                    color: MP.primarySoft,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: Ico(I.send, size: 20, color: MP.primary)),
                    ),
                  ),
                ),
              ],
            ),
            const Gap(12),
            MpButton('Mark reviewed', icon: I.check, onTap: _markReviewed),
          ],
        ),
      );
  }
}

/// White 64px bar with a bottom border: back, name + reason, call.
class _Header extends StatelessWidget {
  final String name;
  final String subtitle;
  final VoidCallback? onCall;
  const _Header({this.name = 'Sujit Mondal', this.subtitle = 'Flagged · dosage timing', this.onCall});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(20, w: w700, h: 1.25)),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, c: MP.ink2, h: 20 / 14),
                ),
              ],
            ),
          ),
          const Gap(4),
          MpIconButton(I.phone, label: 'Call $name', onTap: onCall ?? () => toast(context, 'Calling $name…')),
        ],
      ),
    );
  }
}

/// Pinned message from Dr. Sen; tapping jumps to it in the thread.
class _PinnedBar extends StatelessWidget {
  final VoidCallback onTap;
  final String who;
  final String text;
  const _PinnedBar({
    required this.onTap,
    this.who = 'Dr. Sen',
    this.text = 'Metformin 500 mg: 1 after breakfast, 1 after dinner',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pinned message from $who, jump to it',
      excludeSemantics: true,
      child: Tap(
        onTap: onTap,
        radius: 0,
        color: MP.white,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MP.line))),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(999)),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      D10Caps('Pinned · $who'),
                      const Gap(2),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(14, h: 20 / 14),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                const Center(child: Ico(I.chevronRight, size: 18, color: MP.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Who · time" line above a bubble (13/16, who in 600 #545E72).
class _Meta extends StatelessWidget {
  final String who;
  final String time;
  const _Meta(this.who, this.time);

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [TextSpan(text: who, style: tx(13, w: w600, c: MP.ink2, h: 16 / 13)), TextSpan(text: ' · $time')],
    ),
    style: tx(13, c: MP.ink3, h: 16 / 13),
  );
}

enum _Kind { doctor, patient, ai }

/// Chat bubble: content max 290px (CSS content-box), padding 10/14, 16/1.5.
class _Bubble extends StatelessWidget {
  final String who;
  final String time;
  final String text;
  final _Kind kind;
  const _Bubble({super.key, required this.who, required this.time, required this.text, required this.kind});

  @override
  Widget build(BuildContext context) {
    final mine = kind == _Kind.doctor;
    final bordered = kind == _Kind.patient;
    final bg = switch (kind) {
      _Kind.doctor => MP.primary,
      _Kind.patient => MP.white,
      _Kind.ai => MP.fill,
    };
    const r = Radius.circular(16);
    const tail = Radius.circular(4);
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _Meta(who, time),
        const Gap(4),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 290 + 28 + (bordered ? 2 : 0)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  mine
                      ? const BorderRadius.only(topLeft: r, topRight: r, bottomRight: tail, bottomLeft: r)
                      : const BorderRadius.only(topLeft: r, topRight: r, bottomRight: r, bottomLeft: tail),
              border: bordered ? Border.all(color: MP.line) : null,
            ),
            child: UserText(text, style: tx(16, h: 1.5, c: mine ? MP.white : MP.ink)),
          ),
        ),
      ],
    );
  }
}

/// The AI answer flagged for review, with its audit trail and citations.
class _FlaggedTurn extends StatelessWidget {
  final String time;
  final String text;
  final List<String> audit;
  final List<String> citations;
  const _FlaggedTurn({
    super.key,
    this.time = '9:42 AM',
    this.text =
        "You can take Metformin with dinner instead of breakfast. Since your plan is 1-0-1, take both tablets together with dinner so you don't miss one.",
    this.audit = _audit,
    this.citations = _citations,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Meta('AI assistant', time),
        const Gap(4),
        Semantics(
          container: true,
          label: 'AI answer flagged for review',
          child: Container(
            decoration: BoxDecoration(
              color: MP.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MP.amber, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    color: MP.amberSoft,
                    child: Row(
                      children: [
                        const Ico(I.alert, size: 16, color: MP.amber),
                        const Gap(8),
                        Text('Flagged for review', style: tx(13, w: w600, c: MP.amber)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    color: MP.fill,
                    child: UserText(text, style: tx(16, h: 1.5)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          label: 'AI audit trail',
                          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final a in audit) _AuditPill(a)]),
                        ),
                        if (citations.isNotEmpty) ...[
                          const Gap(12),
                          const D10Caps('Citations'),
                          const Gap(8),
                        ],
                        for (var i = 0; i < citations.length; i++) ...[
                          if (i > 0) const Gap(8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Ico(I.book, size: 16, color: MP.ink2),
                              ),
                              const Gap(8),
                              Expanded(child: Text(citations[i], style: tx(14, h: 20 / 14))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 24px #F1F4F9 pill, 12/600 #545E72, tabular figures.
class _AuditPill extends StatelessWidget {
  final String label;
  const _AuditPill(this.label);

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text(label, style: tx(12, w: w600, c: MP.ink2, tab: true, h: 1))],
    ),
  );
}

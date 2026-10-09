import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Chat-Review-Detail.dc.html — "Chat review · detail".
class ChatReviewDetailScreen extends StatefulWidget {
  const ChatReviewDetailScreen({super.key});

  @override
  State<ChatReviewDetailScreen> createState() => _ChatReviewDetailScreenState();
}

const _audit = ['Urgency: Medium', 'Model-driven', 'No scripted fallback', '2 citations', '1.4 s'];
const _citations = ['ADA Standards of Care 2026 §9', 'Clinic knowledge base: “Metformin timing”'];

class _ChatReviewDetailScreenState extends State<ChatReviewDetailScreen> {
  final _reply = TextEditingController();
  final _pinnedKey = GlobalKey();
  final _endKey = GlobalKey();

  /// Replies sent from this screen: (time, text).
  final _sent = <(String, String)>[];

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _send() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
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
      bottom: MpBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: MpInput(controller: _reply, hint: 'Reply as Dr. Sen', height: 48)),
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
            MpButton(
              'Mark reviewed',
              icon: I.check,
              onTap: () {
                toast(context, 'Marked as reviewed');
                Nav.back(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// White 64px bar with a bottom border: back, name + reason, call.
class _Header extends StatelessWidget {
  const _Header();

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
                Text('Sujit Mondal', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(20, w: w700, h: 1.25)),
                Text(
                  'Flagged · dosage timing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, c: MP.ink2, h: 20 / 14),
                ),
              ],
            ),
          ),
          const Gap(4),
          MpIconButton(I.phone, label: 'Call Sujit Mondal', onTap: () => toast(context, 'Calling Sujit Mondal…')),
        ],
      ),
    );
  }
}

/// Pinned message from Dr. Sen; tapping jumps to it in the thread.
class _PinnedBar extends StatelessWidget {
  final VoidCallback onTap;
  const _PinnedBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pinned message from Dr. Sen, jump to it',
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
                      const D10Caps('Pinned · Dr. Sen'),
                      const Gap(2),
                      Text(
                        'Metformin 500 mg: 1 after breakfast, 1 after dinner',
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
            child: Text(text, style: tx(16, h: 1.5, c: mine ? MP.white : MP.ink)),
          ),
        ),
      ],
    );
  }
}

/// The AI answer flagged for review, with its audit trail and citations.
class _FlaggedTurn extends StatelessWidget {
  const _FlaggedTurn();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Meta('AI assistant', '9:42 AM'),
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
                    child: Text(
                      "You can take Metformin with dinner instead of breakfast. Since your plan is 1-0-1, take both tablets together with dinner so you don't miss one.",
                      style: tx(16, h: 1.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          label: 'AI audit trail',
                          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final a in _audit) _AuditPill(a)]),
                        ),
                        const Gap(12),
                        const D10Caps('Citations'),
                        const Gap(8),
                        for (var i = 0; i < _citations.length; i++) ...[
                          if (i > 0) const Gap(8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Ico(I.book, size: 16, color: MP.ink2),
                              ),
                              const Gap(8),
                              Expanded(child: Text(_citations[i], style: tx(14, h: 20 / 14))),
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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Patient-Chat.dc.html — "Patient · urgent chat with doctor".
class PatientChatScreen extends StatefulWidget {
  const PatientChatScreen({super.key});

  @override
  State<PatientChatScreen> createState() => _PatientChatScreenState();
}

typedef _Message = ({String text, bool mine, String meta});

class _PatientChatScreenState extends State<PatientChatScreen> {
  static const _replies = ["I'm on my way", 'Share my vitals'];

  final List<_Message> _messages = [
    (
      text: "My chest feels tight since morning and I'm sweating a little. Should I come in now?",
      mine: true,
      meta: '9:12 AM · Delivered',
    ),
    (
      text: "Priya, please come to the clinic now. I'm informing the front desk. If the pain gets worse on the way, call 108.",
      mine: false,
      meta: 'Dr. Sen · 9:14 AM',
    ),
  ];
  final _input = TextEditingController();
  bool _showReplies = true;
  bool _hasText = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _messages.add((text: t, mine: true, meta: 'Just now · Sent'));
      _showReplies = false;
      _input.clear();
      _hasText = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      scroll: false,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [_header(context), _banner(context)],
      ),
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            // Messages sit at the bottom of the thread (justify-content: flex-end).
            constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - 32)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _thread(),
            ),
          ),
        ),
      ),
      bottom: _composer(context),
    );
  }

  /// White 68px bar (+1px rule): back, avatar, name and status.
  Widget _header(BuildContext context) {
    return Container(
      height: 69,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: const BoxDecoration(
        color: MP.white,
        border: Border(bottom: BorderSide(color: MP.line)),
      ),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Nav.go(context, 'Patient-DoctorDetail'),
              child: Row(
                children: [
                  const MpAvatar('AS', size: 40, fontSize: 14),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dr. Arjun Sen', style: tx(17, w: w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('Available now', style: tx(13, w: w600, c: MP.green)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Red status strip: "Urgent chat. Dr. Sen has been alerted." + Call 108.
  Widget _banner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: MP.redSoft,
        border: Border(bottom: BorderSide(color: MP.redLine)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const Ico(I.alert, size: 18, color: MP.red),
            const Gap(10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: tx(14, h: 1.4),
                  children: [
                    TextSpan(text: 'Urgent chat.', style: tx(14, w: w700, h: 1.4, c: MP.red)),
                    const TextSpan(text: ' Dr. Sen has been alerted.'),
                  ],
                ),
              ),
            ),
            const Gap(10),
            Semantics(
              link: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => toast(context, 'Calling 108…'),
                child: Text('Call 108', style: tx(14, w: w700, h: 1.4, c: MP.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _thread() {
    final meta = tx(12, c: MP.ink3);
    final items = <Widget>[
      Center(child: Text('Today', style: tx(12, w: w600, c: MP.ink3))),
      for (final m in _messages) ...[
        if (m.mine) _outgoing(m.text) else _incoming(m.text),
        if (m.mine) Align(alignment: Alignment.centerRight, child: Text(m.meta, style: meta)) else Text(m.meta, style: meta),
      ],
      if (_showReplies)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final r in _replies) P1Pill(r, onTap: () => _send(r))],
          ),
        ),
    ];
    return [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const Gap(10), items[i]],
    ];
  }

  /// Patient bubble: max 270px text, #003399, radius 16 16 4 16.
  Widget _outgoing(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 298),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: MP.primary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
            ),
          ),
          child: Text(text, style: tx(15, h: 1.45, c: MP.white)),
        ),
      ),
    );
  }

  /// Doctor bubble: max 280px text, white, 1px #E5E9F0, radius 16 16 16 4.
  Widget _incoming(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: MP.white,
            border: Border.all(color: MP.line),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Text(text, style: tx(15, h: 1.45)),
        ),
      ),
    );
  }

  /// White composer: attach, 48px pill input, round mic (send once typing).
  Widget _composer(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MP.white,
        border: Border(top: BorderSide(color: MP.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              MpIconButton(
                I.paperclip,
                label: 'Attach a photo or report',
                color: MP.ink2,
                onTap: () => toast(context, 'Attachments are coming soon'),
              ),
              const Gap(8),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: MP.bg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MP.lineStrong),
                  ),
                  child: Semantics(
                    label: 'Message',
                    child: TextField(
                      controller: _input,
                      style: tx(16),
                      cursorColor: MP.primary,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      onChanged: (v) {
                        final has = v.trim().isNotEmpty;
                        if (has != _hasText) setState(() => _hasText = has);
                      },
                      decoration: InputDecoration.collapsed(
                        hintText: 'Type a message',
                        hintStyle: tx(16, c: P1.placeholder),
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Semantics(
                button: true,
                label: _hasText ? 'Send' : 'Record a voice message',
                child: Tap(
                  onTap: () => _hasText ? _send(_input.text) : toast(context, 'Voice messages are coming soon'),
                  radius: 999,
                  color: MP.primary,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: Ico(_hasText ? I.send : I.mic, size: 22, color: MP.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Patient-DoctorChat.dc.html — "Patient · chat with doctor".
class PatientDoctorchatScreen extends StatefulWidget {
  const PatientDoctorchatScreen({super.key});

  @override
  State<PatientDoctorchatScreen> createState() => _PatientDoctorchatScreenState();
}

const _replies = ['Thank you', "Share today's sugar", 'Running late'];

const _r16 = Radius.circular(16);
const _r4 = Radius.circular(4);

/// Doctor bubbles: 16 16 16 4; patient bubbles: 16 16 4 16.
const _theirs = BorderRadius.only(topLeft: _r16, topRight: _r16, bottomRight: _r16, bottomLeft: _r4);
const _mine = BorderRadius.only(topLeft: _r16, topRight: _r16, bottomRight: _r4, bottomLeft: _r16);

class _PatientDoctorchatScreenState extends State<PatientDoctorchatScreen> {
  final _text = TextEditingController();
  final _sent = <String>[];
  bool _showReplies = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send(String message) {
    final m = message.trim();
    if (m.isEmpty) return;
    setState(() {
      _sent.add(m);
      _showReplies = false;
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    void detail() => Nav.go(context, 'Patient-DoctorDetail');
    final typing = _text.text.trim().isNotEmpty;

    final items = <Widget>[
      _day('Yesterday', const EdgeInsets.only(bottom: 4)),
      Align(
        alignment: Alignment.centerLeft,
        child: _Attachment(
          mine: false,
          icon: I.fileText,
          title: 'Prescription · 29 Sep',
          sub: '3 medicines · 2 tests',
          text: 'Please get the HbA1c test done and share it here before your visit.',
          onTap: () => Nav.go(context, 'Patient-Records'),
        ),
      ),
      _meta('Dr. Sen · 6:40 PM'),
      _day('Today', const EdgeInsets.symmetric(vertical: 4)),
      Align(
        alignment: Alignment.centerRight,
        child: _Attachment(
          mine: true,
          icon: I.flask,
          title: 'HbA1c · 7.4%',
          sub: 'Shared report · 30 Sep',
          text: "Here's the report, doctor.",
          onTap: () => Nav.go(context, 'Patient-Records'),
        ),
      ),
      _meta('8:50 AM · Seen', right: true),
      const Align(
        alignment: Alignment.centerLeft,
        child: _Bubble("Got your HbA1c report, thanks. We'll adjust the dose when you come in at 5.", mine: false),
      ),
      _meta('Dr. Sen · 9:14 AM'),
      for (final m in _sent) ...[
        Align(alignment: Alignment.centerRight, child: _Bubble(m, mine: true)),
        _meta('Just now · Sent', right: true),
      ],
      if (_showReplies)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _replies)
                P2Box(
                  onTap: () => _send(r),
                  height: 40,
                  radius: 999,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: MP.white,
                  border: MP.lineStrong,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Text(r, style: tx(14, w: w600))]),
                ),
            ],
          ),
        ),
    ];

    return MpPage(
        scroll: false,
        header: _header(detail),
        bottom: MpBottomBar(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
          child: Row(
            children: [
              P2Box(
                onTap: () => Nav.go(context, 'Records-Add'),
                label: 'Share a report, prescription or photo',
                width: 44,
                height: 44,
                radius: 12,
                color: MP.primarySoft,
                alignment: Alignment.center,
                child: const Ico(I.plus, size: 22, color: MP.primary, stroke: 2),
              ),
              const Gap(8),
              Expanded(
                child: P2Field(
                  controller: _text,
                  hint: 'Message Dr. Sen',
                  height: 48,
                  radius: 999,
                  fill: MP.bg,
                  action: TextInputAction.send,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _send,
                ),
              ),
              const Gap(8),
              P2Box(
                onTap: typing ? () => _send(_text.text) : () => p2Missing(context, 'Voice recording'),
                label: typing ? 'Send' : 'Record a voice message',
                width: 48,
                height: 48,
                radius: 999,
                color: MP.primary,
                alignment: Alignment.center,
                child: Ico(typing ? I.send : I.mic, size: 22, color: MP.white),
              ),
            ],
          ),
        ),
        // Messages sit at the bottom (justify-content: flex-end) and scroll up.
        body: LayoutBuilder(
          builder:
              (context, c) => SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0.0, c.maxHeight - 24)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[if (i > 0) const Gap(8), items[i]],
                    ],
                  ),
                ),
              ),
        ),
      );
  }

  Widget _header(VoidCallback detail) {
    return Container(
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 68,
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                const Gap(8),
                const MpAvatar('AS', size: 40, fontSize: 14),
                const Gap(8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: detail,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dr. Arjun Sen', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(17, w: w700)),
                        Text('Available now', style: tx(13, w: w600, c: MP.green)),
                      ],
                    ),
                  ),
                ),
                const Gap(8),
                MpIconButton(I.search, label: 'Search this chat', onTap: () => p2Missing(context, 'Chat search')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: P2Box(
              onTap: detail,
              height: 40,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: MP.primarySoft,
              child: Row(
                children: [
                  const Ico(I.calendar, size: 16, color: MP.primary),
                  const Gap(8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: tx(13),
                        children: [
                          TextSpan(text: 'Visit today, 5:00 PM', style: tx(13, w: w700)),
                          const TextSpan(text: ' · Token 04'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(8),
                  Text('Details', style: tx(13, w: w700, c: MP.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _day(String label, EdgeInsets padding) =>
      Center(child: Padding(padding: padding, child: Text(label, style: tx(12, w: w600, c: MP.ink3))));

  Widget _meta(String text, {bool right = false}) => Align(
    alignment: right ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(text, style: tx(12, c: MP.ink3)),
  );
}

/// Report / prescription card bubble (doctor: white 260px + border; patient: blue 250px).
class _Attachment extends StatelessWidget {
  final bool mine;
  final String icon;
  final String title;
  final String sub;
  final String text;
  final VoidCallback onTap;
  const _Attachment({
    required this.mine,
    required this.icon,
    required this.title,
    required this.sub,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = mine ? MP.white : MP.ink;
    return P2Box(
      onTap: onTap,
      label: title,
      width: mine ? 250 : 262, // doctor's: 260px + 1px border (content-box)
      borderRadius: mine ? _mine : _theirs,
      color: mine ? MP.primary : MP.white,
      border: mine ? null : MP.line,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: mine ? MP.white.withValues(alpha: 0.16) : MP.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mine ? MP.white.withValues(alpha: 0.16) : MP.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Ico(icon, size: 18, color: mine ? MP.white : MP.primary),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tx(14, w: w700, c: fg)),
                      const Gap(1),
                      Text(sub, style: tx(12, c: mine ? MP.white.withValues(alpha: 0.8) : MP.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(text, style: tx(14, h: 1.45, c: fg)),
          ),
        ],
      ),
    );
  }
}

/// Plain text bubble: max-width 280 + padding 12/14 (+1px border on the doctor's).
class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  const _Bubble(this.text, {required this.mine});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: mine ? 308 : 310),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: mine ? MP.primary : MP.white,
        borderRadius: mine ? _mine : _theirs,
        border: mine ? null : Border.all(color: MP.line),
      ),
      child: Text(text, style: tx(15, h: 1.45, c: mine ? MP.white : MP.ink)),
    ),
  );
}

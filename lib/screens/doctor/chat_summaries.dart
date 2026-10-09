import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Chat-Summaries.dc.html — "Chat summaries".
class ChatSummariesScreen extends StatefulWidget {
  const ChatSummariesScreen({super.key});

  @override
  State<ChatSummariesScreen> createState() => _ChatSummariesScreenState();
}

/// (initials, name, meta, needsReply, flag ('' = none), summary)
typedef _Item = (String, String, String, bool, String, String);

const List<_Item> _items = [
  (
    'SM',
    'Sujit Mondal',
    '3 messages · last 9:44 AM',
    true,
    'Flagged: dosage timing',
    'Wants Metformin at night. AI said take both doses at dinner; flagged.',
  ),
  (
    'RD',
    'Rahul Das',
    '5 messages · last 8:52 AM',
    true,
    'Flagged: BP with headache',
    'Home BP 172/104 with headache. AI advised a same-day visit; wants a slot.',
  ),
  (
    'FI',
    'Farhana Islam',
    '2 messages · last 11:05 AM',
    true,
    '',
    'Asked if iron tablets can be taken with tea. Wants her dose confirmed.',
  ),
  (
    'AK',
    'Aisha Khan',
    '4 messages · last 10:30 AM',
    false,
    '',
    'Shared TSH report, asked when to repeat. AI answered from clinic guidance.',
  ),
  (
    'MR',
    'Moumita Roy',
    '2 messages · last 7:50 AM',
    false,
    '',
    'Logged BP 128/84, asked about walking after meals. AI answered; no action.',
  ),
];

class _ChatSummariesScreenState extends State<ChatSummariesScreen> {
  int _scope = 0;
  int _day = 0;

  @override
  Widget build(BuildContext context) {
    final bold = tx(16, w: w600, h: 1.5);
    return MpPage(
      header: const MpHeader("Today's conversations"),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          MpSegmented(
            options: const ['My patients', 'Whole practice'],
            index: _scope,
            onChanged: (i) => setState(() => _scope = i),
          ),
          Row(
            children: [
              D10FilterChip('Today', selected: _day == 0, onTap: () => setState(() => _day = 0)),
              const Gap(8),
              D10FilterChip('Yesterday', selected: _day == 1, onTap: () => setState(() => _day = 1)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '9', style: tx(16, w: w600, h: 1.5, tab: true)),
                    const TextSpan(text: ' patients wrote today · '),
                    TextSpan(text: '3', style: tx(16, w: w600, h: 1.5, tab: true)),
                    const TextSpan(text: ' need a reply'),
                  ],
                ),
                style: bold,
              ),
              const Gap(4),
              Row(
                children: [
                  const Ico(I.sparkle, size: 16, color: MP.ink2),
                  const Gap(6),
                  Expanded(child: Text('Summaries written by the AI assistant', style: tx(14, c: MP.ink2, h: 20 / 14))),
                ],
              ),
            ],
          ),
          for (final c in _items) _SummaryCard(c),
          MpButton(
            'Show 4 more patients',
            kind: MpBtn.ghost,
            height: 48,
            radius: 12,
            fontSize: 15,
            onTap: () => Nav.go(context, 'Doctor-Messages'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _Item c;
  const _SummaryCard(this.c);

  @override
  Widget build(BuildContext context) {
    final flagged = c.$5.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MpAvatar(c.$1, size: 40, fontSize: 14),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600, h: 22 / 16)),
                    Text(c.$3, style: tx(13, c: MP.ink3, h: 18 / 13, tab: true)),
                  ],
                ),
              ),
              if (c.$4) ...[const Gap(12), const MpBadge.blue('Needs reply', weight: w600)],
            ],
          ),
          const Gap(12),
          Text(c.$6, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(16, h: 1.5)),
          if (flagged) ...[const Gap(12), Align(alignment: Alignment.centerLeft, child: _FlagPill(c.$5))],
          const Gap(12),
          Tap(
            // Flagged chats open their AI review; others the patient thread.
            onTap: () => Nav.go(context, flagged ? 'Chat-Review-Detail' : 'Patient-Thread'),
            radius: 0,
            child: Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(child: Text('Open conversation', style: tx(15, w: w600, c: MP.primary))),
                    const Ico(I.chevronRight, size: 18, color: MP.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber 24px pill with a 14px alert icon (stroke 2), 6px gap, 12/600.
class _FlagPill extends StatelessWidget {
  final String text;
  const _FlagPill(this.text);

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Ico(I.alert, size: 14, color: MP.amber, stroke: 2),
        const Gap(6),
        Text(text, style: tx(12, w: w600, c: MP.amber, h: 1)),
      ],
    ),
  );
}

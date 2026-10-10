import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Chat-Summaries.dc.html — "Chat summaries".
/// Live data: GET /api/inbox/summaries?date=today|yesterday[&scope=mine].
/// Flagged rows open Chat-Review-Detail, others Patient-Thread
/// ({'conversationId', 'patientId'}).
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

class _ChatSummariesScreenState extends State<ChatSummariesScreen> with LiveData {
  int _scope = 0;
  int _day = 0;

  @override
  Future<Object?> fetch() => Api.I.get('/api/inbox/summaries', query: {
    'date': _day == 1 ? 'yesterday' : 'today',
    if (_scope == 0) 'scope': 'mine',
  });

  void _setScope(int i) {
    if (i == _scope) return;
    setState(() => _scope = i);
    if (isLive) reload(quiet: true);
  }

  void _setDay(int i) {
    if (i == _day) return;
    setState(() => _day = i);
    if (isLive) reload(quiet: true);
  }

  static _Item _itemOf(Map<String, dynamic> m) {
    final name = m.obj('patientId').str('name', 'Patient');
    final n = m.numOr('messageCount').toInt();
    final last = F.date(m['lastMessageAt']);
    return (
      F.initials(name),
      name,
      [d1Count(n, 'message'), if (last != null) 'last ${F.time(last)}'].join(' · '),
      m['needsReply'] == true,
      m.str('flagLabel'),
      m.str('summary'),
    );
  }

  Future<void> _open(Map<String, dynamic> m, bool flagged) async {
    final args = {'conversationId': m.str('conversationId'), 'patientId': m.obj('patientId').str('id')};
    await Nav.go(context, flagged ? 'Chat-Review-Detail' : 'Patient-Thread', args: args);
    if (mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final bold = tx(16, w: w600, h: 1.5);
    final placeholder = livePlaceholder();
    final d = data;
    final live = d == null ? null : [for (final m in d.list('items')) (m, _itemOf(m))];
    final wrote = d == null ? '9' : '${d.numOr('patientsWrote')}';
    final need = d == null ? '3' : '${d.numOr('needReply')}';
    final dayWord = _day == 1 ? 'yesterday' : 'today';
    return MpPage(
      header: const MpHeader("Today's conversations"),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          MpSegmented(
            options: const ['My patients', 'Whole practice'],
            index: _scope,
            onChanged: _setScope,
          ),
          Row(
            children: [
              D10FilterChip('Today', selected: _day == 0, onTap: () => _setDay(0)),
              const Gap(8),
              D10FilterChip('Yesterday', selected: _day == 1, onTap: () => _setDay(1)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: wrote, style: tx(16, w: w600, h: 1.5, tab: true)),
                    TextSpan(text: wrote == '1' ? ' patient wrote $dayWord · ' : ' patients wrote $dayWord · '),
                    TextSpan(text: need, style: tx(16, w: w600, h: 1.5, tab: true)),
                    TextSpan(text: need == '1' ? ' needs a reply' : ' need a reply'),
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
          if (live == null) ...[
            for (final c in _items) _SummaryCard(c),
            MpButton(
              'Show 4 more patients',
              kind: MpBtn.ghost,
              height: 48,
              radius: 12,
              fontSize: 15,
              onTap: () => Nav.go(context, 'Doctor-Messages'),
            ),
          ] else ...[
            if (live.isEmpty) Text('No conversations $dayWord', style: tx(14, c: MP.ink2)),
            for (final (m, c) in live) _SummaryCard(c, onOpen: () => _open(m, c.$5.isNotEmpty)),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _Item c;
  final VoidCallback? onOpen;
  const _SummaryCard(this.c, {this.onOpen});

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
            onTap: onOpen ?? () => Nav.go(context, flagged ? 'Chat-Review-Detail' : 'Patient-Thread'),
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

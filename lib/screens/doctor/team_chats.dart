import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Chats with colleagues at this clinic (GET /api/inbox?type=direct), for the
/// front desk, assistants and the dietician — the "Team" tab of their chat
/// lists, so a doctor's "Please call Mrs Sharma" can be read and answered.
/// "Message a colleague" starts one.
class TeamChats extends StatefulWidget {
  final String query;
  const TeamChats({super.key, this.query = ''});

  @override
  State<TeamChats> createState() => _TeamChatsState();
}

class _TeamChatsState extends State<TeamChats> with LiveData {
  @override
  Future<Object?> fetch() => Api.I.get('/api/inbox', query: {'type': 'direct'});

  @override
  Duration? get refreshEvery => const Duration(seconds: 30);

  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    if (F.sameDay(at, now)) return F.time(at);
    if (F.sameDay(at, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return F.dayMonth(at);
  }

  Future<void> _open(String id) async {
    await Nav.go(context, 'Patient-Thread', args: {'conversationId': id});
    if (mounted) reload(quiet: true);
  }

  Future<void> _new() async {
    await Nav.go(context, 'Doctor-Messages-New');
    if (mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (placeholder != null) return placeholder;
    final q = widget.query.trim().toLowerCase();
    final me = '${Session.I.user['id']}';
    final rows = [
      for (final c in data?.list('items') ?? const <Map<String, dynamic>>[])
        if (q.isEmpty || '${c.obj('other').str('name')} ${c.obj('lastMessage').str('text')}'.toLowerCase().contains(q)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(q.isEmpty ? 'No chats with colleagues yet' : 'No chats match your search', textAlign: TextAlign.center, style: tx(14, c: MP.ink3)),
          )
        else
          D10ListCard(
            children: [
              for (var i = 0; i < rows.length; i++)
                () {
                  final c = rows[i];
                  final o = c.obj('other');
                  final m = c.obj('lastMessage');
                  final unread = c.numOr('unread').toInt();
                  final mine = '${m['senderId'] ?? ''}' == me;
                  final name = o.str('name', 'Colleague');
                  return Semantics(
                    button: true,
                    label: '$name${unread > 0 ? ', $unread unread' : ''}',
                    excludeSemantics: true,
                    child: D10ListRow(
                      divider: i > 0,
                      vPad: 14,
                      onTap: () => _open(c.str('id')),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MpAvatar(F.initials(name), photo: o.str('photo').isEmpty ? null : o.str('photo'), size: 48, fontSize: 16, weight: w600),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600))),
                                  const Gap(8),
                                  Text(_when(F.date(m['at'])), style: tx(13, w: unread > 0 ? w600 : w400, c: unread > 0 ? MP.primary : MP.ink3)),
                                ]),
                                if (o.str('roleLabel').isNotEmpty) Text(o.str('roleLabel'), style: tx(13, c: MP.ink3)),
                                const Gap(2),
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      '${mine ? 'You: ' : ''}${m.str('text')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tx(14, c: unread > 0 ? MP.ink : MP.ink2, w: unread > 0 ? w600 : w400),
                                    ),
                                  ),
                                  if (unread > 0) ...[const Gap(8), MpBadge.blue('$unread')],
                                ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
            ],
          ),
        const Gap(12),
        MpButton('Message a colleague', kind: MpBtn.secondary, onTap: _new),
      ],
    );
  }
}

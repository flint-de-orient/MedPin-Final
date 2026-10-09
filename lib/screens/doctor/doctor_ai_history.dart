import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Doctor · AI Assistant history — every past conversation, grouped Today /
/// Yesterday / Earlier, with search. Tap to continue a conversation (opens
/// Doctor-AI-Chat with {'sessionId'}); long-press to delete.
/// Live data: GET /api/ai/sessions, DELETE /api/ai/sessions/:id.
class DoctorAiHistoryScreen extends StatefulWidget {
  const DoctorAiHistoryScreen({super.key});

  @override
  State<DoctorAiHistoryScreen> createState() => _DoctorAiHistoryScreenState();
}

class _DoctorAiHistoryScreenState extends State<DoctorAiHistoryScreen> with LiveData {
  static final _sample = [
    {'id': 's1', 'title': "Compare a patient's reports with their last visit", 'patientId': {'name': 'Priya Sharma'}, 'lastAt': null, 'group': 'Today', 'when': '8:42 AM'},
    {'id': 's2', 'title': 'Which patients have abnormal kidney results this month', 'group': 'Yesterday', 'when': '6:10 PM'},
    {'id': 's3', 'title': 'Summarise follow-ups due this week', 'group': 'Earlier', 'when': '28 Sep'},
  ];

  final _q = TextEditingController();

  @override
  Future<Object?> fetch() => Api.I.get('/api/ai/sessions');

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _sessions {
    if (data == null) return [for (final s in _sample) Map<String, dynamic>.from(s)];
    final now = DateTime.now();
    return [
      for (final s in data!.list('items'))
        () {
          final at = F.date(s['lastAt']) ?? F.date(s['createdAt']);
          final group = at == null
              ? 'Earlier'
              : F.sameDay(at, now)
              ? 'Today'
              : F.sameDay(at, now.subtract(const Duration(days: 1)))
              ? 'Yesterday'
              : 'Earlier';
          return {
            ...s,
            'group': group,
            'when': at == null ? '' : (group == 'Earlier' ? F.dayMonth(at) : F.time(at)),
          };
        }(),
    ];
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final yes = await d4Confirm(context, title: 'Delete this conversation?', body: s.str('title', 'Conversation'), confirm: 'Delete');
    if (!yes || !mounted) return;
    if (!isLive) {
      toast(context, 'Conversation deleted');
      return;
    }
    final ok = await runAction(context, () => Api.I.delete('/api/ai/sessions/${s['id']}'));
    if (ok == null || !mounted) return;
    toast(context, 'Conversation deleted');
    reload(quiet: true);
  }

  Future<void> _open(Map<String, dynamic> s) async {
    await Nav.go(context, 'Doctor-AI-Chat', args: {'sessionId': s['id']});
    if (mounted && isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final q = _q.text.trim().toLowerCase();
    final all = _sessions;
    final rows = q.isEmpty
        ? all
        : all.where((s) => s.str('title').toLowerCase().contains(q) || s.obj('patientId').str('name').toLowerCase().contains(q)).toList();
    return MpPage(
      header: D4Header('Conversations', subtitle: data == null ? '3 with MedPin AI' : '${all.length} with MedPin AI'),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 12,
            children: [
              MpInput(controller: _q, hint: 'Search conversations', leadingIcon: I.search, height: 48),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    q.isEmpty ? 'No conversations yet. Ask MedPin AI anything from the AI Assistant.' : 'No conversations match "${_q.text.trim()}"',
                    textAlign: TextAlign.center,
                    style: tx(14, c: MP.ink2, h: 1.5),
                  ),
                ),
              for (final group in ['Today', 'Yesterday', 'Earlier'])
                if (rows.any((s) => s['group'] == group)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(group.toUpperCase(), style: tx(13, w: w700, c: MP.ink3, em: 0.06)),
                  ),
                  for (final s in rows.where((s) => s['group'] == group))
                    GestureDetector(
                      onLongPress: () => _delete(s),
                      child: Tap(
                        onTap: () => _open(s),
                        radius: 16,
                        color: MP.white,
                        border: MP.line,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.str('title', 'New conversation'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [if (s.obj('patientId').str('name').isNotEmpty) s.obj('patientId').str('name'), s.str('when')].where((x) => x.isNotEmpty).join(' · '),
                                    style: tx(13, c: MP.ink3),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
                          ],
                        ),
                      ),
                    ),
                ],
              if (rows.isNotEmpty) const D4Note('Press and hold a conversation to delete it.'),
            ],
          ),
    );
  }
}

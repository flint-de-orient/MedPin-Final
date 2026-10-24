import '../../data/format.dart';
import '../../widgets/chat_extras.dart';
import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';

/// The clinic's reply templates for patient chats ("Clinic timings", "Report received"):
/// tap one to put it in the reply box; save the typed reply as a new one; long-press to remove.
/// Pops the chosen text. GET / PUT /api/practice/templates.
Future<String?> pickReplyTemplate(BuildContext context, {String current = ''}) => openSheet<String>(context, (_) => _TemplatesSheet(current: current));

class _TemplatesSheet extends StatefulWidget {
  final String current;
  const _TemplatesSheet({required this.current});

  @override
  State<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends State<_TemplatesSheet> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = (await Api.I.get('/api/practice/templates') as Map).cast<String, dynamic>();
      if (mounted) setState(() => _items = r.list('items'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _save(List<Map<String, dynamic>> items, String done) async {
    final res = await runAction(context, () => Api.I.put('/api/practice/templates', {'items': items}));
    if (res is! Map || !mounted) return;
    setState(() => _items = res.cast<String, dynamic>().list('items'));
    toast(context, done);
  }

  Future<void> _remove(Map<String, dynamic> t) async {
    final items = [for (final x in _items ?? const <Map<String, dynamic>>[]) if (x != t) x];
    await _save(items, tr(context, 'Template removed'));
  }

  Future<void> _addCurrent() async {
    final text = widget.current.trim();
    final title = text.length > 30 ? '${text.substring(0, 30)}…' : text;
    await _save([...?_items, {'title': title, 'text': text}], tr(context, 'Saved as a template'));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return MpSheet(
      title: 'Reply templates',
      subtitle: "Your clinic's ready replies. Tap one to use it; press and hold to remove it.",
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))))
          else
            for (final t in items)
              GestureDetector(
                onLongPress: () => _remove(t),
                child: Tap(
                  onTap: () => Navigator.pop(context, t.str('text')),
                  radius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.str('title'), style: tx(15, w: w600)),
                      const SizedBox(height: 2),
                      Text(t.str('text'), style: tx(13, c: MP.ink2, h: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
          if (widget.current.trim().length >= 8) ...[
            const SizedBox(height: 12),
            MpButton('Save what I typed as a template', kind: MpBtn.secondary, height: 44, onTap: _addCurrent),
          ],
        ],
      ),
    );
  }
}

/// The clinic's handling of a patient chat: "Handled" (nothing more to do; it opens again when
/// the patient writes), and who looks after it (assign to me / a colleague / nobody).
/// POST /api/conversations/:id/handled, /assign. True when something changed.
Future<bool> chatInboxActions(BuildContext context, {required String conversationId, required Map<String, dynamic> conversation, bool patientChat = true}) async {
  final handled = conversation['handledAt'] != null;
  final assigned = conversation['assignedTo'];
  final me = Session.I.user['id'] as String?;
  final pick = await openSheet<String>(
    context,
    (c) => MpSheet(
      title: 'This chat',
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (patientChat) ...[
            MpButton(handled ? 'Open again' : 'Mark as handled', onTap: () => Navigator.pop(c, handled ? 'reopen' : 'handled')),
            const SizedBox(height: 10),
            if ('${assigned ?? ''}' != me) MpButton('Take this chat', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'me')),
            if ('${assigned ?? ''}' != me) const SizedBox(height: 10),
            MpButton('Give to a colleague', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'colleague')),
            if (assigned != null) ...[
              const SizedBox(height: 10),
              MpButton('Nobody in particular', kind: MpBtn.ghost, onTap: () => Navigator.pop(c, 'none')),
            ],
            const SizedBox(height: 10),
          ],
          // Your own: notifications for this chat, and clearing it on your phones.
          MpButton(F.date(conversation['mutedUntil'])?.isAfter(DateTime.now()) == true ? 'Notifications muted · change' : 'Mute notifications', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'mute')),
          const SizedBox(height: 10),
          MpButton('Clear chat', kind: MpBtn.ghost, onTap: () => Navigator.pop(c, 'clear')),
        ],
      ),
    ),
  );
  if (pick == null || !context.mounted) return false;
  dynamic res;
  switch (pick) {
    case 'mute':
      return ChatExtras.mute(context, convId: conversationId, mutedUntil: F.date(conversation['mutedUntil']));
    case 'clear':
      return ChatExtras.clear(context, convId: conversationId);
    case 'handled' || 'reopen':
      res = await runAction(context, () => Api.I.post('/api/conversations/$conversationId/handled', {'handled': pick == 'handled'}));
      if (res != null && context.mounted) toast(context, pick == 'handled' ? tr(context, 'Marked as handled') : tr(context, 'Open again'));
    case 'me':
      res = await runAction(context, () => Api.I.post('/api/conversations/$conversationId/assign', {'userId': me}));
      if (res != null && context.mounted) toast(context, tr(context, 'This chat is yours'));
    case 'none':
      res = await runAction(context, () => Api.I.post('/api/conversations/$conversationId/assign', const {'userId': null}));
    case 'colleague':
      final team = await Api.I.get('/api/members').catchError((_) => null);
      if (!context.mounted) return false;
      final people = [
        for (final m in ((team is Map ? team['items'] : team) as List? ?? const []))
          if ((m as Map)['status'] == 'active' && '${m['userId']}' != me && const {'doctor', 'front_desk', 'doctor_assistant', 'practice_manager', 'dietician'}.contains(m['role'])) m.cast<String, dynamic>(),
      ];
      final who = await openSheet<Map<String, dynamic>>(
        context,
        (c) => MpSheet(
          title: 'Give this chat to',
          showClose: true,
          child: Column(children: [
            if (people.isEmpty) Text('Nobody else at the clinic yet', style: tx(14, c: MP.ink2)),
            for (final p in people)
              Tap(
                onTap: () => Navigator.pop(c, p),
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Row(children: [Expanded(child: UserText(p.str('name', 'Colleague'), style: tx(16, w: w600))), const Ico(I.chevronRight, size: 18, color: MP.ink3)]),
              ),
          ]),
        ),
      );
      if (who == null || !context.mounted) return false;
      res = await runAction(context, () => Api.I.post('/api/conversations/$conversationId/assign', {'userId': who.str('userId')}));
      if (res != null && context.mounted) toast(context, trf(context, 'Given to {name}', {'name': who.str('name')}));
  }
  return res != null;
}

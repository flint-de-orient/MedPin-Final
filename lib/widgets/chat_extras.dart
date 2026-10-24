import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import '../data/format.dart';
import '../data/live.dart';
import 'i18n.dart';
import 'mp.dart';

/// Chat tools shared by the clinic's thread and the patient's chat: typing, mute, clear,
/// edit, forward, search (the whole chat, on the server) and a voice message as text.
/// Server: POST …/typing, …/mute, …/clear; PATCH …/messages/:id; GET …/forward-targets;
/// POST …/messages/:id/forward; GET …/search?q=; POST …/messages/:id/transcribe.
class ChatExtras {
  ChatExtras._();

  /// A sent message can be edited for this long (the server checks it too).
  static const editWindow = Duration(minutes: 15);

  static bool canEdit(Map<String, dynamic> m) {
    if (m['mine'] != true || m['deleted'] == true || m['auto'] == true || m.str('kind', 'text') != 'text' || m.str('text').isEmpty) return false;
    final at = F.date(m['createdAt']);
    return at != null && DateTime.now().difference(at) < editWindow;
  }

  /// "Payel is typing…", "Dr. Sen is typing…", "Priya and Payel are typing…".
  static String? typingLine(BuildContext context, Object? typing) {
    final names = [for (final t in (typing as List? ?? const [])) if (t is Map && '${t['name'] ?? ''}'.isNotEmpty) '${t['name']}'];
    if (names.isEmpty) return typing is List && typing.isNotEmpty ? tr(context, 'Typing…') : null;
    if (names.length == 1) return trf(context, '{name} is typing…', {'name': names.first});
    return trf(context, '{a} and {b} are typing…', {'a': names[0], 'b': names[1]});
  }

  static Future<String?> edit(BuildContext context, {required String convId, required Map<String, dynamic> message}) async {
    final text = await openSheet<String>(context, (_) => _EditSheet(initial: message.str('text')));
    if (text == null || !context.mounted || text.trim() == message.str('text').trim()) return null;
    final ok = await runAction(context, () => Api.I.patch('/api/conversations/$convId/messages/${message.str('id')}', {'text': text.trim()}));
    if (ok == null || !context.mounted) return null;
    toast(context, 'Message edited');
    return text.trim();
  }

  static Future<bool> forward(BuildContext context, {required String convId, required String messageId}) async {
    final to = await openSheet<List<String>>(context, (_) => _ForwardSheet(convId: convId));
    if (to == null || to.isEmpty || !context.mounted) return false;
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$convId/messages/$messageId/forward', {'to': to}));
    if (ok == null || !context.mounted) return false;
    toast(context, to.length == 1 ? tr(context, 'Forwarded') : trf(context, 'Forwarded to {n} chats', {'n': '${to.length}'}));
    return true;
  }

  /// Mute for 8 hours / a week / always, or unmute. True when changed.
  static Future<bool> mute(BuildContext context, {required String convId, DateTime? mutedUntil}) async {
    final muted = mutedUntil != null && mutedUntil.isAfter(DateTime.now());
    final pick = await openSheet<String>(
      context,
      (c) => MpSheet(
        title: muted ? 'Notifications muted' : 'Mute notifications',
        subtitle: muted
            ? (mutedUntil.year > DateTime.now().year + 10 ? tr(context, 'Muted always') : trf(context, 'Muted until {when}', {'when': F.when(mutedUntil)}))
            : 'Messages still arrive and show as unread. Urgent messages always ring.',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: VGap(
            gap: 8,
            children: [
              if (muted) MpButton('Unmute', onTap: () => Navigator.pop(c, 'off')),
              MpButton('For 8 hours', kind: muted ? MpBtn.secondary : MpBtn.primary, onTap: () => Navigator.pop(c, '8h')),
              MpButton('For 1 week', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, '1w')),
              MpButton('Always', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'always')),
            ],
          ),
        ),
      ),
    );
    if (pick == null || !context.mounted) return false;
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$convId/mute', {'for': pick}));
    if (ok == null || !context.mounted) return false;
    toast(context, switch (pick) { 'off' => 'Notifications on', '8h' => 'Muted for 8 hours', '1w' => 'Muted for a week', _ => 'Muted' });
    return true;
  }

  /// Clear chat: hidden for this person only; the record and everyone else keep it.
  static Future<bool> clear(BuildContext context, {required String convId}) async {
    final yes = await openSheet<bool>(
      context,
      (c) => MpSheet(
        title: 'Clear this chat?',
        subtitle: 'The messages so far are hidden on your phones only. The other person, and the medical record, keep them.',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: VGap(gap: 8, children: [
            MpButton('Clear chat', kind: MpBtn.danger, onTap: () => Navigator.pop(c, true)),
            MpButton('Keep', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, false)),
          ]),
        ),
      ),
    );
    if (yes != true || !context.mounted) return false;
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$convId/clear', const {}));
    if (ok == null || !context.mounted) return false;
    toast(context, 'Chat cleared');
    return true;
  }

  /// The voice message as text (made once on the server, then kept).
  static Future<String?> transcribe(BuildContext context, {required String convId, required String messageId}) async {
    toast(context, 'Turning it into text…');
    final res = await runAction(context, () => Api.I.post('/api/conversations/$convId/messages/$messageId/transcribe', const {}));
    if (res is! Map || !context.mounted) return null;
    return res['transcript'] as String?;
  }

  /// Search the whole chat; returns the id of the message tapped.
  static Future<String?> search(BuildContext context, {required String convId}) => openSheet<String>(context, (_) => _ServerSearchSheet(convId: convId));
}

/// Says "typing…" to the others at most every 3 seconds while this person types.
class TypingPinger {
  final String? Function() convId;
  TypingPinger(this.convId);
  DateTime? _last;

  void changed(String text) {
    final id = convId();
    if (id == null || text.trim().isEmpty || !isLive) return;
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) < const Duration(seconds: 3)) return;
    _last = now;
    Api.I.post('/api/conversations/$id/typing', const {}).catchError((_) => null);
  }

  /// Sent or cleared: no longer typing.
  void stop() {
    final id = convId();
    if (_last == null || id == null || !isLive) return;
    _last = null;
    Api.I.post('/api/conversations/$id/typing', const {'typing': false}).catchError((_) => null);
  }
}

class _EditSheet extends StatefulWidget {
  final String initial;
  const _EditSheet({required this.initial});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MpSheet(
        title: 'Edit message',
        subtitle: 'Others see it marked "Edited".',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: VGap(gap: 12, children: [
            MpInput(controller: _c, maxLines: 5, height: 120, autofocus: true),
            MpButton('Save', onTap: () => _c.text.trim().isEmpty ? toast(context, 'Type a message') : Navigator.pop(context, _c.text)),
          ]),
        ),
      );
}

class _ForwardSheet extends StatefulWidget {
  final String convId;
  const _ForwardSheet({required this.convId});

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  List<Map<String, dynamic>>? _items;
  final _picked = <String>{};

  @override
  void initState() {
    super.initState();
    Api.I.get('/api/conversations/${widget.convId}/forward-targets').then((r) {
      if (mounted) setState(() => _items = (r as Map).cast<String, dynamic>().list('items'));
    }).catchError((Object e) {
      if (mounted) {
        toast(context, e is ApiException ? e.message : "Couldn't load your chats");
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return MpSheet(
      title: 'Forward to',
      subtitle: "A patient's messages go only to colleagues or the same patient's chats.",
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: items == null
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty) Text('No chat to forward it to', style: tx(15, c: MP.ink2)),
                  for (final c in items.take(30))
                    Tap(
                      onTap: () => setState(() => _picked.contains(c.str('id')) ? _picked.remove(c.str('id')) : (_picked.length < 5 ? _picked.add(c.str('id')) : null)),
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      child: Row(children: [
                        MpCheck(value: _picked.contains(c.str('id'))),
                        const Gap(12),
                        Expanded(child: UserText(c.str('name'), style: tx(15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                  const Gap(12),
                  MpButton(_picked.isEmpty ? 'Choose a chat' : trf(context, 'Send to {n}', {'n': '${_picked.length}'}), onTap: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList())),
                ],
              ),
      ),
    );
  }
}

class _ServerSearchSheet extends StatefulWidget {
  final String convId;
  const _ServerSearchSheet({required this.convId});

  @override
  State<_ServerSearchSheet> createState() => _ServerSearchSheetState();
}

class _ServerSearchSheetState extends State<_ServerSearchSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hits = const [];
  bool _searching = false;
  String _asked = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    if (q.length < 2) {
      setState(() => _hits = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = (await Api.I.get('/api/conversations/${widget.convId}/search', query: {'q': q}) as Map).cast<String, dynamic>();
      if (mounted && _q.text.trim() == q) setState(() => (_hits = r.list('items'), _asked = q));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    return MpSheet(
      title: 'Search this chat',
      showClose: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(12),
          MpInput(controller: _q, hint: 'Search messages', leadingIcon: I.search, autofocus: true, onChanged: _changed),
          const Gap(12),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (!_searching && q.length >= 2 && _asked == q && _hits.isEmpty) Text('No messages with these words', style: tx(14, c: MP.ink2)),
          for (final h in _hits.take(40))
            Tap(
              onTap: () => Navigator.pop(context, h.str('id')),
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  [h.str('senderName').isEmpty ? (h.str('senderType') == 'ai' ? 'MedPin AI' : '') : h.str('senderName'), if (F.date(h['createdAt']) != null) F.when(F.date(h['createdAt'])!)].where((s) => s.isNotEmpty).join(' · '),
                  style: tx(12, c: MP.ink3),
                ),
                const Gap(2),
                UserText(h.str('text'), style: tx(15, h: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
        ],
      ),
    );
  }
}

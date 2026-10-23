import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import '../data/live.dart';
import 'i18n.dart';
import 'mp.dart';

/// "What MedPin AI remembers": the notes MedPin AI keeps between conversations
/// (backend services/ai_memory.js). The owner reads them, adds one, deletes one
/// or all, and turns memory off (which also forgets what was kept).
/// [base]: '/api/ai' (doctor) or '/api/patient/ai' (patient).
/// Live data: GET/POST/DELETE {base}/memories, DELETE {base}/memories/:id,
/// PUT {base}/memories/settings.
class AiMemorySheet extends StatefulWidget {
  final String base;
  final bool doctor;
  const AiMemorySheet({super.key, required this.base, this.doctor = false});

  static Future<void> open(BuildContext context, {required String base, bool doctor = false}) =>
      openSheet<void>(context, (_) => AiMemorySheet(base: base, doctor: doctor));

  @override
  State<AiMemorySheet> createState() => _AiMemorySheetState();
}

class _AiMemorySheetState extends State<AiMemorySheet> {
  Map<String, dynamic>? _data;
  bool _failed = false;
  bool _confirmClear = false;
  final _busy = ValueNotifier(false);
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _busy.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Api.I.get('${widget.base}/memories');
      if (mounted) setState(() => _data = (res as Map).cast<String, dynamic>());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _enabled => _data?['enabled'] != false;
  List<Map<String, dynamic>> get _items => [for (final m in (_data?['items'] as List? ?? const [])) (m as Map).cast<String, dynamic>()];

  Future<void> _toggle(bool on) async {
    final res = await runAction(context, () => Api.I.put('${widget.base}/memories/settings', {'enabled': on}), busy: _busy);
    if (res is! Map || !mounted) return;
    setState(() => _data = res.cast<String, dynamic>());
    toast(context, on ? 'MedPin AI will remember things from your chats' : 'Memory is off. MedPin AI forgot what it kept.');
  }

  Future<void> _add() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
    final res = await runAction(context, () => Api.I.post('${widget.base}/memories', {'text': text}), busy: _busy);
    if (res == null || !mounted) return;
    _note.clear();
    FocusScope.of(context).unfocus();
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final ok = await runAction(context, () => Api.I.delete('${widget.base}/memories/${m['id']}'), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Forgotten');
    await _load();
  }

  Future<void> _clear() async {
    if (!_confirmClear) {
      setState(() => _confirmClear = true);
      return;
    }
    final ok = await runAction(context, () => Api.I.delete('${widget.base}/memories'), busy: _busy);
    if (ok == null || !mounted) return;
    setState(() => _confirmClear = false);
    toast(context, 'MedPin AI forgot everything it kept');
    await _load();
  }

  static const _kinds = {'preference': 'How you like answers', 'routine': 'Routine', 'goal': 'Goal', 'health_note': 'You said (not checked by a doctor)', 'about': 'About you'};

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return MpSheet(
      title: 'What MedPin AI remembers',
      subtitle: widget.doctor
          ? 'Notes from your chats that help MedPin AI answer the way you work. Patient details are never kept here — they stay in the record.'
          : 'Notes from your chats that help MedPin AI answer for you: your routine, food, goals. Your doctor sees your record, not these notes.',
      showClose: true,
      child: _data == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: _failed
                    ? MpLink('Couldn\'t load. Try again', onTap: () {
                        setState(() => _failed = false);
                        _load();
                      })
                    : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary)),
              ),
            )
          : ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (context, busy, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tap(
                    onTap: busy ? null : () => _toggle(!_enabled),
                    radius: 14,
                    color: MP.white,
                    border: MP.line,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Remember things from my chats', style: tx(15, w: w600)),
                              const SizedBox(height: 2),
                              Text(
                                _enabled ? 'Say "remember…" or "forget…" in a chat any time' : 'Off: nothing is kept between chats',
                                style: tx(13, c: MP.ink3, h: 1.35),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        MpSwitch(value: _enabled, onChanged: busy ? null : _toggle),
                      ],
                    ),
                  ),
                  if (_enabled) ...[
                    const SizedBox(height: 16),
                    MpInput(
                      controller: _note,
                      hint: widget.doctor ? 'E.g. Keep answers short, in bullet points' : 'E.g. I work night shifts',
                      height: 48,
                      trailing: MpIconButton(I.plus, label: 'Add', iconSize: 18, onTap: busy ? null : _add),
                    ),
                    const SizedBox(height: 16),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nothing yet. MedPin AI keeps short notes here as you chat.',
                          textAlign: TextAlign.center,
                          style: tx(14, c: MP.ink2, h: 1.5),
                        ),
                      ),
                    for (final m in items)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MP.line))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // The note as MedPin AI wrote it (not translated).
                                  UserText(m['text'] as String? ?? '', style: tx(15, h: 1.4)),
                                  const SizedBox(height: 2),
                                  Text(m['source'] == 'added' ? 'Added by you' : (_kinds[m['kind']] ?? 'About you'), style: tx(12, c: MP.ink3)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            MpIconButton(I.close, label: 'Forget this', iconSize: 16, onTap: busy ? null : () => _delete(m)),
                          ],
                        ),
                      ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      MpButton(
                        _confirmClear ? 'Tap again to forget everything' : 'Forget everything',
                        kind: MpBtn.dangerSoft,
                        height: 48,
                        onTap: busy ? null : _clear,
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

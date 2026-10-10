import 'package:flutter/material.dart' hide Text;

import '../data/format.dart';
import 'mp.dart';
import 'i18n.dart';

/// Round "jump to latest" button for a chat whose list is `reverse: true`
/// (offset 0 = newest). It shows only once the reader has scrolled up.
class JumpToLatest extends StatefulWidget {
  final ScrollController controller;

  /// Always visible (the design shows it in the sample thread).
  final bool always;
  const JumpToLatest({super.key, required this.controller, this.always = false});

  @override
  State<JumpToLatest> createState() => _JumpToLatestState();
}

class _JumpToLatestState extends State<JumpToLatest> {
  bool _up = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final up = widget.controller.hasClients && widget.controller.offset > 240;
    if (up != _up) setState(() => _up = up);
  }

  void _jump() {
    if (widget.controller.hasClients) widget.controller.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.always || _up ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(
        ignoring: !(widget.always || _up),
        child: Semantics(
          button: true,
          label: 'Jump to latest message',
          child: SizedBox(
            width: 44,
            height: 44,
            child: Tap(
              onTap: _jump,
              radius: 999,
              color: MP.white,
              border: MP.line,
              shadow: MPShadow.float,
              child: const Center(child: Ico(I.chevronDown, size: 20, color: MP.primary)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Searches the loaded messages of a chat; returns the id of the one tapped.
Future<String?> searchChat(BuildContext context, List<Map<String, dynamic>> messages, {required String Function(Map<String, dynamic>) sender}) {
  return openSheet<String>(context, (_) => _SearchSheet(messages: messages, sender: sender));
}

class _SearchSheet extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String Function(Map<String, dynamic>) sender;
  const _SearchSheet({required this.messages, required this.sender});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final hits = q.length < 2
        ? const <Map<String, dynamic>>[]
        : [
            for (final m in widget.messages.reversed)
              if (m['deleted'] != true && '${m['text'] ?? ''} ${(m['attachment'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(q)) m,
          ];
    return MpSheet(
      title: 'Search this chat',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MpInput(controller: _q, hint: 'Search messages', leadingIcon: I.search, autofocus: true, onChanged: (_) => setState(() {})),
          const Gap(12),
          if (q.length >= 2 && hits.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No messages match “${_q.text.trim()}”', style: tx(14, c: MP.ink2))),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in hits.take(50))
                  Tap(
                    onTap: () => Navigator.pop(context, '${m['id']}'),
                    radius: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [widget.sender(m), if (F.date(m['createdAt']) != null) '${F.dayMonth(F.date(m['createdAt'])!)} · ${F.time(F.date(m['createdAt'])!)}'].join(' · '),
                          style: tx(12, w: w600, c: MP.ink3),
                        ),
                        const Gap(2),
                        Text('${m['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(15, h: 1.4)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

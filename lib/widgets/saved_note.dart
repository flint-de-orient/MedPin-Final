import 'package:flutter/material.dart' hide Text;

import 'i18n.dart';
import 'mp.dart';

OverlayEntry? _noteEntry;

/// Small "Downloaded ✓" card above the tab bar: a green tick, what was saved
/// and where, and Open. It slides up, stays about four seconds and can be
/// swiped or tapped away. Drawn in the root overlay, like [toast].
void showSavedNote(BuildContext context, {required String title, String? detail, VoidCallback? onOpen}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _noteEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SavedNote(
      title: title,
      detail: detail,
      onOpen: onOpen,
      onDone: () {
        if (_noteEntry == entry) _noteEntry = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _noteEntry = entry;
  overlay.insert(entry);
}

class _SavedNote extends StatefulWidget {
  final String title;
  final String? detail;
  final VoidCallback? onOpen;
  final VoidCallback onDone;
  const _SavedNote({required this.title, this.detail, this.onOpen, required this.onDone});

  @override
  State<_SavedNote> createState() => _SavedNoteState();
}

class _SavedNoteState extends State<_SavedNote> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(_fade);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(const Duration(milliseconds: 4000));
    _close();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    await _c.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 100 + mq.padding.bottom,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Dismissible(
            key: const ValueKey('saved-note'),
            direction: DismissDirection.down,
            onDismissed: (_) => widget.onDone(),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: MP.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MP.line),
                    boxShadow: MPShadow.float,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: MP.greenSoft, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Ico(I.check, size: 18, color: MP.green, stroke: 2.5),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.title, style: tx(15, w: w600, h: 1.3)),
                            if (widget.detail != null) ...[
                              const Gap(2),
                              Text(widget.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2, h: 1.35)),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onOpen != null)
                        Tap(
                          onTap: () {
                            widget.onOpen!();
                            _close();
                          },
                          radius: 12,
                          child: SizedBox(
                            height: 44,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Center(child: Text('Open', style: tx(15, w: w600, c: MP.primary))),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

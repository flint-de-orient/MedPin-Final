import 'package:flutter/material.dart';

import '../../widgets/mp.dart';

// Shared pieces for batch D1: AI Assistant composer, status pill, option
// picker sheet and the doctor's consulting locations.

/// Status pill: 22px high, padding 0 8, radius 999, 12px / 700.
class D1Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double height;
  final double fontSize;
  final double padding;
  final double em;
  const D1Pill(
    this.text, {
    super.key,
    required this.bg,
    required this.fg,
    this.height = 22,
    this.fontSize = 12,
    this.padding = 8,
    this.em = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: padding),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(text, maxLines: 1, softWrap: false, style: tx(fontSize, w: w700, c: fg, em: em))],
      ),
    );
  }
}

/// Bottom sheet with a list of options (52px rows, check on the current one).
/// Resolves to the picked option, or null when dismissed.
class D1Picker {
  D1Picker._();

  static Future<String?> show(
    BuildContext context, {
    String? title,
    required List<String> options,
    required String value,
  }) {
    return openSheet<String>(
      context,
      (c) => MpSheet(
        title: title,
        child: Column(
          children: [
            for (final o in options)
              Tap(
                onTap: () => Navigator.pop(c, o),
                radius: 12,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          o,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(16, w: o == value ? w600 : w400),
                        ),
                      ),
                      if (o == value) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A place the doctor consults at (Queue-Select options, Queue-List header).
class D1Location {
  final String name;

  /// Spoken form of [name] (commas instead of the middle dot).
  final String a11y;

  /// Second line in the location picker, e.g. 'Clinic · 9:00 AM – 1:00 PM'.
  final String kind;

  /// Second line in the queue header, e.g. 'Today 9:00 AM – 1:00 PM'.
  final String hours;
  final String? badge;
  final Color badgeBg;
  final Color badgeFg;
  final String? booked;
  final String? waiting;

  /// Set when the location is closed today (option is disabled).
  final String? note;

  const D1Location({
    required this.name,
    required this.a11y,
    required this.kind,
    required this.hours,
    this.badge,
    this.badgeBg = MP.fill,
    this.badgeFg = MP.ink2,
    this.booked,
    this.waiting,
    this.note,
  });

  bool get closed => note != null;

  static const all = [
    D1Location(
      name: 'City Care Clinic · Salt Lake',
      a11y: 'City Care Clinic, Salt Lake',
      kind: 'Clinic · 9:00 AM – 1:00 PM',
      hours: 'Today 9:00 AM – 1:00 PM',
      badge: 'Open now',
      badgeBg: MP.greenSoft,
      badgeFg: MP.green,
      booked: '12 booked',
      waiting: '3 waiting',
    ),
    D1Location(
      name: 'City Care · New Town',
      a11y: 'City Care, New Town',
      kind: 'Clinic · 5:00 PM – 8:00 PM',
      hours: 'Today 5:00 PM – 8:00 PM',
      badge: 'Opens 5:00 PM',
      booked: '6 booked',
    ),
    D1Location(
      name: 'Sen Diabetes Chamber · Gariahat',
      a11y: 'Sen Diabetes Chamber, Gariahat',
      kind: 'Chamber · Thu and Sat only',
      hours: 'Thu and Sat only',
      note: 'Closed today · next session Thu, 1 Oct',
    ),
  ];
}

/// AI Assistant composer bar (Doctor-AI, Doctor-AI-Chat): white bar with a
/// top border, a 56px pill input (1px #D5DBE5; 1.5px #003399 while focused or
/// filled) with a 40px send button, a 56px mic button and an optional caption.
class D1Composer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hint;
  final String? caption;

  /// Screen-reader label of the input.
  final String label;

  /// Filled blue mic (landing) instead of the white outlined one (chat).
  final bool micPrimary;
  final ValueChanged<String> onSend;
  final VoidCallback onMic;
  const D1Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onMic,
    this.hint,
    this.caption,
    this.label = 'Ask the AI Assistant',
    this.micPrimary = true,
  });

  @override
  State<D1Composer> createState() => _D1ComposerState();
}

class _D1ComposerState extends State<D1Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(D1Composer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _send() {
    final t = widget.controller.text.trim();
    if (t.isNotEmpty) widget.onSend(t);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final canSend = text.trim().isNotEmpty;
    final active = canSend || widget.focusNode.hasFocus;
    final mic = widget.micPrimary;
    return MpBottomBar(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.focusNode.requestFocus,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
                    decoration: BoxDecoration(
                      color: MP.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: active ? MP.primary : MP.lineStrong, width: active ? 1.5 : 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              // Placeholder, clipped like a browser input (no ellipsis).
                              if (widget.hint != null && text.isEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        widget.hint!,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.clip,
                                        style: tx(15, c: MP.ink3),
                                      ),
                                    ),
                                  ),
                                ),
                              Semantics(
                                label: widget.label,
                                child: TextField(
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  style: tx(15),
                                  cursorColor: MP.primary,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Gap(8),
                        Semantics(
                          button: true,
                          enabled: canSend,
                          label: 'Send',
                          child: GestureDetector(
                            onTap: canSend ? _send : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: canSend ? MP.primary : MP.fill, shape: BoxShape.circle),
                              child: Ico(I.arrowUp, size: 18, color: canSend ? MP.white : MP.ink3, stroke: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Semantics(
                button: true,
                label: 'Speak your question',
                // 56×56 border-box button: the size wraps the Tap.
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Tap(
                    onTap: widget.onMic,
                    radius: 999,
                    color: mic ? MP.primary : MP.white,
                    border: mic ? null : MP.lineStrong,
                    shadow: mic ? MPShadow.button : null,
                    child: Center(child: Ico(I.mic, size: 22, color: mic ? MP.white : MP.primary)),
                  ),
                ),
              ),
            ],
          ),
          if (widget.caption != null) ...[
            const Gap(10),
            Text(widget.caption!, textAlign: TextAlign.center, style: tx(12, c: MP.ink3)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';

/// Design: Patient-Thread.dc.html — "Patient thread".
///
/// The design shows the voice note long-pressed, with its action menu open;
/// that is the initial state. Tapping anywhere closes the menu and a long
/// press on the voice note opens it again.
class PatientThreadScreen extends StatefulWidget {
  const PatientThreadScreen({super.key});

  @override
  State<PatientThreadScreen> createState() => _PatientThreadScreenState();
}

/// Voice-note waveform bar heights; the first 7 are already played.
const _wave = [
  8.0,
  14.0,
  20.0,
  12.0,
  24.0,
  18.0,
  10.0,
  22.0,
  28.0,
  16.0,
  12.0,
  20.0,
  26.0,
  14.0,
  8.0,
  18.0,
  22.0,
  12.0,
  16.0,
  10.0,
];

const _pushpin = '<path d="M12 17v5M9 3h6l-1 6 3 3v2H7v-2l3-3z"/>';
const _playIcon = '<path d="M8 5v14l11-7z"/>';

const _menuItems = [('Reply', false), ('Pin', false), ('Hide', false), ('Delete for everyone', true)];

class _PatientThreadScreenState extends State<PatientThreadScreen> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  final _menuLink = LayerLink();
  final _voiceKey = GlobalKey();
  final _adviceKey = GlobalKey();

  late final AnimationController _voice = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
    value: 7 / _wave.length,
  )..addStatusListener((s) {
    if (s == AnimationStatus.completed && mounted) setState(() => _voice.value = 0);
  });

  bool _menuOpen = true;
  bool _voiceShown = true;
  bool _voicePinned = false;
  bool _hasText = false;
  final _sent = <(String, String)>[];

  @override
  void initState() {
    super.initState();
    _reply.addListener(() {
      final has = _reply.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _voice.dispose();
    _scroll.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _closeMenu() {
    if (_menuOpen) setState(() => _menuOpen = false);
  }

  void _menuAction(String a) {
    setState(() {
      _menuOpen = false;
      if (a == 'Pin') _voicePinned = true;
      if (a == 'Hide' || a == 'Delete for everyone') {
        _voiceShown = false;
        _voicePinned = false;
        _voice.stop();
      }
    });
    switch (a) {
      case 'Reply':
        _replyFocus.requestFocus();
      case 'Pin':
        toast(context, 'Pinned at the top of the chat');
      case 'Hide':
        toast(context, 'Message hidden');
      default:
        toast(context, 'Deleted for everyone');
    }
  }

  void _togglePlay() {
    setState(() {
      if (_voice.isAnimating) {
        _voice.stop();
      } else {
        _voice.forward();
      }
    });
  }

  String _clock() {
    final t = TimeOfDay.now();
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  void _send() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    setState(() => _sent.add((text, _clock())));
    _toLatest();
  }

  void _toLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _toPinned() {
    final c = (_voicePinned ? _voiceKey : _adviceKey).currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return MpPage(
      header: _header(context),
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AI paused notice
          Container(
            color: MP.fill,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Ico(I.sparkle, size: 16, color: MP.ink2),
                const Gap(8),
                Expanded(
                  child: Text("AI assistant is paused while you're in this thread", style: tx(14, c: MP.ink2, h: 1.45)),
                ),
              ],
            ),
          ),
          // Pinned message
          Tap(
            onTap: _toPinned,
            radius: 0,
            color: MP.white,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  const Ico(_pushpin, size: 16, color: MP.primary),
                  const Gap(10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Pinned:', style: tx(14, w: w600, c: MP.primary, h: 1.45)),
                          TextSpan(text: _voicePinned ? ' Voice note · 0:18' : ' Take Metformin after food'),
                        ],
                      ),
                      style: tx(14, h: 1.45),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(10),
                  const Ico(I.chevronRight, size: 16, color: MP.ink3),
                ],
              ),
            ),
          ),
          Expanded(child: _messages()),
        ],
      ),
      bottom: _composer(),
      overlays: [
        Positioned(
          left: 16,
          bottom: 92 + safeBottom,
          child: Semantics(
            button: true,
            label: 'Jump to latest message',
            // <button>: border-box, 44×44 including the 1px border.
            child: SizedBox(
              width: 44,
              height: 44,
              child: Tap(
                onTap: _toLatest,
                radius: 999,
                color: MP.white,
                border: MP.line,
                shadow: MPShadow.float,
                child: const Center(child: Ico(I.chevronDown, size: 20, color: MP.primary)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(4),
          Expanded(
            child: Tap(
              onTap: () => Nav.go(context, 'PP-Summary'),
              radius: 12,
              child: Row(
                children: [
                  const MpAvatar('PS', size: 40, fontSize: 14),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Priya Sharma',
                          style: tx(20, w: w700, h: 1.25),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('Last seen 2 min ago', style: tx(13, c: MP.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(4),
          MpIconButton(
            I.phone,
            label: 'Call Priya Sharma',
            color: MP.primary,
            onTap: () => toast(context, 'Calling Priya Sharma…'),
          ),
        ],
      ),
    );
  }

  Widget _messages() {
    final items = <Widget>[
      // "Today" separator
      Row(
        children: [
          const Expanded(child: MpDivider()),
          const Gap(12),
          Text('TODAY', style: tx(12, w: w600, c: MP.ink3, em: 0.06)),
          const Gap(12),
          const Expanded(child: MpDivider()),
        ],
      ),
      if (_voiceShown) _voiceNote(),
      _attachment(),
      _aiMessage(),
      _quotedReply(),
      _doctorMessage("I've pinned it at the top of our chat.", '9:24 AM', read: true),
      for (final m in _sent) _doctorMessage(m.$1, m.$2, read: false),
    ];
    return SingleChildScrollView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[if (i > 0) const Gap(12), items[i]],
            ],
          ),
          // Long-press menu, 8px under the voice note, above the later messages.
          if (_menuOpen && _voiceShown)
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _menuLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                offset: const Offset(0, 8),
                child: TapRegion(onTapOutside: (_) => _closeMenu(), child: _menu()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _voiceNote() {
    return Align(
      alignment: Alignment.centerLeft,
      child: CompositedTransformTarget(
        link: _menuLink,
        child: GestureDetector(
          onLongPress: () => setState(() => _menuOpen = true),
          child: Container(
            key: _voiceKey,
            width: 248,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MP.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _menuOpen ? MP.lineStrong : MP.line),
              boxShadow: _menuOpen ? MPShadow.float : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Semantics(
                      container: true,
                      button: true,
                      label: 'Play voice note, 18 seconds',
                      child: Tap(
                        onTap: _togglePlay,
                        radius: 999,
                        color: MP.primarySoft,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Ico(
                              _voice.isAnimating ? I.pause : _playIcon,
                              size: 18,
                              color: MP.primary,
                              filled: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _voice,
                        builder: (context, _) {
                          final played = (_voice.value * _wave.length + 1e-6).floor();
                          return SizedBox(
                            height: 28,
                            child: Row(
                              children: [
                                for (var i = 0; i < _wave.length; i++) ...[
                                  if (i > 0) const Gap(3),
                                  Container(
                                    width: 3,
                                    height: _wave[i],
                                    decoration: BoxDecoration(
                                      color: i < played ? MP.primary : MP.primaryLine,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Gap(12),
                    AnimatedBuilder(
                      animation: _voice,
                      builder: (context, _) {
                        final s = _voice.isAnimating ? (_voice.value * 18).floor() : 18;
                        return Text('0:${s.toString().padLeft(2, '0')}', style: tx(13, c: MP.ink2, tab: true));
                      },
                    ),
                  ],
                ),
                const Gap(4),
                Align(alignment: Alignment.centerRight, child: Text('9:05 AM', style: tx(12, c: MP.ink3, tab: true))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu() {
    return Container(
      width: 232,
      padding: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.line),
        boxShadow: MPShadow.float,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _menuItems.length; i++)
            Tap(
              onTap: () => _menuAction(_menuItems[i].$1),
              radius: 0,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Text(_menuItems[i].$1, style: _menuItems[i].$2 ? tx(16, w: w600, c: MP.red) : tx(16)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attachment() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 264,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MP.line),
        ),
        child: Tap(
          onTap: () => Nav.go(context, 'PP-Tests'),
          radius: 12,
          color: MP.bg,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MP.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MP.line),
                ),
                child: const Ico(I.fileText, size: 20, color: MP.primary),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lipid profile.pdf', style: tx(15, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('PDF · 240 KB · 9:06 AM', style: tx(13, c: MP.ink3, tab: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiMessage() {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 288),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Ico(I.sparkle, size: 14, color: MP.ink2),
                    const Gap(6),
                    Text('AI ASSISTANT', style: tx(12, w: w600, c: MP.ink2, em: 0.06)),
                  ],
                ),
                const Gap(4),
                Text("Thanks, Priya. I've shared your report with Dr. Sen's team.", style: tx(16, h: 1.5)),
                const Gap(4),
                Align(alignment: Alignment.centerRight, child: Text('9:06 AM', style: tx(12, c: MP.ink3, tab: true))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quotedReply() {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 288),
        child: IntrinsicWidth(
          child: Container(
            key: _adviceKey,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'Replying to Priya Sharma: Should I take the tablet before or after breakfast?',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: MP.primaryDark,
                      borderRadius: BorderRadius.circular(12),
                      border: const Border(left: BorderSide(color: MP.primarySoft, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Priya Sharma · Yesterday', style: tx(13, w: w600, c: MP.primarySoft)),
                        const Gap(2),
                        Text(
                          'Should I take the tablet before or after breakfast?',
                          style: tx(14, c: MP.white, h: 1.45),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const Gap(6),
                Text('After food, not before. Your lipid report looks fine.', style: tx(16, c: MP.white, h: 1.5)),
                const Gap(6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('9:22 AM', style: tx(12, c: MP.primarySoft, tab: true)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _doctorMessage(String text, String time, {required bool read}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 288),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(16)),
              child: Text(text, style: tx(16, c: MP.white, h: 1.5)),
            ),
          ),
          const Gap(4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$time ·', style: tx(12, c: MP.ink3, tab: true)),
              const Gap(4),
              Ico(I.check, size: 14, color: read ? MP.green : MP.ink3, stroke: 2.25),
              const Gap(4),
              Text(read ? 'Read' : 'Sent', style: tx(12, c: MP.ink3, tab: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(color: MP.white, border: Border(top: BorderSide(color: MP.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Attach a file',
                child: Tap(
                  onTap: () => toast(context, 'Choose a photo, PDF or report to attach'),
                  radius: 12,
                  child: const SizedBox(
                    width: 44,
                    height: 48,
                    child: Center(child: Ico(I.paperclip, size: 22, color: MP.ink2)),
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: MP.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MP.lineStrong),
                  ),
                  child: TextField(
                    controller: _reply,
                    focusNode: _replyFocus,
                    style: tx(16),
                    cursorColor: MP.primary,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Write a reply',
                      hintStyle: tx(16, c: MP.ink3),
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Semantics(
                button: true,
                label: _hasText ? 'Send reply' : 'Record a voice reply',
                child: Tap(
                  onTap: _hasText ? _send : () => toast(context, 'Hold to record a voice reply'),
                  radius: 999,
                  color: MP.primary,
                  shadow: MPShadow.button,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: Ico(_hasText ? I.send : I.mic, size: 22, color: MP.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

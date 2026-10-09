import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';
import 'common_d1.dart';

/// Design: Doctor-AI-Chat.dc.html — "Doctor · AI Assistant · answers with Listen".
class DoctorAiChatScreen extends StatefulWidget {
  /// True when opened from the AI Assistant landing; "New conversation" then
  /// simply goes back to it.
  final bool fromLanding;
  const DoctorAiChatScreen({super.key, this.fromLanding = false});

  @override
  State<DoctorAiChatScreen> createState() => _DoctorAiChatScreenState();
}

// name, value, flag, source, colour
const _findings = [
  ('LDL cholesterol', '162 mg/dL', 'High', 'Lipid profile · 12 Mar', MP.red),
  ('Triglycerides', '210 mg/dL', 'High', 'Lipid profile · 12 Mar', MP.red),
  ('HbA1c', '7.2%', 'High', 'Diabetes panel · 18 Jul', MP.red),
  ('Fasting glucose', '138 mg/dL', 'High', 'Diabetes panel · 18 Jul', MP.red),
  ('Vitamin D', '14 ng/mL', 'Low', 'Vitamin D · 18 Jul', MP.amber),
];

// name, dose, prescribed by, adherence, adherence colour
const _meds = [
  ('Metformin 500 mg', '1-0-1', 'You · since Jun 2025', '78% taken', MP.amber),
  ('Glimepiride 2 mg', '1-0-0', 'You · started today', 'New', MP.ink2),
  ('Vitamin D3 60,000 IU', 'weekly', 'You · week 7 of 8', '100% taken', MP.green),
  ('Atorvastatin 10 mg', '0-0-1', 'Dr. Rina Mitra · since Feb', '86% taken', MP.green),
];

const _insights = [
  'HbA1c fell from 8.4% to 6.8% on Metformin, then drifted back to 7.2%. Most missed doses are the evening one.',
  'LDL is still high on Atorvastatin. Worth a word with Dr. Mitra.',
  'Fasting sugar at home is still around 142 mg/dL. Recheck HbA1c in 3 months.',
];

const _follow = ['Show her HbA1c trend', 'Draft follow-up advice', 'Compare with last visit'];

const _editIcon = '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>';
const _bars = [6.0, 12.0, 9.0, 14.0, 7.0];

/// Read-aloud length of each answer, in seconds.
const _lengths = [48, 21];

String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _DoctorAiChatScreenState extends State<DoctorAiChatScreen> {
  final _input = TextEditingController(text: 'Show her HbA1c trend');
  final _focus = FocusNode();
  final _scroll = ScrollController();

  /// Questions asked on this screen: text, meta line, spoken.
  final _asked = <(String, String, bool)>[];

  /// Playback position of each answer (answer 2 is being read in the design).
  final _pos = [0, 6];
  int? _playing = 1;
  Timer? _tick;
  bool _patient = true;
  bool _suggest = true;
  int _vote = 0;

  @override
  void initState() {
    super.initState();
    _startTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      final p = _playing;
      if (!mounted || p == null) {
        t.cancel();
        return;
      }
      setState(() {
        _pos[p]++;
        if (_pos[p] >= _lengths[p]) {
          _pos[p] = 0;
          _playing = null;
          t.cancel();
        }
      });
    });
  }

  void _listen(int i) {
    setState(() => _playing = _playing == i ? null : i);
    if (_playing == null) {
      _tick?.cancel();
    } else {
      _startTick();
    }
  }

  void _setVote(int v) {
    setState(() => _vote = _vote == v ? 0 : v);
    if (_vote != 0) toast(context, 'Thanks for the feedback');
  }

  void _copy() {
    final b =
        StringBuffer()
          ..writeln('Priya Sharma, 29 F · Type 2 diabetes · PCOS · Allergic to sulfa drugs')
          ..writeln('Health score 74 (+3 this week)')
          ..writeln()
          ..writeln('Abnormal results');
    for (final f in _findings) {
      b.writeln('${f.$1}: ${f.$2} (${f.$3}) · ${f.$4}');
    }
    b
      ..writeln()
      ..writeln('Current medicines');
    for (final m in _meds) {
      b.writeln('${m.$1} ${m.$2} · ${m.$3} · ${m.$4}');
    }
    b
      ..writeln()
      ..writeln('Insights');
    for (final s in _insights) {
      b.writeln('• $s');
    }
    Clipboard.setData(ClipboardData(text: b.toString().trim()));
    toast(context, 'Copied');
  }

  void _fill(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  void _ask(String text, {bool spoken = false}) {
    final time = _clock(DateTime.now());
    setState(() {
      _asked.add((text, spoken ? 'Spoken · $time' : time, spoken));
      _suggest = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(String text) {
    _input.clear();
    _focus.unfocus();
    _ask(text);
  }

  Future<void> _voice() async {
    final r = await Nav.go<String>(context, 'Doctor-AI-Voice');
    if (!mounted) return;
    if (r == 'ask') _ask('Which patients have abnormal kidney results this month', spoken: true);
    if (r == 'type') _focus.requestFocus();
  }

  void _newConversation() {
    if (widget.fromLanding) {
      Navigator.pop(context);
    } else {
      Navigator.of(context).pushReplacementNamed('Doctor-AI');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      scroll: false,
      header: _header(context),
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Question(
              'Summarise Priya Sharma — health score, abnormal results and current medicines.',
              meta: 'Spoken · 10:02 AM',
              spoken: true,
            ),
            const Gap(16),
            _answerOne(context),
            const Gap(16),
            const _Question('When is her next appointment?', meta: '10:04 AM'),
            const Gap(16),
            _answerTwo(context),
            if (_suggest) ...[
              const Gap(16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _follow)
                    SizedBox(
                      height: 36,
                      child: Tap(
                        onTap: () => _fill(c),
                        radius: 999,
                        color: MP.white,
                        border: MP.lineStrong,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(c, style: tx(14, w: w500))]),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            for (final q in _asked) ...[const Gap(16), _Question(q.$1, meta: q.$2, spoken: q.$3)],
          ],
        ),
      ),
      bottom: D1Composer(
        controller: _input,
        focusNode: _focus,
        hint: 'Ask a follow-up',
        label: 'Ask a follow-up',
        micPrimary: false,
        onSend: _send,
        onMic: _voice,
      ),
    );
  }

  /// White header: title row + "Talking about" patient chip.
  Widget _header(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                  const Gap(4),
                  Expanded(
                    child: Text(
                      'AI Assistant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(20, w: w700, h: 1.25),
                    ),
                  ),
                  const Gap(4),
                  MpIconButton(_editIcon, label: 'New conversation', iconSize: 20, onTap: _newConversation),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child:
                !_patient
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        children: [
                          Text('Talking about', style: tx(13, c: MP.ink2)),
                          const Gap(8),
                          Flexible(
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
                              decoration: BoxDecoration(
                                color: MP.primarySoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const MpAvatar('PS', size: 24, bg: MP.primary, fg: MP.white, fontSize: 11),
                                  const Gap(8),
                                  Flexible(
                                    child: Text(
                                      'Priya Sharma',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tx(14, w: w600, c: MP.primary),
                                    ),
                                  ),
                                  const Gap(8),
                                  MpIconButton(
                                    I.close,
                                    label: 'Clear patient',
                                    size: 24,
                                    iconSize: 14,
                                    radius: 999,
                                    stroke: 2,
                                    color: MP.primary,
                                    onTap: () => setState(() => _patient = false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _answerOne(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnswerHead(playing: _playing == 0, time: _fmt(_pos[0]), onTap: () => _listen(0)),
          const Gap(16),

          // Patient + health score
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Priya Sharma, 29 F', style: tx(17, w: w700)),
                    const Gap(4),
                    Text('Type 2 diabetes · PCOS', style: tx(14, c: MP.ink2)),
                    const Gap(6),
                    const D1Pill('Allergic to sulfa drugs', bg: MP.redSoft, fg: MP.red, height: 24, padding: 10),
                  ],
                ),
              ),
              const Gap(12),
              Container(
                width: 78,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: MP.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MP.line),
                ),
                child: Column(
                  children: [
                    Text('74', style: tx(26, w: w800, h: 1, tab: true)),
                    const Gap(2),
                    Text('Health score', style: tx(11, c: MP.ink2)),
                    const Gap(2),
                    Text('+3 this week', style: tx(11, w: w700, c: MP.green)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(16),

          // Abnormal results
          Text('Abnormal results', style: tx(13, w: w700, c: MP.ink2)),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
            child: Column(
              children: [
                for (var i = 0; i < _findings.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_findings[i].$1, style: tx(14, w: w600)),
                              const Gap(1),
                              Text(_findings[i].$4, style: tx(12, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(10),
                        Text(_findings[i].$2, style: tx(14, w: w700, c: _findings[i].$5, tab: true)),
                        const Gap(10),
                        SizedBox(
                          width: 36,
                          child: Text(
                            _findings[i].$3,
                            textAlign: TextAlign.right,
                            style: tx(12, w: w700, c: _findings[i].$5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Gap(16),

          // Current medicines
          Text('Current medicines', style: tx(13, w: w700, c: MP.ink2)),
          for (final m in _meds) ...[
            const Gap(8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: '${m.$1} ',
                          style: tx(14, w: w600),
                          children: [TextSpan(text: m.$2, style: tx(14, c: MP.ink2))],
                        ),
                      ),
                      const Gap(1),
                      Text(m.$3, style: tx(12, c: MP.ink3)),
                    ],
                  ),
                ),
                const Gap(10),
                Text(m.$4, style: tx(12, w: w700, c: m.$5)),
              ],
            ),
          ],
          const Gap(16),

          // Insights
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Insights', style: tx(13, w: w700, c: MP.ink2)),
                for (final s in _insights) ...[
                  const Gap(8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
                      ),
                      const Gap(10),
                      Expanded(child: Text(s, style: tx(14, h: 1.45))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Gap(16),

          // Sources + actions
          Container(
            padding: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'From 3 lab reports, 2 prescriptions and her medicine log. Not a diagnosis.',
                    style: tx(12, c: MP.ink3, h: 1.4),
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    _SmallButton(
                      'Open profile',
                      bg: MP.primarySoft,
                      fg: MP.primary,
                      onTap: () => Nav.go(context, 'PP-Summary'),
                    ),
                    const Gap(8),
                    _SmallButton('Copy', border: MP.lineStrong, onTap: _copy),
                    const Gap(8),
                    const Spacer(),
                    const Gap(8),
                    MpIconButton(
                      I.thumbUp,
                      label: 'Helpful',
                      size: 40,
                      iconSize: 18,
                      color: _vote == 1 ? MP.primary : MP.ink3,
                      background: _vote == 1 ? MP.primarySoft : null,
                      onTap: () => _setVote(1),
                    ),
                    const Gap(8),
                    MpIconButton(
                      I.thumbDown,
                      label: 'Not helpful',
                      size: 40,
                      iconSize: 18,
                      color: _vote == -1 ? MP.primary : MP.ink3,
                      background: _vote == -1 ? MP.primarySoft : null,
                      onTap: () => _setVote(-1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerTwo(BuildContext context) {
    final body = tx(15, h: 1.55);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnswerHead(playing: _playing == 1, time: _fmt(_pos[1]), onTap: () => _listen(1)),
          const Gap(12),
          Text.rich(
            TextSpan(
              style: body,
              children: [
                const TextSpan(
                  text: 'She is in your consultation room now — started at 9:14 AM. Her next follow-up is ',
                ),
                TextSpan(text: 'Tue, 13 Oct, 10:30 AM', style: tx(15, w: w700, h: 1.55)),
                const TextSpan(text: ' at City Care, Salt Lake.'),
              ],
            ),
          ),
          const Gap(12),
          Text('She also sent an urgent chat at 9:58 AM about chest tightness. It is still unreviewed.', style: body),
          const Gap(12),
          Row(
            children: [
              _SmallButton(
                'Review urgent chat',
                bg: MP.redSoft,
                fg: MP.red,
                onTap: () => Nav.go(context, 'Patient-Thread'),
              ),
              const Gap(8),
              _SmallButton('Reschedule', border: MP.lineStrong, onTap: () => Nav.go(context, 'Appointments-Manage')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Doctor's question: blue bubble (radius 20 20 6 20) + time line.
class _Question extends StatelessWidget {
  final String text;
  final String meta;
  final bool spoken;
  const _Question(this.text, {required this.meta, this.spoken = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: MP.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                  bottomLeft: Radius.circular(20),
                ),
              ),
              child: Text(text, style: tx(15, c: MP.white, h: 1.45)),
            ),
            const Gap(4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (spoken) ...[const Ico(I.mic, size: 12, color: MP.ink3, stroke: 2), const Gap(4)],
                Text(meta, style: tx(12, c: MP.ink3)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "MedPin AI" row of an answer with the Listen / playing pill.
class _AnswerHead extends StatelessWidget {
  final bool playing;
  final String time;
  final VoidCallback onTap;
  const _AnswerHead({required this.playing, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const MpIconTile(I.sparkle, size: 28, iconSize: 16, radius: 9),
        const Gap(10),
        Expanded(child: Text('MedPin AI', style: tx(14, w: w700))),
        const Gap(10),
        Semantics(
          button: true,
          toggled: playing,
          label: playing ? 'Pause reading' : 'Listen to this answer',
          // 36px border-box pill: the height wraps the Tap.
          child: SizedBox(
            height: 36,
            child: Tap(
              onTap: onTap,
              radius: 999,
              color: playing ? MP.primarySoft : MP.white,
              border: playing ? MP.primary : MP.lineStrong,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      playing
                          ? [
                            const Ico(I.pause, size: 16, color: MP.primary, filled: true),
                            const Gap(8),
                            SizedBox(
                              height: 14,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < _bars.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 2),
                                    Container(
                                      width: 2,
                                      height: _bars[i],
                                      decoration: BoxDecoration(
                                        color: MP.primary,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Gap(8),
                            Text(time, style: tx(14, w: w600, c: MP.primary, tab: true)),
                          ]
                          : [
                            const Ico(I.volume, size: 18, color: MP.primary),
                            const Gap(6),
                            Text('Listen', style: tx(14, w: w600, c: MP.primary)),
                          ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 40px action button inside an answer (radius 12, 14 / 600).
class _SmallButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  final VoidCallback onTap;
  const _SmallButton(this.label, {required this.onTap, this.bg = MP.white, this.fg = MP.ink, this.border});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Tap(
        onTap: onTap,
        radius: 12,
        color: bg,
        border: border,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: tx(14, w: w600, c: fg))]),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/voice.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-AI-Chat.dc.html — "Doctor · AI Assistant · answers with Listen".
/// Live (args {'sessionId'} and/or {'patientId'}, optional {'text'} to ask
/// straight away; none = new conversation): GET /api/ai/sessions/:id/messages,
/// GET /api/patients/:id for the "Talking about" patient, ask
/// POST /api/ai/sessions[/:id/messages], vote POST /api/ai/messages/:id/vote,
/// clear patient PATCH /api/ai/sessions/:id.
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

class _DoctorAiChatScreenState extends State<DoctorAiChatScreen> with LiveData {
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

  /// Live: the conversation, its patient, and the question being answered.
  bool _argsRead = false;
  String? _sessionId;
  String? _patientId;
  String? _firstText;
  String _firstMode = 'typed';
  (String, String, bool)? _pending;
  final _busy = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    if (isLive) {
      _input.text = '';
      _playing = null;
      return;
    }
    _startTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    Voice.stopSpeaking();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _busy.dispose();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    if (!_argsRead) {
      final a = await d1Args(this);
      _argsRead = true;
      _sessionId = a['sessionId'] as String?;
      _patientId = a['patientId'] as String?;
      _firstText = (a['text'] as String?)?.trim();
      if (a['inputMode'] == 'spoken') _firstMode = 'spoken';
    }
    final sid = _sessionId;
    final pid = _patientId;
    final res = await Future.wait([
      sid == null ? Future<Object?>.value(const []) : Api.I.get('/api/ai/sessions/$sid/messages'),
      pid == null ? Future<Object?>.value(null) : Api.I.get('/api/patients/$pid'),
    ]);
    return {'messages': res[0] ?? const [], 'patient': res[1]};
  }

  @override
  Future<void> reload({bool quiet = false}) async {
    await super.reload(quiet: quiet);
    final first = _firstText;
    if (mounted && data != null && first != null && first.isNotEmpty) {
      _firstText = null;
      _askLive(first, mode: _firstMode);
    }
  }

  List<Map<String, dynamic>> get _messages => data?.list('messages') ?? const [];

  /// GET /api/patients/:id of the "Talking about" patient (null when none).
  Map<String, dynamic>? get _livePatient {
    final p = data?['patient'];
    return _patientId != null && p is Map ? p.cast<String, dynamic>() : null;
  }

  void _scrollToEnd() {
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

  Future<void> _askLive(String text, {String mode = 'typed'}) async {
    if (_pending != null) return;
    setState(() => _pending = (text, mode == 'spoken' ? 'Spoken · ${_clock(DateTime.now())}' : _clock(DateTime.now()), mode == 'spoken'));
    _scrollToEnd();
    final res = await runAction(context, () async {
      if (_sessionId == null) {
        final s = await Api.I.post('/api/ai/sessions', {if (_patientId != null) 'patientId': _patientId});
        _sessionId = (s as Map)['id'] as String?;
      }
      return Api.I.post('/api/ai/sessions/$_sessionId/messages', {
        'text': text,
        'inputMode': mode,
        if (mode == 'spoken') 'voiceLanguage': Voice.localeId.substring(0, 2),
      });
    }, busy: _busy);
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (res is Map && data != null) {
        data = {
          ...data!,
          'messages': [
            ..._messages,
            if (res['question'] is Map) res['question'],
            if (res['answer'] is Map) res['answer'],
          ],
        };
      }
    });
    if (res == null && _input.text.isEmpty) _input.text = text; // keep it to try again
    _scrollToEnd();
  }

  Future<void> _voteLive(Map<String, dynamic> m, int v) async {
    final res = await runAction(context, () => Api.I.post('/api/ai/messages/${m.str('id')}/vote', {'vote': v}), busy: _busy);
    if (res is! Map || !mounted || data == null) return;
    setState(() {
      data = {
        ...data!,
        'messages': [for (final x in _messages) x.str('id') == m.str('id') ? {...x, 'vote': res['vote']} : x],
      };
    });
    if (res['vote'] != 0) toast(context, 'Thanks for the feedback');
  }

  Future<void> _clearPatient() async {
    if (!isLive) {
      setState(() => _patient = false);
      return;
    }
    final sid = _sessionId;
    if (sid != null) {
      final ok = await runAction(context, () => Api.I.patch('/api/ai/sessions/$sid', {'patientId': null}), busy: _busy);
      if (ok == null || !mounted) return;
    }
    setState(() {
      _patientId = null;
      if (data != null) data = {...data!, 'patient': null};
    });
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
    if (isLive) return; // live answers are read by [Voice.speak]
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
    if (isLive && (_pending != null || data == null)) return;
    _input.clear();
    _focus.unfocus();
    if (isLive) {
      _askLive(text);
      return;
    }
    _ask(text);
  }

  Future<void> _voice() async {
    if (isLive) {
      if (_pending != null || data == null) return;
      final said = await Voice.dictate(context, title: 'Ask MedPin AI');
      if (said != null && mounted) _askLive(said, mode: 'spoken');
      return;
    }
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

  /// The conversation from live data: questions and answers in order.
  List<Widget> _liveThread(BuildContext context) {
    final out = <Widget>[];
    var firstAnswer = true;
    for (final m in _messages) {
      if (out.isNotEmpty) out.add(const Gap(16));
      final at = F.date(m['createdAt']);
      final time = at == null ? '' : _clock(at);
      if (m['role'] == 'user') {
        final spoken = m['inputMode'] == 'spoken';
        out.add(_Question(m.str('text'), meta: spoken ? 'Spoken · $time' : time, spoken: spoken));
      } else {
        out.add(_liveAnswer(context, m, withPatient: firstAnswer));
        firstAnswer = false;
      }
    }
    final p = _pending;
    if (p != null) {
      if (out.isNotEmpty) out.add(const Gap(16));
      out
        ..add(_Question(p.$1, meta: p.$2, spoken: p.$3))
        ..add(const Gap(16))
        ..add(
          Container(
            padding: const EdgeInsets.all(18),
            decoration: MPDeco.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AnswerHead(playing: false, time: _fmt(0), onTap: () => _listen(0)),
                const Gap(12),
                Text('Looking through your records…', style: tx(15, c: MP.ink2, h: 1.55)),
              ],
            ),
          ),
        );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      scroll: false,
      header: _header(context),
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: placeholder ?? (isLive ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _liveThread(context),
        ) : Column(
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
        )),
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
    final livePatient = _livePatient?.obj('patient');
    final showPatient = isLive ? livePatient != null && livePatient.str('name').isNotEmpty : _patient;
    final patientName = isLive ? livePatient?.str('name') ?? '' : 'Priya Sharma';
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
                !showPatient
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
                                  MpAvatar(F.initials(patientName), size: 24, bg: MP.primary, fg: MP.white, fontSize: 11),
                                  const Gap(8),
                                  Flexible(
                                    child: Text(
                                      patientName,
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
                                    onTap: _clearPatient,
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

          ..._patientBlock(
            title: 'Priya Sharma, 29 F',
            conditions: 'Type 2 diabetes · PCOS',
            allergy: 'Allergic to sulfa drugs',
            score: '74',
            delta: '+3 this week',
            deltaColor: MP.green,
            findings: _findings,
            meds: _meds,
          ),
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
                    // Buttons wrap onto a second line on small phones / large text.
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SmallButton(
                            'Open profile',
                            bg: MP.primarySoft,
                            fg: MP.primary,
                            onTap: () => Nav.go(context, 'PP-Summary'),
                          ),
                          _SmallButton('Copy', border: MP.lineStrong, onTap: _copy),
                        ],
                      ),
                    ),
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

  /// "Since Sep 2026"-style month and year.
  static String _monthYear(DateTime d) {
    final s = F.dateLong(d).split(' ');
    return s.length >= 2 ? '${s[s.length - 2]} ${s.last}' : F.dayMonth(d);
  }

  static String _num(Object? v) {
    if (v is! num) return v == null ? '' : '$v';
    return v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  /// The "Talking about" patient's block from GET /api/patients/:id.
  List<Widget> _livePatientBlock(Map<String, dynamic> d) {
    final p = d.obj('patient');
    final ageSex = d1AgeSex(p);
    final conditions = [for (final c in d.list('conditions')) c.str('name')].where((x) => x.isNotEmpty).toList();
    final allergies = [for (final a in d.list('allergies')) a.str('allergen')].where((x) => x.isNotEmpty).toList();
    final hs = p.obj('healthScore');
    final delta = hs['weeklyDelta'] is num ? (hs['weeklyDelta'] as num).round() : null;
    final findings = <(String, String, String, String, Color)>[
      for (final r in d.list('abnormalResults'))
        (
          r.str('analyte', r.str('test')),
          [_num(r['value']), r.str('unit')].where((x) => x.isNotEmpty).join(r.str('unit') == '%' ? '' : ' '),
          r.str('flag') == 'low' ? 'Low' : (r.str('flag') == 'critical' ? 'Critical' : 'High'),
          [r.str('test'), if (F.date(r['collectedAt']) != null) F.dayMonth(F.date(r['collectedAt'])!)].where((x) => x.isNotEmpty).join(' · '),
          r.str('flag') == 'low' ? MP.amber : MP.red,
        ),
    ];
    final meds = <(String, String, String, String, Color)>[
      for (final m in d.list('currentMedicines'))
        (
          [m.str('name'), m.str('strength')].where((x) => x.isNotEmpty).join(' '),
          m.str('pattern', m.str('frequency')),
          [
            m.str('doctorId') == d1MyId ? 'You' : m.str('prescriber'),
            if (F.date(m['since']) != null) 'since ${_monthYear(F.date(m['since'])!)}',
          ].where((x) => x.isNotEmpty).join(' · '),
          '',
          MP.ink2,
        ),
    ];
    return _patientBlock(
      title: [p.str('name'), ageSex].where((x) => x.isNotEmpty).join(', '),
      conditions: conditions.join(' · '),
      allergy: allergies.isEmpty ? null : 'Allergic to ${F.joinAnd(allergies)}',
      score: hs['value'] is num ? '${(hs['value'] as num).round()}' : null,
      delta: delta == null ? null : '${delta >= 0 ? '+' : ''}$delta this week',
      deltaColor: delta != null && delta < 0 ? MP.red : MP.green,
      findings: findings,
      meds: meds,
    );
  }

  /// "From 3 lab reports, 2 prescriptions and the medicine log. Not a diagnosis."
  static String _sourcesLine(Map<String, dynamic> m) {
    final s = m.obj('sources');
    final labs = s.numOr('labReports').toInt();
    final rx = s.numOr('prescriptions').toInt();
    final parts = [
      if (labs > 0) d1Count(labs, 'lab report'),
      if (rx > 0) d1Count(rx, 'prescription'),
      if (s['medicineLog'] == true) 'the medicine log',
    ];
    return parts.isEmpty ? 'Check before acting — not a diagnosis.' : 'From ${F.joinAnd(parts)}. Not a diagnosis.';
  }

  /// One AI answer from live data, in the design's answer card.
  Widget _liveAnswer(BuildContext context, Map<String, dynamic> m, {required bool withPatient}) {
    final patient = withPatient ? _livePatient : null;
    final text = d1PlainText(m.str('text'));
    final vote = m.numOr('vote').toInt();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: Voice.speaking,
            builder: (_, id, _) => _AnswerHead(playing: id == m.str('id'), time: '', onTap: () => Voice.speak(text, id: m.str('id'))),
          ),
          if (patient != null) ...[const Gap(16), ..._livePatientBlock(patient), const Gap(16)] else const Gap(12),
          Text(text, style: tx(15, h: 1.55)),
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
                  child: Text(_sourcesLine(m), style: tx(12, c: MP.ink3, h: 1.4)),
                ),
                const Gap(12),
                Row(
                  children: [
                    if (_patientId != null) ...[
                      _SmallButton(
                        'Open profile',
                        bg: MP.primarySoft,
                        fg: MP.primary,
                        onTap: () => Nav.go(context, 'Patient-Profile', args: {'patientId': _patientId}),
                      ),
                      const Gap(8),
                    ],
                    _SmallButton(
                      'Copy',
                      border: MP.lineStrong,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: text));
                        toast(context, 'Copied');
                      },
                    ),
                    const Gap(8),
                    const Spacer(),
                    const Gap(8),
                    MpIconButton(
                      I.thumbUp,
                      label: 'Helpful',
                      size: 40,
                      iconSize: 18,
                      color: vote == 1 ? MP.primary : MP.ink3,
                      background: vote == 1 ? MP.primarySoft : null,
                      onTap: () => _voteLive(m, 1),
                    ),
                    const Gap(8),
                    MpIconButton(
                      I.thumbDown,
                      label: 'Not helpful',
                      size: 40,
                      iconSize: 18,
                      color: vote == -1 ? MP.primary : MP.ink3,
                      background: vote == -1 ? MP.primarySoft : null,
                      onTap: () => _voteLive(m, -1),
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

  /// Patient, health score, abnormal results and current medicines of an
  /// answer (design sample, or GET /api/patients/:id live).
  List<Widget> _patientBlock({
    required String title,
    required String conditions,
    String? allergy,
    String? score,
    String? delta,
    Color deltaColor = MP.green,
    required List<(String, String, String, String, Color)> findings,
    required List<(String, String, String, String, Color)> meds,
  }) {
    return [
          // Patient + health score
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tx(17, w: w700)),
                    if (conditions.isNotEmpty) ...[
                      const Gap(4),
                      Text(conditions, style: tx(14, c: MP.ink2)),
                    ],
                    if (allergy != null) ...[
                      const Gap(6),
                      D1Pill(allergy, bg: MP.redSoft, fg: MP.red, height: 24, padding: 10),
                    ],
                  ],
                ),
              ),
              if (score != null) ...[
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
                    Text(score, style: tx(26, w: w800, h: 1, tab: true)),
                    const Gap(2),
                    Text('Health score', style: tx(11, c: MP.ink2)),
                    if (delta != null) ...[
                      const Gap(2),
                      Text(delta, style: tx(11, w: w700, c: deltaColor)),
                    ],
                  ],
                ),
              ),
              ],
            ],
          ),
          if (findings.isNotEmpty) ...[
          const Gap(16),

          // Abnormal results
          Text('Abnormal results', style: tx(13, w: w700, c: MP.ink2)),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
            child: Column(
              children: [
                for (var i = 0; i < findings.length; i++)
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
                              Text(findings[i].$1, style: tx(14, w: w600)),
                              const Gap(1),
                              Text(findings[i].$4, style: tx(12, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(10),
                        Text(findings[i].$2, style: tx(14, w: w700, c: findings[i].$5, tab: true)),
                        const Gap(10),
                        SizedBox(
                          width: 36,
                          child: Text(
                            findings[i].$3,
                            textAlign: TextAlign.right,
                            style: tx(12, w: w700, c: findings[i].$5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ],
          if (meds.isNotEmpty) ...[
          const Gap(16),

          // Current medicines
          Text('Current medicines', style: tx(13, w: w700, c: MP.ink2)),
          for (final m in meds) ...[
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
          ],
    ];
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallButton(
                'Review urgent chat',
                bg: MP.redSoft,
                fg: MP.red,
                onTap: () => Nav.go(context, 'Patient-Thread'),
              ),
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

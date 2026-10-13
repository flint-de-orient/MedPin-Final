import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/voice.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'doctor_ai_chat.dart';
import 'patient_picker.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-AI.dc.html — "Doctor · AI Assistant (landing)".
/// Live data: GET /api/ai/sessions (Recent). Questions open Doctor-AI-Chat,
/// which starts a new conversation.
class DoctorAiScreen extends StatefulWidget {
  const DoctorAiScreen({super.key});

  @override
  State<DoctorAiScreen> createState() => _DoctorAiScreenState();
}

// tag, question
const _prompts = [
  ('Patient', 'Summarise a patient — health score, abnormal results, medicines'),
  ('Appointments', 'Who is next in today’s queue?'),
  ('Test results', 'Which patients have abnormal results this week?'),
  ('Prescriptions', 'Which prescriptions run out this week?'),
  ('Insights', 'Which patients are missing their medicines?'),
];

// question, when
const _recent = [
  ('Compare a patient’s reports with their last visit', 'Today, 8:42 AM'),
  ('Which follow-ups are due this week?', 'Yesterday'),
  ('How many consultations did I do last week?', '28 Sep'),
];

class _DoctorAiScreenState extends State<DoctorAiScreen> with LiveData {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  Future<Object?> fetch() => Api.I.get('/api/ai/sessions');

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Recent conversations: (question, when, session).
  List<(String, String, Map<String, dynamic>?)> get _recentRows {
    final d = data;
    if (d == null) return [for (final r in _recent) (r.$1, r.$2, null)];
    return [
      for (final s in d.list('items'))
        if (s.str('title').trim().isNotEmpty)
          (s.str('title').trim(), F.date(s['lastAt']) == null ? '' : d1Recent(F.date(s['lastAt'])!), s),
    ].take(3).toList();
  }

  String get _greeting {
    if (!isLive) return 'What do you need, Dr. Sen?';
    final n = Session.I.name;
    return n.isEmpty ? 'What do you need?' : 'What do you need, ${F.doctorShort(n)}?';
  }

  Future<void> _openChat([Map<String, dynamic>? args]) async {
    _input.clear();
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: 'Doctor-AI-Chat', arguments: isLive ? args : null),
        builder: (_) => const DoctorAiChatScreen(fromLanding: true),
      ),
    );
    if (mounted && isLive) reload(quiet: true);
  }

  /// Opens a new conversation that asks [text] straight away.
  void _ask(String text, {bool spoken = false}) =>
      _openChat({'text': text, if (spoken) 'inputMode': 'spoken'});

  /// "Summarise a patient": choose who, then the chat is about that patient
  /// (the AI gets their record, as far as this doctor may see it).
  Future<void> _askAboutPatient() async {
    if (!isLive) return _ask(_prompts[0].$2);
    final id = await pickPatient(context, title: 'Summarise which patient?');
    if (id == null || !mounted) return;
    _openChat({'patientId': id, 'text': 'Summarise this patient — abnormal results, medicines, adherence and what needs attention.'});
  }

  void _openSession(Map<String, dynamic>? s) {
    if (s == null) {
      _openChat();
      return;
    }
    final p = s['patientId'];
    _openChat({
      'sessionId': s.str('id'),
      if (p is Map) 'patientId': p['id'],
      if (p is String) 'patientId': p,
    });
  }

  Future<void> _voice() async {
    if (isLive) {
      final said = await Voice.dictate(context, title: 'Ask MedPin AI', hint: 'e.g. “Which patients have abnormal kidney results this month?”', purpose: 'question');
      if (said != null && mounted) _ask(said, spoken: true);
      return;
    }
    final r = await Nav.go<String>(context, 'Doctor-AI-Voice');
    if (!mounted) return;
    if (r == 'ask') _openChat();
    if (r == 'type') _focus.requestFocus();
  }

  Future<void> _history() async {
    await Nav.go(context, 'Doctor-AI-History');
    if (mounted && isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recentRows;
    return MpPage(
      header: MpHeader('AI Assistant', background: MP.white, border: true, actions: [_HistoryLink(onTap: _history)]),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Greeting
            Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MP.primary,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: MPShadow.button,
                  ),
                  child: const Ico(I.sparkles, size: 26, color: MP.white),
                ),
                const Gap(14),
                Text(
                  _greeting,
                  textAlign: TextAlign.center,
                  style: tx(24, w: w800, h: 1.2, em: -0.02),
                ),
                const Gap(10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    'Ask about any patient, appointment or prescription. Type, or tap the mic and speak.',
                    textAlign: TextAlign.center,
                    style: tx(15, c: MP.ink2, h: 1.5),
                  ),
                ),
              ],
            ),
            const Gap(28),

            // Try asking
            const _Heading('Try asking'),
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: MPDeco.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _prompts.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Tap(
                        onTap: () => i == 0 ? _askAboutPatient() : _ask(_prompts[i].$2),
                        radius: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration:
                              i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_prompts[i].$1, style: tx(12, w: w700, c: MP.primary)),
                                    const Gap(3),
                                    Text(_prompts[i].$2, style: tx(15, w: w500, h: 1.4)),
                                  ],
                                ),
                              ),
                              const Gap(12),
                              const Ico(I.arrowUpRight, size: 18, color: MP.ink3),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(28),

            // Recent
            _Heading(
              'Recent',
              trailing: Tap(onTap: _history, radius: 6, child: Text('See all', style: tx(14, w: w600, c: MP.primary))),
            ),
            const Gap(12),
            if (livePlaceholder() case final p?) p,
            if (data != null && recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('No conversations yet', style: tx(14, c: MP.ink2)),
              ),
            for (var i = 0; i < recent.length; i++) ...[
              if (i > 0) const Gap(8),
              Tap(
                onTap: () => _openSession(recent[i].$3),
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
                          Text(recent[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w600)),
                          const Gap(2),
                          Text(recent[i].$2, style: tx(13, c: MP.ink3)),
                        ],
                      ),
                    ),
                    const Gap(12),
                    const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottom: D1Composer(
        controller: _input,
        focusNode: _focus,
        hint: 'Ask anything · type @ for a patient',
        caption: 'Answers come from your records. Check before acting — not a diagnosis.',
        onSend: _ask,
        onMic: _voice,
      ),
    );
  }
}

/// Section heading: 13 / 700 / .06em uppercase #69738A, 4px side padding.
class _Heading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _Heading(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: tx(13, w: w700, c: MP.ink3, em: 0.06))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Header link: history icon + "History" (44px, padding 0 12, radius 12).
class _HistoryLink extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Ico(I.historyClock, size: 18, color: MP.primary),
              const Gap(6),
              Text('History', style: tx(14, w: w600, c: MP.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Patient-AskAI.dc.html — "Patient · Ask MedPin AI" (sheet over 'Main').
class PatientAskaiSheet extends StatefulWidget {
  const PatientAskaiSheet({super.key});

  @override
  State<PatientAskaiSheet> createState() => _PatientAskaiSheetState();
}

class _PatientAskaiSheetState extends State<PatientAskaiSheet> {
  // `chevron`: the 18px SVG has no flex-shrink: 0, so the browser squeezes it
  // to these sizes next to the long subtitles; drawn as rendered.
  static const _options = [
    (icon: I.fileText, title: 'Upload a prescription', sub: 'Photo or PDF. We add the medicines to your reminders.', chevron: 14.8),
    (icon: I.flask, title: 'Upload a test report', sub: 'We flag anything out of range and explain it simply.', chevron: 15.9),
    (icon: I.stethoscope, title: 'Find the right doctor', sub: 'Describe your symptoms and we suggest a specialist.', chevron: 15.3),
  ];
  static const _questions = ['Is HbA1c 7.2% high?', 'I missed a dose, what now?'];

  final _ask = TextEditingController();
  final _focus = FocusNode();
  bool _listening = false;

  @override
  void dispose() {
    _ask.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _option(int i) {
    if (i < 2) {
      // Prescription or test report: the add-a-record sheet.
      P1.closeThen(context, 'Records-Add');
    } else {
      // "Describe your symptoms" — straight into the box above.
      _focus.requestFocus();
    }
  }

  void _send() {
    if (_ask.text.trim().isEmpty) {
      _focus.requestFocus();
      return;
    }
    P1.closeWithToast(context, 'Sent to MedPin AI');
  }

  void _askQuestion(String q) {
    _ask.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P1SheetHeader(
              closeWidth: 32,
              title: Row(
                children: [
                  const Ico(I.sparkle, size: 20, color: MP.primary),
                  const Gap(8),
                  Flexible(child: Text('Ask MedPin AI', style: tx(20, w: w700, h: 1.25))),
                ],
              ),
              subtitle: Text(
                "Tell us how you feel or share a report. We'll explain it and point you to the right doctor.",
                style: tx(14, h: 1.45, c: MP.ink2),
              ),
            ),
            const Gap(18),
            pad(_askBox()),
            const Gap(18),
            pad(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < _options.length; i++) _optionRow(i)],
              ),
            ),
            const Gap(18),
            pad(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PEOPLE OFTEN ASK', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                  const Gap(8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final q in _questions) P1Pill(q, onTap: () => _askQuestion(q))],
                  ),
                ],
              ),
            ),
            const Gap(18),
            pad(
              Container(
                padding: const EdgeInsets.only(top: 14),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Text.rich(
                  TextSpan(
                    style: tx(13, h: 1.45, c: MP.ink3),
                    children: [
                      const TextSpan(text: 'MedPin AI gives guidance, not a diagnosis. In an emergency, '),
                      P1.link(
                        'call your clinic',
                        style: tx(13, w: w700, h: 1.45, c: MP.red),
                        onTap: () => P1.closeWithToast(context, 'Calling your clinic…'),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 112px textarea with a 2px #003399 border; Speak + Send sit in its
  /// bottom-right corner. The wrapper is 116px like the browser's (the
  /// textarea is inline-block and leaves a 4px line gap under it).
  Widget _askBox() {
    return SizedBox(
      height: 116,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 112,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              decoration: BoxDecoration(
                color: MP.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MP.primary, width: 2),
              ),
              child: Semantics(
                label: 'Describe your symptoms or ask a question',
                child: TextField(
                  controller: _ask,
                  focusNode: _focus,
                  expands: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  style: tx(16, h: 1.5),
                  cursorColor: MP.primary,
                  decoration: InputDecoration.collapsed(
                    hintText: "E.g. I've had a headache and fever for 2 days",
                    hintStyle: tx(16, h: 1.5, c: P1.placeholder),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  toggled: _listening,
                  label: 'Speak your symptoms',
                  child: P1SoftButton(
                    _listening ? 'Stop' : 'Speak',
                    icon: _listening ? I.stop : I.mic,
                    iconSize: 18,
                    padding: 14,
                    onTap: () => setState(() => _listening = !_listening),
                  ),
                ),
                const Gap(8),
                Semantics(
                  button: true,
                  label: 'Send',
                  child: Tap(
                    onTap: _send,
                    radius: 12,
                    color: MP.primary,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(child: Ico(I.send, size: 18, color: MP.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(int i) {
    final o = _options[i];
    return Tap(
      onTap: () => _option(i),
      radius: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Row(
          children: [
            MpIconTile(o.icon, size: 44, iconSize: 22, radius: 12),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.title, style: tx(16, w: w700)),
                  const Gap(2),
                  Text(o.sub, style: tx(13, h: 1.4, c: MP.ink2)),
                ],
              ),
            ),
            const Gap(14),
            Ico(I.chevronRight, size: o.chevron, color: MP.ink3),
          ],
        ),
      ),
    );
  }
}

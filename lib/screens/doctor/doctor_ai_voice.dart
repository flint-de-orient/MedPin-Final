import 'package:flutter/material.dart' hide Text;

import '../../widgets/mp.dart';
import 'common_d1.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-AI-Voice.dc.html — "Doctor · AI Assistant · voice"
/// (sheet over Doctor-AI). Pops with 'ask' (stop and ask), 'type'
/// (type instead) or null (cancel).
class DoctorAiVoiceSheet extends StatefulWidget {
  const DoctorAiVoiceSheet({super.key});

  @override
  State<DoctorAiVoiceSheet> createState() => _DoctorAiVoiceSheetState();
}

const _bars = [
  8.0,
  14.0,
  22.0,
  30.0,
  18.0,
  40.0,
  52.0,
  34.0,
  46.0,
  56.0,
  42.0,
  50.0,
  30.0,
  38.0,
  24.0,
  44.0,
  28.0,
  18.0,
  12.0,
  8.0,
  6.0,
];
const _languages = ['English (India)', 'বাংলা (Bengali)', 'हिन्दी (Hindi)'];

class _DoctorAiVoiceSheetState extends State<DoctorAiVoiceSheet> {
  String _lang = _languages.first;

  Future<void> _changeLanguage() async {
    final v = await D1Picker.show(context, title: 'Language', options: _languages, value: _lang);
    if (v != null && mounted) setState(() => _lang = v);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Column(
        children: [
          const Gap(24),
          Text('Listening…', style: tx(20, w: w700)),
          const Gap(6),
          Text(
            'Speak naturally. Say a patient’s name to focus on them.',
            textAlign: TextAlign.center,
            style: tx(14, c: MP.ink2),
          ),
          const Gap(24),

          // Live transcript
          Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 84),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(16)),
              child: Text.rich(
                TextSpan(
                  style: tx(17, h: 1.5),
                  children: [
                    const TextSpan(text: 'Which patients have abnormal kidney results '),
                    TextSpan(text: 'this month', style: tx(17, h: 1.5, c: MP.ink3)),
                  ],
                ),
              ),
            ),
          ),
          const Gap(24),

          // Level meter
          ExcludeSemantics(
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _bars.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Container(
                      width: 4,
                      height: _bars[i],
                      decoration: BoxDecoration(
                        color: i < 16 ? MP.primary : MP.lineStrong,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Gap(24),

          // Cancel · stop · type instead (grid 1fr auto 1fr)
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TextButton('Cancel', color: MP.ink2, onTap: () => Navigator.pop(context)),
                ),
              ),
              Semantics(
                button: true,
                label: 'Stop and ask',
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, 'ask'),
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: MP.primary,
                      shape: BoxShape.circle,
                      // CSS: 0 0 0 8px #EBF1FB (on top), 0 6px 16px rgba(0,51,153,.24).
                      boxShadow: [
                        BoxShadow(color: Color(0x3D003399), offset: Offset(0, 6), blurRadius: 16),
                        BoxShadow(color: MP.primarySoft, spreadRadius: 8),
                      ],
                    ),
                    child: const Ico(I.stop, size: 22, color: MP.white, filled: true),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _TextButton('Type instead', color: MP.primary, onTap: () => Navigator.pop(context, 'type')),
                ),
              ),
            ],
          ),
          const Gap(24),

          // Language
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(_lang, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink3))),
              const Gap(8),
              Text('·', style: tx(13, c: MP.ink3)),
              const Gap(8),
              Tap(
                onTap: _changeLanguage,
                radius: 6,
                child: Text('Change language', style: tx(13, w: w600, c: MP.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Transparent 44px text button (padding 0 12, radius 12, 15 / 600).
class _TextButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _TextButton(this.label, {required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: tx(15, w: w600, c: color))]),
        ),
      ),
    );
  }
}

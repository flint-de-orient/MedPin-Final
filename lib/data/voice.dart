import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../widgets/mp.dart';
import 'api.dart';
import 'live.dart';
import 'session.dart';
import '../widgets/i18n.dart';

/// Voice in MedPin: speak-to-type (speech to text) in English, Bengali or
/// Hindi; reading answers aloud (text to speech); and recording / playing
/// voice notes in chats.
class Voice {
  Voice._();

  static final _stt = SpeechToText();
  static bool? _sttReady;

  /// "en-IN" / "bn-IN" / "hi-IN" from the account language.
  static String get localeId => switch (Session.I.user['language']) { 'bn' => 'bn-IN', 'hi' => 'hi-IN', _ => 'en-IN' };

  /// The phone's own name for [want] ("en_IN" on Android, "en-IN" on iOS), else
  /// the same language in another region, else [want] as is.
  static Future<String> bestLocale(String want) async {
    try {
      final all = (await _stt.locales()).map((l) => l.localeId).toList();
      String n(String s) => s.toLowerCase().replaceAll('_', '-');
      final exact = all.where((l) => n(l) == n(want));
      if (exact.isNotEmpty) return exact.first;
      final lang = n(want).split('-').first;
      final same = all.where((l) => n(l).split('-').first == lang).toList()
        ..sort((a, b) => (n(b).endsWith('-in') ? 1 : 0) - (n(a).endsWith('-in') ? 1 : 0));
      if (same.isNotEmpty) return same.first;
    } catch (_) {}
    return want;
  }

  /// Medicine names and medical words the recogniser should expect (catalog).
  static List<String>? _phrases;
  static Future<List<String>> phrases() async {
    if (_phrases != null) return _phrases!;
    try {
      final r = await Api.I.get('/api/me/voice/phrases');
      _phrases = [for (final p in (r is Map ? r['phrases'] as List? : null) ?? const []) '$p'];
    } catch (_) {
      return const [];
    }
    return _phrases!;
  }

  static Future<bool> _initStt() async {
    if (_sttReady == true) return true;
    try {
      _sttReady = await _stt.initialize(onError: (_) {});
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady!;
  }

  /// Opens the listening sheet; returns what was said (null if cancelled).
  /// [purpose]: 'medicine' (doctor dictating a medicine), 'question', 'symptoms'
  /// or 'note' — misheard medical words are corrected for it before use.
  static Future<String?> dictate(BuildContext context, {String title = 'Speak now', String? hint, String purpose = 'note'}) async {
    if (!await _initStt()) {
      if (context.mounted) toast(context, 'Speech input needs microphone access and Google speech services on this phone');
      return null;
    }
    if (!context.mounted) return null;
    return openSheet<String>(context, (_) => _ListenSheet(title: title, hint: hint, purpose: purpose));
  }

  // ── Read aloud ──
  static final _tts = FlutterTts();
  static final speaking = ValueNotifier<String?>(null);

  /// The language of [text] by its script (a Bengali answer is read in Bengali
  /// even when the app is in English).
  static String languageOf(String text) {
    final bn = RegExp(r'[\u0980-\u09FF]').allMatches(text).length;
    final hi = RegExp(r'[\u0900-\u097F]').allMatches(text).length;
    final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
    if (bn > latin / 3 && bn >= hi) return 'bn-IN';
    if (hi > latin / 3) return 'hi-IN';
    return 'en-IN';
  }

  /// Text as it should be heard: no markdown, links or emoji; medical shorthand
  /// read out ("1-0-1" → "1 in the morning and 1 at night", "mg" → "milligram").
  static String spoken(String text) {
    var s = text
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'[*#_`>|~]'), ' ')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), ' ')
        .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '');
    s = s.replaceAllMapped(RegExp(r'\b(\d)\s*-\s*(\d)\s*-\s*(\d)\b'), (m) {
      final parts = [
        if (m[1] != '0') '${m[1]} in the morning',
        if (m[2] != '0') '${m[2]} in the afternoon',
        if (m[3] != '0') '${m[3]} at night',
      ];
      return parts.isEmpty ? m[0]! : parts.join(' and ');
    });
    const words = {
      r'\bmg\b': 'milligram', r'\bmcg\b': 'microgram', r'\bml\b': 'millilitre', r'\bIU\b': 'units',
      r'\bmmHg\b': 'millimetres of mercury', r'\bmg/dL\b': 'milligrams per decilitre', r'\bmmol/L\b': 'millimoles per litre',
      r'\bHbA1c\b': 'H B A 1 C', r'\bBP\b': 'blood pressure', r'\bSOS\b': 'when needed', r'\bOD\b': 'once a day',
      r'\bBD\b': 'twice a day', r'\bTDS\b': 'three times a day', r'\bSpO2\b': 'oxygen level', r'\bSpO₂\b': 'oxygen level',
      r'\bTSH\b': 'T S H', r'\bCBC\b': 'C B C', r'\bECG\b': 'E C G', r'\bRx\b': 'prescription', r'\be\.g\.': 'for example',
      r'\bDr\.': 'Doctor', r'₹\s?': 'rupees ',
    };
    words.forEach((k, v) => s = s.replaceAll(RegExp(k), v));
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The best installed voice for [locale] (network / higher quality first).
  static final _voices = <String, Map<String, String>?>{};
  static Future<Map<String, String>?> _voiceFor(String locale) async {
    if (_voices.containsKey(locale)) return _voices[locale];
    Map<String, String>? best;
    try {
      final all = ((await _tts.getVoices) as List? ?? const []).whereType<Map>().map((v) => v.map((k, x) => MapEntry('$k', '$x'))).toList();
      String n(String? s) => (s ?? '').toLowerCase().replaceAll('_', '-');
      final mine = all.where((v) => n(v['locale']) == n(locale)).toList();
      int rank(Map<String, String> v) {
        final name = n(v['name']);
        final q = n(v['quality']);
        return (q.contains('very') ? 4 : q.contains('high') ? 3 : 0) + (name.contains('network') ? 2 : 0);
      }
      mine.sort((a, b) => rank(b) - rank(a));
      if (mine.isNotEmpty) best = {'name': mine.first['name']!, 'locale': mine.first['locale']!};
    } catch (_) {}
    return _voices[locale] = best;
  }

  /// Reads [text] aloud ([id] marks which answer is playing); again = stop.
  static Future<void> speak(String text, {String? id}) async {
    if (speaking.value == (id ?? text)) return stopSpeaking();
    await _tts.stop();
    final key = id ?? text;
    speaking.value = key;
    final locale = languageOf(text);
    try {
      await _tts.setLanguage(locale);
      final voice = await _voiceFor(locale);
      if (voice != null) await _tts.setVoice(voice);
      await _tts.setSpeechRate(locale == 'en-IN' ? 0.47 : 0.44);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      // Sentence by sentence (long answers would be cut off), stopping if asked to.
      final parts = spoken(text).split(RegExp(r'(?<=[.!?।])\s+')).where((p) => p.trim().isNotEmpty);
      var chunk = '';
      for (final p in [...parts, '']) {
        if (p.isNotEmpty && (chunk.length + p.length) < 600) {
          chunk = chunk.isEmpty ? p : '$chunk $p';
          continue;
        }
        if (chunk.isNotEmpty) {
          if (speaking.value != key) return;
          await _tts.speak(chunk);
        }
        chunk = p;
      }
    } catch (_) {}
    if (speaking.value == key) speaking.value = null;
  }

  static Future<void> stopSpeaking() async {
    await _tts.stop();
    speaking.value = null;
  }

  /// Records a voice note (sheet with timer, Stop / Send). Returns the file to upload.
  static Future<({UploadFile file, int seconds})?> recordNote(BuildContext context) async {
    final rec = AudioRecorder();
    if (!await rec.hasPermission()) {
      if (context.mounted) toast(context, 'Allow microphone access to send voice notes');
      await rec.dispose();
      return null;
    }
    if (!context.mounted) return null;
    final file = await openSheet<({UploadFile file, int seconds})>(context, (_) => _RecordSheet(recorder: rec));
    await rec.dispose();
    return file;
  }
}

class _ListenSheet extends StatefulWidget {
  final String title;
  final String? hint;
  final String purpose;
  const _ListenSheet({required this.title, this.hint, this.purpose = 'note'});

  @override
  State<_ListenSheet> createState() => _ListenSheetState();
}

class _ListenSheetState extends State<_ListenSheet> {
  String _text = '';
  bool _listening = false;
  bool _checking = false;
  final _edit = TextEditingController();
  late String _locale = Voice.localeId;
  static const _langs = [('en-IN', 'English'), ('bn-IN', 'বাংলা'), ('hi-IN', 'हिन्दी')];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    Voice._stt.stop();
    _edit.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _listening = true;
      _text = '';
      _edit.text = '';
    });
    final locale = await Voice.bestLocale(_locale);
    final phrases = widget.purpose == 'medicine' ? await Voice.phrases() : const <String>[];
    if (!mounted) return;
    await Voice._stt.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        if (!r.finalResult) {
          setState(() => _text = r.recognizedWords);
          return;
        }
        // The recogniser's most confident guess, then misheard medical words fixed.
        final alts = [...r.alternates]..sort((a, b) => b.confidence.compareTo(a.confidence));
        final best = alts.isNotEmpty && alts.first.recognizedWords.trim().isNotEmpty ? alts.first.recognizedWords : r.recognizedWords;
        setState(() {
          _text = best;
          _edit.text = best;
          _listening = false;
        });
        _clean(best, [for (final a in alts) a.recognizedWords]);
      },
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 90),
        // Doctors pause to think between a name and its dose.
        pauseFor: Duration(seconds: widget.purpose == 'medicine' ? 6 : 5),
        cancelOnError: true,
        autoPunctuation: true,
        contextualPhrases: phrases.isEmpty ? null : phrases.take(100).toList(),
      ),
    );
  }

  /// POST /api/me/voice/clean: catalog names and MedPin AI fix misheard words.
  Future<void> _clean(String text, List<String> alternates) async {
    if (!isLive || text.trim().isEmpty) return;
    setState(() => _checking = true);
    try {
      final r = await Api.I.post('/api/me/voice/clean', {
        'text': text,
        'alternates': alternates.take(5).toList(),
        'purpose': widget.purpose,
        'language': _locale.split('-').first,
      });
      final fixed = r is Map ? '${r['text'] ?? ''}'.trim() : '';
      // Only if the doctor hasn't started editing it.
      if (mounted && fixed.isNotEmpty && _edit.text == text) {
        setState(() {
          _text = fixed;
          _edit.text = fixed;
        });
      }
    } catch (_) {
      // Offline: what was heard stays, and can be edited.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _switch(String locale) async {
    await Voice._stt.stop();
    setState(() {
      _locale = locale;
      _text = '';
    });
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, children: [for (final l in _langs) MpChip(l.$2, selected: _locale == l.$1, onTap: () => _switch(l.$1))]),
          const Gap(16),
          Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _listening ? MP.primary : MP.line)),
            // While listening: the words as they come. After: the text, editable (fix a word before using it).
            child: _listening || _text.isEmpty
                ? Text(
                    _text.isEmpty ? (_listening ? (widget.hint ?? 'Listening…') : "Didn't catch that. Tap Speak again.") : _text,
                    style: tx(17, h: 1.5, c: _text.isEmpty ? MP.ink3 : MP.ink),
                  )
                : TextField(
                    controller: _edit,
                    maxLines: null,
                    style: tx(17, h: 1.5),
                    cursorColor: MP.primary,
                    onChanged: (v) => setState(() => _text = v),
                    decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                  ),
          ),
          if (_checking) ...[
            const Gap(8),
            Text('Checking medical words…', style: tx(13, c: MP.ink3)),
          ] else if (!_listening && _text.isNotEmpty) ...[
            const Gap(8),
            Text('Tap the text to fix a word.', style: tx(13, c: MP.ink3)),
          ],
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: MpButton(_listening ? 'Listening…' : 'Speak again', kind: MpBtn.secondary, icon: I.mic, onTap: _listening ? null : _start),
              ),
              const Gap(12),
              Expanded(
                child: MpButton('Use this', onTap: _text.trim().isEmpty || _listening ? null : () => Navigator.pop(context, _edit.text.trim().isEmpty ? _text.trim() : _edit.text.trim())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordSheet extends StatefulWidget {
  final AudioRecorder recorder;
  const _RecordSheet({required this.recorder});

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _clock = Stopwatch();
  Timer? _tick;
  String? _path;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_recording) widget.recorder.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await widget.recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
    _clock
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      if (_clock.elapsed >= const Duration(minutes: 2)) _stop(); // notes are short
    });
    setState(() => _recording = true);
  }

  Future<void> _stop() async {
    _tick?.cancel();
    _clock.stop();
    _path = await widget.recorder.stop();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _send() async {
    if (_recording) await _stop();
    final path = _path;
    if (path == null || _clock.elapsed < const Duration(milliseconds: 700)) {
      if (mounted) toast(context, 'Hold on a little longer to record a message');
      return;
    }
    final bytes = await File(path).readAsBytes();
    if (mounted) Navigator.pop(context, (file: UploadFile(bytes, 'voice-note.m4a', 'audio/mp4'), seconds: _clock.elapsed.inSeconds.clamp(1, 600)));
  }

  @override
  Widget build(BuildContext context) {
    final e = _clock.elapsed;
    final time = '${e.inMinutes}:${(e.inSeconds % 60).toString().padLeft(2, '0')}';
    return MpSheet(
      title: 'Voice message',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: MpIconTile(I.mic, size: 72, iconSize: 32, radius: 999, bg: _recording ? MP.redSoft : MP.primarySoft, fg: _recording ? MP.red : MP.primary)),
          const Gap(12),
          Text(_recording ? 'Recording · $time' : 'Recorded · $time', textAlign: TextAlign.center, style: tx(18, w: w600, tab: true)),
          const Gap(20),
          Row(
            children: [
              Expanded(child: MpButton(_recording ? 'Stop' : 'Record again', kind: MpBtn.secondary, onTap: _recording ? _stop : _start)),
              const Gap(12),
              Expanded(child: MpButton('Send', icon: I.send, onTap: _send)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Plays chat voice notes inside the app, one at a time.
class VoiceNotes {
  VoiceNotes._();
  static AudioPlayer? _player;

  /// The link now playing (null when nothing plays).
  static final playing = ValueNotifier<String?>(null);

  /// Plays [url]; tapping the same note again stops it.
  static Future<void> toggle(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return toast(context, 'This voice note is not available');
    final p = _player ??= AudioPlayer()
      ..playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) stop();
      });
    if (playing.value == url) return stop();
    try {
      playing.value = url;
      await p.setUrl(url);
      await p.play();
    } catch (e) {
      debugPrint('voice note: $e');
      playing.value = null;
      if (context.mounted) toast(context, "Couldn't play this voice note");
    }
  }

  static Future<void> stop() async {
    playing.value = null;
    await _player?.stop();
  }
}

/// Play / stop row for a voice note inside a chat bubble.
class VoiceNoteChip extends StatelessWidget {
  final String? url;
  final num? seconds;
  final Color color;
  const VoiceNoteChip({super.key, required this.url, this.seconds, this.color = MP.ink});

  @override
  Widget build(BuildContext context) {
    final s = (seconds ?? 0).round();
    final label = s == 0 ? 'Voice message' : 'Voice message · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceNotes.playing,
      builder: (context, now, _) {
        final on = now != null && now == url;
        return Semantics(
          button: true,
          label: tr(context, on ? 'Stop voice message' : 'Play voice message'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => VoiceNotes.toggle(context, url),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Ico(on ? I.pause : I.play, size: 20, color: color, filled: true),
                const Gap(8),
                Flexible(child: Text(on ? 'Playing…' : label, style: tx(15, h: 1.45, c: color, tab: true))),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Records a voice note and sends it into conversation [convId].
/// Returns true once sent.
Future<bool> sendVoiceNote(BuildContext context, String? convId, {ValueNotifier<bool>? busy, Map<String, String> fields = const {}}) async {
  if (convId == null) return false;
  final note = await Voice.recordNote(context);
  if (note == null || !context.mounted) return false;
  final ok = await runAction(
    context,
    () => Api.I.upload('/api/conversations/$convId/messages', files: {'file': [note.file]}, fields: {'durationSec': '${note.seconds}', ...fields}),
    busy: busy,
  );
  return ok != null;
}

/// Dictates into [c]: adds what was said after any text already there.
/// Returns the words heard (null if nothing).
Future<String?> dictateInto(BuildContext context, TextEditingController c, {String title = 'Speak now'}) async {
  final said = await Voice.dictate(context, title: title);
  if (said == null) return null;
  final before = c.text.trimRight();
  c.text = before.isEmpty ? said : '$before $said';
  c.selection = TextSelection.collapsed(offset: c.text.length);
  return said;
}

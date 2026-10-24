import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/push.dart';
import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../widgets/chat_photo.dart';
import '../../widgets/file_view.dart';
import '../../widgets/chat_tools.dart';
import '../../widgets/fee_actions.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import '../../widgets/chat_extras.dart';
import '../../widgets/i18n.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// Design: Patient-DoctorChat.dc.html — "Patient · chat with doctor".
///
/// Live data: the clinic's care thread (GET /api/conversations/:id/messages)
/// and the doctor from GET /api/patient/my-doctors. Opened with
/// `args: {'doctorId': …, 'conversationId': …}`; without a thread id it opens
/// one with POST /api/patient/conversations. Sending: POST
/// /api/conversations/:id/messages (text, or a photo / PDF as `file`).
class PatientDoctorchatScreen extends StatefulWidget {
  const PatientDoctorchatScreen({super.key});

  @override
  State<PatientDoctorchatScreen> createState() => _PatientDoctorchatScreenState();
}

const _replies = ['Thank you', "Share today's sugar", 'Running late'];

const _r16 = Radius.circular(16);
const _r4 = Radius.circular(4);

/// A pushpin (the clinic's pinned message).
const _pushpin = '<path d="M12 17v5M9 3h6l-1 6 3 3v2H7v-2l3-3z"/>';

/// Doctor bubbles: 16 16 16 4; patient bubbles: 16 16 4 16.
const _theirs = BorderRadius.only(topLeft: _r16, topRight: _r16, bottomRight: _r16, bottomLeft: _r4);
const _mine = BorderRadius.only(topLeft: _r16, topRight: _r16, bottomRight: _r4, bottomLeft: _r16);

class _PatientDoctorchatScreenState extends State<PatientDoctorchatScreen> with LiveData {
  final _text = TextEditingController();
  final _sent = <String>[];
  final _busy = ValueNotifier(false);
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _showReplies = true;
  String? _convId;
  String? _readUpTo;

  // Sent instantly: the message shows at once ("Sending…"), the server
  // confirms it, and MedPin AI's reply arrives a moment later while
  // "MedPin AI is typing…" shows.
  // Each with its own id (sent to the server, which saves a retried message once).
  // Kept per chat for this session, so a failed message isn't lost on Back.
  static final _outboxes = <String, List<({String id, String text, bool failed})>>{};
  var _outbox = <({String id, String text, bool failed})>[];
  static int _seq = 0;
  static String _newId() => 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  /// The server time of the last full load (sent back as ?since= on the 4-second check).
  String? _at;

  /// Older messages loaded with "Show earlier messages" (the server sends the newest 100).
  List<Map<String, dynamic>> _older = const [];
  bool _loadingOlder = false;
  bool _noOlder = false;
  /// Someone at the clinic typing now ("Dr. Sen is typing…").
  Object? _typing;
  late final _typer = TypingPinger(() => _convId);
  final _transcripts = <String, String>{};

  /// The newest message id shown, to keep your place when a new one arrives while you read older ones.
  String? _newestShown;

  /// Replying to this message (long-press → Reply).
  Map<String, dynamic>? _replyTo;
  bool _aiTyping = false;
  Timer? _aiWait;
  int _aiChecks = 0;

  /// MedPin AI said it would answer but nothing came: the clinic will.
  bool _aiNoAnswer = false;
  bool _handingOff = false;

  /// The doctor this chat is with (a row of my-doctors).
  Map<String, dynamic> _doctor = const {};

  @override
  // New messages also arrive at once by a silent push (Push → LiveBus); this is the backup.
  Duration? get refreshEvery => const Duration(seconds: 4);

  @override
  void dispose() {
    VoiceNotes.stop();
    if (Push.I.openChat == _convId) Push.I.openChat = null;
    _aiWait?.cancel();
    _scroll.dispose();
    _text.dispose();
    _busy.dispose();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    final args = p2DoctorArgs(context);
    final doctorId = args['doctorId'];
    if (_doctor.isEmpty) {
      final mine = [
        for (final d in (await Api.I.get('/api/patient/my-doctors') as List? ?? const [])) (d as Map).cast<String, dynamic>(),
      ];
      final convId = args['conversationId'];
      bool isDoctor(Map<String, dynamic> d) => d.str('role') == 'doctor';
      // By doctor; else the doctor whose clinic thread this is (from a notification); else the first doctor.
      // A doctor named (a notification says who wrote): that doctor, never someone else.
      _doctor = (doctorId != null ? mine.where((d) => d.str('doctorId') == doctorId).firstOrNull ?? const <String, dynamic>{'_missing': true} : null) ??
          (convId != null ? mine.where((d) => isDoctor(d) && d.str('conversationId') == convId).firstOrNull : null) ??
          (convId != null ? mine.where((d) => d.str('conversationId') == convId).firstOrNull : null) ??
          (convId == null ? mine.where(isDoctor).firstOrNull : null) ??
          (convId == null && mine.isNotEmpty ? mine.first : const <String, dynamic>{});
    }
    _convId ??= args['conversationId'] ?? (_doctor['conversationId'] as String?);
    if (_convId == null) {
      final id = doctorId ?? _doctor.str('doctorId');
      if (id.isEmpty) throw const ApiException(404, 'NO_DOCTOR', 'You have no doctors to chat with yet.');
      final c = await Api.I.post('/api/patient/conversations', {'doctorId': id}) as Map;
      _convId = '${c['id'] ?? c['_id']}';
    }
    if (_outboxes[_convId!] != null && !identical(_outbox, _outboxes[_convId!])) _outbox = _outboxes[_convId!]!;
    _outboxes[_convId!] = _outbox;
    // On screen (not covered by another screen, app in front): this chat's notifications show
    // in the chat itself, and reading it counts as "Seen".
    if (!mounted) return data;
    final route = ModalRoute.of(context);
    final front = (route?.isCurrent ?? true) && (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;
    if (front) {
      Push.I.openChat = _convId;
    } else if (Push.I.openChat == _convId) {
      Push.I.openChat = null;
    }
    // The 4-second check: nothing changed since the last load → keep what's on screen.
    final prev = data;
    final res = (await Api.I.get('/api/conversations/$_convId/messages', query: {if (_at != null && prev != null) 'since': _at!}) as Map).cast<String, dynamic>();
    _typing = res['typing'];
    if (res['unchanged'] == true && prev != null) {
      _at = '${res['at']}';
      return prev;
    }
    if (res['at'] != null) _at = '${res['at']}';
    // Earlier pages the patient loaded stay above the newest messages.
    final fresh = res.list('items');
    if (_older.isNotEmpty) {
      final ids = {for (final m in fresh) m.str('id')};
      res['items'] = [for (final m in _older) if (!ids.contains(m.str('id'))) m, ...fresh];
    }
    // Messages the server has (a retry that was saved after all) leave the outbox.
    final sentIds = {for (final m in fresh) if (m.str('clientId').isNotEmpty) m.str('clientId')};
    _outbox.removeWhere((o) => sentIds.contains(o.id));
    // Read receipt only when something new came in, and only while the chat is on screen.
    final newest = fresh.isEmpty ? null : fresh.last.str('id');
    if (front && newest != _readUpTo) {
      _readUpTo = newest;
      Api.I.post('/api/conversations/$_convId/read', const {}).catchError((_) => null);
    }
    _keepPlace(newest);
    return res;
  }

  /// A new message arrived while the patient reads older ones: keep what they're reading in place.
  void _keepPlace(String? newest) {
    final grew = _newestShown != null && newest != _newestShown;
    _newestShown = newest;
    if (!grew || !_scroll.hasClients || _scroll.offset < 24) return;
    final before = _scroll.position.maxScrollExtent;
    final offset = _scroll.offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final added = _scroll.position.maxScrollExtent - before;
      if (added > 0) _scroll.jumpTo(offset + added);
    });
  }

  /// "Show earlier messages": the page before the oldest one shown.
  Future<void> _loadOlder() async {
    final items = data?.list('items') ?? const [];
    if (_loadingOlder || items.isEmpty || _convId == null) return;
    setState(() => _loadingOlder = true);
    try {
      final res = (await Api.I.get('/api/conversations/$_convId/messages', query: {'before': items.first.str('createdAt'), 'limit': '50'}) as Map).cast<String, dynamic>();
      if (!mounted) return;
      final page = res.list('items');
      setState(() {
        _older = [...page, ..._older];
        _noOlder = page.length < 50;
        data = {...data!, 'items': [...page, ...items]};
        _loadingOlder = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      toast(context, e.message);
    }
  }

  String get _name =>
      data == null ? 'Dr. Arjun Sen' : _doctor.str('name', data!.obj('conversation').str('practiceName', 'Your clinic'));
  String get _short => data == null ? 'Dr. Sen' : p2ShortName(_name);

  void _send(String message, {bool fromField = false}) {
    final m = message.trim();
    if (m.isEmpty) return;
    if (data != null) {
      _sendLive(m, clearField: fromField);
      return;
    }
    setState(() {
      _sent.add(m);
      _showReplies = false;
      _text.clear();
    });
  }

  Future<void> _sendLive(String text, {String? retryId, bool clearField = false}) async {
    final id = retryId ?? _newId();
    setState(() {
      _outbox.removeWhere((m) => m.id == id);
      _outbox.add((id: id, text: text, failed: false));
      _showReplies = false;
      // A quick reply doesn't wipe what the patient was typing.
      if (clearField) _text.clear();
    });
    _aiNoAnswer = false;
    if (_scroll.hasClients) _scroll.jumpTo(0); // the list is reversed: 0 is the newest
    try {
      final quote = _replyTo;
      if (quote != null) setState(() => _replyTo = null);
      final res = await Api.I.post('/api/conversations/$_convId/messages', {'text': text, 'clientId': id, if (quote != null) 'replyToId': quote.str('id')});
      _typer.stop();
      if (!mounted) return;
      _at = null; // load in full: our message is new
      await reload(quiet: true);
      if (!mounted) return;
      setState(() {
        _outbox.removeWhere((m) => m.id == id);
        if (res is Map && res['aiPending'] == true) _waitForAi();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final i = _outbox.indexWhere((m) => m.id == id);
        if (i >= 0) _outbox[i] = (id: id, text: text, failed: true);
      });
    }
  }

  /// Answered: the newest message is a reply (AI, doctor or clinic), not ours.
  bool get _answered {
    final items = data?.list('items') ?? const [];
    return items.isNotEmpty && items.last.str('senderType') != 'patient';
  }

  /// Shows "MedPin AI is typing…" and checks for the reply every 1.5 s (up to ~30 s).
  void _waitForAi() {
    _aiWait?.cancel();
    if (_answered) return; // it was quicker than us
    _aiTyping = true;
    _aiChecks = 0;
    _aiWait = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      _aiChecks++;
      await reload(quiet: true);
      if (!mounted) return t.cancel();
      if (_answered || _aiChecks >= 20) {
        t.cancel();
        setState(() {
          _aiTyping = false;
          _aiNoAnswer = !_answered;
        });
      }
    });
  }

  /// "Talk to the clinic": MedPin AI steps out of this chat and the clinic is told.
  Future<void> _handoff() async {
    if (_handingOff || _convId == null) return;
    setState(() => _handingOff = true);
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$_convId/handoff', const {}));
    if (!mounted) return;
    setState(() => _handingOff = false);
    if (ok == null) return;
    toast(context, 'The clinic has been told. Someone will reply here.');
    await reload(quiet: true);
  }

  bool get _humanRequested => data?.obj('conversation')['humanRequested'] == true;

  /// Long-press a message: copy it, reply to it, hide it for you, or delete your own for everyone.
  Future<void> _actions(Map<String, dynamic> m) async {
    if (m['deleted'] == true || data == null) return;
    final mine = m['mine'] == true;
    final text = m.str('text');
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MP.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in [
              if (text.isNotEmpty) 'Copy',
              'Reply',
              if (ChatExtras.canEdit(m)) 'Edit',
              if (m.str('senderType') != 'ai') 'Forward',
              if (m.str('kind') == 'voice' && m.obj('voice').str('transcript').isEmpty && !_transcripts.containsKey(m.str('id'))) 'Show text',
              'Hide for me',
              if (mine) 'Delete for everyone',
            ])
              Tap(
                onTap: () => Navigator.of(ctx).pop(a),
                radius: 0,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.centerLeft,
                  child: Text(a, style: a == 'Delete for everyone' ? tx(16, w: w600, c: MP.red) : tx(16)),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final id = m.str('id');
    switch (choice) {
      case 'Copy':
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) toast(context, 'Copied');
        return;
      case 'Reply':
        setState(() => _replyTo = m);
        return;
      case 'Hide for me':
        final ok = await runAction(context, () => Api.I.post('/api/conversations/$_convId/messages/$id/hide'));
        if (ok != null && mounted) toast(context, 'Message hidden');
      case 'Edit':
        await ChatExtras.edit(context, convId: _convId!, message: m);
      case 'Forward':
        await ChatExtras.forward(context, convId: _convId!, messageId: id);
        return;
      case 'Show text':
        final t = await ChatExtras.transcribe(context, convId: _convId!, messageId: id);
        if (t != null && mounted) setState(() => _transcripts[id] = t);
        return;
      default:
        final ok = await runAction(context, () => Api.I.delete('/api/conversations/$_convId/messages/$id'));
        if (ok != null && mounted) toast(context, 'Deleted for everyone');
    }
    _at = null;
    if (mounted) await reload(quiet: true);
  }

  /// "Dr. Sen: Please come fasting" — the quoted message under a reply.
  String _quoteOf(Map<String, dynamic>? q) {
    if (q == null) return '';
    final who = q.str('senderType') == 'patient' || q['mine'] == true ? tr(context, 'You') : _sender(q);
    final what = q['deleted'] == true ? tr(context, 'This message was deleted') : q.str('text', q.str('kind') == 'voice' ? 'Voice message' : 'Photo or file');
    return '$who: $what';
  }

  Future<void> _voiceNote() async {
    if (data == null) return p2Missing(context, 'Voice recording');
    if (!await sendVoiceNote(context, _convId, busy: _busy) || !mounted) return;
    setState(() => _showReplies = false);
    await reload(quiet: true);
  }

  Future<void> _attach() async {
    if (data == null) {
      Nav.go(context, 'Records-Add');
      return;
    }
    final file = await Files.chooseSource(context, title: 'Share a report, prescription or photo');
    if (file == null || !mounted) return;
    final text = _text.text.trim();
    final ok = await runAction(
      context,
      () => Api.I.upload('/api/conversations/$_convId/messages', files: {'file': [file]}, fields: {if (text.isNotEmpty) 'text': text}),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    setState(() {
      _showReplies = false;
      _text.clear();
    });
    await reload(quiet: true);
  }

  Future<void> _search() async {
    if (data == null) return p2Missing(context, 'Chat search');
    final id = await ChatExtras.search(context, convId: _convId!);
    if (id == null || !mounted) return;
    for (var i = 0; i < 12 && !data!.list('items').any((m) => m.str('id') == id) && !_noOlder; i++) {
      await _loadOlder();
      if (!mounted) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final c = _keys[id]?.currentContext;
    if (c != null && c.mounted) {
      Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.3);
    } else if (mounted) {
      toast(context, 'That message is no longer in this chat');
    }
  }

  /// This chat: mute its notifications, or clear it on your phones.
  Future<void> _chatMenu() async {
    if (data == null) return;
    final conv = data!.obj('conversation');
    final muted = F.date(conv['mutedUntil'])?.isAfter(DateTime.now()) == true;
    final pick = await openSheet<String>(
      context,
      (c) => MpSheet(
        title: 'This chat',
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: VGap(gap: 10, children: [
            MpButton(muted ? 'Notifications muted · change' : 'Mute notifications', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'mute')),
            MpButton('Clear chat', kind: MpBtn.ghost, onTap: () => Navigator.pop(c, 'clear')),
          ]),
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final bool changed;
    if (pick == 'mute') {
      changed = await ChatExtras.mute(context, convId: _convId!, mutedUntil: F.date(conv['mutedUntil']));
    } else {
      changed = await ChatExtras.clear(context, convId: _convId!);
    }
    if (changed && mounted) {
      _at = null;
      if (pick == 'clear') _older.clear();
      reload(quiet: true);
    }
  }

  Future<void> _detail() async {
    await Nav.go(context, 'Patient-DoctorDetail', args: data == null ? null : {'doctorId': _doctor.str('doctorId')});
    if (data != null) reload(quiet: true);
  }

  String _sender(Map<String, dynamic> m) {
    final type = m.str('senderType');
    if (type == 'ai') return 'MedPin AI';
    final s = m['senderId'];
    if (s is Map && s['name'] != null) return p2ShortName('${s['name']}');
    if (type == 'doctor') return _short;
    return 'Clinic';
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (F.sameDay(d, now)) return 'Today';
    if (F.sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return F.dayMonth(d);
  }

  /// Live thread: day labels, bubbles, file cards and their meta lines.
  List<Widget> _liveItems() {
    final out = <Widget>[];
    DateTime? lastDay;
    final msgs = data!.list('items');
    // The clinic's pinned note (visit instructions, a dose to remember): always at the top.
    final pinned = data!.obj('pinned');
    if (pinned.isNotEmpty && pinned.str('text').isNotEmpty) {
      out.add(Tap(
        onTap: () {
          final c = _keys[pinned.str('id')]?.currentContext;
          if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), alignment: 0.3);
        },
        radius: 12,
        color: MP.primarySoft,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Ico(_pushpin, size: 16, color: MP.primary)),
          const Gap(8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pinned by the clinic', style: tx(12, w: w700, c: MP.primary)),
              UserText(pinned.str('text'), maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, h: 1.4)),
            ]),
          ),
        ]),
      ));
    }
    // The server sends the newest 100; older ones on request.
    if (msgs.length >= 100 && !_noOlder) {
      out.add(Center(
        child: P2Box(
          onTap: _loadingOlder ? null : _loadOlder,
          height: 36,
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: MP.white,
          border: MP.lineStrong,
          child: Text(_loadingOlder ? 'Loading…' : 'Show earlier messages', style: tx(13, w: w600, c: MP.primary)),
        ),
      ));
    }
    for (final m in msgs) {
      final at = F.date(m['createdAt']);
      if (at != null && (lastDay == null || !F.sameDay(lastDay, at))) {
        out.add(_day(_dayLabel(at), EdgeInsets.only(top: lastDay == null ? 0 : 4, bottom: 4)));
        lastDay = at;
      }
      final mine = m['mine'] == true || m.str('senderType') == 'patient';
      final time = at == null ? '' : F.time(at);
      final text = m['deleted'] == true ? 'This message was deleted' : m.str('text');
      final kind = m.str('kind');
      if (kind == 'attachment' && m['deleted'] != true && m.obj('record').isEmpty && (ReportFile.fromApi(m['attachment'])?.isImage ?? false)) {
        // A photo: the picture itself (tap for full screen), with what was written with it.
        final file = m.obj('attachment');
        out.add(Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ChatPhoto(url: file.str('url'), name: file.str('name'), mime: file.str('mimeType'), mine: mine, caption: text),
        ));
      } else if ((kind == 'record' || kind == 'attachment') && m['deleted'] != true) {
        final rec = m.obj('record');
        final file = m.obj('attachment');
        final recAt = F.date(rec['date']);
        final isTest = rec.str('kind') == 'test_result';
        out.add(Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: _Attachment(
            mine: mine,
            icon: isTest ? I.flask : I.fileText,
            title: rec.isNotEmpty ? rec.str('title', 'Record') : file.str('name', 'Attachment'),
            sub: rec.isNotEmpty
                ? [
                    isTest ? (mine ? 'Shared report' : 'Report') : (rec.str('kind') == 'prescription' ? 'Prescription' : 'Record'),
                    if (recAt != null) F.dayMonth(recAt),
                  ].join(' · ')
                : (file.str('mimeType').contains('pdf') ? 'PDF' : 'Photo'),
            text: text.isEmpty ? null : text,
            onTap: () => rec.isNotEmpty
                ? Nav.go(context, 'Patient-Records')
                : p2Open(context, file['url'] as String?, failed: "Couldn't open the file"),
          ),
        ));
      } else {
        final quoted = m['replyToId'] == null ? null : msgs.where((x) => x.str('id') == m.str('replyToId')).firstOrNull;
        if (m['replyToId'] != null && m['deleted'] != true) {
          out.add(Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(10), border: const Border(left: BorderSide(color: MP.primary, width: 3))),
                child: UserText(quoted == null ? tr(context, 'Earlier message') : _quoteOf(quoted), maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2)),
              ),
            ),
          ));
        }
        final marks = [if (m['forwardedFrom'] != null && m['deleted'] != true) tr(context, 'Forwarded'), if (m['editedAt'] != null && m['deleted'] != true) tr(context, 'Edited')].join(' · ');
        if (marks.isNotEmpty) out.add(_meta(marks, right: mine));
        out.add(Align(
          key: _keys.putIfAbsent(m.str('id'), GlobalKey.new),
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () => _actions(m),
            child: kind == 'voice' && m['deleted'] != true
              ? _Bubble('', mine: mine, child: VoiceNoteChip(url: m.obj('voice').obj('file').str('url'), seconds: m.obj('voice')['durationSec'] as num?, color: mine ? MP.white : MP.ink))
              : m.str('senderType') == 'ai' && m['deleted'] != true
                  ? _AiBubble(text, escalated: m.obj('ai')['escalated'] == true, doctor: _short)
                  : _Bubble(text, mine: mine),
          ),
        ));
        final heard = kind == 'voice' && m['deleted'] != true ? (_transcripts[m.str('id')] ?? m.obj('voice').str('transcript')) : '';
        if (heard.isNotEmpty) {
          out.add(Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: UserText(heard, style: tx(14, c: MP.ink2, h: 1.45))),
          ));
        }
        // Under MedPin AI's latest answer: a person instead.
        if (m.str('senderType') == 'ai' && m == msgs.lastWhere((x) => x.str('senderType') != 'system', orElse: () => m) && !_humanRequested) {
          out.add(Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: P2Box(
                onTap: _handingOff ? null : _handoff,
                height: 36,
                radius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: MP.white,
                border: MP.lineStrong,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Ico(I.user, size: 14, color: MP.primary),
                  const Gap(6),
                  Flexible(child: Text(_handingOff ? 'Asking the clinic…' : 'Talk to the clinic instead', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, w: w600, c: MP.primary))),
                ]),
              ),
            ),
          ));
        }
      }
      // "Please pay ₹600" from the clinic: pay right here; it turns Paid live.
      if (m['payment'] is Map) {
        out.add(Align(
          alignment: Alignment.centerLeft,
          child: PaymentRequestCard(payment: m.obj('payment'), forPatient: true, onPaid: () => reload(quiet: true)),
        ));
      }
      out.add(mine
          ? _meta('$time · ${switch (m.str('deliveryStatus')) { 'seen' => 'Seen', 'delivered' => 'Delivered', _ => 'Sent' }}', right: true)
          : _clinicMeta(m, time));
    }
    // Not yet confirmed by the server: shown at once.
    for (final m in _outbox) {
      out.add(Align(alignment: Alignment.centerRight, child: Opacity(opacity: m.failed ? 0.7 : 1, child: _Bubble(m.text, mine: true))));
      out.add(m.failed
          ? Align(
              alignment: Alignment.centerRight,
              child: MpHitSlop(
                child: Tap(
                  onTap: () => _sendLive(m.text, retryId: m.id),
                  radius: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('Not sent · Tap to retry', style: tx(13, w: w600, c: MP.red)),
                  ),
                ),
              ),
            )
          : _meta('Sending…', right: true));
    }
    final typing = ChatExtras.typingLine(context, _typing);
    if (_aiTyping) {
      out.add(const Align(alignment: Alignment.centerLeft, child: _Typing()));
      out.add(_meta('MedPin AI is typing…'));
    } else if (typing != null) {
      out.add(const Align(alignment: Alignment.centerLeft, child: _Typing()));
      out.add(_meta(typing));
    } else if (_aiNoAnswer && !_answered) {
      out.add(_meta('The clinic will reply here soon'));
    }
    // Quick replies from the server: picked from the latest message and today's readings,
    // doses and visit (none while we're waiting on the clinic). Older servers: the fixed ones.
    final live = data!['suggestions'];
    final replies = live is List
        ? [for (final s in live) if (s is Map) (label: '${s['label'] ?? ''}', text: '${s['text'] ?? s['label'] ?? ''}')]
        : [if (_showReplies) for (final r in _replies) (label: r, text: r)];
    if (replies.isNotEmpty && _outbox.isEmpty && !_aiTyping) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [for (final r in replies) _reply(r.label, send: r.text)]),
      ));
    }
    return out;
  }

  Widget _reply(String r, {String? send}) => P2Box(
    onTap: () => _send(send ?? r),
    label: send == null || send == r ? null : 'Send: $send',
    height: 40,
    radius: 999,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    color: MP.white,
    border: MP.lineStrong,
    child: Row(mainAxisSize: MainAxisSize.min, children: [Text(r, style: tx(14, w: w600))]),
  );

  @override
  Widget build(BuildContext context) {
    final typing = _text.text.trim().isNotEmpty;
    final placeholder = livePlaceholder();

    final items = data != null
        ? _liveItems()
        : <Widget>[
            _day('Yesterday', const EdgeInsets.only(bottom: 4)),
            Align(
              alignment: Alignment.centerLeft,
              child: _Attachment(
                mine: false,
                icon: I.fileText,
                title: 'Prescription · 29 Sep',
                sub: '3 medicines · 2 tests',
                text: 'Please get the HbA1c test done and share it here before your visit.',
                onTap: () => Nav.go(context, 'Patient-Records'),
              ),
            ),
            _meta('Dr. Sen · 6:40 PM'),
            _day('Today', const EdgeInsets.symmetric(vertical: 4)),
            Align(
              alignment: Alignment.centerRight,
              child: _Attachment(
                mine: true,
                icon: I.flask,
                title: 'HbA1c · 7.4%',
                sub: 'Shared report · 30 Sep',
                text: "Here's the report, doctor.",
                onTap: () => Nav.go(context, 'Patient-Records'),
              ),
            ),
            _meta('8:50 AM · Seen', right: true),
            const Align(
              alignment: Alignment.centerLeft,
              child: _Bubble("Got your HbA1c report, thanks. We'll adjust the dose when you come in at 5.", mine: false),
            ),
            _meta('Dr. Sen · 9:14 AM'),
            for (final m in _sent) ...[
              Align(alignment: Alignment.centerRight, child: _Bubble(m, mine: true)),
              _meta('Just now · Sent', right: true),
            ],
            if (_showReplies)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [for (final r in _replies) _reply(r)]),
              ),
          ];

    return MpPage(
      scroll: false,
      header: _header(),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_replyTo != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: MP.primary, width: 3))),
                child: Row(children: [
                  Expanded(child: UserText(_quoteOf(_replyTo), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2))),
                  MpIconButton(I.close, label: 'Cancel reply', iconSize: 16, size: 36, color: MP.ink3, onTap: () => setState(() => _replyTo = null)),
                ]),
              ),
              const Gap(8),
            ],
            Row(
          children: [
            P2Box(
              onTap: _attach,
              label: 'Share a report, prescription or photo',
              width: 44,
              height: 44,
              radius: 12,
              color: MP.primarySoft,
              alignment: Alignment.center,
              child: const Ico(I.plus, size: 22, color: MP.primary, stroke: 2),
            ),
            const Gap(8),
            Expanded(
              child: P2Field(
                controller: _text,
                hint: 'Message $_short',
                height: 48,
                radius: 999,
                fill: MP.bg,
                action: TextInputAction.send,
                onChanged: (v) {
                  _typer.changed(v);
                  setState(() {});
                },
                onSubmitted: (v) => _send(v, fromField: true),
              ),
            ),
            const Gap(8),
            P2Box(
              onTap: typing ? () => _send(_text.text, fromField: true) : _voiceNote,
              label: typing ? 'Send' : 'Record a voice message',
              width: 48,
              height: 48,
              radius: 999,
              color: MP.primary,
              alignment: Alignment.center,
              child: Ico(typing ? I.send : I.mic, size: 22, color: MP.white),
            ),
          ],
        ),
          ],
        ),
      ),
      // Messages sit at the bottom (justify-content: flex-end) and scroll up.
      body:
          placeholder ??
          LayoutBuilder(
            builder:
                (context, c) => SingleChildScrollView(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: math.max(0.0, c.maxHeight - 24)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++) ...[if (i > 0) const Gap(8), items[i]],
                      ],
                    ),
                  ),
                ),
          ),
      overlays: [if (data != null) Positioned(left: 16, bottom: 96 + MediaQuery.paddingOf(context).bottom, child: JumpToLatest(controller: _scroll))],
    );
  }

  Widget _header() {
    final presence = _doctor.str('presence');
    final reply = _doctor['avgReplyMinutes'];
    final note = _doctor.str('presenceNote'); // live, from the server
    final (String status, Color statusColor) = data == null
        ? ('Available now', MP.green)
        : switch (presence) {
            'available' => ('Available now${note.isNotEmpty ? ' · $note' : reply is num ? ' · replies in ~${reply.round()} min' : ''}', MP.green),
            'in_clinic' => (note.isNotEmpty ? 'In clinic · $note' : 'In clinic now', MP.amber),
            _ => (note.isNotEmpty ? note : 'Replies when back', MP.ink3),
          };
    final visit = data?.obj('conversation').obj('nextVisit') ?? const <String, dynamic>{};
    final at = F.date(visit['startAt']);
    String? visitLine;
    if (data == null) {
      visitLine = 'Visit today, 5:00 PM';
    } else if (at != null) {
      final when = F.when(at);
      visitLine = 'Visit ${when.startsWith('Today') || when.startsWith('Tomorrow') ? when[0].toLowerCase() + when.substring(1) : when}';
    }
    final token = data == null ? '04' : visit.str('token');

    return Container(
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 68,
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                const Gap(8),
                MpAvatar(F.initials(_name), size: 40, fontSize: 14, photo: _doctor.str('photoUrl').isEmpty ? null : _doctor.str('photoUrl')),
                const Gap(8),
                Expanded(
                  child: MpHitSlop(child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _detail,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(17, w: w700)),
                        Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, w: w600, c: statusColor)),
                      ],
                    ),
                  )),
                ),
                const Gap(8),
                MpIconButton(I.search, label: 'Search this chat', onTap: _search),
                MpIconButton(I.moreV, label: 'This chat', onTap: _chatMenu),
              ],
            ),
          ),
          if (visitLine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: P2Box(
                onTap: _detail,
                height: 40,
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                color: MP.primarySoft,
                child: Row(
                  children: [
                    const Ico(I.calendar, size: 16, color: MP.primary),
                    const Gap(8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: tx(13),
                          children: [
                            TextSpan(text: visitLine, style: tx(13, w: w700)),
                            if (token.isNotEmpty) TextSpan(text: ' · Token $token'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Gap(8),
                    Text('Details', style: tx(13, w: w700, c: MP.primary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _day(String label, EdgeInsets padding) =>
      Center(child: Padding(padding: padding, child: Text(label, style: tx(12, w: w600, c: MP.ink3))));

  /// Under a clinic message: who sent it and their role ("Tania · Front desk · 9:14 AM" —
  /// the doctor and the desk share this chat), and "Automatic message" for notes the clinic's
  /// system sent from their account (visit booked, fee paid).
  Widget _clinicMeta(Map<String, dynamic> m, String time) {
    final role = m.str('senderRole');
    final line = [
      tr(context, _sender(m)),
      if (role.isNotEmpty && role != 'doctor' && m.str('senderRoleLabel').isNotEmpty) tr(context, m.str('senderRoleLabel')),
      if (time.isNotEmpty) time,
    ].join(' · ');
    if (m['auto'] != true) return _meta(line);
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(line, style: tx(12, c: MP.ink3)),
          Text('Automatic message', style: tx(12, c: MP.ink3)),
        ],
      ),
    );
  }

  Widget _meta(String text, {bool right = false}) => Align(
    alignment: right ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(text, style: tx(12, c: MP.ink3)),
  );
}

/// Report / prescription card bubble (doctor: white 260px + border; patient: blue 250px).
class _Attachment extends StatelessWidget {
  final bool mine;
  final String icon;
  final String title;
  final String sub;
  final String? text;
  final VoidCallback onTap;
  const _Attachment({
    required this.mine,
    required this.icon,
    required this.title,
    required this.sub,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = mine ? MP.white : MP.ink;
    return P2Box(
      onTap: onTap,
      label: title,
      width: mine ? 250 : 262, // doctor's: 260px + 1px border (content-box)
      borderRadius: mine ? _mine : _theirs,
      color: mine ? MP.primary : MP.white,
      border: mine ? null : MP.line,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border:
                  text == null
                      ? null
                      : Border(bottom: BorderSide(color: mine ? MP.white.withValues(alpha: 0.16) : MP.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mine ? MP.white.withValues(alpha: 0.16) : MP.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Ico(icon, size: 18, color: mine ? MP.white : MP.primary),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tx(14, w: w700, c: fg)),
                      const Gap(1),
                      Text(sub, style: tx(12, c: mine ? MP.white.withValues(alpha: 0.8) : MP.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (text != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: UserText(text!, style: tx(14, h: 1.45, c: fg)),
            ),
        ],
      ),
    );
  }
}

/// Plain text bubble: max-width 280 + padding 12/14 (+1px border on the doctor's).
class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  final Widget? child;
  const _Bubble(this.text, {required this.mine, this.child});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: mine ? 308 : 310),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: mine ? MP.primary : MP.white,
        borderRadius: mine ? _mine : _theirs,
        border: mine ? null : Border.all(color: MP.line),
      ),
      child: child ?? UserText(text, style: tx(15, h: 1.45, c: mine ? MP.white : MP.ink)),
    ),
  );
}

/// MedPin AI's answer: its own look, so it isn't mistaken for the doctor's own
/// words; says when it has asked the doctor to check.
class _AiBubble extends StatelessWidget {
  final String text;
  final bool escalated;
  final String doctor;
  const _AiBubble(this.text, {required this.escalated, required this.doctor});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 310),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: MP.primarySoft, borderRadius: _theirs, border: Border.all(color: MP.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Ico(I.sparkle, size: 14, color: MP.primary),
            const Gap(6),
            Flexible(child: Text('MedPin AI · not your doctor', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(12, w: w700, c: MP.primary))),
          ]),
          const Gap(6),
          UserText(text, style: tx(15, h: 1.45, c: MP.ink)),
          if (escalated) ...[
            const Gap(8),
            Text(tr(context, '#1 will check this').replaceFirst('#1', doctor), style: tx(13, w: w600, c: MP.ink2)),
          ],
        ],
      ),
    ),
  );
}

/// Three dots that pulse in a reply bubble while MedPin AI writes.
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(context, 'MedPin AI is typing'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(color: MP.white, borderRadius: _theirs, border: Border.all(color: MP.line)),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Opacity(
                  // Each dot lights up in turn.
                  opacity: 0.3 + 0.7 * (((_c.value * 3 - i) % 3) < 1 ? 1 - ((_c.value * 3 - i) % 3) : 0),
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: MP.ink3, shape: BoxShape.circle)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

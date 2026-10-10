import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../widgets/chat_tools.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';
import 'common_p2.dart';

/// Design: Patient-Chat.dc.html — "Patient · urgent chat with doctor".
///
/// Live: opened from Patient-Emergency with args {conversationId, doctorId,
/// doctorName, presence, avgReplyMinutes, gender}; without a conversation it
/// opens the patient's urgent (else latest) care thread from
/// GET /api/patient/conversations. Messages: GET /api/conversations/:id/messages
/// (refreshed every 15 s, marked read), sending: POST …/messages (urgent),
/// attachments as multipart. "Share my vitals" sends the latest home readings.
class PatientChatScreen extends StatefulWidget {
  const PatientChatScreen({super.key});

  @override
  State<PatientChatScreen> createState() => _PatientChatScreenState();
}

typedef _Message = ({String text, bool mine, String meta, DateTime? at, Map<String, dynamic>? raw});

class _PatientChatScreenState extends State<PatientChatScreen> with LiveData {
  static const _replies = ["I'm on my way", 'Share my vitals'];

  final List<_Message> _messages = [
    (
      text: "My chest feels tight since morning and I'm sweating a little. Should I come in now?",
      mine: true,
      meta: '9:12 AM · Delivered',
      at: null,
      raw: null,
    ),
    (
      text: "Priya, please come to the clinic now. I'm informing the front desk. If the pain gets worse on the way, call 108.",
      mine: false,
      meta: 'Dr. Sen · 9:14 AM',
      at: null,
      raw: null,
    ),
  ];
  final _input = TextEditingController();
  final _busy = ValueNotifier(false);
  final _scroll = ScrollController();
  bool _showReplies = true;
  bool _hasText = false;

  @override
  Duration? get refreshEvery => const Duration(seconds: 15);

  Map<String, dynamic> get _args => (Nav.args<Map>(context) ?? const {}).cast<String, dynamic>();

  @override
  Future<Object?> fetch() async {
    final a = _args;
    var id = a['conversationId'] as String? ?? data?['conversationId'] as String?;
    if (id == null) {
      final list = await Api.I.get('/api/patient/conversations') as List? ?? const [];
      final convos = [for (final c in list) (c as Map).cast<String, dynamic>()];
      final pick = convos.where((c) => c['isUrgent'] == true).firstOrNull ?? convos.firstOrNull;
      id = pick?['id'] as String?;
    }
    if (id == null) return {'conversationId': null, 'items': const []};
    final results = await Future.wait([
      Api.I.get('/api/conversations/$id/messages'),
      a['doctorId'] == null ? Future.value(null) : Api.I.get('/api/patient/urgent/doctors').catchError((_) => null),
    ]);
    final thread = (results[0] as Map).cast<String, dynamic>();
    Map<String, dynamic>? doctor;
    final docs = results[1];
    if (docs is Map) {
      doctor = [for (final d in docs['items'] as List? ?? const []) (d as Map).cast<String, dynamic>()]
          .where((d) => d['doctorId'] == a['doctorId'])
          .firstOrNull;
    }
    // Opening the thread reads it.
    Api.I.post('/api/conversations/$id/read').catchError((_) => null);
    return {...thread, 'conversationId': id, 'doctor': doctor};
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _busy.dispose();
    super.dispose();
  }

  String? get _conversationId => data?['conversationId'] as String?;

  // ── Who the chat is with ──

  Map<String, dynamic> get _doctor {
    final a = _args;
    final live = data?.obj('doctor') ?? const {};
    return {
      'doctorId': a['doctorId'],
      'name': a['doctorName'],
      'presence': a['presence'],
      'avgReplyMinutes': a['avgReplyMinutes'],
      'gender': a['gender'],
      ...live,
    };
  }

  String get _doctorName {
    if (data == null) return 'Dr. Arjun Sen';
    final name = _doctor['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final fromThread = data!.list('items').reversed.where((m) => m['senderType'] == 'doctor').map((m) => m.obj('senderId').str('name')).where((n) => n.isNotEmpty).firstOrNull;
    return fromThread ?? 'Your doctor';
  }

  ({String status, Color color})? get _presence {
    if (data == null) return (status: 'Available now', color: MP.green);
    if (_doctor['presence'] == null) return null;
    final p = P1.presence(_doctor);
    return (status: p.status, color: p.color);
  }

  // ── Messages ──

  static String _status(Map<String, dynamic> m) => switch (m['deliveryStatus']) {
        'seen' => 'Seen',
        'delivered' => 'Delivered',
        _ => 'Sent',
      };

  static String _textOf(Map<String, dynamic> m) {
    if (m['deleted'] == true) return 'This message was deleted';
    final text = m.str('text');
    if (text.isNotEmpty) return text;
    return switch (m['kind']) {
      'attachment' => 'Sent a file',
      'voice' => 'Voice message',
      'record' => 'Shared a health record',
      _ => '',
    };
  }

  List<_Message> get _list {
    if (data == null) return _messages;
    return [
      for (final m in data!.list('items'))
        if (_textOf(m).isNotEmpty)
          () {
            final at = F.date(m['createdAt']);
            final mine = m['mine'] == true || m['senderType'] == 'patient';
            final time = at == null ? '' : F.time(at);
            final who = m['senderType'] == 'ai'
                ? 'MedPin AI'
                : m.obj('senderId').str('name').isNotEmpty
                    ? F.doctorShort(m.obj('senderId').str('name'))
                    : m['senderType'] == 'doctor'
                        ? F.doctorShort(_doctorName)
                        : 'Clinic';
            return (text: _textOf(m), mine: mine, meta: mine ? '$time · ${_status(m)}' : '$who · $time', at: at, raw: m);
          }(),
    ];
  }

  bool get _repliesVisible {
    if (data == null) return _showReplies;
    final l = _list;
    return l.isNotEmpty && !l.last.mine;
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    if (!isLive) {
      setState(() {
        _messages.add((text: t, mine: true, meta: 'Just now · Sent', at: null, raw: null));
        _showReplies = false;
        _input.clear();
        _hasText = false;
      });
      return;
    }
    final id = _conversationId;
    if (id == null) return;
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$id/messages', {'text': t, 'isUrgent': true}), busy: _busy);
    if (ok == null || !mounted) return;
    setState(() {
      _input.clear();
      _hasText = false;
    });
    reload(quiet: true);
  }

  /// "Share my vitals": the latest home readings of the last 7 days as a message.
  Future<void> _shareVitals() async {
    final rows = await runAction(context, () => Api.I.get('/api/patient/readings', query: {'days': 7}));
    if (rows is! List || !mounted) return;
    final latest = <String, String>{};
    for (final r in rows.reversed) {
      final v = (r as Map).cast<String, dynamic>();
      String n(Object? x) => x is num ? (x % 1 == 0 ? '${x.toInt()}' : x.toStringAsFixed(1)) : '$x';
      if (v['bpSystolic'] != null) latest.putIfAbsent('bp', () => 'BP ${n(v['bpSystolic'])}/${n(v['bpDiastolic'])}');
      if (v['bloodSugar'] != null) {
        final type = v['sugarType'] == 'fasting' ? ' (fasting)' : v['sugarType'] == 'post_meal' ? ' (after a meal)' : '';
        latest.putIfAbsent('sugar', () => 'sugar ${n(v['bloodSugar'])} mg/dL$type');
      }
      if (v['pulse'] != null) latest.putIfAbsent('pulse', () => 'pulse ${n(v['pulse'])}');
      if (v['spo2'] != null) latest.putIfAbsent('spo2', () => 'SpO₂ ${n(v['spo2'])}%');
      if (v['temperatureF'] != null) latest.putIfAbsent('temp', () => 'temperature ${n(v['temperatureF'])}°F');
      if (v['weightKg'] != null) latest.putIfAbsent('weight', () => 'weight ${n(v['weightKg'])} kg');
    }
    if (latest.isEmpty) {
      toast(context, 'No readings in the last 7 days');
      return;
    }
    await _send('My latest readings: ${latest.values.join(', ')}.');
  }

  Future<void> _voiceNote() async {
    if (!isLive) return toast(context, 'Recording…');
    if (await sendVoiceNote(context, _conversationId, busy: _busy, fields: const {'isUrgent': 'true'}) && mounted) reload(quiet: true);
  }

  Future<void> _attach() async {
    if (!isLive) {
      toast(context, 'Attach a photo or report');
      return;
    }
    final id = _conversationId;
    if (id == null) return;
    final file = await Files.chooseSource(context, title: 'Send a photo or report');
    if (file == null || !mounted) return;
    final ok = await runAction(
      context,
      () => Api.I.upload('/api/conversations/$id/messages', files: {'file': [file]}, fields: {'isUrgent': 'true'}),
      busy: _busy,
    );
    if (ok != null && mounted) reload(quiet: true);
  }

  void _openDoctor() {
    final id = _doctor['doctorId'];
    Nav.go(context, 'Patient-DoctorDetail', args: id == null ? null : {'doctorId': id});
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      scroll: false,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [_header(context), _banner(context)],
      ),
      body: placeholder ??
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                // Messages sit at the bottom of the thread (justify-content: flex-end).
                constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - 32)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _thread(),
                ),
              ),
            ),
          ),
      bottom: _composer(context),
      overlays: [Positioned(left: 16, bottom: 96 + MediaQuery.paddingOf(context).bottom, child: JumpToLatest(controller: _scroll))],
    );
  }

  /// White 68px bar (+1px rule): back, avatar, name and status.
  Widget _header(BuildContext context) {
    final presence = _presence;
    return Container(
      height: 69,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: const BoxDecoration(
        color: MP.white,
        border: Border(bottom: BorderSide(color: MP.line)),
      ),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openDoctor,
              child: Row(
                children: [
                  MpAvatar(data == null ? 'AS' : F.initials(_doctorName), size: 40, fontSize: 14),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_doctorName, style: tx(17, w: w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (presence != null)
                          Text(presence.status, style: tx(13, w: w600, c: presence.color), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
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

  /// Red status strip: "Urgent chat. Dr. Sen has been alerted." + Call 108.
  Widget _banner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: MP.redSoft,
        border: Border(bottom: BorderSide(color: MP.redLine)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const Ico(I.alert, size: 18, color: MP.red),
            const Gap(10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: tx(14, h: 1.4),
                  children: [
                    TextSpan(text: 'Urgent chat.', style: tx(14, w: w700, h: 1.4, c: MP.red)),
                    TextSpan(text: ' ${data == null ? 'Dr. Sen' : F.doctorShort(_doctorName)} has been alerted.'),
                  ],
                ),
              ),
            ),
            const Gap(10),
            Semantics(
              link: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => isLive ? P1.dial(context, '108') : toast(context, 'Calling 108…'),
                child: Text('Call 108', style: tx(14, w: w700, h: 1.4, c: MP.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dayLabel(DateTime? d) {
    if (d == null) return 'Today';
    final now = DateTime.now();
    if (F.sameDay(d, now)) return 'Today';
    if (F.sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return F.dateLong(d);
  }

  List<Widget> _thread() {
    final meta = tx(12, c: MP.ink3);
    final messages = _list;
    final items = <Widget>[];
    String? day;
    for (final m in messages) {
      final label = data == null ? 'Today' : _dayLabel(m.at);
      if (label != day) {
        day = label;
        items.add(Center(child: Text(label, style: tx(12, w: w600, c: MP.ink3))));
      }
      items
        ..add(m.mine ? _outgoing(m.text, m.raw) : _incoming(m.text, m.raw))
        ..add(m.mine ? Align(alignment: Alignment.centerRight, child: Text(m.meta, style: meta)) : Text(m.meta, style: meta));
    }
    if (messages.isEmpty) {
      items.add(Center(child: Text(_conversationId == null ? 'No conversation yet' : 'Today', style: tx(12, w: w600, c: MP.ink3))));
    }
    if (_repliesVisible) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _replies) P1Pill(r, onTap: () => isLive && r == 'Share my vitals' ? _shareVitals() : _send(r)),
            ],
          ),
        ),
      );
    }
    return [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const Gap(10), items[i]],
    ];
  }

  /// Patient bubble: max 270px text, #003399, radius 16 16 4 16.
  /// A voice note plays here; a photo or PDF opens; else the text.
  Widget _body(String text, Map<String, dynamic>? raw, {required bool mine}) {
    final c = mine ? MP.white : MP.ink;
    if (raw != null && raw['deleted'] != true) {
      if (raw['kind'] == 'voice') {
        final v = raw.obj('voice');
        return VoiceNoteChip(url: v.obj('file').str('url'), seconds: v['durationSec'] as num?, color: c);
      }
      final f = raw.obj('attachment');
      if (raw['kind'] == 'attachment' && f.str('url').isNotEmpty) {
        return Semantics(
          button: true,
          label: 'Open ${f.str('name', 'file')}',
          child: GestureDetector(
            onTap: () => p2Open(context, f.str('url'), failed: "Couldn't open the file"),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Ico(I.fileText, size: 20, color: c),
                const Gap(8),
                Flexible(child: Text(text == 'Sent a file' || text == 'Attachment' ? f.str('name', 'Attachment') : text, style: tx(15, h: 1.45, c: c, w: w600))),
              ],
            ),
          ),
        );
      }
    }
    return Text(text, style: tx(15, h: 1.45, c: c));
  }

  Widget _outgoing(String text, [Map<String, dynamic>? raw]) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 298),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: MP.primary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
            ),
          ),
          child: _body(text, raw, mine: true),
        ),
      ),
    );
  }

  /// Doctor bubble: max 280px text, white, 1px #E5E9F0, radius 16 16 16 4.
  Widget _incoming(String text, [Map<String, dynamic>? raw]) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: MP.white,
            border: Border.all(color: MP.line),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: _body(text, raw, mine: false),
        ),
      ),
    );
  }

  /// White composer: attach, 48px pill input, round mic (send once typing).
  Widget _composer(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MP.white,
        border: Border(top: BorderSide(color: MP.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              MpIconButton(
                I.paperclip,
                label: 'Attach a photo or report',
                color: MP.ink2,
                onTap: _attach,
              ),
              const Gap(8),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: MP.bg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MP.lineStrong),
                  ),
                  child: Semantics(
                    label: 'Message',
                    child: TextField(
                      controller: _input,
                      style: tx(16),
                      cursorColor: MP.primary,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      onChanged: (v) {
                        final has = v.trim().isNotEmpty;
                        if (has != _hasText) setState(() => _hasText = has);
                      },
                      decoration: InputDecoration.collapsed(
                        hintText: 'Type a message',
                        hintStyle: tx(16, c: P1.placeholder),
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Semantics(
                button: true,
                label: _hasText ? 'Send' : 'Record a voice message',
                child: Tap(
                  onTap: () => _hasText ? _send(_input.text) : _voiceNote(),
                  radius: 999,
                  color: MP.primary,
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

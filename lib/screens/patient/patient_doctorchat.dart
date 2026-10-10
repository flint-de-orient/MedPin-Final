import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../widgets/chat_tools.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import '../../widgets/i18n.dart';

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

  /// The doctor this chat is with (a row of my-doctors).
  Map<String, dynamic> _doctor = const {};

  @override
  Duration? get refreshEvery => const Duration(seconds: 20);

  @override
  void dispose() {
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
      _doctor = (doctorId != null ? mine.where((d) => d.str('doctorId') == doctorId).firstOrNull : null) ??
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
    final res = (await Api.I.get('/api/conversations/$_convId/messages') as Map).cast<String, dynamic>();
    Api.I.post('/api/conversations/$_convId/read', const {}).catchError((_) => null);
    return res;
  }

  String get _name =>
      data == null ? 'Dr. Arjun Sen' : _doctor.str('name', data!.obj('conversation').str('practiceName', 'Your clinic'));
  String get _short => data == null ? 'Dr. Sen' : p2ShortName(_name);

  void _send(String message) {
    final m = message.trim();
    if (m.isEmpty) return;
    if (data != null) {
      _sendLive(m);
      return;
    }
    setState(() {
      _sent.add(m);
      _showReplies = false;
      _text.clear();
    });
  }

  Future<void> _sendLive(String text) async {
    final ok = await runAction(context, () => Api.I.post('/api/conversations/$_convId/messages', {'text': text}), busy: _busy);
    if (ok == null || !mounted) return;
    setState(() {
      _showReplies = false;
      _text.clear();
    });
    await reload(quiet: true);
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
    final id = await searchChat(context, data!.list('items'), sender: (m) => m.str('senderType') == 'patient' ? 'You' : _sender(m));
    final c = id == null ? null : _keys[id]?.currentContext;
    if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.3);
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
      if (kind == 'record' || kind == 'attachment') {
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
        out.add(Align(
          key: _keys.putIfAbsent(m.str('id'), GlobalKey.new),
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: kind == 'voice' && m['deleted'] != true
              ? _Bubble('', mine: mine, child: VoiceNoteChip(url: m.obj('voice').obj('file').str('url'), seconds: m.obj('voice')['durationSec'] as num?, color: mine ? MP.white : MP.ink))
              : _Bubble(text, mine: mine),
        ));
      }
      out.add(mine
          ? _meta('$time · ${m.str('deliveryStatus') == 'seen' ? 'Seen' : 'Sent'}', right: true)
          : _meta('${_sender(m)} · $time'));
    }
    if (_showReplies) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [for (final r in _replies) _reply(r)]),
      ));
    }
    return out;
  }

  Widget _reply(String r) => P2Box(
    onTap: () => _send(r),
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
        child: Row(
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
                onChanged: (_) => setState(() {}),
                onSubmitted: _send,
              ),
            ),
            const Gap(8),
            P2Box(
              onTap: typing ? () => _send(_text.text) : _voiceNote,
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
    final (String status, Color statusColor) = data == null
        ? ('Available now', MP.green)
        : switch (presence) {
            'available' => ('Available now${reply is num ? ' · replies in ~${reply.round()} min' : ''}', MP.green),
            'in_clinic' => ('In clinic now', MP.amber),
            _ => ('Replies when back', MP.ink3),
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
                MpAvatar(F.initials(_name), size: 40, fontSize: 14),
                const Gap(8),
                Expanded(
                  child: GestureDetector(
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
                  ),
                ),
                const Gap(8),
                MpIconButton(I.search, label: 'Search this chat', onTap: _search),
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
              child: Text(text!, style: tx(14, h: 1.45, c: fg)),
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
      child: child ?? Text(text, style: tx(15, h: 1.45, c: mine ? MP.white : MP.ink)),
    ),
  );
}

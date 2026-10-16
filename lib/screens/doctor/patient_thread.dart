import 'package:flutter/material.dart' hide Text;

import '../../data/push.dart';
import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../data/voice.dart';
import '../../widgets/chat_tools.dart';
import '../../widgets/mp.dart';
import 'common_d6.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-Thread.dc.html — "Patient thread".
///
/// Live (args `{'conversationId'}`, a bare conversation id, or
/// `{'patientId'}`): GET /api/conversations/:id/messages every 12 s, marks
/// the thread read on open, and sends / pins / hides / deletes messages.
/// Attachments: POST /api/conversations/:id/messages (multipart `file`).
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

class _PatientThreadScreenState extends State<PatientThreadScreen> with SingleTickerProviderStateMixin, LiveData {
  // ── Live thread ──
  String? _convId;
  String? _patientIdArg;
  bool _readSent = false;
  Map<String, dynamic>? _contacts;

  /// Message with its action menu open (live), and the one being replied to.
  String? _menuFor;
  Map<String, dynamic>? _replyTo;
  final _msgKeys = <String, GlobalKey>{};
  final _busy = ValueNotifier(false);

  @override
  // New messages also arrive at once by a silent push (Push → LiveBus); this is the backup.
  Duration? get refreshEvery => const Duration(seconds: 4);

  @override
  Future<Object?> fetch() async {
    if (_convId == null) {
      final a = Nav.args<Object>(context);
      final m = a is Map ? a : (a is String ? {'conversationId': a} : const {});
      _convId = m['conversationId']?.toString();
      _patientIdArg = m['patientId']?.toString();
      if (_convId == null && _patientIdArg != null) {
        final c = await Api.I.post('/api/inbox', {'patientId': _patientIdArg});
        _convId = '${(c as Map)['id'] ?? c['_id']}';
      }
      if (_convId == null) {
        // Opened without a thread: the most pressing patient chat.
        final inbox = await Api.I.get('/api/inbox', query: {'type': 'all'});
        final items = [for (final x in ((inbox as Map)['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
        if (items.isEmpty) throw const ApiException(404, 'NO_CONVERSATION', 'No conversations yet');
        _convId = (items.firstWhere((x) => x['isUrgent'] == true, orElse: () => items.first))['id']?.toString();
      }
    }
    Push.I.openChat = _convId;
    final res = ((await Api.I.get('/api/conversations/$_convId/messages')) as Map).cast<String, dynamic>();
    if (res.obj('conversation')['patient'] == null && _contacts == null) {
      _contacts = ((await Api.I.get('/api/inbox/contacts')) as Map).cast<String, dynamic>();
    }
    if (!_readSent) {
      _readSent = true;
      Api.I.post('/api/conversations/$_convId/read', const {}).catchError((_) => null);
    }
    return res;
  }

  Map<String, dynamic> get _conv => data!.obj('conversation');
  Map<String, dynamic> get _patient => _conv.obj('patient');

  /// Thread title: the patient, or the colleague in a direct chat.
  String get _liveName {
    if (_patient.isNotEmpty) return _patient.str('name');
    final me = '${Session.I.user['id']}';
    final other = _conv.list('participants').firstWhere((p) => '${p['userId']}' != me, orElse: () => const {});
    for (final t in (_contacts ?? const <String, dynamic>{}).list('team')) {
      if ('${t['userId']}' == '${other['userId']}') return t.str('name');
    }
    return 'Conversation';
  }

  /// The header photo: the patient's, or the colleague's in a direct chat
  /// (from their newest message, which is current on every refresh, else the team list).
  String? get _livePhoto {
    if (_patient.isNotEmpty) return _patient.str('photo').isEmpty ? null : _patient.str('photo');
    final me = '${Session.I.user['id']}';
    final other = '${_conv.list('participants').firstWhere((p) => '${p['userId']}' != me, orElse: () => const {})['userId']}';
    for (final m in data!.list('items').reversed) {
      final s = m['senderId'];
      if ('${s is Map ? s['_id'] ?? s['id'] : s}' == other && m.str('senderPhoto').isNotEmpty) return m.str('senderPhoto');
    }
    for (final t in (_contacts ?? const <String, dynamic>{}).list('team')) {
      if ('${t['userId']}' == other && t.str('photo').isNotEmpty) return t.str('photo');
    }
    return null;
  }

  /// "Last seen 2 min ago" / "Next visit Today, 5:00 PM · token 04".
  String get _liveSubtitle {
    final seen = F.date(_patient['lastSeenAt']);
    if (seen != null) {
      final ago = F.ago(seen);
      return 'Last seen ${ago == 'Just now' || ago == 'Yesterday' ? ago.toLowerCase() : ago}';
    }
    final next = _conv.obj('nextVisit');
    final at = F.date(next['startAt']);
    if (at != null) return 'Next visit ${F.when(at)}${next.str('token').isEmpty ? '' : ' · token ${next.str('token')}'}';
    return _patient.isEmpty ? 'Direct message' : '';
  }

  /// Who wrote a clinic-side message — the clinic shares one thread per patient:
  /// "Tania · Front desk", "Dr. Sen"; an automatic note (visit booked,
  /// fee paid) adds "Automatic message" ("You · Automatic message" for mine).
  /// Empty for my own typed messages and for the patient's, AI and clinic lines.
  String _byLine(Map<String, dynamic> m) {
    final type = m['senderType'];
    if ((type != 'doctor' && type != 'staff') || m['deleted'] == true) return '';
    final mine = m['mine'] == true;
    final auto = m['auto'] == true;
    if (mine && !auto) return '';
    final s = m['senderId'];
    final full = s is Map && s['name'] != null ? '${s['name']}'.trim() : '';
    final name = RegExp(r'^Dr\.?\s', caseSensitive: false).hasMatch(full) ? F.doctorShort(full) : full.split(RegExp(r'\s+')).first;
    final role = m.str('senderRoleLabel');
    return [
      if (mine) tr(context, 'You') else if (name.isNotEmpty) name,
      if (!mine && role.isNotEmpty && m['senderRole'] != 'doctor') tr(context, role),
      if (auto) tr(context, 'Automatic message'),
    ].join(' · ');
  }

  String _senderName(Map<String, dynamic> m) {
    if (m['mine'] == true) return 'You';
    final s = m['senderId'];
    if (s is Map && s['name'] != null) return '${s['name']}';
    return switch (m['senderType']) { 'patient' => _liveName, 'ai' => 'AI assistant', _ => 'Clinic' };
  }

  /// One-line summary of a message (pinned bar, quotes).
  String _summary(Map<String, dynamic>? m) {
    if (m == null) return '';
    if (m['deleted'] == true) return 'Message deleted';
    final voice = m.obj('voice');
    if (m['kind'] == 'voice') return 'Voice note${voice['durationSec'] is num ? ' · ${_dur(voice['durationSec'] as num)}' : ''}';
    if (m['kind'] == 'attachment') return m.obj('attachment').str('name', 'Attachment');
    return m.str('text');
  }

  static String _dur(num s) => '${s ~/ 60}:${(s.round() % 60).toString().padLeft(2, '0')}';

  Future<void> _liveMenuAction(String a, Map<String, dynamic> m) async {
    setState(() => _menuFor = null);
    final id = m.str('id');
    switch (a) {
      case 'Reply':
        setState(() => _replyTo = m);
        _replyFocus.requestFocus();
        return;
      case 'Pin':
        final ok = await runAction(context, () => Api.I.post('/api/conversations/$_convId/pin', {'messageId': id}), busy: _busy);
        if (ok != null && mounted) toast(context, 'Pinned at the top of the chat');
      case 'Hide':
        final ok = await runAction(context, () => Api.I.post('/api/conversations/$_convId/messages/$id/hide'), busy: _busy);
        if (ok != null && mounted) toast(context, 'Message hidden');
      default:
        final ok = await runAction(context, () => Api.I.delete('/api/conversations/$_convId/messages/$id'), busy: _busy);
        if (ok != null && mounted) toast(context, 'Deleted for everyone');
    }
    if (mounted) reload(quiet: true);
  }

  Future<void> _sendLive() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _convId == null) return;
    final reply = _replyTo;
    final ok = await runAction(
      context,
      () => Api.I.post('/api/conversations/$_convId/messages', {'text': text, if (reply != null) 'replyToId': reply.str('id')}),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    _reply.clear();
    setState(() => _replyTo = null);
    await reload(quiet: true);
    _toLatest();
  }

  /// Records a voice reply and sends it.
  Future<void> _voiceLive() async {
    if (data == null) return toast(context, 'Recording…');
    if (!await sendVoiceNote(context, _convId, busy: _busy) || !mounted) return;
    await reload(quiet: true);
    _toLatest();
  }

  /// Sends a photo or PDF into the chat.
  Future<void> _attachLive() async {
    if (_convId == null) return;
    final file = await Files.chooseSource(context, title: 'Attach to chat');
    if (file == null || !mounted) return;
    final text = _reply.text.trim();
    final ok = await runAction(
      context,
      () => Api.I.upload('/api/conversations/$_convId/messages', files: {'file': [file]}, fields: {if (text.isNotEmpty) 'text': text}),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    _reply.clear();
    await reload(quiet: true);
    _toLatest();
  }

  Future<void> _callLive() async {
    final pid = _patient.str('id', _patientIdArg ?? '');
    if (pid.isEmpty) {
      toast(context, 'No phone number for this chat');
      return;
    }
    final p = await runAction(context, () => Api.I.get('/api/patients/$pid'));
    if (p is! Map || !mounted) return;
    final phone = '${(p['patient'] as Map?)?['phone'] ?? ''}';
    await d6Call(context, phone, _liveName);
  }

  /// Front desk on an emergency: "Doctor informed" (shown to the doctor on the alert).
  /// It never closes the alert — only the doctor resolves it.
  Future<void> _doctorInformed(String alertId) async {
    final ok = await runAction(context, () => Api.I.post('/api/alerts/$alertId/desk-note', {'note': 'Doctor informed'}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Noted. The doctor sees it on the alert.');
    reload(quiet: true);
  }

  /// The doctor (manage alerts) resolves it here: every bell's red dot clears.
  Future<void> _resolveAlert(String alertId) async {
    final ok = await runAction(context, () => Api.I.post('/api/alerts/$alertId/resolve', const {}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Emergency resolved');
    reload(quiet: true);
  }

  Widget _urgentBanner(Map<String, dynamic> a) {
    final at = F.date(a['createdAt']);
    final seenBy = a.str('acknowledgedBy');
    final doctor = a.str('doctor').isEmpty ? '' : F.doctorShort(a.str('doctor'));
    final status = seenBy.isNotEmpty
        ? tr(context, 'Seen by #1').replaceFirst('#1', F.doctorShort(seenBy))
        : doctor.isEmpty
            ? tr(context, "The doctor hasn't seen it yet")
            : tr(context, "#1 hasn't seen it yet").replaceFirst('#1', doctor);
    final notes = [
      for (final n in a.list('deskNotes'))
        [
          n.str('text'),
          [if (n.str('by').isNotEmpty) n.str('by').split(RegExp(r'\s+')).first, if (F.date(n['at']) != null) F.time(F.date(n['at'])!)].join(', '),
        ].where((x) => x.isNotEmpty).join(' · '),
    ];
    final id = a.str('id');
    return Container(
      color: MP.redSoft,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Ico(I.emergency, size: 18, color: MP.red),
              const Gap(8),
              Expanded(
                child: Text(
                  a.str('kind') == 'urgent_chat' ? 'Asked for urgent help' : 'Emergency alert',
                  style: tx(15, w: w700, c: MP.red, h: 1.35),
                ),
              ),
              if (at != null) Text(F.time(at), style: tx(13, c: MP.red, tab: true)),
            ],
          ),
          if (a.str('detail').isNotEmpty) ...[
            const Gap(4),
            Text(a.str('detail'), maxLines: 3, overflow: TextOverflow.ellipsis, style: tx(15, h: 1.45)),
          ],
          const Gap(4),
          Text(status, style: tx(13, c: MP.ink2, h: 1.4)),
          for (final n in notes) Text(n, style: tx(13, c: MP.ink2, h: 1.4)),
          const Gap(10),
          Row(
            children: [
              Expanded(child: MpButton.small('Call patient', icon: I.phone, kind: MpBtn.secondary, onTap: _callLive)),
              const Gap(8),
              Expanded(
                child: a['canManage'] == true
                    ? MpButton.small('Resolve', icon: I.check, kind: MpBtn.danger, onTap: () => _resolveAlert(id))
                    : MpButton.small('Doctor informed', icon: I.check, kind: MpBtn.danger, onTap: () => _doctorInformed(id)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _searchLive() async {
    final id = await searchChat(context, data!.list('items'), sender: _senderName);
    final c = id == null ? null : _msgKeys[id]?.currentContext;
    if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.3);
  }

  void _toPinnedLive() {
    final c = _msgKeys[data!.obj('pinned').str('id')]?.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.3);
    }
  }

  /// "TODAY" / "YESTERDAY" / "28 SEP"
  static String _dayLabel(DateTime d) {
    final n = DateTime.now();
    if (F.sameDay(d, n)) return 'TODAY';
    if (F.sameDay(d, n.subtract(const Duration(days: 1)))) return 'YESTERDAY';
    return F.dayMonth(d).toUpperCase();
  }

  Widget _separator(String label) => Row(
        children: [
          const Expanded(child: MpDivider()),
          const Gap(12),
          Text(label, style: tx(12, w: w600, c: MP.ink3, em: 0.06)),
          const Gap(12),
          const Expanded(child: MpDivider()),
        ],
      );

  Widget _liveMessage(Map<String, dynamic> m, Map<String, Map<String, dynamic>> byId) {
    final at = F.date(m['createdAt']);
    final time = at == null ? '' : F.time(at);
    final type = m['senderType'];
    final clinicSide = m['mine'] == true || type == 'doctor' || type == 'staff';
    final align = clinicSide ? Alignment.centerRight : Alignment.centerLeft;
    if (type == 'system') {
      return Center(child: Text(m.str('text'), textAlign: TextAlign.center, style: tx(13, c: MP.ink3, h: 1.4)));
    }
    if (m['deleted'] == true) {
      return Align(alignment: align, child: Text('Message deleted · $time', style: tx(14, c: MP.ink3)));
    }
    if (type == 'ai') return _aiMessage(text: m.str('text'), time: time);
    if (m['kind'] == 'voice') {
      final v = m.obj('voice');
      return Align(
        alignment: align,
        child: _liveVoice(v['durationSec'] is num ? _dur(v['durationSec'] as num) : '', time, v.obj('file').str('url')),
      );
    }
    if (m['kind'] == 'attachment' || m['kind'] == 'record') {
      final f = m.obj('attachment');
      final mb = f['sizeBytes'] is num ? (f['sizeBytes'] as num) / 1024 : null;
      final ext = f.str('name').contains('.') ? f.str('name').split('.').last.toUpperCase() : (m['kind'] == 'record' ? 'Record' : 'File');
      final meta = [ext, if (mb != null) mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} MB' : '${mb.round()} KB', time].join(' · ');
      return Align(
        alignment: align,
        child: _attachment(
          name: f.isEmpty ? m.str('text', 'Shared record') : f.str('name'),
          meta: meta,
          onTap: () {
            if (f.str('url').isNotEmpty) {
              d6OpenUrl(context, f.str('url'));
            } else if (m['prescriptionId'] != null) {
              Nav.go(context, 'Prescriptions', args: {'prescriptionId': '${m['prescriptionId']}', if (_patient.isNotEmpty) 'patientId': _patient.str('id')});
            } else {
              Nav.go(context, 'PP-Tests', args: _patient.isEmpty ? null : {'patientId': _patient.str('id')});
            }
          },
        ),
      );
    }
    if (clinicSide) {
      final quoted = byId[m.str('replyToId')];
      if (m['replyToId'] != null) {
        final qAt = F.date(quoted?['createdAt']);
        return _quotedReply(
          who: quoted == null ? 'Earlier message' : '${_senderName(quoted)}${qAt == null ? '' : ' · ${F.askedAt(qAt) == 'yesterday' ? 'Yesterday' : F.askedAt(qAt)}'}',
          quote: quoted == null ? '' : _summary(quoted),
          text: m.str('text'),
          time: time,
        );
      }
      return _doctorMessage(m.str('text'), time, read: m['deliveryStatus'] == 'seen' || m['seenAt'] != null);
    }
    // Patient text: a white bubble like the patient's voice note / file.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 288),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MP.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: m['isUrgent'] == true ? MP.redLine : MP.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(m.str('text'), style: tx(16, h: 1.5)),
                const Gap(4),
                Align(alignment: Alignment.centerRight, child: Text(time, style: tx(12, c: MP.ink3, tab: true))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Voice note bubble (live): play opens the recording.
  Widget _liveVoice(String duration, String time, String url) {
    return Container(
      width: 248,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MpHitSlop(child: Semantics(
                container: true,
                button: true,
                label: 'Play voice note${duration.isEmpty ? '' : ', $duration'}',
                child: ValueListenableBuilder<String?>(
                  valueListenable: VoiceNotes.playing,
                  builder: (context, now, _) => Tap(
                    onTap: () => VoiceNotes.toggle(context, url),
                    radius: 999,
                    color: MP.primarySoft,
                    child: SizedBox(width: 40, height: 40, child: Center(child: Ico(now == url ? I.pause : _playIcon, size: 18, color: MP.primary, filled: true))),
                  ),
                ),
              )),
              const Gap(12),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      for (var i = 0; i < _wave.length; i++) ...[
                        if (i > 0) const Gap(3),
                        Container(
                          width: 3,
                          height: _wave[i],
                          decoration: BoxDecoration(color: MP.primaryLine, borderRadius: BorderRadius.circular(999)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap(12),
              Text(duration, style: tx(13, c: MP.ink2, tab: true)),
            ],
          ),
          const Gap(4),
          Align(alignment: Alignment.centerRight, child: Text(time, style: tx(12, c: MP.ink3, tab: true))),
        ],
      ),
    );
  }

  Widget _liveMessages() {
    final items = data!.list('items');
    final byId = {for (final m in items) m.str('id'): m};
    final children = <Widget>[];
    DateTime? lastDay;
    for (final m in items) {
      final at = F.date(m['createdAt']);
      if (at != null && (lastDay == null || !F.sameDay(at, lastDay))) {
        children.add(_separator(_dayLabel(at)));
        lastDay = at;
      }
      final id = m.str('id');
      final key = _msgKeys.putIfAbsent(id, GlobalKey.new);
      final open = _menuFor == id;
      final by = _byLine(m);
      Widget w = KeyedSubtree(
        key: key,
        child: by.isEmpty
            ? _liveMessage(m, byId)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(by, textAlign: TextAlign.right, style: tx(12, w: w600, c: MP.ink3, h: 1.35)),
                  const Gap(4),
                  _liveMessage(m, byId),
                ],
              ),
      );
      if (m['senderType'] != 'system') {
        w = GestureDetector(
          onLongPress: () {
            setState(() => _menuFor = id);
            _menuPortal.show();
          },
          child: w,
        );
      }
      if (open) w = CompositedTransformTarget(link: _menuLink, child: w);
      children.add(w);
    }
    if (items.isEmpty) children.add(Center(child: Text('No messages yet', style: tx(14, c: MP.ink2))));
    final menuMsg = byId[_menuFor];
    final mine = menuMsg?['mine'] == true && menuMsg?['deleted'] != true;
    // The menu opens above the newest messages (next to the composer), below older ones.
    final below = items.indexWhere((m) => m.str('id') == _menuFor) < items.length - 2;
    final right = menuMsg?['mine'] == true;
    return OverlayPortal(
      controller: _menuPortal,
      overlayChildBuilder: (_) => Stack(
        children: [
          if (menuMsg != null)
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _menuLink,
                showWhenUnlinked: false,
                targetAnchor: below
                    ? (right ? Alignment.bottomRight : Alignment.bottomLeft)
                    : (right ? Alignment.topRight : Alignment.topLeft),
                followerAnchor: below
                    ? (right ? Alignment.topRight : Alignment.topLeft)
                    : (right ? Alignment.bottomRight : Alignment.bottomLeft),
                offset: Offset(0, below ? 8 : -8),
                child: TapRegion(
                  onTapOutside: (_) => setState(() => _menuFor = null),
                  child: Material(
                    type: MaterialType.transparency,
                    child: _menu(
                      items: [for (final it in _menuItems) if (mine || it.$1 != 'Delete for everyone') it],
                      onAction: (a) => _liveMenuAction(a, menuMsg),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: SingleChildScrollView(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const Gap(12), children[i]],
          ],
        ),
      ),
    );
  }

  final _menuPortal = OverlayPortalController();

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

  bool _menuOpen = !isLive;
  bool _voiceShown = true;
  bool _voicePinned = false;
  bool _hasText = false;
  final _sent = <(String, String)>[];

  @override
  void initState() {
    super.initState();
    // Create the voice-note controller now: the live thread may never build
    // it, and a lazy first use in dispose() would need an ancestor lookup.
    _voice.value;
    _reply.addListener(() {
      final has = _reply.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    if (Push.I.openChat == _convId) Push.I.openChat = null;
    // Replies that came in while the thread was open are read too.
    if (isLive && _readSent && _convId != null) Api.I.post('/api/conversations/$_convId/read', const {'pauseAi': false}).catchError((_) => null);
    _voice.dispose();
    _scroll.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    _busy.dispose();
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
    final placeholder = livePlaceholder();
    final live = data != null;
    final pinned = live ? data!.obj('pinned') : const <String, dynamic>{};
    final showAi = !live || (_conv['aiEnabled'] == true && _conv['type'] != 'direct');
    final showPinned = !live || pinned.isNotEmpty;
    return MpPage(
      header: _header(context),
      scroll: false,
      body: placeholder ?? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The patient's open emergency (staff only): what they wrote, who has seen it,
          // Call the patient · Doctor informed (desk) / Resolve (doctor).
          if (live && _conv['urgentAlert'] is Map) _urgentBanner(_conv.obj('urgentAlert')),
          // AI paused notice
          if (showAi) Container(
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
          if (showPinned) Tap(
            onTap: live ? _toPinnedLive : _toPinned,
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
                          TextSpan(
                            text: live ? ' ${_summary(pinned)}' : (_voicePinned ? ' Voice note · 0:18' : ' Take Metformin after food'),
                          ),
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
          Expanded(child: live ? _liveMessages() : _messages()),
        ],
      ),
      bottom: _composer(),
      overlays: [
        Positioned(
          left: 16,
          bottom: 92 + safeBottom,
          child: JumpToLatest(controller: _scroll, always: !live),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final live = data != null;
    final waiting = isLive && !live;
    final name = live ? _liveName : (waiting ? '' : 'Priya Sharma');
    final sub = live ? _liveSubtitle : (waiting ? '' : 'Last seen 2 min ago');
    final pid = live ? _patient.str('id') : '';
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(4),
          Expanded(
            child: MpHitSlop(child: Tap(
              onTap: () {
                if (!isLive) {
                  Nav.go(context, 'PP-Summary');
                } else if (pid.isNotEmpty) {
                  Nav.go(context, 'PP-Summary', args: {'patientId': pid});
                }
              },
              radius: 12,
              child: Row(
                children: [
                  if (!waiting) MpAvatar(live ? F.initials(name) : 'PS', size: 40, fontSize: 14, photo: live ? _livePhoto : null),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: tx(20, w: w700, h: 1.25),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (sub.isNotEmpty) Text(sub, style: tx(13, c: MP.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ),
          const Gap(4),
          if (live) MpIconButton(I.search, label: 'Search this chat', color: MP.ink2, onTap: _searchLive),
          MpIconButton(
            I.phone,
            label: 'Call $name',
            color: MP.primary,
            onTap: isLive ? (live ? _callLive : null) : () => toast(context, 'Calling Priya Sharma…'),
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
                    MpHitSlop(child: Semantics(
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
                    )),
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

  Widget _menu({List<(String, bool)> items = _menuItems, void Function(String)? onAction}) {
    final act = onAction ?? _menuAction;
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
          for (var i = 0; i < items.length; i++)
            Tap(
              onTap: () => act(items[i].$1),
              radius: 0,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Text(items[i].$1, style: items[i].$2 ? tx(16, w: w600, c: MP.red) : tx(16)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attachment({String name = 'Lipid profile.pdf', String meta = 'PDF · 240 KB · 9:06 AM', VoidCallback? onTap}) {
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
          onTap: onTap ?? () => Nav.go(context, 'PP-Tests'),
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
                    Text(name, style: tx(15, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(meta, style: tx(13, c: MP.ink3, tab: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiMessage({String text = "Thanks, Priya. I've shared your report with Dr. Sen's team.", String time = '9:06 AM'}) {
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
                Text(text, style: tx(16, h: 1.5)),
                const Gap(4),
                Align(alignment: Alignment.centerRight, child: Text(time, style: tx(12, c: MP.ink3, tab: true))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quotedReply({
    String who = 'Priya Sharma · Yesterday',
    String quote = 'Should I take the tablet before or after breakfast?',
    String text = 'After food, not before. Your lipid report looks fine.',
    String time = '9:22 AM',
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 288),
        child: IntrinsicWidth(
          child: Container(
            key: data == null ? _adviceKey : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'Replying to ${who.split(' · ').first}: $quote',
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
                        Text(who, style: tx(13, w: w600, c: MP.primarySoft)),
                        const Gap(2),
                        Text(
                          quote,
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
                Text(text, style: tx(16, c: MP.white, h: 1.5)),
                const Gap(6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(time, style: tx(12, c: MP.primarySoft, tab: true)),
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
                  onTap: isLive ? _attachLive : () => toast(context, 'Choose a photo, PDF or report to attach'),
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
                  child: MpFieldArea(child: TextField(
                    textAlignVertical: TextAlignVertical.center,
                    controller: _reply,
                    focusNode: _replyFocus,
                    style: tx(16),
                    cursorColor: MP.primary,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => data != null ? _sendLive() : _send(),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: _replyTo == null ? 'Write a reply' : 'Reply to ${_senderName(_replyTo!)}',
                      hintStyle: tx(16, c: MP.ink3),
                    ),
                  )),
                ),
              ),
              const Gap(8),
              Semantics(
                button: true,
                label: _hasText ? 'Send reply' : 'Record a voice reply',
                child: Tap(
                  onTap: _hasText ? (data != null ? _sendLive : _send) : _voiceLive,
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

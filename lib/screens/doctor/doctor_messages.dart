import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';
import '../../data/nav_counts.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-Messages.dc.html — "Doctor · Messages tab".
/// Live data: GET /api/inbox?type=all (care + nutrition), ?type=direct
/// (colleagues) and /api/inbox/contacts (colleague names).
class DoctorMessagesScreen extends StatefulWidget {
  const DoctorMessagesScreen({super.key});

  @override
  State<DoctorMessagesScreen> createState() => _DoctorMessagesScreenState();
}

class _Chat {
  final String ini;
  final String name;
  final String role;
  final String msg;
  final String time;
  final String unread;

  /// Colleague / staff chats use a rounded-square grey avatar.
  final bool team;

  /// Live: the conversation id.
  final String? id;
  const _Chat(this.ini, this.name, this.role, this.msg, this.time, this.unread, [this.team = false, this.id]);

  Map<String, String>? get args => id == null ? null : {'conversationId': id!};

  bool get isUnread => unread.isNotEmpty;

  bool matches(String q) {
    final s = q.toLowerCase();
    return name.toLowerCase().contains(s) || role.toLowerCase().contains(s) || msg.toLowerCase().contains(s);
  }
}

const _tabs = ['All', 'Unread', 'Patients', 'Colleagues'];

const _chats = [
  _Chat('AK', 'Aisha Khan', 'Patient · Hypothyroidism', 'Shared a file: Thyroid profile, 28 Sep', '9:40 AM', '1'),
  _Chat(
    'RM',
    'Dr. Rina Mitra',
    'Colleague · Cardiology',
    'Saw the lipid report. Can we talk about the statin dose?',
    '9:12 AM',
    '1',
    true,
  ),
  _Chat(
    'FD',
    'Front desk · City Care',
    'Your staff',
    'Vitals entered for Rahul Das. He is next.',
    '9:05 AM',
    '1',
    true,
  ),
  _Chat(
    'MB',
    'Mou Banerjee',
    'Colleague · Dietician',
    'Sent the low-protein meal plan for Amit Pal.',
    'Yesterday',
    '',
    true,
  ),
  _Chat('AP', 'Amit Pal', 'Patient · Diabetes, CKD', 'You: Please come fasting on Friday.', 'Yesterday', ''),
  _Chat('MR', 'Moumita Roy', 'Patient · Cardiology review', 'You: Please bring your ECG reports.', '29 Sep', ''),
  _Chat(
    'NG',
    'Dr. Nandita Gupta',
    'Colleague · Apollo Clinic',
    'Referral for Farhana Islam received. Thank you.',
    '27 Sep',
    '',
    true,
  ),
  _Chat('DB', 'Debasish Bose', 'Patient · Type 2 diabetes', 'Shared his sugar log · last 7 days', '26 Sep', ''),
];

/// The urgent patient chat pinned above the list.
const _urgent = _Chat('PS', 'Priya Sharma', 'Urgent · patient', '“Chest tightness, hard to breathe.”', '9:58 AM', '2');

/// "New chat" pen icon (the design's 2.1 variant of the edit glyph).
const _pen = '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>';

class _DoctorMessagesScreenState extends State<DoctorMessagesScreen> with LiveData {
  int _tab = 0;
  String _query = '';

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/inbox', query: {'type': 'all'}),
      Api.I.get('/api/inbox', query: {'type': 'direct'}),
      Api.I.get('/api/inbox/contacts'),
    ]);
    return {'all': r[0], 'direct': r[1], 'contacts': r[2]};
  }

  @override
  Duration? get refreshEvery => const Duration(seconds: 30);

  bool _inTab(_Chat c) => switch (_tab) {
    1 => c.isUnread,
    2 => !c.team,
    3 => c.team,
    _ => true,
  };

  bool _show(_Chat c) => _inTab(c) && (_query.trim().isEmpty || c.matches(_query.trim()));

  /// "You: Please come fasting." / "Tania: …" / the patient's own words.
  static String _preview(Map<String, dynamic> last) {
    final text = last.str('text');
    final type = last['senderType'];
    if (type == null || type == 'patient') return text;
    final label = last.str('senderLabel');
    final me = Session.I.name.split(' ').first;
    if (label == me) return 'You: $text';
    if (label.isEmpty || label == 'Dr.' || label == 'Clinic') return text;
    return '$label: $text';
  }

  _Chat _patientChat(Map<String, dynamic> c) {
    final p = c.obj('patient');
    final conds = [for (final x in (p['conditions'] as List? ?? const [])) '$x'];
    final n = c.numOr('unread').toInt();
    return _Chat(
      F.initials(p.str('name', 'Patient')),
      p.str('name', 'Patient'),
      [c['type'] == 'nutrition' ? 'Patient · nutrition' : 'Patient', if (conds.isNotEmpty) conds.join(', ')].join(' · '),
      _preview(c.obj('lastMessage')),
      d2ChatTime(c.obj('lastMessage')['at']),
      n > 0 ? '$n' : '',
      false,
      c.str('id'),
    );
  }

  _Chat _directChat(Map<String, dynamic> c, Map<String, Map<String, dynamic>> team) {
    final me = '${Session.I.user['id']}';
    final other = c.list('participants').firstWhere((p) => '${p['userId']}' != me, orElse: () => const {});
    final t = team['${other['userId']}'] ?? const <String, dynamic>{};
    final name = t.str('name', 'Colleague');
    final staff = t['role'] != null && t['role'] != 'doctor' && t['role'] != 'dietician';
    final role = staff
        ? 'Your staff · ${d2Role(t['role'])}'
        : ['Colleague', if (t['role'] == 'dietician') 'Dietician' else if (t.str('department').isNotEmpty) t.str('department')].join(' · ');
    final n = c.numOr('unread').toInt();
    return _Chat(F.initials(name), name, role, _preview(c.obj('lastMessage')), d2ChatTime(c.obj('lastMessage')['at']), n > 0 ? '$n' : '', true, c.str('id'));
  }

  /// Live (urgent chat, other chats newest first, unread conversations, urgent count).
  (_Chat?, List<_Chat>, int, int) get _live {
    final d = data!;
    final team = {for (final t in d.obj('contacts').list('team')) '${t['userId']}': t};
    final care = d.obj('all').list('items');
    final urgentRow = care.where((c) => c['isUrgent'] == true).firstOrNull;
    final rows = <(DateTime, _Chat)>[
      for (final c in care)
        if (c != urgentRow) (F.date(c.obj('lastMessage')['at']) ?? DateTime(2000), _patientChat(c)),
      for (final c in d.obj('direct').list('items')) (F.date(c.obj('lastMessage')['at']) ?? DateTime(2000), _directChat(c, team)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final unread = d.obj('all').numOr('unread').toInt() + d.obj('direct').numOr('unread').toInt();
    // The tab-bar badge shows the same number as the header.
    WidgetsBinding.instance.addPostFrameCallback((_) => NavCounts.setMessages(unread));
    final urgent = urgentRow == null
        ? null
        : () {
            final c = _patientChat(urgentRow);
            final text = urgentRow.obj('lastMessage').str('text');
            return _Chat(c.ini, c.name, 'Urgent · patient', text.isEmpty ? '' : '“$text”', c.time, c.unread, false, c.id);
          }();
    return (urgent, [for (final r in rows) r.$2], unread, d.obj('all').numOr('urgent').toInt());
  }

  /// Opens the thread; back here, unread counts are fetched again.
  Future<void> _open(_Chat c) async {
    await Nav.go(context, 'Patient-Thread', args: c.args);
    if (mounted && isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = data == null ? null : _live;
    final rows = (live?.$2 ?? _chats).where(_show).toList();
    final urgent = live == null ? _urgent : live.$1;
    final showUrgent = urgent != null && _show(urgent);
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final subtitle = live == null
        ? '4 unread · 1 urgent'
        : [
            live.$3 == 0 ? 'No unread' : '${live.$3} unread',
            if (live.$4 > 0) '${live.$4} urgent',
          ].join(' · ');
    return MpPage(
      header: D2TabHeader(
        title: 'Messages',
        subtitle: subtitle,
        search: D2SearchField(
          hint: 'Search people or messages',
          height: 48,
          onChanged: (v) => setState(() => _query = v),
        ),
        chips: [
          for (var i = 0; i < _tabs.length; i++)
            D2Chip(_tabs[i], selected: i == _tab, onTap: () => setState(() => _tab = i)),
        ],
      ),
      nav: const DoctorNav(current: 2),
      overlays: [
        Positioned(
          right: 20,
          bottom: 104 + safeBottom,
          child: Semantics(
            button: true,
            label: 'New chat',
            child: Tap(
              onTap: () async {
                await Nav.go(context, 'Doctor-Messages-New');
                if (mounted && isLive) reload(quiet: true);
              },
              radius: 999,
              color: MP.primary,
              shadow: const [...MPShadow.button, ...MPShadow.float],
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(_pen, size: 20, color: MP.white),
                      const Gap(8),
                      Text('New chat', style: tx(16, w: w600, c: MP.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      body: placeholder ?? VGap(
        // 184px bottom = MpPage's 112px nav space + 72px for the "New chat" button.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
        gap: 16,
        children: [
          if (showUrgent) _UrgentCard(chat: urgent, onTap: () => _open(urgent)),
          if (rows.isNotEmpty)
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: MPDeco.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _ChatRow(rows[i], first: i == 0, onTap: () => _open(rows[i])),
                ],
              ),
            ),
          if (!showUrgent && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No chats found', textAlign: TextAlign.center, style: tx(14, c: MP.ink2)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Patient chats are saved to their records. Urgent messages also alert your front desk.',
              textAlign: TextAlign.center,
              style: tx(12, c: MP.ink3, h: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unread count pill: min 22×22, padding 0 6, 12/700 white.
class _Count extends StatelessWidget {
  final String n;
  final Color bg;
  const _Count(this.n, this.bg);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(n, style: tx(12, w: w700, c: MP.white, h: 1)),
    );
  }
}

class _UrgentCard extends StatelessWidget {
  final _Chat chat;
  final VoidCallback onTap;
  const _UrgentCard({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final u = chat;
    return Tap(
      onTap: onTap,
      radius: 20,
      color: MP.redSoft,
      border: MP.redLine,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 48×48 content box + 1px border → 50×50.
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: MP.white, shape: BoxShape.circle, border: Border.all(color: MP.redLine)),
            child: Text(u.ini, style: tx(15, w: w700, c: MP.red, h: 1)),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(u.name, style: tx(16, w: w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const Gap(8),
                    Text(u.time, style: tx(12, w: w700, c: MP.red)),
                  ],
                ),
                const Gap(4),
                Text(u.role.toUpperCase(), style: tx(12, w: w800, c: MP.red, em: 0.06)),
                const Gap(4),
                Row(
                  children: [
                    Expanded(
                      child: Text(u.msg, style: tx(14, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const Gap(8),
                    if (u.isUnread) _Count(u.unread, MP.red),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final _Chat c;
  final bool first;
  final VoidCallback onTap;
  const _ChatRow(this.c, {required this.first, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final u = c.isUnread;
    return Tap(
      onTap: onTap,
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: MpAvatar(
                c.ini,
                size: 48,
                fontSize: 15,
                radius: c.team ? 14 : null,
                bg: c.team ? MP.fill : MP.primarySoft,
                fg: c.team ? MP.ink2 : MP.primary,
              ),
            ),
            const Gap(12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            c.name,
                            style: tx(16, w: u ? w700 : w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Gap(8),
                        Text(c.time, style: tx(12, w: u ? w700 : w500, c: u ? MP.primary : MP.ink3)),
                      ],
                    ),
                    const Gap(3),
                    Text(c.role, style: tx(12, c: MP.ink3), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const Gap(3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.msg,
                            style: tx(14, w: u ? w600 : w400, c: u ? MP.ink : MP.ink2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (u) ...[const Gap(8), _Count(c.unread, MP.primary)],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

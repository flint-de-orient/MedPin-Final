import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Staff-Patients.dc.html — "Patients" (front desk).
class StaffPatientsScreen extends StatefulWidget {
  const StaffPatientsScreen({super.key});

  @override
  State<StaffPatientsScreen> createState() => _StaffPatientsScreenState();
}

/// Chip colours (bg, fg).
const _chipColors = <String, (Color, Color)>{
  'Needs attention': (MP.amberSoft, MP.amber),
  'Check-in due': (MP.fill, MP.ink2),
};

/// (initials, name, time, unread, who, text, chip ('' = none))
typedef _Conv = (String, String, String, int, String, String, String);

/// API triage → chip label.
const _triageLabels = {'needs_attention': 'Needs attention', 'check_in_due': 'Check-in due', 'review_due': 'Review due'};

const List<_Conv> _rows = [
  ('PS', 'Priya Sharma', '9:12 AM', 2, 'Priya', 'Chest feels tight since morning, should I come in?', 'Needs attention'),
  ('RD', 'Rahul Das', '8:40 AM', 1, 'Rahul', 'BP was 172/104 this morning, feeling a bit dizzy', 'Needs attention'),
  ('SM', 'Sujit Mondal', '8:22 AM', 1, 'Sujit', 'Should I take the tablet before or after breakfast?', ''),
  ('AK', 'Aisha Khan', '7:50 AM', 1, 'AI', 'Your TSH report is in. Dr. Sen will review it today.', 'Check-in due'),
  ('FI', 'Farhana Islam', '7:15 AM', 1, 'You', 'Your appointment is confirmed for Thu, 1 Oct at 11:00 AM.', ''),
  ('AP', 'Amit Pal', 'Yesterday', 1, 'Amit', 'Missed my evening Metformin again, will restart today', 'Needs attention'),
  ('MR', 'Moumita Roy', 'Yesterday', 0, 'Dr. Sen', 'Keep Ecosprin going and walk 20 minutes daily.', 'Check-in due'),
  ('DB', 'Debasish Bose', 'Sun', 0, 'Dr. Sen', 'Please repeat HbA1c before your next visit.', 'Check-in due'),
];

/// Front-desk tabs with the unread count on Patients (as in this design);
/// StaffNav adds Payments for the desk and the assistant's tabs.
Widget _nav(int? badge) => StaffNav(current: 1, patientsBadge: badge);

/// Live data: GET /api/inbox?type=all (care + nutrition chats, unread counts,
/// pending enrolments) and the notification count, refreshed every 30 s.
class _StaffPatientsScreenState extends State<StaffPatientsScreen> with LiveData {
  int _tab = 1;
  String _query = '';
  int _limit = 20;

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/inbox', query: {'type': 'all'}),
      Api.I.get('/api/notifications', query: {'limit': '1', if (Session.I.practiceId != null) 'practiceId': Session.I.practiceId}),
    ]);
    return {...(r[0] as Map).cast<String, dynamic>(), 'unreadNotifications': (r[1] as Map)['unread'] ?? 0};
  }

  @override
  Duration? get refreshEvery => const Duration(seconds: 30);

  /// "9:12 AM" today, "Yesterday", "Sun" this week, else "28 Sep".
  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    if (F.sameDay(at, now)) return F.time(at);
    if (F.sameDay(at, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    if (now.difference(at).inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];
    return F.dayMonth(at);
  }

  /// Who wrote the last message, as the row's bold prefix.
  static String _who(Map<String, dynamic> c) {
    final m = c.obj('lastMessage');
    if (m['senderId'] != null && '${m['senderId']}' == '${Session.I.user['id']}') return 'You';
    return switch (m['senderType']) {
      'patient' => F.firstName(c.obj('patient').str('name')),
      'ai' => 'AI',
      _ => m.str('senderLabel', 'Clinic'),
    };
  }

  /// Rows with their conversation id (null in the design preview).
  List<(_Conv, String?)> get _all {
    if (data == null) return [for (final r in _rows) (r, null)];
    return [
      for (final c in data!.list('items'))
        (
          (
            F.initials(c.obj('patient').str('name', '?')),
            c.obj('patient').str('name', 'Patient'),
            _when(F.date(c.obj('lastMessage')['at'])),
            c.numOr('unread').toInt(),
            _who(c),
            c.obj('lastMessage').str('text'),
            _triageLabels[c['triage']] ?? '',
          ),
          c.str('id'),
        ),
    ];
  }

  int get _unread => data == null ? 6 : data!.numOr('unread').toInt();
  int get _pending => data == null ? 2 : data!.numOr('pendingEnrolments').toInt();
  int get _notes => data == null ? 2 : data!.numOr('unreadNotifications').toInt();

  Future<void> _open(String? conversationId) async {
    await Nav.go(context, 'Patient-Thread', args: conversationId == null ? null : {'conversationId': conversationId});
    if (mounted && isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final matching = [
      for (final r in _all)
        if ((_tab == 1 || r.$1.$4 > 0) &&
            (q.isEmpty || '${r.$1.$2} ${r.$1.$5} ${r.$1.$6}'.toLowerCase().contains(q)))
          r,
    ];
    final shown = data == null ? matching : matching.take(_limit).toList();
    final placeholder = livePlaceholder();
    return MpPage(
      nav: _nav(data == null ? 6 : (_unread > 0 ? _unread : null)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D10StaffHeader(bellLabel: _notes > 0 ? 'Notifications, $_notes new' : 'Notifications', dot: _notes > 0 ? MP.red : MP.line),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              Text('Patients', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              MpSegmented(
                options: ['Unread ($_unread)', 'All'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              D10SearchField(
                hint: 'Search patients or messages',
                padLeft: 48,
                onChanged: (v) => setState(() => _query = v),
              ),
              if (_pending > 0) _EnrolmentBanner(count: _pending, onView: () => Nav.go(context, 'Add-Patient-Existing')),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    q.isNotEmpty ? 'No conversations match “${_query.trim()}”' : (_tab == 0 ? 'No unread messages' : 'No conversations yet'),
                    textAlign: TextAlign.center,
                    style: tx(14, c: MP.ink3, h: 20 / 14),
                  ),
                )
              else
                Semantics(
                  label: 'Conversations',
                  container: true,
                  child: D10ListCard(
                    children: [
                      for (var i = 0; i < shown.length; i++) _ConvRow(shown[i].$1, divider: i > 0, onTap: () => _open(shown[i].$2)),
                    ],
                  ),
                ),
              if (data == null || matching.length > shown.length)
                MpButton(
                  'Show more',
                  kind: MpBtn.secondary,
                  onTap: data == null ? () => toast(context, 'No more conversations') : () => setState(() => _limit += 20),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// #EBF1FB note: pending enrolments + "View".
class _EnrolmentBanner extends StatelessWidget {
  final int count;
  final VoidCallback onView;
  const _EnrolmentBanner({required this.count, required this.onView});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Ico(I.clock, size: 20, color: MP.primary),
          const Gap(12),
          Expanded(
            child: Text(
              "$count ${count == 1 ? 'enrolment' : 'enrolments'} waiting on the patient's confirmation code",
              style: tx(14, h: 1.45),
            ),
          ),
          const Gap(12),
          MpHitSlop(child: Tap(
            onTap: onView,
            radius: 8,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              child: Text('View', style: tx(14, w: w600, c: MP.primary)),
            ),
          )),
        ],
      ),
    );
  }
}

class _ConvRow extends StatelessWidget {
  final _Conv r;
  final bool divider;
  final VoidCallback onTap;
  const _ConvRow(this.r, {required this.divider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = r.$4 > 0;
    final chip = _chipColors[r.$7];
    final label = '${r.$2}${unread ? ', ${r.$4} unread' : ''}, ${r.$3}';
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: D10ListRow(
        divider: divider,
        vPad: 14,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: MP.primarySoft, shape: BoxShape.circle),
              child: Text(r.$1, style: tx(16, w: w600, c: MP.primary, h: 1)),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(16, w: w600, h: 24 / 16),
                        ),
                      ),
                      const Gap(8),
                      Text(
                        r.$3,
                        style: tx(
                          13,
                          w: unread ? w600 : w400,
                          c: unread ? MP.primary : MP.ink3,
                          h: 24 / 13,
                          tab: true,
                        ),
                      ),
                    ],
                  ),
                  const Gap(2),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${r.$5}:', style: tx(14, w: w600, c: unread ? MP.ink : MP.ink2, h: 20 / 14)),
                              TextSpan(text: ' ${r.$6}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(14, c: unread ? MP.ink : MP.ink2, h: 20 / 14),
                        ),
                      ),
                      if (unread) ...[
                        const Gap(8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(999)),
                          child: Text('${r.$4}', style: tx(12, w: w700, c: MP.white, h: 1, tab: true)),
                        ),
                      ],
                    ],
                  ),
                  if (chip != null) ...[
                    const Gap(8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MpBadge(r.$7, bg: chip.$1, fg: chip.$2, weight: w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

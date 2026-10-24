import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/notify_route.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

/// Staff notifications (doctor, front desk, every clinic role): visit requests,
/// cancellations, messages, shared records, reminders — for the active clinic.
/// Tap opens the related screen and marks it read; "Mark all read" clears the
/// bell. Roles that handle clinical alerts get a link to Clinical alerts.
/// Each tap goes to a screen this role can open (data/notify_route.dart: the
/// desk's emergency opens the patient's chat, fees open Payments).
/// Real time: a new notification (push, or a silent "notifications_changed"
/// when it doesn't buzz) refreshes the list at once (LiveBus); unread
/// emergencies and urgent chats show a red dot until read or resolved.
/// Live data: GET /api/notifications?practiceId=, POST /:id/read, /read-all.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with LiveData {
  static final _sample = [
    {'id': 'n1', 'title': 'New visit request', 'body': 'Farhana Islam asked for a visit with Dr. Sen', 'createdAt': null, 'when': '8:20 AM', 'readAt': null},
    {'id': 'n2', 'title': 'Message from Priya Sharma', 'body': 'Should I take the tablet before or after food?', 'when': '7:52 AM', 'readAt': null},
    {'id': 'n3', 'title': 'Appointment cancelled', 'body': 'Amit Pal cancelled the 10:30 AM visit', 'when': 'Yesterday', 'readAt': 'x'},
  ];

  @override
  Future<Object?> fetch() => Api.I.get('/api/notifications', query: {'limit': '50', if (Session.I.practiceId != null) 'practiceId': Session.I.practiceId});

  // New ones also arrive at once (push / silent signal → LiveBus); this is the backup.
  @override
  Duration? get refreshEvery => const Duration(seconds: 15);

  /// Emergencies and urgent chats (red, like the bell's dot).
  static bool _urgent(Map<String, dynamic> n) => RegExp('emergency|urgent').hasMatch(n.str('type'));

  List<Map<String, dynamic>> get _items {
    if (data == null) return [for (final s in _sample) Map<String, dynamic>.from(s)];
    return [
      for (final n in data!.list('items'))
        {...n, 'when': () {
          final at = F.date(n['createdAt']);
          if (at == null) return '';
          final now = DateTime.now();
          if (F.sameDay(at, now)) return F.time(at);
          if (F.sameDay(at, now.subtract(const Duration(days: 1)))) return 'Yesterday';
          return F.dayMonth(at);
        }()},
    ];
  }

  int get _unread => data == null ? (isLive ? 0 : 2) : data!.numOr('unread').toInt();

  Future<void> _open(Map<String, dynamic> n) async {
    if (!isLive) {
      toast(context, n.str('title'));
      return;
    }
    if (n['readAt'] == null) {
      await runAction(context, () => Api.I.post('/api/notifications/${n['id']}/read'));
    }
    if (!mounted) return;
    final params = n['params'] is Map ? (n['params'] as Map).cast<String, dynamic>() : null;
    await openStaffNotification(context, screen: n.str('screen'), type: n.str('type'), params: params, practiceId: n['practiceId']?.toString());
    if (mounted) reload(quiet: true);
  }

  Future<void> _readAll() async {
    if (!isLive) return toast(context, 'All caught up');
    final ok = await runAction(context, () => Api.I.post('/api/notifications/read-all', {if (Session.I.practiceId != null) 'practiceId': Session.I.practiceId}));
    if (ok != null && mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final items = _items;
    final alerts = !isLive || Session.I.can('alerts');
    return MpPage(
      header: MpHeader(
        'Notifications',
        subtitle: _unread > 0 ? '$_unread new' : 'All caught up',
        actions: [if (_unread > 0) MpLink('Mark all read', onTap: _readAll)],
      ),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 12,
            children: [
              if (alerts)
                Tap(
                  onTap: () => Nav.go(context, 'Alerts'),
                  radius: 16,
                  color: MP.redSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Ico(I.emergency, size: 22, color: MP.red),
                      const Gap(12),
                      Expanded(child: Text('Clinical alerts', style: tx(16, w: w600, c: MP.red))),
                      const Ico(I.chevronRight, size: 18, color: MP.red, stroke: 2),
                    ],
                  ),
                ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text('No notifications yet', textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.5)),
                ),
              for (final n in items)
                Tap(
                  onTap: () => _open(n),
                  radius: 16,
                  color: MP.white,
                  border: MP.line,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: n['readAt'] == null ? (_urgent(n) ? MP.red : MP.primary) : Colors.transparent, shape: BoxShape.circle),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(n.str('title'), style: tx(15, w: n['readAt'] == null ? w700 : w600, h: 1.35))),
                                const Gap(8),
                                Text(n.str('when'), style: tx(13, c: MP.ink3, h: 1.35)),
                              ],
                            ),
                            if (n.str('body').isNotEmpty) ...[
                              const Gap(2),
                              Text(n.str('body'), maxLines: 3, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2, h: 1.4)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
    );
  }
}

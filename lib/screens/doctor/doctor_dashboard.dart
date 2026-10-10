import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';

/// Design: Doctor-Dashboard.dc.html — "Doctor · dashboard (redesign)".
/// Live data: GET /api/dashboard.
class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> with LiveData {
  static const _sampleStats = [
    ('12', 'Total appointments', MP.ink, 'Appointments'),
    ('9', 'Pending consultations', MP.amber, 'Queue-List'),
    ('3', 'Completed consultations', MP.green, 'Doctor-History'),
  ];

  @override
  Future<Object?> fetch() => Api.I.get('/api/dashboard');

  @override
  Duration? get refreshEvery => const Duration(seconds: 60);

  List<(String, String, Color, String)> get _stats {
    final d = data;
    if (d == null) return _sampleStats;
    final t = d.obj('today');
    return [
      ('${t.numOr('total')}', 'Total appointments', MP.ink, 'Appointments'),
      ('${t.numOr('pending')}', 'Pending consultations', MP.amber, 'Queue-List'),
      ('${t.numOr('completed')}', 'Completed consultations', MP.green, 'Doctor-History'),
    ];
  }

  String get _name => data?.str('greetingName') ?? 'Dr. Arjun Sen';
  int get _unread => data == null ? 3 : data!.numOr('unreadNotifications').toInt();

  String get _dateLine {
    final d = data;
    if (d == null) return 'Thu, 1 Oct 2026 · City Care, Salt Lake';
    final place = [d.str('practiceName'), d.str('location')].where((x) => x.isNotEmpty).join(', ');
    final today = F.dateLong(DateTime.now());
    return place.isEmpty ? today : '$today · $place';
  }

  /// The newest open emergency (live), or the design's sample.
  Map<String, dynamic>? get _emergency {
    final d = data;
    if (d == null) return const {'patient': 'Priya Sharma', 'detail': 'Chest tightness, hard to breathe.', 'ago': '2 min ago'};
    for (final a in d.list('alerts')) {
      if (a['severity'] == 'emergency') {
        final at = F.date(a['at']);
        return {...a, 'ago': at == null ? '' : F.ago(at)};
      }
    }
    return null;
  }

  static const _actions = [
    (I.users, 'Patient queue', 'Queue-Select'),
    (I.userPlus, 'New patient', 'Add-Patient'),
    (I.fileText, 'Prescriptions', 'Prescriptions'),
    (I.flask, 'Test results', 'PP-Tests'),
    (I.mic, 'Start consultation', 'Consult-Pick'),
    (I.calendarDots, 'Follow-ups', 'Doctor-FollowUps'),
  ];

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final emergency = _emergency;
    return MpPage(
      nav: const DoctorNav(current: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: logo + bell + avatar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const MpLogo(),
                const Spacer(),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MpIconButton(
                      I.bell,
                      label: _unread > 0 ? 'Notifications, $_unread new' : 'Notifications',
                      iconSize: 20,
                      radius: 999,
                      background: MP.white,
                      borderColor: MP.line,
                      onTap: () => Nav.go(context, 'Notifications'),
                    ),
                    if (_unread > 0) Positioned(
                      top: 10,
                      right: 11,
                      child: IgnorePointer(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: MP.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: MP.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                Tap(
                  onTap: () => Nav.go(context, 'Doctor-MyProfile'),
                  radius: 999,
                  child: MpAvatar(F.initials(_name), size: 44, fontSize: 15),
                ),
              ],
            ),
          ),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 20,
            children: [
              // Greeting
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hi, ${F.doctorShort(_name)}', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                  const Gap(4),
                  Text('Good to see you again', style: tx(15, c: MP.ink2)),
                  const Gap(8),
                  Row(
                    children: [
                      const Ico(I.calendar, size: 16, color: MP.primary),
                      const Gap(8),
                      Flexible(child: Text(_dateLine, style: tx(14, w: w600, c: MP.primary))),
                    ],
                  ),
                ],
              ),

              // Stats
              MpGrid(
                columns: 3,
                children: [
                  for (final s in _stats)
                    MpCard(
                      onTap: () => Nav.go(context, s.$4),
                      radius: 16,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Text(s.$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true, c: s.$3)),
                          const Gap(6),
                          Text(s.$2, textAlign: TextAlign.center, style: tx(13, c: MP.ink2, h: 1.3)),
                        ],
                      ),
                    ),
                ],
              ),

              // Emergency (only while one is open)
              if (emergency != null) Tap(
                onTap: () => Nav.go(context, 'Patient-Thread', args: emergency['conversationId']),
                radius: 20,
                color: MP.redSoft,
                border: MP.redLine,
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MpIconTile(I.emergency, bg: MP.red, fg: MP.white, iconSize: 24, stroke: 2.25),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('Emergency · ${emergency['patient'] ?? ''}', style: tx(17, w: w700))),
                              const Gap(8),
                              const Ico(I.chevronRight, size: 18, color: MP.red, stroke: 2),
                            ],
                          ),
                          const Gap(6),
                          Text.rich(
                            TextSpan(
                              text: 'Urgent chat message: ',
                              style: tx(14, c: MP.ink2, h: 1.5),
                              children: [TextSpan(text: '“${emergency['detail'] ?? ''}”', style: tx(14, h: 1.5))],
                            ),
                          ),
                          const Gap(6),
                          Row(
                            children: [
                              const Ico(I.clock, size: 14, color: MP.red, stroke: 2),
                              const Gap(4),
                              Text('${emergency['ago']}', style: tx(14, w: w600, c: MP.red)),
                              const Gap(10),
                              Text('·', style: tx(14, w: w600, c: MP.redMuted)),
                              const Gap(10),
                              Text(
                                'Review now',
                                style: tx(14, w: w800, c: MP.red, deco: TextDecoration.underline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Quick actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Quick actions', style: tx(18, w: w700)),
                  const Gap(12),
                  MpGrid(
                    columns: 3,
                    children: [
                      for (final a in _actions)
                        SizedBox(
                          height: 112,
                          child: MpCard(
                            onTap: () => Nav.go(context, a.$3),
                            radius: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                            // Two-line labels are taller than the 82px content box; like
                            // the CSS (centered, overflow visible) they spill into the padding.
                            child: OverflowBox(
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MpIconTile(a.$1),
                                  const Gap(10),
                                  Text(a.$2, textAlign: TextAlign.center, style: tx(14, w: w600, h: 1.25)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // AI Assistant
              Tap(
                onTap: () => Nav.go(context, 'Doctor-AI'),
                radius: 20,
                color: MP.primary,
                shadow: MPShadow.hero,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MP.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: MP.white.withValues(alpha: 0.22)),
                      ),
                      child: const Ico(I.sparkles, size: 24, color: MP.white),
                    ),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('AI Assistant', style: tx(17, w: w700, c: MP.white)),
                              const Gap(8),
                              Container(
                                height: 20,
                                padding: const EdgeInsets.symmetric(horizontal: 7),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: MP.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: MP.white.withValues(alpha: 0.28)),
                                ),
                                child: Text('NEW', style: tx(11, w: w800, c: MP.white, em: 0.06, h: 1)),
                              ),
                            ],
                          ),
                          const Gap(4),
                          Text(
                            'Instant summaries, draft prescriptions, patient insights and more.',
                            style: tx(14, h: 1.45, c: MP.white.withValues(alpha: 0.82)),
                          ),
                        ],
                      ),
                    ),
                    const Gap(14),
                    Opacity(opacity: 0.8, child: const Ico(I.chevronRight, size: 20, color: MP.white, stroke: 2)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

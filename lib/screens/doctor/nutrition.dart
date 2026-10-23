import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d8.dart';
import '../../widgets/i18n.dart';
import 'team_chats.dart';

/// Design: Nutrition.dc.html — "Nutrition" (Clinician · tabs): food logs and
/// dietician conversations.
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _Conv {
  final String initials;
  final String name;
  final String time;
  final int unread;
  final String who;
  final String text;
  final String chip;
  final String meta;

  /// Thread to open (live data only).
  final String? conversationId;
  final String? patientId;

  /// The patient's profile photo (live data only).
  final String? photo;
  const _Conv(
    this.initials,
    this.name,
    this.time,
    this.unread,
    this.who,
    this.text,
    this.chip,
    this.meta, {
    this.conversationId,
    this.patientId,
    this.photo,
  });
}

const _rows = [
  _Conv(
    'PS',
    'Priya Sharma',
    '8:14 AM',
    2,
    'AI',
    'Good pick. Add a bowl of curd to balance the carbs.',
    'Review due',
    'Meal logged 8:10 AM',
  ),
  _Conv(
    'AP',
    'Amit Pal',
    '7:52 AM',
    1,
    'AI',
    'Go easy on salt today and skip the papad and pickle.',
    '',
    'Meal logged 7:40 AM',
  ),
  _Conv(
    'DB',
    'Debasish Bose',
    '7:30 AM',
    1,
    'Dietician',
    'Swap white rice for one cup of brown rice at lunch.',
    'Review due',
    'Meal logged 7:05 AM',
  ),
  _Conv(
    'FI',
    'Farhana Islam',
    'Yesterday',
    0,
    'Clinic',
    'Please log dinner too so Mou can check your iron intake.',
    '',
    'Meal logged yesterday 1:20 PM',
  ),
  _Conv(
    'AK',
    'Aisha Khan',
    'Yesterday',
    0,
    'Dietician',
    'Great week. Keep soy foods apart from your thyroid tablet.',
    '',
    'Meal logged yesterday 9:45 AM',
  ),
  _Conv(
    'MR',
    'Moumita Roy',
    'Sun',
    0,
    'AI',
    'Steamed fish with vegetables fits your heart-healthy plan.',
    '',
    'Meal logged Sun 1:30 PM',
  ),
  _Conv(
    'RD',
    'Rahul Das',
    'Sat',
    0,
    'Dietician',
    'Aim for under 5 g salt a day, about one teaspoon.',
    '',
    'Meal logged Sat 8:20 PM',
  ),
];

class _NutritionScreenState extends State<NutritionScreen> with LiveData {
  /// 0 = "Unread (3)", 1 = "All" (selected in the design).
  int _filter = 1;
  String _query = '';

  /// Live rows shown before "Show more".
  static const _page = 20;
  int _shown = _page;

  @override
  Future<Object?> fetch() async {
    // The list, and the unread chats with colleagues (the Team tab).
    final r = await Future.wait([
      Api.I.get('/api/inbox', query: {'type': 'nutrition'}),
      Api.I.get('/api/inbox', query: {'type': 'direct', 'tab': 'unread'}).catchError((_) => const <String, dynamic>{}),
    ]);
    return {...(r[0] as Map).cast<String, dynamic>(), 'teamUnread': (r[1] as Map)['unread'] ?? 0};
  }

  int get _teamUnread => data == null ? 0 : data!.numOr('teamUnread').toInt();

  @override
  Duration? get refreshEvery => const Duration(seconds: 60);

  /// "Meal logged 8:10 AM", "Meal logged yesterday 1:20 PM", "Meal logged Sun 1:30 PM".
  static String _mealLogged(DateTime? at) {
    if (at == null) return '';
    final t = d8ListTime(at);
    if (t == 'Yesterday') return 'Meal logged yesterday ${F.time(at)}';
    if (t.length == 3) return 'Meal logged $t ${F.time(at)}';
    if (F.sameDay(at, DateTime.now())) return 'Meal logged $t';
    return 'Meal logged ${F.dayMonth(at)}';
  }

  List<_Conv> get _all {
    final d = data;
    if (d == null) return _rows;
    return [
      for (final c in d.list('items'))
        _Conv(
          F.initials(c.obj('patient').str('name', '?')),
          c.obj('patient').str('name', 'Patient'),
          switch (F.date(c.obj('lastMessage')['at'])) {
            final at? => d8ListTime(at),
            null => '',
          },
          c.numOr('unread').toInt(),
          d8Who(c),
          c.obj('lastMessage').str('text'),
          d8Triage(c['triage']),
          // `lastMealAt` is not in the inbox response yet; shown when the API adds it.
          _mealLogged(F.date(c['lastMealAt'])),
          conversationId: c.str('id'),
          patientId: c.obj('patient').str('id'),
          photo: c.obj('patient').str('photo').isEmpty ? null : c.obj('patient').str('photo'),
        ),
    ];
  }

  int get _unreadCount => data == null ? 3 : data!.numOr('unread').toInt();

  List<_Conv> get _matching {
    final q = _query.trim().toLowerCase();
    return [
      for (final r in _all)
        if ((_filter == 1 || r.unread > 0) && (q.isEmpty || '${r.name} ${r.who} ${r.text}'.toLowerCase().contains(q)))
          r,
    ];
  }

  List<_Conv> get _visible {
    final rows = _matching;
    return data == null || rows.length <= _shown ? rows : rows.sublist(0, _shown);
  }

  void _showMore() {
    if (data == null || _matching.length <= _shown) {
      toast(context, 'No more conversations');
      return;
    }
    setState(() => _shown += _page);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final rows = placeholder == null ? _visible : const <_Conv>[];
    return MpPage(
      nav: const ClinicianNav(current: 2),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D8TabHeader(),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nutrition', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                  const Gap(4),
                  Text('Food logs and dietician conversations', style: tx(14, c: MP.ink2, h: 1.45)),
                ],
              ),
              Semantics(
                container: true,
                label: 'Filter conversations',
                child: MpSegmented(
                  options: ['Unread ($_unreadCount)', 'All', if (data != null) _teamUnread > 0 ? 'Team ($_teamUnread)' : 'Team'],
                  index: _filter,
                  onChanged: (i) => setState(() {
                    _filter = i;
                    _shown = _page;
                  }),
                ),
              ),
              D8SearchField(
                hint: 'Search patients or messages',
                onChanged: (v) => setState(() {
                  _query = v;
                  _shown = _page;
                }),
              ),
              // Team: chats with colleagues at this clinic.
              if (_filter == 2) TeamChats(query: _query) else ...[
              MpCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows.length; i++) _NutritionRow(rows[i], first: i == 0),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          data != null && _all.isEmpty ? 'No nutrition conversations yet' : 'No conversations found',
                          style: tx(14, c: MP.ink3, h: 20 / 14),
                        ),
                      ),
                  ],
                ),
              ),
              MpButton('Show more', kind: MpBtn.secondary, onTap: _showMore),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Conversation row: avatar pinned to the top, name/time, preview/unread,
/// chip + meal-log meta, chevron centred on the row.
class _NutritionRow extends StatelessWidget {
  final _Conv r;
  final bool first;
  const _NutritionRow(this.r, {required this.first});

  @override
  Widget build(BuildContext context) {
    final aria = '${r.name}${r.unread > 0 ? ', ${r.unread} unread' : ''}, ${r.time}, open chat review';
    return Semantics(
      button: true,
      label: aria,
      excludeSemantics: true,
      child: Tap(
        // Live: the conversation itself (Patient-Thread); the design opens its chat review.
        onTap: () => r.conversationId == null
            ? Nav.go(context, 'Chat-Review-Detail')
            : Nav.go(context, 'Patient-Thread', args: {'conversationId': r.conversationId, 'patientId': r.patientId}),
        radius: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
          child: Stack(
            children: [
              Row(
                children: [
                  // Space for the avatar (`align-self: flex-start`), drawn below.
                  const SizedBox(width: 48, height: 48),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        D8ConvHead(name: r.name, time: r.time, who: r.who, text: r.text, unread: r.unread),
                        // Column gap 2px + `margin-top: 4px`.
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 24,
                          child: Row(
                            children: [
                              if (r.chip.isNotEmpty) ...[
                                MpBadge(r.chip, bg: MP.fill, fg: MP.ink2, weight: w600),
                                const Gap(8),
                              ],
                              if (r.meta.isNotEmpty) Flexible(
                                child: Text(
                                  r.meta,
                                  style: tx(13, c: MP.ink3, tab: true),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
              Positioned(left: 0, top: 0, child: MpAvatar(r.initials, size: 48, fontSize: 16, weight: w600, photo: r.photo)),
            ],
          ),
        ),
      ),
    );
  }
}

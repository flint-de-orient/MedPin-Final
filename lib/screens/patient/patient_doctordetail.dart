import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'patient_finddoctor.dart' show openDoctorBooking;
import '../../data/rx_pdf.dart';
import '../../data/checkout.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-DoctorDetail.dc.html — "Patient · doctor page (Dr. Sen)".
///
/// Live data: GET /api/patient/doctors/:doctorId (profile, next visit with its
/// to-dos, plan, last visit, records, history, access, chat). Opened with
/// `args: {'doctorId': …}`; without one it shows the doctor of the patient's
/// next visit (GET /api/patient/my-doctors).
class PatientDoctordetailScreen extends StatefulWidget {
  const PatientDoctordetailScreen({super.key});

  @override
  State<PatientDoctordetailScreen> createState() => _PatientDoctordetailScreenState();
}

typedef _Tone = (Color, Color);

const _Tone _high = (MP.amberSoft, MP.amber);
const _Tone _new = (MP.primarySoft, MP.primary);
const _Tone _ok = (MP.greenSoft, MP.green);

const _todos = ['Upload HbA1c report', "Log today's fasting sugar", 'Note down questions for Dr. Sen'];

const _plan = [
  ('Metformin 500 mg', '1-0-1 · after food', '78%', MP.amber),
  ('Glimepiride 1 mg', '1-0-0 · before breakfast', 'New', MP.ink3),
  ('Vitamin D3 60,000 IU', 'Once a week · Sunday', '100%', MP.green),
];

/// (kind line, title, date · source, flag, tone, file url, from this doctor)
typedef _DocRow = (String, String, String, String, _Tone?, String?, bool);

const List<_DocRow> _docs = [
  ('Test result · shared by you', 'HbA1c', '30 Sep · Suraksha Diagnostics', 'High', _high, null, false),
  ('Prescription', 'Diabetes follow-up', '29 Sep · Dr. Sen', 'Latest', _new, null, true),
  ('Test result · shared by you', 'Lipid profile', '30 Sep · Suraksha Diagnostics', 'High', _high, null, false),
  ('Prescription', 'Sugar and cholesterol', '12 Mar · Dr. Sen', '', null, null, true),
];

/// (date, title, dot fill, dot ring)
const _visits = [
  ('Today · 5:00 PM', 'Follow-up · review HbA1c', MP.primary, MP.primary),
  ('29 Sep 2026', 'Glimepiride added', MP.white, MP.ink3),
  ('12 Mar 2026', 'Lipid test ordered', MP.white, MP.ink3),
  ('12 Jan 2026', 'HbA1c improved to 6.8%', MP.white, MP.ink3),
];

/// To-do circle: dashed 2px #69738A ring (no round caps, so not [Ico]).
const _dashedCircle =
    '<svg viewBox="0 0 24 24" fill="none" stroke="#69738A" stroke-width="2" stroke-dasharray="3 3"><circle cx="12" cy="12" r="9"/></svg>';

const _cardDeco = BoxDecoration(
  color: MP.white,
  borderRadius: BorderRadius.all(Radius.circular(24)),
  border: Border.fromBorderSide(BorderSide(color: MP.line)),
  boxShadow: MPShadow.card,
);

const _foodLabels = {
  'before_food': 'before food',
  'after_food': 'after food',
  'with_food': 'with food',
  'empty_stomach': 'empty stomach',
  'bedtime': 'at bedtime',
};

const _visitTypes = {'new': 'New visit', 'follow_up': 'Follow-up', 'report_review': 'Report review'};

String _fullDate(DateTime d) => '${F.dayMonth(d)} ${d.year}';

Color _pctColor(num pct) => pct >= 90 ? MP.green : (pct >= 70 ? MP.amber : MP.red);

class _PatientDoctordetailScreenState extends State<PatientDoctordetailScreen> with LiveData {
  final _done = [true, false, false];
  int _filter = 0;

  /// Live to-do ticks while the request is on its way.
  final _todoDone = <String, bool>{};

  @override
  Future<Object?> fetch() async {
    final args = p2DoctorArgs(context);
    var id = args['doctorId'];
    if (id == null) {
      final appt = args['appointmentId'];
      final mine = [
        for (final d in (await Api.I.get('/api/patient/my-doctors') as List? ?? const []))
          if ((d as Map)['role'] == 'doctor') d.cast<String, dynamic>(),
      ];
      mine.sort((a, b) {
        final x = F.date(a.obj('nextVisit')['startAt']), y = F.date(b.obj('nextVisit')['startAt']);
        if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
        return x.compareTo(y);
      });
      if (mine.isEmpty) throw const ApiException(404, 'NO_DOCTOR', 'You have no doctors yet. Find one from the Doctor tab.');
      // A visit link (home slide, notification): that visit's doctor; else the next visit's.
      id = (appt == null ? null : mine.where((d) => d.obj('nextVisit').str('id') == appt).firstOrNull)?.str('doctorId') ??
          mine.first.str('doctorId');
    }
    return Api.I.get('/api/patient/doctors/$id');
  }

  Map<String, dynamic> get _d => data ?? const {};
  String get _id => _d.str('doctorId');
  String get _name => data == null ? 'Dr. Arjun Sen' : _d.str('name', 'Doctor');
  String get _short => data == null ? 'Dr. Sen' : p2ShortName(_name);
  Map<String, dynamic>? get _next => data == null || _d.obj('nextVisit').isEmpty ? null : _d.obj('nextVisit');
  Map<String, dynamic>? get _last => data == null || _d.obj('lastVisit').isEmpty ? null : _d.obj('lastVisit');
  Map<String, dynamic> get _convo => _d.obj('conversation');
  int get _unread => data == null ? 2 : _convo.numOr('unread').toInt();

  Future<void> _chat() async {
    await Nav.go(
      context,
      'Patient-DoctorChat',
      args: data == null ? null : {'doctorId': _id, if (_convo['id'] != null) 'conversationId': _convo.str('id')},
    );
    if (data != null) reload(quiet: true);
  }

  Future<void> _book() async {
    if (data == null) {
      p2Missing(context, 'Booking');
      return;
    }
    if (await openDoctorBooking(context, _id)) reload(quiet: true);
  }

  Future<void> _share() async {
    await Nav.go(context, 'Records-Add', args: data == null ? null : {'doctorId': _id});
    if (data != null) reload(quiet: true);
  }

  Future<void> _toggleTodo(Map<String, dynamic> t) async {
    final next = _next;
    if (next == null) return;
    final id = t.str('id', t.str('_id'));
    final done = !(_todoDone[id] ?? t['done'] == true);
    setState(() => _todoDone[id] = done);
    final ok = await runAction(
      context,
      () => Api.I.post('/api/patient/appointments/${next.str('id')}/todos/$id', {'done': done}),
    );
    if (ok == null && mounted) setState(() => _todoDone.remove(id));
  }

  String? _locationId(Map<String, dynamic> visit) {
    final l = visit['locationId'];
    if (l is Map) return '${l['id'] ?? l['_id']}';
    return l == null ? null : '$l';
  }

  /// To the clinic of the next visit, else the doctor's first clinic.
  Future<void> _directions() async {
    final next = _next;
    final places = _d.list('places');
    if (next == null && places.isEmpty) {
      p2Missing(context, 'The map');
      return;
    }
    final loc = next != null && next['locationId'] is Map ? (next['locationId'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final place = (next == null ? null : places.where((p) => p.str('locationId') == _locationId(next)).firstOrNull) ?? places.firstOrNull;
    final address = [place?.str('name') ?? loc.str('name'), place?.str('address') ?? '', place?.str('area') ?? ''].where((x) => x.isNotEmpty).join(', ');
    await p2Directions(
      context,
      lat: place?['lat'] as num?,
      lng: place?['lng'] as num?,
      mapUrl: loc['googleMapsUrl'] as String? ?? place?['mapUrl'] as String?,
      address: address,
    );
  }

  Future<void> _reschedule() async {
    final next = _next;
    final loc = next == null ? null : _locationId(next);
    if (next == null || loc == null) {
      p2Missing(context, 'Rescheduling');
      return;
    }
    final startAt = await openSheet<String>(
      context,
      (_) => P2SlotSheet(
        title: 'Reschedule your visit',
        subtitle: 'With $_name. The clinic is told right away.',
        doctorId: _id,
        locationId: loc,
        action: 'Move my visit',
      ),
    );
    if (startAt == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.post('/api/patient/appointments/${next.str('id')}/reschedule', {'startAt': startAt}));
    if (ok == null || !mounted) return;
    final at = F.date(startAt);
    toast(context, at == null ? 'Visit moved' : 'Visit moved to ${F.when(at)}');
    reload(quiet: true);
  }

  Future<void> _cancelVisit() async {
    final next = _next;
    if (next == null) return;
    final at = F.date(next['startAt']);
    final ok = await openSheet<bool>(
      context,
      (_) => P2ConfirmSheet(
        title: 'Cancel this visit?',
        subtitle: '${at == null ? 'Your visit' : F.when(at)} with $_name. The clinic is told right away.',
        confirm: 'Cancel visit',
        cancel: 'Keep visit',
      ),
    );
    if (ok != true || !mounted) return;
    final res = await runAction(context, () => Api.I.post('/api/patient/appointments/${next.str('id')}/cancel', {'reason': 'Cancelled in the app'}));
    if (res == null || !mounted) return;
    toast(context, 'Visit cancelled');
    reload(quiet: true);
  }

  Future<void> _manage() async {
    final access = _d.obj('access');
    if (data == null || access.isEmpty) {
      p2Missing(context, 'Managing access');
      return;
    }
    final current = p2AccessLevels[access.str('level')] ?? p2AccessLevels['full_record']!;
    final level = await openSheet<String>(
      context,
      (_) => P2SharingSheet(title: 'What $_short can see', subtitle: _d.str('clinic', _d.str('headline')), current: current),
    );
    if (level == null || level == current || !mounted) return;
    final key = p2AccessLevels.entries.firstWhere((e) => e.value == level).key;
    final ok = await runAction(context, () => Api.I.patch('/api/patient/care-team/$_id', {'accessLevel': key}));
    if (ok == null || !mounted) return;
    toast(context, key == 'not_shared' ? 'Stopped sharing with $_name' : '$_name can now see: ${level.toLowerCase()}');
    reload(quiet: true);
  }

  Future<void> _more() async {
    if (data == null) {
      p2Missing(context, 'The options menu');
      return;
    }
    final actions = <(String, String, bool)>[
      (I.calendar, 'Book a visit', false),
      if (_next != null) (I.close, 'Cancel next visit', true),
      if (_d.obj('access').isNotEmpty) (I.shield, 'What $_short can see', false),
    ];
    final i = await openSheet<int>(context, (_) => P2ActionSheet(title: _name, actions: actions));
    if (i == null || !mounted) return;
    final label = actions[i].$2;
    if (label == 'Book a visit') {
      await _book();
    } else if (label == 'Cancel next visit') {
      await _cancelVisit();
    } else {
      await _manage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      // 64px bar: back + more (white, joins the white profile header below).
      header: Container(
        height: 64,
        color: MP.white,
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
        child: Row(
          children: [
            MpIconButton(I.back, label: 'Back to My doctors', onTap: () => Nav.back(context)),
            const Spacer(),
            MpIconButton(I.moreV, label: 'More options', filled: true, onTap: _more),
          ],
        ),
      ),
      body: placeholder ??
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profile(),
              VGap(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
                gap: 16,
                children: [
                  if (data == null || _next != null) _nextVisit(),
                  if (data == null || _convo.obj('latestFromDoctor').isNotEmpty) _latestMessage(),
                  if (data == null || _d.list('medicines').isNotEmpty || _advice.isNotEmpty) _yourPlan(),
                  if (data == null || _last != null) _lastVisit(),
                  if (data == null || _d.list('records').isNotEmpty) _documents(),
                  if (data == null || _history.isNotEmpty) _visitHistory(),
                  if (data == null || _d.obj('access').isNotEmpty) _sharing(),
                ],
              ),
            ],
          ),
    );
  }

  // Avatar, name, availability + Chat / Book / Share.
  Widget _profile() {
    Widget tile(String icon, String label, VoidCallback onTap) => P2Box(
      onTap: onTap,
      label: label,
      height: 58, // <a> 56px + 1px border (content-box)
      radius: 16,
      color: MP.white,
      border: MP.lineStrong,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Ico(icon, size: 18, color: MP.primary), const Gap(2), Text(label, style: tx(13, w: w700))],
      ),
    );

    final presence = _d.str('presence');
    final reply = _d['avgReplyMinutes'];
    final (String status, Color statusColor, Color dot) = data == null
        ? ('Available now · replies in ~10 min', MP.green, MP.green)
        : switch (presence) {
            'available' => ('Available now${reply is num ? ' · replies in ~${reply.round()} min' : ''}', MP.green, MP.green),
            'in_clinic' => ('In clinic now · replies after the clinic', MP.amber, MP.amber),
            _ => ('Away · replies later', MP.ink3, MP.lineStrong),
          };
    final sub = data == null
        ? 'MBBS, MD · Diabetes & hormones'
        : [_d.str('degrees'), _d.str('specialty', _d.str('headline'))].where((x) => x.isNotEmpty).join(' · ');
    final unread = _unread;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 14px dot + 3px ring (content-box) at right 2 / bottom 2.
              P2AvatarDot(F.initials(_name), size: 72, fontSize: 24, dot: dot, dotSize: 20, dotBorder: 3, inset: 2),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, style: tx(26, w: w800, h: 1.15, em: -0.02)),
                    const Gap(2),
                    Text(sub, style: tx(14, c: MP.ink2)),
                    const Gap(2),
                    Text(status, style: tx(13, w: w600, c: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: P2Box(
                  onTap: _chat,
                  label: unread > 0 ? 'Chat, $unread unread' : 'Chat',
                  height: 56,
                  radius: 16,
                  color: MP.primary,
                  shadow: MPShadow.button,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.message, size: 20, color: MP.white),
                      const Gap(8),
                      Text('Chat', style: tx(16, w: w700, c: MP.white)),
                      if (unread > 0) ...[
                        const Gap(8),
                        P2Pill('$unread', bg: MP.white, fg: MP.primary, height: 20, padX: 6, weight: w800, minWidth: 20),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap(8),
              Expanded(child: tile(I.calendar, 'Book', _book)),
              const Gap(8),
              Expanded(child: tile(I.upload, 'Share', _share)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nextVisit() {
    final next = _next;
    final at = F.date(next?['startAt']);
    final loc = next?['locationId'] is Map ? (next!['locationId'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final token = next?['tokenNo'];
    final title = next == null ? 'Today, 5:00 PM' : (at == null ? 'Visit booked' : F.when(at));
    final where = next == null
        ? 'City Care Clinic, Salt Lake · Token 04'
        : [loc.str('name'), if (token != null) 'Token ${'$token'.padLeft(2, '0')}'].where((x) => x.isNotEmpty).join(' · ');
    final pill = next == null ? 'Follow-up' : (_visitTypes[next.str('visitType')] ?? 'Visit');
    final todos = next?.list('todos');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MP.primary, width: 1.5),
        boxShadow: MPShadow.float,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT VISIT', style: tx(12, w: w700, c: MP.primary, em: 0.06)),
                    const Gap(4),
                    Text(title, style: tx(20, w: w700, h: 1.25)),
                    const Gap(4),
                    Text(where, style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              P2Pill(pill, bg: MP.primarySoft, fg: MP.primary, height: 26, padX: 10),
            ],
          ),
          const Gap(14),

          // Before you go (tap an item to tick it off)
          if (todos == null || todos.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('BEFORE YOU GO', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                  if (todos == null)
                    for (var i = 0; i < _todos.length; i++) ...[
                      const Gap(8),
                      _todo(_todos[i], _done[i], () => setState(() => _done[i] = !_done[i])),
                    ]
                  else
                    for (final t in todos) ...[
                      const Gap(8),
                      _todo(
                        t.str('text'),
                        _todoDone[t.str('id', t.str('_id'))] ?? t['done'] == true,
                        () => _toggleTodo(t),
                      ),
                    ],
                ],
              ),
            ),
            const Gap(14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: P2Box(
                  onTap: _directions,
                  height: 48,
                  radius: 12,
                  color: MP.primarySoft,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.pin, size: 16, color: MP.primary),
                      const Gap(6),
                      Text('Directions', style: tx(14, w: w700, c: MP.primary)),
                    ],
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: P2Box(
                  onTap: _reschedule,
                  height: 50, // <a> 48px + 1px border (content-box)
                  radius: 12,
                  border: MP.lineStrong,
                  alignment: Alignment.center,
                  child: Text('Reschedule', style: tx(14, w: w700)),
                ),
              ),
            ],
          ),
          if (next != null && next['feeStatus'] == 'pending' && (next['fee'] as num? ?? 0) > 0) ...[
            const Gap(8),
            P2Box(
              onTap: _payOnline,
              label: 'Pay the visit fee online',
              height: 48,
              radius: 12,
              color: MP.primary,
              alignment: Alignment.center,
              child: Text('Pay ₹${(next['fee'] as num).round()} online', style: tx(14, w: w700, c: MP.white)),
            ),
          ],
        ],
      ),
    );
  }

  /// Pays the next visit's fee in the app (Razorpay Checkout).
  Future<void> _payOnline() async {
    final next = _next;
    if (next == null) return;
    final paid = await Checkout.pay(context, kind: 'fee', id: next.str('id'));
    if (paid && mounted) reload(quiet: true);
  }

  Widget _todo(String text, bool done, VoidCallback onTap) => MpHitSlop(child: Semantics(
    checked: done,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          done ? const Ico(I.check, size: 16, color: MP.green, stroke: 2.5) : const Svg(_dashedCircle, width: 16, height: 16),
          const Gap(10),
          Expanded(
            child: Text(text, style: done ? tx(14, c: MP.ink2, deco: TextDecoration.lineThrough) : tx(14)),
          ),
        ],
      ),
    ),
  ));

  Widget _latestMessage() {
    final m = _convo.obj('latestFromDoctor');
    final at = F.date(m['at']);
    final time = data == null ? '9:14 AM' : (at == null ? '' : F.askedAt(at));
    final text = data == null
        ? " Got your HbA1c report, thanks. We'll adjust the dose when you come in at 5."
        : ' ${m.str('text', m.str('kind') == 'voice' ? 'Voice message' : 'Sent a file')}';
    return P2Box(
      onTap: _chat,
      label: 'Open chat with $_short',
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      radius: 20,
      color: MP.white,
      border: MP.line,
      shadow: MPShadow.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('LATEST MESSAGE', style: tx(12, w: w700, c: MP.ink3, em: 0.06))),
              Text(time, style: tx(13, c: MP.ink3)),
              if (_unread > 0) ...[
                const Gap(6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
          const Gap(8),
          Text.rich(
            TextSpan(
              style: tx(15, h: 1.5),
              children: [
                TextSpan(text: '$_short:', style: tx(15, w: w700, h: 1.5)),
                TextSpan(text: text),
              ],
            ),
          ),
          const Gap(8),
          Text('Reply', style: tx(14, w: w700, c: MP.primary)),
        ],
      ),
    );
  }

  String get _advice {
    if (data == null) {
      return 'Walk 30 minutes, 5 days a week. Avoid sweets and refined flour. Check fasting sugar 3 times a week.';
    }
    final raw = _last?.str('advice') ?? '';
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => RegExp(r'[.!?]$').hasMatch(l) ? l : '$l.')
        .join(' ');
  }

  Widget _yourPlan() {
    final plan = data == null
        ? _plan
        : [
            for (final m in _d.list('medicines'))
              (
                '${m.str('name')} ${m.str('strength')}'.trim(),
                [m.str('pattern'), _foodLabels[m.str('foodRelation')] ?? ''].where((x) => x.isNotEmpty).join(' · '),
                m['tracked'] == false
                    ? 'Not tracked'
                    : (m['isNew'] == true || m['adherencePct'] is! num ? 'New' : '${(m['adherencePct'] as num).round()}%'),
                m['adherencePct'] is num && m['isNew'] != true ? _pctColor(m['adherencePct'] as num) : MP.ink3,
              ),
          ];
    final pct = data == null ? 82 : _d['adherencePct'] as num?;
    final advice = _advice;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Your plan', style: tx(20, w: w700, h: 1.25))),
                if (pct != null) Text('${pct.round()}% taken', style: tx(14, w: w700, c: data == null ? MP.amber : _pctColor(pct))),
              ],
            ),
          ),
          for (final m in plan)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.$1, style: tx(15, w: w600)),
                        const Gap(2),
                        Text(m.$2, style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  Text(m.$3, style: tx(14, w: w700, c: m.$4)),
                ],
              ),
            ),
          if (advice.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ADVICE', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                  const Gap(6),
                  Text(advice, style: tx(14, h: 1.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lastVisit() {
    Widget vital(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(12, c: MP.ink2)),
          const Gap(2),
          Text(value, maxLines: 1, style: tx(16, w: w800, c: color, tab: true)),
        ],
      ),
    );

    final last = _last;
    final date = last == null ? '29 Sep 2026' : (F.date(last['date']) == null ? '' : _fullDate(F.date(last['date'])!));
    String summary;
    var vitals = const [('BP', '128/82', MP.ink), ('Sugar (F)', '142', MP.amber), ('Weight', '68.5', MP.ink)];
    if (last == null) {
      summary = 'Sugar was higher than target, so Glimepiride was added. You were asked to get an HbA1c test and come back today.';
    } else {
      final diag = [for (final x in (last['diagnoses'] as List? ?? const [])) '$x'];
      final cc = last.str('chiefComplaint');
      summary = [
        if (cc.isNotEmpty) 'You came in for ${cc[0].toLowerCase()}${cc.substring(1)}${RegExp(r'[.!?]$').hasMatch(cc) ? '' : '.'}',
        if (diag.isNotEmpty) '$_short noted: ${F.joinAnd(diag)}.',
      ].join(' ');
      final v = last.obj('vitals');
      String n(Object? x) => x is num ? (x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1)) : '';
      final sugar = v['bloodSugar'] as num?;
      final target = 130;
      vitals = [
        if (v['bpSystolic'] is num) ('BP', '${n(v['bpSystolic'])}/${n(v['bpDiastolic'])}', MP.ink),
        if (sugar != null) (v.str('sugarType') == 'fasting' ? 'Sugar (F)' : 'Sugar', n(sugar), sugar > target ? MP.amber : MP.ink),
        if (v['weightKg'] is num) ('Weight', n(v['weightKg']), MP.ink),
        if (v['pulse'] is num) ('Pulse', n(v['pulse']), MP.ink),
        if (v['spo2'] is num) ('SpO2', '${n(v['spo2'])}%', MP.ink),
      ].take(3).toList();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Last visit', style: tx(20, w: w700, h: 1.25))),
              Text(date, style: tx(14, c: MP.ink2)),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const Gap(12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Ico(I.sparkle, size: 16, color: MP.primary, stroke: 2),
                ),
                const Gap(8),
                Expanded(child: Text(summary, style: tx(15, h: 1.5))),
              ],
            ),
          ],
          if (vitals.isNotEmpty) ...[
            const Gap(12),
            Row(
              children: [
                for (var i = 0; i < vitals.length; i++) ...[
                  if (i > 0) const Gap(8),
                  Expanded(child: vital(vitals[i].$1, vitals[i].$2, vitals[i].$3)),
                ],
              ],
            ),
          ],
          if (last == null || last['prescriptionId'] != null) ...[
            const Gap(12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (last == null) {
                  p2Missing(context, 'The prescription view');
                } else if (last['prescriptionId'] != null) {
                  RxPdf.view(context, last.str('prescriptionId'), patient: true);
                } else {
                  Nav.go(context, 'Patient-Records');
                }
              },
              child: Text('View prescription', style: tx(14, w: w700, c: MP.primary)),
            ),
          ],
        ],
      ),
    );
  }

  List<_DocRow> get _docRows {
    if (data == null) return _docs;
    return [
      for (final r in _d.list('records'))
        () {
          final at = F.date(r['date']);
          final mineOrigin = r.str('origin') != 'from_doctor';
          final kind = switch (r.str('kind')) {
            'prescription' => 'Prescription',
            'test_result' => 'Test result',
            'ecg' => 'ECG',
            _ => 'Record',
          };
          final tone = switch (r.str('flagTone')) {
            'high' || 'low' || 'critical' => _high,
            'new' => _new,
            'ok' || 'normal' => _ok,
            _ => null,
          };
          return (
            mineOrigin ? '$kind · shared by you' : kind,
            r.str('title', kind),
            [if (at != null) F.dayMonth(at), r.str('sourceName')].where((x) => x.isNotEmpty).join(' · '),
            r.str('flagLabel'),
            r.str('flagLabel').isEmpty ? null : tone,
            r['url'] as String?,
            !mineOrigin,
          );
        }(),
    ];
  }

  Widget _documents() {
    final rows = _docRows;
    final fromDoctor = rows.where((d) => d.$7).length;
    final filters = data == null
        ? const ['All', 'From Dr. Sen · 3', 'Shared by you · 4']
        : ['All', 'From $_short · $fromDoctor', 'Shared by you · ${rows.length - fromDoctor}'];
    final docs = [
      for (final d in rows)
        if (switch (_filter) {
          1 => data == null ? d.$1 == 'Prescription' : d.$7,
          2 => data == null ? d.$1.endsWith('shared by you') : !d.$7,
          _ => true,
        })
          d,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Prescriptions & reports', style: tx(20, w: w700, h: 1.25))),
                const Gap(8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Nav.go(context, 'Patient-Records'),
                  child: Text('All ${data == null ? 7 : rows.length}', style: tx(14, w: w600, c: MP.primary)),
                ),
              ],
            ),
          ),
          // Filter chips (wider than the card in the design, so they scroll).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                for (var i = 0; i < filters.length; i++) ...[
                  if (i > 0) const Gap(8),
                  P2Box(
                    onTap: () => setState(() => _filter = i),
                    label: filters[i],
                    height: 36,
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    color: _filter == i ? MP.primary : MP.white,
                    border: _filter == i ? null : MP.lineStrong,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(filters[i], style: tx(13, w: w600, c: _filter == i ? MP.white : MP.ink2))],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in docs)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.$1.toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                              const Gap(3),
                              Text(d.$2, style: tx(15, w: w600)),
                              const Gap(3),
                              Text(d.$3, style: tx(13, c: MP.ink2)),
                            ],
                          ),
                        ),
                        if (d.$5 != null) ...[const Gap(12), P2Pill(d.$4, bg: d.$5!.$1, fg: d.$5!.$2)],
                        const Gap(12),
                        P2Box(
                          onTap: () => data == null
                              ? toast(context, 'Downloading ${d.$2}')
                              : p2Open(context, d.$6, failed: '${d.$2} has no file to download'),
                          label: 'Download ${d.$2}',
                          width: 44,
                          height: 44,
                          radius: 12,
                          color: MP.white,
                          border: MP.lineStrong,
                          alignment: Alignment.center,
                          child: const Ico(I.download, size: 18, color: MP.primary),
                        ),
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

  /// (date, title, dot fill, dot ring): the next visit first, then past visits.
  List<(String, String, Color, Color)> get _history {
    if (data == null) return _visits;
    final out = <(String, String, Color, Color)>[];
    final next = _next;
    final at = F.date(next?['startAt']);
    if (next != null && at != null) {
      final when = F.when(at).replaceFirst(', ', ' · ');
      out.add((when, _visitTypes[next.str('visitType')] ?? 'Visit', MP.primary, MP.primary));
    }
    for (final h in _d.list('timeline')) {
      final d = F.date(h['date']);
      out.add((d == null ? '' : _fullDate(d), h.str('text', 'Visit'), MP.white, MP.ink3));
    }
    return out;
  }

  Widget _visitHistory() {
    final visits = _history;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Visits with $_short', style: tx(20, w: w700, h: 1.25)),
          const Gap(12),
          for (var i = 0; i < visits.length; i++) ...[
            const Gap(4),
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(visits[i].$1, style: tx(13, c: MP.ink3)),
                      const Gap(2),
                      Text(visits[i].$2, style: tx(15, w: w600)),
                    ],
                  ),
                ),
                // Timeline: 10px dot (2px ring) + 1px line to the row's end.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: Column(
                    children: [
                      const Gap(5),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: visits[i].$3,
                          shape: BoxShape.circle,
                          border: Border.all(color: visits[i].$4, width: 2),
                        ),
                      ),
                      // Last row: transparent line.
                      Expanded(
                        child:
                            i == visits.length - 1
                                ? const SizedBox(width: 1)
                                : const ColoredBox(color: MP.line, child: SizedBox(width: 1)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sharing() {
    final level = data == null
        ? 'Full record, daily log and tracked vitals'
        : (p2AccessLevels[_d.obj('access').str('level')] ?? 'Full record');
    return P2Box(
      onTap: _manage,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      radius: 20,
      color: MP.white,
      border: MP.line,
      child: Row(
        children: [
          const Ico(I.shield, size: 20, color: MP.ink2),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What $_short can see', style: tx(15, w: w700)),
                const Gap(2),
                Text(level, style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Gap(12),
          Text('Manage', style: tx(14, w: w600, c: MP.primary)),
        ],
      ),
    );
  }
}

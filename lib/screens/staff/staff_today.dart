import 'package:flutter/material.dart' hide Text;
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';
import '../../widgets/i18n.dart';
import '../../widgets/fee_actions.dart';
import '../../widgets/visit_status.dart';

/// Design: Staff-Today.dc.html — "Today" (front desk).
class StaffTodayScreen extends StatefulWidget {
  const StaffTodayScreen({super.key});

  @override
  State<StaffTodayScreen> createState() => _StaffTodayScreenState();
}

/// The canvas sets `line-height: 1.4` on the page; text without its own
/// line height inherits it.
const _lh = 1.4;

/// Status pill colours (bg, fg).
const _statusColors = <String, (Color, Color)>{
  'With doctor': (MP.primarySoft, MP.primary),
  'Waiting': (MP.amberSoft, MP.amber),
  'Upcoming': (MP.fill, MP.ink2),
  'Done': (MP.greenSoft, MP.green),
  'Missed': (MP.redSoft, MP.red),
};

/// API appointment status → the label on the pill.
const _statusLabels = {
  'booked': 'Upcoming',
  'confirmed': 'Upcoming',
  'waiting': 'Waiting',
  'in_consultation': 'With doctor',
  'completed': 'Done',
  'missed': 'Missed',
};

const _channelLabels = {'app': 'app', 'whatsapp': 'WhatsApp', 'phone': 'phone', 'desk': 'desk'};

/// (name, detail, meta)
const _requests = [
  ('Debasish Bose', 'Follow-up with Dr. Sen', 'Asked 8:20 AM · app'),
  ('Farhana Islam', 'New visit with Dr. Sen', 'Asked yesterday · WhatsApp'),
];

/// (time, name, status, doctor)
const _appts = [
  ('8:30', 'Amit Pal', 'Done', 'Dr. Sen'),
  ('9:00', 'Priya Sharma', 'With doctor', 'Dr. Sen'),
  ('9:30', 'Rahul Das', 'Waiting', 'Dr. Sen'),
  ('10:00', 'Aisha Khan', 'Waiting', 'Dr. Sen'),
  ('10:30', 'Sujit Mondal', 'Upcoming', 'Dr. Sen'),
  ('11:00', 'Moumita Roy', 'Upcoming', 'Dr. Mitra'),
];

/// (icon, label, stem)
const _actions = [
  (I.userPlus, 'Register walk-in', 'Add-Patient'),
  (I.activity, 'Record vitals', 'Staff-Vitals'),
  (I.calendar, 'Book appointment', 'Staff-Book'),
];

/// Live data: GET /api/staff/today, refreshed every 30 s.
class _StaffTodayScreenState extends State<StaffTodayScreen> with LiveData {
  // Design preview state.
  late final List<String> _status = [for (final a in _appts) a.$3];
  int _checkedIn = 7;

  @override
  Future<Object?> fetch() => Api.I.get('/api/staff/today');

  @override
  Duration? get refreshEvery => const Duration(seconds: 30);

  /// (name, detail, meta)
  List<(String, String, String)> get _requestRows {
    final d = data;
    if (d == null) return _requests;
    return [
      for (final r in d.list('requests'))
        (
          r.obj('patientId').str('name'),
          _requestDetail(r),
          'Asked ${F.askedAt(F.date(r['createdAt']) ?? DateTime.now())} · ${_channelLabels[r['channel']] ?? r.str('channel')}',
        ),
    ];
  }

  static String _requestDetail(Map<String, dynamic> r) {
    final kind = r['visitType'] == 'follow_up' ? 'Follow-up' : 'New visit';
    final doctor = r.obj('doctorId').str('name');
    return doctor.isEmpty ? kind : '$kind with ${F.doctorShort(doctor)}';
  }

  /// Today's list (time, name, status, doctor, appointment id), at most six:
  /// earlier finished visits drop off first.
  List<(String, String, String, String, String?)> get _apptRows {
    final d = data;
    if (d == null) {
      return [for (var i = 0; i < _appts.length; i++) (_appts[i].$1, _appts[i].$2, _status[i], _appts[i].$4, null)];
    }
    final rows = [
      for (final a in d.list('items'))
        (
          F.timeShort(F.date(a['startAt']) ?? DateTime.now()),
          a.obj('patient').str('name'),
          _statusLabels[a['status']] ?? 'Upcoming',
          F.doctorShort(a.obj('doctor').str('name')),
          a['id'] as String?,
        ),
    ];
    while (rows.length > 6 && (rows.first.$3 == 'Done' || rows.first.$3 == 'Missed')) {
      rows.removeAt(0);
    }
    return rows.take(6).toList();
  }

  Map<String, dynamic> get _summary => data?.obj('summary') ?? const {};

  Future<void> _checkIn(int i) async {
    final row = _apptRows[i];
    if (!isLive) {
      setState(() {
        _status[i] = 'Waiting';
        _checkedIn++;
      });
      toast(context, '${row.$2} checked in');
      return;
    }
    final ok = await runAction(context, () => Api.I.post('/api/appointments/${row.$5}/status', {'status': 'waiting'}));
    if (ok == null || !mounted) return;
    toast(context, '${row.$2} checked in');
    reload(quiet: true);
  }

  /// Opens [stem] with [args] when live (the design preview just navigates),
  /// then refreshes the day.
  Future<void> _go(String stem, Map<String, Object?> args) async {
    await Nav.go(context, stem, args: isLive ? args : null);
    if (mounted && isLive) reload(quiet: true);
  }

  Map<String, dynamic>? _request(int i) {
    final list = data?.list('requests') ?? const [];
    return i < list.length ? list[i] : null;
  }

  void _openRequest(int i) {
    final r = _request(i);
    _go('Patient-Profile-Desk', {if (r != null) 'patientId': r.obj('patientId').str('id')});
  }

  void _assignRequest(int i) {
    final r = _request(i);
    _go('Appointments-Manage', {if (r != null) 'requestId': r.str('id'), if (r != null) 'patientId': r.obj('patientId').str('id')});
  }

  void _openAppointment(int i) {
    final id = _apptRows[i].$5;
    final a = data?.list('items').where((x) => x.str('id') == id).firstOrNull;
    _go('Patient-Profile-Desk', {if (a != null) 'patientId': a.obj('patient').str('id'), if (id != null) 'appointmentId': id});
  }

  String get _greeting {
    if (data == null) return 'Good morning, Tania';
    return '${F.greeting()}, ${F.firstName(data!.str('userName', Session.I.name))}';
  }

  String get _dateLine {
    final at = loadedAt;
    if (data == null || at == null) return 'Tue, 29 Sep 2026 · Updated 4s ago';
    final secs = DateTime.now().difference(at).inSeconds;
    final ago = secs < 60 ? '${secs}s' : '${secs ~/ 60} min';
    return '${F.dateLong(DateTime.now())} · Updated $ago ago';
  }

  int get _unread => data == null ? 3 : data!.numOr('unreadNotifications').toInt();

  String get _bookedLine {
    if (data == null) return '18 booked · Dr. Sen and Dr. Mitra';
    final doctors = [for (final d in (_summary['doctors'] as List? ?? const [])) F.doctorShort('$d')];
    final booked = '${_summary['booked'] ?? 0} booked';
    return doctors.isEmpty ? booked : '$booked · ${F.joinAnd(doctors)}';
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      nav: const StaffNav(current: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D10StaffHeader(bellLabel: _unread > 0 ? 'Notifications, $_unread new' : 'Notifications', dot: MP.primary),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              // Greeting
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting, style: tx(28, w: w800, h: 1.15, em: -0.02)),
                    const Gap(6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle),
                        ),
                        const Gap(8),
                        Flexible(
                          child: Text(_dateLine, style: tx(14, c: MP.ink2, h: _lh)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_requestRows.isNotEmpty) _requestsCard(context),
              Row(
                children: [
                  for (var i = 0; i < _actions.length; i++) ...[
                    if (i > 0) const Gap(8),
                    Expanded(child: _ActionTile(_actions[i])),
                  ],
                ],
              ),
              _appointmentsCard(context),
              _summaryCard(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _requestsCard(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requests waiting for a time', style: tx(20, w: w700, h: 1.25)),
                const Gap(2),
                Text(
                  '${_requestRows.length} ${_requestRows.length == 1 ? 'patient' : 'patients'} asked for a visit, no slot yet',
                  style: tx(14, c: MP.ink2, h: _lh),
                ),
              ],
            ),
          ),
          for (final (i, r) in _requestRows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Tap(
                      onTap: () => _openRequest(i),
                      radius: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _line(r.$1, tx(16, w: w600, h: _lh)),
                          const Gap(2),
                          _line(r.$2, tx(14, c: MP.ink2, h: _lh)),
                          const Gap(2),
                          _line(r.$3, tx(13, c: MP.ink3, h: _lh)),
                        ],
                      ),
                    ),
                  ),
                  const Gap(12),
                  MpButton.small(
                    'Assign time',
                    expand: false,
                    onTap: () => _assignRequest(i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _appointmentsCard(BuildContext context) {
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Today's appointments", style: tx(20, w: w700, h: 1.25)),
                      const Gap(2),
                      Text(_bookedLine, style: tx(14, c: MP.ink2, h: _lh)),
                    ],
                  ),
                ),
                MpHitSlop(child: Tap(
                  onTap: () => _go('Appointments', const {}),
                  radius: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('View all', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                  ),
                )),
              ],
            ),
          ),
          for (var i = 0; i < _apptRows.length; i++) _apptRow(context, i),
        ],
      ),
    );
  }

  Widget _apptRow(BuildContext context, int i) {
    final a = _apptRows[i];
    final status = a.$3;
    final (bg, fg) = _statusColors[status]!;
    // The visit fee: paid (and how), to collect at the desk, or a refund to hand back.
    final appt = data?.list('items').where((x) => x.str('id') == a.$5).firstOrNull;
    final fee = appt == null ? null : VisitFee.of(appt);
    final at = appt == null ? null : F.date(appt['startAt']);
    // Status (tap to change it: arrived, with doctor, done, missed, cancel).
    final statusChip = Tap(
      onTap: appt == null
          ? null
          : () async {
              if (await changeVisitStatus(context, appointmentId: appt.str('id'), status: appt.str('status'), patientName: a.$2) && mounted) {
                reload(quiet: true);
              }
            },
      radius: 999,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status, maxLines: 1, style: tx(12, w: w600, c: fg, h: 1)),
            if (appt != null) ...[const Gap(3), Ico(I.chevronDown, size: 12, color: fg, stroke: 2.2)],
          ],
        ),
      ),
    );
    Widget link(String label, Future<void> Function() go) => Tap(
          onTap: go,
          radius: 6,
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(tr(context, label), style: tx(13, w: w600, c: MP.primary, h: 1.2)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Tap(
        onTap: () => _openAppointment(i),
        radius: 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time, with AM / PM under it (a 6:20 could be morning or evening).
            SizedBox(
              width: 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.$1, style: tx(15, w: w600, tab: true, h: _lh)),
                  if (at != null) Text(at.hour < 12 ? 'AM' : 'PM', style: tx(12, w: w600, c: MP.ink3, h: 1.3)),
                ],
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _line(a.$2, tx(16, w: w600, h: _lh)),
                        ),
                      ),
                      if (status == 'Upcoming') ...[
                        const Gap(10),
                        Semantics(
                          label: 'Check in ${a.$2}',
                          button: true,
                          excludeSemantics: true,
                          child: MpButton.small('Check in', expand: false, onTap: () => _checkIn(i)),
                        ),
                      ],
                    ],
                  ),
                  const Gap(8),
                  // Status · doctor, then the fee: wraps to a new line instead of cutting words off.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      statusChip,
                      if (a.$4.isNotEmpty) Text(a.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink3, h: _lh)),
                    ],
                  ),
                  if (fee != null && fee.status != 'free') ...[
                    const Gap(8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FeeChip(fee),
                        if (fee.due && status != 'Missed')
                          link('Collect', () async {
                            if (await collectFee(context, fee, patientName: a.$2) && mounted) reload(quiet: true);
                          }),
                        if (fee.refundDue)
                          link('Refund', () async {
                            if (await handBackFee(context, fee) && mounted) reload(quiet: true);
                          }),
                      ],
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

  Widget _summaryCard() {
    final m = _summary;
    final summary = data == null
        ? [('18', 'Booked'), ('$_checkedIn', 'Checked in'), ('5', 'Done'), ('1', 'Missed appointments')]
        : [
            ('${m['booked'] ?? 0}', 'Booked'),
            ('${m['checkedIn'] ?? 0}', 'Checked in'),
            ('${m['done'] ?? 0}', 'Done'),
            ('${m['missed'] ?? 0}', 'Missed appointments'),
          ];
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Day summary', style: tx(20, w: w700, h: 1.25)),
          const Gap(16),
          MpGrid(
            columns: 2,
            gap: 8,
            children: [
              for (final s in summary)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                      const Gap(6),
                      Text(s.$2, style: tx(14, c: MP.ink2, h: _lh)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _line(String text, TextStyle style) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}

/// Quick action: 84px tile, radius 12, 1px #E5E9F0, padding 14/12, icon on
/// top and the label at the bottom (space-between).
class _ActionTile extends StatelessWidget {
  final (String, String, String) a;
  const _ActionTile(this.a);

  @override
  Widget build(BuildContext context) {
    // height 84 is border-box; Tap insets the content by the 1px border.
    return SizedBox(
      height: 84,
      child: Tap(
        onTap: () => Nav.go(context, a.$3, args: a.$2 == 'Register walk-in' ? const {'walkIn': true} : null),
        radius: 12,
        color: MP.white,
        border: MP.line,
        shadow: MPShadow.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Ico(a.$1, size: 22, color: MP.primary),
              Flexible(child: _TileLabel(a.$2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 14/600/1.25 label laid out like CSS: two lines may run 3px into the
/// tile's bottom padding, and a word wider than the box overflows it
/// instead of being split mid-word.
class _TileLabel extends StatelessWidget {
  final String text;
  const _TileLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final style = tx(14, w: w600, h: 1.25);
    final label = Text(text, style: style, overflow: TextOverflow.visible);
    return LayoutBuilder(
      builder: (context, c) {
        final scaler = MediaQuery.textScalerOf(context);
        // Measure with the style Text actually paints with (inherited
        // DefaultTextStyle merged in).
        final effective = DefaultTextStyle.of(context).style.merge(style);
        var longest = 0.0;
        for (final word in text.split(' ')) {
          final tp = TextPainter(
            text: TextSpan(text: word, style: effective),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          if (tp.width > longest) longest = tp.width;
          tp.dispose();
        }
        if (longest <= c.maxWidth) return label;
        return OverflowBox(
          alignment: Alignment.topLeft,
          fit: OverflowBoxFit.deferToChild,
          minWidth: 0,
          maxWidth: longest.ceilToDouble(),
          minHeight: 0,
          maxHeight: double.infinity,
          child: label,
        );
      },
    );
  }
}

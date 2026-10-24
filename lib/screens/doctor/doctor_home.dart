import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d8.dart';
import 'patient_picker.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-Home.dc.html — "Home" (Clinician · tabs).
/// Live data: GET /api/dashboard, plus /api/queue, /api/alerts?status=open,
/// /api/inbox/reviews and /api/patients?filter=abnormal for the patient
/// cards (each card shows its own error if its request fails).
class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> with LiveData {
  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/dashboard'),
      d8Optional('/api/queue'),
      d8Optional('/api/alerts', query: {'status': 'open'}),
      d8Optional('/api/inbox/reviews', query: {'status': 'needs_review'}),
      d8Optional('/api/patients', query: {'filter': 'abnormal'}),
    ]);
    return {'dashboard': r[0], 'queue': r[1], 'alerts': r[2], 'reviews': r[3], 'abnormal': r[4]};
  }

  @override
  Duration? get refreshEvery => const Duration(seconds: 60);

  Map<String, dynamic> get _dash => data!.obj('dashboard');

  /// A card's part of the response; null when its request failed.
  Map<String, dynamic>? _part(String k) => data?[k] is Map ? data!.obj(k) : null;

  static const _severityRank = {'emergency': 0, 'urgent': 1, 'watch': 2};
  static const _severityName = {'emergency': 'Emergency', 'urgent': 'Urgent', 'watch': 'Watch'};

  static (Color, Color) _severityTone(String s) => switch (s) {
    'emergency' => _danger,
    'urgent' => _warn,
    _ => _neutral,
  };

  static DateTime _at(Map<String, dynamic> m, [String k = 'createdAt']) => F.date(m[k]) ?? DateTime.fromMillisecondsSinceEpoch(0);

  static String _patientName(Map<String, dynamic> a) {
    final p = a['patient'] is Map ? a.obj('patient') : a.obj('patientId');
    return p.str('name', 'Patient');
  }

  static String? _patientIdOf(Map<String, dynamic> a) {
    final p = a['patient'] is Map ? a.obj('patient') : a.obj('patientId');
    final id = p.str('id');
    return id.isEmpty ? null : id;
  }

  /// Where an alert opens: the chat for urgent messages, else the patient.
  static (String, Map<String, Object?>) _alertTarget(Map<String, dynamic> a) {
    final pid = _patientIdOf(a);
    final cid = a.str('conversationId');
    if (cid.isNotEmpty && (a['kind'] == 'urgent_chat' || a['kind'] == 'message' || a['kind'] == 'chat_flag')) {
      return ('Patient-Thread', {'conversationId': cid, 'patientId': pid});
    }
    if (a['kind'] == 'lab') return ('PP-Tests', {'patientId': pid});
    return ('PP-Summary', {'patientId': pid, 'alertId': a.str('id')});
  }

  List<Map<String, dynamic>> get _openAlertItems {
    final items = [..._part('alerts')?.list('items') ?? const <Map<String, dynamic>>[]];
    items.sort((a, b) {
      final r = (_severityRank[a['severity']] ?? 3).compareTo(_severityRank[b['severity']] ?? 3);
      return r != 0 ? r : _at(b).compareTo(_at(a));
    });
    return items;
  }

  List<_Alert> get _alertRows {
    if (data == null) return _alerts;
    return [
      for (final a in _openAlertItems.take(3))
        _Alert(
          _severityName[a['severity']] ?? 'Alert',
          d8ListTime(_at(a)),
          _patientName(a),
          a.str('detail'),
          _severityTone(a.str('severity')),
          _alertTarget(a).$1,
          args: _alertTarget(a).$2,
        ),
    ];
  }

  int get _openCount => data == null ? (isLive ? 0 : 2) : _part('alerts')?.obj('counts').numOr('open', _openAlertItems.length).toInt() ?? 0;

  static String _visitType(String v) => switch (v) {
    'new' => 'New',
    'follow_up' => 'Follow-up',
    'report_review' => 'Report review',
    _ => 'Visit',
  };

  static String _status(String s) => switch (s) {
    'in_consultation' => 'In consult',
    'waiting' => 'Waiting',
    'completed' => 'Done',
    'missed' => 'Missed',
    _ => 'Upcoming',
  };

  static String _ageSex(Map<String, dynamic> p) {
    final age = p['age'];
    final g = switch (p['gender']) {
      'female' => 'F',
      'male' => 'M',
      'other' => 'O',
      _ => '',
    };
    return [if (age is num) '${age.round()}', if (g.isNotEmpty) g].join(' ');
  }

  /// Today's queue: who's in, waiting and next first (up to five rows).
  List<_Visit> get _queueRows {
    if (data == null) return _queue;
    final items = [..._part('queue')?.list('items') ?? const <Map<String, dynamic>>[]];
    const order = {'in_consultation': 0, 'waiting': 1, 'booked': 2, 'confirmed': 2, 'missed': 3, 'completed': 4};
    items.sort((a, b) {
      final r = (order[a['status']] ?? 2).compareTo(order[b['status']] ?? 2);
      return r != 0 ? r : _at(a, 'startAt').compareTo(_at(b, 'startAt'));
    });
    return [
      for (final a in items.take(5))
        _Visit(
          switch (F.date(a['startAt'])) {
            final t? => F.timeShort(t),
            null => a.str('token'),
          },
          a.obj('patient').str('name', 'Patient'),
          _status(a.str('status')),
          [_ageSex(a.obj('patient')), _visitType(a.str('visitType'))].where((s) => s.isNotEmpty).join(' · '),
          a['hasVitals'] == true,
          a.numOr('documents') > 0,
          patientId: a.obj('patient').str('id'),
          appointmentId: a.str('id'),
        ),
    ];
  }

  /// "12 visits · 3 waiting · 4 done"
  String get _queueLine {
    if (data == null) return '12 visits · 3 waiting · 4 done';
    final t = _dash.obj('today');
    return '${d8Plural(t.numOr('total'), 'visit')} · ${t.numOr('waiting')} waiting · ${t.numOr('completed')} done';
  }

  static (String, Color) _alertKind(Map<String, dynamic> a) {
    final sev = a.str('severity');
    return switch (a['kind']) {
      'lab' => sev == 'watch' ? ('Abnormal lab', MP.amber) : ('Critical lab', MP.red),
      'urgent_chat' => sev == 'emergency' ? ('Emergency message', MP.red) : ('Urgent message', MP.amber),
      'message' => ('Urgent message', MP.amber),
      'reading' => ('Abnormal reading', sev == 'emergency' ? MP.red : MP.amber),
      'adherence' => ('Missed doses', MP.amber),
      'follow_up' => ('Follow-up overdue', MP.ink2),
      'chat_flag' => ('Flagged chat', MP.ink2),
      _ => ('Alert', MP.ink2),
    };
  }

  /// Alerts and flagged AI answers since yesterday, most urgent first.
  List<(int, DateTime, _Review)> get _reviewItems {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final out = <(int, DateTime, _Review)>[];
    for (final a in _openAlertItems) {
      final at = _at(a);
      if (at.isBefore(since)) continue;
      final (kind, color) = _alertKind(a);
      final target = _alertTarget(a);
      out.add((_severityRank[a['severity']] ?? 2, at, _Review(kind, color, d8ListTime(at), _patientName(a), a.str('detail'), target.$1, args: target.$2)));
    }
    for (final r in _part('reviews')?.list('items') ?? const <Map<String, dynamic>>[]) {
      final at = _at(r);
      if (at.isBefore(since)) continue;
      out.add((
        r['urgency'] == 'high' ? 1 : 2,
        at,
        _Review(
          'Flagged chat',
          MP.ink2,
          d8ListTime(at),
          _patientName(r),
          r.str('title', r.str('excerpt')),
          'Chat-Review-Detail',
          args: {'reviewId': r.str('id'), 'conversationId': r.str('conversationId'), 'patientId': _patientIdOf(r)},
        ),
      ));
    }
    out.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
    return out;
  }

  List<Map<String, dynamic>> get _abnormal => _part('abnormal')?.list('items') ?? const [];

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// (initials, name, what's off, detail, patientId)
  List<(String, String, String, String, String?)> get _worseRows {
    if (data == null) return [for (final w in _worse) (w.$1, w.$2, w.$3, w.$4, null)];
    return [
      for (final p in _abnormal.take(3))
        (
          F.initials(p.str('name', '?')),
          p.str('name', 'Patient'),
          'Abnormal lab results to review',
          [
            if (p.str('riskLevel').isNotEmpty) 'Risk band ${_cap(p.str('riskLevel'))}',
            switch (F.date(p['lastVisitAt'])) {
              final at? => 'Last visit ${F.dayMonth(at)}',
              null => 'No visit yet',
            },
          ].join(' · '),
          p.str('id'),
        ),
    ];
  }

  int get _worseCount => data == null ? (isLive ? 0 : 3) : (_part('abnormal')?.numOr('total', _abnormal.length).toInt() ?? 0);

  /// Patients ranked by their most urgent open alert, then abnormal labs by risk.
  List<(String, String, String, String?)> get _triageRows {
    if (data == null) return [for (final t in _triage) (t.$1, t.$2, t.$3, null)];
    const bandRank = {'Critical': 0, 'High': 1, 'Moderate': 2, 'Low': 3};
    final best = <String, (String, String, String, String?)>{};
    void offer(String? id, String name, String why, String band) {
      final key = id ?? name;
      final cur = best[key];
      if (cur == null || (bandRank[band] ?? 3) < (bandRank[cur.$3] ?? 3)) best[key] = (name, why, band, id);
    }

    for (final a in _openAlertItems) {
      final band = switch (a['severity']) {
        'emergency' => 'Critical',
        'urgent' => 'High',
        _ => 'Moderate',
      };
      offer(_patientIdOf(a), _patientName(a), '${_alertKind(a).$1}: ${a.str('detail')}', band);
    }
    for (final p in _abnormal) {
      final band = _cap(p.str('riskLevel', 'moderate'));
      offer(p.str('id'), p.str('name', 'Patient'), 'Abnormal lab results to review', bandRank.containsKey(band) ? band : 'Moderate');
    }
    final rows = best.values.toList()..sort((a, b) => (bandRank[a.$3] ?? 3).compareTo(bandRank[b.$3] ?? 3));
    return rows.take(4).toList();
  }

  /// (count, label, stem, is a clinician tab).
  List<(String, String, String, bool)> get _actionValues {
    if (data == null) return _actions;
    final q = _dash.obj('actionQueue');
    return [
      ('${q.numOr('unreadMessages')}', 'Unread messages', 'Care', true),
      ('${q.numOr('checkInsOverdue')}', 'Check-ins overdue 7+ days', 'Doctor-FollowUps', false),
      ('${q.numOr('pendingActions')}', 'Pending action items', 'Alerts', false),
      ('${q.numOr('nutritionReviewsDue')}', 'Nutrition reviews due', 'Nutrition', true),
    ];
  }

  /// "Couldn't load this card" (Home-States · Error), with a retry.
  Widget _cardError(String title) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tx(20, w: w700, h: 1.25)),
          const Gap(16),
          Text("Couldn't load this card", style: tx(16, w: w600, h: 1.5)),
          const Gap(2),
          Text('The rest of Home is unaffected.', style: tx(14, c: MP.ink2, h: 20 / 14)),
          const Gap(16),
          MpButton.small('Try again', icon: I.history, iconStroke: 1.75, expand: false, onTap: () => reload(quiet: true)),
        ],
      ),
    );
  }

  // Tones from renderVals(): (background, foreground).
  static const _danger = (MP.redSoft, MP.red);
  static const _warn = (MP.amberSoft, MP.amber);
  static const _neutral = (MP.fill, MP.ink2);
  static const _info = (MP.primarySoft, MP.primary);
  static const _ok = (MP.greenSoft, MP.green);

  static (Color, Color) _statusTone(String s) => switch (s) {
    'In consult' => _info,
    'Waiting' => _warn,
    'Done' => _ok,
    _ => _neutral,
  };

  static (Color, Color) _bandTone(String b) => switch (b) {
    'Critical' => _danger,
    'High' => _warn,
    'Low' => _ok,
    _ => _neutral,
  };

  static const _quick = [
    (I.stethoscope, 'Start consultation', 'Consult-Pick'),
    (I.activity, 'Record vitals', 'Consult-Vitals'),
    (I.fileText, 'Write prescription', 'PP-Prescriptions'),
  ];

  static const _alerts = [
    _Alert(
      'Emergency',
      '9:12 AM',
      'Priya Sharma',
      'Emergency message: chest tightness and sweating since morning',
      _danger,
      'Patient-Thread',
    ),
    _Alert('Urgent', '8:40 AM', 'Rahul Das', 'Home BP reading 172/104 mmHg', _warn, 'PP-Summary'),
  ];

  static const _queue = [
    _Visit('9:00', 'Priya Sharma', 'In consult', '29 F · Follow-up', true, true),
    _Visit('9:30', 'Rahul Das', 'Waiting', '45 M · New', true, false),
    _Visit('10:00', 'Aisha Khan', 'Waiting', '52 F · Follow-up', true, false),
    _Visit('10:30', 'Sujit Mondal', 'Upcoming', '37 M · New', false, false),
    _Visit('11:00', 'Moumita Roy', 'Upcoming', '41 F · Follow-up', false, true),
  ];

  static const _review = [
    _Review('Critical lab', MP.red, '7:55 AM', 'Amit Pal', 'Potassium 6.1 mmol/L (critical high)', 'PP-Tests'),
    _Review(
      'Urgent message',
      MP.amber,
      '9:12 AM',
      'Priya Sharma',
      '“Chest feels tight since morning, should I come in?”',
      'Patient-Thread',
    ),
    _Review('Abnormal lab', MP.amber, 'Yesterday', 'Aisha Khan', 'TSH 8.9 mIU/L (high)', 'PP-Tests'),
    _Review(
      'Flagged chat',
      MP.ink2,
      'Yesterday',
      'Sujit Mondal',
      'AI answer about dosage timing flagged for review',
      'Chat-Review-Detail',
    ),
  ];

  static const _worse = [
    ('MR', 'Moumita Roy', 'Risk band Moderate → High', 'Changed 3 days ago'),
    ('AP', 'Amit Pal', '4 missed Metformin doses in a row', 'Last dose taken Fri, 25 Sep'),
    ('DB', 'Debasish Bose', 'Follow-up overdue by 9 days', 'Was due Sun, 20 Sep · no visit since'),
  ];

  static const _triage = [
    ('Amit Pal', 'Critical lab: potassium 6.1 mmol/L', 'Critical'),
    ('Priya Sharma', 'Open emergency alert', 'High'),
    ('Debasish Bose', 'HbA1c 9.4%, up from 8.1%', 'High'),
    ('Moumita Roy', 'Risk trend worsening', 'Moderate'),
  ];

  /// (count, label, stem, is a clinician tab).
  static const _actions = [
    ('6', 'Unread messages', 'Care', true),
    ('4', 'Check-ins overdue 7+ days', 'Doctor-FollowUps', false),
    ('3', 'Pending action items', 'Alerts', false),
    ('2', 'Nutrition reviews due', 'Nutrition', true),
  ];

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = data != null;
    return MpPage(
      nav: const ClinicianNav(current: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D8TabHeader(unread: live ? _dash.numOr('unreadNotifications').toInt() : null),
          if (placeholder != null) placeholder else VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 16,
            children: [
              _greeting(),
              _quickActions(context),
              if (live && _part('alerts') == null) _cardError('Open alerts') else _openAlerts(context),
              if (live && _part('queue') == null) _cardError("Today's OPD queue") else _opdQueue(context),
              if (live && _part('alerts') == null && _part('reviews') == null) _cardError('Needs review') else _needsReview(context),
              if (live && _part('abnormal') == null) _cardError('Worsening or off-track') else _worsening(context),
              if (live && _part('alerts') == null && _part('abnormal') == null) _cardError('Triage queue') else _triageQueue(context),
              _actionQueue(context),
              _weeklyImpact(),
            ],
          ),
        ],
      ),
    );
  }

  // ── Greeting ──────────────────────────────────────────────────────────────

  Widget _greeting() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data == null ? 'Good morning, Dr. Sen' : '${F.greeting()}, ${F.doctorShort(_dash.str('greetingName'))}',
            style: tx(28, w: w800, h: 1.15, em: -0.02),
          ),
          const Gap(6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: loadError != null ? MP.amber : MP.green, shape: BoxShape.circle),
              ),
              const Gap(8),
              Flexible(
                child: Text(
                  data == null
                      ? 'Tue, 29 Sep 2026 · Updated 4s ago'
                      : '${F.dateLong(DateTime.now())} · '
                          '${d8Updated(F.date(_dash['updatedAt']) ?? loadedAt ?? DateTime.now())}'
                          '${loadError != null ? ' · Reconnecting' : ''}',
                  style: tx(14, c: MP.ink2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick actions ─────────────────────────────────────────────────────────

  /// "Write prescription": choose the patient, then their profile's Prescriptions
  /// tab (past prescriptions, and Start consultation to write a new one).
  Future<void> _prescriptionFor(BuildContext context) async {
    if (!isLive) {
      Nav.go(context, 'PP-Prescriptions');
      return;
    }
    final id = await pickPatient(context, title: 'Prescription for');
    if (id == null || !context.mounted) return;
    Nav.go(context, 'PP-Prescriptions', args: {'patientId': id});
  }

  Widget _quickActions(BuildContext context) {
    // Consultations and prescriptions are for roles that prescribe (doctors);
    // assistants and dieticians keep "Record vitals".
    final quick = [
      for (final q in _quick)
        if (!isLive || q.$3 == 'Consult-Vitals' || Session.I.can('prescribe')) q,
    ];
    return Semantics(
      container: true,
      label: 'Quick actions',
      child: Row(
        children: [
          for (var i = 0; i < quick.length; i++) ...[
            if (i > 0) const Gap(8),
            Expanded(
              child: _QuickTile(
                icon: quick[i].$1,
                label: quick[i].$2,
                onTap: () => quick[i].$3 == 'PP-Prescriptions' ? _prescriptionFor(context) : Nav.go(context, quick[i].$3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Open alerts ───────────────────────────────────────────────────────────

  Widget _openAlerts(BuildContext context) {
    final rows = _alertRows;
    if (data != null && rows.isEmpty) {
      // Home-States · All clear: the alerts card is never hidden.
      return MpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Open alerts', style: tx(20, w: w700, h: 1.25)),
            const Gap(16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.check, size: 20, color: MP.green, stroke: 2.25)),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No open alerts', style: tx(16, w: w600, h: 1.5)),
                      Text(
                        'Last checked ${d8Updated(loadedAt ?? DateTime.now()).substring('Updated '.length)}',
                        style: tx(13, c: MP.ink3, h: 18 / 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return MpCard(
      border: MP.redLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Open alerts',
                          style: tx(20, w: w700, h: 1.25),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Gap(10),
                      MpBadge.red('$_openCount open'),
                    ],
                  ),
                ),
                D8Link('View all', onTap: () => Nav.go(context, 'Alerts')),
              ],
            ),
          ),
          for (final a in rows) ...[
            const Gap(4),
            _RowLink(
              onTap: () => Nav.go(context, a.stem, args: a.args),
              padding: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            MpBadge(a.severity, bg: a.tone.$1, fg: a.tone.$2),
                            const Gap(8),
                            Flexible(child: Text(a.time, style: tx(13, c: MP.ink3, tab: true))),
                          ],
                        ),
                        const Gap(6),
                        Text(a.name, style: tx(16, w: w600)),
                        const Gap(6),
                        Text(a.detail, style: tx(14, c: MP.ink2, h: 1.45)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Today's OPD queue (hero) ──────────────────────────────────────────────

  Widget _opdQueue(BuildContext context) {
    final rows = _queueRows;
    if (data != null && rows.isEmpty) {
      // Home-States · Empty.
      return MpCard(
        radius: 20,
        shadow: MPShadow.float,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's OPD queue", style: tx(20, w: w700, h: 1.25)),
            const Gap(16),
            Text('No visits booked today', style: tx(16, w: w600, h: 1.5)),
            const Gap(2),
            Text('Bookings and walk-ins show up here.', style: tx(14, c: MP.ink2, h: 20 / 14)),
            const Gap(16),
            MpButton.small('Open appointments', expand: false, onTap: () => Nav.go(context, 'Appointments')),
          ],
        ),
      );
    }
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: "Today's OPD queue",
            sub: _queueLine,
            trailing: _viewAll(context, 'Queue-List'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final l in const ['Vitals', 'Docs'])
                  SizedBox(
                    width: 44,
                    child: Text(
                      l.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: tx(11, w: w600, c: MP.ink3, em: 0.06),
                    ),
                  ),
              ],
            ),
          ),
          for (final q in rows) _visitRow(context, q),
        ],
      ),
    );
  }

  Widget _visitRow(BuildContext context, _Visit q) {
    final tone = _statusTone(q.status);
    Widget mark(bool done, String label) => Semantics(
      label: label,
      child: SizedBox(
        width: 44,
        child: Center(
          child: done ? const Ico(I.check, size: 18, color: MP.green, stroke: 2.25) : const D8PendingIcon(),
        ),
      ),
    );
    return _RowLink(
      onTap: () => Nav.go(
        context,
        'PP-Summary',
        args: q.patientId == null ? null : {'patientId': q.patientId, 'appointmentId': q.appointmentId},
      ),
      padding: 12,
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(q.time, style: tx(15, w: w600, tab: true), maxLines: 1)),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.name, style: tx(16, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Gap(4),
                LayoutBuilder(
                  builder:
                      (context, c) => Row(
                        children: [
                          // Full size normally; only scales down if very large
                          // text would leave the meta no room.
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: math.max(0, c.maxWidth - 40)),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: MpBadge(q.status, bg: tone.$1, fg: tone.$2, height: 22, padX: 8, weight: w600),
                            ),
                          ),
                          const Gap(8),
                          // Wraps (e.g. "29 F · Follow-" / "up") as in the design.
                          Flexible(child: Text(q.meta, style: tx(13, c: MP.ink3))),
                        ],
                      ),
                ),
              ],
            ),
          ),
          const Gap(12),
          mark(q.vitals, q.vitals ? 'Vitals on file today' : 'Vitals not yet recorded'),
          const Gap(12),
          mark(q.docs, q.docs ? 'Reports uploaded for this visit' : 'No reports for this visit'),
        ],
      ),
    );
  }

  // ── Needs review ──────────────────────────────────────────────────────────

  Widget _needsReview(BuildContext context) {
    final items = data == null ? null : _reviewItems;
    final rows = items == null ? _review : [for (final i in items.take(4)) i.$3];
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: 'Needs review',
            sub: items == null
                ? '4 items since yesterday, most urgent first'
                : items.isEmpty
                ? 'Nothing new since yesterday'
                : '${d8Plural(items.length, 'item')} since yesterday, most urgent first',
            trailing: _viewAll(context, 'Alerts'),
          ),
          for (final r in rows)
            _RowLink(
              onTap: () => Nav.go(context, r.stem, args: r.args),
              padding: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SectionLabel(r.kind, color: r.kindColor),
                            const Gap(8),
                            Flexible(
                              child: Text(
                                '· ${r.time}',
                                style: tx(13, c: MP.ink3, tab: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const Gap(4),
                        Text(r.name, style: tx(16, w: w600)),
                        const Gap(4),
                        Text(r.detail, style: tx(14, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Worsening or off-track ────────────────────────────────────────────────

  Widget _worsening(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: 'Worsening or off-track',
            sub: 'Trends worth a look this week',
            trailing: Padding(padding: const EdgeInsets.only(top: 2), child: MpBadge.amber(d8Plural(_worseCount, 'patient'))),
          ),
          if (data != null && _worseRows.isEmpty)
            Text('No patients off track right now', style: tx(14, c: MP.ink2)),
          for (final w in _worseRows)
            _RowLink(
              onTap: () => Nav.go(context, 'PP-Summary', args: w.$5 == null ? null : {'patientId': w.$5}),
              padding: 14,
              child: Row(
                children: [
                  MpAvatar(w.$1, size: 40, fontSize: 14),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.$2, style: tx(16, w: w600)),
                        const Gap(2),
                        Text(w.$3, style: tx(14, w: w600, c: MP.amber)),
                        const Gap(2),
                        Text(w.$4, style: tx(13, c: MP.ink3)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Triage queue ──────────────────────────────────────────────────────────

  Widget _triageQueue(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(
            title: 'Triage queue',
            sub: 'Patients ranked by who needs you first',
            trailing: _viewAll(context, 'Queue-List'),
          ),
          if (data != null && _triageRows.isEmpty)
            Text('No patients waiting on you', style: tx(14, c: MP.ink2)),
          for (final t in _triageRows)
            _RowLink(
              onTap: () => Nav.go(context, 'PP-Summary', args: t.$4 == null ? null : {'patientId': t.$4}),
              padding: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$1, style: tx(16, w: w600)),
                        const Gap(2),
                        Text(t.$2, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  MpBadge(t.$3, bg: _bandTone(t.$3).$1, fg: _bandTone(t.$3).$2),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Action queue ──────────────────────────────────────────────────────────

  Widget _actionQueue(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Action queue', style: tx(20, w: w700, h: 1.25)),
          const Gap(16),
          MpGrid(
            columns: 2,
            gap: 8,
            children: [
              for (final x in _actionValues)
                Tap(
                  onTap: () => x.$4 ? Nav.tab(context, x.$3) : Nav.go(context, x.$3),
                  radius: 12,
                  color: MP.bg,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(x.$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                      const Gap(6),
                      Text(x.$2, style: tx(14, c: MP.ink2, h: 1.35)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Weekly impact ─────────────────────────────────────────────────────────

  Widget _weeklyImpact() {
    final last7 = data == null ? const <String, dynamic>{} : _dash.obj('last7Days');
    final ai = data == null ? const <String, dynamic>{} : _dash.obj('aiChats');
    final avg = data == null ? 9 : last7['avgConsultMin'] as num?;
    final handled = data == null ? 142 : ai.numOr('handled').toInt();
    final escalated = data == null ? 18 : ai.numOr('escalated').toInt();
    final noData = tx(16, w: w600, c: MP.ink3, h: 1.5);
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weekly impact', style: tx(20, w: w700, h: 1.25)),
              const Gap(2),
              Text(
                data == null ? 'Last 7 days · 64 consultations' : 'Last 7 days · ${d8Plural(last7.numOr('consultations'), 'consultation')}',
                style: tx(14, c: MP.ink2),
              ),
            ],
          ),
          const Gap(20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Avg consultation time'),
              const Gap(4),
              // Home-States · Not enough data: never "0 min".
              if (avg == null) ...[
                Text('Not enough data yet', style: noData),
                const Gap(4),
                Text('Needs three completed consultations first.', style: tx(14, c: MP.ink2, h: 20 / 14)),
              ] else Text.rich(
                TextSpan(
                  text: '${avg.round()}',
                  // " min" inherits the parent's computed -0.6px letter-spacing.
                  children: [TextSpan(text: ' min', style: tx(16, w: w600, c: MP.ink2, h: 1, em: -0.6 / 16))],
                ),
                style: tx(30, w: w800, h: 1, em: -0.02, tab: true),
              ),
            ],
          ),
          const Gap(20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Patient chats'),
              if (handled + escalated <= 0) ...[
                const Gap(4),
                Text('Not enough data yet', style: noData),
              ] else ...[
                const Gap(10),
                _ChatSplitBar(handled: handled, escalated: escalated),
                const Gap(10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _legend(MP.primary, F.count(handled), 'handled by AI'),
                    const Gap(8),
                    _legend(MP.primaryLine, F.count(escalated), 'escalated'),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color swatch, String n, String text) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(2)),
          ),
          const Gap(6),
          Text(n, style: tx(14, w: w700, tab: true)),
          const Gap(6),
          Flexible(child: Text(text, style: tx(14, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  static Widget _viewAll(BuildContext context, String stem) =>
      D8Link('View all', padding: const EdgeInsets.only(top: 3), onTap: () => Nav.go(context, stem));
}

// ─────────────────────────────────────────────────────────────────────────────

class _Alert {
  final String severity;
  final String time;
  final String name;
  final String detail;
  final (Color, Color) tone;
  final String stem;
  final Object? args;
  const _Alert(this.severity, this.time, this.name, this.detail, this.tone, this.stem, {this.args});
}

class _Visit {
  final String time;
  final String name;
  final String status;
  final String meta;
  final bool vitals;
  final bool docs;
  final String? patientId;
  final String? appointmentId;
  const _Visit(this.time, this.name, this.status, this.meta, this.vitals, this.docs, {this.patientId, this.appointmentId});
}

class _Review {
  final String kind;
  final Color kindColor;
  final String time;
  final String name;
  final String detail;
  final String stem;
  final Object? args;
  const _Review(this.kind, this.kindColor, this.time, this.name, this.detail, this.stem, {this.args});
}

/// Card heading: 20/700 title + 14px subtitle on the left, [trailing] on the
/// right (`align-items: flex-start; padding-bottom: 12px`).
class _CardHead extends StatelessWidget {
  final String title;
  final String sub;
  final Widget trailing;
  const _CardHead({required this.title, required this.sub, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(20, w: w700, h: 1.25)),
                const Gap(2),
                Text(sub, style: tx(14, c: MP.ink2)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// A list row inside a card: `padding: Npx 0; border-top: 1px solid #E5E9F0`.
class _RowLink extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double padding;
  const _RowLink({required this.child, required this.onTap, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 0,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: padding),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: child,
      ),
    );
  }
}

/// 84px quick-action tile: icon on top, label at the bottom
/// (`justify-content: space-between`). As in the design's flexbox, a two-line
/// label that doesn't fit next to the 22px icon makes the icon shrink
/// (`flex-shrink: 1`) instead of overflowing.
class _QuickTile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _QuickTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: 84,
      child: Tap(
        onTap: onTap,
        radius: 12,
        color: MP.white,
        border: MP.line,
        shadow: MPShadow.card,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: LayoutBuilder(
          builder: (context, c) {
            final style = _fitLongestWord(tx(14, w: w600, h: 1.25), c.maxWidth, scaler);
            final tp = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
            )..layout(maxWidth: c.maxWidth);
            final iconHeight = (c.maxHeight - tp.height).clamp(0.0, 22.0);
            tp.dispose();
            return OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    height: iconHeight,
                    child: FittedBox(child: Ico(icon, size: 22, color: MP.primary)),
                  ),
                  Text(label, style: style),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Shrinks the font just enough for the longest word to fit (narrow
  /// phones), instead of breaking a word in the middle.
  TextStyle _fitLongestWord(TextStyle style, double maxWidth, TextScaler scaler) {
    var widest = 0.0;
    for (final word in label.split(' ')) {
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }
    if (widest <= maxWidth || widest == 0) return style;
    final size = style.fontSize ?? 14;
    return style.copyWith(fontSize: (size * maxWidth / widest * 4).floorToDouble() / 4);
  }
}

/// 10px split bar: 88.75% #003399, 2px gap, rest #B8C6E3, radius 999.
class _ChatSplitBar extends StatelessWidget {
  final int handled;
  final int escalated;
  const _ChatSplitBar({required this.handled, required this.escalated});

  @override
  Widget build(BuildContext context) {
    final share = handled + escalated <= 0 ? 0.0 : handled / (handled + escalated);
    return Semantics(
      label: '$handled handled by AI, $escalated escalated to the clinic',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder:
                (context, c) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: math.max(0, c.maxWidth * share - (share >= 1 ? 2 : 0)), child: const ColoredBox(color: MP.primary)),
                    const SizedBox(width: 2),
                    const Expanded(child: ColoredBox(color: MP.primaryLine)),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

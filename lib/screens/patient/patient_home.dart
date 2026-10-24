import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/device_sync.dart';
import '../../data/phone_steps.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/photo.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';
import 'p1_sheets.dart';
import 'patient_log.dart';
import '../../data/rx_pdf.dart';
import '../../data/downloads.dart';
import '../../widgets/i18n.dart';
import 'alarm_check.dart';

/// Design: Main.dc.html — "Patient · Home".
class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

typedef _Task = ({String icon, String title, String sub, String action, String later, String doneLabel});

/// Live data: GET /api/patient/home.
class _PatientHomeScreenState extends State<PatientHomeScreen> with LiveData {
  static const List<_Task> _tasks = [
    (icon: I.pill, title: 'Glimepiride 1 mg', sub: '7:30 AM · before breakfast', action: '', later: '', doneLabel: 'Taken'),
    (icon: I.pill, title: 'Metformin 500 mg', sub: '8:30 AM · after breakfast', action: '', later: '', doneLabel: 'Taken'),
    (icon: I.drop, title: 'Log fasting sugar', sub: 'Best before breakfast', action: 'Log', later: '', doneLabel: 'Logged'),
    (icon: I.upload, title: 'Upload HbA1c report', sub: 'Dr. Sen needs it before 5 PM', action: 'Upload', later: '', doneLabel: 'Uploaded'),
    (icon: I.pill, title: 'Metformin 500 mg', sub: '8:30 PM · after dinner', action: '', later: 'Tonight', doneLabel: 'Taken'),
  ];

  /// Watch / wearable icon (smartwatch and ring sync).
  static const _watch = '<rect x="6" y="6" width="12" height="12" rx="3"/><path d="M9 6V3h6v3M9 18v3h6v-3M12 10v2l1 1"/>';

  final Set<int> _done = {0, 1};
  bool _walkDone = false;

  @override
  Future<Object?> fetch() async {
    final home = await Api.I.get('/api/patient/home');
    // Steps from the phone and readings from a connected watch go up quietly
    // (at most every 30 min); the first time, Android asks for "Physical activity".
    DeviceSync.auto().then((sent) {
      if (sent && mounted) reload(quiet: true);
    });
    return home;
  }


  List<Map<String, dynamic>> get _rawTasks => data?.list('tasks') ?? const [];

  /// Today's checklist: the design's sample, or doses, meals and visit to-dos.
  List<_Task> get _taskList => data == null ? _tasks : [for (final t in _rawTasks) _taskFrom(t)];

  Set<int> get _doneSet => data == null
      ? _done
      : {
          for (var i = 0; i < _rawTasks.length; i++)
            if (_rawTasks[i]['done'] == true) i,
        };

  static String _todoAction(String text) {
    final t = text.toLowerCase();
    if (t.contains('upload')) return 'Upload';
    if (t.contains('log')) return 'Log';
    return 'Done';
  }

  _Task _taskFrom(Map<String, dynamic> t) {
    switch (t['kind']) {
      case 'dose':
        // As the alarm says it: "7:45 AM · after breakfast"; Take once it's due
        // (from 30 min before), else when it's due ("In 25 min", "Tonight").
        final at = F.date(t['at']);
        final meal = const {'morning': 'breakfast', 'afternoon': 'lunch', 'night': 'dinner'}[t['slot']] ?? 'food';
        final how = switch (t['foodRelation']) {
          'before_food' => 'before $meal',
          'after_food' => 'after $meal',
          'with_food' => 'with $meal',
          'empty_stomach' => 'on an empty stomach',
          'bedtime' => 'at bedtime',
          _ => null,
        };
        final status = t['status'];
        final now = DateTime.now();
        final mins = at == null ? 0 : at.difference(now).inMinutes;
        // Skipped (or missed) is settled: no "Take" for it.
        final due = status != 'missed' && status != 'skipped' && at != null && mins <= 30;
        return (
          icon: I.pill,
          title: t.str('title'),
          sub: [if (at != null) F.time(at), if (how != null) how].join(' · '),
          action: due ? 'Take' : '',
          later: status == 'missed'
              ? 'Missed'
              : status == 'skipped'
                  ? 'Skipped'
              : mins < 60
                  ? 'In $mins min'
                  : t['slot'] == 'night'
                      ? 'Tonight'
                      : 'Later today',
          doneLabel: 'Taken',
        );
      case 'visit_todo':
        final action = _todoAction(t.str('title'));
        return (
          icon: action == 'Upload' ? I.upload : action == 'Log' ? I.drop : I.check,
          title: t.str('title'),
          sub: 'Before your visit today',
          action: action,
          later: '',
          doneLabel: action == 'Upload' ? 'Uploaded' : action == 'Log' ? 'Logged' : 'Done',
        );
      default:
        final logged = [for (final m in (t['detail'] as List? ?? const [])) '$m'];
        return (
          icon: I.camera,
          title: 'Log your meals',
          sub: logged.isEmpty ? 'Nothing logged yet today' : 'Logged: ${logged.join(', ')}',
          action: 'Log',
          later: '',
          doneLabel: 'Logged',
        );
    }
  }

  /// The measure a "Log …" to-do is about (fasting sugar, BP…), if any.
  static String? _measureIn(String text) {
    final t = text.toLowerCase();
    if (t.contains('sugar') || t.contains('glucose')) return 'blood_sugar';
    if (t.contains('bp') || t.contains('blood pressure')) return 'blood_pressure';
    if (t.contains('weight')) return 'weight';
    if (t.contains('pulse') || t.contains('heart rate')) return 'heart_rate';
    if (t.contains('spo2') || t.contains('oxygen')) return 'spo2';
    return null;
  }

  Future<void> _taskAction(BuildContext context, int i) async {
    final t = _taskList[i];
    if (!isLive) {
      if (t.action == 'Upload') {
        Nav.go(context, 'Records-Add');
      } else {
        setState(() => _done.add(i));
      }
      return;
    }
    final raw = _rawTasks[i];
    // Take: one tap marks the dose taken (its reminder is cancelled with it).
    if (raw['kind'] == 'dose') {
      final ok = await runAction(context, () => Api.I.post('/api/patient/doses/${raw['id']}', {'status': 'taken'}));
      if (ok == null || !context.mounted) return;
      toast(context, '${raw['title']} taken');
      reload(quiet: true);
      return;
    }
    final appointment = raw['appointmentId'];
    Object? result = true;
    if (t.action == 'Upload') {
      result = await Nav.go(context, 'Records-Add', args: {'kind': 'test_result', 'appointmentId': appointment, 'title': t.title});
    } else if (t.action == 'Log') {
      final measure = _measureIn(t.title);
      result = measure != null
          ? await openSheet<bool>(context, (_) => P1ReadingSheet(measure: measure))
          : await Nav.go(context, 'Patient-Log');
    }
    // A visit to-do is ticked off once its action went through (or straight away for "Done").
    if (raw['kind'] == 'visit_todo' && context.mounted && (t.action == 'Done' || result != null)) {
      await runAction(context, () => Api.I.post('/api/patient/appointments/$appointment/todos/${raw['id']}', {'done': true}));
    }
    if (mounted) reload(quiet: true);
  }

  /// Tapping a dose row: Taken / Skip (or undo).
  Future<void> _doseTap(BuildContext context, int i) async {
    final raw = _rawTasks[i];
    final changed = await openSheet<bool>(context, (_) => P1DoseSheet(dose: {...raw, 'status': raw['done'] == true ? 'taken' : raw['status']}));
    if (changed == true && mounted) reload(quiet: true);
  }

  // ── Header ──
  String get _name => data == null ? 'Priya' : data!.str('greetingName', F.firstName(Session.I.name));
  String get _hello => data == null ? 'Good morning,' : '${F.greeting()},';
  /// Last watch / phone sync (null: never connected).
  DateTime? get _synced => F.date(data?.obj('deviceSync')['at']);

  /// The last sync brought in nothing (no watch writing to Health Connect yet).
  bool get _syncEmpty {
    final s = data?.obj('deviceSync') ?? const {};
    return s['readings'] == 0 && s['stepDays'] == 0;
  }

  int get _unread => data == null ? (isLive ? 0 : 1) : data!.numOr('unreadNotifications').toInt();
  String get _initials => data == null ? 'PS' : F.initials(Session.I.name.isEmpty ? _name : Session.I.name);

  // ── Carousel ──
  List<P1Slide> get _slides => data == null ? P1.slides : P1.slidesFrom(data!);

  Future<void> _openBell(BuildContext context) async {
    if (!isLive) {
      toast(context, 'Notifications are coming soon');
      return;
    }
    await openSheet<bool>(context, (_) => const P1NotificationsSheet());
    if (mounted) reload(quiet: true);
  }

  Future<void> _openHistory(BuildContext context) async {
    if (!isLive) {
      toast(context, 'Log history is coming soon');
      return;
    }
    final changed = await openSheet<bool>(context, (_) => const P1LogHistorySheet());
    if (changed == true && mounted) reload(quiet: true);
  }

  Future<void> _openReading(BuildContext context, String measure) async {
    final saved = await openSheet<bool>(context, (_) => P1ReadingSheet(measure: measure));
    if (saved == true && mounted) reload(quiet: true);
  }

  /// "Change" under the daily log: the first doctor it is shared with.
  /// "Change": who sees the daily log (all of the care team to choose from).
  Future<void> _openSharing(BuildContext context) async {
    if (!isLive) return toast(context, 'Share your daily log');
    final changed = await openSheet<bool>(context, (_) => const LogSharingSheet());
    if (changed == true && mounted) reload(quiet: true);
  }

  // ── Daily log ──
  static const _mealOrder = ['breakfast', 'lunch', 'dinner'];

  String get _mealsLine {
    if (data == null) return 'Breakfast logged · lunch next';
    final logged = [for (final m in (data!['mealsLogged'] as List? ?? const [])) '$m'];
    final next = _mealOrder.where((m) => !logged.contains(m)).firstOrNull;
    if (logged.isEmpty) return 'Nothing logged yet · ${next ?? 'breakfast'} next';
    final last = logged.last;
    final cap = last[0].toUpperCase() + last.substring(1);
    return next == null ? 'All meals logged' : '$cap logged · $next next';
  }

  Map<String, dynamic> get _plan => data?.obj('activityPlan') ?? const {};

  static String _clock(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return F.time(DateTime(2000, 1, 1, h, m));
  }

  Future<void> _markWalkDone() async {
    if (!isLive) {
      setState(() => _walkDone = true);
      return;
    }
    final ok = await runAction(context, () => Api.I.post('/api/patient/activity-plans/${_plan['id']}/done'));
    if (ok != null && mounted) reload(quiet: true);
  }

  bool _alarmAsked = false;

  /// Once, when there are medicines to remind about: keep alarms on time (battery saving).
  void _askAlarmsOnce() {
    if (_alarmAsked || !isLive || data == null) return;
    if (!data!.list('tasks').any((t) => t.str('kind') == 'dose')) return;
    _alarmAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AlarmCheck.askOnce(context);
    });
  }

  int get _exMin => data?.obj('exercise').numOr('minutes').toInt() ?? 0;
  int get _exGoal => data?.obj('exercise').numOr('goal', 30).toInt() ?? 30;
  int get _exSessions => data?.obj('exercise').numOr('sessions').toInt() ?? 0;

  /// The patient's daily goals (steps, exercise minutes).
  Future<void> _openGoals(BuildContext context) async {
    final saved = await openSheet<bool>(context, (_) => _GoalsSheet(steps: _stepGoal, exercise: _exGoal));
    if (saved == true && mounted) reload(quiet: true);
  }

  int get _steps => data == null ? 4820 : data!.obj('steps').numOr('today').toInt();
  int get _stepGoal => data == null ? 8000 : data!.obj('steps').numOr('goal', 8000).toInt();

  String get _sharedLine {
    if (data == null) return 'Shared with Dr. Sen and Mou (dietician)';
    final people = [
      for (final p in data!.list('logSharedWith'))
        p['role'] == 'doctor' ? F.doctorShort(p.str('name')) : '${F.firstName(p.str('name'))} (${p.str('role').replaceAll('_', ' ')})',
    ];
    return people.isEmpty ? 'Not shared with your care team yet' : 'Shared with ${F.joinAnd(people)}';
  }

  // ── Your health ──
  num? get _score => data == null ? 74 : data!.obj('healthScore')['value'] as num?;
  int get _scoreDelta => data == null ? 3 : data!.obj('healthScore').numOr('weeklyDelta').toInt();
  num? get _adherence => data == null ? 86 : data!.obj('adherence')['pct'] as num?;
  int get _adherenceDoctors => data == null ? 3 : data!.obj('adherence').numOr('doctors').toInt();

  // ── Health summary ──
  Map<String, dynamic>? get _ai {
    if (data == null) return null;
    final a = data!.obj('aiSummary');
    return a.isEmpty ? null : a;
  }

  // ── What you track ──
  static const _measureLabels = {
    'blood_sugar': ('Fasting sugar', ' mg/dL'),
    'blood_pressure': ('Blood pressure', null),
    'weight': ('Weight', ' kg'),
    'heart_rate': ('Heart rate', ' bpm'),
    'spo2': ('SpO₂', '%'),
    'hba1c': ('HbA1c', '%'),
    'ldl': ('LDL cholesterol', ' mg/dL'),
    'creatinine': ('Creatinine', ' mg/dL'),
  };

  /// Measures that come only from lab reports (a tap opens Records, not "add a reading").
  static const _labOnly = {'hba1c', 'ldl', 'creatinine'};

  /// Sparkline points in the tile's 130×32 box.
  static String _points(List<num> values) {
    if (values.isEmpty) return '';
    final lo = values.reduce(math.min).toDouble();
    final hi = values.reduce(math.max).toDouble();
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    final n = values.length;
    return [
      for (var i = 0; i < n; i++)
        '${(n == 1 ? 65 : 2 + i * 126 / (n - 1)).round()},${(28 - (values[i] - lo) / span * 24).round()}',
    ].join(' ');
  }

  (String note, Color color) _noteFor(String measure, Map<String, dynamic> last) {
    final v = last.numOr('value');
    switch (measure) {
      case 'blood_sugar':
        final target = data!.obj('targets').numOr('sugarFasting', 130);
        return v > target ? ('Above target', MP.amber) : ('In range', MP.green);
      case 'blood_pressure':
        final dia = last.numOr('value2');
        if (v >= 140 || dia >= 90) return ('High', MP.amber);
        if (v >= 130 || dia >= 80) return ('Above normal', MP.amber);
        return ('Normal', MP.green);
      case 'heart_rate':
        return v < 50 || v > 100 ? ('Check with your doctor', MP.amber) : ('Normal', MP.green);
      case 'spo2':
        return v < 95 ? ('Low', MP.amber) : ('Normal', MP.green);
      case 'hba1c':
        final target = data!.obj('targets').numOr('hba1c', 7);
        return v > target ? ('Above target', MP.amber) : ('In target', MP.green);
      case 'ldl':
      case 'creatinine':
        // The lab's own range (its flag on the report).
        return switch (last.str('flag')) {
          'high' || 'critical' => ('Above range', MP.amber),
          'low' => ('Below range', MP.amber),
          _ => ('In range', MP.green),
        };
      default:
        return ('', MP.ink3);
    }
  }

  List<Widget> _trackTiles(BuildContext context) {
    final measures = [
      for (final m in (data!['trackedMeasures'] as List? ?? const []))
        if (_measureLabels.containsKey(m)) '$m',
    ].take(4);
    final tracked = data!.obj('tracked');
    return [
      for (final m in measures)
        () {
          final series = tracked.list(m);
          final (label, unit) = _measureLabels[m]!;
          if (series.isEmpty) {
            return _TrackTile(
              label: label,
              value: '–',
              points: '',
              note: _labOnly.contains(m) ? 'From your next lab report' : 'No reading yet',
              noteColor: MP.ink3,
              onTap: () => _labOnly.contains(m) ? Nav.tab(context, 'Patient-Records') : _openReading(context, m),
            );
          }
          final last = series.last;
          final value = m == 'blood_pressure'
              ? '${last.numOr('value').round()}/${last.numOr('value2').round()}'
              : last.numOr('value').toStringAsFixed(last.numOr('value') % 1 == 0 ? 0 : 1);
          final (status, color) = _noteFor(m, last);
          // When it was measured: the time today, else the date.
          final at = F.date(last['at']);
          final when = at == null ? '' : (F.sameDay(at, DateTime.now()) ? F.time(at) : F.dayMonth(at));
          // A value from a lab report says so ("lab · 15 Oct").
          final stamp = last.str('source') == 'lab' && !_labOnly.contains(m) && when.isNotEmpty ? 'lab · $when' : when;
          final note = [status, stamp].where((s) => s.isNotEmpty).join(' · ');
          return _TrackTile(
            label: label,
            value: value,
            unit: unit,
            points: _points([for (final x in series) x.numOr('value')]),
            note: note,
            noteColor: color,
            onTap: () => _labOnly.contains(m) ? Nav.tab(context, 'Patient-Records') : _openReading(context, m),
          );
        }(),
    ];
  }

  // ── From your doctor ──
  Map<String, dynamic>? get _rx => data == null ? null : (data!.obj('latestPrescription').isEmpty ? null : data!.obj('latestPrescription'));
  Map<String, dynamic>? get _lab => data == null ? null : (data!.obj('latestLab').isEmpty ? null : data!.obj('latestLab'));

  Future<void> _download(BuildContext context) async {
    final rx = _rx;
    if (rx == null) return toast(context, 'This prescription has no file yet');
    if (rx['uploaded'] == true) {
      await Downloads.save(context, rx['url'] as String?, name: 'Prescription', title: 'Prescription downloaded');
    } else {
      await RxPdf.download(context, rx['id']?.toString(), patient: true);
    }
  }

  Future<void> _openLog(BuildContext context, int tab) async {
    final Future<bool?> sheet;
    if (tab == 0) {
      sheet = Nav.go<bool>(context, 'Patient-Log');
    } else {
      sheet = openSheet<bool>(context, (_) => PatientLogSheet(initialTab: tab));
    }
    if (await sheet == true && mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final placeholder = livePlaceholder();
    final slides = placeholder == null ? _slides : const <P1Slide>[];
    _askAlarmsOnce();
    return MpPage(
      nav: const PatientNav(current: 0),
      overlays: [
        Positioned(
          right: 20,
          bottom: 108 + safeBottom,
          child: _AskFab(onTap: () => Nav.go(context, 'Patient-AskAI')),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const Gap(20),
          if (placeholder != null) placeholder else ...[
          // The slide row bleeds into the right gutter (margin-right: -20px).
          if (slides.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.only(left: 20), child: _HeroCarousel(slides: slides)),
            const Gap(16),
          ],
          _pad(_emergency(context)),
          const Gap(16),
          _pad(_today(context)),
          const Gap(16),
          // Tests the doctor asked for that still need a result (hidden when none).
          if (_dueTests.isNotEmpty) ...[
            _pad(_labTests(context)),
            const Gap(16),
          ],
          // The patient's own log (meals by choice, exercise, steps), shared with whom they pick.
          _pad(_dailyLog(context)),
          const Gap(16),
          _pad(_health(context)),
          if (data == null || _ai != null) ...[
            const Gap(16),
            _pad(_summary(context)),
          ],
          const Gap(16),
          _pad(_tracking(context)),
          if (data == null || _rx != null || _lab != null) ...[
            const Gap(16),
            _pad(_fromDoctor(context)),
          ],
          ],
          // main has 184px below it; MpPage already leaves 112 for the nav.
          const Gap(72),
        ],
      ),
    );
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  Widget _card({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    return Container(padding: padding, decoration: MPDeco.card(), child: child);
  }

  Widget _cardTitle(String text) => Text(text, style: tx(20, w: w700, h: 1.25));

  /// Card heading with a link on the right, baseline-aligned.
  Widget _cardHeading(String text, String link, VoidCallback onLink) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: _cardTitle(text)),
        const Gap(12),
        _TextLink(link, onTap: onLink),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_hello, style: tx(15, c: MP.ink2)),
                const Gap(2),
                Text(_name, style: tx(28, w: w800, h: 1.15, em: -0.02)),
              ],
            ),
          ),
          const Gap(12),
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
                onTap: () => _openBell(context),
              ),
              // 8px dot + 2px white ring, top 9 / right 10 inside the border.
              if (_unread > 0) Positioned(
                top: 10,
                right: 11,
                child: IgnorePointer(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: MP.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: MP.white, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Gap(8),
          Semantics(
            button: true,
            label: 'Profile',
            child: Tap(
              onTap: () => Nav.tab(context, 'Patient-Me'),
              radius: 999,
              child: MpAvatar(_initials, size: 44, fontSize: 15, photo: isLive ? myPhotoUrl : null),
            ),
          ),
        ],
      ),
    );
  }

  // ── Emergency link ────────────────────────────────────────────────────────

  Widget _emergency(BuildContext context) {
    // <a> is content-box: 52px + the 1px border = 54px.
    return Tap(
      onTap: () => Nav.go(context, 'Patient-Emergency'),
      radius: 16,
      color: MP.white,
      border: MP.redLine,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Ico(I.messageAlert, size: 18, color: MP.red),
              const Gap(12),
              Expanded(
                child: Text(
                  'Emergency? Chat with your doctor',
                  style: tx(15, w: w600, c: MP.red),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Gap(12),
              const Ico(I.chevronRight, size: 18, color: MP.red),
            ],
          ),
        ),
      ),
    );
  }

  // ── Today's checklist ─────────────────────────────────────────────────────

  Widget _today(BuildContext context) {
    final tasks = _taskList;
    final n = _doneSet.length;
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: _cardTitle('Today')),
                    Text('$n of ${tasks.length} tasks done', style: tx(14, c: MP.ink2, tab: true)),
                  ],
                ),
                const Gap(10),
                Semantics(
                  label: '$n of ${tasks.length} tasks done',
                  child: MpProgress(tasks.isEmpty ? 0 : n / tasks.length, height: 6, color: MP.green, track: MP.line),
                ),
              ],
            ),
          ),
          for (var i = 0; i < tasks.length; i++) _taskRow(context, i),
        ],
      ),
    );
  }

  Widget _taskRow(BuildContext context, int i) {
    final t = _taskList[i];
    final done = _doneSet.contains(i);
    final Widget trailing;
    if (done) {
      trailing = _DoneBadge(t.doneLabel);
    } else if (t.action.isNotEmpty) {
      trailing = P1SoftButton(t.action, onTap: () => _taskAction(context, i));
    } else {
      trailing = Text(t.later, style: tx(13, w: w600, c: MP.ink3));
    }
    final isDose = data != null && _rawTasks[i]['kind'] == 'dose';
    return _ListRow(
      first: i == 0,
      onTap: isDose ? () => _doseTap(context, i) : null,
      child: Row(
        children: [
          MpIconTile(t.icon, size: 40, iconSize: 20, radius: 12, bg: MP.fill, fg: MP.ink2),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: tx(16, w: w600, c: done ? MP.ink2 : MP.ink)),
                const Gap(2),
                Text(t.sub, style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Gap(12),
          trailing,
        ],
      ),
    );
  }

  // ── Lab tests ─────────────────────────────────────────────────────────────
  // Tests the doctor asked for that have no result yet (soonest first). Home
  // shows the first few; View all opens Records on its Tests filter.

  static const _sampleTests = [
    {'name': 'HbA1c', 'doctorName': 'Dr. Arjun Sen', 'bringBy': '2026-10-28', 'fasting': false},
    {'name': 'Fasting lipid profile', 'doctorName': 'Dr. Arjun Sen', 'bringBy': '2026-10-28', 'fasting': true},
    {'name': 'Vitamin D', 'doctorName': 'Dr. Rina Mitra', 'fasting': false},
  ];

  List<Map<String, dynamic>> get _dueTests => data == null ? _sampleTests : data!.obj('pendingTests').list('items');
  int get _dueTotal => data == null ? 5 : data!.obj('pendingTests').numOr('total').toInt();

  void _allTests(BuildContext context) => Nav.tab(context, 'Patient-Records', args: const {'filter': 'tests'});

  /// Upload: Add record set to that test and shared with the doctor who asked;
  /// once saved it is in Records and drops off this card.
  Future<void> _uploadTest(BuildContext context, Map<String, dynamic> t) async {
    if (!isLive) {
      Nav.go(context, 'Records-Add');
      return;
    }
    await Nav.go(context, 'Records-Add', args: {
      'kind': 'test_result',
      'forTest': t.str('name'),
      if (t.str('doctorId').isNotEmpty) 'doctorId': t.str('doctorId'),
      if (t.str('doctorName').isNotEmpty) 'doctorName': t.str('doctorName'),
    });
    if (mounted) reload(quiet: true);
  }

  static String _shortDoctor(String name) {
    final t = name.trim();
    if (RegExp(r'^Dr\.?\s', caseSensitive: false).hasMatch(t)) return 'Dr. ${t.split(RegExp(r'\s+')).last}';
    return t.split(RegExp(r'\s+')).first;
  }

  Widget _labTests(BuildContext context) {
    final tests = _dueTests;
    final total = _dueTotal;
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                total > tests.length ? _cardHeading('Lab tests', 'View all', () => _allTests(context)) : _cardTitle('Lab tests'),
                const Gap(2),
                Text('$total to do', style: tx(14, c: MP.ink2, tab: true)),
              ],
            ),
          ),
          for (var i = 0; i < tests.length; i++) _testRow(context, tests[i], first: i == 0),
        ],
      ),
    );
  }

  Widget _testRow(BuildContext context, Map<String, dynamic> t, {required bool first}) {
    final bringBy = F.date(t['bringBy']);
    final sub = [
      if (t.str('doctorName').isNotEmpty) _shortDoctor(t.str('doctorName')),
      if (bringBy != null) tr(context, 'Bring by #1').replaceFirst('#1', F.dayMonth(bringBy)),
      if (t['fasting'] == true) tr(context, 'Fasting needed'),
    ].join(' · ');
    return _ListRow(
      first: first,
      onTap: () => _allTests(context),
      child: Row(
        children: [
          MpIconTile(I.flask, size: 40, iconSize: 20, radius: 12, bg: MP.fill, fg: MP.ink2),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.str('name'), style: tx(16, w: w600)),
                if (sub.isNotEmpty) ...[const Gap(2), Text(sub, style: tx(13, c: MP.ink2))],
                // The last upload for it didn't count: say why.
                if (t.str('status') == 'wrong' || t.str('status') == 'unreadable') ...[
                  const Gap(2),
                  Text(t.str('status') == 'wrong' ? 'Last upload was a different report' : "Couldn't read the last upload", style: tx(13, w: w600, c: MP.amber)),
                ],
              ],
            ),
          ),
          const Gap(12),
          P1SoftButton('Upload', onTap: () => _uploadTest(context, t)),
        ],
      ),
    );
  }

  // ── Daily log ─────────────────────────────────────────────────────────────

  Widget _dailyLog(BuildContext context) {
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _cardHeading('Daily log', 'History', () => _openHistory(context)),
          ),
          _ListRow(
            first: true,
            child: _LogLine(
              title: const Text('Meals'),
              sub: _mealsLine,
              trailing: P1SoftButton('Log meal', icon: I.camera, onTap: () => _openLog(context, 0)),
            ),
          ),
          if (data == null)
            _ListRow(
              child: _LogLine(
                title: const Text('Evening walk · 30 min'),
                sub: 'Planned 6:00 PM · ${_walkDone ? 4 : 3} of 5 this week',
                trailing: _walkDone ? const _DoneBadge('Done') : P1SoftButton('Mark done', onTap: _markWalkDone),
              ),
            )
          else if (_plan.isNotEmpty)
            _ListRow(
              child: _LogLine(
                title: Text('${_plan.str('name')}${_plan['durationMin'] == null ? '' : ' · ${_plan['durationMin']} min'}'),
                sub: '${_plan['plannedTime'] == null ? '' : 'Planned ${_clock(_plan.str('plannedTime'))} · '}'
                    '${_plan['doneThisWeek']} of ${_plan['daysPerWeek']} this week',
                trailing: _plan['doneToday'] == true ? const _DoneBadge('Done') : P1SoftButton('Mark done', onTap: _markWalkDone),
              ),
            ),
          if (data != null)
            _ListRow(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LogLine(
                    title: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$_exMin', style: tx(16, w: w600, tab: true)),
                        TextSpan(text: ' of $_exGoal min exercise'),
                      ]),
                    ),
                    sub: _exMin == 0
                        ? 'Nothing logged yet today'
                        : '$_exSessions ${_exSessions == 1 ? 'session' : 'sessions'} today${_exMin >= _exGoal ? ' · goal reached' : ''}',
                    trailing: P1SoftButton('Log', onTap: () => _openLog(context, 1)),
                  ),
                  const Gap(8),
                  MpProgress(_exGoal == 0 ? 0 : math.min(1, _exMin / _exGoal), height: 6, color: MP.green, track: MP.line),
                ],
              ),
            ),
          _ListRow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LogLine(
                  title: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: F.count(_steps), style: tx(16, w: w600, tab: true)),
                      const TextSpan(text: ' steps'),
                    ]),
                  ),
                  sub: 'Goal ${F.count(_stepGoal)} · ${switch (data?.obj('steps').str('source')) {
                    'phone' => 'counted by your phone',
                    'watch' => data!.obj('steps').str('app').isEmpty ? 'from Health Connect' : 'from ${data!.obj('steps').str('app')}',
                    'manual' => 'entered by you',
                    _ => isLive ? 'opens to your phone’s step count' : 'entered by you',
                  }}',
                  trailing: P1SoftButton('Add', onTap: () => _openLog(context, 2)),
                ),
                const Gap(8),
                Semantics(
                  label: '${F.count(_steps)} of ${F.count(_stepGoal)} steps',
                  child: MpProgress(_stepGoal == 0 ? 0 : math.min(1, _steps / _stepGoal), height: 6, color: MP.primary, track: MP.line),
                ),
              ],
            ),
          ),
          if (data != null)
            Tap(
              onTap: () => _openGoals(context),
              radius: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                child: Row(
                  children: [
                    const Ico(I.star, size: 16, color: MP.ink2),
                    const Gap(10),
                    Expanded(child: Text('Your goals · ${F.count(_stepGoal)} steps · $_exGoal min exercise a day', style: tx(13, c: MP.ink2))),
                    Text('Change', style: tx(13, w: w600, c: MP.primary)),
                  ],
                ),
              ),
            ),
          Tap(
            onTap: () => _openSharing(context),
            radius: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  const Ico(I.share, size: 16, color: MP.ink2),
                  const Gap(10),
                  Expanded(child: Text(_sharedLine, style: tx(13, c: MP.ink2))),
                  const Gap(10),
                  Text('Change', style: tx(14, w: w600, c: MP.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Your health: scores ───────────────────────────────────────────────────

  Widget _health(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle('Your health'),
          const Gap(16),
          MpGrid(
            columns: 2,
            children: [
              _Tile(
                onTap: () => isLive ? openSheet<void>(context, (_) => const P1HealthScoreSheet()) : toast(context, 'Health score details'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CustomPaint(
                            painter: _RingPainter(data == null ? 111.6 / (2 * math.pi * 24) : ((_score ?? 0) / 100).clamp(0, 1).toDouble()),
                            child: Center(child: Text(_score == null ? '–' : '${_score!.round()}', style: tx(18, w: w800, tab: true))),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Text(
                            _score == null ? '' : '${_scoreDelta >= 0 ? '+' : ''}$_scoreDelta this week',
                            style: tx(13, w: w700, c: _scoreDelta >= 0 ? MP.green : MP.amber),
                          ),
                        ),
                      ],
                    ),
                    const Gap(10),
                    Text('Health score', style: tx(15, w: w700)),
                    const Gap(2),
                    Text('out of 100', style: tx(13, c: MP.ink2)),
                  ],
                ),
              ),
              _Tile(
                onTap: () => Nav.go(context, 'Patient-Adherence'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 56,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_adherence == null ? '–' : '${_adherence!.round()}%', style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                      ),
                    ),
                    const Gap(10),
                    Text('Adherence', style: tx(15, w: w700)),
                    const Gap(2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_adherenceDoctors ${_adherenceDoctors == 1 ? 'doctor' : 'doctors'}', style: tx(13, w: w600, c: MP.primary)),
                        const Gap(2),
                        const Ico(I.chevronRight, size: 14, color: MP.primary, stroke: 2),
                      ],
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

  // ── AI health summary ─────────────────────────────────────────────────────

  List<String> get _focusItems => _ai == null
      ? (data == null ? const ['Take Metformin after dinner, every day', 'Walk 30 minutes, 5 days a week'] : const [])
      : [for (final f in (_ai!['focusItems'] as List? ?? const [])) '$f'].take(3).toList();

  String get _summaryUpdated {
    final at = F.date(_ai?['generatedAt']);
    if (at == null) return 'Updated today';
    return F.sameDay(at, DateTime.now()) ? 'Updated today' : 'Updated ${F.dayMonth(at)}';
  }

  Widget _summary(BuildContext context) {
    Widget focus(String n, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n, style: tx(15, w: w800, h: 1.45, c: MP.primary)),
            const Gap(10),
            Expanded(child: Text(text, style: tx(15, h: 1.45))),
          ],
        );
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Ico(I.sparkle, size: 20, color: MP.primary),
              const Gap(8),
              Expanded(child: _cardTitle('Health summary')),
              const Gap(12),
              Text(_summaryUpdated, style: tx(13, c: MP.ink3)),
            ],
          ),
          const Gap(14),
          Text(
            _ai?.str('body') ??
                'Your sugar has crept up a little since July (HbA1c 7.2%) and bad cholesterol (LDL) is still high. '
                    'You missed 4 evening doses of Metformin this week. Taking it every evening is the biggest help right now.',
            style: tx(16, h: 1.55),
          ),
          if (_focusItems.isNotEmpty) ...[
          const Gap(14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('FOCUS THIS WEEK', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                const Gap(8),
                for (var i = 0; i < _focusItems.length; i++) ...[
                  if (i > 0) const Gap(8),
                  focus('${i + 1}', _focusItems[i]),
                ],
              ],
            ),
          ),
          ],
          const Gap(14),
          Row(
            children: [
              Expanded(child: Text('From your reports and medicines. Not a diagnosis.', style: tx(13, c: MP.ink3))),
              const Gap(12),
              _TextLink(
                'Read more',
                onTap: () => isLive ? openSheet<void>(context, (_) => const P1HealthSummarySheet()) : toast(context, 'Your health summary'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── What you track ────────────────────────────────────────────────────────

  Widget _tracking(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeading('What you track', 'Customize', () async {
            final saved = await Nav.go<bool>(context, 'Patient-Track');
            if (saved == true && mounted) reload(quiet: true);
          }),
          const Gap(14),
          MpGrid(
            columns: 2,
            children: data != null ? _trackTiles(context) : [
              _TrackTile(
                label: 'Fasting sugar',
                value: '142',
                unit: ' mg/dL',
                points: '2,10 22,15 43,19 64,17 85,13 106,20 128,16',
                note: 'Above target',
                noteColor: MP.amber,
                onTap: () => toast(context, 'Fasting sugar trend is coming soon'),
              ),
              _TrackTile(
                label: 'Blood pressure',
                value: '128/82',
                points: '2,18 22,16 43,20 64,15 85,17 106,14 128,16',
                note: 'Normal',
                noteColor: MP.green,
                onTap: () => toast(context, 'Blood pressure trend is coming soon'),
              ),
            ],
          ),
          const Gap(14),
          Tap(
            onTap: () async {
              if (!isLive) return toast(context, 'Smartwatch and ring sync');
              final phoneOk = await PhoneSteps.allowed;
              if (!context.mounted) return;
              final run = _synced == null || !phoneOk ? DeviceSync.connect(context) : DeviceSync.sync(context, force: true);
              final ok = await run;
              if (ok && mounted) reload(quiet: true);
            },
            radius: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  const Ico(_watch, size: 20, color: MP.ink2),
                  const Gap(12),
                  Expanded(child: Text(_synced == null ? 'Smartwatch and ring sync' : (_syncEmpty ? 'Synced ${F.ago(_synced!)} · no new readings from a watch' : 'Synced ${F.ago(_synced!)} · tap to sync now'), style: tx(14, c: MP.ink2))),
                  const Gap(12),
                  if (!isLive) const MpBadge.grey('Coming soon') else if (_synced == null) const MpBadge.blue('Connect') else if (_syncEmpty) const Ico(I.chevronRight, size: 18, color: MP.ink3) else const Ico(I.check, size: 18, color: MP.green, stroke: 2.2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── From your doctor ──────────────────────────────────────────────────────

  String get _rxTitle {
    final at = F.date(_rx?['issuedAt']);
    return at == null ? 'Prescription · 29 Sep' : 'Prescription · ${F.dayMonth(at)}';
  }

  String get _rxDetail {
    final rx = _rx;
    if (rx == null) return 'Dr. Arjun Sen · 3 medicines · valid till 29 Oct';
    final n = rx.numOr('medicines').toInt();
    final until = F.date(rx['validUntil']);
    return [
      if (rx.str('doctorName').isNotEmpty) rx.str('doctorName'),
      '$n ${n == 1 ? 'medicine' : 'medicines'}',
      if (until != null) 'valid till ${F.dayMonth(until)}',
    ].join(' · ');
  }

  String get _labTitle {
    final lab = _lab;
    if (lab == null) return 'Diabetes panel · 18 Jul';
    final at = F.date(lab['collectedAt']);
    return at == null ? lab.str('testName') : '${lab.str('testName')} · ${F.dayMonth(at)}';
  }

  bool get _labFlagged => _lab == null || _lab!.numOr('abnormalCount') > 0;

  String get _labBadge {
    final lab = _lab;
    if (lab == null) return '2 values high';
    final n = lab.numOr('abnormalCount').toInt();
    if (n == 0) return 'All normal';
    return '$n ${n == 1 ? 'value' : 'values'} ${lab.str('abnormalDirection', 'high')}';
  }

  String get _labNames => _lab == null ? 'HbA1c, fasting sugar' : [for (final a in (_lab!['abnormal'] as List? ?? const [])) '$a'].join(', ');

  Widget _fromDoctor(BuildContext context) {
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _cardHeading('From your doctor', 'All records', () => Nav.go(context, 'Patient-Records')),
          ),
          if (data == null || _rx != null) _ListRow(
            first: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_rxTitle, style: tx(16, w: w600)),
                      const Gap(3),
                      Text(_rxDetail, style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
                const Gap(12),
                MpIconButton(
                  I.download,
                  label: 'Download prescription',
                  iconSize: 18,
                  color: MP.primary,
                  background: MP.white,
                  borderColor: MP.lineStrong,
                  onTap: () => data == null ? toast(context, 'Prescription downloaded') : _download(context),
                ),
              ],
            ),
          ),
          if (data == null || _lab != null) _ListRow(
            first: data != null && _rx == null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_labTitle, style: tx(16, w: w600)),
                      const Gap(4),
                      Row(
                        children: [
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(color: _labFlagged ? MP.amberSoft : MP.greenSoft, borderRadius: BorderRadius.circular(999)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [Text(_labBadge, style: tx(12, w: w700, c: _labFlagged ? MP.amber : MP.green))],
                            ),
                          ),
                          const Gap(8),
                          Flexible(child: Text(_labNames, style: tx(13, c: MP.ink2))),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                P1SoftButton(
                  'Explain',
                  icon: I.sparkle,
                  iconStroke: 2,
                  padding: 14,
                  onTap: () => Nav.go(
                    context,
                    'Patient-AskAI',
                    args: _lab == null ? null : {'prefill': 'What does my ${_lab!.str('testName')} report mean?'},
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

// ─────────────────────────────────────────────────────────────────────────────
// Hero carousel: 4 slides, slide 1 shown, the next one peeks 36px.
// Swipe or auto-advance every 6 s.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCarousel extends StatefulWidget {
  final List<P1Slide> slides;
  const _HeroCarousel({required this.slides});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  PageController? _pc;
  double _fraction = 0;
  int _page = 0;
  bool _dragging = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _advance());
  }

  void _advance() {
    final pc = _pc;
    if (!mounted || _dragging || pc == null || !pc.hasClients) return;
    pc.animateToPage(
      (_page + 1) % widget.slides.length,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// One page = slide + 12px gap, leaving a 36px peek of the next slide.
  PageController _controllerFor(double fraction) {
    final current = _pc;
    if (current != null && (fraction - _fraction).abs() < 0.0005) return current;
    _fraction = fraction;
    final next = PageController(viewportFraction: fraction, initialPage: _page);
    if (current != null) WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    return _pc = next;
  }

  /// Scroll position in slides. With padEnds off the last slide is fully in
  /// view at page n − 1/fraction (≈2.89), so that stretch is mapped to n − 1.
  double _position(PageController pc) {
    final n = widget.slides.length;
    var p = pc.hasClients ? (pc.page ?? _page.toDouble()) : _page.toDouble();
    final last = _fraction > 0 ? n - 1 / _fraction : n - 1.0;
    if (p > n - 2 && last > n - 2) p = n - 2 + (p - (n - 2)) / (last - (n - 2));
    return p.clamp(0.0, n - 1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    // One slide: nothing to peek at or swipe to — it lines up with the cards below (20px each
    // side), and no dots.
    if (slides.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(right: 20),
        child: SizedBox(
          height: 212,
          child: P1HeroSlide(
            slide: slides.first,
            imageWidth: 200,
            stops: const [0.42, 0.64, 0.88],
            textMaxWidth: 200,
            background: MP.primary,
            contentOpacity: 1,
            onTap: () => P1.openSlide(context, slides.first),
          ),
        ),
      );
    }
    return Semantics(
      label: 'Highlights, slide ${_page + 1} of ${slides.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 212,
            child: LayoutBuilder(
              builder: (context, c) {
                final pc = _controllerFor((c.maxWidth - 36) / c.maxWidth);
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification && n.dragDetails != null) _dragging = true;
                    if (n is ScrollEndNotification) _dragging = false;
                    return false;
                  },
                  child: PageView.builder(
                    controller: pc,
                    padEnds: false,
                    itemCount: slides.length,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      _schedule();
                    },
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AnimatedBuilder(
                        animation: pc,
                        builder: (context, _) {
                          // As drawn on the home artboard, the peeking slide is #002470
                          // with only its tag; the current one is the full #003399 slide.
                          final t = (1 - (_position(pc) - i).abs()).clamp(0.0, 1.0);
                          return P1HeroSlide(
                            slide: slides[i],
                            imageWidth: 200,
                            stops: const [0.42, 0.64, 0.88],
                            textMaxWidth: 200,
                            background: Color.lerp(MP.primaryDark, MP.primary, t)!,
                            contentOpacity: t,
                            onTap: () => i == _page
                                ? P1.openSlide(context, slides[i])
                                : pc.animateToPage(i, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Gap(12),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? MP.primary : MP.lineStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pieces
// ─────────────────────────────────────────────────────────────────────────────

/// A list row inside a card: 14px top/bottom, 1px #E5E9F0 rule above (not on the first).
class _ListRow extends StatelessWidget {
  final Widget child;
  final bool first;
  final VoidCallback? onTap;
  const _ListRow({required this.child, this.first = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: child,
    );
    return onTap == null ? row : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

/// Title (16/600) + sub (13, #545E72) with a trailing control.
/// Daily goals: steps and exercise minutes (they start again each day).
class _GoalsSheet extends StatefulWidget {
  final int steps;
  final int exercise;
  const _GoalsSheet({required this.steps, required this.exercise});
  @override
  State<_GoalsSheet> createState() => _GoalsSheetState();
}

class _GoalsSheetState extends State<_GoalsSheet> {
  static const _stepOptions = [4000, 6000, 8000, 10000, 12000];
  static const _exOptions = [15, 20, 30, 45, 60];
  late int _steps = widget.steps;
  late int _ex = widget.exercise;
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await runAction(context, () => Api.I.patch('/api/patient/me', {'goals': {'stepsPerDay': _steps, 'exerciseMinPerDay': _ex}}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Goals saved');
    Navigator.of(context).pop(true);
  }

  Widget _stepper(String label, String value, VoidCallback? minus, VoidCallback? plus) => Row(
        children: [
          Expanded(child: Text(label, style: tx(15, w: w600))),
          MpIconButton(I.minus, label: 'Less', onTap: minus, color: minus == null ? MP.ink3 : MP.primary),
          SizedBox(width: 92, child: Center(child: Text(value, style: tx(17, w: w700, tab: true)))),
          MpIconButton(I.plus, label: 'More', onTap: plus, color: plus == null ? MP.ink3 : MP.primary),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Your daily goals',
      subtitle: 'Set what works for you. Each day starts fresh at 0. Ask your doctor if you are unsure.',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VGap(
          gap: 14,
          children: [
            _stepper('Steps', F.count(_steps), _steps <= 1000 ? null : () => setState(() => _steps = (_steps - 500).clamp(1000, 30000)),
                _steps >= 30000 ? null : () => setState(() => _steps = (_steps + 500).clamp(1000, 30000))),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in _stepOptions) MpChip(F.count(s), selected: _steps == s, height: 36, fontSize: 13, onTap: () => setState(() => _steps = s))]),
            const MpDivider(),
            _stepper('Exercise', '$_ex min', _ex <= 5 ? null : () => setState(() => _ex = (_ex - 5).clamp(5, 240)),
                _ex >= 240 ? null : () => setState(() => _ex = (_ex + 5).clamp(5, 240))),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final m in _exOptions) MpChip('$m min', selected: _ex == m, height: 36, fontSize: 13, onTap: () => setState(() => _ex = m))]),
            const Gap(4),
            ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (_, busy, _) => MpButton(busy ? 'Saving…' : 'Save goals', onTap: busy ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final Widget title;
  final String sub;
  final Widget trailing;
  const _LogLine({required this.title, required this.sub, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(style: tx(16, w: w600), child: title),
              const Gap(2),
              Text(sub, style: tx(13, c: MP.ink2)),
            ],
          ),
        ),
        const Gap(12),
        trailing,
      ],
    );
  }
}

/// Green "✓ Taken" pill: 28px, #E7F5EE, 13/700 #076B3C.
class _DoneBadge extends StatelessWidget {
  final String label;
  const _DoneBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Ico(I.check, size: 14, color: MP.green, stroke: 2.5),
          const Gap(4),
          Text(label, style: tx(13, w: w700, c: MP.green)),
        ],
      ),
    );
  }
}

/// Plain text link (14/600 #003399), no extra height.
class _TextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TextLink(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(label, style: tx(14, w: w600, c: MP.primary)),
      ),
    );
  }
}

/// #F7F9FC tile, radius 16, padding 14.
class _Tile extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Tile({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(onTap: onTap, radius: 16, color: MP.bg, padding: const EdgeInsets.all(14), child: child);
  }
}

/// A tracked measure: label, value (+unit), 130×32 sparkline, status note.
class _TrackTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String points;
  final String note;
  final Color noteColor;
  final VoidCallback onTap;
  const _TrackTile({
    required this.label,
    required this.value,
    this.unit,
    required this.points,
    required this.note,
    required this.noteColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Tile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tx(13, c: MP.ink2)),
          const Gap(4),
          Text.rich(
            TextSpan(
              text: value,
              children: [if (unit != null) TextSpan(text: unit, style: tx(12, w: w600, c: MP.ink3))],
            ),
            style: tx(22, w: w800, tab: true),
          ),
          const Gap(4),
          CustomSingleChildLayout(
            delegate: const _SparkLayout(),
            child: Svg(
              '<svg viewBox="0 0 130 32"><polyline points="$points" fill="none" stroke="#003399" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>',
              fit: BoxFit.fill,
            ),
          ),
          const Gap(4),
          Text(note, style: tx(12, w: w700, c: noteColor)),
        ],
      ),
    );
  }
}

/// The sparkline is 130×32 and, as in the design, runs 8px into the tile's
/// right padding; on narrower phones it narrows instead of spilling out.
class _SparkLayout extends SingleChildLayoutDelegate {
  const _SparkLayout();

  @override
  Size getSize(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth, 32));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = constraints.maxWidth.isFinite ? math.min(130.0, constraints.maxWidth + 8) : 130.0;
    return BoxConstraints.tightFor(width: w, height: 32);
  }

  @override
  bool shouldRelayout(_SparkLayout oldDelegate) => false;
}

/// Health score ring: r 24, 6px #E5E9F0 track, #076B3C arc from 12 o'clock.
class _RingPainter extends CustomPainter {
  final double value;
  const _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 24.0;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = MP.line,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = MP.green,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.value != value;
}

/// "Ask MedPin AI" floating button: 56px, radius 16, #003399, strong shadow.
class _AskFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AskFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 16,
      color: MP.primary,
      shadow: MPShadow.buttonStrong,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Ico(I.sparkle, size: 22, color: MP.white),
              const Gap(8),
              Text('Ask MedPin AI', style: tx(16, w: w700, c: MP.white)),
            ],
          ),
        ),
      ),
    );
  }
}

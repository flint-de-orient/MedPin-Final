import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';

// Live-only sheets for batch P1. The design has no screen for these, so they
// reuse the sheet header, inputs, pills and row rules of the P1 sheets.

/// A row inside a P1 sheet: 14px top/bottom, 1px #E5E9F0 rule above (not on the first).
class P1Row extends StatelessWidget {
  final Widget child;
  final bool first;
  final VoidCallback? onTap;
  const P1Row({super.key, required this.child, this.first = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: child,
    );
    return onTap == null ? row : Tap(onTap: onTap!, radius: 0, child: row);
  }
}

/// Sheet frame: P1SheetHeader + sections 18px apart, 20px gutters.
class P1PlainSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const P1PlainSheet({super.key, required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P1SheetHeader(
              title: Text(title, style: tx(20, w: w700, h: 1.25)),
              subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!, style: tx(14, h: 1.45, c: MP.ink2)),
            ),
            for (final c in children) ...[
              const Gap(18),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: c),
            ],
          ],
        ),
      ),
    );
  }
}

/// A home measure: label, unit and how a Vitals row shows it.
class P1Measure {
  final String key;
  final String label;
  final String unit;
  const P1Measure(this.key, this.label, this.unit);

  static const all = {
    'blood_sugar': P1Measure('blood_sugar', 'Blood sugar', 'mg/dL'),
    'blood_pressure': P1Measure('blood_pressure', 'Blood pressure', 'mmHg'),
    'weight': P1Measure('weight', 'Weight', 'kg'),
    'heart_rate': P1Measure('heart_rate', 'Heart rate', 'bpm'),
    'spo2': P1Measure('spo2', 'SpO₂', '%'),
  };

  /// "142 mg/dL" / "128/82 mmHg"; null when the row has no value for it.
  String? valueOf(Map<String, dynamic> v) {
    String n(Object? x) => x is num ? (x % 1 == 0 ? '${x.toInt()}' : x.toStringAsFixed(1)) : '';
    switch (key) {
      case 'blood_sugar':
        return v['bloodSugar'] == null ? null : '${n(v['bloodSugar'])} $unit';
      case 'blood_pressure':
        return v['bpSystolic'] == null ? null : '${n(v['bpSystolic'])}/${n(v['bpDiastolic'])} $unit';
      case 'weight':
        return v['weightKg'] == null ? null : '${n(v['weightKg'])} $unit';
      case 'heart_rate':
        return v['pulse'] == null ? null : '${n(v['pulse'])} $unit';
      default:
        return v['spo2'] == null ? null : '${n(v['spo2'])}$unit';
    }
  }
}

/// Log a home reading (POST /api/patient/readings) and see recent ones
/// (GET /api/patient/readings). Pops true when a reading was saved.
class P1ReadingSheet extends StatefulWidget {
  final String measure;
  const P1ReadingSheet({super.key, required this.measure});

  @override
  State<P1ReadingSheet> createState() => _P1ReadingSheetState();
}

class _P1ReadingSheetState extends State<P1ReadingSheet> with LiveData {
  static const _sugarTypes = [('fasting', 'Fasting'), ('post_meal', 'After a meal'), ('random', 'Random')];
  final _a = TextEditingController();
  final _b = TextEditingController();
  final _c = TextEditingController();
  int _sugarType = 0;
  final _busy = ValueNotifier(false);

  P1Measure get _m => P1Measure.all[widget.measure] ?? P1Measure.all['blood_sugar']!;

  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/readings', query: {'measure': _m.key, 'days': 30});

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _c.dispose();
    _busy.dispose();
    super.dispose();
  }

  num? _num(TextEditingController c) => num.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final a = _num(_a);
    final body = <String, Object?>{};
    switch (_m.key) {
      case 'blood_sugar':
        body.addAll({'bloodSugar': a, 'sugarType': _sugarTypes[_sugarType].$1});
      case 'blood_pressure':
        body.addAll({'bpSystolic': a, 'bpDiastolic': _num(_b), if (_num(_c) != null) 'pulse': _num(_c)});
      case 'weight':
        body['weightKg'] = a;
      case 'heart_rate':
        body['pulse'] = a;
      default:
        body['spo2'] = a;
    }
    if (a == null || (_m.key == 'blood_pressure' && body['bpDiastolic'] == null)) {
      toast(context, 'Enter the reading');
      return;
    }
    final res = await runAction(context, () => Api.I.post('/api/patient/readings', body), busy: _busy);
    if (res == null || !mounted) return;
    final alerted = res is Map && res['alerted'] == true;
    P1.closeWithToast(context, alerted ? 'Saved. This reading is outside your range, your doctor has been told.' : 'Reading saved', true);
  }

  @override
  Widget build(BuildContext context) {
    final rows = (data?.list('items') ?? const <Map<String, dynamic>>[]).reversed.toList();
    final recent = [
      for (final v in rows)
        if (_m.valueOf(v) != null) v,
    ].take(5).toList();
    return P1PlainSheet(
      title: _m.label,
      subtitle: data == null ? 'Add a reading' : 'Last 30 days · ${rows.length} ${rows.length == 1 ? 'reading' : 'readings'}',
      children: [
        if (_m.key == 'blood_sugar')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _sugarTypes.length; i++)
                MpChip(_sugarTypes[i].$2, selected: i == _sugarType, onTap: () => setState(() => _sugarType = i)),
            ],
          ),
        if (_m.key == 'blood_pressure')
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MpInput(label: 'Upper', controller: _a, hint: '120', keyboard: TextInputType.number)),
              const Gap(10),
              Expanded(child: MpInput(label: 'Lower', controller: _b, hint: '80', keyboard: TextInputType.number)),
              const Gap(10),
              Expanded(child: MpInput(label: 'Pulse', controller: _c, hint: '72', keyboard: TextInputType.number)),
            ],
          )
        else
          MpInput(
            label: 'Reading',
            controller: _a,
            hint: 'E.g. ${switch (_m.key) { 'weight' => '68.5', 'spo2' => '98', 'heart_rate' => '72', _ => '110' }}',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            unit: _m.unit,
          ),
        if (recent.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('RECENT', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
              const Gap(4),
              for (var i = 0; i < recent.length; i++)
                P1Row(
                  first: i == 0,
                  child: Row(
                    children: [
                      Expanded(child: Text(_m.valueOf(recent[i])!, style: tx(15, w: w600, tab: true))),
                      const Gap(12),
                      Text(F.date(recent[i]['recordedAt']) == null ? '' : F.when(F.date(recent[i]['recordedAt'])!), style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
            ],
          ),
        ValueListenableBuilder<bool>(
          valueListenable: _busy,
          builder: (_, busy, __) => MpButton(busy ? 'Saving…' : 'Save reading', onTap: _save),
        ),
      ],
    );
  }
}

/// A dose from today's list: Taken / Skip, or undo (POST /api/patient/doses/:id).
/// Pops true when the dose changed.
class P1DoseSheet extends StatelessWidget {
  final Map<String, dynamic> dose;
  const P1DoseSheet({super.key, required this.dose});

  Future<void> _set(BuildContext context, String status, String message) async {
    final res = await runAction(context, () => Api.I.post('/api/patient/doses/${dose['id']}', {'status': status}));
    if (res == null || !context.mounted) return;
    P1.closeWithToast(context, message, true);
  }

  @override
  Widget build(BuildContext context) {
    final at = F.date(dose['at']);
    final status = dose.str('status');
    final done = status == 'taken' || status == 'skipped';
    return P1PlainSheet(
      title: dose.str('title'),
      subtitle: [
        if (at != null) F.time(at),
        if (status == 'missed') 'Missed',
        if (status == 'skipped') 'Skipped',
        if (status == 'taken') 'Taken',
      ].join(' · '),
      children: [
        if (done)
          MpButton('Undo', kind: MpBtn.secondary, onTap: () => _set(context, 'due', 'Marked as not taken'))
        else ...[
          MpButton('Taken', icon: I.check, onTap: () => _set(context, 'taken', '${dose.str('title')} marked as taken')),
          MpButton('Skip this dose', kind: MpBtn.secondary, onTap: () => _set(context, 'skipped', 'Dose skipped')),
        ],
      ],
    );
  }
}

/// The bell: GET /api/notifications; tapping one marks it read and opens its screen.
class P1NotificationsSheet extends StatefulWidget {
  const P1NotificationsSheet({super.key});

  @override
  State<P1NotificationsSheet> createState() => _P1NotificationsSheetState();
}

class _P1NotificationsSheetState extends State<P1NotificationsSheet> with LiveData {
  @override
  Future<Object?> fetch() => Api.I.get('/api/notifications', query: {'limit': 30});

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['readAt'] == null) await runAction(context, () => Api.I.post('/api/notifications/${n['id']}/read'));
    if (!mounted) return;
    // Chat notifications name the clinic's thread screen; the patient's is Patient-DoctorChat.
    final stem = n['screen'] == 'Patient-Thread' ? 'Patient-DoctorChat' : n.str('screen');
    final spec = Nav.spec(stem);
    final nav = Navigator.of(context);
    nav.pop(true);
    if (spec != null && spec.panel == 'patient') Nav.go(nav.context, stem, args: n['params']);
  }

  Future<void> _readAll() async {
    final ok = await runAction(context, () => Api.I.post('/api/notifications/read-all'));
    if (ok != null && mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final items = data?.list('items') ?? const <Map<String, dynamic>>[];
    final unread = data?.numOr('unread').toInt() ?? 0;
    return P1PlainSheet(
      title: 'Notifications',
      subtitle: data == null ? null : (unread == 0 ? 'All caught up' : '$unread new'),
      children: [
        livePlaceholder() ??
            (items.isEmpty
                ? Text('Nothing here yet.', style: tx(15, c: MP.ink2))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        P1Row(
                          first: i == 0,
                          onTap: () => _open(items[i]),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: items[i]['readAt'] == null ? MP.primary : MP.line, shape: BoxShape.circle),
                                ),
                              ),
                              const Gap(10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(items[i].str('title'), style: tx(15, w: w600)),
                                    if (items[i].str('body').isNotEmpty) ...[const Gap(2), Text(items[i].str('body'), style: tx(13, c: MP.ink2))],
                                  ],
                                ),
                              ),
                              const Gap(12),
                              Text(F.date(items[i]['createdAt']) == null ? '' : F.ago(F.date(items[i]['createdAt'])!), style: tx(12, c: MP.ink3)),
                            ],
                          ),
                        ),
                    ],
                  )),
        if (unread > 0) Align(alignment: Alignment.centerLeft, child: P1SoftButton('Mark all as read', onTap: _readAll)),
      ],
    );
  }
}

/// Daily log history: GET /api/patient/logs?date= for one day, with remove.
/// Pops true when something was removed.
class P1LogHistorySheet extends StatefulWidget {
  const P1LogHistorySheet({super.key});

  @override
  State<P1LogHistorySheet> createState() => _P1LogHistorySheetState();
}

class _P1LogHistorySheetState extends State<P1LogHistorySheet> with LiveData {
  int _daysBack = 0;
  bool _changed = false;

  DateTime get _day => DateTime.now().subtract(Duration(days: _daysBack));
  String get _dayParam => '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/logs', query: {'date': _dayParam});

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _title(Map<String, dynamic> l) => switch (l['type']) {
        'meal' => _cap(l.str('mealType', 'meal')),
        'exercise' => '${_cap(l.str('exerciseType', 'exercise'))}${l['durationMin'] == null ? '' : ' · ${l['durationMin']} min'}',
        _ => '${F.count(l.numOr('steps'))} steps',
      };

  Future<void> _delete(Map<String, dynamic> l) async {
    final ok = await runAction(context, () => Api.I.delete('/api/patient/logs/${l['id']}'));
    if (ok == null || !mounted) return;
    _changed = true;
    toast(context, 'Removed from your log');
    reload(quiet: true);
  }

  void _go(int back) {
    setState(() {
      _daysBack = back;
      data = null;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final items = data?.list('items') ?? const <Map<String, dynamic>>[];
    return P1PlainSheet(
      title: 'Your log',
      subtitle: _daysBack == 0 ? 'Today' : _daysBack == 1 ? 'Yesterday' : F.dateLong(_day),
      children: [
        Row(
          children: [
            P1Pill('Earlier day', onTap: () => _go(_daysBack + 1)),
            if (_daysBack > 0) ...[const Gap(8), P1Pill('Next day', onTap: () => _go(_daysBack - 1))],
          ],
        ),
        livePlaceholder() ??
            (items.isEmpty
                ? Text('Nothing logged on this day.', style: tx(15, c: MP.ink2))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        P1Row(
                          first: i == 0,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_title(items[i]), style: tx(16, w: w600)),
                                    const Gap(2),
                                    Text(
                                      [
                                        if (F.date(items[i]['loggedAt']) != null) F.time(F.date(items[i]['loggedAt'])!),
                                        if (items[i].str('note').isNotEmpty) items[i].str('note'),
                                      ].join(' · '),
                                      style: tx(13, c: MP.ink2),
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(12),
                              MpIconButton(I.close, label: 'Remove', iconSize: 18, color: MP.ink2, onTap: () => _delete(items[i])),
                            ],
                          ),
                        ),
                    ],
                  )),
        MpButton('Done', kind: MpBtn.secondary, onTap: () => Navigator.of(context).pop(_changed)),
      ],
    );
  }
}

/// MedPin AI's answer to a Patient-AskAI question (POST /api/patient/ai/ask).
/// Emergencies get the 108 strip; a suggested specialist opens Find a doctor.
class P1AiAnswerSheet extends StatelessWidget {
  final String question;
  final Map<String, dynamic> result;
  const P1AiAnswerSheet({super.key, required this.question, required this.result});

  @override
  Widget build(BuildContext context) {
    final emergency = result['emergency'] == true;
    final specialist = result.str('specialistKey');
    return P1PlainSheet(
      title: 'MedPin AI',
      subtitle: question,
      children: [
        if (emergency)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.redSoft, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(
                style: tx(14, h: 1.45),
                children: [
                  TextSpan(text: 'This may be an emergency.', style: tx(14, w: w700, h: 1.45, c: MP.red)),
                  const TextSpan(text: " Don't wait for a reply. "),
                  P1.link('Call 108', style: tx(14, w: w700, h: 1.45, c: MP.red), onTap: () => P1.dial(context, '108')),
                ],
              ),
            ),
          ),
        Text(result.obj('answer').str('text'), style: tx(16, h: 1.55)),
        if (emergency)
          MpButton('Message your doctor now', onTap: () => P1.closeThen(context, 'Patient-Emergency'))
        else if (specialist.isNotEmpty)
          MpButton('Find a doctor', icon: I.stethoscope, onTap: () => P1.closeThen(context, 'Patient-FindDoctor', args: {'specialty': specialist})),
        Text('MedPin AI gives guidance, not a diagnosis.', style: tx(13, h: 1.45, c: MP.ink3)),
      ],
    );
  }
}

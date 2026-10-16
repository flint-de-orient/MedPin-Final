import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import '../doctor/patient_picker.dart';
import '../../widgets/i18n.dart';

/// "Record vitals" at the front desk (Staff-Today quick action, the desk's
/// patient profile): choose the patient, take BP, pulse, SpO₂, temperature,
/// weight, height and sugar, and save. With a visit here today the reading
/// belongs to that visit — the doctor's queue shows "Vitals done" and the
/// consultation opens with them filled in; without one it goes on the
/// patient's record. The last readings show under each field.
///
/// Live (args {'patientId', 'appointmentId'?}; no patient → the picker):
/// GET /api/patients/:id, GET /api/patients/:id/vitals?days=365,
/// GET /api/appointments?view=today&patientId=, POST /api/patients/:id/vitals
/// (+ POST /api/appointments/:id/status {waiting} when "Mark as arrived").
class StaffVitalsScreen extends StatefulWidget {
  const StaffVitalsScreen({super.key});

  @override
  State<StaffVitalsScreen> createState() => _StaffVitalsScreenState();
}

/// (label, unit, keyboard, sample last reading). Blood pressure is one field
/// ("128/84"), as on Add patient.
const _fields = [
  ('Blood pressure', 'mmHg', TextInputType.datetime, '130/84'),
  ('Pulse', 'bpm', TextInputType.number, '78'),
  ('SpO₂', '%', TextInputType.number, '98'),
  ('Temperature', '°F', TextInputType.numberWithOptions(decimal: true), '98.4'),
  ('Weight', 'kg', TextInputType.numberWithOptions(decimal: true), '68.5'),
  ('Height', 'cm', TextInputType.number, '158'),
  ('Blood sugar', 'mg/dL', TextInputType.number, '142'),
];
const _bp = 0, _pulse = 1, _spo2 = 2, _temp = 3, _weight = 4, _height = 5, _sugar = 6;

/// When the sugar was taken: label → the API's sugarType.
const _sugarTypes = [('Fasting', 'fasting'), ('Random', 'random'), ('After food', 'post_meal')];

/// Visits still to happen or happening (a reading belongs to these).
const _active = ['in_consultation', 'waiting', 'confirmed', 'booked'];

class _StaffVitalsScreenState extends State<StaffVitalsScreen> with LiveData {
  // A form: it doesn't reload itself while being filled in.
  @override
  bool get autoRefresh => false;

  final _ctrls = [for (final _ in _fields) TextEditingController()];
  final _note = TextEditingController();
  int _sugarType = 0;
  bool _arrived = true;
  String? _patientId;
  final _busy = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    for (final c in _ctrls) {
      c.addListener(_onEdit);
    }
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [..._ctrls, _note]) {
      c.dispose();
    }
    _busy.dispose();
    super.dispose();
  }

  static String _num(Object? v) {
    if (v is! num) return '';
    return v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  @override
  Future<Object?> fetch() async {
    final args = Nav.args<Map>(context) ?? const {};
    final apptArg = args['appointmentId']?.toString();
    _patientId ??= args['patientId']?.toString();
    if (_patientId == null && apptArg != null) {
      final a = (await Api.I.get('/api/appointments/$apptArg') as Map).cast<String, dynamic>();
      _patientId = a.str('patientId');
    }
    if (!mounted) throw const ApiException(400, 'NO_PATIENT', 'Choose a patient');
    final id = await patientOrPick(context, _patientId, title: 'Record vitals for…');
    _patientId = id;
    final res = await Future.wait([
      Api.I.get('/api/patients/$id'),
      Api.I.get('/api/patients/$id/vitals', query: {'days': '365'}).catchError((_) => const <Object>[]),
      Api.I.get('/api/appointments', query: {'view': 'today', 'patientId': id}).catchError((_) => const <String, Object>{}),
    ]);
    final summary = (res[0] as Map).cast<String, dynamic>();
    final readings = [for (final x in (res[1] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final today = res[2] is Map ? (res[2] as Map).cast<String, dynamic>().list('items') : const <Map<String, dynamic>>[];
    // Today's visit: the one asked for, else the one with the doctor / arrived / still to come.
    Map<String, dynamic>? visit = today.where((a) => a.str('id') == apptArg).firstOrNull;
    if (visit == null) {
      final open = today.where((a) => _active.contains(a.str('status'))).toList()
        ..sort((a, b) => _active.indexOf(a.str('status')).compareTo(_active.indexOf(b.str('status'))));
      visit = open.firstOrNull;
    }
    // Height rarely changes: start with the one on record.
    final p = summary.obj('patient');
    if (_ctrls[_height].text.isEmpty && p['heightCm'] is num) _ctrls[_height].text = _num(p['heightCm']);
    return {'summary': summary, 'readings': readings, 'visit': visit};
  }

  Map<String, dynamic> get _patient => data?.obj('summary').obj('patient') ?? const {'name': 'Amit Pal', 'age': 42, 'gender': 'male', 'phone': '9831120770'};

  Map<String, dynamic>? get _visit => data == null
      ? const {'status': 'waiting', 'startAt': null, 'token': '04', 'doctor': {'name': 'Dr. Arjun Sen'}}
      : (data!['visit'] is Map ? data!.obj('visit') : null);

  /// The latest reading of field [i] ("130/84", "12 Oct"), or null.
  (String, DateTime?)? _last(int i) {
    if (data == null) return (_fields[i].$4, DateTime.now().subtract(const Duration(days: 9)));
    for (final v in data!.list('readings')) {
      final at = F.date(v['recordedAt']);
      final s = switch (i) {
        _bp => v['bpSystolic'] is num && v['bpDiastolic'] is num ? '${_num(v['bpSystolic'])}/${_num(v['bpDiastolic'])}' : '',
        _pulse => _num(v['pulse']),
        _spo2 => _num(v['spo2']),
        _temp => _num(v['temperatureF']),
        _weight => _num(v['weightKg']),
        _height => _num(v['heightCm']),
        _ => v['bloodSugar'] is num ? '${_num(v['bloodSugar'])} · ${tr(context, switch (v['sugarType']) { 'fasting' => 'Fasting', 'post_meal' => 'After food', _ => 'Random' })}' : '',
      };
      if (s.isNotEmpty) return (s, at);
    }
    return null;
  }

  num? _n(int i) => num.tryParse(_ctrls[i].text.trim().replaceAll(',', '.'));

  double? get _bmi {
    final w = _n(_weight)?.toDouble();
    final h = _n(_height)?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / ((h / 100) * (h / 100));
  }

  static (String, Color, Color) _band(double bmi) {
    if (bmi < 18.5) return ('Underweight', MP.amberSoft, MP.amber);
    if (bmi < 25) return ('Normal', MP.greenSoft, MP.green);
    if (bmi < 30) return ('Overweight', MP.amberSoft, MP.amber);
    return ('Obese', MP.redSoft, MP.red);
  }

  /// First value that isn't a plausible reading, as the message to show.
  String? _problem() {
    final bp = _ctrls[_bp].text.trim();
    if (bp.isNotEmpty && !RegExp(r'^\d{2,3}\s*/\s*\d{2,3}$').hasMatch(bp)) return 'Enter the blood pressure like 120/80';
    const ranges = [
      (_pulse, 20, 250, 'Enter the pulse between 20 and 250 bpm'),
      (_spo2, 50, 100, 'Enter SpO₂ between 50 and 100%'),
      (_temp, 90, 110, 'Enter the temperature in °F, between 90 and 110'),
      (_weight, 1, 300, 'Enter the weight in kg, between 1 and 300'),
      (_height, 30, 250, 'Enter the height in cm, between 30 and 250'),
      (_sugar, 20, 800, 'Enter the sugar in mg/dL, between 20 and 800'),
    ];
    for (final (i, lo, hi, msg) in ranges) {
      if (_ctrls[i].text.trim().isEmpty) continue;
      final v = _n(i);
      if (v == null || v < lo || v > hi) return msg;
    }
    return null;
  }

  Map<String, Object> get _body {
    final bp = RegExp(r'^(\d{2,3})\s*/\s*(\d{2,3})$').firstMatch(_ctrls[_bp].text.trim());
    final note = _note.text.trim();
    return {
      if (bp != null) 'bpSystolic': int.parse(bp.group(1)!),
      if (bp != null) 'bpDiastolic': int.parse(bp.group(2)!),
      if (_n(_pulse) != null) 'pulse': _n(_pulse)!,
      if (_n(_spo2) != null) 'spo2': _n(_spo2)!,
      if (_n(_temp) != null) 'temperatureF': _n(_temp)!,
      if (_n(_weight) != null) 'weightKg': _n(_weight)!,
      if (_n(_height) != null) 'heightCm': _n(_height)!,
      if (_n(_sugar) != null) 'bloodSugar': _n(_sugar)!,
      if (_n(_sugar) != null) 'sugarType': _sugarTypes[_sugarType].$2,
      if (note.isNotEmpty) 'note': note,
    };
  }

  /// Something besides the height already on record was entered.
  bool get _entered {
    final h = _num(_patient['heightCm']);
    return [for (var i = 0; i < _fields.length; i++) if (i != _height || _ctrls[i].text.trim() != h) _ctrls[i].text.trim()].any((s) => s.isNotEmpty);
  }

  bool get _canArrive => const ['booked', 'confirmed'].contains(_visit?.str('status'));

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) return toast(context, problem);
    if (!_entered) return toast(context, 'Enter at least one vital');
    final name = F.firstName(_patient.str('name', 'Patient'));
    if (!isLive) {
      toast(context, 'Vitals saved');
      Nav.back(context);
      return;
    }
    final visit = _visit;
    final arrive = _canArrive && _arrived;
    final ok = await runAction(context, busy: _busy, () async {
      await Api.I.post('/api/patients/$_patientId/vitals', {..._body, if (visit != null) 'appointmentId': visit.str('id')});
      if (arrive) await Api.I.post('/api/appointments/${visit!.str('id')}/status', const {'status': 'waiting'});
      return true;
    });
    if (ok == null || !mounted) return;
    toast(
      context,
      visit == null
          ? 'Vitals saved'
          : arrive
              ? tr(context, 'Vitals saved · #1 checked in').replaceFirst('#1', name)
              : 'Vitals saved · the doctor can see them now',
    );
    Nav.back(context);
  }

  Future<void> _changePatient() async {
    if (!isLive) return;
    final id = await pickPatient(context, title: 'Record vitals for…');
    if (id == null || id == _patientId || !mounted) return;
    setState(() {
      _patientId = id;
      data = null;
      for (final c in [..._ctrls, _note]) {
        c.clear();
      }
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: const MpHeader('Record vitals', subtitle: 'The doctor sees them before the visit'),
      bottom: placeholder != null
          ? null
          : MpBottomBar(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: ValueListenableBuilder<bool>(
                valueListenable: _busy,
                builder: (_, busy, _) => MpButton(busy ? 'Saving…' : 'Save vitals', onTap: busy ? null : _save),
              ),
            ),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            gap: 16,
            children: [_patientCard(), _vitalsCard(), _noteCard()],
          ),
    );
  }

  Widget _patientCard() {
    final p = _patient;
    final visit = _visit;
    final facts = [
      if (p['age'] != null) '${p['age']} yrs',
      if (p.str('gender').isNotEmpty) p.str('gender')[0].toUpperCase() + p.str('gender').substring(1),
      if (p.str('phone').length == 10) '+91 ${p.str('phone').substring(0, 5)} ${p.str('phone').substring(5)}',
    ].join(' · ');
    String visitLine() {
      if (visit == null) return tr(context, 'No visit today · saved to the patient’s record');
      final at = F.date(visit['startAt']);
      final doctor = visit.obj('doctor').str('name');
      final token = visit.str('token');
      return [
        tr(context, "For today's visit"),
        if (at != null) F.time(at),
        if (doctor.isNotEmpty) F.doctorShort(doctor),
        if (token.isNotEmpty) tr(context, 'Token #1').replaceFirst('#1', token),
      ].join(' · ');
    }

    return MpCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: VGap(
        gap: 12,
        children: [
          Row(
            children: [
              MpAvatar(F.initials(p.str('name', 'P')), size: 44, fontSize: 15, photo: p.str('photo').isEmpty ? null : p.str('photo')),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.str('name', 'Patient'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w700)),
                    if (facts.isNotEmpty) ...[
                      const Gap(2),
                      Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink2, tab: true)),
                    ],
                  ],
                ),
              ),
              if (isLive)
                MpHitSlop(
                  child: Tap(
                    onTap: _changePatient,
                    radius: 8,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text('Change', style: tx(14, w: w600, c: MP.primary)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: visit == null ? MP.bg : MP.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Ico(visit == null ? I.file : I.calendar, size: 16, color: visit == null ? MP.ink2 : MP.primary),
                  ),
                  const Gap(8),
                  Expanded(child: Text(visitLine(), style: tx(14, h: 1.4, c: visit == null ? MP.ink2 : MP.ink))),
                ],
              ),
            ),
          ),
          if (_canArrive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mark as arrived', style: tx(15, w: w600)),
                        const Gap(2),
                        Text('Checks them in for this visit', style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  MpSwitch(value: _arrived, label: 'Mark as arrived', onChanged: (v) => setState(() => _arrived = v)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _vitalsCard() {
    final bmi = _bmi;
    final band = bmi == null ? null : _band(bmi);
    Widget field(int i) => _VitalBox(_fields[i], controller: _ctrls[i], last: _last(i));
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Vitals', style: tx(20, w: w700, h: 1.25)),
          const Gap(2),
          Text('Fill in what you measured; leave the rest empty', style: tx(14, c: MP.ink2, h: 1.4)),
          const Gap(16),
          for (var r = 0; r < _fields.length; r += 2) ...[
            if (r > 0) const Gap(16),
            if (r + 1 < _fields.length)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: field(r)), const Gap(12), Expanded(child: field(r + 1))],
              )
            else
              field(r),
          ],
          const Gap(8),
          MpSegmented(
            options: [for (final t in _sugarTypes) t.$1],
            index: _sugarType,
            height: 36,
            fontSize: 14,
            onChanged: (i) => setState(() => _sugarType = i),
          ),
          const Gap(16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BMI', style: tx(16, w: w600)),
                      const Gap(2),
                      Text('Calculated from height and weight', style: tx(13, c: MP.ink3)),
                    ],
                  ),
                ),
                const Gap(12),
                Semantics(liveRegion: true, child: Text(bmi == null ? '–' : bmi.toStringAsFixed(1), style: tx(20, w: w700, tab: true))),
                if (band != null) ...[const Gap(12), MpBadge(band.$1, bg: band.$2, fg: band.$3)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteCard() => MpCard(
    child: MpInput(controller: _note, label: 'Note', labelTrailing: 'optional', hint: 'e.g. Feeling dizzy since morning', maxLines: 2),
  );
}

/// One reading: label, a 56px field with its unit, and the last reading under it.
class _VitalBox extends StatefulWidget {
  final (String, String, TextInputType, String) f;
  final TextEditingController controller;
  final (String, DateTime?)? last;
  const _VitalBox(this.f, {required this.controller, this.last});

  @override
  State<_VitalBox> createState() => _VitalBoxState();
}

class _VitalBoxState extends State<_VitalBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, unit, keyboard, _) = widget.f;
    final on = _focus.hasFocus;
    final last = widget.last;
    final at = last?.$2;
    final when = at == null ? '' : (F.sameDay(at, DateTime.now()) ? F.time(at) : F.dayMonth(at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: tx(14, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        const Gap(8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: MP.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? MP.primary : MP.lineStrong),
            boxShadow: on ? MPShadow.focusRing : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: MpFieldArea(
                  child: Semantics(
                    label: label,
                    child: TextField(
                      textAlignVertical: TextAlignVertical.center,
                      controller: widget.controller,
                      focusNode: _focus,
                      keyboardType: keyboard,
                      textInputAction: TextInputAction.next,
                      style: tx(16, tab: true),
                      cursorColor: MP.primary,
                      decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                    ),
                  ),
                ),
              ),
              const Gap(6),
              Text(unit, style: tx(13, c: MP.ink3)),
            ],
          ),
        ),
        if (last != null) ...[
          const Gap(4),
          Text(
            [tr(context, 'Last #1').replaceFirst('#1', last.$1), if (when.isNotEmpty) when].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tx(12, c: MP.ink3, tab: true),
          ),
        ],
      ],
    );
  }
}

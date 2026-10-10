import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';
import 'patient_picker.dart';

/// Design: Consult-Vitals.dc.html — "Consult 1 · Vitals".
/// Live: args {'consultationId'} → GET /api/consultations/:id, saved with
/// POST /api/consultations/:id/vitals + PATCH (complaint, print switch); or
/// {'patientId'} / {'appointmentId'} → POST /api/patients/:id/vitals. Values
/// are prefilled from this visit's vitals, else the latest reading.
class ConsultVitalsScreen extends StatefulWidget {
  const ConsultVitalsScreen({super.key});

  @override
  State<ConsultVitalsScreen> createState() => _ConsultVitalsScreenState();
}

class _ConsultVitalsScreenState extends State<ConsultVitalsScreen> with LiveData {
  /// Field id → API key.
  static const _keys = {
    'v-sys': 'bpSystolic',
    'v-dia': 'bpDiastolic',
    'v-pulse': 'pulse',
    'v-spo2': 'spo2',
    'v-temp': 'temperatureF',
    'v-wt': 'weightKg',
    'v-ht': 'heightCm',
    'v-fbs': 'bloodSugar',
  };

  final _complaint = TextEditingController(
    text: 'Chest tightness since morning with mild sweating. Tired for about two weeks.',
  );
  Map<String, String> _initial = const {};
  String? _consultationId;
  String? _patientId;
  String? _appointmentId;
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _complaint.dispose();
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
    _consultationId = args['consultationId'] as String?;
    _appointmentId = args['appointmentId'] as String?;
    _patientId = args['patientId'] as String?;
    Map<String, dynamic> summary;
    Map<String, dynamic>? consultation;
    Map<String, dynamic>? vitals;
    if (_consultationId != null) {
      final c = (await Api.I.get('/api/consultations/$_consultationId') as Map).cast<String, dynamic>();
      consultation = c.obj('consultation');
      summary = c.obj('summary');
      if (c['vitals'] is Map) vitals = c.obj('vitals');
      _patientId = consultation.str('patientId');
    } else {
      if (_patientId == null && _appointmentId != null) {
        final a = (await Api.I.get('/api/appointments/$_appointmentId') as Map).cast<String, dynamic>();
        _patientId = a.str('patientId');
      }
      if (!mounted) throw const ApiException(400, 'NO_PATIENT', 'Choose a patient');
      _patientId = await patientOrPick(context, _patientId, title: 'Record vitals for…');
      summary = (await Api.I.get('/api/patients/$_patientId') as Map).cast<String, dynamic>();
    }
    vitals ??= summary['latestVitals'] is Map ? summary.obj('latestVitals') : null;
    final p = summary.obj('patient');
    final v = vitals ?? const <String, dynamic>{};
    final values = {
      for (final e in _keys.entries) e.key: _num(v[e.value]),
    };
    if (values['v-wt']!.isEmpty) values['v-wt'] = _num(p['weightKg']);
    if (values['v-ht']!.isEmpty) values['v-ht'] = _num(p['heightCm']);
    if (v['sugarType'] != null && v['sugarType'] != 'fasting') values['v-fbs'] = '';
    if (data == null) {
      _values
        ..clear()
        ..addAll(values);
      _initial = Map.of(values);
      _complaint.text = consultation?.str('chiefComplaint') ?? '';
      _onPrescription = consultation?['printVitalsOnRx'] != false;
    }
    return {'summary': summary, 'consultation': consultation, 'vitals': vitals};
  }

  /// 'Recorded at the front desk, 8:52 AM'.
  String get _recorded {
    final d = data;
    if (d == null) return 'Recorded at the front desk, 8:52 AM';
    final v = d['vitals'] is Map ? d.obj('vitals') : null;
    final at = F.date(v?['recordedAt']);
    if (v == null || at == null) return 'Not recorded yet for this visit';
    final when = F.sameDay(at, DateTime.now()) ? F.time(at) : '${F.dayMonth(at)}, ${F.time(at)}';
    return switch (v.str('recordedByRole')) {
      'front_desk' => 'Recorded at the front desk, $when',
      'patient' => 'Home reading by the patient, $when',
      _ => v.str('source') == 'home' ? 'Home reading, $when' : 'Recorded in the clinic, $when',
    };
  }

  Map<String, Object> get _vitalsBody {
    final out = <String, Object>{};
    for (final e in _keys.entries) {
      final n = num.tryParse((_values[e.key] ?? '').trim());
      if (n != null) out[e.value] = n;
    }
    if (out.containsKey('bloodSugar')) out['sugarType'] = 'fasting';
    return out;
  }

  Future<void> _next() async {
    if (!isLive) {
      Nav.go(context, 'Consult-Diagnosis');
      return;
    }
    final d = data;
    if (d == null) return;
    final body = _vitalsBody;
    final linked = d['vitals'] is Map && (d.obj('vitals')['consultationId'] != null || d.obj('vitals')['appointmentId'] != null);
    final changed = _keys.keys.any((k) => (_values[k] ?? '').trim() != (_initial[k] ?? '').trim());
    final post = body.isNotEmpty && (changed || !linked);
    final isDoctor = Session.I.role == 'doctor';
    final id = await runAction(context, busy: _busy, () async {
      var cid = _consultationId;
      if (cid == null) {
        if (post) {
          await Api.I.post('/api/patients/$_patientId/vitals', {...body, if (_appointmentId != null) 'appointmentId': _appointmentId!});
        }
        if (!isDoctor) return '';
        final c = (await Api.I.post('/api/consultations', {
          if (_appointmentId != null) 'appointmentId': _appointmentId else 'patientId': _patientId,
        }) as Map).cast<String, dynamic>();
        cid = c.str('id');
      } else if (post) {
        await Api.I.post('/api/consultations/$cid/vitals', body);
      }
      await Api.I.patch('/api/consultations/$cid', {
        'chiefComplaint': _complaint.text.trim(),
        'printVitalsOnRx': _onPrescription,
      });
      return cid;
    });
    if (id == null || !mounted) return;
    if (id.isEmpty) {
      toast(context, 'Vitals saved');
      Nav.back(context);
      return;
    }
    _consultationId = id;
    _initial = Map.of(_values);
    Nav.go(context, 'Consult-Diagnosis', args: {'consultationId': id});
  }
  /// id, label, value, unit — renderVals().fields.
  static const _fields = [
    ('v-sys', 'BP systolic', '128', 'mmHg'),
    ('v-dia', 'BP diastolic', '82', 'mmHg'),
    ('v-pulse', 'Pulse', '78', 'bpm'),
    ('v-spo2', 'SpO2', '98', '%'),
    ('v-temp', 'Temperature', '98.4', '°F'),
    ('v-wt', 'Weight', '68.5', 'kg'),
    ('v-ht', 'Height', '158', 'cm'),
    ('v-fbs', 'Fasting sugar', '142', 'mg/dL'),
  ];

  final _values = {for (final f in _fields) f.$1: f.$3};
  bool _onPrescription = true;

  /// BMI from the weight (kg) and height (cm) fields — 27.4 for the design values.
  double? get _bmi {
    final w = double.tryParse(_values['v-wt']!.trim());
    final h = double.tryParse(_values['v-ht']!.trim());
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    final m = h / 100;
    return w / (m * m);
  }

  static (String, Color, Color) _band(double bmi) {
    if (bmi < 18.5) return ('Underweight', MP.amberSoft, MP.amber);
    if (bmi < 25) return ('Normal', MP.greenSoft, MP.green);
    if (bmi < 30) return ('Overweight', MP.amberSoft, MP.amber);
    return ('Obese', MP.redSoft, MP.red);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: const MpHeader('Consultation'),
      body: placeholder ?? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D7ConsultTop(step: 0, summary: data?.obj('summary')),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            gap: 16,
            children: [_vitalsCard(), _complaintCard()],
          ),
        ],
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: MpButton('Next: Diagnosis', onTap: _next),
      ),
    );
  }

  Widget _vitalsCard() {
    final bmi = _bmi;
    final band = bmi == null ? null : _band(bmi);
    final rows = <Widget>[];
    for (var i = 0; i < _fields.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 16));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(_fields[i])),
            const SizedBox(width: 12),
            Expanded(child: _field(_fields[i + 1])),
          ],
        ),
      );
    }
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vitals', style: tx(20, w: w700, h: 1.25)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Ico(I.check, size: 16, color: MP.green, stroke: 2.25),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_recorded, style: tx(14, c: MP.ink2, h: 1.45))),
                ],
              ),
            ],
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          // BMI
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
                      const SizedBox(height: 2),
                      Text('Calculated from height and weight', style: tx(13, c: MP.ink3)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(bmi == null ? '–' : bmi.toStringAsFixed(1), style: tx(20, w: w700, tab: true)),
                ),
                if (band != null) ...[const SizedBox(width: 12), MpBadge(band.$1, bg: band.$2, fg: band.$3)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field((String, String, String, String) f) {
    return D7Labeled(
      f.$2,
      child: D7Field(
        value: _values[f.$1] ?? f.$3,
        tab: true,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        action: TextInputAction.next,
        padding: const EdgeInsets.only(left: 16, right: 64),
        onChanged: (v) => setState(() => _values[f.$1] = v),
        overlays: [Positioned(right: 16, top: 18, child: IgnorePointer(child: Text(f.$4, style: tx(14, c: MP.ink3))))],
      ),
    );
  }

  Widget _complaintCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          const D7Title('Chief complaint'),
          D7Field(
            controller: _complaint,
            hint: data == null ? null : 'What brings the patient in today?',
            lines: 3,
            height: 104,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          D7Ruled(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Show on prescription', style: tx(16, w: w600)),
                      const SizedBox(height: 2),
                      Text('Vitals and complaint print on the PDF', style: tx(14, c: MP.ink2, h: 1.45)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  label: 'Show on prescription',
                  child: MpSwitch(value: _onPrescription, onChanged: (v) => setState(() => _onPrescription = v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

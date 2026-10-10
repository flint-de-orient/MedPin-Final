import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/voice.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-Blank.dc.html — "Consultation · fresh start, no records".
/// Live: the same draft as Consult-Page (args {'consultationId'} or
/// {'appointmentId'} / {'patientId'}, plus 'justAdded' from Consult-QuickAdd).
/// Vitals typed here are recorded with POST /api/consultations/:id/vitals when
/// the draft is saved or the prescription generated.
class ConsultBlankScreen extends StatefulWidget {
  const ConsultBlankScreen({super.key});

  @override
  State<ConsultBlankScreen> createState() => _ConsultBlankScreenState();
}

class _ConsultBlankScreenState extends State<ConsultBlankScreen> with LiveData, D5Draft {
  // (label, placeholder, unit); BMI is worked out from weight and height.
  static const _fields = [
    ('Blood pressure', '120/80', 'mmHg'),
    ('Pulse', '72', 'bpm'),
    ('SpO₂', '98', '%'),
    ('Temperature', '98.6', '°F'),
    ('Weight', '0.0', 'kg'),
    ('Height', '000', 'cm'),
    ('Blood sugar', '000', 'mg/dL'),
    ('BMI', 'Auto', ''),
  ];
  static const _weight = 4, _height = 5, _bmi = 7;

  static const _later = [
    ('3', 'Medications'),
    ('4', 'Lab tests'),
    ('5', 'Advice & instructions'),
    ('6', 'Validity & follow-up'),
  ];

  final _vitals = [for (var i = 0; i < _fields.length; i++) TextEditingController()];
  final _cc = TextEditingController();
  final _dxCtrl = TextEditingController();
  final _medCtrl = TextEditingController();
  final _labCtrl = TextEditingController();
  final _advCtrl = TextEditingController();

  final _allergies = <String>[];
  final _dx = <String>[];
  final _meds = <D5Med>[];
  final _labs = <String, bool>{};
  final _open = <int>{};
  int _sugar = 1;
  bool _hasComplaint = false;

  // Live: the draft's records behind the lists above (same order).
  final _dxItems = <Map<String, dynamic>>[];
  final _medItems = <Map<String, dynamic>>[];
  Map<String, dynamic>? _validity;
  Map<String, dynamic>? _followUp;
  bool _applying = false;

  /// The vitals last recorded from this screen (so they are sent once).
  Map<String, dynamic>? _savedVitals;

  @override
  void initState() {
    super.initState();
    _vitals[_weight].addListener(_updateBmi);
    _vitals[_height].addListener(_updateBmi);
    _cc.addListener(_complaintChanged);
    _advCtrl.addListener(() {
      if (!_applying) save({'advice': _adviceJson});
    });
  }

  @override
  void dispose() {
    for (final c in _vitals) {
      c.dispose();
    }
    _cc.dispose();
    _dxCtrl.dispose();
    _medCtrl.dispose();
    _labCtrl.dispose();
    _advCtrl.dispose();
    super.dispose();
  }

  // Live data ----------------------------------------------------------------

  @override
  Future<Object?> fetch() => loadDraft();

  @override
  void draftLoaded() {
    final c = consult;
    _allergies
      ..clear()
      ..addAll(summary.list('allergies').map((a) => a.str('allergen')));
    _dx.clear();
    _dxItems.clear();
    for (final d in c.list('diagnoses')) {
      _dx.add(d.str('name'));
      _dxItems.add(d);
    }
    _medItems
      ..clear()
      ..addAll(c.list('medications').map(D5Live.item));
    _buildMeds();
    _labs.clear();
    for (final t in c.list('labOrders')) {
      _labs[t.str('testName')] = t['selected'] != false;
    }
    _validity = c.obj('validity');
    _followUp = c.obj('followUp');
    _applying = true;
    if (_cc.text != c.str('chiefComplaint')) _cc.text = c.str('chiefComplaint');
    if (_advCtrl.text != c.obj('advice').str('freeText')) _advCtrl.text = c.obj('advice').str('freeText');
    _applying = false;
    _hasComplaint = _cc.text.trim().isNotEmpty;
    final v = vitals;
    if (v != null && _savedVitals == null) {
      String n(Object? x) => x is num ? D5Live.number(x) : '';
      _vitals[0].text = v['bpSystolic'] is num && v['bpDiastolic'] is num ? '${n(v['bpSystolic'])}/${n(v['bpDiastolic'])}' : '';
      _vitals[1].text = n(v['pulse']);
      _vitals[2].text = n(v['spo2']);
      _vitals[3].text = n(v['temperatureF']);
      _vitals[_weight].text = n(v['weightKg']);
      _vitals[_height].text = n(v['heightCm']);
      _vitals[6].text = n(v['bloodSugar']);
      _sugar = v['sugarType'] == 'fasting' ? 0 : 1;
      _savedVitals = _vitalsJson();
    }
  }

  void _buildMeds() {
    _meds
      ..clear()
      ..addAll([for (var i = 0; i < _medItems.length; i++) D5Live.med(_medItems[i], warningsAt(i))]);
  }

  @override
  void draftSaved(Set<String> fields) {
    if (fields.contains('medications') && !pendingHas('medications')) {
      _medItems
        ..clear()
        ..addAll(consult.list('medications').map(D5Live.item));
      _buildMeds();
    }
  }

  List<Map<String, dynamic>> get _labJson => [
    for (final e in _labs.entries) {'testName': e.key, 'source': 'typed', 'selected': e.value},
  ];

  Map<String, dynamic> get _adviceJson => {'items': consult.obj('advice').list('items'), 'freeText': _advCtrl.text.trim()};

  @override
  Map<String, dynamic> draftFields() => {
    'chiefComplaint': _cc.text.trim(),
    'diagnoses': _dxItems,
    'medications': _medItems,
    'labOrders': _labJson,
    'advice': _adviceJson,
    if (_validity != null) 'validity': _validity,
    if (_followUp != null) 'followUp': _followUp,
  };

  /// The typed vitals as the API takes them; null when the BP is malformed.
  Map<String, dynamic>? _vitalsJson() {
    num? n(int i) => num.tryParse(_vitals[i].text.trim());
    final bp = _vitals[0].text.trim();
    final m = RegExp(r'^(\d{2,3})\s*/\s*(\d{2,3})$').firstMatch(bp);
    if (bp.isNotEmpty && m == null) return null;
    return {
      if (m != null) 'bpSystolic': int.parse(m.group(1)!),
      if (m != null) 'bpDiastolic': int.parse(m.group(2)!),
      if (n(1) != null) 'pulse': n(1),
      if (n(2) != null) 'spo2': n(2),
      if (n(3) != null) 'temperatureF': n(3),
      if (n(_weight) != null) 'weightKg': n(_weight),
      if (n(_height) != null) 'heightCm': n(_height),
      if (n(6) != null) 'bloodSugar': n(6),
      if (n(6) != null) 'sugarType': _sugar == 0 ? 'fasting' : 'random',
    };
  }

  /// Records the typed vitals (once per change) before saving.
  @override
  Future<bool> beforeSave() async {
    final v = _vitalsJson();
    if (v == null) {
      toast(context, 'Enter the blood pressure like 120/80');
      return false;
    }
    if (v.isEmpty || _sameVitals(v, _savedVitals)) return true;
    final res = await runAction(context, () => Api.I.post('/api/consultations/$consultId/vitals', v));
    if (res == null) return false;
    _savedVitals = v;
    return true;
  }

  bool _sameVitals(Map<String, dynamic> a, Map<String, dynamic>? b) =>
      b != null && a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  // Actions ------------------------------------------------------------------

  void _updateBmi() {
    final w = double.tryParse(_vitals[_weight].text.trim());
    final h = double.tryParse(_vitals[_height].text.trim());
    final bmi = (w != null && h != null && w > 0 && h > 0) ? (w / ((h / 100) * (h / 100))).toStringAsFixed(1) : '';
    if (_vitals[_bmi].text != bmi) _vitals[_bmi].text = bmi;
  }

  void _complaintChanged() {
    final has = _cc.text.trim().isNotEmpty;
    if (has != _hasComplaint) setState(() => _hasComplaint = has);
    if (!_applying) save({'chiefComplaint': _cc.text.trim()});
  }

  /// Speak-to-type into a field; for list fields (diagnosis, tests) the words are added at once.
  Future<void> _listen(TextEditingController c, {String title = 'Speak now', void Function(String)? submit}) async {
    if (!isLive) return toast(context, 'Listening…');
    final said = await dictateInto(context, c, title: title);
    if (said != null && submit != null && mounted) submit(c.text);
  }

  Future<void> _addAllergies() async {
    final text = await openSheet<String>(context, (_) => const _AllergySheet());
    if (text == null || !mounted) return;
    final items = text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && !_allergies.contains(s));
    if (!isLive) {
      setState(() => _allergies.addAll(items.toSet()));
      return;
    }
    if (items.isEmpty) return;
    final res = await runAction(context, () => Api.I.post('/api/patients/$patientId/allergies', {'allergens': items.join(', ')}));
    if (res is! List || !mounted) return;
    setState(() {
      _allergies
        ..clear()
        ..addAll(D5Live.list(res).map((a) => a.str('allergen')));
    });
    toast(context, res.length == 1 ? 'Allergy saved' : 'Allergies saved');
    // Medicines already added are checked against the new allergies.
    if (_medItems.isNotEmpty) save({'medications': List.of(_medItems)}, delay: Duration.zero);
  }

  void _addDx(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    setState(() {
      _dx.add(name);
      _dxItems.add({'name': name, 'source': 'custom'});
      _dxCtrl.clear();
    });
    if (!isLive) return;
    save({'diagnoses': List.of(_dxItems)});
    _matchIcd(name);
  }

  /// A typed diagnosis that is in the ICD catalog gets its code.
  Future<void> _matchIcd(String name) async {
    try {
      final r = await Api.I.get('/api/catalog/icd', query: {'q': name});
      final hit = D5Live.list(r).where((x) => x.str('name').toLowerCase() == name.toLowerCase()).firstOrNull;
      final i = _dxItems.indexWhere((d) => d['name'] == name && d['source'] == 'custom');
      if (hit == null || i < 0 || !mounted) return;
      setState(() {
        _dx[i] = hit.str('name');
        _dxItems[i] = {'name': hit.str('name'), 'icdCode': hit.str('code'), 'source': 'catalog'};
      });
      save({'diagnoses': List.of(_dxItems)});
    } on ApiException {
      // Keep it as typed.
    }
  }

  void _removeDx(String d) {
    final i = _dx.indexOf(d);
    setState(() {
      _dx.remove(d);
      if (isLive && i >= 0 && i < _dxItems.length) _dxItems.removeAt(i);
    });
    if (isLive) save({'diagnoses': List.of(_dxItems)});
  }

  void _saveMeds() => save({'medications': List.of(_medItems)}, delay: const Duration(milliseconds: 150));

  void _addLine(D5MedResult r) {
    final item = {...r.item!, 'change': D5Live.change(r.item!, currentMedicines)};
    setState(() {
      _medItems.add(item);
      _meds.add(D5Live.med(item));
    });
    _saveMeds();
  }

  Future<void> _addMed(String name) async {
    if (isLive) {
      final r = await Nav.go<D5MedResult>(context, 'Consult-Dosage', args: {'item': D5Live.parse(name), 'consultationId': consultId});
      if (r?.item == null || !mounted) return;
      _addLine(r!);
      return;
    }
    final r = await Nav.go<D5MedResult>(context, 'Consult-Dosage');
    if (r == null || !mounted) return;
    setState(() => _meds.add(D5Med(name, r.dose, '${r.duration} · new')));
  }

  void _typedMed(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    _medCtrl.clear();
    _addMed(name);
  }

  Future<void> _voiceMed() async {
    if (isLive) {
      // Say the medicine (or use the typed line); the voice screen reads dose and timing from it.
      var text = _medCtrl.text.trim();
      if (text.isEmpty) text = await Voice.dictate(context, title: 'Say the medicine', hint: 'e.g. “Metformin 500 twice daily after food”') ?? '';
      if (text.isEmpty || !mounted) return;
      final r = await Nav.go<D5MedResult>(context, 'Consult-Voice', args: {'text': text, 'consultationId': consultId});
      if (r?.item == null || !mounted) return;
      _medCtrl.clear();
      _addLine(r!);
      return;
    }
    final r = await Nav.go<D5MedResult>(context, 'Consult-Voice');
    if (r == null || !mounted) return;
    if (_meds.any((m) => m.name == r.name)) return;
    setState(() => _meds.add(D5Med(r.name, r.dose, '${r.duration} · new')));
  }

  Future<void> _editMed(D5Med m) async {
    final i = _meds.indexOf(m);
    if (isLive) {
      if (i < 0) return;
      final r = await Nav.go<D5MedResult>(
        context,
        'Consult-Dosage',
        args: {'item': _medItems[i], if (m.caution.isNotEmpty) 'caution': m.caution, 'consultationId': consultId},
      );
      if (r?.item == null || !mounted) return;
      setState(() {
        _medItems[i] = {...r!.item!, 'change': _medItems[i]['change'] ?? 'new'};
        _meds[i] = D5Live.med(_medItems[i]);
      });
      _saveMeds();
      return;
    }
    final r = await Nav.go<D5MedResult>(context, 'Consult-Dosage');
    if (r == null || !mounted) return;
    if (i < 0) return;
    setState(() => _meds[i] = D5Med(m.name, r.dose, '${r.duration} · new'));
  }

  void _removeMed(D5Med m) {
    final i = _meds.indexOf(m);
    setState(() {
      _meds.remove(m);
      if (isLive && i >= 0 && i < _medItems.length) _medItems.removeAt(i);
    });
    if (isLive) _saveMeds();
  }

  void _addLab(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    final existing = _labs.keys.where((k) => k.toLowerCase() == name.toLowerCase());
    setState(() {
      _labs[existing.isEmpty ? name : existing.first] = true;
      _labCtrl.clear();
    });
    if (isLive) save({'labOrders': _labJson});
  }

  void _toggleLab(String key, bool on) {
    setState(() => _labs[key] = on);
    if (isLive) save({'labOrders': _labJson});
  }

  void _toggle(int i) => setState(() {
    if (!_open.remove(i)) _open.add(i);
  });

  void _generate() {
    if (isLive) {
      generate();
      return;
    }
    toast(context, 'Prescription generated');
    Nav.go(context, 'Prescriptions');
  }

  Future<void> _preview() async {
    if (!isLive) {
      Nav.go(context, 'Prescriptions');
      return;
    }
    await flush();
    if (!mounted) return;
    Nav.go(
      context,
      'Prescriptions',
      args: {'consultationId': consultId, 'patientId': patientId, if (issuedRxId != null) 'prescriptionId': issuedRxId},
    );
  }

  // Display values -----------------------------------------------------------

  String get _name => isLive ? patient.str('name') : 'Ankit Ghosh';
  String get _first => isLive ? firstName : 'Ankit';

  String get _meta {
    if (!isLive) return 'Male · New patient · added just now';
    return [
      D5Live.gender(patient['gender']),
      if (summary['lastVisitAt'] == null) 'New patient',
      if (justAdded) 'added just now',
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final ready = _hasComplaint && placeholder == null;
    return MpPage(
      header: D5Header(
        'Consultation',
        subtitle: isLive ? (data == null ? 'Loading…' : startedLine) : 'Started 9:41 AM',
        action: 'Save draft',
        onAction: isLive ? (data == null ? null : saveDraft) : () => toast(context, 'Draft saved'),
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Row(
          children: [
            Expanded(
              child: ready ? D5Button.secondary('Preview', onTap: _preview) : const D5Button.disabledOutline('Preview'),
            ),
            const Gap(8),
            Expanded(
              flex: 2,
              child:
                  ready
                      ? D5Button('Generate prescription', onTap: _generate)
                      : const D5Button.disabled('Generate prescription'),
            ),
          ],
        ),
      ),
      body:
          placeholder ??
          VGap(
            // 136px in the design, less the 97px bar that covers it.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 39),
            gap: 16,
            children: [_patient(), _snapshot(), _vitalsCard(), _complaint(), _diagnosis(), _laterSteps()],
          ),
    );
  }

  // Patient ------------------------------------------------------------------

  Widget _patient() => MpCard(
    radius: 20,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    shadow: MPShadow.float,
    child: VGap(
      gap: 10,
      children: [
        Row(
          children: [
            MpAvatar(F.initials(_name), size: 48, fontSize: 16),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name, style: tx(18, w: w700)),
                  const Gap(2),
                  Text(_meta, style: tx(14, c: MP.ink2)),
                ],
              ),
            ),
            const Gap(12),
            D5Link('Change', onTap: () => Nav.go(context, 'Consult-Pick')),
          ],
        ),
        if (_allergies.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [for (final a in _allergies) MpBadge.amber('Allergy: $a')]),
        D5Link('Add allergies', icon: I.plus, onTap: _addAllergies),
      ],
    ),
  );

  // Snapshot (dashed, no records) -----------------------------------------

  Widget _snapshot() => CustomPaint(
    foregroundPainter: const _DashedBorder(radius: 24, color: MP.lineStrong),
    child: Container(
      // 20px padding inside the 1px dashed border.
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(24)),
      child: VGap(
        gap: 12,
        children: [
          Text('Patient snapshot', style: tx(20, w: w700, h: 1.25)),
          Text(
            'No records yet. The AI summary, abnormal test results and current medicines appear here '
            'once $_first shares reports or past prescriptions.',
            style: tx(15, c: MP.ink2, h: 1.5),
          ),
          D5Button.tonal(
            'Send $_first an upload link',
            icon: I.upload,
            iconSize: 18,
            height: 48,
            radius: 12,
            fontSize: 15,
            // No API sends an upload link yet (see the report).
            onTap:
                () => toast(context, isLive ? 'Upload links can\'t be sent yet' : 'Upload link sent to Ankit'),
          ),
        ],
      ),
    ),
  );

  // Vitals -------------------------------------------------------------------

  Widget _vitalsCard() => MpCard(
    child: VGap(
      gap: 14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vitals', style: tx(20, w: w700, h: 1.25)),
            const Gap(2),
            Text('Not recorded at the desk. Enter what you measure.', style: tx(13, c: MP.ink2)),
          ],
        ),
        Column(
          children: [
            for (var r = 0; r < _fields.length; r += 2) ...[
              if (r > 0) const Gap(12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: _vitalField(r)), const Gap(12), Expanded(child: _vitalField(r + 1))],
              ),
            ],
          ],
        ),
        Row(
          children: [
            Flexible(child: Text('Sugar reading is', style: tx(14, c: MP.ink2))),
            const Gap(10),
            D5Segmented(
              options: const ['Fasting', 'Random'],
              index: _sugar,
              onChanged: (i) => setState(() => _sugar = i),
              height: 36,
              radius: 12,
              innerRadius: 9,
              fontSize: 14,
              expand: false,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _vitalField(int i) {
    final f = _fields[i];
    final auto = i == _bmi;
    return VGap(
      gap: 6,
      children: [
        Text(f.$1, style: tx(14, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        D5Field(
          controller: _vitals[i],
          hint: f.$2,
          tab: true,
          padLeft: 14,
          padRight: 56,
          readOnly: auto,
          background: auto ? MP.bg : MP.white,
          keyboard: i == 0 ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
          action: TextInputAction.next,
          overlays: [
            if (f.$3.isNotEmpty)
              Positioned(right: 12, top: 0, bottom: 0, child: Center(child: Text(f.$3, style: tx(13, c: MP.ink3)))),
          ],
        ),
      ],
    );
  }

  // 1 Chief complaint -------------------------------------------------------

  Widget _complaint() => MpCard(
    child: VGap(
      gap: 12,
      children: [
        const D5Step('1', 'Chief complaint'),
        D5TextArea(
          controller: _cc,
          hint: 'What brings $_first in today?',
          speakLabel: 'Dictate chief complaint',
          onSpeak: () => _listen(_cc, title: 'Chief complaint'),
        ),
        Text('Type or speak in English, বাংলা or हिन्दी.', style: tx(13, c: MP.ink3)),
      ],
    ),
  );

  // 2 Diagnosis --------------------------------------------------------------

  Widget _diagnosis() => MpCard(
    child: VGap(
      gap: 12,
      children: [
        const D5Step('2', 'Diagnosis'),
        if (_dx.isNotEmpty)
          VGap(
            gap: 8,
            children: [for (final d in _dx) D5DxRow(name: d, onRemove: () => _removeDx(d))],
          ),
        D5MicField(
          controller: _dxCtrl,
          hint: 'Type or speak a diagnosis',
          micLabel: 'Dictate diagnosis',
          onMic: () => _listen(_dxCtrl, title: 'Diagnosis', submit: _addDx),
          onSubmitted: _addDx,
        ),
        D5IconText(
          icon: I.sparkle,
          size: 14,
          stroke: 2,
          gap: 6,
          text: 'Suggestions appear once you add a chief complaint.',
          style: tx(13, c: MP.ink3),
        ),
      ],
    ),
  );

  // 3–6 Later steps (collapsed) ----------------------------------------------

  Widget _laterSteps() => MpCard(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _later.length; i++) ...[
          _StepRow(
            n: _later[i].$1,
            title: _later[i].$2,
            first: i == 0,
            open: _open.contains(i),
            onTap: () => _toggle(i),
          ),
          Visibility(
            visible: _open.contains(i),
            maintainState: true,
            child: Padding(padding: const EdgeInsets.only(bottom: 16), child: _stepBody(i)),
          ),
        ],
      ],
    ),
  );

  Widget _stepBody(int i) => switch (i) {
    0 => VGap(
      gap: 14,
      children: [
        for (final m in _meds) D5MedCard(med: m, onEdit: () => _editMed(m), onRemove: () => _removeMed(m)),
        D5MicField(
          controller: _medCtrl,
          hint: 'Add medicine or say “Metformin 500 twice daily”',
          fontSize: 15,
          micLabel: 'Add medicine by voice',
          onMic: _voiceMed,
          onSubmitted: _typedMed,
        ),
      ],
    ),
    1 => VGap(
      gap: 14,
      children: [
        D5MicField(
          controller: _labCtrl,
          hint: 'Type or speak a test name',
          micLabel: 'Dictate lab test',
          onMic: () => _listen(_labCtrl, title: 'Lab test', submit: _addLab),
          onSubmitted: _addLab,
        ),
        if (_labs.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final e in _labs.entries) D5Chip.lab(e.key, on: e.value, onTap: () => _toggleLab(e.key, !e.value))],
          ),
      ],
    ),
    2 => D5TextArea(
      controller: _advCtrl,
      hint: 'Add your own advice',
      height: 96,
      bottomPad: 52,
      speakLabel: 'Dictate advice',
      onSpeak: () => _listen(_advCtrl, title: 'Advice'),
    ),
    _ =>
      isLive
          ? D5ValidityFollowUp(
            patient: _first,
            today: DateUtils.dateOnly(DateTime.now()),
            validity: _validity,
            followUpData: _followUp,
            onChanged: (v, f) {
              _validity = v;
              _followUp = f;
              save({'validity': v, 'followUp': f});
            },
          )
          : const D5ValidityFollowUp(patient: 'Ankit'),
  };
}

/// Collapsed step row: 60px, grey number, 17 / 600 #545E72 title, chevron.
class _StepRow extends StatelessWidget {
  final String n;
  final String title;
  final bool first;
  final bool open;
  final VoidCallback onTap;
  const _StepRow({required this.n, required this.title, required this.first, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: open,
    child: Tap(
      onTap: onTap,
      radius: 0,
      child: Container(
        // 60px rows; the 1px top border sits outside (content-box).
        height: first ? 60 : 61,
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: MP.line))),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: MP.fill, shape: BoxShape.circle),
              child: Text(n, style: tx(13, w: w700, c: MP.ink2)),
            ),
            const Gap(10),
            Expanded(child: Text(title, style: tx(17, w: w600, c: MP.ink2))),
            const Gap(10),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Ico(I.chevronDown, size: 18, color: MP.ink3),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 1px dashed rounded border (Chrome draws 1px dashes as 3px on, 2px off).
class _DashedBorder extends CustomPainter {
  final double radius;
  final Color color;
  const _DashedBorder({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 5) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => oldDelegate.radius != radius || oldDelegate.color != color;
}

/// Small sheet for "Add allergies" (no screen for it in the design).
class _AllergySheet extends StatefulWidget {
  const _AllergySheet();

  @override
  State<_AllergySheet> createState() => _AllergySheetState();
}

class _AllergySheetState extends State<_AllergySheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _c.text);

  @override
  Widget build(BuildContext context) => MpSheet(
    title: 'Add allergies',
    subtitle: 'Separate several with commas.',
    showClose: true,
    child: VGap(
      gap: 16,
      children: [
        D5Field(
          controller: _c,
          hint: 'e.g. Penicillin, peanuts',
          autofocus: true,
          action: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        D5Button('Save allergies', onTap: _save),
      ],
    ),
  );
}

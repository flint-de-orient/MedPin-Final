import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/voice.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Consult-Page.dc.html — "Consultation · from patient (auto-filled)".
/// Live: args {'consultationId'} or {'appointmentId'} / {'patientId'} (starts
/// or resumes the draft); GET /api/consultations/:id (+ /checks,
/// /suggestions); every change is saved with PATCH; "Generate prescription"
/// is POST /api/consultations/:id/issue.
class ConsultPageScreen extends StatefulWidget {
  const ConsultPageScreen({super.key});

  @override
  State<ConsultPageScreen> createState() => _ConsultPageScreenState();
}

class _ConsultPageScreenState extends State<ConsultPageScreen> with LiveData, D5Draft {
  static const _sulfaCaution = 'Sulfonylurea. Priya has a sulfa drug allergy; confirm it is safe before prescribing.';

  static const _sampleAbnormal = ['LDL 162 ↑', 'Triglycerides 210 ↑', 'HbA1c 7.2% ↑', 'Vitamin D 14 ↓'];

  static const _sampleCurrent = [
    ('Metformin 500 mg', 'Dr. Arjun Sen', '1-0-1'),
    ('Atorvastatin 10 mg', 'Dr. Rina Mitra', '0-0-1'),
    ('Myo-inositol 2 g', 'Dr. Nandita Gupta · shared', '1-0-1'),
  ];

  static const _sampleVitals = [
    ('BP', '128/82', 'mmHg', MP.ink),
    ('Pulse', '78', 'bpm', MP.ink),
    ('SpO₂', '98', '%', MP.ink),
    ('Sugar (F)', '142', 'mg/dL', MP.amber),
    ('Weight', '68.5', 'kg', MP.ink),
    ('Temp', '98.4', '°F', MP.ink),
  ];

  static const _adviceText = [
    'Take Metformin after food. Don’t skip the evening dose.',
    'Walk 30 minutes, 5 days a week.',
    'Avoid sugar, sweets and refined flour.',
    'Check fasting sugar 3 times a week and log it in the app.',
    'Go to emergency if chest pain returns or gets worse.',
    '15 minutes of morning sunlight daily.',
  ];

  static const _sampleComplaint =
      'Mild chest tightness since morning. Tired for 2 weeks. Missed evening Metformin for 4 days.';

  bool _printVitals = true;

  // (name, ICD code)
  final _dx = <(String, String)>[('Type 2 diabetes, poorly controlled', 'E11.65'), ('Mixed dyslipidaemia', 'E78.2')];

  // (name, why, ICD code used once added)
  final _dxSuggest = <(String, String, String)>[
    ('Atypical chest pain, rule out cardiac', 'Chest tightness today · LDL high', 'R07.89'),
    ('Vitamin D deficiency', 'Vitamin D 14 ng/mL on 18 Jul', 'E55.9'),
    ('PCOS', 'From past diagnoses', 'E28.2'),
  ];

  final _meds = <D5Med>[
    const D5Med('Metformin 500 mg', '1-0-1 · after food', '30 days · continued'),
    const D5Med('Glimepiride 1 mg', '1-0-0 · before breakfast', '30 days · new', _sulfaCaution),
    const D5Med('Vitamin D3 60,000 IU', 'Once a week · Sunday', '8 weeks · new'),
  ];

  // (title, colour, suggestions (name, why))
  final _medGroups = <(String, Color, List<(String, String)>)>[
    (
      'From your past prescriptions',
      MP.ink3,
      [
        ('Metformin 1000 mg', 'Step up from 500 mg · you did this for 6 patients'),
        ('Vildagliptin 50 mg', 'Your usual add-on when HbA1c is above 7%'),
      ],
    ),
    (
      'Suggested for this diagnosis',
      MP.primary,
      [
        ('Atorvastatin 20 mg', 'LDL 162 on 10 mg · replaces current dose'),
        ('Aspirin 75 mg', 'Consider only if a cardiac cause is confirmed'),
      ],
    ),
  ];

  final _labs = <String, bool>{
    'HbA1c': true,
    'Fasting sugar': true,
    'Post-meal sugar': true,
    'Lipid profile': true,
    'ECG': true,
    'Troponin I': false,
    'Kidney function': false,
    'Vitamin D': false,
  };

  final _adviceOn = [true, true, true, false, true, false];

  // Live: the draft's records behind the lists above (same order).
  final _dxItems = <Map<String, dynamic>>[];
  final _dxSuggestItems = <Map<String, dynamic>>[];
  final _medItems = <Map<String, dynamic>>[];
  final _suggestItems = <String, Map<String, dynamic>>{};
  final _labMeta = <String, Map<String, dynamic>>{};
  final _advice = <Map<String, dynamic>>[];
  Map<String, dynamic>? _validity;
  Map<String, dynamic>? _followUp;

  late final _ccCtrl = TextEditingController(text: isLive ? '' : _sampleComplaint);
  final _advCtrl = TextEditingController();
  final _dxCtrl = TextEditingController();
  final _medCtrl = TextEditingController();
  final _labCtrl = TextEditingController();
  late final TapGestureRecognizer _readMore = TapGestureRecognizer()..onTap = _openProfile;

  @override
  void initState() {
    super.initState();
    _ccCtrl.addListener(() {
      if (!_applying) save({'chiefComplaint': _ccCtrl.text.trim()});
    });
    _advCtrl.addListener(() {
      if (!_applying) save({'advice': _adviceJson});
    });
  }

  @override
  void dispose() {
    _ccCtrl.dispose();
    _advCtrl.dispose();
    _dxCtrl.dispose();
    _medCtrl.dispose();
    _labCtrl.dispose();
    _readMore.dispose();
    super.dispose();
  }

  // Live data ----------------------------------------------------------------

  @override
  Future<Object?> fetch() => loadDraft();

  @override
  void draftLoaded() {
    final c = consult;
    _printVitals = c['printVitalsOnRx'] != false;
    _dx.clear();
    _dxItems.clear();
    for (final d in c.list('diagnoses')) {
      _dx.add((d.str('name'), d.str('icdCode')));
      _dxItems.add(d);
    }
    _buildDxSuggestions();
    _medItems
      ..clear()
      ..addAll(c.list('medications').map(D5Live.item));
    _buildMeds();
    _buildMedSuggestions();
    _labs.clear();
    _labMeta.clear();
    for (final t in c.list('labOrders')) {
      _labs[t.str('testName')] = t['selected'] != false;
      _labMeta[t.str('testName')] = t;
    }
    for (final t in suggestions.list('tests')) {
      if (_labs.keys.any((k) => k.toLowerCase() == t.str('testName').toLowerCase())) continue;
      _labs[t.str('testName')] = false;
      _labMeta[t.str('testName')] = t;
    }
    final advice = c.obj('advice');
    _advice
      ..clear()
      ..addAll(advice.list('items'));
    _adviceOn
      ..clear()
      ..addAll(_advice.map((a) => a['included'] != false));
    _validity = c.obj('validity');
    _followUp = c.obj('followUp');
    _setText(_ccCtrl, c.str('chiefComplaint'));
    _setText(_advCtrl, advice.str('freeText'));
  }

  /// Sets a field from the server without saving it back.
  void _setText(TextEditingController c, String text) {
    if (c.text == text) return;
    _applying = true;
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _applying = false;
  }

  bool _applying = false;

  void _buildDxSuggestions() {
    _dxSuggest.clear();
    _dxSuggestItems.clear();
    bool taken(String n) =>
        _dx.any((d) => d.$1.toLowerCase() == n.toLowerCase()) || _dxSuggest.any((d) => d.$1.toLowerCase() == n.toLowerCase());
    final since = F.date(previousVisitAt);
    for (final d in previousDiagnoses) {
      if (d.str('name').isEmpty || taken(d.str('name'))) continue;
      _dxSuggest.add((d.str('name'), since == null ? 'From past diagnoses' : 'From the visit on ${F.dayMonth(since)}', d.str('icdCode')));
      _dxSuggestItems.add({
        'name': d.str('name'),
        if (d['icdCode'] != null) 'icdCode': d['icdCode'],
        'source': 'reused',
        if (previousVisitAt != null) 'reusedFrom': previousVisitAt,
      });
    }
    for (final d in summary.list('conditions')) {
      if (d.str('name').isEmpty || taken(d.str('name'))) continue;
      _dxSuggest.add((d.str('name'), 'On the patient\'s record', d.str('icdCode')));
      _dxSuggestItems.add({'name': d.str('name'), if (d['icdCode'] != null) 'icdCode': d['icdCode'], 'source': 'catalog'});
    }
  }

  void _buildMeds() {
    _meds
      ..clear()
      ..addAll([for (var i = 0; i < _medItems.length; i++) D5Live.med(_medItems[i], warningsAt(i))]);
  }

  void _buildMedSuggestions() {
    bool inDraft(Map<String, dynamic> m) => _medItems.any(
      (d) => d.str('name').toLowerCase() == m.str('name').toLowerCase() && d.str('strength') == m.str('strength'),
    );
    _suggestItems.clear();
    List<(String, String)> rows(List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) why) => [
      for (final m in items)
        if (!inDraft(m) && !_suggestItems.containsKey(D5Live.medName(m)))
          () {
            _suggestItems[D5Live.medName(m)] = m;
            return (D5Live.medName(m), why(m));
          }(),
    ];
    _medGroups
      ..clear()
      ..addAll([
        ('From your past prescriptions', MP.ink3, rows(suggestions.list('fromPastPrescriptions'), D5Live.doseText)),
        ('Suggested for this diagnosis', MP.primary, rows(suggestions.list('forDiagnosis'), (m) => D5Live.reason(m['reason']))),
      ]);
  }

  @override
  void draftSaved(Set<String> fields) {
    if (fields.contains('medications') && !pendingHas('medications')) {
      _medItems
        ..clear()
        ..addAll(consult.list('medications').map(D5Live.item));
      _buildMeds();
    }
    if (fields.contains('diagnoses')) _buildMedSuggestions();
    if (fields.contains('labOrders') || fields.contains('diagnoses')) {
      for (final t in suggestions.list('tests')) {
        if (_labs.keys.any((k) => k.toLowerCase() == t.str('testName').toLowerCase())) continue;
        _labs[t.str('testName')] = false;
        _labMeta[t.str('testName')] = t;
      }
    }
  }

  List<Map<String, dynamic>> get _labJson => [
    for (final e in _labs.entries)
      {
        'testName': e.key,
        if (_labMeta[e.key]?['panel'] != null) 'panel': _labMeta[e.key]!['panel'],
        'source': _labMeta[e.key]?['source'] ?? 'typed',
        'selected': e.value,
      },
  ];

  Map<String, dynamic> get _adviceJson => {
    'items': [
      for (var i = 0; i < _advice.length; i++)
        {
          'text': _advice[i].str('text'),
          'category': _advice[i]['category'] ?? 'general',
          'included': i < _adviceOn.length ? _adviceOn[i] : true,
        },
    ],
    'freeText': _advCtrl.text.trim(),
  };

  @override
  Map<String, dynamic> draftFields() => {
    'chiefComplaint': _ccCtrl.text.trim(),
    'printVitalsOnRx': _printVitals,
    'diagnoses': _dxItems,
    'medications': _medItems,
    'labOrders': _labJson,
    'advice': _adviceJson,
    if (_validity != null) 'validity': _validity,
    if (_followUp != null) 'followUp': _followUp,
  };

  void _saveMeds() => save({'medications': List.of(_medItems)}, delay: const Duration(milliseconds: 150));

  // Actions ------------------------------------------------------------------

  void _openProfile() => Nav.go(context, 'PP-Summary', args: isLive ? {'patientId': patientId} : null);

  /// Speak-to-type into a field; for list fields (diagnosis, tests) the words are added at once.
  Future<void> _listen(TextEditingController c, {String title = 'Speak now', void Function(String)? submit}) async {
    if (!isLive) return toast(context, 'Listening…');
    final said = await dictateInto(context, c, title: title);
    if (said != null && submit != null && mounted) submit(c.text);
  }

  String _cautionFor(String name) => name.startsWith('Glimepiride') ? _sulfaCaution : '';

  void _addDx(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    setState(() {
      _dx.add((name, ''));
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
        _dx[i] = (hit.str('name'), hit.str('code'));
        _dxItems[i] = {'name': hit.str('name'), 'icdCode': hit.str('code'), 'source': 'catalog'};
      });
      save({'diagnoses': List.of(_dxItems)});
    } on ApiException {
      // Keep it as typed.
    }
  }

  void _acceptDx((String, String, String) s) {
    final i = _dxSuggest.indexOf(s);
    setState(() {
      _dxSuggest.remove(s);
      _dx.add((s.$1, s.$3));
      if (isLive && i >= 0) _dxItems.add(_dxSuggestItems.removeAt(i));
    });
    if (isLive) save({'diagnoses': List.of(_dxItems)});
  }

  void _removeDx((String, String) d) {
    final i = _dx.indexOf(d);
    setState(() {
      _dx.remove(d);
      if (isLive && i >= 0 && i < _dxItems.length) _dxItems.removeAt(i);
    });
    if (isLive) save({'diagnoses': List.of(_dxItems)});
  }

  /// Opens the dosage sheet for a live line ([item]) and returns the result.
  Future<D5MedResult?> _dosage(Map<String, dynamic> item, {String? reason, String? caution}) => Nav.go<D5MedResult>(
    context,
    'Consult-Dosage',
    args: {'item': item, if (reason != null) 'reason': reason, if (caution != null) 'caution': caution, 'consultationId': consultId},
  );

  Future<void> _editMed(D5Med m) async {
    if (isLive) {
      final i = _meds.indexOf(m);
      if (i < 0) return;
      final r = await _dosage(_medItems[i], caution: m.caution.isEmpty ? null : m.caution);
      if (r?.item == null || !mounted) return;
      setState(() {
        _medItems[i] = {...r!.item!, 'change': _medItems[i]['change'] ?? 'new'};
        _meds[i] = D5Med(r.name, r.dose, '${r.duration} · ${_medItems[i]['change']}', m.caution);
      });
      _saveMeds();
      return;
    }
    final r = await Nav.go<D5MedResult>(context, 'Consult-Dosage');
    if (r == null || !mounted) return;
    final i = _meds.indexOf(m);
    if (i < 0) return;
    final parts = m.meta.split(' · ');
    final status = parts.length > 1 ? parts.last : 'new';
    setState(() {
      _meds[i] = D5Med(
        m.name.startsWith('Glimepiride') ? r.name : m.name,
        r.dose,
        '${r.duration} · $status',
        m.caution,
      );
    });
  }

  void _removeMed(D5Med m) {
    final i = _meds.indexOf(m);
    setState(() {
      _meds.remove(m);
      if (isLive && i >= 0 && i < _medItems.length) _medItems.removeAt(i);
    });
    if (isLive) {
      _buildMedSuggestions();
      _saveMeds();
    }
  }

  /// Adds a live line after the dosage (or voice) sheet confirmed it.
  void _addLine(D5MedResult r) {
    final item = {...r.item!};
    item['change'] = D5Live.change(item, currentMedicines);
    setState(() {
      _medItems.add(item);
      _meds.add(D5Live.med(item));
      _buildMedSuggestions();
    });
    _saveMeds();
  }

  Future<void> _addMed(String name, {List<(String, String)>? from, (String, String)? item}) async {
    if (isLive) {
      final s = _suggestItems[name];
      final line = s == null ? D5Live.parse(name) : {...D5Live.item(s), 'entrySource': 'suggestion'};
      final r = await _dosage(line, reason: s == null ? null : D5Live.reason(s['reason']));
      if (r?.item == null || !mounted) return;
      _addLine(r!);
      return;
    }
    final r = await Nav.go<D5MedResult>(context, 'Consult-Dosage');
    if (r == null || !mounted) return;
    setState(() {
      from?.remove(item);
      _meds.add(D5Med(name, r.dose, '${r.duration} · new', _cautionFor(name)));
    });
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
    setState(() => _meds.add(D5Med(r.name, r.dose, '${r.duration} · new', _cautionFor(r.name))));
  }

  void _toggleLab(String key, bool on) {
    setState(() => _labs[key] = on);
    if (isLive) save({'labOrders': _labJson});
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

  void _toggleAdvice(int i, bool on) {
    setState(() => _adviceOn[i] = on);
    if (isLive) save({'advice': _adviceJson});
  }

  void _togglePrint(bool on) {
    setState(() => _printVitals = on);
    if (isLive) save({'printVitalsOnRx': on});
  }

  Future<void> _editVitals() async {
    if (!isLive) {
      Nav.go(context, 'Consult-Vitals');
      return;
    }
    await flush();
    if (!mounted) return;
    await Nav.go(context, 'Consult-Vitals', args: {'consultationId': consultId, 'patientId': patientId});
    if (mounted) reload(quiet: true);
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

  void _generate() {
    if (isLive) {
      generate();
      return;
    }
    toast(context, 'Prescription generated');
    Nav.go(context, 'Prescriptions');
  }

  // Display values -----------------------------------------------------------

  String get _patientName => isLive ? patient.str('name') : 'Priya Sharma';

  String get _patientMeta {
    if (!isLive) return '29 F · Token 04 · Follow-up';
    final a = appointment;
    final visit = switch (a?['visitType']) {
      'follow_up' => 'Follow-up',
      'new' => 'New visit',
      'report_review' => 'Report review',
      _ => '',
    };
    return [
      D5Live.ageSex(patient),
      if (a != null && a.str('token').isNotEmpty) 'Token ${a.str('token')}',
      if (visit.isNotEmpty) visit,
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  List<Widget> get _badges {
    if (!isLive) {
      return const [
        MpBadge.amber('Allergy: Sulfa drugs'),
        MpBadge.grey('Type 2 diabetes', weight: w600),
        MpBadge.grey('PCOS', weight: w600),
      ];
    }
    return [
      for (final a in summary.list('allergies')) MpBadge.amber('Allergy: ${a.str('allergen')}'),
      for (final c in summary.list('conditions')) MpBadge.grey(c.str('name'), weight: w600),
    ];
  }

  String? get _aiSummary {
    if (!isLive) {
      return 'Type 2 diabetes with PCOS. HbA1c drifted from 6.8% to 7.2%. LDL high on Atorvastatin. '
          '4 evening Metformin doses missed this week. Reported chest tightness today. ';
    }
    final body = summary.obj('aiSummary').str('body').trim();
    return body.isEmpty ? null : '$body ';
  }

  List<String> get _abnormal => isLive ? D5Live.abnormal(summary.list('abnormalResults')) : _sampleAbnormal;

  List<(String, String, String)> get _current {
    if (!isLive) return _sampleCurrent;
    return [
      for (final m in currentMedicines)
        (
          D5Live.medName(m),
          m.str('prescriber'),
          m['frequency'] == 'weekly' ? 'Weekly' : m['frequency'] == 'as_needed' ? 'As needed' : m.str('pattern'),
        ),
    ];
  }

  /// The visit's vitals, or today's latest reading.
  Map<String, dynamic>? get _liveVitals {
    if (vitals != null) return vitals;
    final v = summary['latestVitals'] is Map ? summary.obj('latestVitals') : null;
    final at = F.date(v?['recordedAt']);
    return at != null && F.sameDay(at, DateTime.now()) ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: D5Header(
        'Consultation',
        subtitle: isLive ? (data == null ? 'Loading…' : startedLine) : 'Started 9:14 AM · draft saved',
        action: 'Save draft',
        onAction: isLive ? (data == null ? null : saveDraft) : () => toast(context, 'Draft saved'),
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Row(
          children: [
            Expanded(child: D5Button.secondary('Preview', onTap: isLive && data == null ? null : _preview)),
            const Gap(8),
            Expanded(
              flex: 2,
              child:
                  isLive && data == null
                      ? const D5Button.disabled('Generate prescription')
                      : D5Button('Generate prescription', onTap: _generate),
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
            children: [
              _patient(),
              _snapshot(),
              _vitalsCard(),
              _complaint(),
              _diagnosis(),
              _medications(),
              _labTests(),
              _adviceCard(),
              MpCard(
                child: VGap(
                  gap: 16,
                  children: [
                    const D5Step('6', 'Validity & follow-up'),
                    isLive
                        ? D5ValidityFollowUp(
                          patient: firstName,
                          today: DateUtils.dateOnly(DateTime.now()),
                          validity: _validity,
                          followUpData: _followUp,
                          onChanged: (v, f) {
                            _validity = v;
                            _followUp = f;
                            save({'validity': v, 'followUp': f});
                          },
                        )
                        : const D5ValidityFollowUp(patient: 'Priya'),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  // Patient ------------------------------------------------------------------

  Widget _patient() {
    final badges = _badges;
    return MpCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shadow: MPShadow.float,
      child: VGap(
        gap: 12,
        children: [
          Row(
            children: [
              MpAvatar(F.initials(_patientName), size: 48, fontSize: 16),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_patientName, style: tx(18, w: w700)),
                    const Gap(2),
                    Text(_patientMeta, style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              D5Link('Profile', onTap: _openProfile),
            ],
          ),
          if (badges.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: badges),
        ],
      ),
    );
  }

  // Snapshot -----------------------------------------------------------------

  Widget _snapshot() {
    final ai = _aiSummary;
    final abnormal = _abnormal;
    final current = _current;
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Patient snapshot', style: tx(20, w: w700, h: 1.25))),
              Text('Auto-filled', style: tx(13, c: MP.ink3)),
            ],
          ),
          if (ai != null)
            VGap(
              gap: 6,
              children: [
                const D5Label('AI summary', color: MP.primary, icon: I.sparkle),
                Text.rich(
                  TextSpan(
                    text: ai,
                    children: [
                      TextSpan(text: 'Read more', style: tx(15, w: w600, c: MP.primary, h: 1.5), recognizer: _readMore),
                    ],
                  ),
                  style: tx(15, h: 1.5),
                ),
              ],
            ),
          if (abnormal.isNotEmpty)
            VGap(
              gap: 8,
              children: [
                const D5Label('Abnormal test results'),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final a in abnormal) _AbnormalPill(a)]),
              ],
            ),
          if (current.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const D5Label('Current medications', bottom: 4),
                for (var i = 0; i < current.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: MP.line))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(current[i].$1, style: tx(15, w: w600)),
                              const Gap(1),
                              Text(current[i].$2, style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        Text(current[i].$3, textAlign: TextAlign.right, style: tx(14, c: MP.ink2, tab: true)),
                      ],
                    ),
                  ),
              ],
            ),
          if (ai == null && abnormal.isEmpty && current.isEmpty) Text('No records yet', style: tx(14, c: MP.ink2)),
        ],
      ),
    );
  }

  // Vitals -------------------------------------------------------------------

  Widget _vitalsCard() {
    final v = isLive ? _liveVitals : null;
    final tiles = isLive ? (v == null ? const <(String, String, String, Color)>[] : D5Live.vitalTiles(v)) : _sampleVitals;
    return MpCard(
      child: VGap(
        gap: 14,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vitals', style: tx(20, w: w700, h: 1.25)),
                    const Gap(2),
                    if (isLive && v == null)
                      Text('Not recorded yet', style: tx(13, c: MP.ink2))
                    else
                      D5IconText(
                        icon: I.check,
                        size: 14,
                        stroke: 2.5,
                        color: MP.green,
                        gap: 6,
                        text: v == null ? 'Recorded at front desk, 8:52 AM' : D5Live.recorded(v, Session.I.user.str('id')),
                        style: tx(13, w: w600, c: MP.green),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: D5Link(isLive && v == null ? 'Add' : 'Edit', onTap: _editVitals),
              ),
            ],
          ),
          if (tiles.isNotEmpty)
            MpGrid(
              columns: 3,
              gap: 8,
              children: [
                for (final t in tiles)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$1, style: tx(12, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const Gap(2),
                        Text(
                          t.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(17, w: w800, c: t.$4, tab: true),
                        ),
                        const Gap(2),
                        Text(t.$3, style: tx(11, c: MP.ink3)),
                      ],
                    ),
                  ),
              ],
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _togglePrint(!_printVitals),
            child: Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  Expanded(child: Text('Print vitals on prescription', style: tx(15))),
                  const Gap(12),
                  MpSwitch(value: _printVitals, onChanged: _togglePrint),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1 Chief complaint -------------------------------------------------------

  Widget _complaint() => MpCard(
    child: VGap(
      gap: 12,
      children: [
        const D5Step('1', 'Chief complaint'),
        D5TextArea(
          controller: _ccCtrl,
          hint: isLive ? 'What brings $firstName in today?' : null,
          speakLabel: 'Dictate chief complaint',
          onSpeak: () => _listen(_ccCtrl, title: 'Chief complaint'),
        ),
        Text('Type or speak in English, বাংলা or हिन्दी.', style: tx(13, c: MP.ink3)),
      ],
    ),
  );

  // 2 Diagnosis --------------------------------------------------------------

  Widget _diagnosis() => MpCard(
    child: VGap(
      gap: 14,
      children: [
        const D5Step('2', 'Diagnosis'),
        if (_dx.isNotEmpty)
          VGap(
            gap: 8,
            children: [for (final d in _dx) D5DxRow(name: d.$1, code: d.$2, onRemove: () => _removeDx(d))],
          ),
        D5MicField(
          controller: _dxCtrl,
          hint: 'Type or speak a diagnosis',
          micLabel: 'Dictate diagnosis',
          onMic: () => _listen(_dxCtrl, title: 'Diagnosis', submit: _addDx),
          onSubmitted: _addDx,
        ),
        if (_dxSuggest.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D5Label('Suggested from complaint and reports', color: MP.primary, icon: I.sparkle, bottom: 4),
              for (var i = 0; i < _dxSuggest.length; i++)
                D5SuggestRow(
                  name: _dxSuggest[i].$1,
                  why: _dxSuggest[i].$2,
                  first: i == 0,
                  onAdd: () => _acceptDx(_dxSuggest[i]),
                ),
            ],
          ),
      ],
    ),
  );

  // 3 Medications ------------------------------------------------------------

  Widget _medications() => MpCard(
    child: VGap(
      gap: 14,
      children: [
        D5Step('3', 'Medications', trailing: '${_meds.length} added'),
        for (final m in _meds) D5MedCard(med: m, onEdit: () => _editMed(m), onRemove: () => _removeMed(m)),
        D5MicField(
          controller: _medCtrl,
          hint: 'Add medicine or say “Metformin 500 twice daily”',
          fontSize: 15,
          micLabel: 'Add medicine by voice',
          onMic: _voiceMed,
          onSubmitted: _typedMed,
        ),
        for (final g in _medGroups)
          if (g.$3.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                D5Label(g.$1, color: g.$2, bottom: 4),
                for (var i = 0; i < g.$3.length; i++)
                  D5SuggestRow(
                    name: g.$3[i].$1,
                    why: g.$3[i].$2,
                    first: i == 0,
                    onAdd: () => _addMed(g.$3[i].$1, from: g.$3, item: g.$3[i]),
                  ),
              ],
            ),
      ],
    ),
  );

  // 4 Lab tests --------------------------------------------------------------

  Widget _labTests() {
    final selected = _labs.values.where((on) => on).length;
    return MpCard(
      child: VGap(
        gap: 14,
        children: [
          D5Step('4', 'Lab tests', trailing: '$selected selected'),
          D5MicField(
            controller: _labCtrl,
            hint: 'Type or speak a test name',
            micLabel: 'Dictate lab test',
            onMic: () => _listen(_labCtrl, title: 'Lab test', submit: _addLab),
            onSubmitted: _addLab,
          ),
          if (!isLive || _labs.isNotEmpty) ...[
            const D5Label('Relevant to this diagnosis', color: MP.primary, icon: I.sparkle),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final e in _labs.entries) D5Chip.lab(e.key, on: e.value, onTap: () => _toggleLab(e.key, !e.value))],
            ),
          ],
          if (!isLive)
            Text('Troponin I and ECG suggested because of today\'s chest tightness.', style: tx(13, c: MP.ink3, h: 1.45)),
        ],
      ),
    );
  }

  // 5 Advice -----------------------------------------------------------------

  Widget _adviceCard() {
    final texts = isLive ? [for (final a in _advice) a.str('text')] : _adviceText;
    return MpCard(
      child: VGap(
        gap: 12,
        children: [
          const D5Step('5', 'Advice & instructions'),
          if (texts.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < texts.length; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleAdvice(i, !_adviceOn[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: MP.line))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: MpCheck(value: _adviceOn[i], onChanged: (v) => _toggleAdvice(i, v)),
                          ),
                          const Gap(12),
                          Expanded(child: Text(texts[i], style: tx(15, h: 1.45))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          D5TextArea(
            controller: _advCtrl,
            hint: 'Add your own advice',
            height: 96,
            bottomPad: 52,
            speakLabel: 'Dictate advice',
            onSpeak: () => _listen(_advCtrl, title: 'Advice'),
          ),
        ],
      ),
    );
  }
}

/// Amber abnormal-result pill: 28px, 13 / 600, tabular figures.
class _AbnormalPill extends StatelessWidget {
  final String text;
  const _AbnormalPill(this.text);

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(999)),
    // A min-size Row keeps the pill as wide as its text (an Align would fill the Wrap).
    child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: tx(13, w: w600, c: MP.amber, tab: true))]),
  );
}

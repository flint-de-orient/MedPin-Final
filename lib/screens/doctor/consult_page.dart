import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Consult-Page.dc.html — "Consultation · from patient (auto-filled)".
class ConsultPageScreen extends StatefulWidget {
  const ConsultPageScreen({super.key});

  @override
  State<ConsultPageScreen> createState() => _ConsultPageScreenState();
}

class _ConsultPageScreenState extends State<ConsultPageScreen> {
  static const _sulfaCaution = 'Sulfonylurea. Priya has a sulfa drug allergy; confirm it is safe before prescribing.';

  static const _abnormal = ['LDL 162 ↑', 'Triglycerides 210 ↑', 'HbA1c 7.2% ↑', 'Vitamin D 14 ↓'];

  static const _current = [
    ('Metformin 500 mg', 'Dr. Arjun Sen', '1-0-1'),
    ('Atorvastatin 10 mg', 'Dr. Rina Mitra', '0-0-1'),
    ('Myo-inositol 2 g', 'Dr. Nandita Gupta · shared', '1-0-1'),
  ];

  static const _vitals = [
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

  final _dxCtrl = TextEditingController();
  final _medCtrl = TextEditingController();
  final _labCtrl = TextEditingController();
  late final TapGestureRecognizer _readMore = TapGestureRecognizer()..onTap = () => Nav.go(context, 'PP-Summary');

  @override
  void dispose() {
    _dxCtrl.dispose();
    _medCtrl.dispose();
    _labCtrl.dispose();
    _readMore.dispose();
    super.dispose();
  }

  void _listen() => toast(context, 'Listening…');

  String _cautionFor(String name) => name.startsWith('Glimepiride') ? _sulfaCaution : '';

  void _addDx(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    setState(() {
      _dx.add((name, ''));
      _dxCtrl.clear();
    });
  }

  void _acceptDx((String, String, String) s) => setState(() {
    _dxSuggest.remove(s);
    _dx.add((s.$1, s.$3));
  });

  Future<void> _editMed(D5Med m) async {
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

  Future<void> _addMed(String name, {List<(String, String)>? from, (String, String)? item}) async {
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
    final r = await Nav.go<D5MedResult>(context, 'Consult-Voice');
    if (r == null || !mounted) return;
    if (_meds.any((m) => m.name == r.name)) return;
    setState(() => _meds.add(D5Med(r.name, r.dose, '${r.duration} · new', _cautionFor(r.name))));
  }

  void _addLab(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    final existing = _labs.keys.where((k) => k.toLowerCase() == name.toLowerCase());
    setState(() {
      _labs[existing.isEmpty ? name : existing.first] = true;
      _labCtrl.clear();
    });
  }

  void _generate() {
    toast(context, 'Prescription generated');
    Nav.go(context, 'Prescriptions');
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: D5Header(
        'Consultation',
        subtitle: 'Started 9:14 AM · draft saved',
        action: 'Save draft',
        onAction: () => toast(context, 'Draft saved'),
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Row(
          children: [
            Expanded(child: D5Button.secondary('Preview', onTap: () => Nav.go(context, 'Prescriptions'))),
            const Gap(8),
            Expanded(flex: 2, child: D5Button('Generate prescription', onTap: _generate)),
          ],
        ),
      ),
      body: VGap(
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
          const MpCard(
            child: VGap(gap: 16, children: [D5Step('6', 'Validity & follow-up'), D5ValidityFollowUp(patient: 'Priya')]),
          ),
        ],
      ),
    );
  }

  // Patient ------------------------------------------------------------------

  Widget _patient() => MpCard(
    radius: 20,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    shadow: MPShadow.float,
    child: VGap(
      gap: 12,
      children: [
        Row(
          children: [
            const MpAvatar('PS', size: 48, fontSize: 16),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Priya Sharma', style: tx(18, w: w700)),
                  const Gap(2),
                  Text('29 F · Token 04 · Follow-up', style: tx(14, c: MP.ink2)),
                ],
              ),
            ),
            const Gap(12),
            D5Link('Profile', onTap: () => Nav.go(context, 'PP-Summary')),
          ],
        ),
        const Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            MpBadge.amber('Allergy: Sulfa drugs'),
            MpBadge.grey('Type 2 diabetes', weight: w600),
            MpBadge.grey('PCOS', weight: w600),
          ],
        ),
      ],
    ),
  );

  // Snapshot -----------------------------------------------------------------

  Widget _snapshot() => MpCard(
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
        VGap(
          gap: 6,
          children: [
            const D5Label('AI summary', color: MP.primary, icon: I.sparkle),
            Text.rich(
              TextSpan(
                text:
                    'Type 2 diabetes with PCOS. HbA1c drifted from 6.8% to 7.2%. LDL high on Atorvastatin. '
                    '4 evening Metformin doses missed this week. Reported chest tightness today. ',
                children: [
                  TextSpan(text: 'Read more', style: tx(15, w: w600, c: MP.primary, h: 1.5), recognizer: _readMore),
                ],
              ),
              style: tx(15, h: 1.5),
            ),
          ],
        ),
        VGap(
          gap: 8,
          children: [
            const D5Label('Abnormal test results'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final a in _abnormal) _AbnormalPill(a)]),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const D5Label('Current medications', bottom: 4),
            for (var i = 0; i < _current.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: MP.line))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_current[i].$1, style: tx(15, w: w600)),
                          const Gap(1),
                          Text(_current[i].$2, style: tx(13, c: MP.ink3)),
                        ],
                      ),
                    ),
                    const Gap(12),
                    Text(_current[i].$3, textAlign: TextAlign.right, style: tx(14, c: MP.ink2, tab: true)),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );

  // Vitals -------------------------------------------------------------------

  Widget _vitalsCard() => MpCard(
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
                  D5IconText(
                    icon: I.check,
                    size: 14,
                    stroke: 2.5,
                    color: MP.green,
                    gap: 6,
                    text: 'Recorded at front desk, 8:52 AM',
                    style: tx(13, w: w600, c: MP.green),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: D5Link('Edit', onTap: () => Nav.go(context, 'Consult-Vitals')),
            ),
          ],
        ),
        MpGrid(
          columns: 3,
          gap: 8,
          children: [
            for (final v in _vitals)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.$1, style: tx(12, c: MP.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const Gap(2),
                    Text(
                      v.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(17, w: w800, c: v.$4, tab: true),
                    ),
                    const Gap(2),
                    Text(v.$3, style: tx(11, c: MP.ink3)),
                  ],
                ),
              ),
          ],
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _printVitals = !_printVitals),
          child: Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
            child: Row(
              children: [
                Expanded(child: Text('Print vitals on prescription', style: tx(15))),
                const Gap(12),
                MpSwitch(value: _printVitals, onChanged: (v) => setState(() => _printVitals = v)),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // 1 Chief complaint -------------------------------------------------------

  Widget _complaint() => MpCard(
    child: VGap(
      gap: 12,
      children: [
        const D5Step('1', 'Chief complaint'),
        D5TextArea(
          value: 'Mild chest tightness since morning. Tired for 2 weeks. Missed evening Metformin for 4 days.',
          speakLabel: 'Dictate chief complaint',
          onSpeak: _listen,
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
            children: [
              for (final d in _dx) D5DxRow(name: d.$1, code: d.$2, onRemove: () => setState(() => _dx.remove(d))),
            ],
          ),
        D5MicField(
          controller: _dxCtrl,
          hint: 'Type or speak a diagnosis',
          micLabel: 'Dictate diagnosis',
          onMic: _listen,
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
        for (final m in _meds)
          D5MedCard(med: m, onEdit: () => _editMed(m), onRemove: () => setState(() => _meds.remove(m))),
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
            onMic: _listen,
            onSubmitted: _addLab,
          ),
          const D5Label('Relevant to this diagnosis', color: MP.primary, icon: I.sparkle),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _labs.entries)
                D5Chip.lab(e.key, on: e.value, onTap: () => setState(() => _labs[e.key] = !e.value)),
            ],
          ),
          Text('Troponin I and ECG suggested because of today\'s chest tightness.', style: tx(13, c: MP.ink3, h: 1.45)),
        ],
      ),
    );
  }

  // 5 Advice -----------------------------------------------------------------

  Widget _adviceCard() => MpCard(
    child: VGap(
      gap: 12,
      children: [
        const D5Step('5', 'Advice & instructions'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _adviceText.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _adviceOn[i] = !_adviceOn[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: MP.line))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: MpCheck(value: _adviceOn[i], onChanged: (v) => setState(() => _adviceOn[i] = v)),
                      ),
                      const Gap(12),
                      Expanded(child: Text(_adviceText[i], style: tx(15, h: 1.45))),
                    ],
                  ),
                ),
              ),
          ],
        ),
        D5TextArea(
          hint: 'Add your own advice',
          height: 96,
          bottomPad: 52,
          speakLabel: 'Dictate advice',
          onSpeak: _listen,
        ),
      ],
    ),
  );
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

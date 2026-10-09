import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Consult-Blank.dc.html — "Consultation · fresh start, no records".
class ConsultBlankScreen extends StatefulWidget {
  const ConsultBlankScreen({super.key});

  @override
  State<ConsultBlankScreen> createState() => _ConsultBlankScreenState();
}

class _ConsultBlankScreenState extends State<ConsultBlankScreen> {
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

  @override
  void initState() {
    super.initState();
    _vitals[_weight].addListener(_updateBmi);
    _vitals[_height].addListener(_updateBmi);
    _cc.addListener(_complaintChanged);
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

  void _updateBmi() {
    final w = double.tryParse(_vitals[_weight].text.trim());
    final h = double.tryParse(_vitals[_height].text.trim());
    final bmi = (w != null && h != null && w > 0 && h > 0) ? (w / ((h / 100) * (h / 100))).toStringAsFixed(1) : '';
    if (_vitals[_bmi].text != bmi) _vitals[_bmi].text = bmi;
  }

  void _complaintChanged() {
    final has = _cc.text.trim().isNotEmpty;
    if (has != _hasComplaint) setState(() => _hasComplaint = has);
  }

  void _listen() => toast(context, 'Listening…');

  Future<void> _addAllergies() async {
    final text = await openSheet<String>(context, (_) => const _AllergySheet());
    if (text == null || !mounted) return;
    final items = text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && !_allergies.contains(s));
    setState(() => _allergies.addAll(items.toSet()));
  }

  void _addDx(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    setState(() {
      _dx.add(name);
      _dxCtrl.clear();
    });
  }

  Future<void> _addMed(String name) async {
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
    final r = await Nav.go<D5MedResult>(context, 'Consult-Voice');
    if (r == null || !mounted) return;
    if (_meds.any((m) => m.name == r.name)) return;
    setState(() => _meds.add(D5Med(r.name, r.dose, '${r.duration} · new')));
  }

  Future<void> _editMed(D5Med m) async {
    final r = await Nav.go<D5MedResult>(context, 'Consult-Dosage');
    if (r == null || !mounted) return;
    final i = _meds.indexOf(m);
    if (i < 0) return;
    setState(() => _meds[i] = D5Med(m.name, r.dose, '${r.duration} · new'));
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

  void _toggle(int i) => setState(() {
    if (!_open.remove(i)) _open.add(i);
  });

  void _generate() {
    toast(context, 'Prescription generated');
    Nav.go(context, 'Prescriptions');
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: D5Header(
        'Consultation',
        subtitle: 'Started 9:41 AM',
        action: 'Save draft',
        onAction: () => toast(context, 'Draft saved'),
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Row(
          children: [
            Expanded(
              child:
                  _hasComplaint
                      ? D5Button.secondary('Preview', onTap: () => Nav.go(context, 'Prescriptions'))
                      : const D5Button.disabledOutline('Preview'),
            ),
            const Gap(8),
            Expanded(
              flex: 2,
              child:
                  _hasComplaint
                      ? D5Button('Generate prescription', onTap: _generate)
                      : const D5Button.disabled('Generate prescription'),
            ),
          ],
        ),
      ),
      body: VGap(
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
            const MpAvatar('AG', size: 48, fontSize: 16),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ankit Ghosh', style: tx(18, w: w700)),
                  const Gap(2),
                  Text('Male · New patient · added just now', style: tx(14, c: MP.ink2)),
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
            'once Ankit shares reports or past prescriptions.',
            style: tx(15, c: MP.ink2, h: 1.5),
          ),
          D5Button.tonal(
            'Send Ankit an upload link',
            icon: I.upload,
            iconSize: 18,
            height: 48,
            radius: 12,
            fontSize: 15,
            onTap: () => toast(context, 'Upload link sent to Ankit'),
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
          hint: 'What brings Ankit in today?',
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
      gap: 12,
      children: [
        const D5Step('2', 'Diagnosis'),
        if (_dx.isNotEmpty)
          VGap(
            gap: 8,
            children: [for (final d in _dx) D5DxRow(name: d, onRemove: () => setState(() => _dx.remove(d)))],
          ),
        D5MicField(
          controller: _dxCtrl,
          hint: 'Type or speak a diagnosis',
          micLabel: 'Dictate diagnosis',
          onMic: _listen,
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
      ],
    ),
    1 => VGap(
      gap: 14,
      children: [
        D5MicField(
          controller: _labCtrl,
          hint: 'Type or speak a test name',
          micLabel: 'Dictate lab test',
          onMic: _listen,
          onSubmitted: _addLab,
        ),
        if (_labs.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _labs.entries)
                D5Chip.lab(e.key, on: e.value, onTap: () => setState(() => _labs[e.key] = !e.value)),
            ],
          ),
      ],
    ),
    2 => D5TextArea(
      controller: _advCtrl,
      hint: 'Add your own advice',
      height: 96,
      bottomPad: 52,
      speakLabel: 'Dictate advice',
      onSpeak: _listen,
    ),
    _ => const D5ValidityFollowUp(patient: 'Ankit'),
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

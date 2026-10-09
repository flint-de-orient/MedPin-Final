import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Records-Review.dc.html — "Records · check and save (multi-test file)".
class RecordsReviewScreen extends StatefulWidget {
  const RecordsReviewScreen({super.key});

  @override
  State<RecordsReviewScreen> createState() => _RecordsReviewScreenState();
}

typedef _Tone = (Color, Color);

const _Tone _high = (MP.amberSoft, MP.amber);
const _Tone _ok = (MP.greenSoft, MP.green);

class _Val {
  final String name;
  final String ref;
  final String value;
  final bool high;
  const _Val(this.name, this.ref, this.value, [this.high = false]);
}

class _Test {
  final String name;
  final String pages;
  final String flag;
  final _Tone tone;
  final String summary;
  final List<_Val> values;
  const _Test(this.name, this.pages, this.flag, this.tone, this.summary, this.values);
}

const _tests = [
  _Test(
    'Lipid profile',
    'Pages 1–2',
    '2 high',
    _high,
    'Bad cholesterol (LDL) and triglycerides are high. Good cholesterol is normal.',
    [
      _Val('LDL cholesterol', 'below 100', '158', true),
      _Val('Triglycerides', 'below 150', '205', true),
      _Val('HDL cholesterol', 'above 40', '46'),
      _Val('Total cholesterol', 'below 200', '196'),
    ],
  ),
  // The design draws these two collapsed (no values listed); the values below
  // match their summaries so "Show values" has something to open.
  _Test('Liver function (LFT)', 'Pages 3–4', 'Normal', _ok, 'All 8 liver values are in the normal range.', [
    _Val('Bilirubin, total', '0.3–1.2', '0.8'),
    _Val('SGOT (AST)', 'below 40', '26'),
    _Val('SGPT (ALT)', 'below 41', '31'),
    _Val('Alkaline phosphatase', '44–147', '92'),
    _Val('GGT', 'below 60', '24'),
    _Val('Total protein', '6.0–8.3', '7.1'),
    _Val('Albumin', '3.5–5.0', '4.4'),
    _Val('Globulin', '2.0–3.5', '2.7'),
  ]),
  _Test(
    'Kidney function (KFT)',
    'Pages 5–6',
    '1 high',
    _high,
    'Creatinine is slightly high (1.3). Your doctor may want to repeat it.',
    [
      _Val('Creatinine', '0.7–1.2', '1.3', true),
      _Val('Urea', '15–40', '34'),
      _Val('Uric acid', '3.5–7.2', '5.9'),
      _Val('eGFR', 'above 60', '64'),
    ],
  ),
];

const _doctors = [
  P2Doctor('Dr. Arjun Sen', 'Suggested · your diabetes doctor', suggested: true, on: true),
  P2Doctor('Dr. Rina Mitra', 'Suggested · follows your cholesterol', suggested: true, on: true),
  P2Doctor('Dr. Nandita Gupta', 'Gynaecology · Apollo Clinic'),
];

class _RecordsReviewScreenState extends State<RecordsReviewScreen> {
  final _selected = [true, true, true];
  final _open = [true, false, false];

  int get _count => _selected.where((s) => s).length;

  void _save() {
    final n = _count;
    if (n == 0) {
      toast(context, 'Pick at least one test to save');
      return;
    }
    toast(context, n == 1 ? '1 record saved' : '$n records saved');
    Nav.back(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = _count;
    final shareTitle =
        n == _tests.length ? 'Share all $n tests with' : (n == 1 ? 'Share 1 test with' : 'Share $n tests with');

    return MpPage(
        header: const P2WhiteHeader('Check your report'),
        bottom: MpBottomBar(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: MpButton(n == 1 ? 'Save 1 record' : 'Save $n records', onTap: _save),
        ),
        // main: padding 16 20 120 — the pinned bar (97px) takes the rest.
        body: VGap(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 23),
          gap: 16,
          children: [
            _FileCard(onRetake: () => Nav.go(context, 'Records-Add')),

            // We found 3 tests…
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.sparkle, size: 18, color: MP.primary)),
                  const Gap(10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: tx(14, h: 1.45),
                        children: [
                          TextSpan(text: 'We found 3 tests in this file.', style: tx(14, w: w700, h: 1.45)),
                          const TextSpan(
                            text: ' Each is saved as its own record, so you can find, track and share it separately.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tests found
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('TESTS FOUND', style: tx(12, w: w700, c: MP.ink3, em: 0.06))),
                      Text('$n SELECTED', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                    ],
                  ),
                ),
                for (var i = 0; i < _tests.length; i++) ...[
                  const Gap(8),
                  _TestCard(
                    _tests[i],
                    selected: _selected[i],
                    open: _open[i],
                    onSelect: () => setState(() => _selected[i] = !_selected[i]),
                    onToggle: () => setState(() => _open[i] = !_open[i]),
                  ),
                ],
                const Gap(8),
                P2Box(
                  onTap: () => p2Missing(context, 'Adding a test by hand'),
                  height: 48,
                  radius: 12,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.plus, size: 16, color: MP.primary, stroke: 2),
                      const Gap(6),
                      Text('Add a test we missed', style: tx(14, w: w600, c: MP.primary)),
                    ],
                  ),
                ),
              ],
            ),

            // Report details
            Container(
              padding: const EdgeInsets.all(20),
              decoration: MPDeco.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Report details', style: tx(18, w: w700)),
                  const Gap(16),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _LabeledField('Date', '30 Sep 2026')),
                      Gap(12),
                      Expanded(child: _LabeledField('Lab', 'Suraksha, Salt Lake')),
                    ],
                  ),
                  const Gap(16),
                  P2ShareDoctors(title: shareTitle, doctors: _doctors),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

/// The uploaded file: two stacked page thumbnails + lab, date, retake link.
class _FileCard extends StatelessWidget {
  final VoidCallback onRetake;
  const _FileCard({required this.onRetake});

  static Widget _bar(double height, double width, Color color) => FractionallySizedBox(
    widthFactor: width,
    child: Container(height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MPDeco.card(radius: 20, shadow: MPShadow.float),
      child: Row(
        children: [
          Semantics(
            label: 'Report preview, 6 pages',
            child: SizedBox(
              width: 76,
              height: 100,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Back page (content-box span: 70×94 + 1px border).
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      width: 72,
                      height: 96,
                      decoration: BoxDecoration(
                        color: MP.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MP.line),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      width: 70,
                      height: 94,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MP.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MP.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _bar(6, 0.6, MP.lineStrong),
                          const Gap(5),
                          _bar(4, 1, MP.line),
                          const Gap(5),
                          _bar(4, 1, MP.line),
                          const Gap(5),
                          _bar(4, 0.8, MP.line),
                          const Gap(5),
                          _bar(4, 1, MP.line),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1 FILE · 6 PAGES', style: tx(12, w: w700, c: MP.ink2, em: 0.06)),
                const Gap(4),
                Text('Suraksha Diagnostics', style: tx(17, w: w700)),
                const Gap(4),
                Text('Collected 30 Sep 2026', style: tx(14, c: MP.ink2)),
                const Gap(4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetake,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Retake or replace', style: tx(14, w: w600, c: MP.primary)),
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

class _TestCard extends StatelessWidget {
  final _Test t;
  final bool selected;
  final bool open;
  final VoidCallback onSelect;
  final VoidCallback onToggle;
  const _TestCard(this.t, {required this.selected, required this.open, required this.onSelect, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MPDeco.card(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: MpCheck(value: selected, onChanged: (_) => onSelect()),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: tx(17, w: w700)),
                      const Gap(2),
                      Text(t.pages, style: tx(13, c: MP.ink3)),
                    ],
                  ),
                ),
                const Gap(12),
                P2Pill(t.flag, bg: t.tone.$1, fg: t.tone.$2, height: 24, padX: 10),
              ],
            ),
          ),
          const Gap(12),
          Padding(padding: const EdgeInsets.only(left: 34), child: Text(t.summary, style: tx(14, h: 1.5))),
          if (open) ...[
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final v in t.values) _ValueRow(v)],
              ),
            ),
          ],
          const Gap(12),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Row(
                children: [
                  Text(open ? 'Hide values' : 'Show values', style: tx(14, w: w600, c: MP.primary)),
                  const Gap(4),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Ico(I.chevronDown, size: 16, color: MP.primary, stroke: 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final _Val v;
  const _ValueRow(this.v);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.name, style: tx(14, w: w600)),
              const Gap(1),
              Text('Normal ${v.ref}', style: tx(12, c: MP.ink3)),
            ],
          ),
        ),
        const Gap(12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(v.value, style: tx(15, w: w800, tab: true)),
            const Gap(1),
            Text(v.high ? 'High' : 'Normal', style: tx(12, w: w700, c: v.high ? MP.amber : MP.green)),
          ],
        ),
      ],
    ),
  );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String value;
  const _LabeledField(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [Text(label, style: tx(14, w: w600)), const Gap(6), P2Field(value: value, padLeft: 14, padRight: 14)],
  );
}

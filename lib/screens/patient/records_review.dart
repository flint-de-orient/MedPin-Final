import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';
import '../../widgets/i18n.dart';
import '../../widgets/file_view.dart';

/// Design: Records-Review.dc.html — "Records · check and save (multi-test file)".
///
/// Live args: {'record', 'extracted', 'shareWith'} straight after an upload
/// (Records-Add), or {'recordId'} to reopen a report still waiting to be
/// checked (POST /api/patient/records/:id/extract reads it again). Save posts
/// the kept tests to POST /api/patient/records/:id/split.
class RecordsReviewScreen extends StatefulWidget {
  const RecordsReviewScreen({super.key});

  @override
  State<RecordsReviewScreen> createState() => _RecordsReviewScreenState();
}

typedef _Tone = (Color, Color);

const _Tone _high = (MP.amberSoft, MP.amber);
const _Tone _ok = (MP.greenSoft, MP.green);

const _Tone _critical = (MP.redSoft, MP.red);

class _Val {
  final String name;
  final String ref;
  final String value;
  final bool high;

  /// Live: the API flag ('high', 'low', 'critical', 'normal').
  final String? flag;
  const _Val(this.name, this.ref, this.value, [this.high = false, this.flag]);

  String get label => flag == null ? (high ? 'High' : 'Normal') : p3Cap(flag!);
  Color get color => switch (flag) {
    'critical' => MP.red,
    'high' || 'low' => MP.amber,
    null => high ? MP.amber : MP.green,
    _ => MP.green,
  };
}

class _Test {
  final String name;
  final String pages;
  final String flag;
  final _Tone tone;
  final String summary;
  final List<_Val> values;

  /// Live: the test as sent to /split.
  final Map<String, dynamic>? raw;
  const _Test(this.name, this.pages, this.flag, this.tone, this.summary, this.values, {this.raw});

  /// A test read from the report (AI extraction, snake_case) or typed in.
  factory _Test.fromApi(Map<String, dynamic> t) {
    final values = t.list('values');
    final from = t['page_from'] ?? t['pageFrom'];
    final to = t['page_to'] ?? t['pageTo'];
    final pages = from is num && from > 0
        ? (to is num && to > from ? 'Pages ${from.toInt()}–${to.toInt()}' : 'Page ${from.toInt()}')
        : '${values.length} ${values.length == 1 ? 'value' : 'values'}';
    final flags = [for (final v in values) v.str('flag', 'normal')];
    final off = flags.where((f) => f != 'normal').length;
    final allLow = off > 0 && flags.where((f) => f != 'normal').every((f) => f == 'low');
    final critical = flags.contains('critical');
    return _Test(
      t.str('test_name', t.str('testName')),
      pages,
      off == 0 ? 'Normal' : (critical ? 'Critical' : '$off ${allLow ? 'low' : 'high'}'),
      off == 0 ? _ok : (critical ? _critical : _high),
      t.str('summary'),
      [
        for (final v in values)
          _Val(
            v.str('analyte'),
            v.str('ref_text', v.str('refText')),
            [v.str('value'), v.str('unit')].where((s) => s.isNotEmpty).join(' '),
            v.str('flag') == 'high',
            v.str('flag', 'normal'),
          ),
      ],
      raw: {
        'testName': t.str('test_name', t.str('testName')),
        if (from is num) 'pageFrom': from,
        if (to is num) 'pageTo': to,
        'summary': t.str('summary'),
        'values': [
          for (final v in values)
            {
              'analyte': v.str('analyte'),
              'value': v.str('value'),
              'unit': v.str('unit'),
              'refText': v.str('ref_text', v.str('refText')),
              'flag': v.str('flag', 'normal'),
            },
        ],
      },
    );
  }
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

class _RecordsReviewScreenState extends State<RecordsReviewScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  List<bool> _selected = [true, true, true];
  List<bool> _open = [true, false, false];

  // Live state (filled by fetch).
  List<_Test> _liveTests = const [];
  List<P3Doctor> _liveDoctors = const [];
  Set<String> _shareWith = {};
  final _date = TextEditingController();
  final _lab = TextEditingController();
  final _busy = ValueNotifier(false);

  List<_Test> get _shown => data == null ? _tests : _liveTests;

  int get _count => _selected.where((s) => s).length;

  Map<String, dynamic> get _record => data?.obj('record') ?? const {};
  Map<String, dynamic> get _extracted => data?.obj('extracted') ?? const {};

  @override
  Future<Object?> fetch() async {
    final args = (Nav.args<Map>(context) ?? const {}).cast<String, dynamic>();
    Map<String, dynamic> body;
    if (args['extracted'] is Map) {
      body = {'record': args['record'], 'extracted': args['extracted']};
    } else {
      final res = await Api.I.post('/api/patient/records/${args['recordId']}/extract');
      body = (res as Map).cast<String, dynamic>();
    }
    final doctors = await p3LoadDoctors();
    final record = body.obj('record');
    final extracted = body.obj('extracted');
    final shared = <String>{
      for (final id in (args['shareWith'] as List? ?? const [])) '$id',
      for (final s in record.list('sharedWith')) s.str('userId'),
    };
    _liveDoctors = doctors;
    _shareWith = args['shareWith'] != null || shared.isNotEmpty
        ? shared
        : {
            for (final d in doctors)
              if (d.suggested) d.id,
          };
    _liveTests = [for (final t in extracted.list('tests')) _Test.fromApi(t)];
    _selected = [for (final _ in _liveTests) true];
    _open = [for (var i = 0; i < _liveTests.length; i++) i == 0];
    final collected = DateTime.tryParse(extracted.str('collected_on'));
    final at = collected ?? F.date(record['recordDate']) ?? DateTime.now();
    _date.text = p3Date(at);
    _lab.text = extracted.str('lab_name', record.str('sourceName') == 'uploaded by you' ? '' : record.str('sourceName'));
    return body;
  }

  @override
  void dispose() {
    _date.dispose();
    _lab.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = _count;
    if (n == 0) {
      toast(context, 'Pick at least one test to save');
      return;
    }
    if (data == null) {
      if (isLive) return;
      toast(context, n == 1 ? '1 record saved' : '$n records saved');
      Nav.back(context);
      return;
    }
    final day = p3ParseDate(_date.text);
    if (day == null) {
      toast(context, 'Enter the date like 30 Sep 2026');
      return;
    }
    final tests = [
      for (var i = 0; i < _liveTests.length; i++)
        if (_selected[i]) _liveTests[i].raw,
    ];
    final ok = await runAction(
      context,
      () => Api.I.post('/api/patient/records/${_record.str('id')}/split', {
        'tests': tests,
        'collectedAt': p3Iso(day),
        if (_lab.text.trim().isNotEmpty) 'labName': _lab.text.trim(),
        'shareWith': _shareWith.toList(),
      }),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    p3RecordsChanged.value++;
    toast(context, n == 1 ? '1 record saved' : '$n records saved');
    Nav.back(context);
  }

  /// "Retake or replace": drop this upload and pick the file again.
  Future<void> _retake() async {
    if (data == null) {
      if (!isLive) Nav.go(context, 'Records-Add');
      return;
    }
    final ok = await runAction(context, () => Api.I.delete('/api/patient/records/${_record.str('id')}'), busy: _busy);
    if (ok == null || !mounted) return;
    p3RecordsChanged.value++;
    final nav = Navigator.of(context);
    nav.pop();
    Nav.go(nav.context, 'Records-Add');
  }

  Future<void> _addTest() async {
    if (data == null) {
      if (!isLive) p2Missing(context, 'Adding a test by hand');
      return;
    }
    final t = await openSheet<Map<String, dynamic>>(context, (_) => const _AddTestSheet());
    if (t == null || !mounted) return;
    setState(() {
      _liveTests = [..._liveTests, _Test.fromApi(t)];
      _selected = [..._selected, true];
      _open = [..._open, true];
    });
  }

  String get _foundLead {
    final n = _shown.length;
    if (data == null) return 'We found 3 tests in this file.';
    if (n == 0) return "We couldn't find the tests in this file.";
    return n == 1 ? 'We found 1 test in this file.' : 'We found $n tests in this file.';
  }

  String get _foundRest => data != null && _shown.isEmpty
      ? ' Add each test below, so you can find, track and share it.'
      : ' Each is saved as its own record, so you can find, track and share it separately.';

  @override
  Widget build(BuildContext context) {
    final n = _count;
    final tests = _shown;
    final shareTitle =
        n == tests.length ? 'Share all $n tests with' : (n == 1 ? 'Share 1 test with' : 'Share $n tests with');
    final placeholder = livePlaceholder();

    return MpPage(
        header: const P2WhiteHeader('Check your report'),
        bottom: placeholder != null
            ? null
            : MpBottomBar(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: MpButton(n == 1 ? 'Save 1 record' : 'Save $n records', onTap: _save),
              ),
        // main: padding 16 20 120 — the pinned bar (97px) takes the rest.
        body: placeholder ?? VGap(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 23),
          gap: 16,
          children: [
            data == null ? _FileCard(onRetake: _retake) : _FileCard.live(_record, _extracted, tests, onRetake: _retake),

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
                          TextSpan(text: _foundLead, style: tx(14, w: w700, h: 1.45)),
                          TextSpan(text: _foundRest),
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
                for (var i = 0; i < tests.length; i++) ...[
                  const Gap(8),
                  _TestCard(
                    tests[i],
                    selected: _selected[i],
                    open: _open[i],
                    onSelect: () => setState(() => _selected[i] = !_selected[i]),
                    onToggle: () => setState(() => _open[i] = !_open[i]),
                  ),
                ],
                const Gap(8),
                P2Box(
                  onTap: _addTest,
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
                  if (data == null)
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _LabeledField('Date', '30 Sep 2026')),
                        Gap(12),
                        Expanded(child: _LabeledField('Lab', 'Suraksha, Salt Lake')),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _LabeledField('Date', '', controller: _date)),
                        const Gap(12),
                        Expanded(child: _LabeledField('Lab', '', controller: _lab)),
                      ],
                    ),
                  const Gap(16),
                  if (data == null)
                    P2ShareDoctors(title: shareTitle, doctors: _doctors)
                  else
                    P3ShareDoctors(
                      title: shareTitle,
                      doctors: _liveDoctors,
                      selected: _shareWith,
                      onChanged: (s) => setState(() => _shareWith = s),
                      onAdd: (d) => setState(() {
                        _liveDoctors = [..._liveDoctors.where((x) => x.id != d.id), d];
                        _shareWith = {..._shareWith, d.id};
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

// The uploaded file: two stacked page thumbnails + lab, date, retake link.
class _FileCard extends StatelessWidget {
  final VoidCallback onRetake;
  final String files;
  final String pages;
  final String lab;
  final String collected;
  final String preview;
  /// Live: the uploaded file, drawn as its first page (tap to read it all).
  final ReportFile? file;
  const _FileCard({required this.onRetake})
    : file = null,
      files = '1 FILE · 6 PAGES',
      pages = '6',
      lab = 'Suraksha Diagnostics',
      collected = 'Collected 30 Sep 2026',
      preview = 'Report preview, 6 pages';

  /// The upload from the API and what the AI read from it.
  factory _FileCard.live(Map<String, dynamic> record, Map<String, dynamic> extracted, List<_Test> tests, {required VoidCallback onRetake}) {
    final n = record.list('files').length.clamp(1, 99);
    var pages = 0;
    for (final t in extracted.list('tests')) {
      pages = [pages, (t['page_to'] as num? ?? 0).toInt(), (t['page_from'] as num? ?? 0).toInt()].reduce((a, b) => a > b ? a : b);
    }
    final collected = DateTime.tryParse(extracted.str('collected_on'));
    final uploaded = F.date(record['createdAt']) ?? F.date(record['recordDate']);
    final source = record.str('sourceName');
    return _FileCard._(
      onRetake: onRetake,
      file: record.list('files').isEmpty ? null : ReportFile.fromApi(record.list('files').first),
      files: '$n ${n == 1 ? 'FILE' : 'FILES'}${pages > 0 ? ' · $pages ${pages == 1 ? 'PAGE' : 'PAGES'}' : ''}',
      pages: '$pages',
      lab: extracted.str('lab_name', source == 'uploaded by you' || source.isEmpty ? 'Your report' : source),
      collected: collected != null ? 'Collected ${p3Date(collected)}' : (uploaded != null ? 'Uploaded ${p3Date(uploaded)}' : ''),
      preview: pages > 0 ? 'Report preview, $pages pages' : 'Report preview',
    );
  }

  const _FileCard._({required this.onRetake, required this.file, required this.files, required this.pages, required this.lab, required this.collected, required this.preview});

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
            label: preview,
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
                    child: file != null
                        ? FilePreview(file: file, width: 70, height: 94, title: lab)
                        : Container(
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
                Text(files, style: tx(12, w: w700, c: MP.ink2, em: 0.06)),
                const Gap(4),
                Text(lab, style: tx(17, w: w700)),
                const Gap(4),
                if (collected.isNotEmpty) ...[Text(collected, style: tx(14, c: MP.ink2)), const Gap(4)],
                MpHitSlop(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetake,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Retake or replace', style: tx(14, w: w600, c: MP.primary)),
                  ),
                )),
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
          MpHitSlop(child: GestureDetector(
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
          )),
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
            Text(v.label, style: tx(12, w: w700, c: v.color)),
          ],
        ),
      ],
    ),
  );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String value;
  final TextEditingController? controller;
  const _LabeledField(this.label, this.value, {this.controller});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [Text(label, style: tx(14, w: w600)), const Gap(6), P2Field(value: value, controller: controller, padLeft: 14, padRight: 14)],
  );
}

/// "Add a test we missed" (no screen in the design): the test name and its
/// values, typed from the report. Pops with the test in the /split shape.
class _AddTestSheet extends StatefulWidget {
  const _AddTestSheet();

  @override
  State<_AddTestSheet> createState() => _AddTestSheetState();
}

class _ValueInput {
  final name = TextEditingController();
  final value = TextEditingController();
  final ref = TextEditingController();
  bool outside = false;

  void dispose() {
    name.dispose();
    value.dispose();
    ref.dispose();
  }
}

class _AddTestSheetState extends State<_AddTestSheet> {
  final _name = TextEditingController();
  final _values = [_ValueInput()];

  @override
  void dispose() {
    _name.dispose();
    for (final v in _values) {
      v.dispose();
    }
    super.dispose();
  }

  void _add() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Enter the test name');
      return;
    }
    final values = [
      for (final v in _values)
        if (v.name.text.trim().isNotEmpty && v.value.text.trim().isNotEmpty)
          {
            'analyte': v.name.text.trim(),
            'value': v.value.text.trim(),
            'unit': '',
            'refText': v.ref.text.trim(),
            'flag': v.outside ? 'high' : 'normal',
          },
    ];
    final off = values.where((v) => v['flag'] != 'normal').length;
    Navigator.of(context).pop(<String, dynamic>{
      'testName': name,
      'summary': values.isEmpty ? '' : (off == 0 ? 'All values in the normal range.' : '$off value${off == 1 ? '' : 's'} outside the normal range.'),
      'values': values,
    });
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          const P2SheetHeader(title: 'Add a test we missed', subtitle: 'Type the test and its values as printed on the report.'),
          const Gap(20),
          MpInput(label: 'Test name', hint: 'e.g. Thyroid profile', controller: _name),
          for (var i = 0; i < _values.length; i++) ...[
            const Gap(16),
            Text('Value ${i + 1}', style: tx(14, w: w600)),
            const Gap(8),
            MpInput(hint: 'Name, e.g. TSH', controller: _values[i].name),
            const Gap(8),
            Row(
              children: [
                Expanded(child: MpInput(hint: 'Result', controller: _values[i].value)),
                const Gap(8),
                Expanded(child: MpInput(hint: 'Normal range', controller: _values[i].ref)),
              ],
            ),
            const Gap(8),
            P2Box(
              onTap: () => setState(() => _values[i].outside = !_values[i].outside),
              label: 'Outside the normal range',
              minHeight: 44,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  MpCheck(value: _values[i].outside, onChanged: (_) => setState(() => _values[i].outside = !_values[i].outside)),
                  const Gap(12),
                  Expanded(child: Text('Outside the normal range', style: tx(14, c: MP.ink2))),
                ],
              ),
            ),
          ],
          const Gap(8),
          P2Box(
            onTap: () => setState(() => _values.add(_ValueInput())),
            height: 48,
            radius: 12,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Ico(I.plus, size: 16, color: MP.primary, stroke: 2),
                const Gap(6),
                Text('Add another value', style: tx(14, w: w600, c: MP.primary)),
              ],
            ),
          ),
          const Gap(20),
          MpButton('Add test', onTap: _add),
        ],
      ),
    );
  }
}

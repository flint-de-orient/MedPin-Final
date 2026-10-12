import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';
import '../../data/rx_pdf.dart';
import '../../data/downloads.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-Records.dc.html — "Patient · Health records".
class PatientRecordsScreen extends StatefulWidget {
  const PatientRecordsScreen({super.key});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

typedef _Tone = (Color, Color);

const _Tone _high = (MP.amberSoft, MP.amber);
const _Tone _ok = (MP.greenSoft, MP.green);
const _Tone _new = (MP.primarySoft, MP.primary);

class _Rec {
  final String kind;
  final String title;
  final String meta;
  final String summary;
  final String flag;
  final _Tone? tone;

  /// The API record (live only).
  final Map<String, dynamic>? raw;
  const _Rec(this.kind, this.title, this.meta, this.summary, [this.flag = '', this.tone, this.raw]);

  bool get isRx => kind == 'Prescription';
}

const List<(String, List<_Rec>)> _months = [
  (
    'September 2026',
    [
      _Rec(
        'Prescription',
        'Diabetes follow-up',
        '29 Sep · Dr. Arjun Sen',
        'Glimepiride added to bring sugar down. Keep Metformin twice a day. HbA1c test before your next visit.',
        'New',
        _new,
      ),
    ],
  ),
  ('August 2026', [_Rec('Test result', 'ECG', '12 Aug · City Care', 'Your heart rhythm is normal.', 'Normal', _ok)]),
  (
    'July 2026',
    [
      _Rec(
        'Test result',
        'Diabetes panel',
        '18 Jul · City Care lab',
        'HbA1c 7.2%, slightly above your target of 7. Fasting sugar 138, also a little high.',
        '2 high',
        _high,
      ),
      _Rec(
        'Test result',
        'Vitamin D',
        '18 Jul · uploaded by you',
        'Vitamin D is low (14). Your doctor started a weekly supplement.',
        'Low',
        _high,
      ),
    ],
  ),
  (
    'March 2026',
    [
      _Rec(
        'Test result',
        'Lipid profile',
        '12 Mar · SRL Diagnostics',
        'Bad cholesterol (LDL 162) and triglycerides are high. Good cholesterol is normal.',
        '2 high',
        _high,
      ),
      _Rec(
        'Prescription',
        'Sugar and cholesterol',
        '12 Mar · Dr. Arjun Sen',
        'Metformin continued. Lipid test ordered after a high LDL reading.',
      ),
    ],
  ),
];

const _kindLabels = {'prescription': 'Prescription', 'test_result': 'Test result', 'ecg': 'ECG', 'other': 'Record'};

/// Live data: GET /api/patient/records (the screen reloads when a record is
/// added from anywhere in the app).
class _PatientRecordsScreenState extends State<PatientRecordsScreen> with LiveData, P3Listen {
  int _filter = 0;
  String _query = '';

  /// Args {recordId}: open that record once the list has loaded.
  bool _openedArg = false;

  @override
  Future<Object?> fetch() async {
    final want = _openedArg ? null : Nav.args<Map>(context)?['recordId'];
    final res = await Api.I.get('/api/patient/records');
    if (want != null && res is Map) {
      _openedArg = true;
      final rows = res.cast<String, dynamic>().list('items');
      final hit = rows.where((x) => x.str('id') == '$want').toList();
      if (hit.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _view(_fromApi(hit.first));
        });
      }
    }
    return res;
  }

  @override
  void initState() {
    super.initState();
    p3Listen(p3RecordsChanged, () => reload(quiet: true));
  }

  static _Rec _fromApi(Map<String, dynamic> x) {
    final at = F.date(x['recordDate']);
    final pending = x.str('status') == 'processing' && x.str('kind') == 'test_result';
    final tone = switch (x.str('flagTone')) { 'high' => _high, 'ok' => _ok, 'new' => _new, _ => null };
    return _Rec(
      _kindLabels[x.str('kind')] ?? 'Record',
      x.str('title'),
      [if (at != null) F.dayMonth(at), x.str('sourceName')].where((s) => s.isNotEmpty).join(' · '),
      x.str('aiSummary'),
      pending ? 'To check' : x.str('flagLabel'),
      pending ? _new : (x.str('flagLabel').isEmpty ? null : tone),
      x,
    );
  }

  /// Live records grouped by month, newest first (the API sorts by date).
  List<(String, List<_Rec>)> get _liveMonths {
    final out = <(String, List<_Rec>)>[];
    for (final x in data!.list('items')) {
      final at = F.date(x['recordDate']) ?? DateTime.now();
      final m = p3Month(at);
      if (out.isEmpty || out.last.$1 != m) out.add((m, <_Rec>[]));
      out.last.$2.add(_fromApi(x));
    }
    return out;
  }

  bool _shows(_Rec r) {
    if (_filter == 1 && !r.isRx) return false;
    if (_filter == 2 && r.isRx) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty || '${r.kind} ${r.title} ${r.meta} ${r.summary}'.toLowerCase().contains(q);
  }

  Future<void> _view(_Rec r) async {
    final x = r.raw;
    if (x == null) {
      p2Missing(context, 'Viewing a record');
      return;
    }
    if (r.flag == 'To check') {
      await Nav.go(context, 'Records-Review', args: {'recordId': x.str('id')});
      return;
    }
    await openSheet<void>(context, (_) => _RecordSheet(record: x));
  }

  Future<void> _download(_Rec r) async {
    final x = r.raw;
    if (x == null) {
      toast(context, 'Downloading ${r.title}');
      return;
    }
    final files = x.list('files');
    final url = files.isNotEmpty ? files.first['url'] as String? : null;
    if (url == null && x['prescriptionId'] != null) {
      await RxPdf.download(context, x.str('prescriptionId'), patient: true);
      return;
    }
    if (url == null) {
      toast(context, 'This record has no file to download');
      return;
    }
    await Downloads.save(context, url, name: r.title, title: 'Downloaded');
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final live = data != null;
    final source = live ? _liveMonths : _months;
    final all = [for (final m in source) ...m.$2];
    final rx = all.where((r) => r.isRx).length;
    final filters = ['All · ${all.length}', 'Prescriptions · $rx', 'Tests · ${all.length - rx}'];
    final months = [
      for (final m in source)
        if (m.$2.any(_shows)) (m.$1, m.$2.where(_shows).toList()),
    ];
    final placeholder = livePlaceholder();

    return MpPage(
        nav: const PatientNav(current: 3),
        overlays: [
          // Floating "Add record" button: right 20, bottom 108.
          Positioned(
            right: 20,
            bottom: 108 + safeBottom,
            child: _AddRecordButton(onTap: () => Nav.go(context, 'Records-Add')),
          ),
        ],
        body: placeholder ?? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Health records', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                  const Gap(4),
                  Text('Prescriptions and test results from all your doctors', style: tx(14, c: MP.ink2)),
                  const Gap(16),
                  P2Field(
                    hint: 'Search a test, medicine or doctor',
                    icon: I.search,
                    padLeft: 46,
                    action: TextInputAction.search,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            const Gap(16),
            MpChipRow(
              gap: 8,
              children: [
                for (var i = 0; i < filters.length; i++)
                  _FilterChip(
                    filters[i],
                    selected: _filter == i,
                    padX: i == 2 ? 14 : 16,
                    onTap: () => setState(() => _filter = i),
                  ),
              ],
            ),
            // main: padding 20 20 184 (112 of it is the nav room MpPage adds).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
              child:
                  months.isEmpty
                      ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          all.isEmpty ? 'No records yet. Add a prescription or test report.' : 'No records match your search',
                          textAlign: TextAlign.center,
                          style: tx(14, c: MP.ink2),
                        ),
                      )
                      : VGap(gap: 20, children: [
                        for (final m in months) _MonthSection(title: m.$1, items: m.$2, onView: _view, onDownload: _download),
                      ]),
            ),
          ],
        ),
      );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final double padX;
  final VoidCallback onTap;
  const _FilterChip(this.label, {required this.selected, required this.padX, required this.onTap});

  @override
  Widget build(BuildContext context) => P2Box(
    onTap: onTap,
    label: label,
    height: 40,
    radius: 999,
    padding: EdgeInsets.symmetric(horizontal: padX),
    color: selected ? MP.primary : MP.white,
    border: selected ? null : MP.lineStrong,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text(label, style: tx(14, w: w600, c: selected ? MP.white : MP.ink2))],
    ),
  );
}

class _MonthSection extends StatelessWidget {
  final String title;
  final List<_Rec> items;
  final ValueChanged<_Rec> onView;
  final ValueChanged<_Rec> onDownload;
  const _MonthSection({required this.title, required this.items, required this.onView, required this.onDownload});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(title.toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
      ),
      const Gap(8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: MPDeco.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              _RecordItem(items[i], first: i == 0, onView: () => onView(items[i]), onDownload: () => onDownload(items[i])),
          ],
        ),
      ),
    ],
  );
}

class _RecordItem extends StatelessWidget {
  final _Rec r;
  final bool first;
  final VoidCallback onView;
  final VoidCallback onDownload;
  const _RecordItem(this.r, {required this.first, required this.onView, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.kind.toUpperCase(), style: tx(12, w: w700, c: MP.ink2, em: 0.06))),
              if (r.tone != null) ...[const Gap(8), P2Pill(r.flag, bg: r.tone!.$1, fg: r.tone!.$2)],
            ],
          ),
          const Gap(8),
          Text(r.title, style: tx(17, w: w700)),
          const Gap(2),
          Text(r.meta, style: tx(13, c: MP.ink2)),
          const Gap(8),
          // Live records without a summary (e.g. a prescription you uploaded) skip this line.
          if (r.summary.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Ico(I.sparkle, size: 16, color: MP.primary, stroke: 2),
                ),
                const Gap(8),
                Expanded(child: Text(r.summary, style: tx(14, h: 1.5))),
              ],
            ),
            const Gap(8),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: P2Box(
                    onTap: onView,
                    label: 'View ${r.title}',
                    height: 44,
                    radius: 12,
                    color: MP.primarySoft,
                    alignment: Alignment.center,
                    child: Text('View', style: tx(14, w: w700, c: MP.primary)),
                  ),
                ),
                const Gap(8),
                P2Box(
                  onTap: onDownload,
                  label: 'Download ${r.title}',
                  width: 44,
                  height: 44,
                  radius: 12,
                  color: MP.white,
                  border: MP.lineStrong,
                  alignment: Alignment.center,
                  child: const Ico(I.download, size: 18, color: MP.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddRecordButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddRecordButton({required this.onTap});

  @override
  Widget build(BuildContext context) => P2Box(
    onTap: onTap,
    label: 'Add record',
    height: 56,
    radius: 16,
    color: MP.primary,
    shadow: MPShadow.buttonStrong,
    padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Ico(I.plus, size: 22, color: MP.white, stroke: 2),
        const Gap(8),
        Text('Add record', style: tx(16, w: w700, c: MP.white)),
      ],
    ),
  );
}

/// "View" on a record (no screen in the design): the record's summary, its
/// values or medicines, the file, who it is shared with and Delete.
/// GET /api/patient/records/:id · POST …/share · DELETE …/:id
class _RecordSheet extends StatefulWidget {
  final Map<String, dynamic> record;
  const _RecordSheet({required this.record});

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> with LiveData {
  List<P3Doctor> _doctors = const [];
  Set<String> _shared = {};
  final _busy = ValueNotifier(false);

  String get _id => widget.record.str('id');

  @override
  Future<Object?> fetch() async {
    final res = await Future.wait([Api.I.get('/api/patient/records/$_id'), p3LoadDoctors()]);
    final rec = (res[0] as Map).cast<String, dynamic>();
    final doctors = res[1] as List<P3Doctor>;
    final shared = {for (final s in rec.list('sharedWith')) s.str('userId')};
    _doctors = [
      ...doctors,
      // Someone it is shared with who isn't in the care team any more.
      for (final id in shared)
        if (!doctors.any((d) => d.id == id)) P3Doctor(id, 'Shared doctor', ''),
    ];
    _shared = shared;
    return rec;
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _share(Set<String> next) async {
    final before = _shared;
    setState(() => _shared = next);
    final ok = await runAction(context, () => Api.I.post('/api/patient/records/$_id/share', {'userIds': next.toList()}), busy: _busy);
    if (!mounted) return;
    if (ok == null) {
      setState(() => _shared = before);
      return;
    }
    p3RecordsChanged.value++;
    toast(context, next.isEmpty ? 'Not shared with anyone' : 'Sharing updated');
  }

  Future<void> _delete() async {
    final yes = await p3Confirm(
      context,
      title: 'Delete this record?',
      body: 'It is removed from your records and from the doctors you shared it with.',
      confirm: 'Delete record',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(context, () => Api.I.delete('/api/patient/records/$_id'), busy: _busy);
    if (ok == null || !mounted) return;
    p3RecordsChanged.value++;
    toast(context, 'Record deleted');
    Navigator.of(context).pop();
  }

  String? get _fileUrl {
    final d = data ?? widget.record;
    final files = d.list('files');
    if (files.isNotEmpty) return files.first['url'] as String?;
    return d.obj('prescription').obj('file')['url'] as String?;
  }

  static String _pattern(Map<String, dynamic> m) {
    if (m.str('frequency') == 'weekly') return 'Once a week';
    final d = m.obj('dose');
    return '${d.numOr('morning').toInt()}-${d.numOr('afternoon').toInt()}-${d.numOr('night').toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final r = data ?? widget.record;
    final at = F.date(r['recordDate']);
    final meta = [if (at != null) p3Date(at), r.str('sourceName')].where((s) => s.isNotEmpty).join(' · ');
    final values = [for (final res in r.list('results')) ...res.list('values')];
    final meds = r.obj('prescription').list('items');
    final url = _fileUrl;

    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          P2SheetHeader(title: r.str('title', 'Record'), subtitle: meta),
          if (r.str('aiSummary').isNotEmpty) ...[
            const Gap(16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 3), child: Ico(I.sparkle, size: 16, color: MP.primary, stroke: 2)),
                const Gap(8),
                Expanded(child: Text(r.str('aiSummary'), style: tx(14, h: 1.5))),
              ],
            ),
          ],
          if (values.isNotEmpty) ...[
            const Gap(12),
            for (final v in values) _ApiValueRow(v),
          ],
          if (meds.isNotEmpty) ...[
            const Gap(12),
            for (var i = 0; i < meds.length; i++)
              P3Row(
                p3MedName(meds[i]),
                [_pattern(meds[i]), p3Food(meds[i].str('foodRelation')) ?? ''].where((s) => s.isNotEmpty).join(' · '),
                first: i == 0,
              ),
          ],
          if (data == null && isLive)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))),
            ),
          const Gap(20),
          if (url != null) ...[
            MpButton(
              'Open file',
              icon: I.download,
              onTap: () => r['prescriptionId'] != null && r.list('files').isEmpty
                  ? RxPdf.view(context, r.str('prescriptionId'), patient: true)
                  : p3Open(context, url, what: r.str('title', 'the file')),
            ),
            const Gap(20),
          ],
          if (data != null) ...[
            P3ShareDoctors(
              title: 'Shared with',
              doctors: _doctors,
              selected: _shared,
              onChanged: _share,
              onAdd: (d) {
                setState(() => _doctors = [..._doctors.where((x) => x.id != d.id), d]);
                _share({..._shared, d.id});
              },
            ),
            const Gap(20),
          ],
          MpButton('Delete record', kind: MpBtn.dangerSoft, onTap: _delete),
        ],
      ),
    );
  }
}

/// One analyte from the API: name, normal range, value and flag.
class _ApiValueRow extends StatelessWidget {
  final Map<String, dynamic> v;
  const _ApiValueRow(this.v);

  @override
  Widget build(BuildContext context) {
    final flag = v.str('flag', 'normal');
    final color = switch (flag) { 'critical' => MP.red, 'high' || 'low' => MP.amber, _ => MP.green };
    final value = [v.str('value', v.str('valueText')), v.str('unit')].where((s) => s.isNotEmpty).join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.str('analyte'), style: tx(14, w: w600)),
                if (v.str('refText').isNotEmpty) ...[const Gap(1), Text('Normal ${v.str('refText')}', style: tx(12, c: MP.ink3))],
              ],
            ),
          ),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: tx(15, w: w800, tab: true)),
              const Gap(1),
              Text(p3Cap(flag), style: tx(12, w: w700, c: color)),
            ],
          ),
        ],
      ),
    );
  }
}

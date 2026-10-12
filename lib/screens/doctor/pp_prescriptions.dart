import 'package:flutter/material.dart' hide Text;

import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d6.dart';
import '../../data/rx_pdf.dart';
import '../../widgets/i18n.dart';

/// Design: PP-Prescriptions.dc.html — "Patient profile · Prescriptions".
/// Live data: GET /api/patients/:id and /prescriptions?filter=all|this_clinic|shared.
class PpPrescriptionsScreen extends StatefulWidget {
  const PpPrescriptionsScreen({super.key});

  @override
  State<PpPrescriptionsScreen> createState() => _PpPrescriptionsScreenState();
}

enum _Tag { none, latest, shared }

class _PpPrescriptionsScreenState extends State<PpPrescriptionsScreen> with LiveData {
  static const _filterKeys = ['all', 'this_clinic', 'shared'];

  @override
  Future<Object?> fetch() => d6Load(context, {'rx': '/prescriptions?filter=${_filterKeys[_filter]}'});

  /// "Dr. Arjun Sen · City Care Clinic" / "Dr. S. Chatterjee · scanned paper".
  static String _by(Map<String, dynamic> x) {
    final mine = '${x['practiceId']}' == '${Session.I.practiceId}';
    final where = mine ? D6Rec.practiceName : (x['kind'] == 'scanned' ? 'scanned paper' : 'another clinic');
    return [x.str('doctorName'), where].where((s) => s.isNotEmpty).join(' · ');
  }

  /// "Diabetes follow-up. Metformin 500 mg started. HbA1c and Lipid profile advised."
  static String _summary(Map<String, dynamic> x) {
    String verb(Object? c) => switch (c) {
          'new' => 'started',
          'continued' => 'continued',
          'stopped' => 'stopped',
          null => '',
          _ => 'changed',
        };
    final meds = [
      for (final i in x.list('items')) [i.str('name'), i.str('strength'), verb(i['change'])].where((s) => s.isNotEmpty).join(' '),
    ];
    final tests = [for (final t in (x['tests'] as List? ?? const [])) '$t'];
    return [
      if (x.str('diagnosisSummary').isNotEmpty) '${x.str('diagnosisSummary')}.',
      if (meds.isNotEmpty) '${d6Cap(meds.join(', '))}.',
      if (tests.isNotEmpty) '${F.joinAnd(tests)} ${tests.length == 1 ? 'test' : 'tests'} advised.',
    ].join(' ');
  }

  /// "3 medicines · 3 tests · Follow-up 29 Oct"
  static String _meta(Map<String, dynamic> x) {
    final n = x.list('items').length;
    final t = (x['tests'] as List? ?? const []).length;
    final f = F.date(x['followUpDate']);
    return [
      if (x['source'] == 'uploaded_by_patient') 'Uploaded by patient',
      if (n > 0) '$n ${n == 1 ? 'medicine' : 'medicines'}',
      if (t > 0) '$t ${t == 1 ? 'test' : 'tests'}',
      if (f != null) 'Follow-up ${F.dayMonth(f)}',
    ].join(' · ');
  }

  static _Tag _tag(Map<String, dynamic> x) {
    if ('${x['practiceId']}' != '${Session.I.practiceId}' || (x['source'] != null && x['source'] != 'this_clinic')) return _Tag.shared;
    return x['latest'] == true ? _Tag.latest : _Tag.none;
  }

  Widget _liveBody(D6Rec rec) {
    final rx = rec.m.obj('rx');
    final c = rx.obj('counts');
    final items = rx.list('items');
    final labels = ['All · ${c.numOr('all')}', 'This clinic · ${c.numOr('thisClinic')}', 'Shared · ${c.numOr('shared')}'];
    return VGap(
      gap: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < labels.length; i++)
              D6FilterChip(
                labels[i],
                padH: _filters[i].$2,
                selected: _filter == i,
                onTap: () {
                  if (_filter == i) return;
                  setState(() => _filter = i);
                  reload(quiet: true);
                },
              ),
          ],
        ),
        D6ShieldNote('Includes prescriptions ${rec.first} chose to share from other clinics.'),
        if (items.isEmpty) Text('No prescriptions yet', style: tx(14, c: MP.ink2)),
        for (final x in items)
          _RxCard(
            date: F.date(x['issuedAt']) == null ? '' : d6Date(F.date(x['issuedAt'])!),
            by: _by(x),
            summary: _summary(x),
            meta: _meta(x),
            tag: _tag(x),
            // View opens the prescription itself; Download saves it to the phone.
            onView: () => RxPdf.view(context, x.str('id')),
            onDownload: () => RxPdf.download(context, x.str('id')),
          ),
        // The full folder: every prescription, send to patient, file a paper one.
        Center(
          child: D6Link(
            'All prescriptions · file a paper one',
            leading: I.fileText,
            minHeight: 44,
            onTap: () => Nav.go(context, 'Prescriptions', args: {'patientId': rec.id}),
          ),
        ),
      ],
    );
  }

  /// date, prescriber, summary, meta, tag.
  static const _rx = [
    (
      '29 Sep 2026',
      'Dr. Arjun Sen · Endocrinology · City Care',
      'Diabetes follow-up. Glimepiride 2 mg added, Metformin continued. HbA1c and glucose tests advised.',
      '3 medicines · 3 tests · Follow-up 29 Oct',
      _Tag.latest,
    ),
    (
      '12 Mar 2026',
      'Dr. Arjun Sen · Endocrinology · City Care',
      'Sugar stable. Metformin continued. Lipid profile ordered after a high LDL reading.',
      '2 medicines · 1 test · Follow-up 12 Jun',
      _Tag.none,
    ),
    (
      '02 Feb 2026',
      'Dr. Rina Mitra · Cardiology · City Care',
      'Chest discomfort review. ECG normal. Atorvastatin 10 mg started for raised LDL.',
      '1 medicine · 1 test',
      _Tag.none,
    ),
    (
      '12 Jan 2026',
      'Dr. Arjun Sen · Endocrinology · City Care',
      'HbA1c improved to 6.8%. Metformin kept at 500 mg twice daily.',
      '1 medicine · 2 tests',
      _Tag.none,
    ),
    (
      '18 Nov 2025',
      'Dr. Nandita Gupta · Gynaecology · Apollo Clinic',
      'PCOS review. Myo-inositol started, with diet and activity advice.',
      '1 medicine · 1 test',
      _Tag.shared,
    ),
    (
      '05 Sep 2025',
      'Dr. S. Chatterjee · General medicine · scanned paper',
      'Diabetes diagnosed. Metformin 500 mg once daily started.',
      'Uploaded by Priya · 1 medicine',
      _Tag.shared,
    ),
  ];

  /// label, horizontal padding.
  static const _filters = [('All · 6', 16.0), ('This clinic · 4', 16.0), ('Shared · 2', 14.0)];

  int _filter = 0;

  bool _visible(_Tag tag) => switch (_filter) {
    1 => tag != _Tag.shared,
    2 => tag == _Tag.shared,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final rec = data == null ? null : D6Rec(data!);
    if (rec != null) {
      return D6PatientTabsPage(tab: 1, gap: 12, rec: rec, onChanged: () => reload(quiet: true), children: [_liveBody(rec)]);
    }
    return D6PatientTabsPage(
      tab: 1,
      gap: 12,
      placeholder: livePlaceholder(),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _filters.length; i++)
              D6FilterChip(
                _filters[i].$1,
                padH: _filters[i].$2,
                selected: _filter == i,
                onTap: () => setState(() => _filter = i),
              ),
          ],
        ),
        const D6ShieldNote('Includes prescriptions Priya chose to share from other clinics.'),
        for (final r in _rx)
          if (_visible(r.$5)) _RxCard(date: r.$1, by: r.$2, summary: r.$3, meta: r.$4, tag: r.$5),
      ],
    );
  }
}

class _RxCard extends StatelessWidget {
  final String date;
  final String by;
  final String summary;
  final String meta;
  final _Tag tag;
  final VoidCallback? onView;
  final VoidCallback? onDownload;
  const _RxCard({
    required this.date,
    required this.by,
    required this.summary,
    required this.meta,
    required this.tag,
    this.onView,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final pill = switch (tag) {
      _Tag.latest => const D6Pill('Latest', bg: MP.fill, fg: MP.ink2),
      _Tag.shared => const D6Pill('Shared by patient', bg: MP.primarySoft, fg: MP.primary),
      _Tag.none => null,
    };
    return MpCard(
      child: VGap(
        gap: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(date, style: tx(18, w: w700, h: 1.25, tab: true))),
                  if (pill != null) ...[const Gap(8), pill],
                ],
              ),
              const Gap(4),
              Text(by, style: tx(14, c: MP.ink2)),
            ],
          ),
          Text(summary, style: tx(15, h: 1.5)),
          Text(meta, style: tx(13, c: MP.ink3)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Tap(
                    onTap: onView ?? () => Nav.go(context, 'Prescriptions'),
                    radius: 12,
                    color: MP.primarySoft,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Ico(I.eye, size: 18, color: MP.primary),
                          const Gap(8),
                          Text('View', style: tx(15, w: w600, c: MP.primary)),
                        ],
                      ),
                    ),
                  ),
                ),
                const Gap(8),
                MpIconButton(
                  I.download,
                  label: 'Download $date prescription',
                  size: 48,
                  iconSize: 20,
                  color: MP.primary,
                  background: MP.white,
                  borderColor: MP.lineStrong,
                  onTap: onDownload ?? () => toast(context, 'Downloading $date prescription'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

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
  const _Rec(this.kind, this.title, this.meta, this.summary, [this.flag = '', this.tone]);

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

class _PatientRecordsScreenState extends State<PatientRecordsScreen> {
  int _filter = 0;
  String _query = '';

  bool _shows(_Rec r) {
    if (_filter == 1 && !r.isRx) return false;
    if (_filter == 2 && r.isRx) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty || '${r.kind} ${r.title} ${r.meta} ${r.summary}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final all = [for (final m in _months) ...m.$2];
    final rx = all.where((r) => r.isRx).length;
    final filters = ['All · ${all.length}', 'Prescriptions · $rx', 'Tests · ${all.length - rx}'];
    final months = [
      for (final m in _months)
        if (m.$2.any(_shows)) (m.$1, m.$2.where(_shows).toList()),
    ];

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
        body: Column(
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
                          'No records match your search',
                          textAlign: TextAlign.center,
                          style: tx(14, c: MP.ink2),
                        ),
                      )
                      : VGap(gap: 20, children: [for (final m in months) _MonthSection(title: m.$1, items: m.$2)]),
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
  const _MonthSection({required this.title, required this.items});

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
          children: [for (var i = 0; i < items.length; i++) _RecordItem(items[i], first: i == 0)],
        ),
      ),
    ],
  );
}

class _RecordItem extends StatelessWidget {
  final _Rec r;
  final bool first;
  const _RecordItem(this.r, {required this.first});

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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: P2Box(
                    onTap: () => p2Missing(context, 'Viewing a record'),
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
                  onTap: () => toast(context, 'Downloading ${r.title}'),
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

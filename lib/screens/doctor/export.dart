import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: Export.dc.html — "Export".
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

// (dataset, detail)
const _sets = [
  ('Patients', 'Profiles and contact details'),
  ('Clinical summary', 'Conditions, medicines, latest readings'),
  ('Alerts', 'Raised within the date range below'),
];

class _ExportScreenState extends State<ExportScreen> {
  final _included = [true, true, true];
  int _format = 0;

  void _export() {
    if (!_included.contains(true)) {
      toast(context, 'Choose at least one dataset');
      return;
    }
    toast(context, '${_format == 0 ? 'CSV' : 'JSON'} export ready to share');
  }

  Widget _dateField(String value) => D9Input(
    value: value,
    tab: true,
    keyboard: TextInputType.datetime,
    padRight: 44,
    trailingRight: 14,
    trailing: const Ico(I.calendar, size: 20, color: MP.ink2),
  );

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Export data'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 24,
        children: [
          // Datasets
          D9Card(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('What to include', style: tx(20, w: w700, h: 1.25)),
              ),
              for (var i = 0; i < _sets.length; i++)
                Semantics(
                  checked: _included[i],
                  child: D9Row(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: () => setState(() => _included[i] = !_included[i]),
                    child: Row(
                      children: [
                        D9Check(_included[i]),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_sets[i].$1, style: tx(16, w: w600, h: 1.5)),
                              const Gap(2),
                              Text(_sets[i].$2, style: tx(14, c: MP.ink2, h: 1.45)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Alerts date range
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Alerts date range', bottom: 8),
              Row(
                children: [
                  Expanded(child: Semantics(label: 'From', child: _dateField('1 Jul 2026'))),
                  const Gap(8),
                  Expanded(child: Semantics(label: 'To', child: _dateField('29 Sep 2026'))),
                ],
              ),
            ],
          ),

          // Format
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Format'),
              const Gap(8),
              MpSegmented(
                options: const ['CSV', 'JSON'],
                index: _format,
                onChanged: (i) => setState(() => _format = i),
              ),
            ],
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Privacy warning
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.alert, size: 20, color: MP.amber)),
                    const Gap(12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: tx(14, h: 1.45),
                          children: [
                            TextSpan(
                              text: 'This file will contain patient health information.',
                              style: tx(14, w: w600, c: MP.amber, h: 1.45),
                            ),
                            const TextSpan(text: ' Share it only through channels your clinic trusts.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Includes all 412 patients, not just the first page',
                  style: tx(14, c: MP.ink2, h: 1.45, tab: true),
                ),
              ),
            ],
          ),

          MpButton('Export and share', icon: I.share, iconStroke: 1.75, onTap: _export),
        ],
      ),
    );
  }
}

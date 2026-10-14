import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';
import '../../widgets/i18n.dart';

/// Design: Export.dc.html — "Export".
/// Live data: GET /api/billing (active patient count); "Export and share" →
/// POST /api/exports {kind: data_export} and opens the file link.
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

// API dataset keys, in the order of [_sets].
const _setKeys = ['patients', 'clinical_summary', 'alerts'];

class _ExportScreenState extends State<ExportScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  final _included = [true, true, true];
  int _format = 0;
  final _busy = ValueNotifier(false);

  // Live: the last 90 days.
  late final _from = TextEditingController(
    text: isLive ? D9Fmt.date(DateTime.now().subtract(const Duration(days: 90))) : '1 Jul 2026',
  );
  late final _to = TextEditingController(text: isLive ? D9Fmt.date(DateTime.now()) : '29 Sep 2026');

  @override
  Future<Object?> fetch() => Api.I.get('/api/billing', query: {'invoices': 1});

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _busy.dispose();
    super.dispose();
  }

  /// Hidden until the live count arrives.
  String? get _patientsLine {
    if (data == null) return isLive ? null : 'Includes all 412 patients, not just the first page';
    final n = data!.obj('usage').obj('activePatients').numOr('used');
    return 'Includes all ${D9Fmt.plural(n, 'patient')}, not just the first page';
  }

  Future<void> _export() async {
    if (!_included.contains(true)) {
      toast(context, 'Choose at least one dataset');
      return;
    }
    final format = _format == 0 ? 'CSV' : 'JSON';
    if (!isLive) {
      toast(context, '$format export ready to share');
      return;
    }
    final from = D9Fmt.parseDate(_from.text);
    final to = D9Fmt.parseDate(_to.text);
    if (from == null || to == null) {
      toast(context, 'Enter dates like ${D9Fmt.date(DateTime.now())}');
      return;
    }
    if (from.isAfter(to)) {
      toast(context, 'The start date is after the end date');
      return;
    }
    final res = await runAction(
      context,
      () => Api.I.post('/api/exports', {
        'kind': 'data_export',
        'datasets': [for (var i = 0; i < _setKeys.length; i++) if (_included[i]) _setKeys[i]],
        'format': format.toLowerCase(),
        'filters': {'from': D9Fmt.dayKey(from), 'to': D9Fmt.dayKey(to)},
      }),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    toast(context, '$format export ready to share');
    await D9Open.url(context, res['url'], failed: "Couldn't open the export");
  }

  Widget _dateField(TextEditingController controller) => D9Input(
    controller: controller,
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
                  Expanded(child: Semantics(label: 'From', child: _dateField(_from))),
                  const Gap(8),
                  Expanded(child: Semantics(label: 'To', child: _dateField(_to))),
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
              if (_patientsLine != null) ...[
                const Gap(12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _patientsLine!,
                    style: tx(14, c: MP.ink2, h: 1.45, tab: true),
                  ),
                ),
              ],
            ],
          ),

          MpButton('Export and share', icon: I.share, iconStroke: 1.75, onTap: _export),
        ],
      ),
    );
  }
}

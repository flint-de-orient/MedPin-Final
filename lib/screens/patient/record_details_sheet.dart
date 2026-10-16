import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import 'common_p3.dart';

/// "Check the details" after an upload, and "Edit details" on any record: the
/// name, who it's from and the date — filled in from what MedPin read on the
/// document (doctor, clinic, date, diagnosis), but the patient has the final
/// say. PATCH /api/patient/records/:id. Pops the saved record, or null.
class RecordDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> record;

  /// What was read from the document ({doctor, clinic, diagnosis, tests, medicines}), if anything.
  final Map<String, dynamic> detected;
  final bool afterUpload;
  const RecordDetailsSheet({super.key, required this.record, this.detected = const {}, this.afterUpload = false});

  @override
  State<RecordDetailsSheet> createState() => _RecordDetailsSheetState();
}

class _RecordDetailsSheetState extends State<RecordDetailsSheet> {
  late final _title = TextEditingController(text: widget.record.str('title'));
  late final _from = TextEditingController(text: widget.record.str('sourceName') == 'uploaded by you' ? '' : widget.record.str('sourceName'));
  late final _date = TextEditingController(text: () {
    final d = F.date(widget.record['recordDate']);
    return d == null ? '' : p3Date(d);
  }());
  final _busy = ValueNotifier(false);

  bool get _isRx => widget.record.str('kind') == 'prescription';

  @override
  void dispose() {
    _title.dispose();
    _from.dispose();
    _date.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return toast(context, 'Give it a name');
    final day = _date.text.trim().isEmpty ? null : p3ParseDate(_date.text);
    if (_date.text.trim().isNotEmpty && day == null) return toast(context, 'Enter the date like 30 Sep 2026');
    final res = await runAction(
      context,
      () => Api.I.patch('/api/patient/records/${widget.record.str('id')}', {
        'title': title,
        if (_from.text.trim().isNotEmpty) 'sourceName': _from.text.trim(),
        if (day != null) 'recordDate': p3Iso(day),
      }),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    p3RecordsChanged.value++;
    Navigator.of(context).pop(res.cast<String, dynamic>().obj('record'));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detected;
    final found = [
      if (d.str('doctor').isNotEmpty) d.str('doctor'),
      if (d.str('clinic').isNotEmpty) d.str('clinic'),
      if (d.str('diagnosis').isNotEmpty) d.str('diagnosis'),
      if (d.numOr('medicines') > 0) tr(context, d.numOr('medicines') == 1 ? '1 medicine' : '#1 medicines').replaceFirst('#1', '${d.numOr('medicines').toInt()}'),
      if ((d['tests'] as List? ?? const []).isNotEmpty)
        tr(context, (d['tests'] as List).length == 1 ? '1 test advised' : '#1 tests advised').replaceFirst('#1', '${(d['tests'] as List).length}'),
    ];
    return MpSheet(
      title: widget.afterUpload ? 'Check the details' : 'Edit details',
      subtitle: widget.afterUpload
          ? (found.isEmpty ? 'Name it so you can find it later. You can change this any time.' : 'We read these from the document. Change anything that isn’t right.')
          : 'Change how this record is named and dated.',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VGap(
          gap: 14,
          children: [
            if (found.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.sparkle, size: 16, color: MP.primary, stroke: 2)),
                    const Gap(8),
                    Expanded(child: Text(found.join(' · '), style: tx(14, h: 1.45))),
                  ],
                ),
              ),
            MpInput(label: 'Name', controller: _title),
            MpInput(label: _isRx ? 'Doctor or clinic' : 'Lab', controller: _from, hint: _isRx ? 'e.g. Dr. Rina Mitra' : 'e.g. Suraksha Diagnostics'),
            MpInput(label: 'Date', controller: _date, hint: 'e.g. 30 Sep 2026'),
            ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (_, busy, _) => MpButton(busy ? 'Saving…' : 'Save', onTap: busy ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}

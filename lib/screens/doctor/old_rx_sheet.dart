import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';

/// File a prescription written on paper: one written here, or an old one the patient brought
/// from another doctor or hospital. Like filing it in the patient's folder: every page (photos
/// one by one, or a PDF), the date it was written, and who wrote it. MedPin AI reads the
/// medicines, diagnosis and tests from it when it is on (the scan stays the record).
/// POST /api/patients/:id/records (kind prescription, scanned). True when filed.
Future<bool> fileOldPrescription(BuildContext context, {required String patientId, required String source}) async {
  UploadFile? first;
  try {
    first = source == 'pdf' ? await Files.pdf() : await Files.photo(camera: source == 'camera');
  } catch (_) {
    if (context.mounted) toast(context, source == 'camera' ? "Couldn't open the camera" : "Couldn't open your files");
    return false;
  }
  if (first == null || !context.mounted) return false;
  final done = await openSheet<bool>(context, (_) => _OldRxSheet(patientId: patientId, first: first!, source: source));
  return done == true;
}

class _OldRxSheet extends StatefulWidget {
  final String patientId;
  final UploadFile first;
  final String source;
  const _OldRxSheet({required this.patientId, required this.first, required this.source});

  @override
  State<_OldRxSheet> createState() => _OldRxSheetState();
}

class _OldRxSheetState extends State<_OldRxSheet> {
  late final List<UploadFile> _pages = [widget.first];
  DateTime _date = DateTime.now();
  bool _elsewhere = false;
  final _from = TextEditingController();
  bool _busy = false;

  bool get _pdf => widget.first.mimeType.contains('pdf');

  @override
  void dispose() {
    _from.dispose();
    super.dispose();
  }

  Future<void> _addPage(bool camera) async {
    try {
      final f = await Files.photo(camera: camera);
      if (f != null && mounted) setState(() => _pages.add(f));
    } catch (_) {
      if (mounted) toast(context, camera ? "Couldn't open the camera" : "Couldn't open your files");
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: tr(context, 'Date written on it'),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  String get _day => '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_elsewhere && _from.text.trim().isEmpty) {
      toast(context, 'Write the doctor or hospital, as on the prescription');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await runAction(
        context,
        () => Api.I.upload('/api/patients/${widget.patientId}/records', files: {'files': _pages}, fields: {
          'kind': 'prescription',
          'scanned': 'true',
          'title': _elsewhere ? 'Old prescription' : 'Paper prescription',
          'uploadSource': widget.source,
          'recordDate': _day,
          'writtenBy': _elsewhere ? 'elsewhere' : 'here',
          if (_elsewhere) 'sourceName': _from.text.trim(),
        }),
      );
      if (res is! Map || !mounted) return;
      final rx = res['prescription'] is Map ? (res['prescription'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final n = (rx['medicines'] as num? ?? 0).toInt();
      toast(
        context,
        n > 0
            ? trf(context, 'Prescription filed · {n} medicines read from it', {'n': '$n'})
            : rx['read'] == true || rx['aiOff'] == true
                ? tr(context, 'Prescription filed')
                : tr(context, "Prescription filed · the medicines couldn't be read, the scan is kept"),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = F.sameDay(_date, DateTime.now());
    return MpSheet(
      title: 'File a paper prescription',
      subtitle: 'Every page, the date written on it, and who wrote it',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VGap(
          gap: 16,
          children: [
            // Pages
            MpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_pdf ? 'PDF' : trf(context, '{n} pages', {'n': '${_pages.length}'}), style: tx(15, w: w600)),
                  const Gap(4),
                  for (var i = 0; i < _pages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Ico(_pdf ? I.fileText : I.image, size: 18, color: MP.ink2),
                          const Gap(8),
                          Expanded(child: Text(_pdf ? _pages[i].name : trf(context, 'Page {n}', {'n': '${i + 1}'}), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2))),
                          if (_pages.length > 1)
                            MpIconButton(I.close, label: 'Remove page', iconSize: 16, color: MP.ink3, onTap: () => setState(() => _pages.removeAt(i))),
                        ],
                      ),
                    ),
                  if (!_pdf && _pages.length < 10) ...[
                    const Gap(10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MpButton.small('Add a page · Camera', kind: MpBtn.secondary, expand: false, onTap: () => _addPage(true)),
                        MpButton.small('Gallery', kind: MpBtn.secondary, expand: false, onTap: () => _addPage(false)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Date written on it
            MpInput(
              label: 'Date written on it',
              value: today ? tr(context, 'Today') : F.dateLong(_date),
              readOnly: true,
              trailing: const Ico(I.calendar, size: 18, color: MP.ink2),
              onTap: _pickDate,
            ),
            // Who wrote it
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Written by', style: tx(14, w: w600, c: MP.ink2)),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MpChip('This clinic', selected: !_elsewhere, onTap: () => setState(() => _elsewhere = false)),
                    MpChip('Another doctor or hospital', selected: _elsewhere, onTap: () => setState(() => _elsewhere = true)),
                  ],
                ),
                if (_elsewhere) ...[
                  const Gap(12),
                  MpInput(controller: _from, label: 'Doctor or hospital', hint: 'E.g. Dr. R. Das · AMRI Hospital'),
                ],
              ],
            ),
            MpButton(_busy ? 'Filing…' : 'File prescription', onTap: _busy ? null : _save),
          ],
        ),
      ),
    );
  }
}

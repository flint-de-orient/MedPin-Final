import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';
import '../../widgets/i18n.dart';

/// Design: Records-Add.dc.html — "Records · add a record" (sheet over Patient-Records).
///
/// Live: the "Share with" list is the patient's care team (GET
/// /api/patient/my-doctors). Take photo / Gallery / PDF file picks a file and
/// uploads it (POST /api/patient/records, multipart `files`). A test report the
/// AI could read opens Records-Review to check and save each test.
///
/// Args (optional): {'kind': 'test_result' | 'prescription', 'title',
/// 'appointmentId' (sent with the upload), 'doctorId' / 'doctorName' (ticked,
/// so the upload is shared with them via the upload's shareWith)}; staff
/// opening it for a patient pass {'patientId'} and the file goes to
/// /api/patients/:id/records. Pops with the new record id after an upload.
class RecordsAddSheet extends StatefulWidget {
  const RecordsAddSheet({super.key});

  @override
  State<RecordsAddSheet> createState() => _RecordsAddSheetState();
}

class _RecordsAddSheetState extends State<RecordsAddSheet> with LiveData {
  int _kind = 1;
  final _busy = ValueNotifier(false);
  bool _uploading = false;

  List<P3Doctor> _liveDoctors = const [];
  Set<String> _shareWith = {};

  /// Opened from one of the doctor's tests (Upload on Home / Records): the
  /// report is for that test only. The server reads the report and checks it
  /// really is that test (its content, not the file name).
  String? _forTest;

  static const _sources = [(I.camera, 'Take photo'), (I.image, 'Gallery'), (I.fileText, 'PDF file')];
  static const _sourceKeys = ['camera', 'gallery', 'pdf'];

  static const _doctors = [
    P2Doctor('Dr. Arjun Sen', "Suggested · asked for this before today's 5 PM visit", suggested: true, on: true),
    P2Doctor('Dr. Rina Mitra', 'Heart · City Care'),
    P2Doctor('Dr. Nandita Gupta', 'Gynaecology · Apollo Clinic'),
  ];

  Map<String, dynamic> get _args => (Nav.args<Map>(context) ?? const {}).cast<String, dynamic>();

  bool _argsRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final kind = _args['kind'];
    if (kind == 'prescription') _kind = 0;
    if (kind == 'test_result') _kind = 1;
    if (_args['forTest'] is String && (_args['forTest'] as String).trim().isNotEmpty) {
      _forTest = (_args['forTest'] as String).trim();
      _kind = 1;
    }
  }

  /// Staff uploading for a patient (no care-team picker then).
  String? get _forPatient => Session.I.patientId == null ? _args['patientId'] as String? : null;

  @override
  Future<Object?> fetch() async {
    if (_forPatient != null) return {'doctors': const []};
    final pre = _args['doctorId'] as String?;
    final name = _args['doctorName'] as String?;
    final doctors = await p3LoadDoctors();
    // Opened from a doctor's page ("Share"): that doctor is ticked even when
    // they aren't in the care team yet.
    if (pre != null && !doctors.any((d) => d.id == pre)) doctors.insert(0, P3Doctor(pre, name ?? 'This doctor', ''));
    _liveDoctors = doctors;
    _shareWith = {
      for (final d in doctors)
        if (d.suggested || d.id == pre) d.id,
    };
    return {'doctors': doctors.length};
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _pick(int i) async {
    if (!isLive) {
      p2SheetThen(context, 'Records-Review');
      return;
    }
    if (_busy.value) return;
    final source = _sourceKeys[i];
    UploadFile? file;
    try {
      file = source == 'pdf' ? await Files.pdf() : await Files.photo(camera: source == 'camera');
    } catch (_) {
      if (mounted) toast(context, "Couldn't open ${source == 'camera' ? 'the camera' : 'your files'}");
      return;
    }
    if (file == null || !mounted) return;
    final upload = file;
    final kind = _kind == 0 ? 'prescription' : 'test_result';
    final patientId = _forPatient;
    // The doctor this sheet was opened for, even if the care team didn't load.
    final pre = _args['doctorId'] as String?;
    if (data == null && pre != null) _shareWith = {..._shareWith, pre};
    setState(() => _uploading = true);
    if (kind == 'test_result') toast(context, 'Reading your report…');
    final res = await runAction(
      context,
      () => Api.I.upload(
        patientId != null ? '/api/patients/$patientId/records' : '/api/patient/records',
        files: {'files': [upload]},
        fields: {
          'kind': kind,
          'uploadSource': source,
          if (_args['title'] != null) 'title': '${_args['title']}',
          if (kind == 'test_result' && _forTest != null) 'forTests': _forTest!,
          if (_args['appointmentId'] != null) 'appointmentId': '${_args['appointmentId']}',
          if (patientId == null && _shareWith.isNotEmpty) 'shareWith': _shareWith.join(','),
        },
      ),
      busy: _busy,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res == null) return;
    p3RecordsChanged.value++;
    final body = res is Map ? res.cast<String, dynamic>() : <String, dynamic>{};
    final extracted = body.obj('extracted');
    final recordId = body.obj('record').str('id', body.str('id', 'uploaded'));
    // Uploaded for one test: was it really that test?
    if (_forTest != null && patientId == null && !await _checked(body.obj('testCheck'), recordId)) return;
    if (!mounted) return;
    if (patientId == null && extracted.list('tests').isNotEmpty) {
      // Check and save each test on Records-Review.
      final nav = Navigator.of(context);
      nav.pop(recordId);
      Nav.go(nav.context, 'Records-Review', args: {'record': body.obj('record'), 'extracted': extracted, 'shareWith': _shareWith.toList()});
      return;
    }
    final meds = body.list('medicines');
    toast(
      context,
      kind == 'prescription'
          ? (meds.isEmpty ? 'Prescription saved' : 'Prescription saved · ${meds.length} ${meds.length == 1 ? 'medicine' : 'medicines'} found — add them in Medicines')
          : 'Report saved',
    );
    Navigator.of(context).pop(recordId);
  }

  /// What the server found in a report uploaded for [_forTest]. The right
  /// test: carry on. Another test, a prescription, or too blurred to read:
  /// say so, and offer to upload the right report (this one is removed) or
  /// keep it as a separate report. Returns false when the patient goes back
  /// to pick another file.
  Future<bool> _checked(Map<String, dynamic> check, String recordId) async {
    final test = _forTest!;
    if (check.isEmpty || check['checked'] == false) {
      // MedPin couldn't read it automatically: it's with the doctor.
      toast(context, "Report uploaded. We couldn't check it automatically — your doctor will look at it.");
      return true;
    }
    String t(String s, [String a = '', String b = '']) => tr(context, s).replaceFirst('#1', a).replaceFirst('#2', b);
    if ((check['found'] as List? ?? const []).isNotEmpty) {
      toast(context, t('#1 report received', test));
      return true;
    }
    final readable = check['readable'] == true;
    final type = check.str('documentType');
    final detected = [for (final d in (check['detected'] as List? ?? const [])) '$d'];
    final askRight = t('Upload the #1 report from your lab. The file name doesn’t matter — we read what’s inside.', test);
    final (title, body) = !readable && type != 'prescription' && type != 'not_medical'
        ? (t("We couldn't read this report"), t('Make sure the whole page is in the photo, flat and in good light — or upload the PDF your lab sent.'))
        : type == 'prescription'
            ? (t('This is a prescription, not a test report'), askRight)
            : type == 'not_medical' || detected.isEmpty
                ? (t("This doesn't look like a test report"), askRight)
                : (t('This isn’t the #1 report', test), '${t('We found #1 in it.', detected.join(', '))} $askRight');
    final retry = await openSheet<bool>(
      context,
      (c) => MpSheet(
        title: title,
        subtitle: body,
        child: VGap(
          gap: 8,
          children: [
            MpButton(readable ? 'Upload the right report' : 'Try again', onTap: () => Navigator.pop(c, true)),
            MpButton(readable ? 'Keep it as a separate report' : 'Keep it — my doctor will check', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, false)),
          ],
        ),
      ),
    );
    if (!mounted) return false;
    if (retry == false) return true; // kept: it stays in Records for what it is
    // Try again (or closed the sheet): this file goes, the sheet stays open for the right one.
    await Api.I.delete('/api/patient/records/$recordId').catchError((_) => null);
    p3RecordsChanged.value++;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(20),
            const P2SheetHeader(
              title: 'Add a record',
              subtitle: 'We read it for you, summarise it in simple words and flag anything out of range.',
              subtitleHeight: 1.45,
            ),
            const Gap(20),

            if (_forTest == null) ...[
              // What are you adding?
              Text('What are you adding?', style: tx(14, w: w600)),
              const Gap(8),
              P2Segmented(
                options: const ['Prescription', 'Test result'],
                index: _kind,
                onChanged: (i) => setState(() => _kind = i),
              ),
            ] else
              // The doctor's test this report is for.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MpIconTile(I.flask, size: 40, iconSize: 20, radius: 12, bg: MP.white, fg: MP.primary),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('REPORT FOR', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                          const Gap(2),
                          Text(_forTest!, style: tx(16, w: w700)),
                          const Gap(4),
                          Text(
                            [
                              if (_args['doctorName'] is String) tr(context, 'Asked by #1.').replaceFirst('#1', '${_args['doctorName']}'),
                              tr(context, 'We read the report to check it’s this test — the file name doesn’t matter.'),
                            ].join(' '),
                            style: tx(13, c: MP.ink2, h: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Gap(20),

            // Take photo · Gallery · PDF file
            Row(
              children: [
                for (var i = 0; i < _sources.length; i++) ...[
                  if (i > 0) const Gap(8),
                  Expanded(
                    child: P2Box(
                      onTap: _uploading ? null : () => _pick(i),
                      label: _sources[i].$2,
                      height: 104,
                      radius: 16,
                      color: MP.white,
                      border: MP.lineStrong,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MpIconTile(_sources[i].$1, size: 44, radius: 12, iconSize: 22),
                          const Gap(10),
                          Text(_sources[i].$2, style: tx(14, w: w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_uploading) ...[
              const Gap(12),
              const LinearProgressIndicator(minHeight: 3, color: MP.primary, backgroundColor: MP.fill),
            ],
            const Gap(20),

            if (!isLive)
              const P2ShareDoctors(title: 'Share with', doctors: _doctors)
            else if (data != null && _forPatient == null)
              P3ShareDoctors(
                title: 'Share with',
                doctors: _liveDoctors,
                selected: _shareWith,
                onChanged: (s) => setState(() => _shareWith = s),
                onAdd: (d) => setState(() {
                  _liveDoctors = [..._liveDoctors.where((x) => x.id != d.id), d];
                  _shareWith = {..._shareWith, d.id};
                }),
              ),
            if (!isLive || (data != null && _forPatient == null)) const Gap(20),

            Row(
              children: [
                // 16px svg without flex-shrink: 0 — the wrapping text squeezes it to 12px in the design.
                const Ico(I.lock, size: 12, color: MP.ink3),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Only you and the doctors you pick can see it. You can stop sharing any time.',
                    style: tx(13, c: MP.ink3),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }
}

import 'old_rx_sheet.dart';
import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';
import 'signature_gate.dart';
import 'patient_picker.dart';
import '../../data/rx_pdf.dart';
import '../../widgets/i18n.dart';

/// Design: Prescriptions.dc.html — "Prescriptions" (Priya Sharma's list).
/// Live: args {'prescriptionId'} and/or {'patientId'} → GET /api/prescriptions/:id
/// and GET /api/patients/:id/prescriptions (latest first). "Download PDF"
/// opens the signed file link; an unsent prescription from this clinic can be
/// sent with POST /api/prescriptions/:id/send.
class PrescriptionsScreen extends StatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  State<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

/// One prescription card.
typedef _Rx =
    ({
      String? id,
      String date,
      bool scanned,
      String byline,
      String dx,
      String meds,
      String labs,
      String follow,
      String list,
      String fileTitle,
      String fileMeta,
      String? url,
      bool sendable,
    });

class _PrescriptionsScreenState extends State<PrescriptionsScreen> with LiveData {
  static const _issued = [
    (
      date: '29 Sep 2026',
      dx: 'Type 2 diabetes mellitus, PCOS',
      meds: '3',
      labs: '3',
      follow: '29 Oct',
      list: 'Metformin 500 mg, Glimepiride 2 mg, Atorvastatin 10 mg',
    ),
    (
      date: '12 Mar 2026',
      dx: 'Type 2 diabetes mellitus, dyslipidaemia',
      meds: '2',
      labs: '2',
      follow: '12 Jun',
      list: 'Metformin 500 mg, Atorvastatin 10 mg',
    ),
  ];

  static final List<_Rx> _sample = [
    for (final rx in _issued)
      (
        id: null,
        date: rx.date,
        scanned: false,
        byline: 'Dr. Arjun Sen · City Care Clinic, Salt Lake',
        dx: rx.dx,
        meds: rx.meds,
        labs: rx.labs,
        follow: rx.follow,
        list: rx.list,
        fileTitle: '',
        fileMeta: '',
        url: null,
        sendable: false,
      ),
    (
      id: null,
      date: '12 Jan 2026',
      scanned: true,
      byline: 'Paper prescription · filed by Dr. Arjun Sen',
      dx: '',
      meds: '',
      labs: '',
      follow: '',
      list: '',
      fileTitle: 'Prescription, 12 Jan 2026',
      fileMeta: 'Photo from camera · 1 page',
      url: null,
      sendable: false,
    ),
  ];

  @override
  Future<Object?> fetch() async {
    final args = Nav.args<Map>(context) ?? const {};
    final rxId = args['prescriptionId'] as String?;
    var patientId = args['patientId'] as String?;
    Map<String, dynamic>? rx;
    if (rxId != null) {
      rx = (await Api.I.get('/api/prescriptions/$rxId') as Map).cast<String, dynamic>();
      patientId ??= rx.str('patientId');
    }
    if (!mounted) throw const ApiException(400, 'NO_PATIENT', 'Choose a patient');
    patientId = await patientOrPick(context, patientId, title: 'Prescriptions for…');
    final r = await Future.wait([
      Api.I.get('/api/patients/$patientId/prescriptions'),
      Api.I.get('/api/patients/$patientId'),
      Api.I.get('/api/locations').catchError((_) => const {}),
    ]);
    final list = (r[0] as Map).cast<String, dynamic>();
    var items = list.list('items');
    // The one just opened, in case the list was read before it was saved.
    if (rx != null && !items.any((x) => x.str('id') == rxId)) items = [rx, ...items];
    return {
      'items': items,
      'patient': (r[1] as Map).cast<String, dynamic>().obj('patient'),
      'locations': r[2] is Map ? (r[2] as Map).cast<String, dynamic>().list('items') : const [],
    };
  }

  String get _patientName => data == null ? 'Priya Sharma' : data!.obj('patient').str('name');

  /// Files a prescription written on paper (here, or an old one from another doctor) into the
  /// patient's record: its pages, the date written on it and who wrote it.
  Future<void> _filePaper(String source) async {
    if (!isLive) {
      toast(context, source == 'camera' ? 'Opening camera' : source == 'gallery' ? 'Opening gallery' : 'Choose a PDF to file');
      return;
    }
    final filed = await fileOldPrescription(context, patientId: data!.obj('patient').str('id'), source: source);
    if (filed && mounted) reload(quiet: true);
  }

  Map<String, dynamic> _raw(String? id) => data?.list('items').where((x) => x.str('id') == id).firstOrNull ?? const {};

  /// "Cancelled" / "Replaced" on an issued prescription that no longer stands.
  String? _badge(_Rx rx) => switch (_raw(rx.id).str('status')) {
        'cancelled' => 'Cancelled',
        'amended' => 'Replaced',
        _ => null,
      };

  /// Correct (a new draft that replaces this one), repeat (the same medicines today), or cancel.
  Future<void> _more(_Rx rx) async {
    final x = _raw(rx.id);
    final mine = x.str('doctorId') == '${Session.I.user['id']}';
    final standing = x.str('status', 'issued') == 'issued';
    final pick = await openSheet<String>(
      context,
      (c) => MpSheet(
        title: tr(context, 'Prescription, #1').replaceFirst('#1', rx.date),
        showClose: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mine && standing) ...[MpButton('Correct this prescription', onTap: () => Navigator.pop(c, 'amend')), const SizedBox(height: 10)],
          MpButton('Repeat for today', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, 'repeat')),
          if (mine && standing) ...[const SizedBox(height: 10), MpButton('Cancel prescription', kind: MpBtn.dangerSoft, onTap: () => Navigator.pop(c, 'cancel'))],
          if (!mine && standing) ...[const SizedBox(height: 10), Text('Only the doctor who wrote it can correct or cancel it.', style: tx(13, c: MP.ink2))],
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == 'cancel') {
      final reason = TextEditingController();
      final ok = await openSheet<bool>(
        context,
        (c) => MpSheet(
          title: 'Cancel this prescription?',
          subtitle: 'Its medicines stop and the patient is told not to take them. It stays in the record, marked cancelled.',
          showClose: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MpInput(controller: reason, label: 'Why', hint: 'E.g. Written for the wrong patient', height: 52),
            const SizedBox(height: 14),
            MpButton('Cancel prescription', kind: MpBtn.danger, onTap: () => Navigator.pop(c, true)),
          ]),
        ),
      );
      if (ok != true || !mounted) return;
      if (reason.text.trim().isEmpty) return toast(context, 'Say why it is cancelled');
      final res = await runAction(context, () => Api.I.post('/api/prescriptions/${rx.id}/cancel', {'reason': reason.text.trim()}));
      if (res == null || !mounted) return;
      toast(context, 'Prescription cancelled · the patient is told to stop those medicines');
      reload(quiet: true);
      return;
    }
    final res = await runAction(context, () => Api.I.post('/api/prescriptions/${rx.id}/$pick', const {}));
    if (res is! Map || !mounted) return;
    toast(context, pick == 'amend' ? 'Make the changes, then issue: it replaces the old one' : 'The same medicines, ready to change and issue');
    await Nav.go(context, 'Consult-Page', args: {'consultationId': '${res['id'] ?? res['_id']}', 'patientId': x.str('patientId')});
    if (mounted) reload(quiet: true);
  }

  List<_Rx> get _rows {
    final d = data;
    if (d == null) return _sample;
    final places = {for (final l in d.list('locations')) l.str('id'): l.str('shortName', l.str('name'))};
    final practice = Session.I.activeMembership?['practiceName'] as String? ?? '';
    return [for (final x in d.list('items')) _fromApi(x, places, practice)];
  }

  _Rx _fromApi(Map<String, dynamic> x, Map<String, String> places, String practice) {
    final at = F.date(x['issuedAt']) ?? F.date(x['createdAt']);
    final date = at == null ? '' : d7Date(at).substring(5);
    final ours = x.str('practiceId') == Session.I.practiceId;
    final doctor = x.str('doctorName');
    final loc = places[x.str('locationId')] ?? '';
    final place = ours ? [practice, loc].where((s) => s.isNotEmpty).join(', ') : '';
    final file = x['file'] is Map ? x.obj('file') : const <String, dynamic>{};
    final scanned = x.str('kind') == 'scanned';
    final items = x.list('items');
    final follow = F.date(x['followUpDate']);
    final pages = file.numOr('pages', 1).toInt();
    return (
      id: x.str('id'),
      date: date,
      scanned: scanned,
      byline:
          scanned
              ? [
                x['fromElsewhere'] == true
                    ? [tr(context, 'Old prescription'), if (x.str('sourceName').isNotEmpty) x.str('sourceName')].join(' · ')
                    : x.str('source') == 'this_clinic' ? 'Paper prescription' : 'Shared by the patient',
                if (doctor.isNotEmpty && x['fromElsewhere'] != true) 'filed by $doctor',
              ].join(' · ')
              : [
                if (doctor.isNotEmpty) doctor,
                if (place.isNotEmpty) place else if (!ours) 'Another clinic',
              ].join(' · '),
      dx: x.str('diagnosisSummary', '–'),
      meds: '${items.length}',
      labs: '${(x['tests'] as List? ?? const []).length}',
      follow: follow == null ? '–' : F.dayMonth(follow),
      list: [for (final i in items) [i.str('name'), i.str('strength')].where((s) => s.isNotEmpty).join(' ')].join(', '),
      fileTitle: 'Prescription, $date',
      fileMeta: [
        file.str('mimeType').contains('pdf') ? 'PDF' : 'Photo',
        '$pages ${pages == 1 ? 'page' : 'pages'}',
      ].join(' · '),
      url: file['url'] is String ? file.str('url') : null,
      // Only roles that prescribe can send (the front desk sees the prescription only).
      sendable: ours && !scanned && x['sentAt'] == null && Session.I.can('prescribe'),
    );
  }

  Future<void> _download(_Rx rx) async {
    if (!isLive) {
      toast(context, 'Downloading PDF · ${rx.date}');
      return;
    }
    final url = rx.url;
    if (url == null) {
      toast(context, 'No PDF for this prescription yet');
      return;
    }
    // Saves to Downloads › MedPin (fresh link; older PDFs are redrawn in the current layout).
    await RxPdf.download(context, rx.id);
  }

  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _send(_Rx rx) async {
    final ok = await withSignature(context, () => Api.I.post('/api/prescriptions/${rx.id}/send', const {}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Prescription sent to ${F.firstName(_patientName)}');
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final rows = _rows;
    return MpPage(
      header: _Header(name: placeholder == null ? _patientName : ''),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          // File a paper prescription
          MpCard(
            child: VGap(
              gap: 16,
              children: [
                const D7Title('File a paper prescription', sub: 'Scan or upload one written on paper'),
                Row(
                  children: [
                    Expanded(child: _UploadButton(I.camera, 'Camera', onTap: () => _filePaper('camera'))),
                    const SizedBox(width: 8),
                    Expanded(child: _UploadButton(I.image, 'Gallery', onTap: () => _filePaper('gallery'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _UploadButton(I.fileText, 'PDF', onTap: () => _filePaper('pdf')),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              rows.isEmpty
                  ? 'NO PRESCRIPTIONS YET'
                  : '${rows.length} ${rows.length == 1 ? 'PRESCRIPTION' : 'PRESCRIPTIONS'} · LATEST FIRST',
              style: tx(12, w: w600, h: 1.35, em: 0.06, c: MP.ink3),
            ),
          ),

          for (final rx in rows)
            if (!rx.scanned)
              _RxCard(
                date: rx.date,
                byline: rx.byline,
                badge: _badge(rx),
                onMore: isLive && rx.id != null ? () => _more(rx) : null,
                onDownload: () => _download(rx),
                onSend: rx.sendable && _badge(rx) == null ? () => _send(rx) : null,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DIAGNOSIS', style: tx(12, w: w600, h: 1.35, em: 0.06, c: MP.ink3)),
                      const SizedBox(height: 4),
                      Text(rx.dx, style: tx(16, h: 1.5)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MpGrid(
                        columns: 3,
                        children: [
                          _Stat(rx.meds, 'Medicines'),
                          _Stat(rx.labs, 'Lab tests'),
                          _Stat(rx.follow, 'Follow-up'),
                        ],
                      ),
                      if (rx.list.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(rx.list, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2, h: 1.45)),
                      ],
                    ],
                  ),
                ],
              )
            else
              // Scanned paper prescription
              _RxCard(
                date: rx.date,
                scanned: true,
                byline: rx.byline,
                onDownload: () => _download(rx),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Ico(I.fileText, size: 22, color: MP.ink2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rx.fileTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w600)),
                              const SizedBox(height: 2),
                              Text(rx.fileMeta, style: tx(13, c: MP.ink3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// 64px bar: back + "Prescriptions" (20/700) over "Priya Sharma" (14/1.45).
class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      color: MP.bg,
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prescriptions', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(20, w: w700, h: 1.25)),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 48px #EBF1FB tile button: 18px icon, 6px gap, 15/600 label.
class _UploadButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _UploadButton(this.icon, this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      color: MP.primarySoft,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Ico(icon, size: 18, color: MP.primary),
                  const SizedBox(width: 6),
                  Text(label, style: tx(15, w: w600, c: MP.primary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prescription card: date (+ Scanned tag), byline, [children], Download PDF.
class _RxCard extends StatelessWidget {
  final String date;
  final String byline;
  final bool scanned;
  final List<Widget> children;
  final VoidCallback onDownload;

  /// Live: send an unsent prescription to the patient's chat.
  final VoidCallback? onSend;
  const _RxCard({
    required this.date,
    required this.byline,
    this.scanned = false,
    required this.children,
    required this.onDownload,
    this.onSend,
    this.badge,
    this.onMore,
  });

  /// "Cancelled" / "Replaced" (it no longer stands); null for an issued one.
  final String? badge;

  /// Correct / repeat / cancel (the doctor's own issued prescription).
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${scanned ? 'Scanned prescription' : 'Prescription'}, $date',
      child: MpCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: VGap(
          gap: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(date, style: tx(20, w: w700, h: 1.25, tab: true)),
                    if (scanned) ...[const SizedBox(width: 8), const MpBadge.grey('Scanned', weight: w600)],
                    if (badge != null) ...[const SizedBox(width: 8), MpBadge.grey(badge!, weight: w600)],
                    if (onMore != null) ...[const Spacer(), MpIconButton(I.moreV, label: 'Correct, repeat or cancel', color: MP.ink2, onTap: onMore)],
                  ],
                ),
                const SizedBox(height: 2),
                Text(byline, style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
            ...children,
            D7Ruled(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  D7Btn(
                    'Download PDF',
                    icon: I.download,
                    height: 44,
                    radius: 8,
                    padding: EdgeInsets.zero,
                    onTap: onDownload,
                  ),
                  if (onSend != null) ...[
                    const Spacer(),
                    D7Btn('Send to patient', height: 44, radius: 8, padding: EdgeInsets.zero, onTap: onSend),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// #F7F9FC stat tile: 16/700 value over a 13px label.
class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: tx(16, w: w700, tab: true)),
          const SizedBox(height: 2),
          Text(label, style: tx(13, c: MP.ink2)),
        ],
      ),
    );
  }
}

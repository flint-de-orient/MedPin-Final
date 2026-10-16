import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/file_view.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'signature_gate.dart';

/// Doctor · Prescription letterhead and signature (from My profile).
/// Live data: GET /api/doctor/profile (signature), GET /api/doctor/locations
/// (each clinic's letterhead); POST /api/doctor/profile/signature.
/// The letterhead itself (logo, printed name, clinic name / address / phone)
/// is set per clinic in Clinic-Editor by the owner; the doctor's lines
/// (qualifications, headline, registration) come from Professional details.
/// "Preview" draws the real prescription PDF with it
/// (GET /api/doctor/letterhead/preview?locationId=).
class ProfileSignatureScreen extends StatefulWidget {
  const ProfileSignatureScreen({super.key});

  @override
  State<ProfileSignatureScreen> createState() => _ProfileSignatureScreenState();
}

class _ProfileSignatureScreenState extends State<ProfileSignatureScreen> with LiveData {
  bool _sampleSigned = true;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([Api.I.get('/api/doctor/profile'), Api.I.get('/api/doctor/locations')]);
    return {'profile': r[0], 'locations': r[1]};
  }

  @override
  void dispose() {
    _busy.dispose();
    _previewing.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _p => data!.obj('profile');
  String get _name => data == null ? 'Dr. Arjun Sen' : _p.str('displayName', Session.I.name);
  String? get _signatureUrl {
    if (data == null) return null;
    final u = _p.obj('signature')['url'];
    return u is String && u.isNotEmpty ? u : null;
  }

  bool get _signed => data == null ? _sampleSigned : _signatureUrl != null;

  /// The signature checker's last result ({status, issues, readsAs, by}).
  Map<String, dynamic> get _check => data == null ? const {'status': 'ok', 'by': 'image'} : _p.obj('signatureCheck');
  bool _rechecking = false;
  bool _autoChecked = false; // only once, even if the check fails

  /// A signature added before the checker existed is checked once, here.
  Future<void> _recheck({bool quiet = false}) async {
    if (!isLive || _rechecking) return;
    setState(() => _rechecking = true);
    try {
      await Api.I.post('/api/doctor/profile/signature/recheck');
      if (mounted) await reload(quiet: true);
    } on ApiException catch (e) {
      if (!quiet && mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _rechecking = false);
    }
  }

  Widget _checkResult() {
    final c = _check;
    if (isLive && _signed && c.isEmpty && !_autoChecked) {
      _autoChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recheck(quiet: true));
    }
    if (!_rechecking && c.isEmpty) {
      return Row(children: [
        Expanded(child: Text('Not checked yet', style: tx(14, c: MP.ink2))),
        D4TextLink('Check now', onTap: () => _recheck()),
      ]);
    }
    if (_rechecking) {
      return Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const Gap(10),
        Expanded(child: Text('Checking your signature…', style: tx(14, c: MP.ink2))),
      ]);
    }
    final issues = c.list('issues');
    final ok = c['status'] == 'ok' && issues.isEmpty;
    final readsAs = c.str('readsAs');
    final at = F.date(c['checkedAt']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ok ? MP.greenSoft : MP.amberSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Ico(ok ? I.check : I.alert, size: 18, color: ok ? MP.green : MP.amber, stroke: 2.2),
              const Gap(10),
              Expanded(child: Text(ok ? 'Signature checked · looks good' : 'Signature checked · please look', style: tx(15, w: w600))),
            ],
          ),
          for (final i in issues) ...[const Gap(8), Text(i.str('message'), style: tx(14, c: MP.ink, h: 1.4))],
          if (ok && readsAs.isNotEmpty) ...[const Gap(6), Text('Reads as “$readsAs”', style: tx(13, c: MP.ink2))],
          const Gap(6),
          Row(
            children: [
              Expanded(
                child: Text(
                  [c.str('by') == 'image+ai' ? 'Checked by MedPin AI' : 'Image check', if (at != null) F.ago(at)].join(' · '),
                  style: tx(12, c: MP.ink3),
                ),
              ),
              if (isLive) D4TextLink('Check again', onTap: () => _recheck()),
            ],
          ),
        ],
      ),
    );
  }

  /// The clinics this doctor practises at: (location id, name, letterhead set?, location).
  List<(String, String, bool, Map<String, dynamic>)> get _clinics {
    if (data == null) return const [('', 'City Care Clinic — Salt Lake', true, {})];
    return [
      for (final dl in data!.list('locations'))
        if (dl['locationId'] is Map && dl['status'] != 'ended' && dl.obj('locationId')['status'] != 'inactive')
          () {
            final l = dl.obj('locationId');
            final lh = l.obj('letterhead');
            final set = lh['logo'] != null || lh.str('doctorNamePrinted').isNotEmpty;
            return (l.str('id', l.str('_id')), l.str('name', 'Clinic'), set, l);
          }(),
    ];
  }

  /// What the prescription prints at [loc], by the same rules as the PDF
  /// (services/rxpdf.js): the clinic's printed name wins over yours; your
  /// registration wins over the clinic's fallback number.
  ({String name, String quals, String headline, String reg, String clinic, String address, String phone, bool logo}) _prints(Map<String, dynamic> loc) {
    final lh = loc.obj('letterhead');
    final p = data == null ? const <String, dynamic>{} : _p;
    final quals = [for (final q in p.list('qualifications')) q.str('name')].where((s) => s.isNotEmpty).join(', ');
    final r = p.obj('registration');
    final council = r.str('council', r.str('councilShort'));
    return (
      name: lh.str('doctorNamePrinted').isNotEmpty ? lh.str('doctorNamePrinted') : _name,
      quals: quals.isNotEmpty ? quals : p.str('degreesSummary', lh.str('tagline')),
      headline: p.str('headline'),
      reg: r.str('number').isNotEmpty
          ? 'Reg. No. ${r.str('number')}${council.isEmpty ? '' : ' · $council'}'
          : (lh.str('registrationNo').isEmpty ? '' : 'Reg. No. ${lh.str('registrationNo')}'),
      clinic: loc.str('name'),
      address: [
        loc.str('address'),
        [loc.str('area'), loc.str('city')].where((s) => s.isNotEmpty).join(', '),
        loc.str('pincode'),
      ].where((s) => s.isNotEmpty).join(', '),
      phone: loc.str('phone', loc.str('patientPhone')),
      logo: lh['logo'] != null,
    );
  }

  final _previewing = ValueNotifier<String?>(null);

  /// The real prescription PDF for a sample patient, with this clinic's letterhead.
  Future<void> _preview(String locationId) async {
    if (!isLive) return toast(context, 'Preparing the preview…');
    if (_previewing.value != null) return;
    _previewing.value = locationId;
    try {
      final r = await Api.I.get('/api/doctor/letterhead/preview', query: {if (locationId.isNotEmpty) 'locationId': locationId});
      final f = ReportFile.fromApi(r);
      if (!mounted) return;
      if (f == null) return toast(context, 'No file to open');
      await openFileView(context, f, title: 'Letterhead preview');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      _previewing.value = null;
    }
  }

  Widget _printed(Map<String, dynamic> loc) {
    final x = data == null
        ? (name: 'Dr. Arjun Sen', quals: 'MBBS, MD (Medicine)', headline: 'Diabetologist · Internal medicine', reg: 'Reg. No. 64213 · WBMC', clinic: 'City Care Clinic — Salt Lake', address: 'DD-24, Sector 1, Salt Lake, Kolkata 700064', phone: '033 4012 5678', logo: true)
        : _prints(loc);
    final missing = [if (!x.logo) 'logo', if (x.reg.isEmpty) 'registration number', if (x.phone.isEmpty) 'clinic phone'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: MP.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(x.name, style: tx(15, w: w700, c: MP.primary)),
          if (x.quals.isNotEmpty) Text(x.quals, style: tx(13, c: MP.ink2)),
          if (x.headline.isNotEmpty) Text(x.headline, style: tx(13, c: MP.ink2)),
          if (x.reg.isNotEmpty) Text(x.reg, style: tx(13, w: w600)),
          const Gap(8),
          Text(x.clinic, style: tx(13, w: w700)),
          if (x.address.isNotEmpty) Text(x.address, style: tx(13, c: MP.ink2)),
          if (x.phone.isNotEmpty) Text('Ph. ${x.phone}', style: tx(13, c: MP.ink2, tab: true)),
          if (missing.isNotEmpty) ...[const Gap(8), Text('Not on the letterhead yet: ${F.joinAnd(missing)}', style: tx(12, c: MP.amber))],
        ],
      ),
    );
  }

  Future<void> _upload() async {
    if (!isLive) {
      setState(() => _sampleSigned = true);
      toast(context, 'Signature saved · printed on every prescription');
      return;
    }
    // A photo of the signature on white paper, checked and cleaned by the server.
    if (await chooseAndUploadSignature(context, busy: _busy) && mounted) reload(quiet: true);
  }

  Future<void> _openClinic(String locationId) async {
    if (!isLive || locationId.isEmpty) {
      Nav.go(context, 'Clinic-Editor');
      return;
    }
    await Nav.go(context, 'Clinic-Editor', args: {'locationId': locationId});
    if (mounted) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    return MpPage(
      header: const D4Header('Letterhead and signature', subtitle: 'Printed on every prescription'),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              D4Card(
                children: [
                  D4CardTitle('Digital signature', action: _signed ? 'Replace' : null, onAction: _upload),
                  if (_signed)
                    Semantics(
                      image: true,
                      label: 'Signature preview as printed',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: MP.line)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 56,
                              child: _signatureUrl != null
                                  ? Image.network(_signatureUrl!, width: 176, height: 56, fit: BoxFit.contain, alignment: Alignment.centerLeft)
                                  : Align(alignment: Alignment.centerLeft, child: Text(_name, style: tx(24, w: w600, c: MP.primary))),
                            ),
                            Container(height: 1, margin: const EdgeInsets.only(top: 4), color: MP.line),
                            const Gap(8),
                            Text(_name, style: tx(14, w: w600, h: 20 / 14)),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Ico(I.alert, size: 18, color: MP.amber),
                          const Gap(10),
                          Expanded(child: Text('Add your signature to issue prescriptions. They can\'t be sent without it.', style: tx(14, c: MP.ink, h: 1.4))),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _busy,
                      builder: (_, busy, _) => MpButton(busy ? 'Uploading…' : 'Add signature', icon: I.cameraAlt, onTap: busy ? null : _upload),
                    ),
                  ],
                  if (_signed) _checkResult(),
                  const D4Note('Sign on plain white paper and take a clear photo, or choose a PNG with a transparent background. MedPin checks it and cleans up the background before printing.'),
                ],
              ),
              D4Card(
                children: [
                  const D4CardTitle('Letterhead'),
                  const D4Note('What prints at the top of your prescriptions. Each clinic has its own logo, name, address and phone; your qualifications and registration come from Professional details.'),
                  for (final c in _clinics) ...[
                    Tap(
                      onTap: () => _openClinic(c.$1),
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(child: D4TitleSub(c.$2, c.$3 ? 'Letterhead set' : 'Not set yet · uses the clinic name')),
                          const Gap(12),
                          const Ico(I.chevronRight, size: 18, color: MP.ink3),
                        ],
                      ),
                    ),
                    _printed(c.$4),
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        ValueListenableBuilder<String?>(
                          valueListenable: _previewing,
                          builder: (_, busy, _) => D4TextLink(busy == c.$1 ? 'Preparing…' : 'Preview prescription', onTap: () => _preview(c.$1)),
                        ),
                        D4TextLink(Session.I.isOwner || !isLive ? 'Edit clinic letterhead' : 'View clinic letterhead', onTap: () => _openClinic(c.$1)),
                        D4TextLink('Your details', onTap: () => Nav.go(context, 'Profile-Professional')),
                      ],
                    ),
                  ],
                  if (_clinics.isEmpty) const D4Note('Add a clinic first.'),
                ],
              ),
            ],
          ),
    );
  }
}

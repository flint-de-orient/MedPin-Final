import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Doctor · Prescription letterhead and signature (from My profile).
/// Live data: GET /api/doctor/profile (signature), GET /api/doctor/locations
/// (each clinic's letterhead); POST /api/doctor/profile/signature.
/// The letterhead itself (logo, tagline, printed name) is set per clinic in
/// Clinic-Editor by the owner.
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

  /// The clinics this doctor practises at: (location id, name, letterhead set?).
  List<(String, String, bool)> get _clinics {
    if (data == null) return const [('', 'City Care Clinic — Salt Lake', true)];
    return [
      for (final dl in data!.list('locations'))
        if (dl['locationId'] is Map)
          () {
            final l = dl.obj('locationId');
            final lh = l.obj('letterhead');
            return (l.str('id', l.str('_id')), l.str('name', 'Clinic'), lh.isNotEmpty && (lh['logo'] != null || lh.str('tagline').isNotEmpty));
          }(),
    ];
  }

  Future<void> _upload() async {
    if (!isLive) {
      setState(() => _sampleSigned = true);
      toast(context, 'Signature saved · printed on every prescription');
      return;
    }
    // A photo of the signature on white paper (or a PNG with a clear background).
    final file = await Files.chooseSource(context, title: 'Digital signature', allowPdf: false);
    if (file == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.upload('/api/doctor/profile/signature', files: {'file': [file]}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Signature saved · printed on every prescription');
    reload(quiet: true);
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
                  const D4Note('Sign on plain white paper and take a clear photo, or choose a PNG with a transparent background.'),
                ],
              ),
              D4Card(
                children: [
                  const D4CardTitle('Letterhead'),
                  const D4Note('Logo, clinic name, tagline and the name printed at the top. Each clinic has its own.'),
                  for (final c in _clinics)
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
                  if (_clinics.isEmpty) const D4Note('Add a clinic first.'),
                ],
              ),
            ],
          ),
    );
  }
}

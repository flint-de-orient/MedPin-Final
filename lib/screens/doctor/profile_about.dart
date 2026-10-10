import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';
import '../../widgets/i18n.dart';

/// Doctor · About and photo — the bio and photo patients see before booking.
/// Live data: GET/PATCH /api/doctor/profile, POST /api/doctor/profile/photo.
class ProfileAboutScreen extends StatefulWidget {
  const ProfileAboutScreen({super.key});

  @override
  State<ProfileAboutScreen> createState() => _ProfileAboutScreenState();
}

class _ProfileAboutScreenState extends State<ProfileAboutScreen> with LiveData {
  static const _sampleBio =
      'I treat diabetes, thyroid and hormone problems, and help patients bring their sugar and BP into '
      'a healthy range with simple changes they can keep. I see patients at City Care Clinic in Salt Lake '
      'and New Town, and on video.';

  final _bio = TextEditingController(text: _sampleBio);
  bool _filled = false;
  bool _busy = false;

  @override
  Future<Object?> fetch() => Api.I.get('/api/doctor/profile');

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  String get _name => data?.str('displayName', 'Dr. Arjun Sen') ?? 'Dr. Arjun Sen';
  String get _headline => data?.str('headline', '') ?? 'Diabetologist · Internal medicine';
  String? get _photoUrl => (data?.obj('photo')['url']) as String?;

  Future<void> _save() async {
    if (!isLive) {
      d4Save(context);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => Api.I.patch('/api/doctor/profile', {'bio': _bio.text.trim()}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) d4Save(context);
  }

  Future<void> _changePhoto() async {
    if (!isLive) {
      toast(context, 'Photo updated');
      return;
    }
    final file = await Files.chooseSource(context, title: 'Profile photo', allowPdf: false);
    if (file == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.upload('/api/doctor/profile/photo', files: {'file': [file]}));
    if (ok == null || !mounted) return;
    toast(context, 'Photo updated');
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (data != null && !_filled) {
      _filled = true;
      _bio.text = data!.str('bio');
    }
    return MpPage(
      header: D4Header('About and photo', subtitle: 'What patients read before booking', onSave: placeholder == null ? _save : null),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              D4Card(
                children: [
                  const D4CardTitle('Profile photo'),
                  Row(
                    children: [
                      _Photo(url: _photoUrl, initials: F.initials(_name)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const D4Note('A clear, front-facing photo. Patients trust profiles with a photo more.'),
                            const SizedBox(height: 10),
                            D4TextLink(_photoUrl == null ? 'Add photo' : 'Change photo', onTap: _changePhoto),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              D4Card(
                children: [
                  const D4CardTitle('About you'),
                  D11Field(
                    'Bio',
                    _bio,
                    hint: 'What you treat, how you work with patients, where you practise',
                    maxLines: null,
                    maxLength: 2000,
                    caps: TextCapitalization.sentences,
                  ),
                  const D4Note('Plain words work best. Patients see this on your profile in the MedPin app.'),
                ],
              ),
              D4Card(
                children: [
                  const D4CardTitle('How patients see it'),
                  Row(
                    children: [
                      _Photo(url: _photoUrl, initials: F.initials(_name), size: 48),
                      const SizedBox(width: 12),
                      Expanded(child: D4TitleSub(_name, _headline.isEmpty ? null : _headline, weight: w700)),
                    ],
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _bio,
                    builder: (_, v, _) => Text(
                      v.text.trim().isEmpty ? 'Add a short bio so patients know how you can help.' : v.text.trim(),
                      style: tx(14, c: v.text.trim().isEmpty ? MP.ink3 : MP.ink, h: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
    );
  }
}

class _Photo extends StatelessWidget {
  final String? url;
  final String initials;
  final double size;
  const _Photo({required this.url, required this.initials, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: MP.primarySoft, shape: BoxShape.circle),
      child: Text(initials, style: tx(size / 3, w: w800, c: MP.primary)),
    );
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

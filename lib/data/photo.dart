import 'package:flutter/material.dart' hide Text;

import '../widgets/i18n.dart';
import '../widgets/mp.dart';
import 'api.dart';
import 'files.dart';
import 'live.dart';
import 'session.dart';

/// The signed-in person's profile photo link (null: show initials).
String? get myPhotoUrl {
  final u = Session.I.user['photoUrl'];
  return u is String && u.isNotEmpty ? u : null;
}

/// Picks a photo and saves it as the account's profile photo
/// (POST /api/me/photo). Returns true once saved.
Future<bool> changeMyPhoto(BuildContext context) async {
  final file = await Files.chooseSource(context, title: 'Profile photo', allowPdf: false);
  if (file == null || !context.mounted) return false;
  final res = await runAction(context, () => Api.I.upload('/api/me/photo', files: {'file': [file]}));
  if (res is! Map || !context.mounted) return false;
  await Session.I.adoptAccount(res.cast<String, dynamic>());
  if (context.mounted) toast(context, 'Photo updated');
  return true;
}

const _heroTag = 'my-profile-photo';

/// Removes the account's profile photo (DELETE /api/me/photo). True once removed.
Future<bool> removeMyPhoto(BuildContext context) async {
  final yes = await openSheet<bool>(
    context,
    (c) => MpSheet(
      title: 'Remove profile photo?',
      subtitle: 'Your initials show instead, for you, your clinic and patients.',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VGap(gap: 8, children: [
          MpButton('Remove photo', kind: MpBtn.danger, onTap: () => Navigator.pop(c, true)),
          MpButton('Keep it', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    ),
  );
  if (yes != true || !context.mounted) return false;
  final res = await runAction(context, () => Api.I.delete('/api/me/photo'));
  if (res is! Map || !context.mounted) return false;
  await Session.I.adoptAccount(res.cast<String, dynamic>());
  if (context.mounted) toast(context, 'Photo removed');
  return true;
}

/// The avatar was tapped / held: full-screen photo, or (no photo yet) choose one.
Future<void> _open(BuildContext context, String? photo) async {
  if (photo == null) {
    await changeMyPhoto(context);
    return;
  }
  await Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const MyPhotoViewer(),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// Full-screen view of your own profile photo (as WhatsApp / Google do): pinch or
/// double-tap to zoom, swipe down or Close to go back, and Change / Remove below.
/// Follows the session, so a new photo shows here at once.
class MyPhotoViewer extends StatefulWidget {
  const MyPhotoViewer({super.key});

  @override
  State<MyPhotoViewer> createState() => _MyPhotoViewerState();
}

class _MyPhotoViewerState extends State<MyPhotoViewer> {
  final _zoom = TransformationController();
  TapDownDetails? _tap;
  double _drag = 0;

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final at = _tap?.localPosition;
    if (_zoomed || at == null) {
      _zoom.value = Matrix4.identity();
    } else {
      const s = 2.5;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-at.dx * (s - 1), -at.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) {
        final photo = myPhotoUrl;
        final fade = (1 - (_drag.abs() / 300)).clamp(0.4, 1.0);
        return Scaffold(
          backgroundColor: Colors.black.withValues(alpha: fade),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      MpIconButton(I.close, label: 'Close', color: MP.white, onTap: () => Navigator.pop(context)),
                      const Gap(4),
                      Expanded(child: Text('Profile photo', style: tx(18, w: w600, c: MP.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                Expanded(
                  child: photo == null
                      ? Center(child: Text('No profile photo', style: tx(15, c: MP.white)))
                      : GestureDetector(
                          onDoubleTapDown: (d) => _tap = d,
                          onDoubleTap: _toggleZoom,
                          // Swipe down (not zoomed in) to close.
                          onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
                          onVerticalDragEnd: _zoomed
                              ? null
                              : (d) {
                                  if (_drag.abs() > 120 || (d.primaryVelocity ?? 0).abs() > 900) {
                                    Navigator.pop(context);
                                  } else {
                                    setState(() => _drag = 0);
                                  }
                                },
                          child: Transform.translate(
                            offset: Offset(0, _drag),
                            child: InteractiveViewer(
                              transformationController: _zoom,
                              minScale: 1,
                              maxScale: 5,
                              child: Center(
                                child: Hero(
                                  tag: _heroTag,
                                  child: Image.network(
                                    photo,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 48, width: 48, child: CircularProgressIndicator(color: MP.white, strokeWidth: 2)),
                                    errorBuilder: (_, _, _) => Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Text("Couldn't load the photo. Check your internet and try again.", textAlign: TextAlign.center, style: tx(15, c: MP.white, h: 1.4)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: MpButton('Change photo', onTap: () async {
                          await changeMyPhoto(context);
                        }),
                      ),
                      if (photo != null) ...[
                        const Gap(12),
                        Expanded(
                          child: MpButton('Remove', kind: MpBtn.secondary, onTap: () async {
                            if (await removeMyPhoto(context) && context.mounted) Navigator.pop(context);
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 72px profile avatar with the small camera button to change the photo.
class MyPhotoAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final double fontSize;
  final FontWeight weight;
  final VoidCallback? onChanged;
  final bool editable;
  const MyPhotoAvatar(this.initials, {super.key, this.size = 72, this.fontSize = 24, this.weight = w700, this.onChanged, this.editable = true});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) {
        final photo = myPhotoUrl;
        // Tap or hold the picture: see it full screen (zoom, change, remove). No photo yet: add one.
        final avatar = Semantics(
          button: true,
          label: photo == null ? 'Add a profile photo' : 'View profile photo',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(context, photo),
            onLongPress: () => _open(context, photo),
            child: Hero(
              tag: _heroTag,
              child: MpAvatar(initials, size: size, fontSize: fontSize, weight: weight, photo: photo),
            ),
          ),
        );
        if (!editable) return avatar;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                right: -2,
                bottom: -2,
                child: Semantics(
                  button: true,
                  label: 'Change photo',
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Tap(
                      onTap: () async {
                        if (await changeMyPhoto(context)) onChanged?.call();
                      },
                      radius: 999,
                      color: MP.primary,
                      border: MP.white,
                      borderWidth: 2,
                      child: const Center(child: Ico(I.cameraAlt, size: 14, color: MP.white, stroke: 2)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

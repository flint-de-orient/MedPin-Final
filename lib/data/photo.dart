import 'package:flutter/material.dart';

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
        final avatar = MpAvatar(initials, size: size, fontSize: fontSize, weight: weight, photo: myPhotoUrl);
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

import 'package:flutter/material.dart' hide Text;

import 'file_view.dart';
import 'i18n.dart';
import 'mp.dart';

/// A photo sent in a chat (patient or clinic side): the picture itself, not a
/// file card. Tap opens it full screen with pinch-zoom. The link stays the same
/// all day (server stableUrl), so the 4-second chat refresh reuses the cached
/// picture.
class ChatPhoto extends StatelessWidget {
  final String url;
  final String name;
  final String mime;
  final bool mine;

  /// Under the picture: "11:36 AM" (and "· Read" on your own).
  final String meta;

  /// Text sent with the photo, shown under it.
  final String? caption;
  const ChatPhoto({super.key, required this.url, this.name = '', this.mime = '', required this.mine, this.meta = '', this.caption});

  static const double _w = 240;
  static const double _h = 200;

  @override
  Widget build(BuildContext context) {
    final file = ReportFile(url: url, name: name, mime: mime);
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Open photo',
          child: GestureDetector(
            onTap: () => openFileView(context, file, title: 'Photo'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: _w,
                height: _h,
                color: MP.fill,
                child: Image.network(
                  url,
                  width: _w,
                  height: _h,
                  fit: BoxFit.cover,
                  // Decoded at the size shown, not the camera's full size.
                  cacheWidth: (_w * MediaQuery.devicePixelRatioOf(context)).round(),
                  gaplessPlayback: true,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))),
                  errorBuilder: (_, _, _) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Ico(I.image, size: 28, color: MP.ink3),
                      const Gap(6),
                      Text('Photo · tap to open', style: tx(13, c: MP.ink3)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (caption != null && caption!.trim().isNotEmpty) ...[
          const Gap(4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _w),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? MP.primary : MP.white,
                borderRadius: BorderRadius.circular(16),
                border: mine ? null : Border.all(color: MP.line),
              ),
              child: UserText(caption!, style: tx(15, h: 1.45, c: mine ? MP.white : MP.ink)),
            ),
          ),
        ],
        if (meta.isNotEmpty) ...[
          const Gap(4),
          Text(meta, style: tx(12, c: MP.ink3, tab: true)),
        ],
      ],
    );
  }
}

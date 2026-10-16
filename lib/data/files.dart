import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../widgets/mp.dart';
import 'api.dart';
import '../widgets/i18n.dart';

/// Picking photos and documents for upload (signature, logo, profile photo,
/// proofs, reports, chat attachments).
class Files {
  Files._();

  static final _images = ImagePicker();

  static String _imageMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  /// A photo from the camera or the gallery, resized for upload. Null if cancelled.
  static Future<UploadFile?> photo({required bool camera, double maxSide = 2000}) async {
    final x = await _images.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 85,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    return UploadFile(bytes, x.name, x.mimeType ?? _imageMime(x.name));
  }

  /// Several photos from the gallery at once (the pages of one report), up to [limit]. Empty if cancelled.
  static Future<List<UploadFile>> photos({double maxSide = 2000, int limit = 10}) async {
    final xs = await _images.pickMultiImage(maxWidth: maxSide, maxHeight: maxSide, imageQuality: 85, limit: limit);
    return [
      for (final x in xs.take(limit)) UploadFile(await x.readAsBytes(), x.name, x.mimeType ?? _imageMime(x.name)),
    ];
  }

  /// A PDF from the device. Null if cancelled.
  static Future<UploadFile?> pdf() => _pick(FileType.custom, const ['pdf']);

  /// A PDF or image file from the device. Null if cancelled.
  static Future<UploadFile?> document() => _pick(FileType.custom, const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);

  static Future<UploadFile?> _pick(FileType type, List<String> extensions) async {
    final f = await FilePicker.pickFile(type: type, allowedExtensions: extensions);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    final n = f.name.toLowerCase();
    final mime = n.endsWith('.pdf') ? 'application/pdf' : _imageMime(n);
    return UploadFile(bytes, f.name, mime);
  }

  /// "Take photo / Choose from gallery / Choose a PDF" sheet in the app's style.
  /// Returns the picked file or null.
  static Future<UploadFile?> chooseSource(BuildContext context, {String title = 'Add a file', bool allowPdf = true}) async {
    final choice = await openSheet<int>(
      context,
      (c) => MpSheet(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, icon, label) in [
              (0, I.cameraAlt, 'Take photo'),
              (1, I.image, 'Choose from gallery'),
              if (allowPdf) (2, I.fileText, 'Choose a PDF'),
            ])
              Tap(
                onTap: () => Navigator.pop(c, i),
                radius: 12,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      MpIconTile(icon, size: 40, iconSize: 20, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label, style: tx(16, w: w600))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return null;
    try {
      if (choice == 2) return await pdf();
      return await photo(camera: choice == 0);
    } catch (e) {
      if (context.mounted) toast(context, "Couldn't open ${choice == 0 ? 'the camera' : 'your files'}");
      return null;
    }
  }
}

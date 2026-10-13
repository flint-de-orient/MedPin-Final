import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/mp.dart';
import '../widgets/saved_note.dart';

/// Prescriptions, reports, exports and attachments: fetched into the app,
/// then opened in the phone's viewer ("Open") or handed to the share sheet so
/// it can be saved to Files / Downloads / Drive or sent ("Download").
class Downloads {
  Downloads._();

  /// Testing hook.
  static http.Client client = http.Client();

  /// A file served by MedPin (signed /files/… link), as opposed to a web or map link.
  static bool isFile(String? url) => url != null && (Uri.tryParse(url)?.path.startsWith('/files/') ?? false);

  static String _safeName(String name) => name.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();

  /// "Prescription-0012.pdf" from the link or a fallback.
  static String nameFor(String url, {String? name}) {
    if (name != null && name.trim().isNotEmpty) return _safeName(name.contains('.') ? name : '$name${_extOf(url)}');
    final last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? 'MedPin-file';
    return _safeName(last.isEmpty ? 'MedPin-file' : last);
  }

  static String _extOf(String url) {
    final p = Uri.tryParse(url)?.path ?? '';
    final dot = p.lastIndexOf('.');
    return dot > p.lastIndexOf('/') && dot >= 0 ? p.substring(dot) : '.pdf';
  }

  /// Downloads [url] into the app's cache (kept until the phone clears it).
  static Future<File> fetch(String url, {String? name}) async {
    final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode == 403) throw const DownloadException('This link has expired. Go back and open it again.');
    if (res.statusCode != 200) throw DownloadException("Couldn't download the file (${res.statusCode}).");
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}medpin');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${nameFor(url, name: name)}');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file;
  }

  /// Opens the file in the phone's viewer (PDF viewer, gallery…).
  static Future<void> open(BuildContext context, String? url, {String? name}) async {
    if (url == null || url.isEmpty) return toast(context, 'No file to open');
    if (kIsWeb) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    toast(context, 'Opening…');
    try {
      final file = await fetch(url, name: name);
      final r = await OpenFilex.open(file.path);
      if (r.type != ResultType.done && context.mounted) {
        // No app for this type: offer to save / send it instead.
        await share(context, url, name: name, file: file);
      }
    } on DownloadException catch (e) {
      if (context.mounted) toast(context, e.message);
    } on TimeoutException {
      if (context.mounted) toast(context, 'The download is taking too long. Please try again.');
    } catch (_) {
      if (context.mounted) toast(context, "Couldn't reach MedPin. Check your internet connection.");
    }
  }

  static const _channel = MethodChannel('medpin/downloads');

  /// Testing hook: replaces the Android save (path, name) → saved name.
  @visibleForTesting
  static Future<String?> Function(String path, String name)? saveOverride;

  /// "Download": saves the file to the phone (Downloads › MedPin on Android)
  /// and shows a small "Saved" note with Open. Where saving isn't possible
  /// (web, iPhone, Android 9 or older) the share sheet opens instead, which
  /// has "Save to Files".
  static Future<bool> save(BuildContext context, String? url, {String? name, String title = 'Downloaded'}) async {
    if (url == null || url.isEmpty) {
      toast(context, 'No file to download');
      return false;
    }
    if (kIsWeb) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return true;
    }
    final File file;
    try {
      file = await fetch(url, name: name);
    } on DownloadException catch (e) {
      if (context.mounted) toast(context, e.message);
      return false;
    } on TimeoutException {
      if (context.mounted) toast(context, 'The download is taking too long. Please try again.');
      return false;
    } catch (_) {
      if (context.mounted) toast(context, "Couldn't reach MedPin. Check your internet connection.");
      return false;
    }
    final fileName = file.uri.pathSegments.last;
    String? saved;
    try {
      if (saveOverride != null) {
        saved = await saveOverride!(file.path, fileName);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final r = await _channel.invokeMapMethod<String, dynamic>('save', {'path': file.path, 'name': fileName, 'mime': _mimeOf(fileName)});
        saved = r?['name'] as String?;
      }
    } catch (_) {
      saved = null;
    }
    if (!context.mounted) return false;
    if (saved == null) {
      await share(context, url, name: name, file: file);
      return false;
    }
    showSavedNote(context, title: title, detail: 'Downloads › MedPin · $saved', onOpen: () => OpenFilex.open(file.path));
    return true;
  }

  static String _mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.csv')) return 'text/csv';
    if (n.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (n.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  /// Saves / sends the file through the share sheet.
  static Future<void> share(BuildContext context, String? url, {String? name, File? file}) async {
    if (url == null || url.isEmpty) return toast(context, 'No file to download');
    if (kIsWeb) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    try {
      final f = file ?? await fetch(url, name: name);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], title: nameFor(url, name: name)));
    } on DownloadException catch (e) {
      if (context.mounted) toast(context, e.message);
    } catch (_) {
      if (context.mounted) toast(context, "Couldn't download the file. Please try again.");
    }
  }
}

class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
}

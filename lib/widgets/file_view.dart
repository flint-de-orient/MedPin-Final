import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../data/downloads.dart';
import 'i18n.dart';
import 'mp.dart';

/// A report or prescription file inside the app: the first page as a
/// thumbnail ([FilePreview]) and every page with pinch-zoom ([openFileView]).
/// PDFs are drawn by Android's own PdfRenderer (MainActivity "medpin/pdf");
/// photos are shown as they are. Elsewhere the phone's viewer opens instead.
class ReportFile {
  final String url;
  final String name;
  final String mime;
  const ReportFile({required this.url, this.name = '', this.mime = ''});

  /// A file from the API ({url, name, mimeType}); null without a link.
  static ReportFile? fromApi(Object? f) {
    if (f is! Map || f['url'] is! String || (f['url'] as String).isEmpty) return null;
    return ReportFile(url: f['url'] as String, name: '${f['name'] ?? ''}', mime: '${f['mimeType'] ?? ''}');
  }

  String get _lower => '${name.toLowerCase()} ${Uri.tryParse(url)?.path.toLowerCase() ?? ''}';
  bool get isPdf => mime == 'application/pdf' || _lower.contains('.pdf');
  bool get isImage => mime.startsWith('image/') || RegExp(r'\.(jpe?g|png|webp|heic)\b').hasMatch(_lower);

  /// Signed links change on every load; the stored file behind them doesn't.
  String get key => Uri.tryParse(url)?.path ?? url;
}

/// One drawn PDF page.
class PdfPageImage {
  final Uint8List png;
  final int pages;
  final double aspect; // height / width
  const PdfPageImage(this.png, this.pages, this.aspect);
}

class PdfPages {
  PdfPages._();
  static const _channel = MethodChannel('medpin/pdf');

  /// Drawn in the app (Android); elsewhere the phone's viewer opens the file.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static final _files = <String, Future<File>>{};
  static final _pages = <String, Future<PdfPageImage>>{};

  /// The file on the phone, downloaded once per app run.
  static Future<File> local(ReportFile f) {
    final hit = _files[f.key];
    if (hit != null) return hit;
    final future = Downloads.fetch(f.url, name: f.name.isEmpty ? null : f.name);
    _files[f.key] = future;
    future.catchError((Object _) {
      _files.remove(f.key); // try again next time (an expired link, no internet)
      return File('');
    });
    return future;
  }

  /// Page [page] (0-based) drawn [width] pixels wide.
  static Future<PdfPageImage> page(ReportFile f, int page, int width) {
    final k = '${f.key}#$page@$width';
    final hit = _pages[k];
    if (hit != null) return hit;
    final future = () async {
      final file = await local(f);
      final res = await _channel.invokeMapMethod<String, Object?>('render', {'path': file.path, 'page': page, 'width': width});
      if (res == null) throw PlatformException(code: 'PDF', message: "Couldn't open the PDF");
      final w = (res['width'] as num?)?.toDouble() ?? 1;
      final h = (res['height'] as num?)?.toDouble() ?? 1;
      return PdfPageImage(res['png'] as Uint8List, (res['pages'] as num?)?.toInt() ?? 1, h / w);
    }();
    _pages[k] = future;
    // Keep the cache small: the newest 24 pages.
    if (_pages.length > 24) _pages.remove(_pages.keys.first);
    future.catchError((Object _) {
      _pages.remove(k);
      return PdfPageImage(Uint8List(0), 0, 1);
    });
    return future;
  }
}

/// The first page of a file as a thumbnail (a white page with a soft border,
/// like the app's file cards); a page-count badge when there are more. Tap
/// opens [openFileView].
class FilePreview extends StatelessWidget {
  final ReportFile? file;
  final double width;
  final double height;
  final String title;
  final double radius;

  /// The report's other files (pages photographed one by one): tapping opens them all; the badge counts them.
  final List<ReportFile> more;
  const FilePreview({super.key, required this.file, this.width = 70, this.height = 94, this.title = 'Report', this.radius = 8, this.more = const []});

  Widget _badge(int n) => Positioned(
        right: 4,
        bottom: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: MP.ink.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(6)),
          child: Text('$n', style: tx(10, w: w700, c: MP.white, tab: true)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = file;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    Widget inner;
    if (f == null) {
      inner = const _Blank();
    } else if (f.isImage) {
      inner = Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            f.url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: (width * dpr).round(),
            errorBuilder: (_, _, _) => const _FileIcon(),
            loadingBuilder: (_, child, p) => p == null ? child : const _Loading(),
          ),
          if (more.isNotEmpty) _badge(more.length + 1),
        ],
      );
    } else if (f.isPdf && PdfPages.supported) {
      inner = FutureBuilder<PdfPageImage>(
        future: PdfPages.page(f, 0, (width * dpr).round().clamp(120, 900)),
        builder: (_, s) {
          if (s.hasError) return const _FileIcon();
          final p = s.data;
          if (p == null || p.png.isEmpty) return const _Loading();
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(p.png, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true),
              if (p.pages > 1 || more.isNotEmpty) _badge(more.isEmpty ? p.pages : more.length + 1),
            ],
          );
        },
      );
    } else {
      inner = const _FileIcon();
    }
    return Semantics(
      button: f != null,
      label: f == null ? null : 'Open $title',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: f == null ? null : () => openFilesView(context, [f, ...more], title: title),
        child: Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(radius), border: Border.all(color: MP.line)),
          child: inner,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: MP.bg,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MP.primary))),
      );
}

class _FileIcon extends StatelessWidget {
  const _FileIcon();
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MP.bg, child: Center(child: Ico(I.fileText, size: 22, color: MP.ink3)));
}

/// No file yet: the page outline the file cards always had.
class _Blank extends StatelessWidget {
  const _Blank();
  static Widget _bar(double height, double width, Color color) => FractionallySizedBox(
        widthFactor: width,
        child: Container(height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      );
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(6, 0.6, MP.lineStrong),
            const Gap(5),
            _bar(4, 1, MP.line),
            const Gap(5),
            _bar(4, 1, MP.line),
            const Gap(5),
            _bar(4, 0.8, MP.line),
          ],
        ),
      );
}

/// Opens the file inside the app: PDFs page by page, photos full screen, both
/// with pinch-zoom and Download / Share. Other files (or other phones) open in
/// the phone's own viewer.
Future<void> openFileView(BuildContext context, ReportFile f, {String title = 'Report'}) async {
  if ((f.isPdf && PdfPages.supported) || f.isImage) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _FileViewScreen(file: f, title: title)));
    return;
  }
  await Downloads.open(context, f.url, name: f.name.isEmpty ? title : f.name);
}

/// A report kept as several files (pages photographed one by one): one viewer, page by page.
Future<void> openFilesView(BuildContext context, List<ReportFile> files, {String title = 'Report'}) async {
  if (files.isEmpty) return;
  if (files.length == 1) return openFileView(context, files.first, title: title);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _FileViewScreen(file: files.first, files: files, title: title)));
}

class _FileViewScreen extends StatefulWidget {
  final ReportFile file;
  final List<ReportFile> files;
  final String title;
  const _FileViewScreen({required this.file, this.files = const [], required this.title});
  @override
  State<_FileViewScreen> createState() => _FileViewScreenState();
}

class _FileViewScreenState extends State<_FileViewScreen> {
  final _pageCtl = PageController();
  int _pages = 0;
  int _at = 0;
  String? _error;

  /// Several files: one page each (a photo, or a PDF's first page).
  bool get _many => widget.files.length > 1;
  ReportFile get _f => _many ? widget.files[_at.clamp(0, widget.files.length - 1)] : widget.file;
  ReportFile _fileAt(int i) => _many ? widget.files[i] : widget.file;
  int _pageAt(int i) => _many ? 0 : i;
  String get _name => _f.name.isNotEmpty ? _f.name : widget.title;

  @override
  void initState() {
    super.initState();
    if (_many) {
      _pages = widget.files.length;
    } else if (_f.isPdf) {
      // Page 1 tells how many pages there are.
      PdfPages.page(_f, 0, 1080).then((p) {
        if (mounted) setState(() => _pages = p.pages);
      }).catchError((Object e) {
        if (mounted) {
          setState(() => _error = e is DownloadException
              ? e.message
              : "Couldn't show this PDF here. It may be password-protected — open it in another app instead.");
        }
      });
    } else {
      _pages = 1;
    }
  }

  @override
  void dispose() {
    _pageCtl.dispose();
    super.dispose();
  }

  Widget _page(BuildContext context, int i) {
    final file = _fileAt(i);
    if (file.isImage) {
      return InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.network(file.url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const _FileIcon())),
      );
    }
    if (!PdfPages.supported) return const _FileIcon();
    final width = (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).round().clamp(600, 1600);
    return FutureBuilder<PdfPageImage>(
      future: PdfPages.page(file, _pageAt(i), width),
      builder: (_, s) {
        final p = s.data;
        if (s.hasError) return Center(child: Text(tr(context, "Couldn't show page #1").replaceFirst('#1', '${i + 1}'), style: tx(14, c: MP.ink2)));
        if (p == null || p.png.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary));
        return InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: 1 / p.aspect,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: MP.white, boxShadow: MPShadow.card),
                  child: Image.memory(p.png, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      MpIconButton(I.download, label: 'Download', color: MP.primary, onTap: () => Downloads.save(context, _f.url, name: _name)),
    ];
    return MpPage(
      scroll: false,
      header: Container(
        decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
        child: MpHeader(widget.title, subtitle: _pages > 1 ? tr(context, 'Page #1 of #2').replaceFirst('#1', '${_at + 1}').replaceFirst('#2', '$_pages') : null, background: MP.white, actions: actions),
      ),
      bottom: MpBottomBar(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: MpButton('Share', kind: MpBtn.secondary, icon: I.share, onTap: () => Downloads.share(context, _f.url, name: _name)),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.45)),
                  const Gap(16),
                  MpButton('Open in another app', onTap: () => Downloads.open(context, _f.url, name: _name)),
                ],
              ),
            )
          : _pages == 0
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))
              : PageView.builder(
                  controller: _pageCtl,
                  itemCount: _pages,
                  onPageChanged: (i) => setState(() => _at = i),
                  itemBuilder: _page,
                ),
    );
  }
}

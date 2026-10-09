// Dev-only preview entry used to screenshot screens against the design.
// Open `#/<Stem>` (e.g. `#/Consult-Vitals`) to show one screen; sheets open
// over their parent. Build: flutter build web -t tool/preview_main.dart
import 'package:flutter/material.dart';
import 'package:medpin_app/app/launcher.dart';
import 'package:medpin_app/app/registry.dart';
import 'package:medpin_app/core/nav.dart';
import 'package:medpin_app/core/tokens.dart';

void main() {
  Nav.registry = screenRegistry;
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: medpinTheme(),
    onGenerateRoute: (settings) {
      final name = settings.name ?? '/';
      final stem = name.startsWith('/') ? name.substring(1) : name;
      return PageRouteBuilder(
        settings: settings,
        transitionDuration: Duration.zero,
        pageBuilder: (c, _, __) => stem.isEmpty ? const LauncherScreen() : _Preview(stem),
      );
    },
  ));
}

class _Preview extends StatefulWidget {
  final String stem;
  const _Preview(this.stem);
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  @override
  void initState() {
    super.initState();
    final s = Nav.spec(widget.stem);
    if (s != null && s.sheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openSheet(context, s.builder);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Nav.spec(widget.stem);
    if (s == null) return Scaffold(body: Center(child: Text('Unknown ${widget.stem}')));
    if (s.sheet) {
      final p = s.parent == null ? null : Nav.spec(s.parent!);
      return p == null ? const Scaffold() : p.builder(context);
    }
    return s.builder(context);
  }
}

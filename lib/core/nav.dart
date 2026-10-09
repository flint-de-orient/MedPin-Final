import 'package:flutter/material.dart';

import '../data/config.dart';
import 'tokens.dart';

/// One screen from the design canvas.
class ScreenSpec {
  /// Design file stem, e.g. 'Consult-Vitals'. Used as the route name.
  final String stem;
  final String title;

  /// Canvas row it belongs to, e.g. 'Consultation'.
  final String group;

  /// 'doctor', 'staff' or 'patient'.
  final String panel;
  final WidgetBuilder builder;

  /// Bottom sheets open over their [parent] screen.
  final bool sheet;
  final String? parent;

  const ScreenSpec({
    required this.stem,
    required this.title,
    required this.group,
    required this.panel,
    required this.builder,
    this.sheet = false,
    this.parent,
  });
}

/// Navigation between design screens, addressed by their design stem.
class Nav {
  Nav._();

  /// The app's root navigator (for navigation that outlives a screen).
  static final key = GlobalKey<NavigatorState>();

  /// Filled at startup from app/registry.dart.
  static Map<String, ScreenSpec> registry = {};

  static ScreenSpec? spec(String stem) => registry[stem];

  /// Opens [stem]. Sheets open as modal bottom sheets over the current screen.
  /// [args] (e.g. a record id) is read on the next screen with [Nav.args].
  static Future<T?> go<T>(BuildContext context, String stem, {Object? args}) {
    final s = spec(stem);
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$stem is not in the design yet')));
      return Future.value();
    }
    if (s.sheet) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: MP.scrim,
        elevation: 0,
        routeSettings: RouteSettings(name: stem, arguments: args),
        builder: s.builder,
      );
    }
    return Navigator.of(context).push<T>(_route(s, args));
  }

  /// Arguments passed to the current screen with [Nav.go].
  static T? args<T>(BuildContext context) {
    final a = ModalRoute.of(context)?.settings.arguments;
    return a is T ? a : null;
  }

  /// Replaces the current screen (used by bottom-nav tabs), no transition.
  static void tab(BuildContext context, String stem) {
    final s = spec(stem);
    if (s == null) {
      toast(context, 'This section is not in the design yet');
      return;
    }
    if (ModalRoute.of(context)?.settings.name == stem) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      settings: RouteSettings(name: stem),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (c, _, __) => s.builder(c),
    ));
  }

  /// Clears the stack and starts at [stem] (e.g. after sign-in or log out).
  /// In the design launcher the launcher itself stays underneath.
  static void reset(BuildContext context, String stem) {
    final s = spec(stem);
    if (s == null) return;
    Navigator.of(context).pushAndRemoveUntil(_route(s), (r) => AppMode.preview && r.isFirst);
  }

  /// Opens a sheet screen on top of its parent screen (used by the gallery).
  static Future<void> openWithParent(BuildContext context, String stem) async {
    final s = spec(stem);
    if (s == null) return;
    if (!s.sheet || s.parent == null || spec(s.parent!) == null) {
      await go(context, stem);
      return;
    }
    final nav = Navigator.of(context);
    nav.push(_route(spec(s.parent!)!));
    await Future.delayed(const Duration(milliseconds: 380));
    final overlay = nav.overlay;
    if (overlay != null && overlay.mounted) await openSheet(overlay.context, s.builder);
  }

  static void back(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  static Route<T> _route<T>(ScreenSpec s, [Object? args]) => MaterialPageRoute<T>(
        settings: RouteSettings(name: s.stem, arguments: args),
        builder: s.builder,
      );
}

/// Shows [builder] as a MedPin bottom sheet (scrim rgba(17,24,39,.40)).
Future<T?> openSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: MP.scrim,
    elevation: 0,
    builder: builder,
  );
}

OverlayEntry? _toastEntry;

/// Shows a short confirmation toast for actions that have no screen. It is
/// drawn in the root overlay, so it also shows above open bottom sheets.
void toast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      onDone: () {
        if (_toastEntry == entry) _toastEntry = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _Toast({required this.message, required this.onDone});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    await _c.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 100 + bottom,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _c,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: MP.ink,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: MPShadow.float,
                ),
                child: Text(widget.message, textAlign: TextAlign.center, style: tx(14, w: w600, c: MP.white, h: 1.4)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

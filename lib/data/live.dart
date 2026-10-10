import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../widgets/mp.dart';
import 'api.dart';
import 'config.dart';
import 'session.dart';
import '../widgets/i18n.dart';

/// True when screens should load real data: signed in and not in the
/// design launcher / gallery.
bool get isLive => !AppMode.preview && Session.I.signedIn;

/// Loads one API resource for a screen.
///
/// In preview (launcher, gallery, tests) nothing is fetched and the screen
/// keeps its design sample data. Live, [data] is filled from [fetch].
mixin LiveData<W extends StatefulWidget> on State<W> {
  Map<String, dynamic>? data;
  ApiException? loadError;
  bool loading = false;

  /// When the data arrived (for "Updated 4s ago").
  DateTime? loadedAt;

  /// Set to refresh quietly in the background (e.g. the front desk's day).
  Duration? get refreshEvery => null;
  Timer? _refreshTimer;

  Future<Object?> fetch();

  @override
  void initState() {
    super.initState();
    if (!isLive) return;
    // Start after initState: fetch() may read the route arguments (Nav.args),
    // which Flutter doesn't allow during initState.
    loading = true;
    Future.microtask(() {
      if (mounted) reload();
    });
    final every = refreshEvery;
    if (every != null) _refreshTimer = Timer.periodic(every, (_) => reload(quiet: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Fetches again; with [quiet] the current data stays on screen meanwhile.
  Future<void> reload({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      if (data != null || loadError != null) setState(() => loadError = null);
    }
    try {
      final res = await fetch();
      if (!mounted) return;
      setState(() {
        data = res is Map ? res.cast<String, dynamic>() : {'items': res};
        loadedAt = DateTime.now();
        loadError = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        loadError = e;
        loading = false;
      });
      if (data != null && !quiet) toast(context, e.message);
    }
  }

  /// While live data hasn't arrived yet: a spinner, or the error with a retry.
  /// Returns null once there is something to show.
  Widget? livePlaceholder() {
    if (!isLive || data != null) return null;
    return LiveStatus(error: loadError, onRetry: reload);
  }
}

/// Loading / error state for a screen whose data hasn't arrived yet.
class LiveStatus extends StatelessWidget {
  final ApiException? error;
  final VoidCallback onRetry;
  const LiveStatus({super.key, this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 0),
      child: Center(
        child: error == null
            ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!.message, textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.5)),
                  const Gap(16),
                  MpButton('Try again', kind: MpBtn.secondary, expand: false, onTap: onRetry),
                ],
              ),
      ),
    );
  }
}

/// Runs an API action from a button: shows the error as a toast and returns
/// null when it fails. Guards against double taps with [busy].
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {ValueNotifier<bool>? busy}) async {
  if (busy?.value == true) return null;
  busy?.value = true;
  try {
    return await action();
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return null;
  } finally {
    busy?.value = false;
  }
}

/// Typed reads from API JSON.
extension JsonRead on Map<String, dynamic> {
  Map<String, dynamic> obj(String k) => (this[k] as Map?)?.cast<String, dynamic>() ?? const {};
  List<Map<String, dynamic>> list(String k) => [for (final x in (this[k] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  String str(String k, [String fallback = '']) => this[k] == null ? fallback : '${this[k]}';
  num numOr(String k, [num fallback = 0]) => this[k] is num ? this[k] as num : fallback;
}

/// Log out: ends the session on the server and the device, then shows sign-in.
/// In the design preview it only navigates.
Future<void> signOut(BuildContext context) async {
  if (!AppMode.preview) await Session.I.logout();
  if (context.mounted) Nav.reset(context, 'Auth-Login');
}

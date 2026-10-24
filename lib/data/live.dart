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

/// Keeps every live screen current without pull-to-refresh:
/// - [changed] after anything is saved (the API calls it for every successful
///   change, a push notification too): open screens refresh quietly, so the list
///   underneath a form is already up to date when you go back;
/// - coming back to a screen, or to the app, refreshes it;
/// - the visible screen also refreshes every 30 s, for changes made on other
///   phones (front desk, patients).
class LiveBus {
  LiveBus._();
  static final changes = ValueNotifier<int>(0);
  static void changed() => changes.value++;

  /// Registered on the app's navigator (main.dart) to know which screen is in front.
  static final routes = RouteObserver<ModalRoute<void>>();
}

/// Route and app-lifecycle events for one [LiveData] screen.
class _LiveWatch extends RouteAware with WidgetsBindingObserver {
  final VoidCallback onBack;
  final VoidCallback onResume;
  _LiveWatch(this.onBack, this.onResume);

  @override
  void didPopNext() => onBack();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Loads one API resource for a screen.
///
/// In preview (launcher, gallery, tests) nothing is fetched and the screen
/// keeps its design sample data. Live, [data] is filled from [fetch].
mixin LiveData<W extends StatefulWidget> on State<W> implements MpRefreshable {
  /// Pull-to-refresh on this screen's page (MpPage): loads it again, keeping what's shown meanwhile.
  @override
  Future<void> pageRefresh() => reload(quiet: true);

  /// Only screens with real data (not the design preview).
  @override
  bool get canRefresh => isLive;

  Map<String, dynamic>? data;
  ApiException? loadError;
  bool loading = false;

  /// When the data arrived (for "Updated 4s ago").
  DateTime? loadedAt;

  /// How often the screen refreshes while it's in front (default 30 s; chats and
  /// the queue use less). null keeps the default.
  Duration? get refreshEvery => null;

  /// false for a screen that must not refresh by itself (e.g. a form whose
  /// fields are filled from [data]).
  bool get autoRefresh => true;

  Timer? _refreshTimer;
  Timer? _changeDebounce;
  /// Set for a few seconds after each load (no second load straight after).
  Timer? _justLoaded;
  /// A change came in during that guard: load once it ends (a new chat message isn't lost).
  bool _changeWaiting = false;
  _LiveWatch? _watch;
  bool _subscribed = false;

  Future<Object?> fetch();

  /// In front: the top route and the app on screen.
  bool get _inFront {
    final route = ModalRoute.of(context);
    final app = WidgetsBinding.instance.lifecycleState;
    return (route?.isCurrent ?? true) && (app == null || app == AppLifecycleState.resumed);
  }

  void _quiet({bool onlyInFront = true}) {
    if (!mounted || !isLive || loading) return;
    if (onlyInFront && !_inFront) return;
    // Not again within a few seconds of the last load (a change is kept for when it ends).
    if (_justLoaded?.isActive ?? false) {
      if (!onlyInFront) _changeWaiting = true;
      return;
    }
    reload(quiet: true);
  }

  void _onChange() {
    _changeDebounce?.cancel();
    // Wait for the saving screen to finish; refresh even when not in front.
    _changeDebounce = Timer(const Duration(milliseconds: 600), () => _quiet(onlyInFront: false));
  }

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
    if (!autoRefresh && refreshEvery == null) return;
    _refreshTimer = Timer.periodic(refreshEvery ?? const Duration(seconds: 30), (_) => _quiet());
    if (!autoRefresh) return;
    LiveBus.changes.addListener(_onChange);
    _watch = _LiveWatch(_quiet, _quiet);
    WidgetsBinding.instance.addObserver(_watch!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_watch != null && !_subscribed && route is PageRoute) {
      LiveBus.routes.subscribe(_watch!, route);
      _subscribed = true;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _changeDebounce?.cancel();
    _justLoaded?.cancel();
    if (_watch != null) {
      LiveBus.changes.removeListener(_onChange);
      WidgetsBinding.instance.removeObserver(_watch!);
      if (_subscribed) LiveBus.routes.unsubscribe(_watch!);
    }
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
      _justLoaded?.cancel();
      _justLoaded = Timer(const Duration(seconds: 3), () {
        if (!_changeWaiting) return;
        _changeWaiting = false;
        _quiet(onlyInFront: false);
      });
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
    } catch (e, st) {
      // Unexpected data (a field of another shape): the error with a retry, never an endless spinner.
      debugPrint('Screen data not shown: $e\n$st');
      if (!mounted) return;
      const err = ApiException(0, 'BAD_DATA', "Something went wrong showing this. Try again.");
      setState(() {
        loadError = err;
        loading = false;
      });
      if (data != null && !quiet) toast(context, err.message);
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

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'queue_list.dart';

/// Design: Queue-Select.dc.html — "Patient queue · choose location"
/// (sheet over Doctor-Dashboard).
/// Live data: GET /api/queue/locations; "Don't ask again today" →
/// PUT /api/doctor/default-queue-location.
class QueueSelectSheet extends StatefulWidget {
  /// Location selected when the sheet opens (index into [D1Location.all]).
  final int initial;

  /// Live: id of the location selected when the sheet opens.
  final String? initialId;

  /// When true (opened from the queue's "Change"), the sheet pops with the
  /// chosen index (live: the location id) instead of opening the queue.
  final bool pick;
  const QueueSelectSheet({super.key, this.initial = 0, this.initialId, this.pick = false});

  @override
  State<QueueSelectSheet> createState() => _QueueSelectSheetState();
}

class _QueueSelectSheetState extends State<QueueSelectSheet> with LiveData {
  late int _sel = widget.initial;
  bool _dontAsk = true;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() => d1QueueLocations();

  @override
  Future<void> reload({bool quiet = false}) async {
    final first = data == null;
    await super.reload(quiet: quiet);
    if (!first || !mounted || data == null) return;
    final locs = _locations;
    final def = data!.str('defaultLocationId');
    // "Don't ask again today": go straight to today's chosen queue.
    if (!widget.pick && def.isNotEmpty && locs.any((l) => l.id == def && !l.closed)) {
      _open(def);
      return;
    }
    final want = widget.initialId ?? (def.isNotEmpty ? def : null);
    var i = want == null ? -1 : locs.indexWhere((l) => l.id == want);
    if (i < 0 || locs[i].closed) i = locs.indexWhere((l) => l.badge == 'Open now');
    if (i < 0) i = locs.indexWhere((l) => !l.closed);
    setState(() {
      _sel = i < 0 ? 0 : i;
      _dontAsk = widget.pick ? def.isNotEmpty : true;
    });
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  List<D1Location> get _locations {
    final d = data;
    if (d == null) return D1Location.all;
    return [for (final m in d.list('items')) D1Location.fromApi(m)];
  }

  void _open(String id) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: 'Queue-List', arguments: {'locationId': id}),
        builder: (_) => const QueueListScreen(),
      ),
    );
  }

  Future<void> _show() async {
    if (!isLive) {
      if (widget.pick) {
        Navigator.pop(context, _sel);
        return;
      }
      final nav = Navigator.of(context);
      final sel = _sel;
      nav.pop();
      nav.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'Queue-List'),
          builder: (_) => QueueListScreen(location: sel),
        ),
      );
      return;
    }
    final locs = _locations;
    if (data == null || locs.isEmpty || _sel >= locs.length || locs[_sel].closed) {
      toast(context, 'Choose a location first');
      return;
    }
    final id = locs[_sel].id!;
    final hadDefault = data!.str('defaultLocationId').isNotEmpty;
    if (_dontAsk || hadDefault) {
      final ok = await runAction(
        context,
        () => Api.I.put('/api/doctor/default-queue-location', {'locationId': _dontAsk ? id : null}),
        busy: _busy,
      );
      if (ok == null || !mounted) return;
    }
    if (widget.pick) {
      Navigator.pop(context, id);
    } else {
      _open(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final locations = placeholder == null ? _locations : const <D1Location>[];
    return MpSheet(
      title: 'Which queue are you seeing?',
      subtitle: "Pick the location you're consulting at right now. You can switch any time.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (placeholder != null) placeholder,
          if (placeholder == null && locations.isEmpty) Text('No consulting locations yet', style: tx(14, c: MP.ink2)),
          for (var i = 0; i < locations.length; i++) ...[
            if (i > 0) const Gap(8),
            _Option(
              locations[i],
              selected: i == _sel,
              onTap: locations[i].closed ? null : () => setState(() => _sel = i),
            ),
          ],
          const Gap(20),
          Semantics(
            checked: _dontAsk,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _dontAsk = !_dontAsk),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    MpCheck(value: _dontAsk, onChanged: (v) => setState(() => _dontAsk = v)),
                    const Gap(12),
                    Expanded(child: Text("Don't ask again today", style: tx(15))),
                  ],
                ),
              ),
            ),
          ),
          const Gap(20),
          MpButton('Show queue', onTap: _show),
        ],
      ),
    );
  }
}

/// Location radio card. Selected: 2px #003399 border; open: 1px #D5DBE5;
/// closed today: 1px #E5E9F0 on #F7F9FC, not selectable.
class _Option extends StatelessWidget {
  final D1Location loc;
  final bool selected;
  final VoidCallback? onTap;
  const _Option(this.loc, {required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final closed = loc.closed;
    final ring = selected ? MP.primary : (closed ? MP.line : MP.lineStrong);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: !closed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // 16 + 2px border when selected, 17 + 1px otherwise (same content box).
          padding: EdgeInsets.all(selected ? 16 : 17),
          decoration: BoxDecoration(
            color: closed ? MP.bg : MP.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ring, width: selected ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
                  child:
                      selected
                          ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
                          )
                          : null,
                ),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.name, style: tx(16, w: w700, c: closed ? MP.ink2 : MP.ink)),
                    const Gap(4),
                    Text(loc.kind, style: tx(14, c: closed ? MP.ink3 : MP.ink2)),
                    const Gap(6),
                    if (closed)
                      Text(loc.note!, style: tx(13, c: MP.ink3))
                    else
                      Row(
                        children: [
                          D1Pill(loc.badge!, bg: loc.badgeBg, fg: loc.badgeFg),
                          const Gap(8),
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                style: tx(13, c: MP.ink2, tab: true),
                                children: [
                                  TextSpan(text: loc.waiting == null ? loc.booked : '${loc.booked} · '),
                                  if (loc.waiting != null)
                                    TextSpan(text: loc.waiting, style: tx(13, w: w700, c: MP.amber, tab: true)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

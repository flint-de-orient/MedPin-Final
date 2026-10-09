import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'queue_list.dart';

/// Design: Queue-Select.dc.html — "Patient queue · choose location"
/// (sheet over Doctor-Dashboard).
class QueueSelectSheet extends StatefulWidget {
  /// Location selected when the sheet opens (index into [D1Location.all]).
  final int initial;

  /// When true (opened from the queue's "Change"), the sheet pops with the
  /// chosen index instead of opening the queue.
  final bool pick;
  const QueueSelectSheet({super.key, this.initial = 0, this.pick = false});

  @override
  State<QueueSelectSheet> createState() => _QueueSelectSheetState();
}

class _QueueSelectSheetState extends State<QueueSelectSheet> {
  late int _sel = widget.initial;
  bool _dontAsk = true;

  void _show() {
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
  }

  @override
  Widget build(BuildContext context) {
    const locations = D1Location.all;
    return MpSheet(
      title: 'Which queue are you seeing?',
      subtitle: "Pick the location you're consulting at right now. You can switch any time.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

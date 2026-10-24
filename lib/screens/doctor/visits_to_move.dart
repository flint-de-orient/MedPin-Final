import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';

/// Appointments → "N visits need a new time": upcoming visits on a day the doctor can't see
/// them (leave, a closure, changed hours). Tick the ones to move, choose a day: each goes to
/// the next free time that day with the same doctor and branch (the patient's chat says so).
/// Live data: [items] from GET /api/appointments/to-move; POST /api/appointments/bulk-reschedule.
/// Pops true when visits were moved.
class VisitsToMoveSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const VisitsToMoveSheet({super.key, required this.items});

  @override
  State<VisitsToMoveSheet> createState() => _VisitsToMoveSheetState();
}

class _VisitsToMoveSheetState extends State<VisitsToMoveSheet> {
  late final Set<String> _picked = {for (final a in widget.items) a.str('id')};
  DateTime? _day;
  bool _busy = false;

  List<DateTime> get _days {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return [for (var i = 0; i < 21; i++) start.add(Duration(days: i))];
  }

  String _dayLabel(DateTime d) {
    final today = DateTime.now();
    if (F.sameDay(d, today)) return tr(context, 'Today');
    if (F.sameDay(d, today.add(const Duration(days: 1)))) return tr(context, 'Tomorrow');
    return '${tr(context, const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1])} ${d.day}';
  }

  Future<void> _move() async {
    final day = _day;
    if (day == null) return toast(context, 'Choose the day to move them to');
    if (_picked.isEmpty) return toast(context, 'Choose the visits to move');
    setState(() => _busy = true);
    try {
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final res = (await Api.I.post('/api/appointments/bulk-reschedule', {'ids': _picked.toList(), 'date': key}) as Map).cast<String, dynamic>();
      if (!mounted) return;
      final moved = (res['moved'] as num?)?.toInt() ?? 0;
      final failed = (res['failed'] as List? ?? const []).length;
      toast(
        context,
        [
          if (moved > 0) tr(context, '#1 visits moved · patients told').replaceFirst('#1', '$moved'),
          if (failed > 0) tr(context, "#1 couldn't move: no free time that day").replaceFirst('#1', '$failed'),
        ].join(' · '),
      );
      if (moved > 0) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Visits that need a new time',
      subtitle: "Each one goes to the next free time on the day you choose, with the same doctor and branch.",
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in widget.items)
            Tap(
              onTap: () => setState(() => _picked.contains(a.str('id')) ? _picked.remove(a.str('id')) : _picked.add(a.str('id'))),
              radius: 10,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  MpCheck(value: _picked.contains(a.str('id'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserText(a.obj('patient').str('name', 'Patient'), style: tx(15, w: w600)),
                        Text(
                          [
                            if (F.date(a['startAt']) != null) F.when(F.date(a['startAt'])!),
                            a.obj('doctor').str('name'),
                            tr(context, a.str('moveReason')),
                          ].where((x) => x.isNotEmpty).join(' · '),
                          style: tx(13, c: MP.ink2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text('Move them to', style: tx(14, w: w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final d in _days) ...[
                MpChip(_dayLabel(d), selected: _day != null && F.sameDay(_day!, d), onTap: () => setState(() => _day = d)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          MpButton(_busy ? 'Moving…' : tr(context, 'Move #1 visits').replaceFirst('#1', '${_picked.length}'), onTap: _busy ? null : _move),
        ],
      ),
    );
  }
}

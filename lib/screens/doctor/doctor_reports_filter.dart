import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';

/// Design: Doctor-Reports-Filter.dc.html — "Doctor · Reports · filters".
/// Sheet over 'Doctor-Reports': starts 72px below the top, pinned footer.
class DoctorReportsFilterSheet extends StatefulWidget {
  const DoctorReportsFilterSheet({super.key});

  @override
  State<DoctorReportsFilterSheet> createState() => _DoctorReportsFilterSheetState();
}

const _dates = ['Today', '7 days', '30 days', 'This month', 'This year'];

// (legend, options of (label, consultations))
const _groups = [
  ('Location', [('City Care · Salt Lake', 168), ('City Care · New Town', 84), ('Sen Diabetes Chamber · Gariahat', 34)]),
  ('Visit type', [('Follow-up', 196), ('New patient', 64), ('Report review', 26)]),
  ('Consultation mode', [('In clinic', 262), ('Video', 24)]),
  ('Age group', [('Under 18', 18), ('18 – 40', 92), ('41 – 60', 121), ('Over 60', 55)]),
];

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Date presets, with "today" = Thu, 1 Oct 2026 as on the dashboard.
(DateTime, DateTime) _preset(int i) => switch (i) {
  0 => (DateTime(2026, 10, 1), DateTime(2026, 10, 1)),
  1 => (DateTime(2026, 9, 24), DateTime(2026, 9, 30)),
  2 => (DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
  3 => (DateTime(2026, 10, 1), DateTime(2026, 10, 1)),
  _ => (DateTime(2026, 1, 1), DateTime(2026, 10, 1)),
};

class _DoctorReportsFilterSheetState extends State<DoctorReportsFilterSheet> {
  int _date = 2;
  DateTime _from = DateTime(2026, 9, 1);
  DateTime _to = DateTime(2026, 9, 30);
  bool _compare = true;
  late List<List<bool>> _on = _allOn();

  static List<List<bool>> _allOn() => [for (final g in _groups) List.filled(g.$2.length, true)];

  /// Consultations matching the ticked options (286 with everything ticked).
  int get _count {
    var f = 286.0;
    for (var g = 0; g < _groups.length; g++) {
      final opts = _groups[g].$2;
      var all = 0, sel = 0;
      for (var i = 0; i < opts.length; i++) {
        all += opts[i].$2;
        if (_on[g][i]) sel += opts[i].$2;
      }
      f *= sel / all;
    }
    return f.round();
  }

  void _reset() => setState(() {
    _date = 2;
    final r = _preset(2);
    _from = r.$1;
    _to = r.$2;
    _compare = true;
    _on = _allOn();
  });

  Future<void> _pickDate(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2026, 12, 31),
    );
    if (d == null || !mounted) return;
    setState(() {
      _date = -1;
      if (from) {
        _from = d;
        if (_to.isBefore(d)) _to = d;
      } else {
        _to = d;
        if (_from.isAfter(d)) _from = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.hasBoundedHeight ? c.maxHeight : MediaQuery.of(context).size.height;
        return Container(
          height: math.max(0.0, avail - 72),
          decoration: const BoxDecoration(
            color: MP.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: MPShadow.float,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle + title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SheetHandle(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text('Filters', style: tx(20, w: w700, h: 1.25))),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 44,
                          child: Tap(
                            onTap: _reset,
                            radius: 12,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Center(widthFactor: 1, child: Text('Reset', style: tx(15, w: w600, c: MP.primary))),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filters
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: VGap(gap: 24, children: [_dateRange(), for (var g = 0; g < _groups.length; g++) _group(g)]),
                ),
              ),

              // Footer
              MpBottomBar(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: MpButton('Show $_count consultations', onTap: () => Navigator.pop(context)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dateRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Date range', style: tx(15, w: w700))),
        Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < _dates.length; i++) _dateChip(i)]),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dateField('From', _from, true)),
            const SizedBox(width: 8),
            Expanded(child: _dateField('To', _to, false)),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          checked: _compare,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _compare = !_compare),
            child: Row(
              children: [
                _Box(_compare),
                const SizedBox(width: 10),
                Expanded(child: Text('Compare with previous period', style: tx(14))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateChip(int i) {
    final sel = i == _date;
    return Semantics(
      selected: sel,
      child: SizedBox(
        height: 36,
        child: Tap(
          onTap:
              () => setState(() {
                _date = i;
                final r = _preset(i);
                _from = r.$1;
                _to = r.$2;
              }),
          radius: 999,
          color: sel ? MP.primary : MP.white,
          border: sel ? MP.primary : MP.lineStrong,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(widthFactor: 1, child: Text(_dates[i], style: tx(14, w: w600, c: sel ? MP.white : MP.ink))),
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime d, bool from) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: tx(13, c: MP.ink2)),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: Tap(
            onTap: () => _pickDate(from),
            radius: 16,
            border: MP.lineStrong,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_fmt(d), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w500)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _group(int g) {
    final opts = _groups[g].$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_groups[g].$1, style: tx(15, w: w700))),
        for (var i = 0; i < opts.length; i++)
          Semantics(
            checked: _on[g][i],
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _on[g][i] = !_on[g][i]),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    _Box(_on[g][i]),
                    const SizedBox(width: 12),
                    Expanded(child: Text(opts[i].$1, style: tx(15))),
                    const SizedBox(width: 12),
                    Text('${opts[i].$2}', style: tx(13, c: MP.ink3, tab: true)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 22×22 checkbox, radius 6: ticked = #003399 with a white 14px / 3 stroke
/// check; empty = white with a 2px #D5DBE5 border.
class _Box extends StatelessWidget {
  final bool on;
  const _Box(this.on);

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: on ? MP.primary : MP.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: on ? MP.primary : MP.lineStrong, width: 2),
    ),
    child: on ? const Ico(I.checkAlt, size: 14, color: MP.white, stroke: 3) : null,
  );
}

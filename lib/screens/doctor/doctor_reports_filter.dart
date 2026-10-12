import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';
import '../../widgets/i18n.dart';

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

class _DoctorReportsFilterSheetState extends State<DoctorReportsFilterSheet> with LiveData {
  int _date = 2;
  DateTime _from = DateTime(2026, 9, 1);
  DateTime _to = DateTime(2026, 9, 30);
  bool _compare = true;
  late List<List<bool>> _on = _allOn();

  List<List<bool>> _allOn() => [for (final g in _shown) List.filled(g.$2.length, true)];

  // ── Live ──
  D3Filters? _start;
  List<Map<String, dynamic>>? _locations;

  /// Option keys per group (location ids, visit types, modes, age groups).
  List<List<String>> _keys = const [];
  static const _visitKeys = ['follow_up', 'new', 'report_review'];
  static const _modeKeys = ['in_clinic', 'video'];
  static const _ageKeys = ['under_18', '18_40', '41_60', 'over_60'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_start != null || !isLive) return;
    final f = D3Filters.of(Nav.args<Object>(context));
    _start = f;
    final i = D3Filters.presets.indexOf(f.range);
    final (a, b) = f.days;
    _date = i;
    _from = a;
    _to = b;
    _compare = f.compare;
  }

  /// The filters as ticked now.
  D3Filters get _current {
    List<String> picked(int g) {
      if (g >= _keys.length || g >= _on.length || _on[g].every((x) => x)) return const [];
      return [for (var i = 0; i < _keys[g].length; i++) if (_on[g][i]) _keys[g][i]];
    }

    final locs = _keys.isEmpty ? 0 : _on[0].where((x) => x).length;
    String locLabel() {
      if (_keys.isEmpty || _on[0].every((x) => x)) return 'All locations';
      if (locs == 1) return _shown[0].$2[_on[0].indexOf(true)].$1;
      return '$locs locations';
    }

    return D3Filters(
      range: _date >= 0 ? D3Filters.presets[_date] : 'custom',
      from: _date >= 0 ? null : _from,
      to: _date >= 0 ? null : _to,
      locationIds: picked(0),
      visitTypes: picked(1),
      modes: picked(2),
      ageGroups: picked(3),
      compare: _compare,
      locationLabel: locLabel(),
    );
  }

  /// A group with nothing ticked matches no consultations.
  bool get _noneInAGroup => _on.any((g) => g.isNotEmpty && !g.contains(true));

  @override
  Future<Object?> fetch() async {
    // The first fetch starts in initState; let didChangeDependencies read
    // the args first.
    await Future<void>.value();
    final f = _current;
    final r = await Future.wait([
      Api.I.get('/api/reports/filter-counts', query: f.query),
      if (_locations == null) Api.I.get('/api/locations'),
    ]);
    if (_locations == null) {
      _locations = [
        for (final l in (r[1] as Map).cast<String, dynamic>().list('items'))
          if (l['status'] != 'inactive') l,
      ];
      final s = _start ?? const D3Filters();
      _keys = [
        [for (final l in _locations!) l.str('id')],
        _visitKeys,
        _modeKeys,
        _ageKeys,
      ];
      final chosen = [s.locationIds, s.visitTypes, s.modes, s.ageGroups];
      _on = [
        for (var g = 0; g < _keys.length; g++)
          [for (final k in _keys[g]) chosen[g].isEmpty || chosen[g].contains(k)],
      ];
    }
    return (r[0] as Map).cast<String, dynamic>();
  }

  /// Groups shown: the design's sample, or live options with their counts.
  List<(String, List<(String, int)>)> get _shown {
    final d = data;
    if (d == null || _locations == null) return _groups;
    int count(String group, String key) {
      for (final x in d.list(group)) {
        if (x['key'] == key) return x.numOr('count').toInt();
      }
      return 0;
    }

    return [
      ('Location', [for (final l in _locations!) (d3LocationName(l), count('location', l.str('id')))]),
      ('Visit type', [for (final k in _visitKeys) (d3VisitType(k), count('visitType', k))]),
      ('Consultation mode', [for (final k in _modeKeys) (d3Mode(k), count('mode', k))]),
      ('Age group', [for (final k in _ageKeys) (d3AgeGroup(k), count('ageGroup', k))]),
    ];
  }

  /// After a change: live, ask the API how many consultations match.
  void _changed() {
    if (isLive && data != null) reload(quiet: true);
  }

  void _apply() {
    if (!isLive) {
      Navigator.pop(context);
      return;
    }
    if (_noneInAGroup) {
      toast(context, 'Tick at least one option in each group');
      return;
    }
    Navigator.pop(context, _current);
  }

  /// Consultations matching the ticked options (286 with everything ticked).
  int get _count {
    if (data != null) return _noneInAGroup ? 0 : data!.numOr('matching').toInt();
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

  /// Live presets count back from today (IST), as the API does.
  (DateTime, DateTime) _range(int i) => isLive ? D3Filters(range: D3Filters.presets[i]).days : _preset(i);

  void _reset() {
    setState(() {
      _date = 2;
      final r = _range(2);
      _from = r.$1;
      _to = r.$2;
      _compare = true;
      _on = _allOn();
    });
    _changed();
  }

  Future<void> _pickDate(bool from) async {
    final today = d3Today();
    final last = isLive ? today : DateTime(2026, 12, 31);
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to).isAfter(last) ? last : (from ? _from : _to),
      firstDate: DateTime(2024, 1, 1),
      lastDate: last,
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
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
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
                child:
                    placeholder ??
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: VGap(gap: 24, children: [_dateRange(), for (var g = 0; g < _shown.length; g++) _group(g)]),
                    ),
              ),

              // Footer
              MpBottomBar(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: MpButton(
                  placeholder != null
                      ? 'Show consultations'
                      : (_count == 1 ? 'Show 1 consultation' : 'Show ${F.count(_count)} consultations'),
                  onTap: placeholder != null ? null : _apply,
                ),
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
        MpHitSlop(child: Semantics(
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
        )),
      ],
    );
  }

  Widget _dateChip(int i) {
    final sel = i == _date;
    return MpHitSlop(child: Semantics(
      selected: sel,
      child: SizedBox(
        height: 36,
        child: Tap(
          onTap:
              () {
                setState(() {
                  _date = i;
                  final r = _range(i);
                  _from = r.$1;
                  _to = r.$2;
                });
                _changed();
              },
          radius: 999,
          color: sel ? MP.primary : MP.white,
          border: sel ? MP.primary : MP.lineStrong,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(widthFactor: 1, child: Text(_dates[i], style: tx(14, w: w600, c: sel ? MP.white : MP.ink))),
        ),
      ),
    ));
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
    final group = _shown[g];
    final opts = group.$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(group.$1, style: tx(15, w: w700))),
        for (var i = 0; i < opts.length; i++)
          Semantics(
            checked: _on[g][i],
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _on[g][i] = !_on[g][i]);
                _changed();
              },
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

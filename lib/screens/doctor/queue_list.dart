import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'queue_select.dart';

/// Design: Queue-List.dc.html — "Patient queue".
class QueueListScreen extends StatefulWidget {
  /// Index into [D1Location.all] of the location whose queue is shown.
  final int location;
  const QueueListScreen({super.key, this.location = 0});

  @override
  State<QueueListScreen> createState() => _QueueListScreenState();
}

enum _Kind { consult, waiting, booked, done }

/// One patient in the queue.
class _Q {
  final _Kind kind;
  final String token;
  final String name;
  final String meta;
  final String time;
  final bool vitals;
  final int docs;
  final bool ai;
  final bool next;

  /// Waiting longer than usual (time shown in amber, 600).
  final bool long;
  final String? button;
  final MpBtn buttonKind;
  const _Q(
    this.kind,
    this.token,
    this.name,
    this.meta,
    this.time, {
    required this.vitals,
    required this.docs,
    this.ai = false,
    this.next = false,
    this.long = false,
    this.button,
    this.buttonKind = MpBtn.tonal,
  });
}

class _Group {
  final String title;
  final String count;
  final List<_Q> rows;
  final bool hero;
  final String? more;
  const _Group(this.title, this.count, this.rows, {this.hero = false, this.more});
}

// value, unit, label, colour
const _stats = [
  ('3', '', 'Waiting', MP.amber),
  ('1', '', 'In consult', MP.ink),
  ('6', '', 'Completed', MP.ink),
  ('14', ' min', 'Avg wait', MP.ink),
];

const _filters = ['All · 12', 'Waiting · 3', 'In consultation · 1', 'Completed · 6'];

const _groups = [
  _Group('In consultation', '1', hero: true, [
    _Q(
      _Kind.consult,
      '04',
      'Priya Sharma',
      '29 F · Follow-up · Diabetes',
      'Started 9:14 AM · 11 min',
      vitals: true,
      docs: 2,
      ai: true,
      button: 'Resume',
    ),
  ]),
  _Group('Waiting', '3', [
    _Q(
      _Kind.waiting,
      '05',
      'Rahul Das',
      '45 M · New · High BP',
      'Waiting 22 min',
      vitals: true,
      docs: 0,
      long: true,
      next: true,
      button: 'Start consultation',
    ),
    _Q(
      _Kind.waiting,
      '06',
      'Aisha Khan',
      '52 F · Follow-up · Thyroid',
      'Waiting 15 min',
      vitals: true,
      docs: 1,
      ai: true,
      button: 'Start consultation',
    ),
    _Q(
      _Kind.waiting,
      '07',
      'Sujit Mondal',
      '37 M · New · Fever, cough',
      'Waiting 6 min',
      vitals: false,
      docs: 0,
      button: 'Start consultation',
    ),
  ]),
  _Group('Not arrived yet', '2', [
    _Q(
      _Kind.booked,
      '08',
      'Moumita Roy',
      '41 F · Follow-up · Cardiology',
      'Booked for 11:00 AM',
      vitals: false,
      docs: 3,
      ai: true,
    ),
    _Q(
      _Kind.booked,
      '09',
      'Amit Pal',
      '55 M · Follow-up · Diabetes, CKD',
      'Booked for 11:30 AM',
      vitals: false,
      docs: 1,
      ai: true,
    ),
  ]),
  _Group('Completed', '6', more: 'Show 4 more', [
    _Q(
      _Kind.done,
      '03',
      'Debasish Bose',
      '62 M · Follow-up · Diabetes',
      'Done 9:10 AM · 9 min',
      vitals: true,
      docs: 1,
      button: 'View prescription',
      buttonKind: MpBtn.secondary,
    ),
    _Q(
      _Kind.done,
      '02',
      'Farhana Islam',
      '34 F · Review reports · Anaemia',
      'Done 8:58 AM · 12 min',
      vitals: true,
      docs: 2,
      button: 'View prescription',
      buttonKind: MpBtn.secondary,
    ),
  ]),
];

/// Dashed 9px circle ("no vitals" / "no documents"): butt caps like the design.
const _dashed = '<circle cx="12" cy="12" r="9" stroke-dasharray="3 3" stroke-linecap="butt" stroke-linejoin="miter"/>';

(String, Color, Color) _status(_Kind k) => switch (k) {
  _Kind.consult => ('In consultation', MP.primarySoft, MP.primary),
  _Kind.waiting => ('Waiting', MP.amberSoft, MP.amber),
  _Kind.booked => ('Not arrived', MP.fill, MP.ink2),
  _Kind.done => ('Completed', MP.greenSoft, MP.green),
};

class _QueueListScreenState extends State<QueueListScreen> {
  late int _loc = widget.location;
  int _filter = 0;

  Future<void> _changeLocation() async {
    final r = await openSheet<int>(context, (_) => QueueSelectSheet(initial: _loc, pick: true));
    if (r != null && mounted) setState(() => _loc = r);
  }

  void _onButton(_Q r) {
    if (r.kind == _Kind.done) {
      Nav.go(context, 'Prescriptions');
    } else {
      Nav.go(context, 'Consult-Page');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = switch (_filter) {
      1 => [_groups[1]],
      2 => [_groups[0]],
      3 => [_groups[3]],
      _ => _groups,
    };
    return MpPage(
      header: _header(context, D1Location.all[_loc]),
      body: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _statsCard()),
            const Gap(16),
            // Chips run to the right edge (design: margin-right -20px, overflow hidden).
            MpChipRow(
              gap: 8,
              children: [
                for (var i = 0; i < _filters.length; i++)
                  Semantics(
                    toggled: i == _filter,
                    child: MpChip(
                      _filters[i],
                      selected: i == _filter,
                      onTap: () => setState(() => _filter = i),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
              ],
            ),
            for (final g in groups) ...[
              const Gap(16),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _group(g)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, D1Location loc) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
                  const Gap(4),
                  Expanded(
                    child: Text(
                      'Patient queue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(20, w: w700, h: 1.25),
                    ),
                  ),
                  const Gap(4),
                  MpIconButton(
                    I.search,
                    label: 'Search the queue',
                    onTap: () => Nav.go(context, 'Doctor-Patients-Search'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'Change location. Current: ${loc.a11y}',
                  // 56px border-box button: the height wraps the Tap.
                  child: SizedBox(
                    height: 56,
                    child: Tap(
                      onTap: _changeLocation,
                      radius: 16,
                      color: MP.white,
                      border: MP.lineStrong,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Ico(I.pin, size: 20, color: MP.primary),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(loc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                                  Text(
                                    loc.hours,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tx(13, c: MP.ink2),
                                  ),
                                ],
                              ),
                            ),
                            const Gap(12),
                            Text('Change', style: tx(14, w: w600, c: MP.primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Gap(10),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle),
                    ),
                    const Gap(8),
                    Expanded(child: Text('Tue, 29 Sep · Updated 4s ago', style: tx(13, c: MP.ink2))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 4-up stats strip: white, 1px border, radius 16, cells split by 1px lines.
  /// Every cell has the same two lines, so the cells (and dividers) line up.
  Widget _statsCard() {
    return Container(
      decoration: MPDeco.card(radius: 16),
      child: Row(
        children: [
          for (var i = 0; i < _stats.length; i++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(left: BorderSide(color: MP.line))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: _stats[i].$1,
                        style: tx(22, w: w800, h: 1.1, c: _stats[i].$4, tab: true),
                        children: [
                          if (_stats[i].$2.isNotEmpty)
                            TextSpan(text: _stats[i].$2, style: tx(12, w: w600, c: MP.ink3, h: 1.1, tab: true)),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                    const Gap(2),
                    // On narrow phones a label may run into the cell's own
                    // 12px right padding rather than break mid-word.
                    Text(
                      _stats[i].$3,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: tx(12, c: MP.ink2, h: 1.3),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _group(_Group g) {
    final label = tx(12, w: w700, c: MP.ink3, em: 0.06);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text(g.title.toUpperCase(), style: label)),
              Text(g.count, style: tx(12, w: w700, c: MP.ink3, em: 0.06, tab: true)),
            ],
          ),
        ),
        const Gap(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: MP.white,
            borderRadius: BorderRadius.circular(24),
            border: g.hero ? Border.all(color: MP.primary, width: 1.5) : Border.all(color: MP.line),
            boxShadow: g.hero ? MPShadow.float : MPShadow.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < g.rows.length; i++) _row(g.rows[i], first: i == 0),
              if (g.more != null)
                Tap(
                  onTap: () => Nav.go(context, 'Doctor-History'),
                  radius: 0,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Text(g.more!, style: tx(14, w: w600, c: MP.primary)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(_Q r, {required bool first}) {
    final s = _status(r.kind);
    final consult = r.kind == _Kind.consult;
    final tokenFg = consult ? MP.white : MP.ink;
    final recordVitals = !r.vitals && r.kind == _Kind.waiting;
    final timeColor = r.long ? MP.amber : MP.ink2;
    return Opacity(
      opacity: r.kind == _Kind.done ? 0.85 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'Token ${r.token}',
                  excludeSemantics: true,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: consult ? MP.primary : MP.fill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('NO.', style: tx(10, w: w700, c: tokenFg, em: 0.06, h: 1)),
                        Text(r.token, style: tx(17, w: w800, c: tokenFg, h: 1.1, tab: true)),
                      ],
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Tap(
                    onTap: () => Nav.go(context, 'PP-Summary'),
                    radius: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                            ),
                            if (r.next) ...[
                              const Gap(8),
                              const D1Pill('NEXT', bg: MP.primary, fg: MP.white, fontSize: 11, em: 0.06),
                            ],
                          ],
                        ),
                        const Gap(2),
                        Text(r.meta, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                ),
                const Gap(12),
                D1Pill(s.$1, bg: s.$2, fg: s.$3, height: 24, padding: 10),
              ],
            ),
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                    r.vitals ? 'Vitals' : 'No vitals',
                    icon: r.vitals ? I.check : _dashed,
                    stroke: r.vitals ? 2.5 : 2,
                    ok: r.vitals,
                  ),
                  _Chip(
                    r.docs == 0 ? 'No documents' : '${r.docs} ${r.docs == 1 ? 'document' : 'documents'}',
                    icon: r.docs > 0 ? I.file : _dashed,
                    stroke: 2,
                    ok: r.docs > 0,
                  ),
                  if (r.ai) const _Chip('AI brief', icon: I.sparkle, stroke: 2, ai: true),
                ],
              ),
            ),
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Row(
                children: [
                  Ico(I.clock, size: 14, color: timeColor, stroke: 2),
                  const Gap(6),
                  Expanded(child: Text(r.time, style: tx(13, w: r.long ? w600 : w400, c: timeColor, tab: true))),
                  if (recordVitals) ...[
                    const Gap(12),
                    Tap(
                      onTap: () => Nav.go(context, 'Consult-Vitals'),
                      radius: 6,
                      child: Text('Record vitals', style: tx(14, w: w600, c: MP.primary)),
                    ),
                  ],
                ],
              ),
            ),
            if (r.button != null) ...[
              const Gap(12),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: MpButton.small(r.button!, kind: r.buttonKind, onTap: () => _onButton(r)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 28px readiness chip (padding 0 10 0 8, radius 999, 13 / 600, 14px icon).
class _Chip extends StatelessWidget {
  final String label;
  final String icon;
  final double stroke;
  final bool ok;
  final bool ai;
  const _Chip(this.label, {required this.icon, required this.stroke, this.ok = false, this.ai = false});

  @override
  Widget build(BuildContext context) {
    final bg = ai ? MP.primarySoft : (ok ? MP.greenSoft : MP.fill);
    final fg = ai ? MP.primary : (ok ? MP.green : MP.ink2);
    return Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Ico(icon, size: 14, color: fg, stroke: stroke),
          const Gap(5),
          Text(label, style: tx(13, w: w600, c: fg)),
        ],
      ),
    );
  }
}

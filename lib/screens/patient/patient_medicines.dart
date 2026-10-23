import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';
import '../doctor/common_d4.dart';
import '../../data/checkout.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-Medicines.dc.html — "Patient · Medicines tab".
class PatientMedicinesScreen extends StatefulWidget {
  const PatientMedicinesScreen({super.key});

  @override
  State<PatientMedicinesScreen> createState() => _PatientMedicinesScreenState();
}

/// (slot, [(medicine, when, taken at — null while due)])
const List<(String, List<(String, String, String?)>)> _slots = [
  (
    'Morning',
    [
      ('Glimepiride 1 mg', 'Before breakfast', '7:32 AM'),
      ('Metformin 500 mg', 'After breakfast', '8:40 AM'),
      ('Myo-inositol 2 g', 'After breakfast', '8:41 AM'),
    ],
  ),
  (
    'Night',
    [('Metformin 500 mg', '8:30 PM · after dinner', null), ('Atorvastatin 10 mg', '10:00 PM · at bedtime', null)],
  ),
];

class _Med {
  final String name;
  final String dose;
  final String day;
  final String taken;
  final Color takenColor;
  final String stock;
  final Color stockColor;
  final String by;

  /// Strips already in the cart.
  final int? inCart;

  /// The API medicine (live only).
  final Map<String, dynamic>? raw;
  const _Med(
    this.name,
    this.dose,
    this.day,
    this.taken,
    this.takenColor,
    this.stock,
    this.stockColor,
    this.by, [
    this.inCart,
    this.raw,
  ]);
}

const _meds = [
  _Med(
    'Metformin 500 mg',
    '1-0-1 · after food',
    'Day 468',
    '78%',
    MP.amber,
    '6 · 3 days',
    MP.amber,
    'Dr. Arjun Sen · 29 Sep 2026 · ongoing',
    3,
  ),
  _Med(
    'Glimepiride 1 mg',
    '1-0-0 · before breakfast',
    'Day 2 of 30',
    'New',
    MP.ink3,
    '28 · 28 days',
    MP.ink,
    'Dr. Arjun Sen · 29 Sep 2026',
  ),
  _Med(
    'Atorvastatin 10 mg',
    '0-0-1 · at bedtime',
    'Day 241',
    '91%',
    MP.green,
    '12 · 12 days',
    MP.ink,
    'Dr. Rina Mitra · 02 Feb 2026 · ongoing',
  ),
  _Med(
    'Myo-inositol 2 g',
    '1-0-1 · after food',
    'Day 316',
    'Not tracked',
    MP.ink3,
    '40 · 20 days',
    MP.ink,
    'Dr. Nandita Gupta · 18 Nov 2025',
  ),
  _Med(
    'Vitamin D3 60,000 IU',
    'Once a week · Sunday',
    'Week 7 of 8',
    '100%',
    MP.green,
    '2 · 2 weeks',
    MP.ink,
    'Dr. Arjun Sen · 11 Aug 2026',
  ),
];

const _more = [
  ('Reminder times', 'Morning 7:30 AM · Night 8:30 PM', 'Editing reminder times'),
  ('Orders', '1 delivered · 12 Sep', 'Order history'),
  ('Past medicines', '3 completed courses', 'The past medicines list'),
  ('Share medicine list', 'PDF for a new doctor or pharmacy', ''),
];

/// Shield with a check (safety check).
const _shieldCheck = '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>';

/// Live data: GET /api/patient/medicines, /doses (today), /cart and /orders.
/// Taken / Skip post to /doses/:id; the screen reloads when the cart changes.
class _PatientMedicinesScreenState extends State<PatientMedicinesScreen> with LiveData, P3Listen {
  /// Per dose: null = due, '' = skipped, otherwise the time it was taken.
  late final List<List<String?>> _status = [
    for (final s in _slots) [for (final d in s.$2) d.$3],
  ];
  late final List<int?> _cart = [for (final m in _meds) m.inCart];

  /// Live dose overrides while a Taken / Skip request is on its way (id → status).
  final _pending = <String, String>{};

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([
      Api.I.get('/api/patient/medicines'),
      Api.I.get('/api/patient/doses'),
      Api.I.get('/api/patient/cart'),
      Api.I.get('/api/patient/orders'),
    ]);
    final out = {'meds': r[0], 'doses': r[1], 'cart': r[2], 'orders': r[3]};
    _openCourseArg(out);
    return out;
  }

  /// Args {courseId} (e.g. a refill reminder): open that medicine's
  /// add-to-cart sheet once, or the cart when it is already in it.
  bool _openedArg = false;

  void _openCourseArg(Map<String, dynamic> d) {
    final want = _openedArg ? null : Nav.args<Map>(context)?['courseId'];
    if (want == null) return;
    _openedArg = true;
    final meds = (d['meds'] as Map).cast<String, dynamic>();
    final hit = meds.list('items').where((c) => c.str('id') == '$want').toList();
    if (hit.isEmpty) return;
    final inCart = (d['cart'] as Map).cast<String, dynamic>().list('items').any((i) => i.str('courseId') == '$want');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || data == null) return;
      if (inCart) {
        Nav.go(context, 'Med-Cart');
      } else if (await _addCourseToCart(hit.first) && mounted) {
        reload(quiet: true);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    p3Listen(p3CartChanged, () => reload(quiet: true));
  }

  Map<String, dynamic> get _medsData => data!.obj('meds');
  List<Map<String, dynamic>> get _courses => _medsData.list('items');

  /// Strips in the cart per course.
  Map<String, int> get _cartByCourse => {
    for (final i in data!.obj('cart').list('items'))
      if (i['courseId'] != null) i.str('courseId'): i.numOr('strips', 1).toInt(),
  };

  // ── Live doses ──

  static const _slotNames = {'morning': 'Morning', 'afternoon': 'Afternoon', 'night': 'Night'};

  List<(String, List<Map<String, dynamic>>)> get _liveSlots {
    final doses = data!.obj('doses').list('items');
    return [
      for (final slot in _slotNames.keys)
        if (doses.any((d) => d.str('slot') == slot)) (_slotNames[slot]!, doses.where((d) => d.str('slot') == slot).toList()),
    ];
  }

  String _doseStatus(Map<String, dynamic> d) => _pending[d.str('id')] ?? d.str('status', 'due');

  Future<void> _markDose(Map<String, dynamic> d, String status) async {
    final id = d.str('id');
    setState(() => _pending[id] = status);
    final ok = await runAction(context, () => Api.I.post('/api/patient/doses/$id', {'status': status}));
    if (!mounted) return;
    if (ok == null) {
      setState(() => _pending.remove(id));
      return;
    }
    if (ok is Map) {
      d['status'] = ok['status'];
      d['takenAt'] = ok['takenAt'];
    }
    _pending.remove(id);
    reload(quiet: true); // stock goes down when a dose is taken
  }

  // ── Cart ──

  Future<void> _addToCart(int i) async {
    final strips = await Nav.go<int>(context, 'Med-AddToCart');
    if (!mounted || strips == null) return;
    setState(() => _cart[i] = strips);
  }

  Future<bool> _addCourseToCart(Map<String, dynamic> c) async {
    final strips = await Nav.go<int>(context, 'Med-AddToCart', args: {'course': c, 'nextVisitAt': _medsData['nextVisitAt']});
    return mounted && strips != null;
  }

  // ── Medicine actions (sheets) ──

  Future<void> _updateStock(Map<String, dynamic> c) async {
    final units = await openSheet<int>(context, (_) => _StockSheet(course: c));
    if (units == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.patch('/api/patient/medicines/${c.str('id')}', {'stockUnits': units}));
    if (ok == null || !mounted) return;
    toast(context, 'Stock updated');
    reload(quiet: true);
  }

  Future<void> _editMedicine([Map<String, dynamic>? c]) async {
    final saved = await openSheet<bool>(context, (_) => _MedicineSheet(course: c));
    if (saved == true && mounted) reload(quiet: true);
  }

  Future<void> _onMore(int i) async {
    final d = data!;
    switch (i) {
      case 0:
        final saved = await openSheet<bool>(context, (_) => _ReminderSheet(times: _medsData.obj('reminderTimes'), slots: _usedSlots, bedAt: _medsData.str('bedAt', '22:30'), bedtime: _courses.any((c) => c.str('foodRelation') == 'bedtime')));
        if (saved == true && mounted) reload(quiet: true);
      case 1:
        await openSheet<void>(context, (_) => _OrdersSheet(orders: d.list('orders')));
        // Payments or cancels may have happened in the sheet.
        if (mounted && isLive) reload(quiet: true);
      case 2:
        await openSheet<void>(context, (_) => const _PastSheet());
      default:
        final res = await runAction(context, () => Api.I.post('/api/patient/medicines/share-pdf'));
        if (res is Map && mounted) await p3Open(context, res['url'] as String?, what: 'the medicine list');
    }
  }

  /// Slots any running medicine is taken in (for the reminder times line).
  List<String> get _usedSlots => [
    for (final s in _slotNames.keys)
      if (_courses.any((c) => c.obj('dose').numOr(s) > 0)) s,
  ];

  List<(String, String, String)> get _liveMore {
    final times = _medsData.obj('reminderTimes');
    final slots = _usedSlots.isEmpty ? const ['morning', 'night'] : _usedSlots;
    final orders = data!.list('orders');
    final last = orders.isEmpty ? null : orders.first;
    final lastAt = last == null ? null : F.date(last['createdAt']);
    final past = _medsData.numOr('pastCount').toInt();
    return [
      ('Meal times', [for (final s in slots) '${const {'morning': 'Breakfast', 'afternoon': 'Lunch', 'night': 'Dinner'}[s]} ${p3Clock(times.str(s, const {'morning': '08:00', 'afternoon': '13:30', 'night': '20:30'}[s]!))}'].join(' · '), ''),
      ('Orders', last == null ? 'No orders yet' : '${orders.length} · last ${last.str('status').replaceAll('_', ' ')}${lastAt != null ? ' · ${F.dayMonth(lastAt)}' : ''}', ''),
      ('Past medicines', past == 0 ? 'None yet' : '$past completed ${past == 1 ? 'course' : 'courses'}', ''),
      ('Share medicine list', 'PDF for a new doctor or pharmacy', ''),
    ];
  }

  // ── Live medicine cards ──

  _Med _medFrom(Map<String, dynamic> c) {
    final name = p3MedName(c);
    final weekly = c.str('frequency') == 'weekly';
    final food = p3Food(c.str('foodRelation'));
    final dose = weekly
        ? ['Once a week', if (p3WeekdayKey(c.str('weekday')).isNotEmpty) p3WeekdayKey(c.str('weekday'))].join(' · ')
        : [c.str('pattern'), if (food != null) food].join(' · ');
    final course = c.obj('course');
    final day = course.numOr('day', 1).toInt();
    final total = course['totalDays'] as num?;
    final dayText = weekly
        ? (total != null ? 'Week ${(day / 7).ceil()} of ${(total / 7).ceil()}' : 'Week ${(day / 7).ceil()}')
        : (total != null ? 'Day $day of ${total.toInt()}' : 'Day $day');
    final pct = c['adherencePct'] as num?;
    final few = p3FewDoses(c['adherenceCount']);
    final (taken, takenColor) = c['tracked'] == false
        ? ('Not tracked', MP.ink3)
        : c['asNeeded'] == true
        ? ('When needed', MP.ink2)
        : few != null
        ? (few, c.obj('adherenceCount').numOr('taken') == c.obj('adherenceCount').numOr('total') ? MP.green : MP.amber)
        : pct == null
        ? ('New', MP.ink3)
        : ('${pct.round()}%', pct >= 85 ? MP.green : MP.amber);
    final stock = c.obj('stock');
    // "When needed": how long it lasts depends on use, so just how many are left.
    final daysLeft = c['asNeeded'] == true ? null : stock['daysLeft'] as num?;
    final units = stock['units'] as num?;
    final stockText = units == null
        ? 'Not set'
        : daysLeft == null
        ? '${units.toInt()}'
        : weekly
        ? '${units.toInt()} · ${(daysLeft / 7).floor()} ${(daysLeft / 7).floor() == 1 ? 'week' : 'weeks'}'
        : '${units.toInt()} · ${daysLeft.toInt()} ${daysLeft == 1 ? 'day' : 'days'}';
    final stockColor = units == null ? MP.ink3 : (daysLeft != null && daysLeft <= 5 ? MP.amber : MP.ink);
    final start = F.date(c['startDate']);
    final by = [
      c.str('prescriber', c['selfAdded'] == true ? 'Added by you' : ''),
      if (start != null) p3Date(start),
      if (c['endDate'] == null) 'ongoing',
    ].where((s) => s.isNotEmpty).join(' · ');
    return _Med(name, dose, dayText, taken, takenColor, stockText, stockColor, by, _cartByCourse[c.str('id')], c);
  }

  /// "Metformin runs out on Friday" — the first medicine with 7 days or less.
  Map<String, dynamic>? get _refillCourse {
    for (final c in _courses) {
      final d = c.obj('stock')['daysLeft'] as num?;
      if (d != null && d <= 7) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = data != null;
    final liveSlots = live ? _liveSlots : const <(String, List<Map<String, dynamic>>)>[];
    final int taken;
    final int total;
    if (live) {
      final all = liveSlots.expand((s) => s.$2);
      taken = all.where((d) => _doseStatus(d) == 'taken').length;
      total = all.length;
    } else {
      final all = _status.expand((s) => s);
      taken = all.where((v) => v != null && v.isNotEmpty).length;
      total = all.length;
    }
    final inCart = live ? data!.obj('cart').numOr('count').toInt() : _cart.where((c) => c != null).length;
    final subtitle = live
        ? '${_medsData.numOr('running').toInt()} running · from ${_medsData.numOr('fromDoctors').toInt()} ${_medsData.numOr('fromDoctors') == 1 ? 'doctor' : 'doctors'}'
        : '5 running · from 3 doctors';
    final refill = live ? _refillCourse : null;

    return MpPage(
        nav: const PatientNav(current: 2),
        body: placeholder ?? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: title + cart button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Medicines', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                        const Gap(4),
                        Text(subtitle, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  _CartButton(count: inCart, onTap: () => Nav.go(context, 'Med-Cart')),
                ],
              ),
            ),
            VGap(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              gap: 16,
              children: [
                if (!live || total > 0) _todaysDoses(taken, total, liveSlots),
                if (live) for (final u in _medsData.list('fromUploads')) _fromUpload(u),
                if (!live) _refill() else if (refill != null) _refill(refill),
                _runningNow(),
                if (!live || _safetyShown) _safety(),
                _moreList(),
              ],
            ),
          ],
        ),
      );
  }

  Widget _todaysDoses(int taken, int total, List<(String, List<Map<String, dynamic>>)> liveSlots) {
    final live = data != null;
    final slotCount = live ? liveSlots.length : _slots.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      decoration: MPDeco.card(radius: 20, shadow: MPShadow.float),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text("Today's doses", style: tx(20, w: w700, h: 1.25))),
                Text('$taken of $total taken', style: tx(14, c: MP.ink2, tab: true)),
              ],
            ),
          ),
          for (var s = 0; s < slotCount; s++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: s == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text((live ? liveSlots[s].$1 : _slots[s].$1).toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                  if (live)
                    for (final d in liveSlots[s].$2) ...[const Gap(10), _liveDoseRow(d)]
                  else
                    for (var d = 0; d < _slots[s].$2.length; d++) ...[const Gap(10), _doseRow(s, d)],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _liveDoseRow(Map<String, dynamic> d) {
    final m = d.obj('medicine');
    final status = _doseStatus(d);
    final at = F.date(d['at']);
    final food = p3SlotFood(d.str('slot'), m.str('foodRelation'));
    final takenAt = F.date(d['takenAt']);
    final String? shown = switch (status) {
      'taken' => takenAt != null ? F.time(takenAt) : 'Taken',
      'skipped' => '',
      _ => null,
    };
    final sub = shown == null
        ? [if (at != null) F.time(at), if (food != null) food].join(' · ')
        : p3Cap(food ?? (at != null ? F.time(at) : ''));
    return _doseLine(
      p3MedName(m),
      sub,
      shown,
      onSkip: () => _markDose(d, 'skipped'),
      onTaken: () => _markDose(d, 'taken'),
      onUndo: () => _markDose(d, 'due'),
    );
  }

  Widget _doseRow(int s, int d) {
    final dose = _slots[s].$2[d];
    void set(String? v) => setState(() => _status[s][d] = v);
    return _doseLine(
      dose.$1,
      dose.$2,
      _status[s][d],
      onSkip: () => set(''),
      onTaken: () => set(p2Now()),
      onUndo: () => set(null),
    );
  }

  /// One dose: name + when, and Skip / Taken (due), a grey Skipped pill or the
  /// green taken time (tap either to undo).
  Widget _doseLine(
    String name,
    String sub,
    String? status, {
    required VoidCallback onSkip,
    required VoidCallback onTaken,
    required VoidCallback onUndo,
  }) {
    final due = status == null;

    Widget trailing;
    if (due) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          P2Box(
            onTap: onSkip,
            label: 'Skip $name',
            height: 40,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: MP.white,
            border: MP.lineStrong,
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Skip', style: tx(14, w: w600, c: MP.ink2))]),
          ),
          const Gap(6),
          P2Box(
            onTap: onTaken,
            label: 'Taken $name',
            height: 40,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: MP.primarySoft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('Taken', style: tx(14, w: w700, c: MP.primary))],
            ),
          ),
        ],
      );
    } else if (status.isEmpty) {
      // Skipped (not drawn in the design): grey pill, tap to undo.
      trailing = GestureDetector(
        onTap: onUndo,
        child: const P2Pill('Skipped', height: 28, padX: 10, fontSize: 13),
      );
    } else {
      trailing = MpHitSlop(child: Semantics(
        button: true,
        label: 'Taken at $status, tap to undo',
        child: GestureDetector(
          onTap: onUndo,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Ico(I.check, size: 14, color: MP.green, stroke: 2.5),
                const Gap(4),
                Text(status, style: tx(13, w: w700, c: MP.green)),
              ],
            ),
          ),
        ),
      ));
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: tx(16, w: w600, c: due ? MP.ink : MP.ink2)),
              const Gap(1),
              Text(sub, style: tx(13, c: MP.ink2)),
            ],
          ),
        ),
        const Gap(12),
        trailing,
      ],
    );
  }

  /// Medicines read from a prescription the patient uploaded: add them here.
  Widget _fromUpload(Map<String, dynamic> u) {
    final meds = u.list('medicines');
    final at = F.date(u['date']);
    String dose(Map<String, dynamic> m) => '${m.numOr('morning')}-${m.numOr('afternoon')}-${m.numOr('night')}';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('From your uploaded prescription', style: tx(18, w: w700, h: 1.3)),
          const Gap(2),
          Text([if (u.str('doctor').isNotEmpty) u.str('doctor'), if (at != null) F.dayMonth(at)].join(' · '), style: tx(14, c: MP.ink2, h: 1.4)),
          const Gap(10),
          for (final m in meds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${m.str('name')} ${m.str('strength')} · ${dose(m)}', style: tx(15, h: 1.4)),
            ),
          const Gap(8),
          Text('Check these against the paper before adding.', style: tx(13, c: MP.ink3, h: 1.4)),
          const Gap(12),
          MpButton('Add ${meds.length == 1 ? 'it' : 'all ${meds.length}'} to my medicines', onTap: () => _addFromUpload(u)),
        ],
      ),
    );
  }

  Future<void> _addFromUpload(Map<String, dynamic> u) async {
    final r = await runAction(context, () => Api.I.post('/api/patient/records/${u['recordId']}/add-medicines', const {}));
    if (r is! Map || !mounted) return;
    // What happened: added, already on the list, or added without times (no alarm until set).
    final added = (r['added'] as num?)?.toInt() ?? 0;
    final skipped = (r['skipped'] as List? ?? const []).length;
    final unclear = (r['unclear'] as List? ?? const []).length;
    toast(
      context,
      unclear > 0
          ? tr(context, 'Added. Some times were not clear: check them with your doctor before setting reminders.')
          : added == 0 && skipped > 0
          ? tr(context, 'You already take these medicines')
          : skipped > 0
          ? tr(context, 'Added · the ones you already take were skipped')
          : tr(context, 'Added · reminders are on for them'),
    );
    reload(quiet: true);
  }

  Widget _refill([Map<String, dynamic>? c]) {
    var title = 'Metformin runs out on Friday';
    var sub = '6 tablets left · 3 days';
    if (c != null) {
      final stock = c.obj('stock');
      final days = stock.numOr('daysLeft').toInt();
      final units = stock.numOr('units').toInt();
      final out = DateTime.now().add(Duration(days: days));
      final when = days <= 0 ? 'today' : (days == 1 ? 'tomorrow' : (days < 7 ? 'on ${p3Weekday(out)}' : 'on ${F.dayMonth(out)}'));
      title = '${c.str('name')} runs out $when';
      sub = '$units ${units == 1 ? 'tablet' : 'tablets'} left · $days ${days == 1 ? 'day' : 'days'}';
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MP.amberSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.amberLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(15, w: w700)),
                const Gap(2),
                Text(sub, style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Gap(12),
          P2Box(
            onTap: () async {
              if (c != null && _cartByCourse[c.str('id')] == null && !await _addCourseToCart(c)) return;
              if (mounted) Nav.go(context, 'Med-Cart');
            },
            height: 44,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: MP.white,
            shadow: MPShadow.hairline,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('Reorder', style: tx(14, w: w700, c: MP.primary))],
            ),
          ),
        ],
      ),
    );
  }

  Widget _runningNow() {
    final live = data != null;
    final courses = live ? _courses : const <Map<String, dynamic>>[];
    final meds = live ? [for (final c in courses) _medFrom(c)] : _meds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Running now', style: tx(20, w: w700, h: 1.25))),
              const Gap(8),
              Text('Sorted by what runs out first', style: tx(13, c: MP.ink3)),
            ],
          ),
        ),
        for (var i = 0; i < meds.length; i++) ...[
          const Gap(12),
          if (live)
            _MedCard(
              meds[i],
              inCart: meds[i].inCart,
              onCart: meds[i].inCart == null
                  ? () async {
                      if (await _addCourseToCart(courses[i]) && mounted) reload(quiet: true);
                    }
                  : () => Nav.go(context, 'Med-Cart'),
              onStock: () => _updateStock(courses[i]),
              onEdit: () => _editMedicine(courses[i]),
            )
          else
            _MedCard(
              meds[i],
              inCart: _cart[i],
              onCart: _cart[i] == null ? () => _addToCart(i) : () => Nav.go(context, 'Med-Cart'),
            ),
        ],
        if (live) ...[
          const Gap(12),
          // Not in the design: adding a medicine you take (same dashed box as the cart's suggestion).
          P2Box(
            onTap: () => _editMedicine(),
            dashed: true,
            border: MP.lineStrong,
            radius: 16,
            color: MP.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Ico(I.plus, size: 18, color: MP.primary, stroke: 2),
                const Gap(12),
                Expanded(child: Text('Add a medicine you take', style: tx(14, w: w600))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool get _safetyShown {
    final s = _medsData.obj('safety');
    return _medsData.list('items').isNotEmpty && (s.list('warnings').isNotEmpty || (_medsData['allergies'] as List? ?? const []).isNotEmpty);
  }

  Widget _safety() {
    var title = 'No clashes found';
    var body = 'Your 5 medicines from 3 doctors were checked against each other and your sulfa allergy.';
    var color = MP.green;
    if (data != null) {
      final warnings = _medsData.obj('safety').list('warnings');
      final allergies = [for (final a in (_medsData['allergies'] as List? ?? const [])) '$a'.toLowerCase()];
      final n = _medsData.numOr('running').toInt();
      final docs = _medsData.numOr('fromDoctors').toInt();
      if (warnings.isEmpty) {
        body = 'Your $n ${n == 1 ? 'medicine' : 'medicines'} from $docs ${docs == 1 ? 'doctor' : 'doctors'} '
            'were checked against your ${F.joinAnd(allergies)} ${allergies.length == 1 ? 'allergy' : 'allergies'}.';
      } else {
        title = 'Check with your doctor';
        body = [for (final w in warnings) '${w.str('medicine')}: ${w.str('text')}'].join('\n');
        color = MP.amber;
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Ico(_shieldCheck, size: 20, color: color)),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(15, w: w700)),
                const Gap(2),
                Text(body, style: tx(13, h: 1.45, c: MP.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moreList() {
    final live = data != null;
    final more = live ? _liveMore : _more;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: MPDeco.card(shadow: null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < more.length; i++)
            P2Box(
              onTap: live
                  ? () => _onMore(i)
                  : more[i].$3.isEmpty
                  ? () => toast(context, 'Medicine list saved as PDF')
                  : () => p2Missing(context, more[i].$3),
              label: more[i].$1,
              topBorder: i == 0 ? null : const BorderSide(color: MP.line),
              minHeight: i == 0 ? 60 : 61,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(more[i].$1, style: tx(15, w: w600)),
                        const Gap(2),
                        Text(more[i].$2, style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  const Ico(I.chevronRight, size: 18, color: MP.ink3),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// 44px round cart link (+1px border, content-box) with the item count badge.
class _CartButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CartButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        P2Box(
          onTap: onTap,
          label: count == 1 ? 'Cart, 1 item' : 'Cart, $count items',
          width: 46,
          height: 46,
          radius: 999,
          color: MP.white,
          border: MP.line,
          alignment: Alignment.center,
          child: const Ico(I.cart, size: 20, color: MP.ink),
        ),
        if (count > 0)
          Positioned(
            top: -1,
            right: -1,
            child: IgnorePointer(
              child: Container(
                height: 20,
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MP.primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MP.bg, width: 2),
                ),
                child: Text('$count', style: tx(11, w: w800, c: MP.white)),
              ),
            ),
          ),
      ],
    );
  }
}

class _MedCard extends StatelessWidget {
  final _Med m;
  final int? inCart;
  final VoidCallback onCart;

  /// Live: "Update stock" and tapping the medicine (edit / stop).
  final VoidCallback? onStock;
  final VoidCallback? onEdit;
  const _MedCard(this.m, {required this.inCart, required this.onCart, this.onStock, this.onEdit});

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tx(12, c: MP.ink2)),
          const Gap(2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(17, w: w800, c: color, tab: true)),
        ],
      ),
    );

    final carted = inCart != null;
    final cartFg = carted ? MP.green : MP.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MPDeco.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEdit,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: tx(18, w: w700)),
                      const Gap(3),
                      Text(m.dose, style: tx(14, tab: true)),
                    ],
                  ),
                ),
              ),
              const Gap(12),
              P2Pill(m.day, height: 24, padX: 10, tab: true),
            ],
          ),
          const Gap(14),
          Row(
            children: [
              Expanded(
                child: stat(
                  m.raw == null
                      ? 'Taken · 30 days'
                      : m.raw!['asNeeded'] == true
                          ? 'Doses'
                          : p3FewDoses(m.raw!['adherenceCount']) != null
                              ? p3TakenSince(context, m.raw!['adherenceCount'])
                              : 'Taken · 30 days',
                  m.taken,
                  m.takenColor,
                ),
              ),
              const Gap(8),
              Expanded(child: stat('In stock', m.stock, m.stockColor)),
            ],
          ),
          const Gap(14),
          MpHitSlop(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Nav.go(context, 'Patient-Records'),
            child: Row(
              children: [
                const Ico(I.fileText, size: 18, color: MP.ink2),
                const Gap(10),
                Expanded(child: Text(m.by, style: tx(13, h: 1.4, c: MP.ink2))),
                const Gap(10),
                Text('Prescription', style: tx(14, w: w700, c: MP.primary)),
              ],
            ),
          )),
          const Gap(16),
          const MpDivider(),
          const Gap(16),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: P2Box(
                  onTap: onStock ?? () => p2Missing(context, 'Updating stock'),
                  height: 48,
                  radius: 12,
                  color: MP.white,
                  border: MP.lineStrong,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.pill, size: 16, color: MP.ink),
                      const Gap(8),
                      Flexible(child: Text('Stock', maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: tx(14, w: w700))),
                    ],
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                flex: 6,
                child: P2Box(
                  onTap: onCart,
                  height: 48,
                  radius: 12,
                  color: carted ? MP.greenSoft : MP.primarySoft,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Ico(I.cart, size: 16, color: cartFg),
                      const Gap(6),
                      Flexible(
                        child: Text(
                          carted ? 'In cart · $inCart ${inCart == 1 ? 'strip' : 'strips'}' : 'Add to cart',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(14, w: w700, c: cartFg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live sheets (no screens for these in the design; built from the app's sheet
// pieces): stock, add / edit a medicine, reminder times, orders, past medicines.
// ─────────────────────────────────────────────────────────────────────────────

/// "Update stock": tablets at home now. Pops with the number.
class _StockSheet extends StatefulWidget {
  final Map<String, dynamic> course;
  const _StockSheet({required this.course});

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  late int _units = widget.course.obj('stock').numOr('units').toInt();

  void _step(int by) => setState(() => _units = (_units + by).clamp(0, 999));

  @override
  Widget build(BuildContext context) {
    final per = widget.course.numOr('unitsPerStrip', 10).toInt();
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          P2SheetHeader(title: 'Update stock', subtitle: '${p3MedName(widget.course)} · how many do you have at home?'),
          const Gap(20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tablets at home', style: tx(14, w: w600)),
                    const Gap(2),
                    Text('A strip has $per', style: tx(13, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              P2Stepper(
                value: '$_units',
                button: 44,
                valueWidth: 48,
                iconSize: 18,
                style: tx(17, w: w800, tab: true),
                label: 'Tablets at home',
                minusLabel: 'One less',
                plusLabel: 'One more',
                onMinus: () => _step(-1),
                onPlus: () => _step(1),
              ),
            ],
          ),
          const Gap(12),
          P2Box(
            onTap: () => _step(per),
            height: 44,
            radius: 12,
            alignment: Alignment.center,
            child: Text('Add a strip (+$per)', style: tx(14, w: w600, c: MP.primary)),
          ),
          const Gap(20),
          MpButton('Save', onTap: () => Navigator.of(context).pop(_units)),
        ],
      ),
    );
  }
}

/// Add a medicine you take, or edit one. Doctor-prescribed medicines can only
/// be tracked / untracked or stopped; ones you added can be edited in full.
class _MedicineSheet extends StatefulWidget {
  final Map<String, dynamic>? course;
  const _MedicineSheet({this.course});

  @override
  State<_MedicineSheet> createState() => _MedicineSheetState();
}

class _MedicineSheetState extends State<_MedicineSheet> {
  Map<String, dynamic> get _c => widget.course ?? const {};
  bool get _isNew => widget.course == null;
  bool get _editable => _isNew || _c['selfAdded'] == true;

  late final _name = TextEditingController(text: _c.str('name'));
  late final _strength = TextEditingController(text: _c.str('strength'));
  late final _by = TextEditingController(text: _c['selfAdded'] == true ? _c.str('prescriber') : '');
  late final _stock = TextEditingController(text: _isNew ? '' : '${_c.obj('stock')['units'] ?? ''}');
  late final Map<String, int> _dose = {
    for (final s in const ['morning', 'afternoon', 'night']) s: _isNew ? (s == 'morning' ? 1 : 0) : _c.obj('dose').numOr(s).toInt(),
  };
  late bool _weekly = _c.str('frequency') == 'weekly';
  late String _weekday = _c.str('weekday', 'sun');
  late String? _food = _c['foodRelation'] as String? ?? (_isNew ? 'after_food' : null);
  late bool _tracked = _c['tracked'] != false;
  final _busy = ValueNotifier(false);

  static const _foods = [('before_food', 'Before food'), ('after_food', 'After food'), ('with_food', 'With food'), ('bedtime', 'At bedtime')];
  static const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _by.dispose();
    _stock.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, dynamic>{};
    if (_editable) {
      if (_name.text.trim().isEmpty) {
        toast(context, 'Enter the medicine name');
        return;
      }
      if (_dose.values.every((v) => v == 0)) {
        toast(context, 'Pick when you take it');
        return;
      }
      body.addAll({
        'name': _name.text.trim(),
        'strength': _strength.text.trim(),
        'dose': _dose,
        'frequency': _weekly ? 'weekly' : 'daily',
        if (_weekly) 'weekday': _weekday,
        if (_food != null) 'foodRelation': _food,
        if (_by.text.trim().isNotEmpty) 'prescriberName': _by.text.trim(),
      });
      final stock = int.tryParse(_stock.text.trim());
      if (stock != null) body['stockUnits'] = stock;
    }
    if (!_isNew) body['trackingEnabled'] = _tracked;
    final ok = await runAction(
      context,
      () => _isNew ? Api.I.post('/api/patient/medicines', body) : Api.I.patch('/api/patient/medicines/${_c.str('id')}', body),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    toast(context, _isNew ? 'Medicine added' : 'Medicine updated');
    Navigator.of(context).pop(true);
  }

  Future<void> _stop() async {
    final yes = await p3Confirm(
      context,
      title: 'Stop ${p3MedName(_c)}?',
      body: _c['selfAdded'] == true
          ? 'It moves to your past medicines and reminders stop.'
          : 'Tell your doctor too. It moves to your past medicines and reminders stop.',
      confirm: 'Stop medicine',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(context, () => Api.I.patch('/api/patient/medicines/${_c.str('id')}', {'stop': true}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Medicine stopped');
    Navigator.of(context).pop(true);
  }

  Widget _doseStepper(String slot, String label) => Row(
    children: [
      Expanded(child: Text(label, style: tx(15, w: w600))),
      P2Stepper(
        value: '${_dose[slot]}',
        button: 40,
        valueWidth: 40,
        iconSize: 16,
        style: tx(15, w: w700, tab: true),
        label: '$label dose',
        onMinus: () => setState(() => _dose[slot] = (_dose[slot]! - 1).clamp(0, 9)),
        onPlus: () => setState(() => _dose[slot] = (_dose[slot]! + 1).clamp(0, 9)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          P2SheetHeader(
            title: _isNew ? 'Add a medicine' : p3MedName(_c),
            subtitle: _isNew
                ? 'A medicine you take that isn’t from a MedPin prescription.'
                : (_editable ? 'Added by you' : 'Prescribed by ${_c.str('prescriber', 'your doctor')}'),
          ),
          const Gap(20),
          if (_editable) ...[
            MpInput(label: 'Medicine', hint: 'e.g. Metformin', controller: _name),
            const Gap(12),
            MpInput(label: 'Strength', hint: 'e.g. 500 mg', controller: _strength),
            const Gap(16),
            P2Segmented(options: const ['Every day', 'Once a week'], index: _weekly ? 1 : 0, onChanged: (i) => setState(() => _weekly = i == 1)),
            const Gap(12),
            if (_weekly) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in _days)
                    MpChip(p3WeekdayKey(d).substring(0, 3), selected: _weekday == d, onTap: () => setState(() => _weekday = d)),
                ],
              ),
              const Gap(12),
            ],
            _doseStepper('morning', 'Morning'),
            const Gap(8),
            _doseStepper('afternoon', 'Afternoon'),
            const Gap(8),
            _doseStepper('night', 'Night'),
            const Gap(16),
            Text('When', style: tx(14, w: w600)),
            const Gap(8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in _foods) MpChip(f.$2, selected: _food == f.$1, onTap: () => setState(() => _food = f.$1)),
              ],
            ),
            const Gap(16),
            MpInput(label: 'Tablets at home', hint: 'e.g. 20', keyboard: TextInputType.number, controller: _stock),
            const Gap(12),
            MpInput(label: 'Prescribed by (optional)', hint: 'e.g. Dr. Rina Mitra', controller: _by),
            const Gap(16),
          ],
          if (!_isNew) ...[
            P2Box(
              onTap: () => setState(() => _tracked = !_tracked),
              label: 'Remind me and track doses',
              minHeight: 56,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Remind me and track doses', style: tx(15, w: w600)),
                        const Gap(2),
                        Text('Shows in today’s doses', style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  MpSwitch(value: _tracked, onChanged: (v) => setState(() => _tracked = v)),
                ],
              ),
            ),
            const Gap(16),
          ],
          MpButton(_isNew ? 'Add medicine' : 'Save', onTap: _save),
          if (!_isNew) ...[
            const Gap(8),
            MpButton('Stop this medicine', kind: MpBtn.dangerSoft, onTap: _stop),
          ],
        ],
      ),
    );
  }
}

/// Reminder times for the dose slots in use. PATCH /api/patient/me.
/// Meal times (breakfast / lunch / dinner) and bedtime: each dose rings around
/// its meal by how it's taken (before food 30 min before, after food 15 min after…).
class _ReminderSheet extends StatefulWidget {
  final Map<String, dynamic> times;
  final List<String> slots;
  final String bedAt;
  final bool bedtime;
  const _ReminderSheet({required this.times, required this.slots, this.bedAt = '22:30', this.bedtime = false});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  static const _defaults = {'morning': '08:00', 'afternoon': '13:30', 'night': '20:30'};
  static const _meals = {'morning': 'Breakfast', 'afternoon': 'Lunch', 'night': 'Dinner', 'bed': 'Bedtime'};
  late final Map<String, String> _t = {for (final s in _defaults.keys) s: widget.times.str(s, _defaults[s]!), 'bed': widget.bedAt};
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _pick(String slot) async {
    final p = _t[slot]!.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 8, minute: int.tryParse(p.last) ?? 0),
    );
    if (picked == null || !mounted) return;
    setState(() => _t[slot] = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _save() async {
    final meals = {for (final s in _defaults.keys) s: _t[s]};
    final ok = await runAction(context, () => Api.I.patch('/api/patient/me', {'settings': {'reminderTimes': meals, 'bedAt': _t['bed']}}), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Meal times saved · reminders follow them');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final slots = [...(widget.slots.isEmpty ? _defaults.keys.toList() : widget.slots), if (widget.bedtime) 'bed'];
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          const P2SheetHeader(
            title: 'Meal times',
            subtitle: 'Reminders follow your meals: before food 30 min before, after food 15 min after, with food at the meal.',
          ),
          const Gap(12),
          for (var i = 0; i < slots.length; i++)
            P3Row(
              _meals[slots[i]]!,
              p3Clock(_t[slots[i]]!),
              first: i == 0,
              onTap: () => _pick(slots[i]),
              trailing: Text('Change', style: tx(14, w: w600, c: MP.primary)),
            ),
          const Gap(20),
          MpButton('Save', onTap: _save),
        ],
      ),
    );
  }
}

/// Order history. Loads fresh from GET /api/patient/orders each time it
/// opens and after a payment or cancel, so each order's payment shows as it
/// really is: "Paid ✓", "Not paid" (online, unfinished) or "Pay at delivery".
class _OrdersSheet extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  const _OrdersSheet({required this.orders});

  @override
  State<_OrdersSheet> createState() => _OrdersSheetState();
}

class _OrdersSheetState extends State<_OrdersSheet> {
  late List<Map<String, dynamic>> _orders = widget.orders;
  bool _loading = isLive;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!isLive) return;
    try {
      final r = await Api.I.get('/api/patient/orders');
      if (!mounted || r is! List) return;
      setState(() => _orders = [for (final x in r) (x as Map).cast<String, dynamic>()]);
    } catch (_) {
      // Offline: keep what the Medicines screen had.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// (label, text colour, background) of an order's payment.
  static (String, Color, Color)? _payTag(Map<String, dynamic> o) {
    final pay = o.obj('pay');
    final status = o.str('status');
    return switch (pay.str('status')) {
      'paid' => ('Paid ✓', MP.green, MP.greenSoft),
      'refunded' => ('Refunded', MP.ink2, MP.fill),
      'refund_pending' => ('Refund on its way', MP.amber, MP.amberSoft),
      _ when status == 'cancelled' => null,
      _ when const {'delivered', 'picked_up'}.contains(status) => ('Paid at pharmacy', MP.ink2, MP.fill),
      _ when pay.str('method') == 'online' => ('Not paid', MP.amber, MP.amberSoft),
      _ => (o.str('mode') == 'pickup' ? 'Pay at the counter' : 'Pay at delivery', MP.ink2, MP.fill),
    };
  }

  Future<void> _options(Map<String, dynamic> o) async {
    final pay = o.obj('pay');
    final paid = pay.str('status') == 'paid';
    final status = o.str('status');
    final cancellable = const {'placed', 'confirmed'}.contains(status);
    // Unpaid and not yet handed over: can still be paid online.
    final payable = !paid && !const {'cancelled', 'delivered', 'picked_up'}.contains(status) && !pay.str('status').startsWith('refund');
    final at = F.date(o['createdAt']);
    final tag = _payTag(o);
    final choice = await openSheet<String>(
      context,
      (ctx) => MpSheet(
        title: o.obj('pharmacyId').str('name', 'Your order'),
        subtitle: [
          p3Rupees(o.numOr('total')),
          if (at != null) '${F.dayMonth(at)}, ${F.time(at)}',
          if (tag != null) tag.$1,
        ].join(' · '),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (paid) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: MP.greenSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Paid online${F.date(pay['paidAt']) != null ? ' on ${F.dayMonth(F.date(pay['paidAt'])!)}' : ''}. The pharmacy knows not to collect money.',
                style: tx(14, c: MP.green, h: 1.4),
              ),
            ),
            const Gap(12),
          ],
          if (payable) ...[MpButton('Pay ${p3Rupees(o.numOr('total'))} online', onTap: () => Navigator.pop(ctx, 'pay')), const Gap(10)],
          if (cancellable)
            MpButton(paid ? 'Cancel order · get a refund' : 'Cancel order', kind: MpBtn.secondary, onTap: () => Navigator.pop(ctx, 'cancel')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'pay') {
      await Checkout.pay(context, kind: 'order', id: '${o['id']}');
      if (mounted) await _refresh();
      return;
    }
    final yes = await d4Confirm(
      context,
      title: 'Cancel this order?',
      body: paid ? 'The pharmacy is told straight away and your money is refunded.' : 'The pharmacy is told straight away.',
      confirm: 'Cancel order',
    );
    if (!yes || !mounted) return;
    final r = await runAction(context, () => Api.I.post('/api/patient/orders/${o['id']}/cancel'));
    if (r == null || !mounted) return;
    toast(context, paid ? 'Order cancelled · refund started' : 'Order cancelled');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          const P2SheetHeader(title: 'Orders', subtitle: 'Medicines you ordered from a pharmacy'),
          const Gap(12),
          if (orders.isEmpty) _loading ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5))) : const P3Empty('No orders yet'),
          for (var i = 0; i < orders.length; i++)
            Builder(builder: (_) {
              final o = orders[i];
              final at = F.date(o['createdAt']);
              final items = o.list('items');
              final status = o.str('status');
              final tag = _payTag(o);
              final actionable = isLive && (const {'placed', 'confirmed'}.contains(status) || (tag?.$1 == 'Not paid'));
              final row = P3Row(
                o.obj('pharmacyId').str('name', 'Pharmacy'),
                [
                  // The time tells apart two orders on the same day.
                  if (at != null) '${F.dayMonth(at)}, ${F.time(at)}',
                  '${items.length} ${items.length == 1 ? 'medicine' : 'medicines'}',
                  p3Rupees(o.numOr('total')),
                  o.str('mode') == 'pickup' ? 'pick up' : 'delivery',
                  if (const {'placed', 'confirmed'}.contains(status) && o.str('etaText').isNotEmpty) o.str('etaText'),
                ].join(' · '),
                first: i == 0,
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    P2Pill(p3Cap(status.replaceAll('_', ' ')), bg: status == 'cancelled' ? MP.fill : MP.primarySoft, fg: status == 'cancelled' ? MP.ink3 : MP.primary),
                    if (tag != null) ...[const Gap(6), P2Pill(tag.$1, fg: tag.$2, bg: tag.$3)],
                  ],
                ),
              );
              if (!actionable) return row;
              return Tap(onTap: () => _options(o), radius: 12, child: row);
            }),
        ],
      ),
    );
  }
}

/// Past medicines: GET /api/patient/medicines?status=past.
class _PastSheet extends StatefulWidget {
  const _PastSheet();

  @override
  State<_PastSheet> createState() => _PastSheetState();
}

class _PastSheetState extends State<_PastSheet> with LiveData {
  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/medicines', query: {'status': 'past'});

  @override
  Widget build(BuildContext context) {
    final items = data?.list('items') ?? const [];
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          const P2SheetHeader(title: 'Past medicines', subtitle: 'Courses you finished or stopped'),
          const Gap(12),
          if (data == null)
            loadError == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))),
                  )
                : P3Empty(loadError!.message)
          else if (items.isEmpty)
            const P3Empty('No past medicines yet'),
          for (var i = 0; i < items.length; i++)
            Builder(builder: (_) {
              final c = items[i];
              final start = F.date(c['startDate']);
              final end = F.date(c['stoppedAt']) ?? F.date(c['endDate']);
              return P3Row(
                p3MedName(c),
                [
                  c.str('prescriber'),
                  if (start != null) '${p3Date(start)}${end != null ? ' – ${p3Date(end)}' : ''}',
                  c.str('status') == 'stopped' ? 'stopped' : 'completed',
                ].where((s) => s.isNotEmpty).join(' · '),
                first: i == 0,
              );
            }),
        ],
      ),
    );
  }
}

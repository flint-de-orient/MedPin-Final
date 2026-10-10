import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';
import '../../widgets/i18n.dart';

/// Design: Med-AddToCart.dc.html — "Medicines · add to cart" (sheet over Patient-Medicines).
/// Pops with the number of strips added.
class MedAddtocartSheet extends StatefulWidget {
  const MedAddtocartSheet({super.key});

  @override
  State<MedAddtocartSheet> createState() => _MedAddtocartSheetState();
}

/// (title, sub, strips, tag)
const _options = [
  ('Till my next visit', '2 strips · lasts till 1 Nov', 2, 'Suggested'),
  ('1 month', '3 strips · 30 days', 3, ''),
  ('3 months', '9 strips · 90 days', 9, ''),
];

/// Live args: {'course': a medicine from GET /api/patient/medicines,
/// 'nextVisitAt'}. Add posts to /api/patient/cart/items with the strips and
/// pack option (the server works the same strips out for the pack options).
class _MedAddtocartSheetState extends State<MedAddtocartSheet> {
  int _strips = 2;
  bool _init = false;
  final _busy = ValueNotifier(false);

  Map<String, dynamic>? get _course => isLive ? (Nav.args<Map>(context)?['course'] as Map?)?.cast<String, dynamic>() : null;

  DateTime? get _nextVisit => F.date(Nav.args<Map>(context)?['nextVisitAt']);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  // ── Live maths (same as POST /cart/items) ──

  double get _perDay => (_course?['perDay'] as num? ?? 1).toDouble();
  int get _perStrip => (_course?['unitsPerStrip'] as num? ?? 10).toInt();
  int get _stock => (_course?.obj('stock')['units'] as num? ?? 0).toInt();

  int _stripsFor(double days) => (days * _perDay / _perStrip).ceil().clamp(1, 99);

  /// (title, sub, strips, tag, packOption)
  List<(String, String, int, String, String)> get _liveOptions {
    final next = _nextVisit;
    final out = <(String, String, int, String, String)>[];
    if (next != null && next.isAfter(DateTime.now())) {
      final days = next.difference(DateTime.now()).inHours / 24;
      final strips = (((days.ceil() + 3) * _perDay - _stock) / _perStrip).ceil().clamp(1, 99);
      out.add(('Till my next visit', '${_s(strips)} · lasts till ${_lastsTill(strips)}', strips, 'Suggested', 'till_next_visit'));
    }
    out.add(('1 month', '${_s(_stripsFor(30))} · 30 days', _stripsFor(30), out.isEmpty ? 'Suggested' : '', '1_month'));
    out.add(('3 months', '${_s(_stripsFor(90))} · 90 days', _stripsFor(90), '', '3_months'));
    return out;
  }

  static String _s(int n) => n == 1 ? '1 strip' : '$n strips';

  String _lastsTill(int strips) {
    final days = _perDay <= 0 ? 0 : ((_stock + _perStrip * strips) / _perDay).floor();
    return p2Day(DateTime.now().add(Duration(days: days - 1)));
  }

  /// Atorvastatin: 12 tablets at home, 1 a day, 10 a strip.
  String get _covers => _course == null ? p2Day(p2FromToday(12 + 10 * _strips - 1)) : _lastsTill(_strips);

  String get _subtitle {
    final c = _course;
    if (c == null) return 'Strip of 10 tablets · you take 1 a day';
    final dose = c.obj('dose');
    final perTake = ['morning', 'afternoon', 'night'].map((s) => dose.numOr(s)).fold<num>(0, (a, b) => a + b).toInt();
    final weekly = c.str('frequency') == 'weekly';
    return 'Strip of $_perStrip tablets · you take ${perTake == 0 ? 1 : perTake} a ${weekly ? 'week' : 'day'}';
  }

  Future<void> _add() async {
    final c = _course;
    if (c == null) {
      if (isLive) {
        toast(context, 'Choose a medicine on the Medicines tab');
        return;
      }
      toast(context, _strips == 1 ? 'Added 1 strip to cart' : 'Added $_strips strips to cart');
      Navigator.of(context).pop(_strips);
      return;
    }
    final opts = _liveOptions;
    final match = opts.where((o) => o.$3 == _strips).toList();
    final pack = match.isEmpty ? 'custom' : match.first.$5;
    final ok = await runAction(
      context,
      () => Api.I.post('/api/patient/cart/items', {'courseId': c.str('id'), 'strips': _strips, 'packOption': pack}),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    p3CartChanged.value++;
    toast(context, _strips == 1 ? 'Added 1 strip to cart' : 'Added $_strips strips to cart');
    Navigator.of(context).pop(_strips);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init && _course != null) {
      _init = true;
      _strips = _liveOptions.first.$3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _course;
    final options = c == null ? [for (final o in _options) (o.$1, o.$2, o.$3, o.$4, '')] : _liveOptions;
    return MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(20),
            P2SheetHeader(title: c == null ? 'Atorvastatin 10 mg' : p3MedName(c), subtitle: _subtitle),
            const Gap(20),

            // How much do you need?
            Text('How much do you need?', style: tx(14, w: w600)),
            for (final o in options) ...[
              const Gap(8),
              _Option(
                title: o.$1,
                sub: o.$2,
                tag: o.$4,
                on: _strips == o.$3,
                onTap: () => setState(() => _strips = o.$3),
              ),
            ],
            const Gap(20),

            // Or pick strips
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Or pick strips', style: tx(14, w: w600)),
                      const Gap(2),
                      Text('Covers till $_covers with what you have', style: tx(13, c: MP.ink2)),
                    ],
                  ),
                ),
                const Gap(12),
                P2Stepper(
                  value: '$_strips',
                  button: 44,
                  valueWidth: 40,
                  iconSize: 18,
                  style: tx(17, w: w800, tab: true),
                  label: 'Number of strips',
                  minusLabel: 'One less strip',
                  plusLabel: 'One more strip',
                  onMinus: () {
                    if (_strips > 1) setState(() => _strips--);
                  },
                  onPlus: () {
                    if (_strips < 99) setState(() => _strips++);
                  },
                ),
              ],
            ),
            const Gap(20),

            Text('Final price depends on the pharmacy you pick at checkout.', style: tx(13, h: 1.45, c: MP.ink3)),
            const Gap(20),

            MpButton(_strips == 1 ? 'Add 1 strip to cart' : 'Add $_strips strips to cart', onTap: _add),
          ],
        ),
      );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String sub;
  final String tag;
  final bool on;
  final VoidCallback onTap;
  const _Option({required this.title, required this.sub, required this.tag, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    child: P2Box(
      onTap: onTap,
      label: title,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 16,
      color: on ? MP.primarySoft : MP.white,
      border: on ? MP.primary : MP.lineStrong,
      borderWidth: on ? 1.5 : 1,
      child: Row(
        children: [
          P2Radio(on),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title, style: tx(16, w: w700)), const Gap(2), Text(sub, style: tx(13, c: MP.ink2))],
            ),
          ),
          if (tag.isNotEmpty) ...[const Gap(14), P2Pill(tag, bg: MP.primary, fg: MP.white, fontSize: 11)],
        ],
      ),
    ),
  );
}

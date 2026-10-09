import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'common_p3.dart';

/// Design: Med-Cart.dc.html — "Medicines · cart".
class MedCartScreen extends StatefulWidget {
  const MedCartScreen({super.key});

  @override
  State<MedCartScreen> createState() => _MedCartScreenState();
}

class _Item {
  final String name;
  final String sub;

  /// Tablets a day and tablets already at home (10 a strip).
  final int perDay;
  final int stock;
  const _Item(this.name, this.sub, this.perDay, this.stock);
}

const _metformin = _Item('Metformin 500 mg', 'Dr. Arjun Sen · strip of 10', 2, 6);
const _atorvastatin = _Item('Atorvastatin 10 mg', 'Dr. Rina Mitra · strip of 10', 1, 12);
const _glimepiride = _Item('Glimepiride 1 mg', 'Dr. Arjun Sen · strip of 10', 1, 28);

/// Live data: GET /api/patient/cart (+ /medicines for the "Add … too?" hint).
/// The stepper and × change the cart on the server; Change picks or adds the
/// delivery address (POST /api/patient/addresses).
class _MedCartScreenState extends State<MedCartScreen> with LiveData {
  final _items = <_Item>[_metformin, _atorvastatin];
  final _qty = <int>[3, 2];
  String? _addressId;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([Api.I.get('/api/patient/cart'), Api.I.get('/api/patient/medicines')]);
    return {'cart': r[0], 'meds': r[1]};
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _cart => data!.obj('cart');
  List<Map<String, dynamic>> get _liveItems => _cart.list('items');

  /// The active medicine not in the cart that runs out first.
  Map<String, dynamic>? get _suggestion {
    final inCart = {for (final i in _liveItems) i.str('courseId')};
    Map<String, dynamic>? best;
    for (final c in data!.obj('meds').list('items')) {
      final d = c.obj('stock')['daysLeft'] as num?;
      if (d == null || inCart.contains(c.str('id'))) continue;
      if (best == null || d < (best.obj('stock')['daysLeft'] as num)) best = c;
    }
    return best;
  }

  List<Map<String, dynamic>> get _addresses => _cart.list('addresses');

  Map<String, dynamic>? get _address {
    final all = _addresses;
    if (all.isEmpty) return null;
    return all.firstWhere(
      (a) => a.str('id', a.str('_id')) == _addressId,
      orElse: () => all.firstWhere((a) => a['isDefault'] == true, orElse: () => all.first),
    );
  }

  Future<void> _applyCart(Future<dynamic> Function() call) async {
    final res = await runAction(context, call, busy: _busy);
    if (res is! Map || !mounted) return;
    setState(() => data = {...data!, 'cart': res.cast<String, dynamic>()});
    p3CartChanged.value++;
  }

  void _remove(int i) {
    if (data == null) {
      setState(() {
        _items.removeAt(i);
        _qty.removeAt(i);
      });
      return;
    }
    final id = _liveItems[i].str('_id', _liveItems[i].str('id'));
    _applyCart(() => Api.I.delete('/api/patient/cart/items/$id'));
  }

  void _change(int i, int by) {
    if (data == null) {
      final q = _qty[i] + by;
      if (q < 1 || q > 99) return;
      setState(() => _qty[i] = q);
      return;
    }
    final it = _liveItems[i];
    final q = it.numOr('strips', 1).toInt() + by;
    if (q < 1 || q > 99) return;
    setState(() => it['strips'] = q); // show it now; the server's cart replaces it
    _applyCart(() => Api.I.patch('/api/patient/cart/items/${it.str('_id', it.str('id'))}', {'strips': q}));
  }

  Future<void> _addSuggestion() async {
    if (data == null) {
      setState(() {
        _items.add(_glimepiride);
        _qty.add(1);
      });
      return;
    }
    final c = _suggestion;
    if (c == null) return;
    await _applyCart(() => Api.I.post('/api/patient/cart/items', {'courseId': c.str('id'), 'strips': 1, 'packOption': 'custom'}));
  }

  Future<void> _changeAddress() async {
    if (data == null) {
      p2Missing(context, 'Changing the address');
      return;
    }
    final current = _address;
    final picked = await openSheet<String>(
      context,
      (_) => _AddressSheet(addresses: _addresses, selected: current?.str('id', current.str('_id'))),
    );
    if (picked == null || !mounted) return;
    setState(() => _addressId = picked);
    await reload(quiet: true);
  }

  Future<void> _choosePharmacy(int n) async {
    if (n == 0) {
      toast(context, 'Your cart is empty');
      return;
    }
    final a = data == null ? null : _address;
    await Nav.go(context, 'Med-Pharmacy', args: {if (a != null) 'addressId': a.str('id', a.str('_id'))});
    if (mounted && data != null) reload(quiet: true);
  }

  static String _addressText(Map<String, dynamic> a) {
    final line = a.str('line');
    final area = a.str('area');
    return area.isEmpty || line.contains(area) ? line : '$line, $area';
  }

  String get _rxText {
    if (data == null) return "We'll attach Dr. Sen's 29 Sep and Dr. Mitra's 02 Feb prescriptions automatically.";
    final rx = _cart.list('prescriptions');
    if (rx.isEmpty) return 'No valid prescription on file yet. Add one so the pharmacy can check your order.';
    final parts = [
      for (final p in rx.take(3))
        "${F.doctorShort(p.str('doctorName', 'your doctor'))}'s${F.date(p['issuedAt']) != null ? ' ${F.dayMonth(F.date(p['issuedAt'])!)}' : ''}",
    ];
    return "We'll attach ${F.joinAnd(parts)} ${rx.length == 1 ? 'prescription' : 'prescriptions'} automatically.";
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = data != null;
    final n = live ? _liveItems.length : _items.length;
    final suggestion = live ? _suggestion : null;
    final suggest = live ? suggestion != null : !_items.contains(_glimepiride);
    final address = live ? _address : null;

    return MpPage(
        header: P2WhiteHeader(n == 1 ? 'Cart · 1 medicine' : 'Cart · $n medicines'),
        bottom: placeholder != null
            ? null
            : MpBottomBar(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: MpButton('Choose a pharmacy', onTap: () => _choosePharmacy(n)),
              ),
        // main: padding 16 20 120 — the pinned bar (97px) takes the rest.
        body: placeholder ?? VGap(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 23),
          gap: 16,
          children: [
            if (n == 0)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: MPDeco.card(),
                child: Text('Your cart is empty', style: tx(15, w: w600, c: MP.ink2)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: MPDeco.card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var i = 0; i < n; i++) live ? _liveItemRow(i) : _itemRow(i)],
                ),
              ),

            if (suggest)
              P2Box(
                onTap: _addSuggestion,
                dashed: true,
                border: MP.lineStrong,
                radius: 16,
                color: MP.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Ico(I.plus, size: 18, color: MP.primary, stroke: 2),
                    const Gap(12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: tx(14, w: w600),
                          children: [
                            TextSpan(text: suggestion == null ? 'Add Glimepiride too? ' : 'Add ${suggestion.str('name')} too? '),
                            TextSpan(
                              text: suggestion == null
                                  ? 'Runs out 28 Oct'
                                  : 'Runs out ${p2Day(DateTime.now().add(Duration(days: suggestion.obj('stock').numOr('daysLeft').toInt())))}',
                              style: tx(14, c: MP.ink2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Prescriptions attached
            Container(
              padding: const EdgeInsets.all(20),
              decoration: MPDeco.card(shadow: null),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Prescriptions attached', style: tx(15, w: w700)),
                            const Gap(2),
                            Text(_rxText, style: tx(13, h: 1.4, c: MP.ink2)),
                          ],
                        ),
                      ),
                      const Gap(12),
                      const P2Pill('Coming soon', height: 24, padX: 10),
                    ],
                  ),
                  const Gap(14),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Nav.go(context, 'Records-Add'),
                    child: Text('Attach prescriptions yourself for now', style: tx(14, w: w600, c: MP.primary)),
                  ),
                ],
              ),
            ),

            // Deliver to home
            Container(
              padding: const EdgeInsets.all(20),
              decoration: MPDeco.card(shadow: null),
              child: Row(
                children: [
                  const Ico(I.pin, size: 20, color: MP.ink2),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !live ? 'Deliver to home' : (address == null ? 'Add a delivery address' : 'Deliver to ${address.str('label', 'home').toLowerCase()}'),
                          style: tx(15, w: w700),
                        ),
                        const Gap(2),
                        Text(
                          !live
                              ? 'Flat 3B, 12 Purbachal Rd, Salt Lake'
                              : (address == null
                                    ? 'Or pick up from a pharmacy nearby'
                                    : _addressText(address)),
                          style: tx(13, c: MP.ink2),
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _changeAddress,
                    child: Text(live && address == null ? 'Add' : 'Change', style: tx(14, w: w600, c: MP.primary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _liveItemRow(int i) {
    final it = _liveItems[i];
    final q = it.numOr('strips', 1).toInt();
    final lasts = F.date(it['lastsTill']);
    final per = it.numOr('unitsPerStrip', 10).toInt();
    final sub = [it.str('prescriberName'), 'strip of $per'].where((s) => s.isNotEmpty).join(' · ');
    return _row(
      first: i == 0,
      name: it.str('name'),
      sub: sub.isEmpty ? '' : p3Cap(sub),
      lasts: lasts == null ? '' : 'Lasts till ${p2Day(lasts)}',
      q: q,
      onRemove: () => _remove(i),
      onMinus: () => _change(i, -1),
      onPlus: () => _change(i, 1),
    );
  }

  Widget _itemRow(int i) {
    final it = _items[i];
    final lasts = p2Day(p2FromToday((it.stock + 10 * _qty[i]) ~/ it.perDay - 1));
    return _row(
      first: i == 0,
      name: it.name,
      sub: it.sub,
      lasts: 'Lasts till $lasts',
      q: _qty[i],
      onRemove: () => _remove(i),
      onMinus: () => _change(i, -1),
      onPlus: () => _change(i, 1),
    );
  }

  Widget _row({
    required bool first,
    required String name,
    required String sub,
    required String lasts,
    required int q,
    required VoidCallback onRemove,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: tx(16, w: w700)),
                    const Gap(2),
                    Text(sub, style: tx(13, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              // 40px remove button, margin: -8px -8px 0 0.
              P2Bleed(
                width: 40,
                height: 40,
                top: 8,
                right: 8,
                child: MpIconButton(
                  I.close,
                  label: 'Remove $name',
                  size: 40,
                  iconSize: 18,
                  color: MP.ink2,
                  onTap: onRemove,
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(child: Text(lasts, style: tx(13, c: MP.ink2))),
              P2Stepper(
                value: q == 1 ? '1 strip' : '$q strips',
                button: 40,
                valueWidth: 64,
                iconSize: 16,
                style: tx(14, w: w700, tab: true),
                label: 'Strips of $name',
                onMinus: onMinus,
                onPlus: onPlus,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pick where to deliver, or add an address. Pops with the address id.
class _AddressSheet extends StatefulWidget {
  final List<Map<String, dynamic>> addresses;
  final String? selected;
  const _AddressSheet({required this.addresses, this.selected});

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late bool _adding = widget.addresses.isEmpty;
  final _label = TextEditingController(text: 'Home');
  final _line = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _pin = TextEditingController();
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    for (final c in [_label, _line, _area, _city, _pin]) {
      c.dispose();
    }
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_line.text.trim().isEmpty) {
      toast(context, 'Enter the address');
      return;
    }
    final res = await runAction(
      context,
      () => Api.I.post('/api/patient/addresses', {
        'label': _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
        'line': _line.text.trim(),
        'area': _area.text.trim(),
        'city': _city.text.trim(),
        'pincode': _pin.text.trim(),
        'isDefault': widget.addresses.isEmpty,
      }),
      busy: _busy,
    );
    if (res is! List || !mounted) return;
    final added = (res.last as Map).cast<String, dynamic>();
    toast(context, 'Address added');
    Navigator.of(context).pop(added.str('id', added.str('_id')));
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.addresses;
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          P2SheetHeader(title: _adding ? 'Add an address' : 'Deliver to', subtitle: _adding ? 'Where should the pharmacy deliver?' : 'Pick an address'),
          const Gap(12),
          if (!_adding) ...[
            for (var i = 0; i < list.length; i++)
              P2Box(
                onTap: () => Navigator.of(context).pop(list[i].str('id', list[i].str('_id'))),
                label: list[i].str('label', 'Address'),
                topBorder: i == 0 ? null : const BorderSide(color: MP.line),
                minHeight: 61,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    P2Radio(list[i].str('id', list[i].str('_id')) == widget.selected),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(list[i].str('label', 'Address'), style: tx(15, w: w600)),
                          const Gap(2),
                          Text(
                            [list[i].str('line'), list[i].str('city')].where((s) => s.isNotEmpty).join(', '),
                            style: tx(13, c: MP.ink2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Gap(8),
            P2Box(
              onTap: () => setState(() => _adding = true),
              height: 48,
              radius: 12,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Ico(I.plus, size: 16, color: MP.primary, stroke: 2),
                  const Gap(6),
                  Text('Add an address', style: tx(14, w: w600, c: MP.primary)),
                ],
              ),
            ),
          ] else ...[
            MpInput(label: 'Name', hint: 'Home, Office…', controller: _label),
            const Gap(12),
            MpInput(label: 'Address', hint: 'Flat, building, street', controller: _line),
            const Gap(12),
            Row(
              children: [
                Expanded(child: MpInput(label: 'Area', controller: _area)),
                const Gap(12),
                Expanded(child: MpInput(label: 'City', controller: _city)),
              ],
            ),
            const Gap(12),
            MpInput(label: 'PIN code', keyboard: TextInputType.number, controller: _pin),
            const Gap(20),
            MpButton('Save address', onTap: _save),
          ],
        ],
      ),
    );
  }
}

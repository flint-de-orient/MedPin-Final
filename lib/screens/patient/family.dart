import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';

/// Patient · Family on this phone: the account's own profile and each family member
/// (a child, a parent), each with their own medicines, visits and reports. Choosing one
/// opens the app for that person (Session.selectFamily → X-Patient-Id); their alarms ring
/// on this phone with their name. "Add family member" makes a new profile.
/// Live data: GET /api/patient/family, POST /api/patient/family.
class FamilySwitcher extends StatefulWidget {
  const FamilySwitcher({super.key});

  @override
  State<FamilySwitcher> createState() => _FamilySwitcherState();
}

class _FamilySwitcherState extends State<FamilySwitcher> {
  List<Map<String, dynamic>> _items = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // The list itself is the account's (whichever profile is open).
      final res = await Api.I.get('/api/patient/family', asPatient: '') as Map;
      if (!mounted) return;
      setState(() {
        _items = [for (final x in (res['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
        _loaded = true;
      });
    } on ApiException catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _pick(Map<String, dynamic> p) async {
    final me = p['me'] == true;
    final id = me ? null : '${p['id']}';
    if (id == Session.I.familyPatientId) return;
    await Session.I.selectFamily(id, name: me ? null : '${p['name']}');
    if (!mounted) return;
    toast(context, me ? tr(context, 'Your own profile') : trf(context, "Now showing {name}'s health", {'name': p['name']}));
    setState(() {});
  }

  Future<void> _add() async {
    final added = await openSheet<Map<String, dynamic>>(context, (_) => const _AddFamilySheet());
    if (added == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await _pick(added);
  }

  static const _relations = {'child': 'Child', 'spouse': 'Spouse', 'parent': 'Parent', 'sibling': 'Brother / sister', 'grandparent': 'Grandparent', 'other': 'Family'};

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final active = Session.I.familyPatientId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4), child: SectionLabel('Family on this phone', h: 1.35)),
        const Gap(8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in _items) ...[
                MpChip(
                  p['me'] == true ? tr(context, 'Me') : '${p['name']} · ${tr(context, _relations[p['relation']] ?? 'Family')}',
                  selected: p['me'] == true ? active == null : active == '${p['id']}',
                  onTap: () => _pick(p),
                ),
                const SizedBox(width: 8),
              ],
              MpChip('+ ${tr(context, 'Add family member')}', onTap: _add),
            ],
          ),
        ),
        if (active != null) ...[
          const Gap(8),
          Text(
            trf(context, "You're seeing {name}'s medicines, visits and reports. Their reminders ring on this phone.", {'name': Session.I.familyName ?? ''}),
            style: tx(13, c: MP.ink2, h: 1.4),
          ),
        ],
      ],
    );
  }
}

/// New family member: name, relation, gender, age. Pops the new profile row.
class _AddFamilySheet extends StatefulWidget {
  const _AddFamilySheet();

  @override
  State<_AddFamilySheet> createState() => _AddFamilySheetState();
}

class _AddFamilySheetState extends State<_AddFamilySheet> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  String _relation = 'child';
  String? _gender;
  final _busy = ValueNotifier(false);

  static const _relations = [('child', 'Child'), ('parent', 'Parent'), ('spouse', 'Spouse'), ('sibling', 'Brother / sister'), ('grandparent', 'Grandparent'), ('other', 'Other')];
  static const _genders = [('female', 'Female'), ('male', 'Male'), ('other', 'Other')];

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final age = int.tryParse(_age.text.trim());
    if (_name.text.trim().length < 2) return toast(context, 'Enter their name');
    if (_gender == null) return toast(context, 'Choose a gender');
    if (age == null || age < 0 || age > 120) return toast(context, 'Enter an age from 0 to 120');
    final res = await runAction(
      context,
      () => Api.I.post('/api/patient/family', {'name': _name.text.trim(), 'relation': _relation, 'gender': _gender, 'ageYears': age}, ''),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    Navigator.pop(context, res.cast<String, dynamic>());
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Add family member',
      subtitle: 'Their own medicines, visits and reports, on your phone. Their clinic links them with the consent code from their profile.',
      showClose: true,
      child: ValueListenableBuilder<bool>(
        valueListenable: _busy,
        builder: (context, busy, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MpInput(controller: _name, label: 'Name', hint: 'E.g. Aarav Sharma', height: 52),
            const Gap(14),
            Text('Relation', style: tx(14, w: w600)),
            const Gap(8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in _relations) MpChip(r.$2, selected: _relation == r.$1, onTap: () => setState(() => _relation = r.$1)),
            ]),
            const Gap(14),
            Text('Gender', style: tx(14, w: w600)),
            const Gap(8),
            Wrap(spacing: 8, children: [
              for (final g in _genders) MpChip(g.$2, selected: _gender == g.$1, onTap: () => setState(() => _gender = g.$1)),
            ]),
            const Gap(14),
            MpInput(controller: _age, label: 'Age in years', hint: 'E.g. 8', keyboard: TextInputType.number, height: 52),
            const Gap(18),
            MpButton(busy ? 'Saving…' : 'Add', onTap: busy ? null : _save),
          ],
        ),
      ),
    );
  }
}

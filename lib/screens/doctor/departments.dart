import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Departments.dc.html — "Departments".
class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  /// This practice's departments: name, dashboard panels using it.
  final _own = <(String, int)>[('Endocrinology', 3), ('Diabetology', 2)];

  /// Read-only specialties defined by MedPin.
  static const _shared = [('Cardiology', 4), ('General medicine', 2), ('Gynaecology', 1), ('Nephrology', 0)];

  static String _usage(int n) =>
      n == 0
          ? 'Not used'
          : n == 1
          ? 'Used by 1 dashboard panel'
          : 'Used by $n dashboard panels';

  Future<void> _edit(int i) async {
    final name = await openSheet<String>(
      context,
      (_) => _NameSheet(title: 'Edit department', action: 'Save', name: _own[i].$1),
    );
    if (name == null || !mounted) return;
    setState(() => _own[i] = (name, _own[i].$2));
    toast(context, 'Department saved');
  }

  Future<void> _add() async {
    final name = await openSheet<String>(
      context,
      (_) => const _NameSheet(title: 'Add department', action: 'Add department'),
    );
    if (name == null || !mounted) return;
    setState(() => _own.add((name, 0)));
    toast(context, 'Department added');
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Departments'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          // This practice (editable)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: D7Title('This practice', sub: 'Specialties City Care Clinic has added'),
                ),
                for (var i = 0; i < _own.length; i++)
                  _row(
                    _own[i].$1,
                    _own[i].$2,
                    MpIconButton(
                      I.edit,
                      label: 'Edit ${_own[i].$1}',
                      color: MP.primary,
                      iconSize: 20,
                      onTap: () => _edit(i),
                    ),
                    plainUsage: _own[i].$2 > 0,
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: D7Btn(
                    'Add department',
                    bg: MP.primarySoft,
                    icon: I.plus,
                    iconSize: 20,
                    expand: true,
                    onTap: _add,
                  ),
                ),
              ],
            ),
          ),

          // Shared specialties (read-only)
          MpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: D7Title('Shared specialties', sub: 'Defined by MedPin for every practice'),
                ),
                for (final s in _shared)
                  _row(
                    s.$1,
                    s.$2,
                    Semantics(
                      label: 'Read-only',
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(child: Ico(I.lock, size: 18, color: MP.ink3)),
                      ),
                    ),
                    plainUsage: s.$2 > 0,
                  ),
                D7Ruled(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    "Shared specialties are set by MedPin for all clinics, so they can't be edited here.",
                    style: tx(14, c: MP.ink2, h: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String name, int panels, Widget trailing, {required bool plainUsage}) {
    return D7Ruled(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600, h: 1.5)),
                const SizedBox(height: 2),
                Text(_usage(panels), style: tx(14, c: plainUsage ? MP.ink2 : MP.ink3, h: 1.45, tab: true)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// Name a department (add or rename).
class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.title, required this.action, this.name = ''});
  final String title;
  final String action;
  final String name;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _c = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final v = _c.text.trim();
    if (v.isEmpty) {
      toast(context, 'Enter a department name');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: widget.title,
      subtitle: 'Shown on dashboards and patient records',
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MpInput(label: 'Department name', controller: _c, hint: 'e.g. Rheumatology', autofocus: true),
          const SizedBox(height: 24),
          MpButton(widget.action, onTap: _done),
        ],
      ),
    );
  }
}

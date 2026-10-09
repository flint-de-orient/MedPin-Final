import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: People-Member.dc.html — "People · member".
class PeopleMemberScreen extends StatefulWidget {
  const PeopleMemberScreen({super.key});

  @override
  State<PeopleMemberScreen> createState() => _PeopleMemberScreenState();
}

class _PeopleMemberScreenState extends State<PeopleMemberScreen> {
  static const _departments = ['Endocrinology', 'Diabetology', 'Cardiology', 'General medicine'];

  String _role = "Doctor's assistant";
  String _department = 'Endocrinology';
  List<bool> _locations = [true, false];
  bool _suspended = false;

  String get _locationLabel {
    final names = [
      for (var i = 0; i < _locations.length; i++)
        if (_locations[i]) D9Locations.names[i],
    ];
    return names.isEmpty ? 'None' : names.join(', ');
  }

  Future<void> _pickLocations() async {
    final picked = await openSheet<List<bool>>(context, (_) => _LocationsSheet(_locations));
    if (picked != null && mounted) setState(() => _locations = picked);
  }

  void _save() {
    toast(context, 'Saved');
    Nav.back(context);
  }

  @override
  Widget build(BuildContext context) {
    final count = _locations.where((v) => v).length;
    return MpPage(
      header: const _MemberHeader(),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        gap: 16,
        children: [
          D9Labeled(
            'Role',
            child: D9Select(
              title: 'Role',
              value: _role,
              options: D9Roles.all,
              onChanged: (v) => setState(() => _role = v),
            ),
          ),
          D9Labeled(
            'Department',
            child: D9Select(
              title: 'Department',
              value: _department,
              options: _departments,
              onChanged: (v) => setState(() => _department = v),
            ),
          ),
          D9Labeled(
            'Locations',
            child: D9Field(
              value: _locationLabel,
              count: '$count of ${_locations.length}',
              right: 17,
              onTap: _pickLocations,
            ),
          ),

          // Read-only permissions from the role preset.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: D9Card(
              gap: 16,
              children: [
                D9Head('What this role can do', sub: 'Set by the $_role role', subH: 1.45),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (label, allowed) in D9Roles.perms(_role))
                      SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            allowed
                                ? const Ico(I.check, size: 18, color: MP.green, stroke: 2.25)
                                : const Ico(I.close, size: 18, color: MP.ink3, stroke: 2),
                            const Gap(12),
                            Expanded(child: Text(label, style: tx(15, c: allowed ? MP.ink : MP.ink3))),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Suspend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: MPDeco.card(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Suspend access', style: tx(16, w: w600, h: 1.5)),
                      const Gap(2),
                      Text('Suspended members lose access immediately.', style: tx(14, c: MP.ink2, h: 1.45)),
                    ],
                  ),
                ),
                const Gap(16),
                Semantics(
                  label: 'Suspend access',
                  child: MpSwitch(value: _suspended, onChanged: (v) => setState(() => _suspended = v)),
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: MpBottomBar(
        color: MP.bg,
        border: false,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: MpButton('Save', onTap: _save),
      ),
    );
  }
}

/// 64px bar: back, 40px avatar, name over phone · joined.
class _MemberHeader extends StatelessWidget {
  const _MemberHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: MP.bg,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(4),
          const MpAvatar('RS', size: 40, fontSize: 14),
          // margin-right 8 + gap 4
          const Gap(12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rohit Saha', style: tx(20, w: w700, h: 1.25), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '+91 98311 20486 · Joined Mar 2026',
                  style: tx(14, c: MP.ink2, h: 1.45, tab: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-select of the practice's locations, opened from the Locations field.
class _LocationsSheet extends StatefulWidget {
  final List<bool> initial;
  const _LocationsSheet(this.initial);

  @override
  State<_LocationsSheet> createState() => _LocationsSheetState();
}

class _LocationsSheetState extends State<_LocationsSheet> {
  late final List<bool> _selected = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Locations',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          D9Locations(value: _selected, onToggle: (i) => setState(() => _selected[i] = !_selected[i])),
          const Gap(20),
          MpButton('Done', onTap: () => Navigator.pop(context, _selected)),
        ],
      ),
    );
  }
}

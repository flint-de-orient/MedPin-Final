import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d9.dart';
import '../../widgets/i18n.dart';

/// Design: People-Member.dc.html — "People · member".
/// Live data (args `{'memberId'}`): GET /api/members/:id, /api/departments,
/// /api/locations; Save → PATCH /api/members/:id.
class PeopleMemberScreen extends StatefulWidget {
  const PeopleMemberScreen({super.key});

  @override
  State<PeopleMemberScreen> createState() => _PeopleMemberScreenState();
}

class _PeopleMemberScreenState extends State<PeopleMemberScreen> with LiveData {
  static const _sampleDepartments = ['Endocrinology', 'Diabetology', 'Cardiology', 'General medicine'];
  static const _noDepartment = 'None';

  String _role = "Doctor's assistant";
  String _department = 'Endocrinology';
  List<bool> _locations = [true, false];
  bool _suspended = false;
  final _busy = ValueNotifier(false);

  String? _memberId;

  @override
  Future<Object?> fetch() async {
    final a = Nav.args<Map>(context) ?? const {};
    _memberId = a['memberId'] as String?;
    if (_memberId == null) throw const ApiException(404, 'NO_MEMBER', 'Choose a team member first');
    final r = await Future.wait([
      Api.I.get('/api/members/$_memberId'),
      Api.I.get('/api/departments'),
      Api.I.get('/api/locations'),
    ]);
    final m = (r[0] as Map).cast<String, dynamic>();
    final locs = ((r[2] as Map)['items'] as List? ?? const []).cast<Map>();
    final mine = {for (final l in m.list('locations')) l.str('id')};
    _role = D9Roles.label(m.str('role'));
    _department = m.obj('department').str('name', _noDepartment);
    _locations = [for (final l in locs) m['allLocations'] == true || mine.contains('${l['id']}')];
    _suspended = m['status'] == 'suspended';
    return {'member': m, 'departments': r[1], 'locations': r[2]};
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _member => data!.obj('member');
  List<Map<String, dynamic>> get _locationItems => data!.obj('locations').list('items');
  List<Map<String, dynamic>> get _departmentItems => [
    for (final d in (data!['departments'] as List? ?? const [])) (d as Map).cast<String, dynamic>(),
  ];

  List<String> get _departments =>
      data == null ? _sampleDepartments : [for (final d in _departmentItems) d.str('name'), _noDepartment];

  List<String> get _locationNames =>
      data == null ? D9Locations.names : [for (final l in _locationItems) l.str('name')];

  String get _locationLabel {
    final labels = _locationNames;
    final names = [
      for (var i = 0; i < _locations.length && i < labels.length; i++)
        if (_locations[i]) labels[i],
    ];
    return names.isEmpty ? 'None' : names.join(', ');
  }

  Future<void> _pickLocations() async {
    final picked = await openSheet<List<bool>>(context, (_) => _LocationsSheet(_locations, labels: _locationNames));
    if (picked != null && mounted) setState(() => _locations = picked);
  }

  Future<void> _save() async {
    if (!isLive) {
      toast(context, 'Saved');
      Nav.back(context);
      return;
    }
    final m = _member;
    final locs = _locationItems;
    final ids = [
      for (var i = 0; i < locs.length && i < _locations.length; i++)
        if (_locations[i]) locs[i].str('id'),
    ];
    final dept = _departmentItems.where((d) => d.str('name') == _department).map((d) => d['id']).firstOrNull;
    final body = <String, Object?>{
      'role': D9Roles.key(_role),
      'departmentId': dept,
      'locationIds': ids,
      'allLocations': locs.isNotEmpty && ids.length == locs.length,
      // Only when it changed: the server refuses any suspend flag for the owner.
      if (_suspended != (m['status'] == 'suspended')) 'suspended': _suspended,
    };
    final res = await runAction(context, () => Api.I.patch('/api/members/$_memberId', body), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, 'Saved');
    Nav.back(context);
  }

  @override
  Widget build(BuildContext context) {
    final count = _locations.where((v) => v).length;
    final placeholder = livePlaceholder();
    final m = data == null ? null : _member;
    final joined = F.date(m?['joinedAt']);
    return MpPage(
      header: m == null
          ? const _MemberHeader()
          : _MemberHeader(
              name: m.str('name'),
              initials: F.initials(m.str('name')),
              line: [
                if (m.str('phone').isNotEmpty) D9Fmt.phone(m.str('phone')),
                if (joined != null) 'Joined ${D9Fmt.monthYear(joined)}',
              ].join(' · '),
            ),
      body: placeholder ?? VGap(
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
      bottom: placeholder != null
          ? null
          : MpBottomBar(
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
  final String name;
  final String initials;
  final String line;
  const _MemberHeader({this.name = 'Rohit Saha', this.initials = 'RS', this.line = '+91 98311 20486 · Joined Mar 2026'});

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
          MpAvatar(initials, size: 40, fontSize: 14),
          // margin-right 8 + gap 4
          const Gap(12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: tx(20, w: w700, h: 1.25), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  line,
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
  final List<String> labels;
  const _LocationsSheet(this.initial, {this.labels = D9Locations.names});

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
          D9Locations(
            value: _selected,
            labels: widget.labels,
            onToggle: (i) => setState(() => _selected[i] = !_selected[i]),
          ),
          const Gap(20),
          MpButton('Done', onTap: () => Navigator.pop(context, _selected)),
        ],
      ),
    );
  }
}

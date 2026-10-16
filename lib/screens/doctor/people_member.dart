import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart' show d4Confirm;
import 'common_d9.dart';
import 'people_access.dart';
import '../../widgets/i18n.dart';

/// Design: People-Member.dc.html — "People · member" ("Edit access").
/// Live data (args `{'memberId'}`): GET /api/members/:id (with what the viewer
/// may change: canEdit / canChangeRole / canSuspend / canRemove / lockReason)
/// and /api/members/options. Works for every role: role, locations, the
/// doctor(s) an assistant works for, department where the role has one, and
/// Suspend / Reactivate. Save → PATCH /api/members/:id; Remove from team →
/// DELETE /api/members/:id. Nobody changes their own access, only owners
/// change an owner, and the last owner can't be suspended or removed — the
/// server refuses these too.
class PeopleMemberScreen extends StatefulWidget {
  const PeopleMemberScreen({super.key});

  @override
  State<PeopleMemberScreen> createState() => _PeopleMemberScreenState();
}

class _PeopleMemberScreenState extends State<PeopleMemberScreen> with LiveData {
  // A form: don't refresh by itself while it's being changed.
  @override
  bool get autoRefresh => false;

  String _role = "Doctor's assistant";
  String? _department = 'Diabetology';
  List<bool> _locations = [true, false];
  final _assists = <String>{'as'};
  bool _suspended = false;
  final _busy = ValueNotifier(false);

  String? _memberId;

  @override
  Future<Object?> fetch() async {
    final a = Nav.args<Map>(context) ?? const {};
    _memberId = a['memberId'] as String?;
    if (_memberId == null) throw const ApiException(404, 'NO_MEMBER', 'Choose a team member first');
    final r = await Future.wait([Api.I.get('/api/members/$_memberId'), Api.I.get('/api/members/options')]);
    final m = (r[0] as Map).cast<String, dynamic>();
    final opts = (r[1] as Map).cast<String, dynamic>();
    final mine = {for (final l in m.list('locations')) l.str('id')};
    _role = D9Roles.label(m.str('role'));
    _department = m.obj('department').str('name', TeamOptions.noDepartment);
    _locations = [for (final l in opts.list('locations')) m['allLocations'] == true || mine.contains(l.str('id'))];
    _assists
      ..clear()
      ..addAll([for (final d in m.list('assists')) d.str('userId')]);
    _suspended = m['status'] == 'suspended';
    return {'member': m, 'options': opts};
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _member => data!.obj('member');
  TeamOptions get _options => TeamOptions(data?.obj('options'));
  List<(String, String)> get _locationItems => _options.locations;

  /// What the viewer may change (design preview: everything).
  bool get _canEdit => data == null || _member['canEdit'] == true;
  bool get _canChangeRole => data == null || _member['canChangeRole'] == true;
  bool get _canSuspend => data == null || _member['canSuspend'] == true;
  bool get _canRemove => data == null || _member['canRemove'] == true;
  String? get _lockReason => data == null ? null : _member['lockReason'] as String?;

  Set<String> get _chosenLocations => {
    for (var i = 0; i < _locationItems.length && i < _locations.length; i++)
      if (_locations[i]) _locationItems[i].$1,
  };

  List<({String id, String name, Set<String> locationIds, List<String> departments})> get _assistable {
    final at = _options.doctorsAt(_chosenLocations);
    // Keep a doctor already assisted even if their hours moved elsewhere.
    return [
      ...at,
      for (final d in _options.doctors)
        if (_assists.contains(d.id) && !at.any((x) => x.id == d.id)) d,
    ];
  }

  List<String> get _departments => _options.departmentsFor(_role, _chosenLocations, assists: _assists);

  /// The department shown: the saved / picked one if the role still offers it, else the first.
  String? get _departmentValue {
    final opts = _departments;
    if (opts.isEmpty) return null;
    return opts.contains(_department) ? _department : opts.first;
  }

  String _labelOf(List<bool> on, List<String> labels) {
    final names = [
      for (var i = 0; i < on.length && i < labels.length; i++)
        if (on[i]) labels[i],
    ];
    return names.isEmpty ? 'None' : names.join(', ');
  }

  Future<void> _pickLocations() async {
    final picked = await openSheet<List<bool>>(
      context,
      (_) => _LocationsSheet(_locations, labels: [for (final l in _locationItems) l.$2]),
    );
    if (picked == null || !mounted) return;
    setState(() => _locations = picked);
  }

  Future<void> _pickAssists() async {
    final docs = _assistable;
    final picked = await openSheet<List<bool>>(
      context,
      (_) => _LocationsSheet(
        [for (final d in docs) _assists.contains(d.id)],
        labels: [for (final d in docs) d.departments.isEmpty ? d.name : '${d.name} · ${d.departments.join(', ')}'],
        title: 'Assists',
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _assists
        ..clear()
        ..addAll([for (var i = 0; i < docs.length && i < picked.length; i++) if (picked[i]) docs[i].id]);
      _department = null; // follows the doctor(s) they assist
    });
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    final ids = _chosenLocations.toList();
    if (ids.isEmpty) return toast(context, 'Choose at least one location');
    if (_role == "Doctor's assistant" && _assists.isEmpty && _options.doctors.isNotEmpty) {
      return toast(context, 'Choose the doctor they assist');
    }
    if (!isLive) {
      toast(context, 'Saved');
      Nav.back(context);
      return;
    }
    final m = _member;
    final dep = _departmentValue;
    final body = <String, Object?>{
      if (_canChangeRole) 'role': D9Roles.key(_role),
      // '' clears it (front desk, lab roles and practice managers have none).
      'departmentName': dep == null || dep == TeamOptions.noDepartment ? '' : dep,
      'locationIds': ids,
      'allLocations': _locations.isNotEmpty && _locations.every((v) => v),
      if (_role == "Doctor's assistant") 'assistsDoctorIds': _assists.toList(),
      // Only when it changed: the server refuses it for the last owner.
      if (_canSuspend && _suspended != (m['status'] == 'suspended')) 'suspended': _suspended,
    };
    final res = await runAction(context, () => Api.I.patch('/api/members/$_memberId', body), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, 'Saved');
    Nav.back(context);
  }

  Future<void> _remove() async {
    final name = data == null ? 'Rohit Saha' : _member.str('name', 'this person');
    final ok = await d4Confirm(
      context,
      title: 'Remove $name from the team?',
      body: 'Their access ends at once. Their name stays on past visits and records. You can add them again later.',
      confirm: 'Remove from team',
    );
    if (!ok || !mounted) return;
    if (!isLive) {
      toast(context, 'Removed from team');
      Nav.back(context);
      return;
    }
    final res = await runAction(context, () => Api.I.delete('/api/members/$_memberId'), busy: _busy);
    if (res == null || !mounted) return;
    toast(context, 'Removed from team');
    Nav.back(context);
  }

  /// A field that can't be changed here: the value, no picker.
  Widget _fixed(String value) => Opacity(opacity: 0.6, child: D9Field(value: value, chevronColor: MP.line));

  @override
  Widget build(BuildContext context) {
    final count = _locations.where((v) => v).length;
    final placeholder = livePlaceholder();
    final m = data == null ? null : _member;
    final joined = F.date(m?['joinedAt']);
    final edit = _canEdit;
    final dep = placeholder == null ? _departmentValue : null;
    final docs = placeholder == null ? _assistable : const <({String id, String name, Set<String> locationIds, List<String> departments})>[];
    final lock = _lockReason;
    return MpPage(
      header: m == null
          ? const _MemberHeader()
          : _MemberHeader(
              name: m.str('name'),
              initials: F.initials(m.str('name')),
              photo: m.str('photo').isEmpty ? null : m.str('photo'),
              line: [
                if (m.str('phone').isNotEmpty) D9Fmt.phone(m.str('phone')),
                if (joined != null) 'Joined ${D9Fmt.monthYear(joined)}',
              ].join(' · '),
            ),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [
          // Why some (or all) of this can't be changed by you.
          if (lock != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Ico(I.lock, size: 18, color: MP.primary),
                  const Gap(10),
                  Expanded(child: Text(lock, style: tx(14, c: MP.ink2, h: 1.4))),
                ],
              ),
            ),
          D9Labeled(
            'Role',
            child: edit && _canChangeRole
                ? D9Select(
                    title: 'Role',
                    value: _role,
                    options: D9Roles.all,
                    onChanged: (v) => setState(() {
                      _role = v;
                      _department = null; // the new role's own default
                    }),
                  )
                : _fixed(m?['isOwner'] == true ? '$_role · Owner' : _role),
          ),
          D9Labeled(
            'Locations',
            child: edit
                ? D9Field(
                    value: _labelOf(_locations, [for (final l in _locationItems) l.$2]),
                    count: '$count of ${_locations.length}',
                    right: 17,
                    onTap: _pickLocations,
                  )
                : _fixed(_labelOf(_locations, [for (final l in _locationItems) l.$2])),
          ),
          if (_role == "Doctor's assistant")
            D9Labeled(
              'Assists',
              child: docs.isEmpty
                  ? Text('No doctors practise at the chosen locations yet.', style: tx(14, c: MP.ink2, h: 1.4))
                  : edit
                      ? D9Field(value: _labelOf([for (final d in docs) _assists.contains(d.id)], [for (final d in docs) d.name]), right: 17, onTap: _pickAssists)
                      : _fixed(_labelOf([for (final d in docs) _assists.contains(d.id)], [for (final d in docs) d.name])),
            ),
          if (dep != null)
            D9Labeled(
              'Department',
              child: edit
                  ? D9Select(title: 'Department', value: dep, options: _departments, onChanged: (v) => setState(() => _department = v))
                  : _fixed(dep),
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

          // Suspend / reactivate
          if (_canSuspend)
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
                        Text(
                          m?['status'] == 'suspended'
                              ? 'Suspended now. Switch off and save to give their access back.'
                              : 'Suspended members lose access immediately.',
                          style: tx(14, c: MP.ink2, h: 1.45),
                        ),
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
          if (_canRemove)
            MpButton('Remove from team', kind: MpBtn.dangerSoft, height: 48, onTap: _remove),
        ],
      ),
      bottom: placeholder != null || !edit
          ? null
          : MpBottomBar(
              color: MP.bg,
              border: false,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: ValueListenableBuilder<bool>(
                valueListenable: _busy,
                builder: (_, busy, _) => MpButton(busy ? 'Saving…' : 'Save', onTap: busy ? null : _save),
              ),
            ),
    );
  }
}

/// 64px bar: back, 40px avatar, name over phone · joined.
class _MemberHeader extends StatelessWidget {
  final String name;
  final String initials;
  final String line;
  final String? photo;
  const _MemberHeader({this.name = 'Rohit Saha', this.initials = 'RS', this.line = '+91 98311 20486 · Joined Mar 2026', this.photo});

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
          MpAvatar(initials, size: 40, fontSize: 14, photo: photo),
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

/// Multi-select sheet: the practice's locations (Locations field) or the
/// doctors an assistant works for (Assists field).
class _LocationsSheet extends StatefulWidget {
  final List<bool> initial;
  final List<String> labels;
  final String title;
  const _LocationsSheet(this.initial, {this.labels = D9Locations.names, this.title = 'Locations'});

  @override
  State<_LocationsSheet> createState() => _LocationsSheetState();
}

class _LocationsSheetState extends State<_LocationsSheet> {
  late final List<bool> _selected = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: widget.title,
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

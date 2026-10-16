import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';
import '../../widgets/i18n.dart';

/// Design: Doctor-Patients.dc.html — "Doctor · Patients tab".
/// Live data: GET /api/patients?filter=all|today|follow_up_due|abnormal&sort=recent|name.
class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _Patient {
  final String name;
  final String meta;
  final String cond;
  final String last;
  final String? flag;
  final Color flagColor;

  /// Live: the patient's id (null in the design preview).
  final String? id;

  /// Which branch they go to: "Salt Lake" or "Salt Lake · last at New Town".
  final String? branch;

  /// Their profile photo (set in the patient app).
  final String? photo;
  const _Patient(this.name, this.meta, this.cond, this.last, [this.flag, this.flagColor = MP.ink2, this.id, this.branch, this.photo]);

  String get initials {
    final s = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).join();
    return s.length > 2 ? s.substring(0, 2) : s;
  }
}

const _filterKeys = ['all', 'today', 'follow_up_due', 'abnormal'];

/// Flag shown on every row of a filtered list (the reason it is in it).
const _filterFlags = [null, ('Booked today', MP.primary), ('Follow-up due', MP.amber), ('Abnormal results · not reviewed', MP.amber)];

const _filters = [('All', '248'), ('Today', '12'), ('Follow-up due', '9'), ('Abnormal results', '14')];

const _patients = [
  _Patient(
    'Priya Sharma',
    '29 F · +91 98765 43210',
    'Type 2 diabetes · PCOS',
    'Today',
    'Urgent chat · not reviewed',
    MP.red,
  ),
  _Patient(
    'Rahul Das',
    '45 M · +91 98311 20764',
    'High BP · first visit',
    'Today',
    'In queue · waiting 22 min',
    MP.primary,
  ),
  _Patient('Aisha Khan', '52 F · +91 90070 41288', 'Hypothyroidism', 'Today', 'In queue · waiting 15 min', MP.primary),
  _Patient('Debasish Bose', '62 M · +91 98740 33126', 'Type 2 diabetes', 'Today'),
  _Patient('Farhana Islam', '34 F · +91 90511 72830', 'Anaemia', 'Today', 'Haemoglobin 9.1 g/dL · low', MP.amber),
  _Patient(
    'Amit Pal',
    '55 M · +91 98303 11942',
    'Type 2 diabetes · CKD',
    '24 Sep',
    'Creatinine up since last visit',
    MP.amber,
  ),
  _Patient(
    'Moumita Roy',
    '41 F · +91 97480 62215',
    'Under cardiology review',
    '02 Sep',
    'Booked today · 11:00 AM',
    MP.primary,
  ),
  _Patient(
    'Sujit Mondal',
    '37 M · +91 98362 50417',
    'Fever, cough · first visit',
    'Today',
    'In queue · waiting 6 min',
    MP.primary,
  ),
];

const _sorts = ['Recent visits first', 'Name, A to Z'];

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> with LiveData {
  int _filter = 0;
  String _sort = _sorts.first;
  int _limit = 50;

  /// Branch filter: null = all branches.
  String? _branchId;

  @override
  Future<Object?> fetch() => Api.I.get('/api/patients', query: {
        'filter': _filterKeys[_filter],
        'sort': _sort == _sorts.first ? 'recent' : 'name',
        'limit': _limit,
        if (_branchId != null) 'locationId': _branchId,
      });

  List<Map<String, dynamic>> get _branches => data?.list('locations') ?? const [];

  String get _branchLabel => _branchId == null ? 'All branches' : _branches.where((b) => b.str('id') == _branchId).map((b) => b.str('name')).firstOrNull ?? 'All branches';

  /// "Salt Lake" · "Salt Lake · last at New Town" (only when they've been to more than one).
  static String? _branchOf(Map<String, dynamic> p) {
    final b = p.obj('branch');
    final usual = b.obj('usual').str('name');
    final last = b.obj('last').str('name');
    if (usual.isEmpty) return last.isEmpty ? null : last;
    return last.isNotEmpty && last != usual ? '$usual · last at $last' : usual;
  }

  Future<void> _pickBranch() async {
    final names = ['All branches', for (final b in _branches) b.str('name')];
    final v = await d2PickOption(context, title: 'Branch', options: names, value: _branchLabel);
    if (v == null || !mounted) return;
    setState(() {
      _branchId = v == 'All branches' ? null : _branches.firstWhere((b) => b.str('name') == v).str('id');
      _limit = 50;
    });
    reload(quiet: true);
  }

  bool _inFilter(_Patient p) => switch (_filter) {
    1 => p.last == 'Today',
    2 => p.last != 'Today',
    3 => p.flagColor == MP.amber,
    _ => true,
  };

  List<_Patient> get _visible {
    final d = data;
    if (d != null) {
      final flag = _filterFlags[_filter];
      return [
        for (final p in d.list('items'))
          () {
            // Reports this patient shared that I haven't opened yet (cleared when I open the patient).
            final n = p.numOr('newReports').toInt();
            final shared = n == 0 ? null : (tr(context, n == 1 ? '1 new report shared' : '#1 new reports shared').replaceFirst('#1', '$n'), MP.primary);
            final f = flag ?? shared;
            return _Patient(
            p.str('name'),
            d2PatientMeta(p),
            [for (final c in (p['conditions'] as List? ?? const [])) '$c'].join(' · '),
            d2LastSeen(p['lastVisitAt']),
            f?.$1,
            f?.$2 ?? MP.ink2,
            p.str('id'),
            _branches.length > 1 ? _branchOf(p) : null,
            p.str('photo').isEmpty ? null : p.str('photo'),
          );
          }(),
      ];
    }
    final list = _patients.where(_inFilter).toList();
    if (_sort != _sorts.first) list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  List<(String, String)> get _chipLabels {
    final d = data;
    if (d == null) return _filters;
    final c = d.obj('counts');
    return [
      ('All', '${c.numOr('all')}'),
      ('Today', '${c.numOr('today')}'),
      ('Follow-up due', '${c.numOr('followUpDue')}'),
      ('Abnormal results', '${c.numOr('abnormal')}'),
    ];
  }

  void _setFilter(int i) {
    setState(() {
      _filter = i;
      _limit = 50;
    });
    if (isLive) reload(quiet: true);
  }

  Future<void> _pickSort() async {
    final v = await d2PickOption(context, title: 'Sort patients', options: _sorts, value: _sort);
    if (v != null && mounted) {
      setState(() => _sort = v);
      if (isLive) reload(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final placeholder = livePlaceholder();
    final d = data;
    final all = d?.obj('counts').numOr('all').toInt();
    final more = d == null || d.list('items').length < d.numOr('total');
    return MpPage(
      header: D2TabHeader(
        title: 'Patients',
        subtitle: all == null ? '248 patients · all locations' : '$all ${all == 1 ? 'patient' : 'patients'} · ${_branchId == null ? 'all branches' : _branchLabel}',
        action: D2PillButton('Add patient', icon: I.plus, onTap: () => Nav.go(context, 'Add-Patient')),
        search: D2SearchField(
          hint: 'Search by name or mobile number',
          onTap: () => Nav.go(context, 'Doctor-Patients-Search'),
        ),
        chips: [
          for (final (i, f) in _chipLabels.indexed)
            D2Chip(
              f.$1,
              count: f.$2,
              selected: i == _filter,
              onTap: () => _setFilter(i),
            ),
        ],
      ),
      nav: const DoctorNav(current: 1),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        gap: 10,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(child: D2Caps(_sort)),
                if (_branches.length > 1) ...[
                  MpHitSlop(child: Tap(
                    onTap: _pickBranch,
                    radius: 8,
                    child: SizedBox(
                      height: 32,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Ico(I.pin, size: 15, color: MP.primary, stroke: 2),
                            const Gap(4),
                            Text(_branchLabel, style: tx(14, w: w600, c: MP.primary)),
                            const Gap(2),
                            const Ico(I.chevronDown, size: 16, color: MP.primary, stroke: 2),
                          ],
                        ),
                      ),
                    ),
                  )),
                  const Gap(12),
                ],
                MpHitSlop(child: Tap(
                  onTap: _pickSort,
                  radius: 8,
                  child: SizedBox(
                    height: 32,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Sort', style: tx(14, w: w600, c: MP.primary)),
                          const Gap(4),
                          const Ico(I.chevronDown, size: 16, color: MP.primary, stroke: 2),
                        ],
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ),
          if (d != null && list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('No patients here yet', style: tx(14, c: MP.ink2)),
            ),
          for (final p in list) _PatientCard(p),
          if (more) SizedBox(
            height: 48,
            child: Tap(
              onTap: () {
                if (!isLive) {
                  toast(context, 'No more patients to show');
                  return;
                }
                _limit += 50;
                reload(quiet: true);
              },
              radius: 12,
              child: Center(child: Text('Show more patients', style: tx(15, w: w600, c: MP.primary))),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final _Patient p;
  const _PatientCard(this.p);

  @override
  Widget build(BuildContext context) {
    return MpCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MpAvatar(p.initials, size: 44, fontSize: 15, photo: p.photo),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.name, style: tx(16, w: w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const Gap(8),
                        Text(p.last, style: tx(12, c: MP.ink3)),
                      ],
                    ),
                    const Gap(3),
                    Text(p.meta, style: tx(13, c: MP.ink2, tab: true)),
                    if (p.branch != null) ...[
                      const Gap(3),
                      Row(children: [
                        const Ico(I.pin, size: 13, color: MP.ink3, stroke: 2),
                        const Gap(4),
                        Expanded(child: Text(p.branch!, style: tx(13, c: MP.ink3), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                    if (p.cond.isNotEmpty) ...[
                      const Gap(3),
                      Text(p.cond, style: tx(13)),
                    ],
                    if (p.flag != null) ...[
                      // column gap 3 + margin-top 3
                      const Gap(6),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: p.flagColor, shape: BoxShape.circle),
                          ),
                          const Gap(6),
                          Expanded(child: Text(p.flag!, style: tx(13, w: w600, c: p.flagColor))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),
          D2ViewConsult(
            onView: () => Nav.go(context, 'PP-Summary', args: p.id == null ? null : {'patientId': p.id}),
            onConsult: () => Nav.go(context, 'Consult-Page', args: p.id == null ? null : {'patientId': p.id}),
          ),
        ],
      ),
    );
  }
}

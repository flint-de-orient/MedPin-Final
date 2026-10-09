import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d2.dart';

/// Design: Doctor-Patients.dc.html — "Doctor · Patients tab".
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
  const _Patient(this.name, this.meta, this.cond, this.last, [this.flag, this.flagColor = MP.ink2]);

  String get initials {
    final s = name.split(' ').map((w) => w[0]).join();
    return s.length > 2 ? s.substring(0, 2) : s;
  }
}

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

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  int _filter = 0;
  String _sort = _sorts.first;

  bool _inFilter(_Patient p) => switch (_filter) {
    1 => p.last == 'Today',
    2 => p.last != 'Today',
    3 => p.flagColor == MP.amber,
    _ => true,
  };

  List<_Patient> get _visible {
    final list = _patients.where(_inFilter).toList();
    if (_sort != _sorts.first) list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> _pickSort() async {
    final v = await d2PickOption(context, title: 'Sort patients', options: _sorts, value: _sort);
    if (v != null && mounted) setState(() => _sort = v);
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    return MpPage(
      header: D2TabHeader(
        title: 'Patients',
        subtitle: '248 patients · all locations',
        action: D2PillButton('Add patient', icon: I.plus, onTap: () => Nav.go(context, 'Add-Patient')),
        search: D2SearchField(
          hint: 'Search by name or mobile number',
          onTap: () => Nav.go(context, 'Doctor-Patients-Search'),
        ),
        chips: [
          for (var i = 0; i < _filters.length; i++)
            D2Chip(
              _filters[i].$1,
              count: _filters[i].$2,
              selected: i == _filter,
              onTap: () => setState(() => _filter = i),
            ),
        ],
      ),
      nav: const DoctorNav(current: 1),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        gap: 10,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(child: D2Caps(_sort)),
                Tap(
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
                ),
              ],
            ),
          ),
          for (final p in list) _PatientCard(p),
          SizedBox(
            height: 48,
            child: Tap(
              onTap: () => toast(context, 'No more patients to show'),
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
              MpAvatar(p.initials, size: 44, fontSize: 15),
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
                    const Gap(3),
                    Text(p.cond, style: tx(13)),
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
            onView: () => Nav.go(context, 'PP-Summary'),
            onConsult: () => Nav.go(context, 'Consult-Page'),
          ),
        ],
      ),
    );
  }
}

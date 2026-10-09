import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d9.dart';

/// Design: People-Add.dc.html — "People · add".
class PeopleAddScreen extends StatefulWidget {
  const PeopleAddScreen({super.key});

  @override
  State<PeopleAddScreen> createState() => _PeopleAddScreenState();
}

class _PeopleAddScreenState extends State<PeopleAddScreen> {
  static const _departments = [
    'Endocrinology',
    'Diabetology',
    'Cardiology',
    'General medicine',
    'Gynaecology',
    'Nephrology',
  ];

  String _role = 'Doctor';
  String _department = 'Endocrinology';
  final _locations = [true, false];

  // Doctor-only fields keep their text while another role is picked.
  final _qualifications = TextEditingController(text: 'MBBS, DNB (Endocrinology)');
  final _registration = TextEditingController(text: 'WBMC 71842');

  @override
  void dispose() {
    _qualifications.dispose();
    _registration.dispose();
    super.dispose();
  }

  void _submit() {
    toast(context, 'Added to team');
    Nav.back(context);
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Add someone'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 24,
        children: [
          // Role picker
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const D9FieldLabel('Role', bottom: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in D9Roles.all)
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: r == _role,
                      child: _RoleChip(r, selected: r == _role, onTap: () => setState(() => _role = r)),
                    ),
                ],
              ),
            ],
          ),

          const D9Labeled('Full name', child: D9Input(value: 'Dr. Ananya Basu')),

          // Phone, verified
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Phone'),
              const Gap(8),
              D9Input(
                value: '+91 98300 45127',
                tab: true,
                keyboard: TextInputType.phone,
                padRight: 112,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Ico(I.check, size: 18, color: MP.green, stroke: 2.25),
                    const Gap(6),
                    Text('Verified', style: tx(14, w: w600, c: MP.green)),
                  ],
                ),
              ),
              const Gap(8),
              Text('OTP confirmed just now', style: tx(13, c: MP.ink3, h: 1.4)),
            ],
          ),

          // Doctor-only fields
          if (_role == 'Doctor')
            VGap(
              gap: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const D9Label('Doctor details', h: 1.35),
                    const Gap(4),
                    Text("Printed on this doctor's prescriptions", style: tx(13, c: MP.ink3, h: 1.4)),
                  ],
                ),
                D9Labeled('Qualifications', child: D9Input(controller: _qualifications)),
                D9Labeled('Registration number', child: D9Input(controller: _registration, tab: true)),
              ],
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

          // Locations
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const D9FieldLabel('Locations', bottom: 8),
              D9Locations(value: _locations, onToggle: (i) => setState(() => _locations[i] = !_locations[i])),
            ],
          ),

          // Permissions info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.shield, size: 20, color: MP.primary)),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Permissions come from the role', style: tx(15, w: w600, c: MP.primary, h: 1.45)),
                      const Gap(2),
                      Text(D9Roles.summary(_role), style: tx(14, h: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          MpButton('Add to team', onTap: _submit),
        ],
      ),
    );
  }
}

/// Role radio pill: 40px, padding 0 16, radius 999 and a 1px border in both
/// states (#003399 on the filled selected pill, #D5DBE5 otherwise).
class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip(this.label, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Tap(
        onTap: onTap,
        radius: 999,
        color: selected ? MP.primary : MP.white,
        border: selected ? MP.primary : MP.lineStrong,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: tx(14, w: w600, c: selected ? MP.white : MP.ink2), maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

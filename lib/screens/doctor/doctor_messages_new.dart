import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d2.dart';

/// Design: Doctor-Messages-New.dc.html — "Doctor · Messages · start a new chat".
/// Sheet over 'Doctor-Messages'. In the design the sheet is pinned 72px below
/// the top of the screen (top: 72px; bottom: 0), so it is drawn full height.
class DoctorMessagesNewSheet extends StatefulWidget {
  const DoctorMessagesNewSheet({super.key});

  @override
  State<DoctorMessagesNewSheet> createState() => _DoctorMessagesNewSheetState();
}

const _patients = [
  ('RD', 'Rahul Das', '45 M · +91 98311 20764 · in queue'),
  ('SM', 'Sujit Mondal', '37 M · +91 98362 50417 · in queue'),
  ('FI', 'Farhana Islam', '34 F · +91 90511 72830 · seen today'),
];

const _team = [
  ('FD', 'Front desk · City Care', 'Staff · Salt Lake'),
  ('MB', 'Mou Banerjee', 'Dietician'),
  ('RM', 'Dr. Rina Mitra', 'Cardiology'),
];

class _DoctorMessagesNewSheetState extends State<DoctorMessagesNewSheet> {
  String _query = '';

  bool _hit((String, String, String) p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(' ', '');
    return p.$2.toLowerCase().contains(q) ||
        p.$3.toLowerCase().contains(q) ||
        (digits.isNotEmpty && p.$3.replaceAll(' ', '').contains(digits));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final patients = _patients.where(_hit).toList();
    final team = _team.where(_hit).toList();
    return LayoutBuilder(
      builder: (context, c) {
        final maxH = c.maxHeight.isFinite ? c.maxHeight : mq.size.height;
        final inset = mq.viewInsets.bottom;
        final h = math.max(0.0, math.min(maxH - 72, maxH - inset));
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Container(
            height: h,
            decoration: const BoxDecoration(
              color: MP.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: MPShadow.float,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: VGap(
                  gap: 16,
                  children: [
                    const SheetHandle(),
                    Row(
                      children: [
                        Expanded(child: Text('New chat', style: tx(20, w: w700, h: 1.25))),
                        const Gap(8),
                        Transform.translate(
                          offset: const Offset(10, 0),
                          child: MpIconButton(
                            I.close,
                            label: 'Close',
                            iconSize: 20,
                            color: MP.ink2,
                            onTap: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                    D2SearchField(
                      hint: 'Patient name, mobile, doctor or staff',
                      active: true,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    Tap(
                      onTap: () => d2CloseThenGo(context, 'Doctor-FollowUps'),
                      radius: 16,
                      color: MP.bg,
                      border: MP.line,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const MpIconTile(I.users, size: 40, iconSize: 20, radius: 12),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Message several patients', style: tx(15, w: w700)),
                                const Gap(2),
                                Text('e.g. everyone with a follow-up due this week', style: tx(13, c: MP.ink2)),
                              ],
                            ),
                          ),
                          const Gap(12),
                          const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
                        ],
                      ),
                    ),
                    if (patients.isNotEmpty)
                      _Group(
                        title: 'Patients seen recently',
                        people: patients,
                        team: false,
                        onTap: () => d2CloseThenGo(context, 'Patient-Thread'),
                      ),
                    if (team.isNotEmpty)
                      _Group(
                        title: 'Colleagues & staff',
                        people: team,
                        team: true,
                        onTap: () => d2CloseThenGo(context, 'Patient-Thread'),
                      ),
                    if (patients.isEmpty && team.isEmpty)
                      Text('No one matches “${_query.trim()}”', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<(String, String, String)> people;
  final bool team;
  final VoidCallback onTap;
  const _Group({required this.title, required this.people, required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return VGap(
      gap: 4,
      children: [
        D2Caps(title),
        for (final p in people)
          Tap(
            onTap: onTap,
            radius: 12,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                MpAvatar(
                  p.$1,
                  size: 40,
                  fontSize: 14,
                  radius: team ? 12 : null,
                  bg: team ? MP.fill : MP.primarySoft,
                  fg: team ? MP.ink2 : MP.primary,
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.$2, style: tx(15, w: w600)),
                      const Gap(1),
                      Text(p.$3, style: tx(13, c: MP.ink2, tab: !team)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

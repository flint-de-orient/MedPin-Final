import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';
import '../../widgets/i18n.dart';

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

class _DoctorMessagesNewSheetState extends State<DoctorMessagesNewSheet> with LiveData {
  String _query = '';
  Timer? _debounce;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() => Api.I.get('/api/inbox/contacts', query: {if (_query.trim().isNotEmpty) 'q': _query.trim()});

  @override
  void dispose() {
    _debounce?.cancel();
    _busy.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    setState(() => _query = v);
    if (!isLive) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) reload(quiet: true);
    });
  }

  bool _hit((String, String, String) p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(' ', '');
    return p.$2.toLowerCase().contains(q) ||
        p.$3.toLowerCase().contains(q) ||
        (digits.isNotEmpty && p.$3.replaceAll(' ', '').contains(digits));
  }

  static String _visit(Object? status) => switch (status) {
        'waiting' => 'in queue',
        'in_consultation' => 'in consultation',
        'completed' => 'seen recently',
        'missed' => 'missed a visit',
        'booked' || 'confirmed' => 'booked',
        _ => '',
      };

  List<(String, String, String)> get _livePatients => [
        for (final p in data!.list('patients'))
          (F.initials(p.str('name')), p.str('name'), [d2PatientMeta(p), _visit(p['today'])].where((s) => s.isNotEmpty).join(' · ')),
      ];

  List<(String, String, String)> get _liveTeam => [
        for (final t in data!.list('team'))
          (
            F.initials(t.str('name')),
            t.str('name'),
            t['role'] == 'doctor' ? t.str('department', 'Doctor') : d2Role(t['role']),
          ),
      ];

  /// Opens the care thread ({patientId}; POST /api/inbox creates it the first
  /// time) or a direct thread ({userId}) — never another screen.
  Future<void> _start(BuildContext context, Map<String, dynamic> body) async {
    final res = await runAction(context, () => Api.I.post('/api/inbox', body), busy: _busy);
    if (res is! Map || !context.mounted) return;
    d2CloseThenGo(context, 'Patient-Thread', args: {
      'conversationId': '${res['id'] ?? res['_id']}',
      if (body['patientId'] != null) 'patientId': body['patientId'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final live = data != null;
    final patients = live ? _livePatients : _patients.where(_hit).toList();
    final team = live ? _liveTeam : _team.where(_hit).toList();
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
                      onChanged: _onQuery,
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
                    if (isLive && data == null) livePlaceholder() ?? const SizedBox.shrink(),
                    if (patients.isNotEmpty)
                      _Group(
                        // Live: every patient linked to the clinic, most recently active first.
                        title: live ? 'Patients' : 'Patients seen recently',
                        people: patients,
                        team: false,
                        onTap: (i) => live
                            ? _start(context, {'patientId': data!.list('patients')[i].str('id')})
                            : d2CloseThenGo(context, 'Patient-Thread'),
                      ),
                    if (team.isNotEmpty)
                      _Group(
                        title: 'Colleagues & staff',
                        people: team,
                        team: true,
                        onTap: (i) => live
                            ? _start(context, {'userId': data!.list('team')[i].str('userId')})
                            : d2CloseThenGo(context, 'Patient-Thread'),
                      ),
                    if ((!isLive || live) && patients.isEmpty && team.isEmpty)
                      Text(
                        _query.trim().isEmpty ? 'No one to message yet' : 'No one matches “${_query.trim()}”',
                        style: tx(14, c: MP.ink2),
                      ),
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
  final ValueChanged<int> onTap;
  const _Group({required this.title, required this.people, required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return VGap(
      gap: 4,
      children: [
        D2Caps(title),
        for (final (i, p) in people.indexed)
          Tap(
            onTap: () => onTap(i),
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

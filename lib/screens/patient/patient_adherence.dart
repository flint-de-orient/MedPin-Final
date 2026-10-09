import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';

typedef _Doc = ({
  String name,
  String dept,
  String pct,
  double pctSize,
  Color pctColor,
  double? bar,
  Color barColor,
  String meds,
  List<String> untracked,
});

/// Design: Patient-Adherence.dc.html — "Patient · adherence by doctor" (sheet over 'Main').
///
/// Live: GET /api/patient/adherence (doctors with their medicines, the most
/// missed time of day). "Set" turns on the reminder for that time
/// (PATCH /api/patient/me); tapping a doctor whose medicines aren't tracked
/// turns tracking on (PATCH /api/patient/medicines/:id).
class PatientAdherenceSheet extends StatefulWidget {
  const PatientAdherenceSheet({super.key});

  @override
  State<PatientAdherenceSheet> createState() => _PatientAdherenceSheetState();
}

class _PatientAdherenceSheetState extends State<PatientAdherenceSheet> with LiveData {
  static const List<_Doc> _docs = [
    (
      name: 'Dr. Arjun Sen',
      dept: 'Diabetes · City Care',
      pct: '82%',
      pctSize: 20.0,
      pctColor: MP.amber,
      bar: 0.82,
      barColor: MP.amber,
      meds: 'Metformin 78% · Glimepiride started today · Vitamin D3 100%',
      untracked: [],
    ),
    (
      name: 'Dr. Rina Mitra',
      dept: 'Heart · City Care',
      pct: '91%',
      pctSize: 20.0,
      pctColor: MP.green,
      bar: 0.91,
      barColor: MP.primary,
      meds: 'Atorvastatin 91%',
      untracked: [],
    ),
    (
      name: 'Dr. Nandita Gupta',
      dept: 'Gynaecology · Apollo Clinic',
      pct: 'Not tracked',
      pctSize: 14.0,
      pctColor: MP.ink3,
      bar: null,
      barColor: MP.primary,
      meds: 'Myo-inositol · turn on reminders to start tracking',
      untracked: [],
    ),
  ];

  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/adherence', query: {'days': 30});

  static String _medLine(Map<String, dynamic> m) {
    final name = m.str('name');
    if (m['tracked'] != true) return '$name not tracked';
    if (m['isNew'] == true || m['pct'] == null) {
      final start = F.date(m['startDate']);
      return start != null && F.sameDay(start, DateTime.now()) ? '$name started today' : '$name new';
    }
    return '$name ${m.numOr('pct').round()}%';
  }

  static _Doc _docFrom(Map<String, dynamic> d) {
    final meds = d.list('medicines');
    final dept = P1.dept(d);
    final untracked = [
      for (final m in meds)
        if (m['tracked'] != true) '${m['courseId']}',
    ];
    if (d['tracked'] != true) {
      return (
        name: d.str('name'),
        dept: dept,
        pct: 'Not tracked',
        pctSize: 14.0,
        pctColor: MP.ink3,
        bar: null,
        barColor: MP.primary,
        meds: [...meds.map((m) => m.str('name')), 'turn on reminders to start tracking'].join(' · '),
        untracked: untracked,
      );
    }
    final pct = d['pct'] as num?;
    final good = pct != null && pct >= 90;
    return (
      name: d.str('name'),
      dept: dept,
      pct: pct == null ? 'No doses yet' : '${pct.round()}%',
      pctSize: pct == null ? 14.0 : 20.0,
      pctColor: pct == null ? MP.ink3 : (good ? MP.green : MP.amber),
      bar: pct == null ? null : (pct / 100).clamp(0, 1).toDouble(),
      barColor: good ? MP.primary : MP.amber,
      meds: meds.map(_medLine).join(' · '),
      untracked: untracked,
    );
  }

  List<_Doc> get _list => data == null ? _docs : [for (final d in data!.list('doctors')) _docFrom(d)];

  String get _overall {
    if (data == null) return '86%';
    final p = data!['overallPct'] as num?;
    return p == null ? '–' : '${p.round()}%';
  }

  /// The most missed time of day and the reminder time for it.
  ({String slot, String when, String time})? get _tip {
    if (data == null) return (slot: 'night', when: 'evening', time: '8:30 PM');
    final m = data!.obj('mostMissedSlot');
    if (m.isEmpty) return null;
    final slot = m.str('slot');
    final hhmm = data!.obj('reminderTimes').str(slot, const {'morning': '07:30', 'afternoon': '13:30', 'night': '20:30'}[slot] ?? '20:30');
    return (slot: slot, when: slot == 'night' ? 'evening' : slot, time: P1.clock(hhmm));
  }

  Future<void> _setReminder() async {
    final tip = _tip!;
    if (!isLive) {
      P1.closeWithToast(context, 'Reminder set for ${tip.time}');
      return;
    }
    final hhmm = data!.obj('reminderTimes').str(tip.slot);
    final ok = await runAction(
      context,
      () => Api.I.patch('/api/patient/me', {
        'settings': {
          'medReminders': true,
          if (hhmm.isNotEmpty) 'reminderTimes': {tip.slot: hhmm},
        },
      }),
    );
    if (ok != null && mounted) P1.closeWithToast(context, 'Reminder set for ${tip.time}', true);
  }

  Future<void> _track(_Doc d) async {
    if (!isLive || d.untracked.isEmpty) return;
    final ok = await runAction(context, () async {
      for (final id in d.untracked) {
        await Api.I.patch('/api/patient/medicines/$id', {'trackingEnabled': true});
      }
      return true;
    });
    if (ok == null || !mounted) return;
    toast(context, 'Reminders on for ${d.name}');
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
    final placeholder = livePlaceholder();
    final tip = placeholder == null ? _tip : null;
    final docs = placeholder == null ? _list : const <_Doc>[];
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P1SheetHeader(
              title: Text('Taking your medicines', style: tx(20, w: w700, h: 1.25)),
              subtitle: Text.rich(
                TextSpan(
                  style: tx(14, c: MP.ink2),
                  children: [
                    const TextSpan(text: 'Last 30 days · '),
                    TextSpan(text: _overall, style: tx(14, w: w700, tab: true)),
                    const TextSpan(text: ' of doses taken'),
                  ],
                ),
              ),
            ),
            if (placeholder != null) placeholder,
            if (data != null && docs.isEmpty) ...[
              const Gap(18),
              pad(Text('No medicines are being tracked yet.', style: tx(15, c: MP.ink2))),
            ],
            for (final d in docs) ...[
              const Gap(18),
              pad(
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: d.untracked.isEmpty ? null : () => _track(d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: MP.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.name, style: tx(16, w: w700)),
                                  if (d.dept.isNotEmpty) ...[
                                    const Gap(2),
                                    Text(d.dept, style: tx(13, c: MP.ink2)),
                                  ],
                                ],
                              ),
                            ),
                            const Gap(12),
                            Text(d.pct, style: tx(d.pctSize, w: w800, tab: true, c: d.pctColor)),
                          ],
                        ),
                        if (d.bar != null) ...[
                          const Gap(10),
                          MpProgress(d.bar!, height: 6, color: d.barColor, track: MP.line),
                        ],
                        if (d.meds.isNotEmpty) ...[
                          const Gap(10),
                          Text(d.meds, style: tx(13, h: 1.45, c: MP.ink2)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (tip != null) ...[
              const Gap(18),
              pad(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: tx(14, h: 1.45),
                            children: [
                              TextSpan(text: 'Most misses are in the ${tip.when}.', style: tx(14, w: w700, h: 1.45, c: MP.amber)),
                              TextSpan(text: ' A reminder at ${tip.time} can help.'),
                            ],
                          ),
                        ),
                      ),
                      const Gap(12),
                      P1SoftButton('Set', padding: 14, background: MP.white, onTap: _setReminder),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

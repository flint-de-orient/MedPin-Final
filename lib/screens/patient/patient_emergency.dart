import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';
import '../../widgets/i18n.dart';

typedef _Doctor = ({String initials, String name, String dept, String status, Color statusColor, Color dot});

/// Design: Patient-Emergency.dc.html — "Patient · emergency: choose doctor" (sheet over 'Main').
///
/// Live: the doctors come from GET /api/patient/urgent/doctors. Choosing one
/// sends the urgent message (POST /api/patient/urgent), which alerts the
/// doctor, and opens Patient-Chat on that thread. "Call 108" dials 108.
class PatientEmergencySheet extends StatefulWidget {
  const PatientEmergencySheet({super.key});

  @override
  State<PatientEmergencySheet> createState() => _PatientEmergencySheetState();
}

class _PatientEmergencySheetState extends State<PatientEmergencySheet> with LiveData {
  static const List<_Doctor> _doctors = [
    (initials: 'AS', name: 'Dr. Arjun Sen', dept: 'Diabetes · City Care', status: 'Available now', statusColor: MP.green, dot: MP.green),
    (
      initials: 'RM',
      name: 'Dr. Rina Mitra',
      dept: 'Heart · City Care',
      status: 'In clinic · usually replies in 15 min',
      statusColor: MP.ink2,
      dot: MP.amber,
    ),
    (
      initials: 'NG',
      name: 'Dr. Nandita Gupta',
      dept: 'Gynaecology · Apollo Clinic',
      status: 'Away · her clinic team will see it',
      statusColor: MP.ink2,
      dot: MP.lineStrong,
    ),
  ];

  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/urgent/doctors');

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  static _Doctor _from(Map<String, dynamic> d) {
    final p = P1.presence(d);
    return (initials: F.initials(d.str('name')), name: d.str('name'), dept: P1.dept(d), status: p.status, statusColor: p.color, dot: p.dot);
  }

  List<Map<String, dynamic>> get _raw => data?.list('items') ?? const [];

  /// The clinics of these doctors that have a phone number (one button each, at most 2).
  List<({String name, String phone})> get _clinics {
    final seen = <String>{};
    return [
      for (final d in _raw)
        if (d.str('clinicPhone').isNotEmpty && seen.add(d.str('clinicPhone'))) (name: d.str('clinic', 'the clinic'), phone: d.str('clinicPhone')),
    ].take(2).toList();
  }
  List<_Doctor> get _list => data == null ? (isLive ? const [] : _doctors) : [for (final d in _raw) _from(d)];

  Future<void> _choose(int i) async {
    if (!isLive) {
      P1.closeThen(context, 'Patient-Chat');
      return;
    }
    final d = _raw[i];
    final res = await runAction(
      context,
      () => Api.I.post('/api/patient/urgent', {'doctorId': d['doctorId'], 'text': 'I need help urgently.'}),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    P1.closeThen(context, 'Patient-Chat', args: {
      'conversationId': res['conversationId'],
      'doctorId': d['doctorId'],
      'doctorName': d['name'],
      'presence': d['presence'],
      'avgReplyMinutes': d['avgReplyMinutes'],
      'gender': d['gender'],
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
    final docs = _list;
    final placeholder = livePlaceholder();
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P1SheetHeader(
              closeWidth: 35.9,
              title: Text('Which doctor do you need?', style: tx(20, w: w700, h: 1.25)),
              subtitle: Text(
                'Your message is marked urgent and the doctor is alerted right away.',
                style: tx(14, h: 1.45, c: MP.ink2),
              ),
            ),
            if (placeholder != null) placeholder,
            if (data != null && docs.isEmpty) ...[
              const Gap(18),
              pad(Text("You don't have a doctor on MedPin yet. In an emergency, call 108.", style: tx(15, h: 1.45, c: MP.ink2))),
            ],
            if (docs.isNotEmpty) ...[
              const Gap(18),
              pad(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var i = 0; i < docs.length; i++) _doctorRow(context, docs, i)],
                ),
              ),
            ],
            const Gap(18),
            pad(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: MP.redSoft, borderRadius: BorderRadius.circular(12)),
                child: Text.rich(
                  TextSpan(
                    style: tx(14, h: 1.45),
                    children: [
                      TextSpan(text: 'Chest pain, trouble breathing or fainting?', style: tx(14, w: w700, h: 1.45, c: MP.red)),
                      const TextSpan(text: " Don't wait for a reply. "),
                      P1.link(
                        'Call 108',
                        style: tx(14, w: w700, h: 1.45, c: MP.red),
                        onTap: () => isLive ? P1.dial(context, '108') : P1.closeWithToast(context, 'Calling 108…'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Or ring the clinic now (its phone, once per clinic).
            for (final c in _clinics) ...[
              const Gap(10),
              pad(MpButton('${tr(context, 'Call')} ${c.name}', kind: MpBtn.secondary, height: 48, icon: I.phone, onTap: () => P1.dial(context, c.phone))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doctorRow(BuildContext context, List<_Doctor> docs, int i) {
    final d = docs[i];
    final photo = data == null || i >= _raw.length ? '' : _raw[i].str('photoUrl');
    return Tap(
      onTap: () => _choose(i),
      radius: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                children: [
                  MpAvatar(d.initials, size: 48, fontSize: 15, photo: photo.isEmpty ? null : photo),
                  // 12px status dot with a 2px white ring, bottom-right.
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: d.dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: MP.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name, style: tx(16, w: w700)),
                  if (d.dept.isNotEmpty) ...[
                    const Gap(2),
                    Text(d.dept, style: tx(13, c: MP.ink2)),
                  ],
                  const Gap(2),
                  Text(d.status, style: tx(13, w: w600, c: d.statusColor)),
                ],
              ),
            ),
            const Gap(12),
            const Ico(I.chevronRight, size: 18, color: MP.ink3),
          ],
        ),
      ),
    );
  }
}

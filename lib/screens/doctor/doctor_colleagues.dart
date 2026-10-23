import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import '../../widgets/i18n.dart';

/// Doctor · Colleagues you work with (from My profile → Team). Two lists:
/// the other doctors and the dietician in this clinic (specialty, branches),
/// and the doctors this doctor refers patients to or gets referrals from —
/// any clinic, on MedPin or not — with how many each way and when last.
/// Live data: GET /api/colleagues. Tap a referral colleague: Report-Referrals.
class DoctorColleaguesScreen extends StatefulWidget {
  const DoctorColleaguesScreen({super.key});

  @override
  State<DoctorColleaguesScreen> createState() => _DoctorColleaguesScreenState();
}

class _DoctorColleaguesScreenState extends State<DoctorColleaguesScreen> with LiveData {
  static final _sample = <String, dynamic>{
    'inClinic': [
      {'name': 'Dr. Meera Iyer', 'specialty': 'Cardiology', 'locations': ['Salt Lake'], 'sent': 3, 'received': 1},
      {'name': 'Ritu Das', 'role': 'dietician', 'specialty': 'Nutrition', 'locations': ['Salt Lake', 'New Town'], 'sent': 0, 'received': 0},
    ],
    'network': [
      {'name': 'Dr. Sourav Lahiri', 'specialty': 'Nephrology', 'onMedPin': true, 'sent': 4, 'received': 0, 'awaiting': 1},
    ],
  };

  @override
  Future<Object?> fetch() => Api.I.get('/api/colleagues');

  Map<String, dynamic> get _d => data ?? _sample;

  List<Map<String, dynamic>> _list(String k) => [for (final x in (_d[k] as List? ?? const [])) (x as Map).cast<String, dynamic>()];

  /// "3 sent · 1 received · last 12 Oct" (or nothing yet).
  String _referrals(Map<String, dynamic> c) {
    final sent = c.numOr('sent').toInt();
    final received = c.numOr('received').toInt();
    if (sent + received == 0) return '';
    final at = F.date(c['lastReferralAt']);
    return [
      if (sent > 0) '${tr(context, 'Referred')} $sent',
      if (received > 0) '${tr(context, 'Received')} $received',
      if (c.numOr('awaiting') > 0) '${c.numOr('awaiting').toInt()} ${tr(context, 'awaiting')}',
      if (at != null) '${tr(context, 'last')} ${F.dayMonth(at)}',
    ].join(' · ');
  }

  Widget _row(Map<String, dynamic> c, {required bool clinic}) {
    final name = c.str('name', 'Doctor');
    final where = clinic ? [for (final l in (c['locations'] as List? ?? const [])) '$l'].join(', ') : (c['onMedPin'] == true ? 'On MedPin' : 'Not on MedPin');
    final info = [c.str('specialty'), where].where((x) => x.isNotEmpty).join(' · ');
    final refs = _referrals(c);
    return Tap(
      onTap: clinic && refs.isEmpty ? null : () => Nav.go(context, 'Report-Referrals'),
      radius: 16,
      color: MP.white,
      border: MP.line,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          MpAvatar(F.initials(name), size: 44, photo: c['photoUrl'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserText(name, style: tx(15, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (info.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(info, style: tx(13, c: MP.ink2), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (refs.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(refs, style: tx(13, c: MP.ink3)),
                ],
              ],
            ),
          ),
          if (!clinic || refs.isNotEmpty) ...[
            const SizedBox(width: 8),
            const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
          ],
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(s.toUpperCase(), style: tx(13, w: w700, c: MP.ink3, em: 0.06)),
      );

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final inClinic = _list('inClinic');
    final network = _list('network');
    final owner = Session.I.isOwner;
    return MpPage(
      header: D4Header('Colleagues', subtitle: data == null ? '3 doctors you work with' : d4Plural(inClinic.length + network.length, 'colleague')),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 12,
            children: [
              _label('In this clinic'),
              if (inClinic.isEmpty)
                const D4Note('No other doctor works in this clinic yet.')
              else
                for (final c in inClinic) _row(c, clinic: true),
              if (owner) MpButton('Add a doctor to this clinic', kind: MpBtn.secondary, height: 48, icon: I.plus, onTap: () => Nav.go(context, 'People')),
              const SizedBox(height: 4),
              _label('Doctors you refer to'),
              if (network.isEmpty)
                const D4Note("Doctors you refer patients to, or who refer patients to you, show here. Add a referral from a patient's profile.")
              else
                for (final c in network) _row(c, clinic: false),
            ],
          ),
    );
  }
}

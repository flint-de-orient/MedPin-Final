import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import 'patient_finddoctor.dart' show openDoctorBooking;
import '../../widgets/i18n.dart';
import 'common_p3.dart';

/// Design: Patient-Doctors.dc.html — "Patient · Doctor tab: my doctors".
///
/// Live data: GET /api/patient/my-doctors (the doctors on the patient's care
/// team, with their next visit, medicines and unread chat).
class PatientDoctorsScreen extends StatefulWidget {
  const PatientDoctorsScreen({super.key});

  @override
  State<PatientDoctorsScreen> createState() => _PatientDoctorsScreenState();
}

class _PatientDoctorsScreenState extends State<PatientDoctorsScreen> with LiveData {
  static const _doctors = [
    _Doc(
      'AS',
      'Dr. Arjun Sen',
      'Diabetes · City Care, Salt Lake',
      MP.green,
      'Visit today, 5:00 PM · Token 04',
      true,
      '3 medicines · 82% taken',
      2,
      'Visit details',
      true,
    ),
    _Doc(
      'RM',
      'Dr. Rina Mitra',
      'Heart · City Care, Salt Lake',
      MP.amber,
      'No visit booked · last seen 02 Feb',
      false,
      '1 medicine · 91% taken',
      0,
      'Book a visit',
      false,
    ),
    _Doc(
      'NG',
      'Dr. Nandita Gupta',
      'Gynaecology · Apollo Clinic',
      MP.lineStrong,
      'Follow-up due in November',
      false,
      '1 medicine · not tracked',
      0,
      'Book a visit',
      false,
    ),
  ];

  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/my-doctors');

  /// Doctors only (the dietician and others are listed on Patient-Me).
  List<Map<String, dynamic>> get _rows => [
        for (final d in data?.list('items') ?? const <Map<String, dynamic>>[])
          if (d.str('role', 'doctor') == 'doctor') d,
      ];

  /// A clinic's doctors share one care thread: count its unread once.
  int get _unread {
    if (data == null) return isLive ? 0 : 2;
    final seen = <String>{};
    var n = 0;
    for (final d in data!.list('items')) {
      final c = d.str('conversationId');
      if (c.isEmpty || !seen.add(c)) continue;
      n += d.numOr('unread').toInt();
    }
    return n;
  }

  List<_Doc> get _docs {
    if (data == null) return isLive ? const [] : _doctors;
    final threads = <String>{};
    return [for (final d in _rows) _docFrom(d, threads)];
  }

  static Color _presence(String p) => switch (p) {
        'available' => MP.green,
        'in_clinic' => MP.amber,
        _ => MP.lineStrong,
      };

  _Doc _docFrom(Map<String, dynamic> d, Set<String> threads) {
    final name = d.str('name', 'Doctor');
    final what = d.str('specialty', d.str('headline'));
    // "City Care, Salt Lake" as in the design: the clinic without "Clinic" / "Hospital".
    final clinic = d.str('clinic').replaceFirst(RegExp(r'\s+(Clinic|Clinics|Hospital|Medical Centre|Medical Center)$', caseSensitive: false), '');
    final where = [clinic, d.str('area')].where((x) => x.isNotEmpty).join(', ');
    final next = d.obj('nextVisit');
    final at = F.date(next['startAt']);
    final due = F.date(d['followUpDue']);
    final seen = F.date(d['lastSeenAt']);
    String visit;
    if (at != null) {
      final when = F.when(at);
      final lower = when.startsWith('Today') || when.startsWith('Tomorrow') ? when[0].toLowerCase() + when.substring(1) : when;
      visit = 'Visit $lower${next.str('token').isEmpty ? '' : ' · Token ${next.str('token')}'}';
    } else if (due != null) {
      visit = 'Follow-up due by ${F.dayMonth(due)}';
    } else if (seen != null) {
      visit = 'No visit booked · last seen ${F.dayMonth(seen)}';
    } else {
      visit = 'No visit booked';
    }
    final meds = d.numOr('medicines').toInt();
    final pct = d['adherencePct'];
    final medLine = meds == 0
        ? 'No medicines from this doctor'
        : '$meds medicine${meds == 1 ? '' : 's'} · ${p3FewDoses(d['adherenceCount']) != null ? '${p3FewDoses(d['adherenceCount'])} doses taken' : pct is num ? '${pct.round()}% taken' : 'not tracked'}';
    final convo = d.str('conversationId');
    return _Doc(
      F.initials(name),
      name,
      [if (what.isNotEmpty) what, if (where.isNotEmpty) where].join(' · '),
      _presence(d.str('presence')),
      visit,
      at != null,
      medLine,
      convo.isNotEmpty && threads.add(convo) ? d.numOr('unread').toInt() : 0,
      at != null ? 'Visit details' : 'Book a visit',
      at != null && F.sameDay(at, DateTime.now()),
      doctorId: d.str('doctorId'),
      conversationId: convo.isEmpty ? null : convo,
      photo: d.str('photoUrl').isEmpty ? null : d.str('photoUrl'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final docs = _docs;
    final unread = _unread;
    return MpPage(
      // Patient nav, Doctor tab active with its unread badge.
      nav: FloatingNav(
        current: 1,
        items: [
          for (final it in PatientNav.items)
            it.stem == 'Patient-Doctors' && unread > 0 ? NavItem(it.label, it.icon, it.stem, badge: unread) : it,
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My doctors', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                const Gap(4),
                Text(
                  placeholder != null
                      ? 'Doctors caring for you'
                      : '${docs.length} doctor${docs.length == 1 ? '' : 's'} caring for you',
                  style: tx(14, c: MP.ink2),
                ),
              ],
            ),
          ),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 12,
            children: [
              // Moved up from the end of the list, as a banner.
              _FindDoctorBanner(showMatch: !isLive),
              if (placeholder != null) placeholder,
              for (final d in docs) _DoctorCard(d, onChanged: () => reload(quiet: true)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Doc {
  final String initials;
  final String name;
  final String dept;
  final Color dot;
  final String visit;
  final bool visitBold;
  final String meds;
  final int unread;
  final String second;
  final bool raised;

  /// Live only: the doctor's user id and the clinic's care thread.
  final String? doctorId;
  final String? conversationId;
  const _Doc(
    this.initials,
    this.name,
    this.dept,
    this.dot,
    this.visit,
    this.visitBold,
    this.meds,
    this.unread,
    this.second,
    this.raised, {
    this.doctorId,
    this.conversationId,
    this.photo,
  });

  /// The doctor's profile photo, when they set one.
  final String? photo;
}

class _DoctorCard extends StatelessWidget {
  final _Doc d;

  /// After a visit was booked or the chat read: refresh the list.
  final VoidCallback onChanged;
  const _DoctorCard(this.d, {required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final id = d.doctorId;
    Future<void> detail() async {
      await Nav.go(context, 'Patient-DoctorDetail', args: id == null ? null : {'doctorId': id});
      if (id != null) onChanged();
    }

    Future<void> chat() async {
      await Nav.go(
        context,
        'Patient-DoctorChat',
        args: id == null ? null : {'doctorId': id, 'conversationId': d.conversationId},
      );
      if (id != null) onChanged();
    }

    Future<void> book() async {
      if (id == null) {
        p2Missing(context, 'Booking a visit');
        return;
      }
      if (await openDoctorBooking(context, id)) onChanged();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MPDeco.card(shadow: d.raised ? MPShadow.float : MPShadow.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Avatar, name, department → doctor page
          Semantics(
            button: true,
            label: d.name,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: detail,
              child: Row(
                children: [
                  // 12px dot + 2px ring (content-box) at right 1 / bottom 1.
                  P2AvatarDot(d.initials, size: 56, fontSize: 18, dot: d.dot, dotSize: 16, dotBorder: 2, inset: 1, photo: d.photo),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: tx(18, w: w700)),
                        const Gap(2),
                        Text(d.dept, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(14),
                  const Ico(I.chevronRight, size: 20, color: MP.ink3),
                ],
              ),
            ),
          ),
          const Gap(16),

          // Visit + medicines
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Ico(I.calendar, size: 16, color: MP.ink2),
                    const Gap(10),
                    // One line, as in the design (shrinks a little when long).
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(d.visit, maxLines: 1, softWrap: false, style: tx(14, w: d.visitBold ? w700 : w400)),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                Row(
                  children: [
                    const Ico(I.pill, size: 16, color: MP.ink2),
                    const Gap(10),
                    Expanded(child: Text(d.meds, style: tx(14))),
                  ],
                ),
              ],
            ),
          ),
          const Gap(16),

          // Chat · Visit details / Book a visit
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: P2Box(
                  onTap: chat,
                  label: d.unread > 0 ? 'Chat, ${d.unread} unread' : 'Chat',
                  height: 48,
                  radius: 12,
                  color: MP.primary,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.message, size: 18, color: MP.white),
                      const Gap(8),
                      Text('Chat', style: tx(15, w: w700, c: MP.white)),
                      if (d.unread > 0) ...[
                        const Gap(8),
                        P2Pill(
                          '${d.unread}',
                          bg: MP.white,
                          fg: MP.primary,
                          height: 20,
                          padX: 6,
                          weight: w800,
                          minWidth: 20,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                // <a> with height 48 + 1px border (content-box) → 50px.
                child: P2Box(
                  onTap: d.second == 'Visit details' ? detail : book,
                  height: 50,
                  radius: 12,
                  color: MP.white,
                  border: MP.lineStrong,
                  alignment: Alignment.center,
                  child: Text(d.second, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Find a new doctor" banner at the top of the Doctor tab. Opens the MedPin
/// doctor directory with MedPin AI search (Patient-FindDoctor).
class _FindDoctorBanner extends StatelessWidget {
  /// The sample "Dr. Ghosh · Available today" match (design preview only).
  final bool showMatch;
  const _FindDoctorBanner({this.showMatch = true});

  static const _tagBg = Color(0x29FFFFFF); // rgba(255,255,255,.16)
  static const _tagLine = Color(0x47FFFFFF); // rgba(255,255,255,.28)
  static const _sub = Color(0xDBFFFFFF); // rgba(255,255,255,.86)

  @override
  Widget build(BuildContext context) {
    void open() => Nav.go(context, 'Patient-FindDoctor');
    return Semantics(
      button: true,
      label: 'Find a new doctor. Search every doctor on MedPin with MedPin AI.',
      child: GestureDetector(
        onTap: open,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            // Narrow phones give the copy more room.
            final narrow = w < 340;
            final photoW = narrow ? 136.0 : (w * 0.5).clamp(150.0, 200.0);
            final textW = (w - photoW - 4).clamp(150.0, 200.0);
            // The floating match only shows where it clears the CTA pill.
            final chipW = w - 12 - (20 + 172 + 10);
            final showChip = chipW >= 164; // never show it truncated
            return Container(
              height: 224,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: MP.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: MPShadow.floatStrong,
              ),
              child: Stack(
                children: [
                  // Consultation photo on the right, melting into the blue.
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: photoW,
                    child: Image.asset(
                      'assets/images/hero_patient.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.55, -0.35),
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: w - photoW - 1,
                    width: 110,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [MP.primary, Color(0x00003399)])),
                    ),
                  ),
                  // A doctor match floating over the photo.
                  if (showChip && showMatch)
                    Positioned(right: 12, bottom: 20, child: _MatchChip(maxWidth: chipW.clamp(164.0, 180.0))),
                  // Copy and the CTA.
                  Positioned(
                    left: 20,
                    top: 20,
                    bottom: 20,
                    width: textW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _tagBg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: _tagLine),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Ico(I.sparkles, size: 14, color: MP.white),
                                    const Gap(6),
                                    Text('MEDPIN AI', style: tx(12, w: w700, c: MP.white, em: 0.06)),
                                  ],
                                ),
                              ),
                              const Gap(10),
                              Text(
                                'Find a new doctor',
                                maxLines: 2,
                                style: tx(24, w: w800, h: 1.15, em: -0.02, c: MP.white),
                              ),
                              const Gap(6),
                              Flexible(
                                child: Text(
                                  "Tell us what's wrong. We'll match the right specialist.",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: tx(14, h: 1.4, c: _sub),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tap(
                          onTap: open,
                          radius: 999,
                          color: MP.white,
                          child: SizedBox(
                            height: 44,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: narrow ? 14 : 18),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(child: Text('Search doctors', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(15, w: w700, c: MP.primary))),
                                  const Gap(8),
                                  const Ico(I.arrowRight, size: 18, color: MP.primary, stroke: 2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// White "match" card: avatar, doctor, green "Available today".
class _MatchChip extends StatelessWidget {
  final double maxWidth;
  const _MatchChip({required this.maxWidth});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(14), boxShadow: MPShadow.float),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MpAvatar('AG', size: 26, fontSize: 10),
          const Gap(8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dr. Ghosh · Diabetes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx(12, w: w700, h: 1.3),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle),
                    ),
                    const Gap(4),
                    Flexible(
                      child: Text(
                        'Available today',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(11, w: w600, c: MP.green, h: 1.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

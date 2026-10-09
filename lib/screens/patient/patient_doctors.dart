import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Patient-Doctors.dc.html — "Patient · Doctor tab: my doctors".
class PatientDoctorsScreen extends StatelessWidget {
  const PatientDoctorsScreen({super.key});

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
  Widget build(BuildContext context) {
    return MpPage(
      // Patient nav, Doctor tab active with its "2 unread" badge.
      nav: FloatingNav(
        current: 1,
        items: [
          for (final it in PatientNav.items)
            it.stem == 'Patient-Doctors' ? NavItem(it.label, it.icon, it.stem, badge: 2) : it,
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
                Text('3 doctors caring for you', style: tx(14, c: MP.ink2)),
              ],
            ),
          ),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 12,
            children: [
              // Moved up from the end of the list, as a banner.
              const _FindDoctorBanner(),
              for (final d in _doctors) _DoctorCard(d),
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
    this.raised,
  );
}

class _DoctorCard extends StatelessWidget {
  final _Doc d;
  const _DoctorCard(this.d);

  @override
  Widget build(BuildContext context) {
    void detail() => Nav.go(context, 'Patient-DoctorDetail');
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
                  P2AvatarDot(d.initials, size: 56, fontSize: 18, dot: d.dot, dotSize: 16, dotBorder: 2, inset: 1),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: tx(18, w: w700)),
                        const Gap(2),
                        Text(d.dept, style: tx(14, c: MP.ink2)),
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
                    Expanded(child: Text(d.visit, style: tx(14, w: d.visitBold ? w700 : w400))),
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
                  onTap: () => Nav.go(context, 'Patient-DoctorChat'),
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
                  onTap: d.second == 'Visit details' ? detail : () => p2Missing(context, 'Booking a visit'),
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
  const _FindDoctorBanner();

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
                  if (showChip)
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
                                  Text('Search doctors', style: tx(15, w: w700, c: MP.primary)),
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

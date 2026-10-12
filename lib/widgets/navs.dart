import 'package:flutter/material.dart' hide Text;

import '../core/icons.dart';
import '../core/nav.dart';
import '../core/tokens.dart';
import 'i18n.dart';
import '../data/config.dart';
import '../data/nav_counts.dart';

class NavItem {
  final String label;
  final String icon;
  final String stem;
  final int? badge;
  const NavItem(this.label, this.icon, this.stem, {this.badge});
}

/// Floating pill bottom nav: 64px, radius 28, white, 1px #E5E9F0 border,
/// shadow 0 8 24 rgba(0,51,153,.10). Active tab: #EBF1FB pill, #003399.
class FloatingNav extends StatelessWidget {
  final List<NavItem> items;
  final int current;
  final double fontSize;
  final double gap;

  /// Unread badge offset from the tab's top (3px on 5-tab navs, 4px on others).
  final double badgeTop;
  const FloatingNav({super.key, required this.items, required this.current, this.fontSize = 11, this.gap = 2, this.badgeTop = 3});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: MP.line),
        boxShadow: MPShadow.float,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: _tab(context, items[i], i == current)),
          ],
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, NavItem it, bool active) {
    final fg = active ? MP.primary : MP.ink2;
    return Semantics(
      selected: active,
      button: true,
      label: it.label,
      child: Material(
        color: active ? MP.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Nav.tab(context, it.stem),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Ico(it.icon, size: 22, color: fg),
                    const SizedBox(height: 2),
                    Text(it.label, style: tx(fontSize, w: active ? w700 : w600, c: fg, h: 1.2), maxLines: 1),
                  ],
                ),
              ),
              if (it.badge != null)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: badgeTop,
                          left: c.maxWidth / 2 + 6,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: MP.primary,
                              borderRadius: BorderRadius.circular(999),
                              // The ring matches the tab behind it (#EBF1FB when active).
                              border: Border.all(color: active ? MP.primarySoft : MP.white, width: 2),
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: Text(it.badge! > 99 ? '99+' : '${it.badge}', style: tx(11, w: w700, c: MP.white, h: 1)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Doctor app (redesign): Home · Patients · Messages · Reports · History.
class DoctorNav extends StatelessWidget {
  final int current;
  const DoctorNav({super.key, required this.current});
  /// The design's tabs (sample badge); live badges come from [NavCounts].
  static const items = [
    NavItem('Home', I.home, 'Doctor-Dashboard'),
    NavItem('Patients', I.users, 'Doctor-Patients'),
    NavItem('Messages', I.message, 'Doctor-Messages', badge: 4),
    NavItem('Reports', I.file, 'Doctor-Reports'),
    NavItem('History', I.history, 'Doctor-History'),
  ];
  @override
  Widget build(BuildContext context) {
    if (AppMode.preview) return FloatingNav(items: items, current: current);
    NavCounts.refresh();
    return ValueListenableBuilder(
      valueListenable: NavCounts.counts,
      builder: (_, c, _) => FloatingNav(current: current, items: [
        items[0],
        items[1],
        NavItem('Messages', I.message, 'Doctor-Messages', badge: c.messages > 0 ? c.messages : null),
        items[3],
        items[4],
      ]),
    );
  }
}

/// Clinician tabs (first version): Home · Care · Nutrition · Profile.
class ClinicianNav extends StatelessWidget {
  final int current;
  const ClinicianNav({super.key, required this.current});
  static const items = [
    NavItem('Home', I.home, 'Doctor-Home'),
    NavItem('Care', I.heart, 'Care', badge: 6),
    NavItem('Nutrition', I.leaf, 'Nutrition'),
    NavItem('Profile', I.user, 'Profile'),
  ];
  @override
  Widget build(BuildContext context) {
    if (AppMode.preview) return FloatingNav(items: items, current: current, fontSize: 12, gap: 4, badgeTop: 4);
    NavCounts.refresh();
    return ValueListenableBuilder(
      valueListenable: NavCounts.counts,
      builder: (_, c, _) => FloatingNav(current: current, fontSize: 12, gap: 4, badgeTop: 4, items: [
        items[0],
        NavItem('Care', I.heart, 'Care', badge: c.care > 0 ? c.care : null),
        items[2],
        items[3],
      ]),
    );
  }
}

/// Front desk: Today · Patients · Profile.
class StaffNav extends StatelessWidget {
  final int current;
  const StaffNav({super.key, required this.current});
  static const items = [
    NavItem('Today', I.calendar, 'Staff-Today'),
    NavItem('Patients', I.users, 'Staff-Patients'),
    NavItem('Profile', I.user, 'Staff-Profile'),
  ];
  @override
  Widget build(BuildContext context) => FloatingNav(items: items, current: current, fontSize: 12, gap: 4, badgeTop: 4);
}

/// Patient app: Home · Doctor · Medicines · Records · Profile.
class PatientNav extends StatelessWidget {
  final int current;
  const PatientNav({super.key, required this.current});
  static const items = [
    NavItem('Home', I.home, 'Main'),
    NavItem('Doctor', I.message, 'Patient-Doctors'),
    NavItem('Medicines', I.pill, 'Patient-Medicines'),
    NavItem('Records', I.fileText, 'Patient-Records'),
    NavItem('Profile', I.user, 'Patient-Me'),
  ];
  @override
  Widget build(BuildContext context) => FloatingNav(items: items, current: current);
}

import 'package:flutter/material.dart' hide Text;

import '../data/config.dart';
import '../widgets/mp.dart';
import 'splash.dart';
import '../widgets/i18n.dart';

/// Entry point: pick the doctor app, the front desk or the patient app,
/// or browse every design screen.
class LauncherScreen extends StatelessWidget {
  const LauncherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Everything opened from here shows the design's sample data.
    AppMode.preview = true;
    final count = Nav.registry.length;
    return MpPage(
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        gap: 12,
        children: [
          // The splash's logo lands here (Hero flight).
          const Align(alignment: Alignment.centerLeft, child: Hero(tag: kLogoHeroTag, child: MpLogo())),
          const Gap(28),
          Text('Choose an app', style: tx(28, w: w800, h: 1.15, em: -0.02)),
          Text('Every screen of the MedPin design, built in Flutter.', style: tx(15, c: MP.ink2, h: 1.5)),
          const Gap(12),
          _AppCard(
            icon: I.stethoscope,
            title: 'Doctor app',
            body: 'Sign in, dashboard, patients, consultation, reports, history and profile.',
            onTap: () => Nav.go(context, 'Auth-Login'),
          ),
          _AppCard(
            icon: I.calendar,
            title: 'Front desk',
            body: 'Today’s queue, patients and the staff profile.',
            onTap: () => Nav.go(context, 'Staff-Today'),
          ),
          _AppCard(
            icon: I.heart,
            title: 'Patient app',
            body: 'Home, doctors, medicines, health records and AI help.',
            onTap: () => Nav.go(context, 'Main'),
          ),
          const Gap(4),
          MpButton(
            'Browse all $count screens',
            kind: MpBtn.secondary,
            icon: I.search,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GalleryScreen())),
          ),
        ],
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final String icon, title, body;
  final VoidCallback onTap;
  const _AppCard({required this.icon, required this.title, required this.body, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      radius: 20,
      child: Row(
        children: [
          MpIconTile(icon, size: 52, radius: 16),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(17, w: w700)),
                const Gap(4),
                Text(body, style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
          ),
          const Gap(8),
          const Ico(I.chevronRight, size: 20, color: MP.ink3),
        ],
      ),
    );
  }
}

/// Every design screen grouped like the canvas rows.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  int panel = 0;
  static const panels = ['doctor', 'staff', 'patient'];

  @override
  Widget build(BuildContext context) {
    final specs = Nav.registry.values.where((s) => s.panel == panels[panel]).toList();
    final groups = <String, List<ScreenSpec>>{};
    for (final s in specs) {
      groups.putIfAbsent(s.group, () => []).add(s);
    }
    return MpPage(
      header: const MpHeader('All screens'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          MpSegmented(
            options: const ['Doctor', 'Front desk', 'Patient'],
            index: panel,
            onChanged: (i) => setState(() => panel = i),
          ),
          for (final g in groups.entries) ...[
            const Gap(4),
            SectionLabel(g.key, trailing: Text('${g.value.length}', style: tx(12, w: w600, c: MP.ink3))),
            MpCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < g.value.length; i++) ...[
                    if (i > 0) const MpDivider(indent: 20),
                    Tap(
                      onTap: () => Nav.openWithParent(context, g.value[i].stem),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(g.value[i].title, style: tx(16, w: w600)),
                                  const Gap(2),
                                  Text(
                                    g.value[i].sheet ? '${g.value[i].stem} · sheet' : g.value[i].stem,
                                    style: tx(13, c: MP.ink3),
                                  ),
                                ],
                              ),
                            ),
                            const Ico(I.chevronRight, size: 18, color: MP.ink3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

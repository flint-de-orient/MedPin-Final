import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Hero-Carousel.dc.html — "Patient · home carousel slides".
class HeroCarouselScreen extends StatelessWidget {
  const HeroCarouselScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MpPage(
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        gap: 28,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Home carousel · 4 slides', style: tx(20, w: w700)),
              const Gap(4),
              Text(
                'Swipe or auto-advance every 6 s. Only slides with something current are shown, most urgent first.',
                style: tx(14, h: 1.45, c: MP.ink2),
              ),
            ],
          ),
          for (final s in P1.slides)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.spec.toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                const Gap(8),
                P1HeroSlide(slide: s, onTap: () => P1.openSlide(context, s)),
              ],
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Hero-Carousel.dc.html — "Patient · home carousel slides".
///
/// Live: the patient's current slides from GET /api/patient/home.
class HeroCarouselScreen extends StatefulWidget {
  const HeroCarouselScreen({super.key});

  @override
  State<HeroCarouselScreen> createState() => _HeroCarouselScreenState();
}

class _HeroCarouselScreenState extends State<HeroCarouselScreen> with LiveData {
  @override
  Future<Object?> fetch() => Api.I.get('/api/patient/home');

  static String _spec(int i, P1Slide s) {
    final what = switch (s.stem) {
      'Patient-DoctorDetail' => 'Opens appointment details',
      'Patient-Records' => 'Opens the report in Health records',
      'Patient-Medicines' => 'Opens Medicines, refill',
      _ => 'Opens health score details',
    };
    return '${i + 1} · $what';
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final slides = !isLive ? P1.slides : (data == null ? const <P1Slide>[] : P1.slidesFrom(data!));
    return MpPage(
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        gap: 28,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Home carousel · ${slides.length} ${slides.length == 1 ? 'slide' : 'slides'}', style: tx(20, w: w700)),
              const Gap(4),
              Text(
                'Swipe or auto-advance every 6 s. Only slides with something current are shown, most urgent first.',
                style: tx(14, h: 1.45, c: MP.ink2),
              ),
            ],
          ),
          if (placeholder != null) placeholder,
          for (var i = 0; i < slides.length; i++)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text((data == null ? slides[i].spec : _spec(i, slides[i])).toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                const Gap(8),
                P1HeroSlide(slide: slides[i], onTap: () => P1.openSlide(context, slides[i])),
              ],
            ),
        ],
      ),
    );
  }
}

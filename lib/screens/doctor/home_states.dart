import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d8.dart';

/// Design: Home-States.dc.html — "Home · states" (Clinician · tabs): how the
/// dashboard cards look while loading, stale, empty, failed or all clear.
///
/// Live: the samples use the real GET /api/dashboard request — the greeting
/// and "Updated / Last checked" times come from it, and Retry / Try again
/// fetch it again.
class HomeStatesScreen extends StatefulWidget {
  const HomeStatesScreen({super.key});

  @override
  State<HomeStatesScreen> createState() => _HomeStatesScreenState();
}

class _HomeStatesScreenState extends State<HomeStatesScreen> with LiveData {
  @override
  Future<Object?> fetch() => Api.I.get('/api/dashboard');

  String get _greeting =>
      data == null ? 'Good morning, Dr. Sen' : '${F.greeting()}, ${F.doctorShort(data!.str('greetingName'))}';

  /// "3 min ago" since the last successful load.
  String get _since => loadedAt == null ? '' : d8Updated(loadedAt!).substring('Updated '.length);

  void _retry() {
    toast(context, 'Retrying…');
    if (isLive) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        gap: 32,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Home states', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              const Gap(4),
              Text(
                'How dashboard cards behave while loading, when data is late or missing, and when a card fails.',
                style: tx(14, c: MP.ink2, h: 1.45),
              ),
            ],
          ),
          const _Section(
            label: 'Loading',
            caption: "Static blocks in the card's real shape. No shimmer or pulse.",
            child: ExcludeSemantics(child: _LoadingSkeleton()),
          ),
          _Section(
            label: 'Stale data',
            caption: 'Polls keep failing. Last values stay on screen, nothing animates.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_greeting, style: tx(28, w: w800, h: 1.15, em: -0.02)),
                const Gap(6),
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: MP.amber, shape: BoxShape.circle),
                      ),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          data == null ? 'Updated 3 min ago · Reconnecting' : 'Updated $_since · Reconnecting',
                          style: tx(14, w: w600, c: MP.amber),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Gap(8),
                      D8Link(
                        'Retry',
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onTap: _retry,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _Section(
            label: 'All clear',
            caption: 'Always rendered. An empty alerts card is never hidden.',
            child: MpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Open alerts', style: tx(20, w: w700, h: 1.25)),
                  const Gap(16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Ico(I.check, size: 20, color: MP.green, stroke: 2.25),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No open alerts', style: tx(16, w: w600, h: 1.5)),
                            Text(data == null ? 'Last checked 4s ago' : 'Last checked $_since', style: tx(13, c: MP.ink3, h: 18 / 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _Section(
            label: 'Not enough data',
            caption: 'Never "0 min". Zero reads as a real, good result.',
            child: MpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly impact', style: tx(20, w: w700, h: 1.25)),
                  const Gap(2),
                  Text('Last 7 days', style: tx(14, c: MP.ink2, h: 20 / 14)),
                  const Gap(20),
                  const SectionLabel('Avg consultation time', h: 16 / 12),
                  const Gap(4),
                  Text('Not enough data yet', style: _noData),
                  const Gap(4),
                  Text('Needs one completed consultation first.', style: tx(14, c: MP.ink2, h: 20 / 14)),
                  const Gap(20),
                  const SectionLabel('Patient chats', h: 16 / 12),
                  const Gap(4),
                  Text('Not enough data yet', style: _noData),
                ],
              ),
            ),
          ),
          _Section(
            label: 'Error',
            caption: 'Fails per card, in neutral tones. Danger is kept for emergencies.',
            child: MpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Needs review', style: tx(20, w: w700, h: 1.25)),
                  const Gap(16),
                  Text("Couldn't load this card", style: tx(16, w: w600, h: 1.5)),
                  const Gap(2),
                  Text('The rest of Home is unaffected.', style: tx(14, c: MP.ink2, h: 20 / 14)),
                  const Gap(16),
                  MpButton.small(
                    'Try again',
                    icon: I.history,
                    iconStroke: 1.75,
                    expand: false,
                    onTap: _retry,
                  ),
                ],
              ),
            ),
          ),
          _Section(
            label: 'Empty',
            caption: 'A real empty state with a way forward, never a blank card.',
            child: MpCard(
              radius: 20,
              shadow: MPShadow.float,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today's OPD queue", style: tx(20, w: w700, h: 1.25)),
                  const Gap(16),
                  Text('No visits booked today', style: tx(16, w: w600, h: 1.5)),
                  const Gap(2),
                  Text('Bookings and walk-ins show up here.', style: tx(14, c: MP.ink2, h: 20 / 14)),
                  const Gap(16),
                  MpButton.small('Open appointments', expand: false, onTap: () => Nav.go(context, 'Appointments')),
                ],
              ),
            ),
          ),
          _Section(
            label: 'Critical lab results · Loading',
            child: D8DashedBox(
              radius: 24,
              strokeWidth: 1.5,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Critical lab results', style: tx(16, w: w600, c: MP.ink2, h: 1.5)),
                  const Gap(4),
                  Text(
                    'Renders nothing while loading (prevents a false all-clear)',
                    style: tx(14, c: MP.ink2, h: 20 / 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final _noData = tx(16, w: w600, c: MP.ink3, h: 1.5);
}

/// A state section: uppercase label, gap 12, sample, gap 12, caption.
class _Section extends StatelessWidget {
  final String label;
  final String? caption;
  final Widget child;
  const _Section({required this.label, this.caption, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label, h: 1.35),
        const Gap(12),
        child,
        if (caption != null) ...[const Gap(12), Text(caption!, style: tx(13, c: MP.ink3, h: 1.4))],
      ],
    );
  }
}

/// Static #F1F4F9 blocks in the shape of the Home header and two cards.
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  static Widget _block({double? width, required double height, required double radius}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(radius)),
  );

  static Widget _fraction(double factor, double height) => FractionallySizedBox(
    widthFactor: factor,
    alignment: Alignment.centerLeft,
    child: _block(height: height, radius: 999),
  );

  static Widget _listRow(double a, double b) => Row(
    children: [
      _block(width: 40, height: 40, radius: 999),
      const Gap(12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_fraction(a, 14), const Gap(8), _fraction(b, 12)],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              _block(width: 97, height: 28, radius: 12),
              const Spacer(),
              _block(width: 24, height: 24, radius: 999),
              const Gap(12),
              _block(width: 40, height: 40, radius: 999),
            ],
          ),
        ),
        const Gap(20),
        _block(width: 240, height: 32, radius: 12),
        const Gap(8),
        _block(width: 180, height: 16, radius: 999),
        const Gap(20),
        SizedBox(
          width: double.infinity,
          child: MpCard(
            child: VGap(
              gap: 16,
              cross: CrossAxisAlignment.start,
              children: [
                _block(width: 140, height: 20, radius: 999),
                _listRow(0.60, 0.85),
                _listRow(0.50, 0.75),
                _listRow(0.55, 0.80),
              ],
            ),
          ),
        ),
        const Gap(16),
        SizedBox(
          width: double.infinity,
          child: MpCard(
            child: VGap(
              gap: 16,
              cross: CrossAxisAlignment.start,
              children: [
                _block(width: 120, height: 20, radius: 999),
                _block(width: 88, height: 30, radius: 12),
                _block(width: double.infinity, height: 10, radius: 999),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Knowledge-Shared.dc.html — "Knowledge · shared".
class KnowledgeSharedScreen extends StatelessWidget {
  const KnowledgeSharedScreen({super.key});

  static const _tags = ['levothyroxine', 'thyroid', 'dosage timing'];

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Knowledge entry'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        gap: 20,
        children: [
          // Read-only note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.lock, size: 20, color: MP.primary)),
                const Gap(12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Shared by MedPin.', style: tx(14, w: w600, h: 20 / 14)),
                        const TextSpan(text: " Your practice can adopt this entry but can't edit it."),
                      ],
                    ),
                    style: tx(14, h: 20 / 14),
                  ),
                ),
              ],
            ),
          ),

          // Status + title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const MpBadge.green('Approved', weight: w600),
                  const Gap(8),
                  Flexible(child: Text('Not yet adopted by your practice', style: tx(13, c: MP.ink3))),
                ],
              ),
              const Gap(8),
              Text('Thyroid tablet on an empty stomach', style: tx(28, w: w800, h: 1.15, em: -0.02)),
            ],
          ),

          // Entry details
          Semantics(
            container: true,
            label: 'Entry details',
            child: MpCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Item(
                    label: 'Content',
                    gap: 8,
                    divider: false,
                    child: Text(
                      'Levothyroxine works best on an empty stomach. Take it with a glass of water as soon as you wake up, '
                      '30 to 60 minutes before breakfast or tea. Keep calcium, iron and antacid tablets at least 4 hours '
                      'apart from it. If you miss a dose, take it the same day when you remember; do not take two doses '
                      'the next morning.',
                      style: tx(16, h: 1.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Pair('Language', 'English')),
                        Gap(12),
                        Expanded(child: _Pair('Category', 'Medicines')),
                      ],
                    ),
                  ),
                  _Item(
                    label: 'Source citation',
                    child: Text('American Thyroid Association, Hypothyroidism guidelines', style: tx(16, h: 1.5)),
                  ),
                  _Item(
                    label: 'Tags',
                    gap: 8,
                    child: Wrap(spacing: 8, runSpacing: 8, children: [for (final t in _tags) MpBadge(t, weight: w600)]),
                  ),
                  _Item(
                    label: 'Last updated',
                    child: Text('MedPin clinical team · 1 Sep 2026', style: tx(16, h: 24 / 16)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottom: MpBottomBar(
        child: MpButton(
          'Adopt for my practice',
          onTap: () {
            toast(context, 'Adopted for your practice');
            Nav.back(context);
          },
        ),
      ),
    );
  }
}

/// One `<dt>/<dd>` block: 16px vertical padding, optional top divider.
class _Item extends StatelessWidget {
  final String label;
  final Widget child;
  final double gap;
  final bool divider;
  const _Item({required this.label, required this.child, this.gap = 4, this.divider = true});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: divider ? const BoxDecoration(border: Border(top: BorderSide(color: MP.line))) : null,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [D10Caps(label), Gap(gap), child]),
  );
}

/// Label over a single-line value (16/24).
class _Pair extends StatelessWidget {
  final String label;
  final String value;
  const _Pair(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [D10Caps(label), const Gap(4), Text(value, style: tx(16, h: 24 / 16))],
  );
}

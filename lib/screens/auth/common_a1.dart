import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;

import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

/// Shared pieces for the sign-up screens (Auth-Welcome, Auth-Clinic-Setup,
/// Auth-Patient-Setup), in the style of Auth-Register.

/// "1 · Your details" step heading.
class A1Step extends StatelessWidget {
  final String text;
  const A1Step(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: tx(12, w: w700, c: MP.ink3, h: 1.35, em: 0.06));
}

/// Field label (14 / 600), with an optional muted "(optional)".
class A1Label extends StatelessWidget {
  final String text;
  final bool optional;
  const A1Label(this.text, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: text, style: tx(14, w: w600, h: 1.4)),
          if (optional) TextSpan(text: ' (optional)', style: tx(14, c: MP.ink3, h: 1.4)),
        ]),
      );
}

/// Big tappable choice card: icon tile, title, subtitle, chevron.
class A1Choice extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const A1Choice({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Tap(
        onTap: onTap,
        radius: 16,
        color: MP.white,
        border: MP.line,
        shadow: MPShadow.card,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            MpIconTile(icon, size: 48, iconSize: 24, radius: 14),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tx(17, w: w700, h: 1.3)),
                  const Gap(4),
                  Text(subtitle, style: tx(14, c: MP.ink2, h: 1.4)),
                ],
              ),
            ),
            const Gap(12),
            const Ico(I.chevronRight, size: 20, color: MP.ink3, stroke: 2),
          ],
        ),
      ),
    );
  }
}

/// "I agree to MedPin's Terms of Use and Privacy Policy." with working links.
class A1Terms extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const A1Terms({super.key, required this.value, required this.onChanged});

  @override
  State<A1Terms> createState() => _A1TermsState();
}

class _A1TermsState extends State<A1Terms> {
  late final _terms = TapGestureRecognizer()..onTap = () => Nav.go(context, 'Legal', args: {'doc': 'terms'});
  late final _privacy = TapGestureRecognizer()..onTap = () => Nav.go(context, 'Legal', args: {'doc': 'privacy'});

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = tx(14, w: w600, c: MP.primary, h: 1.4);
    return Semantics(
      checked: widget.value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.translate(offset: const Offset(0, -1), child: MpCheck(value: widget.value, onChanged: widget.onChanged)),
            const Gap(12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: tx(14, c: MP.ink2, h: 1.4),
                  children: [
                    const TextSpan(text: "I agree to MedPin's "),
                    TextSpan(text: 'Terms of Use', style: link, recognizer: _terms),
                    const TextSpan(text: ' and '),
                    TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

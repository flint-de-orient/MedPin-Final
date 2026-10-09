import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Consult-NotFound.dc.html — "Consultation · patient not found".
class ConsultNotfoundScreen extends StatelessWidget {
  const ConsultNotfoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Clearing the search returns to the empty search state (Consult-Pick).
    void clear() => Nav.tab(context, 'Consult-Pick');

    return MpPage(
      header: const D5Header('Consultation', subtitle: 'No patient selected'),
      bottom: const MpBottomBar(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: D5Button.disabled('Generate prescription'),
      ),
      body: VGap(
        // 136px in the design, less the 97px bar that covers it.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 39),
        gap: 16,
        children: [
          MpCard(
            radius: 20,
            shadow: MPShadow.float,
            child: VGap(
              gap: 16,
              children: [
                Text('Who are you consulting?', style: tx(20, w: w700, h: 1.25)),
                D5SearchField(
                  value: '98300 71245',
                  tab: true,
                  onClear: clear,
                  onSubmitted: (v) {
                    if (v.trim().isEmpty) clear();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No patient with this number', style: tx(16, w: w700)),
                      const Gap(4),
                      Text(
                        'Check the number, or add them as a new patient and start right away.',
                        style: tx(14, c: MP.ink2, h: 1.45),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const D5Label('Close match · check before adding', bottom: 4),
                    D5PersonRow(
                      leading: const MpAvatar('AG', size: 40, fontSize: 14),
                      name: 'Ankita Ghosh',
                      meta: TextSpan(
                        children: [
                          const TextSpan(text: '31 F · +91 98300 7'),
                          TextSpan(text: '1254', style: tx(13, w: w700, c: MP.ink, tab: true)),
                          const TextSpan(text: ' · last visit Jun'),
                        ],
                      ),
                      tab: true,
                      first: true,
                      onTap: () => Nav.go(context, 'Consult-Page'),
                    ),
                  ],
                ),
                D5Button('Add as new patient', icon: I.userPlus, onTap: () => Nav.go(context, 'Consult-QuickAdd')),
              ],
            ),
          ),
          MpCard(
            shadow: null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: D5IconText(
              icon: I.lock,
              text: 'Vitals, complaint, diagnosis and prescription open once a patient is selected.',
              style: tx(13, c: MP.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

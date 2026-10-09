import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Records-Add.dc.html — "Records · add a record" (sheet over Patient-Records).
class RecordsAddSheet extends StatefulWidget {
  const RecordsAddSheet({super.key});

  @override
  State<RecordsAddSheet> createState() => _RecordsAddSheetState();
}

class _RecordsAddSheetState extends State<RecordsAddSheet> {
  int _kind = 1;

  static const _sources = [(I.camera, 'Take photo'), (I.image, 'Gallery'), (I.fileText, 'PDF file')];

  static const _doctors = [
    P2Doctor('Dr. Arjun Sen', "Suggested · asked for this before today's 5 PM visit", suggested: true, on: true),
    P2Doctor('Dr. Rina Mitra', 'Heart · City Care'),
    P2Doctor('Dr. Nandita Gupta', 'Gynaecology · Apollo Clinic'),
  ];

  @override
  Widget build(BuildContext context) {
    return MpSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(20),
            const P2SheetHeader(
              title: 'Add a record',
              subtitle: 'We read it for you, summarise it in simple words and flag anything out of range.',
              subtitleHeight: 1.45,
            ),
            const Gap(20),

            // What are you adding?
            Text('What are you adding?', style: tx(14, w: w600)),
            const Gap(8),
            P2Segmented(
              options: const ['Prescription', 'Test result'],
              index: _kind,
              onChanged: (i) => setState(() => _kind = i),
            ),
            const Gap(20),

            // Take photo · Gallery · PDF file
            Row(
              children: [
                for (var i = 0; i < _sources.length; i++) ...[
                  if (i > 0) const Gap(8),
                  Expanded(
                    child: P2Box(
                      onTap: () => p2SheetThen(context, 'Records-Review'),
                      label: _sources[i].$2,
                      height: 104,
                      radius: 16,
                      color: MP.white,
                      border: MP.lineStrong,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MpIconTile(_sources[i].$1, size: 44, radius: 12, iconSize: 22),
                          const Gap(10),
                          Text(_sources[i].$2, style: tx(14, w: w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Gap(20),

            const P2ShareDoctors(title: 'Share with', doctors: _doctors),
            const Gap(20),

            Row(
              children: [
                // 16px svg without flex-shrink: 0 — the wrapping text squeezes it to 12px in the design.
                const Ico(I.lock, size: 12, color: MP.ink3),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Only you and the doctors you pick can see it. You can stop sharing any time.',
                    style: tx(13, c: MP.ink3),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }
}

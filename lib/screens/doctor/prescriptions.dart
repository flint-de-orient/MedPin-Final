import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Prescriptions.dc.html — "Prescriptions" (Priya Sharma's list).
class PrescriptionsScreen extends StatelessWidget {
  const PrescriptionsScreen({super.key});

  static const _issued = [
    (
      date: '29 Sep 2026',
      dx: 'Type 2 diabetes mellitus, PCOS',
      meds: '3',
      labs: '3',
      follow: '29 Oct',
      list: 'Metformin 500 mg, Glimepiride 2 mg, Atorvastatin 10 mg',
    ),
    (
      date: '12 Mar 2026',
      dx: 'Type 2 diabetes mellitus, dyslipidaemia',
      meds: '2',
      labs: '2',
      follow: '12 Jun',
      list: 'Metformin 500 mg, Atorvastatin 10 mg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const _Header(),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          // File a paper prescription
          MpCard(
            child: VGap(
              gap: 16,
              children: [
                const D7Title('File a paper prescription', sub: 'Scan or upload one written on paper'),
                Row(
                  children: [
                    Expanded(child: _UploadButton(I.camera, 'Camera', onTap: () => toast(context, 'Opening camera'))),
                    const SizedBox(width: 8),
                    Expanded(child: _UploadButton(I.image, 'Gallery', onTap: () => toast(context, 'Opening gallery'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _UploadButton(I.fileText, 'PDF', onTap: () => toast(context, 'Choose a PDF to file')),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('3 PRESCRIPTIONS · LATEST FIRST', style: tx(12, w: w600, h: 1.35, em: 0.06, c: MP.ink3)),
          ),

          for (final rx in _issued)
            _RxCard(
              date: rx.date,
              byline: 'Dr. Arjun Sen · City Care Clinic, Salt Lake',
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DIAGNOSIS', style: tx(12, w: w600, h: 1.35, em: 0.06, c: MP.ink3)),
                    const SizedBox(height: 4),
                    Text(rx.dx, style: tx(16, h: 1.5)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MpGrid(
                      columns: 3,
                      children: [
                        _Stat(rx.meds, 'Medicines'),
                        _Stat(rx.labs, 'Lab tests'),
                        _Stat(rx.follow, 'Follow-up'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(rx.list, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2, h: 1.45)),
                  ],
                ),
              ],
            ),

          // Scanned paper prescription
          _RxCard(
            date: '12 Jan 2026',
            scanned: true,
            byline: 'Paper prescription · filed by Dr. Arjun Sen',
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Ico(I.fileText, size: 22, color: MP.ink2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Prescription, 12 Jan 2026',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx(15, w: w600),
                          ),
                          const SizedBox(height: 2),
                          Text('Photo from camera · 1 page', style: tx(13, c: MP.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 64px bar: back + "Prescriptions" (20/700) over "Priya Sharma" (14/1.45).
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      color: MP.bg,
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prescriptions', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(20, w: w700, h: 1.25)),
                Text('Priya Sharma', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 48px #EBF1FB tile button: 18px icon, 6px gap, 15/600 label.
class _UploadButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _UploadButton(this.icon, this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      radius: 12,
      color: MP.primarySoft,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Ico(icon, size: 18, color: MP.primary),
                  const SizedBox(width: 6),
                  Text(label, style: tx(15, w: w600, c: MP.primary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prescription card: date (+ Scanned tag), byline, [children], Download PDF.
class _RxCard extends StatelessWidget {
  final String date;
  final String byline;
  final bool scanned;
  final List<Widget> children;
  const _RxCard({required this.date, required this.byline, this.scanned = false, required this.children});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${scanned ? 'Scanned prescription' : 'Prescription'}, $date',
      child: MpCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: VGap(
          gap: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(date, style: tx(20, w: w700, h: 1.25, tab: true)),
                    if (scanned) ...[const SizedBox(width: 8), const MpBadge.grey('Scanned', weight: w600)],
                  ],
                ),
                const SizedBox(height: 2),
                Text(byline, style: tx(14, c: MP.ink2, h: 1.45)),
              ],
            ),
            ...children,
            D7Ruled(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: D7Btn(
                  'Download PDF',
                  icon: I.download,
                  height: 44,
                  radius: 8,
                  padding: EdgeInsets.zero,
                  onTap: () => toast(context, 'Downloading PDF · $date'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// #F7F9FC stat tile: 16/700 value over a 13px label.
class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: tx(16, w: w700, tab: true)),
          const SizedBox(height: 2),
          Text(label, style: tx(13, c: MP.ink2)),
        ],
      ),
    );
  }
}

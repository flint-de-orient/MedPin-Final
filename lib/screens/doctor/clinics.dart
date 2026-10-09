import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Clinics.dc.html — "Locations".
class ClinicsScreen extends StatelessWidget {
  const ClinicsScreen({super.key});

  static const _locations = [
    (
      name: 'City Care Clinic — Salt Lake',
      status: 'Active',
      days: 'Mon–Sat · 15-min slots',
      meta: 'DD-24, Sector 1, Salt Lake · 2 doctors',
    ),
    (
      name: 'City Care — New Town',
      status: 'Active',
      days: 'Tue · Thu · Sat · 20-min slots',
      meta: 'AA-II, Action Area 2, New Town · 1 doctor',
    ),
    (
      name: 'City Care — Behala',
      status: 'Inactive',
      days: 'No new bookings',
      meta: 'Deactivated 14 Aug 2026 · history kept',
    ),
    (
      name: 'Apollo Diagnostics desk',
      status: 'View only',
      days: 'Shared lab desk',
      meta: 'Managed by Apollo Diagnostics, not editable',
    ),
  ];

  /// Status pill fill / text (renderVals() ACTIVE, INACTIVE, SHARED).
  static (Color, Color) _tone(String status) => switch (status) {
    'Active' => (MP.greenSoft, MP.green),
    'Inactive' => (MP.fill, MP.ink2),
    _ => (MP.primarySoft, MP.primary),
  };

  @override
  Widget build(BuildContext context) {
    void addLocation() => Nav.go(context, 'Clinic-Editor');

    return MpPage(
      header: MpHeader(
        'Locations',
        actions: [MpIconButton(I.plus, label: 'Add location', color: MP.primary, onTap: addLocation)],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          Text('City Care Clinic · 2 active, 1 inactive, 1 shared', style: tx(14, c: MP.ink2)),
          Semantics(
            container: true,
            label: 'Locations',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: MPDeco.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < _locations.length; i++) _row(context, i)],
              ),
            ),
          ),
          Text(
            "Locations are never deleted. Deactivating one stops new bookings and keeps every patient's history.",
            style: tx(13, c: MP.ink3, h: 1.45),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: D7Btn(
              'Add location',
              bg: MP.primary,
              fg: MP.white,
              shadow: MPShadow.button,
              height: 56,
              radius: 16,
              size: 16,
              icon: I.plus,
              iconSize: 20,
              expand: true,
              onTap: addLocation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final l = _locations[i];
    final tone = _tone(l.status);
    final shared = l.status == 'View only';
    return Tap(
      onTap:
          shared
              ? () => toast(context, 'View only · managed by Apollo Diagnostics')
              : () => Nav.go(context, 'Clinic-Editor'),
      radius: 12,
      child: D7Ruled(
        top: i > 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tx(16, w: w600, c: l.status == 'Inactive' ? MP.ink2 : MP.ink),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      MpBadge(l.status, bg: tone.$1, fg: tone.$2, weight: w600),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(l.days, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(l.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: MP.ink3)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Ico(I.chevronRight, size: 18, color: MP.ink3),
          ],
        ),
      ),
    );
  }
}

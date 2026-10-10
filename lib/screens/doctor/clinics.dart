import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d7.dart';
import '../../widgets/i18n.dart';

/// Design: Clinics.dc.html — "Locations".
/// Live data: GET /api/locations; rows open Clinic-Editor {'locationId'}.
class ClinicsScreen extends StatefulWidget {
  const ClinicsScreen({super.key});

  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

typedef _Location = ({String name, String status, String days, String meta});

class _ClinicsScreenState extends State<ClinicsScreen> with LiveData {
  @override
  Future<Object?> fetch() => Api.I.get('/api/locations');

  static const _sample = [
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

  List<Map<String, dynamic>> get _items => data?.list('items') ?? const [];

  List<_Location> get _locations {
    if (data == null) return _sample;
    return [for (final l in _items) _fromApi(l)];
  }

  static _Location _fromApi(Map<String, dynamic> l) {
    final status = switch (l.str('status')) {
      'inactive' => 'Inactive',
      'view_only' => 'View only',
      _ => 'Active',
    };
    final doctors = l.numOr('doctors').toInt();
    final off = F.date(l['deactivatedAt']);
    final slot = l['slotMinutes'] is num ? ' · ${l['slotMinutes']}-min slots' : '';
    final open = d7OpenDays(l.list('weeklyHours'));
    return (
      name: l.str('name'),
      status: status,
      days: switch (status) {
        'Inactive' => 'No new bookings',
        'View only' => 'Shared ${l.str('type', 'location').replaceAll('_', ' ')}',
        _ => open.isEmpty ? 'No opening hours yet' : '$open$slot',
      },
      meta: switch (status) {
        'Inactive' => off == null ? 'History kept' : 'Deactivated ${d7Date(off).substring(5)} · history kept',
        'View only' => 'Managed by another organisation, not editable',
        _ => [
          d7ShortAddress(l),
          '$doctors ${doctors == 1 ? 'doctor' : 'doctors'}',
        ].where((s) => s.isNotEmpty).join(' · '),
      },
    );
  }

  String get _summary {
    final d = data;
    if (d == null) return 'City Care Clinic · 2 active, 1 inactive, 1 shared';
    final s = d.obj('summary');
    final practice = Session.I.activeMembership?['practiceName'] as String? ?? '';
    final counts = [
      '${s.numOr('active')} active',
      if (s.numOr('inactive') > 0) '${s.numOr('inactive')} inactive',
      if (s.numOr('shared') > 0) '${s.numOr('shared')} shared',
    ].join(', ');
    return practice.isEmpty ? counts : '$practice · $counts';
  }

  Future<void> _open(String? locationId) async {
    await Nav.go(context, 'Clinic-Editor', args: locationId == null ? null : {'locationId': locationId});
    if (mounted && isLive) reload(quiet: true);
  }

  /// Status pill fill / text (renderVals() ACTIVE, INACTIVE, SHARED).
  static (Color, Color) _tone(String status) => switch (status) {
    'Active' => (MP.greenSoft, MP.green),
    'Inactive' => (MP.fill, MP.ink2),
    _ => (MP.primarySoft, MP.primary),
  };

  @override
  Widget build(BuildContext context) {
    void addLocation() => _open(null);
    final placeholder = livePlaceholder();
    final locations = _locations;

    return MpPage(
      header: MpHeader(
        'Locations',
        actions: [MpIconButton(I.plus, label: 'Add location', color: MP.primary, onTap: addLocation)],
      ),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gap: 16,
        children: [
          Text(_summary, style: tx(14, c: MP.ink2)),
          Semantics(
            container: true,
            label: 'Locations',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: MPDeco.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < locations.length; i++) _row(context, locations, i),
                  if (locations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No locations yet', style: tx(14, c: MP.ink2)),
                    ),
                ],
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

  Widget _row(BuildContext context, List<_Location> locations, int i) {
    final l = locations[i];
    final tone = _tone(l.status);
    final shared = l.status == 'View only';
    final id = data == null || i >= _items.length ? null : _items[i].str('id');
    return Tap(
      onTap:
          shared
              ? () => toast(
                context,
                data == null ? 'View only · managed by Apollo Diagnostics' : 'View only · managed by another organisation',
              )
              : () => data == null ? Nav.go(context, 'Clinic-Editor') : _open(id),
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

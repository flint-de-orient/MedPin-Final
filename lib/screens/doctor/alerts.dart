import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d7.dart';

/// Design: Alerts.dc.html — "Alerts" (Clinical alerts).
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

enum _Status { open, acknowledged, resolved }

class _Alert {
  _Alert({
    required this.sev,
    required this.time,
    required this.initials,
    required this.name,
    required this.meta,
    required this.detail,
    this.status = _Status.open,
    this.note,
    this.noteBy,
  });

  /// Index into the severities: 0 Emergency, 1 Urgent, 2 Watch.
  final int sev;
  final String time;
  final String initials;
  final String name;
  final String meta;
  final String detail;
  _Status status;
  final String? note;
  final String? noteBy;
}

class _AlertsScreenState extends State<AlertsScreen> {
  static const _tabs = ['Open', 'Acknowledged', 'Resolved', 'All'];

  /// Severity: label, filter dot, badge text / fill, border of an open card.
  static const _sevs = [
    (label: 'Emergency', dot: MP.red, fg: MP.red, bg: MP.redSoft, border: MP.redLine),
    (label: 'Urgent', dot: MP.amber, fg: MP.amber, bg: MP.amberSoft, border: MP.line),
    (label: 'Watch', dot: MP.ink3, fg: MP.ink2, bg: MP.fill, border: MP.line),
  ];

  final _alerts = [
    _Alert(
      sev: 0,
      time: '9:12 AM',
      initials: 'PS',
      name: 'Priya Sharma',
      meta: '29 F · Type 2 DM, PCOS',
      detail: 'Emergency message: chest tightness and sweating since morning.',
    ),
    _Alert(
      sev: 1,
      time: '8:40 AM',
      initials: 'RD',
      name: 'Rahul Das',
      meta: '45 M · Hypertension',
      detail: 'Home BP reading 172/104 mmHg, above his alert limit.',
    ),
    _Alert(
      sev: 2,
      time: '7:30 AM',
      initials: 'AK',
      name: 'Aisha Khan',
      meta: '52 F · Hypothyroidism',
      detail: 'TSH 8.9 mIU/L, high. Missed thyroxine on 3 of the last 7 days.',
      status: _Status.acknowledged,
      note: 'Called patient, advised to come in',
      noteBy: 'Dr. Sen, 9:20 AM',
    ),
  ];

  int _tab = 0;
  final Set<int> _sevOn = {};
  String _query = '';

  /// Alerts with [status] (all when null) matching the search and severity
  /// filters, most severe first.
  List<_Alert> _list(_Status? status) {
    final q = _query.trim().toLowerCase();
    final out =
        _alerts
            .where(
              (a) =>
                  (status == null || a.status == status) &&
                  (_sevOn.isEmpty || _sevOn.contains(a.sev)) &&
                  a.name.toLowerCase().contains(q),
            )
            .toList();
    out.sort((a, b) => a.sev != b.sev ? a.sev.compareTo(b.sev) : a.status.index.compareTo(b.status.index));
    return out;
  }

  void _toggleSeverity(int i) {
    setState(() {
      if (!_sevOn.remove(i)) _sevOn.add(i);
    });
  }

  void _acknowledge(_Alert a) {
    setState(() => a.status = _Status.acknowledged);
    toast(context, 'Alert acknowledged');
  }

  void _resolve(_Alert a) {
    setState(() => a.status = _Status.resolved);
    toast(context, 'Alert resolved');
  }

  @override
  Widget build(BuildContext context) {
    final openTotal = _alerts.where((a) => a.status == _Status.open).length;
    final open = _list(_Status.open);
    final acknowledged = _list(_Status.acknowledged);
    final resolved = _list(_Status.resolved);
    final all = _list(null);
    final (String summary, List<_Alert> shown) = switch (_tab) {
      0 => ('${open.length} open · most severe first', open),
      1 => ('${acknowledged.length} acknowledged', acknowledged),
      2 => (resolved.isEmpty ? 'No resolved alerts yet' : '${resolved.length} resolved', resolved),
      _ => ('${all.length} alerts · most severe first', all),
    };

    return MpPage(
      header: const MpHeader('Clinical alerts'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status tabs + severity filters
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MpChipRow(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      D7Pill(
                        i == 0 ? 'Open ($openTotal)' : _tabs[i],
                        on: _tab == i,
                        borderOn: false,
                        hPad: 14,
                        onTap: () => setState(() => _tab = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                MpChipRow(
                  children: [
                    for (var i = 0; i < _sevs.length; i++)
                      D7Pill(
                        _sevs[i].label,
                        on: _sevOn.contains(i),
                        tonal: true,
                        hPad: 14,
                        dot: _sevs[i].dot,
                        onTap: () => _toggleSeverity(i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            gap: 16,
            children: [
              D7Field(
                hint: 'Search by patient name',
                padding: const EdgeInsets.only(left: 48, right: 16),
                action: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                overlays: const [
                  Positioned(left: 16, top: 18, child: IgnorePointer(child: Ico(I.search, size: 20, color: MP.ink3))),
                ],
              ),
              Text(summary, style: tx(14, c: MP.ink2)),
              for (final a in shown) _card(a),
              if (_tab == 0 && acknowledged.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('ACKNOWLEDGED TODAY', style: tx(12, w: w600, em: 0.06, c: MP.ink3)),
                ),
                for (final a in acknowledged) _card(a),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(_Alert a) {
    final s = _sevs[a.sev];
    final status = switch (a.status) {
      _Status.open => const MpBadge.grey('Open', weight: w600),
      _Status.acknowledged => const MpBadge.blue('Acknowledged', weight: w600),
      _Status.resolved => const MpBadge.green('Resolved', weight: w600),
    };
    return MpCard(
      border: a.status == _Status.open ? s.border : MP.line,
      child: VGap(
        gap: 16,
        children: [
          Row(
            children: [
              MpBadge(s.label, bg: s.bg, fg: s.fg),
              const SizedBox(width: 8),
              status,
              const SizedBox(width: 8),
              const Spacer(),
              Text(a.time, style: tx(13, c: MP.ink3, tab: true)),
            ],
          ),
          Tap(
            onTap: () => Nav.go(context, 'PP-Summary'),
            radius: 12,
            child: Row(
              children: [
                MpAvatar(a.initials, size: 40, fontSize: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                      Text(a.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, c: MP.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Ico(I.chevronRight, size: 18, color: MP.ink3),
              ],
            ),
          ),
          Text(a.detail, style: tx(16, h: 1.5)),
          if (a.note != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.note!, style: tx(14, h: 1.45)),
                  const SizedBox(height: 4),
                  Text(a.noteBy ?? '', style: tx(13, c: MP.ink3)),
                ],
              ),
            ),
          if (a.status == _Status.open)
            Row(
              children: [
                Expanded(child: D7Btn('Acknowledge', bg: MP.primarySoft, expand: true, onTap: () => _acknowledge(a))),
                const SizedBox(width: 8),
                D7Btn(
                  'Resolve',
                  bg: MP.white,
                  fg: MP.ink,
                  border: MP.lineStrong,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  onTap: () => _resolve(a),
                ),
              ],
            ),
          if (a.status == _Status.acknowledged)
            D7Btn(
              'Resolve',
              bg: MP.white,
              fg: MP.ink,
              border: MP.lineStrong,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              expand: true,
              onTap: () => _resolve(a),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/device_sync.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_p1.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-Track.dc.html — "Patient · choose what to track" (sheet over 'Main').
class PatientTrackSheet extends StatefulWidget {
  const PatientTrackSheet({super.key});

  @override
  State<PatientTrackSheet> createState() => _PatientTrackSheetState();
}

/// Live: the choice comes from GET /api/patient/me (trackedMeasures) and Save
/// sends PATCH /api/patient/me, then the sheet closes with true.
class _PatientTrackSheetState extends State<PatientTrackSheet> with LiveData {
  static const _max = 4;
  static const _items = [
    (key: 'blood_sugar', name: 'Blood sugar', source: 'You log it'),
    (key: 'blood_pressure', name: 'Blood pressure', source: 'You log it'),
    (key: 'hba1c', name: 'HbA1c', source: 'From lab reports'),
    (key: 'heart_rate', name: 'Heart rate', source: 'You log it or a device'),
    (key: 'weight', name: 'Weight', source: 'You log it'),
    (key: 'spo2', name: 'SpO₂', source: 'From a device'),
  ];
  /// Watches and rings sync through Health Connect (Android) or Apple Health.
  static const _devices = [
    ('Smartwatch', 'Fitbit, Samsung, Mi, Noise, boAt and more'),
    ('Smart ring', 'Oura, Ultrahuman, Samsung Galaxy Ring and more'),
  ];

  final List<bool> _on = [true, true, false, false, false, false];
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    final me = (await Api.I.get('/api/patient/me') as Map).cast<String, dynamic>();
    final sync = (me['deviceSync'] as Map?)?.cast<String, dynamic>();
    _synced = F.date(sync?['at']);
    _source = sync?['source'] as String?;
    final tracked = {for (final m in (me['trackedMeasures'] as List? ?? const [])) '$m'};
    for (var i = 0; i < _items.length; i++) {
      _on[i] = tracked.contains(_items[i].key);
    }
    return me;
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  int get _count => _on.where((v) => v).length;

  /// The last watch / ring sync (from the Home data the server keeps).
  DateTime? _synced;
  String? _source;

  Future<void> _connect() async {
    if (!isLive) return toast(context, 'Connect your watch or ring');
    final ok = await DeviceSync.connect(context);
    if (ok && mounted) setState(() => _synced = DateTime.now());
  }

  void _toggle(int i) {
    // Pick up to 4.
    if (!_on[i] && _count >= _max) {
      if (isLive) toast(context, 'Pick up to $_max');
      return;
    }
    setState(() => _on[i] = !_on[i]);
  }

  Future<void> _save() async {
    if (!isLive) {
      P1.closeWithToast(context, 'Saved');
      return;
    }
    final keys = [
      for (var i = 0; i < _items.length; i++)
        if (_on[i]) _items[i].key,
    ];
    final ok = await runAction(context, () => Api.I.patch('/api/patient/me', {'trackedMeasures': keys}), busy: _busy);
    if (ok != null && mounted) P1.closeWithToast(context, 'Saved', true);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: VGap(
          gap: 18,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What do you want to track?', style: tx(20, w: w700, h: 1.25)),
                const Gap(4),
                Text(
                  'Pick up to 4. They appear on your home screen and your doctor sees them too. You can skip this.',
                  style: tx(14, h: 1.45, c: MP.ink2),
                ),
              ],
            ),
            Semantics(
              label: 'Health measures',
              child: MpGrid(
                columns: 2,
                children: [for (var i = 0; i < _items.length; i++) _tile(i)],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('SYNC FROM A DEVICE', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                ),
                for (var i = 0; i < _devices.length; i++)
                  Tap(
                    onTap: _connect,
                    radius: 0,
                    child: Container(
                      constraints: BoxConstraints(minHeight: i == 0 ? 56 : 57),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_devices[i].$1, style: tx(15, w: w600)),
                                const Gap(1),
                                Text(_synced == null ? _devices[i].$2 : 'Syncs through ${_source ?? 'your phone'} · ${F.ago(_synced!)}', style: tx(13, c: MP.ink2)),
                              ],
                            ),
                          ),
                          const Gap(12),
                          if (!isLive)
                            const MpBadge.blue('Connect')
                          else if (_synced == null)
                            const MpBadge.blue('Connect')
                          else
                            const MpBadge.green('Connected'),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Turn on Health Connect sync in your watch or ring app, then tap Connect.',
                    style: tx(12, c: MP.ink3, h: 1.4),
                  ),
                ),
              ],
            ),
            MpButton('Save · $_count selected', onTap: data == null && isLive ? null : _save),
          ],
        ),
      ),
    );
  }

  Widget _tile(int i) {
    final on = _on[i];
    // Border-box button: min-height 72 includes the 1.5px / 1px border.
    return Semantics(
      button: true,
      toggled: on,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Tap(
          onTap: () => _toggle(i),
          radius: 16,
          color: on ? MP.primarySoft : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          borderWidth: on ? 1.5 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MpCheck(value: on, onChanged: (_) => _toggle(i)),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_items[i].name, style: tx(15, w: w700)),
                      const Gap(2),
                      Text(_items[i].source, style: tx(12, h: 1.35, c: MP.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

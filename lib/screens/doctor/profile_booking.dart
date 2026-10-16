import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Doctor · Booking rules (from My profile), per location: online booking,
/// approving each booking, how far ahead, the cancel / reschedule cut-off,
/// slot length, patients per slot and walk-in places.
/// Live: GET /api/doctor/locations; Save → PUT /api/doctor/locations/:id with
/// only these schedule fields (the weekly hours stay as they are). The server
/// uses each one: visit requests and the patient's slot list (online booking,
/// approval, booking window), cancelling (cut-off), slots (length, per slot,
/// walk-ins kept free).
Future<void> openBookingRules(BuildContext context, {String? locationId}) =>
    openSheet<void>(context, (_) => _BookingRulesSheet(locationId: locationId));

/// One location's rules as edited.
class _Rules {
  _Rules(this.id, this.name, Map<String, dynamic> s)
    : online = s['onlineBooking'] != false,
      approve = s['requireApproval'] == true,
      ahead = s.numOr('bookingWindowDays', 7).toInt(),
      cancel = s.numOr('cancelCutoffHours', 2).toInt(),
      slot = s.numOr('slotLengthMin', 15).toInt(),
      perSlot = s.numOr('patientsPerSlot', 1).toInt(),
      walkIns = s.numOr('walkInPlaces').toInt(),
      breakMin = s.numOr('breakBetweenMin').toInt(),
      sessions = [
        for (final d in s.list('week'))
          for (final x in d.list('sessions')) x.numOr('endMin').toInt() - x.numOr('startMin').toInt(),
      ];

  final String id;
  final String name;
  bool online, approve;
  int ahead, cancel, slot, perSlot, walkIns;

  final int breakMin;

  /// Session lengths (minutes) across the week.
  final List<int> sessions;
  bool dirty = false;

  /// Slots in the longest session at the current slot length: walk-in places can't be more.
  int get maxWalkIns {
    var best = 0;
    for (final len in sessions) {
      if (len >= slot) best = math.max(best, (len - slot) ~/ (slot + breakMin) + 1);
    }
    return best;
  }

  Map<String, Object?> get body => {
    'onlineBooking': online,
    'requireApproval': approve,
    'bookingWindowDays': ahead,
    'cancelCutoffHours': cancel,
    'slotLengthMin': slot,
    'patientsPerSlot': perSlot,
    'walkInPlaces': walkIns,
  };
}

class _BookingRulesSheet extends StatefulWidget {
  final String? locationId;
  const _BookingRulesSheet({this.locationId});

  @override
  State<_BookingRulesSheet> createState() => _BookingRulesSheetState();
}

class _BookingRulesSheetState extends State<_BookingRulesSheet> {
  List<_Rules>? _locs;
  String? _error;
  int _sel = 0;
  final _busy = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    if (isLive) {
      _load();
    } else {
      _locs = [
        _Rules('', 'Salt Lake', const {'walkInPlaces': 4, 'week': []}),
        _Rules('', 'New Town', const {'walkInPlaces': 2, 'slotLengthMin': 20, 'week': []}),
      ];
    }
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.get('/api/doctor/locations');
      if (!mounted) return;
      final out = <_Rules>[];
      for (final x in r as List? ?? const []) {
        final dl = (x as Map).cast<String, dynamic>();
        final loc = dl.obj('locationId');
        if (dl['status'] == 'ended' || loc['status'] == 'inactive') continue;
        out.add(_Rules(loc.str('id'), loc.str('shortName', loc.str('name')), dl.obj('schedule')));
      }
      final i = out.indexWhere((l) => l.id == widget.locationId);
      setState(() {
        _locs = out;
        _sel = i < 0 ? 0 : i;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _set(void Function(_Rules l) change) => setState(() {
    final l = _locs![_sel];
    change(l);
    l.walkIns = math.min(l.walkIns, isLive ? l.maxWalkIns : 8);
    l.dirty = true;
  });

  Future<void> _save() async {
    final locs = _locs;
    if (locs == null) return;
    if (!isLive) {
      toast(context, 'Booking rules saved');
      Navigator.pop(context);
      return;
    }
    for (final l in locs.where((l) => l.dirty && l.id.isNotEmpty)) {
      final ok = await runAction(context, () => Api.I.put('/api/doctor/locations/${l.id}', {'schedule': l.body}), busy: _busy);
      if (ok == null || !mounted) return;
      l.dirty = false;
    }
    if (!mounted) return;
    toast(context, 'Booking rules saved');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final locs = _locs;
    final Widget body;
    if (locs == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: _error == null
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))
              : Column(children: [
                  Text(_error!, textAlign: TextAlign.center, style: tx(15, c: MP.ink2, h: 1.5)),
                  const Gap(12),
                  MpButton('Try again', kind: MpBtn.secondary, expand: false, onTap: _load),
                ]),
        ),
      );
    } else if (locs.isEmpty) {
      body = Text('You don’t practise at any location yet.', style: tx(14, c: MP.ink2));
    } else {
      final l = locs[_sel];
      final maxWalk = isLive ? l.maxWalkIns : 8;
      body = VGap(
        gap: 16,
        children: [
          if (locs.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < locs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    D4OptionCard(
                      title: locs[i].name,
                      sub: locs[i].online ? 'Online booking on' : 'Online booking off',
                      selected: i == _sel,
                      titleSize: 14,
                      nowrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      onTap: () => setState(() => _sel = i),
                    ),
                  ],
                ],
              ),
            ),
          D4SwitchRow(
            title: 'Online booking',
            sub: l.online ? 'Patients book from the MedPin app' : 'Patients are asked to call the clinic',
            value: l.online,
            onChanged: (v) => _set((l) => l.online = v),
          ),
          D4SwitchRow(
            title: 'Approve each booking',
            sub: l.approve ? 'Front desk confirms before it’s final' : 'A free slot is booked at once',
            value: l.approve,
            onChanged: (v) => _set((l) => l.approve = v),
          ),
          D4StepperRow(
            title: 'Open booking',
            sub: 'How far ahead patients can book',
            value: '${l.ahead} ${l.ahead == 1 ? 'day' : 'days'}',
            onMinus: l.ahead > 1 ? () => _set((l) => l.ahead -= 1) : null,
            onPlus: l.ahead < 60 ? () => _set((l) => l.ahead += 1) : null,
          ),
          D4StepperRow(
            title: 'Cancel or reschedule',
            sub: 'Allowed until this long before',
            value: '${l.cancel} ${l.cancel == 1 ? 'hr' : 'hrs'}',
            onMinus: l.cancel > 1 ? () => _set((l) => l.cancel -= 1) : null,
            onPlus: l.cancel < 48 ? () => _set((l) => l.cancel += 1) : null,
          ),
          D4StepperRow(
            title: 'Slot length',
            sub: 'Time you plan per patient',
            value: '${l.slot} min',
            onMinus: l.slot > 5 ? () => _set((l) => l.slot -= 5) : null,
            onPlus: l.slot < 60 ? () => _set((l) => l.slot += 5) : null,
          ),
          D4StepperRow(
            title: 'Patients per slot',
            sub: 'More than 1 lets you double-book',
            value: '${l.perSlot}',
            onMinus: l.perSlot > 1 ? () => _set((l) => l.perSlot -= 1) : null,
            onPlus: l.perSlot < 6 ? () => _set((l) => l.perSlot += 1) : null,
          ),
          D4StepperRow(
            title: 'Walk-in places',
            sub: maxWalk == 0 ? 'Add weekly hours first' : 'Kept free each session, not bookable online',
            value: '${l.walkIns}',
            onMinus: l.walkIns > 0 ? () => _set((l) => l.walkIns -= 1) : null,
            onPlus: l.walkIns < maxWalk ? () => _set((l) => l.walkIns += 1) : null,
          ),
          const D4Note('Weekly hours and breaks are in Schedules and slots.'),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, _) => MpButton(busy ? 'Saving…' : 'Save', onTap: busy ? null : _save),
          ),
        ],
      );
    }
    return MpSheet(title: 'Booking rules', subtitle: 'Set separately for each location', showClose: true, child: body);
  }
}

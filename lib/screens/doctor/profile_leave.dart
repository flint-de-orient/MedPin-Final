import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';

/// Doctor · Leave and holidays (from My profile, "Take leave" and Schedules).
/// Live: GET /api/doctor/time-off (the doctor's leave + the holidays of the
/// clinics they practise at); Add leave → POST /api/doctor/leaves (booked
/// patients are told), cancel → DELETE /api/doctor/leaves/:id; owners and
/// practice managers add / remove clinic holidays with
/// POST / DELETE /api/locations/:id/closures. With [add] the Add leave form
/// opens straight away ("Take leave").
Future<void> openTimeOff(BuildContext context, {bool add = false}) =>
    openSheet<void>(context, (_) => _TimeOffSheet(startWithAdd: add));

/// The Add leave / Add clinic holiday form on its own (Schedules' "Add leave",
/// Clinic-Editor's "Add closure"). [locations] are (id, name); for a holiday a
/// location must be chosen, for leave null means all locations.
/// Resolves {reason, startDate, endDate, locationId} or null.
Future<Map<String, String?>?> pickTimeOff(
  BuildContext context, {
  required bool holiday,
  required List<(String, String)> locations,
  String? locationId,
}) => openSheet<Map<String, String?>>(context, (_) => _TimeOffForm(holiday: holiday, locations: locations, locationId: locationId));

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "1 patient will be told", "no patients booked".
String timeOffPatients(int n) => switch (n) {
  0 => 'no patients booked',
  1 => '1 patient will be told',
  _ => '$n patients will be told',
};

class _TimeOffSheet extends StatefulWidget {
  final bool startWithAdd;
  const _TimeOffSheet({this.startWithAdd = false});

  @override
  State<_TimeOffSheet> createState() => _TimeOffSheetState();
}

class _TimeOffSheetState extends State<_TimeOffSheet> {
  Map<String, dynamic>? _data;
  String? _error;
  final _busy = ValueNotifier(false);

  // Design preview: the sample leave and holiday.
  final _sampleLeave = <(String, String)>[('Durga Puja', '19 – 23 Oct · all locations · 14 patients will be told')];
  final _sampleHolidays = <(String, String)>[('Gandhi Jayanti', '2 Oct · Salt Lake')];

  @override
  void initState() {
    super.initState();
    if (isLive) {
      _load();
    } else if (widget.startWithAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addLeave());
    }
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.get('/api/doctor/time-off');
      if (!mounted) return;
      setState(() {
        _data = (r as Map).cast<String, dynamic>();
        _error = null;
      });
      if (widget.startWithAdd && !_openedAdd) {
        _openedAdd = true;
        _addLeave();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _openedAdd = false;

  List<(String, String)> get _locations => [
    for (final l in _data?.list('locations') ?? const <Map<String, dynamic>>[]) (l.str('id'), l.str('name')),
  ];

  bool get _canAddHoliday => !isLive || _data?['canAddHoliday'] == true;

  String _where(Map<String, dynamic> x) => x.str('locationName').isEmpty ? (x['locationId'] == null ? 'all locations' : 'one location') : x.str('locationName');

  String _dates(Map<String, dynamic> x) {
    final s = F.date(x['startDate']) ?? DateTime.now();
    return d4DateRange(s, F.date(x['endDate']) ?? s);
  }

  Future<void> _addLeave() async {
    final r = await pickTimeOff(context, holiday: false, locations: isLive ? _locations : const [('', 'Salt Lake'), ('', 'New Town')]);
    if (r == null || !mounted) return;
    if (!isLive) {
      setState(() => _sampleLeave.add((r['reason'] ?? 'Leave', 'all locations')));
      return;
    }
    final res = await runAction(context, () => Api.I.post('/api/doctor/leaves', r), busy: _busy);
    if (res is! Map || !mounted) return;
    final told = (res['patientsTold'] as num?)?.toInt() ?? 0;
    toast(context, told == 0 ? 'Leave added' : 'Leave added · ${told == 1 ? '1 patient told' : '$told patients told'}');
    _load();
  }

  Future<void> _addHoliday() async {
    final locs = isLive ? _locations : const [('', 'Salt Lake'), ('', 'New Town')];
    if (locs.isEmpty) return toast(context, 'You don’t practise at any location yet.');
    final r = await pickTimeOff(context, holiday: true, locations: locs, locationId: locs.first.$1);
    if (r == null || !mounted) return;
    if (!isLive) {
      setState(() => _sampleHolidays.add((r['reason'] ?? 'Closed all day', locs.first.$2)));
      return;
    }
    final id = r['locationId'];
    final res = await runAction(
      context,
      () => Api.I.post('/api/locations/$id/closures', {'reason': r['reason'], 'startDate': r['startDate'], 'endDate': r['endDate']}),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    final told = (res['patientsTold'] as num?)?.toInt() ?? 0;
    toast(context, told == 0 ? 'Clinic holiday added' : 'Clinic holiday added · ${told == 1 ? '1 patient told' : '$told patients told'}');
    _load();
  }

  Future<void> _cancelLeave(Map<String, dynamic> l) async {
    final ok = await d4Confirm(context, title: 'Cancel ${l.str('reason', 'leave')}?', body: 'Bookings open again for these dates.', confirm: 'Cancel leave');
    if (!ok || !mounted) return;
    final r = await runAction(context, () => Api.I.delete('/api/doctor/leaves/${l.str('id')}'), busy: _busy);
    if (r == null || !mounted) return;
    toast(context, 'Leave cancelled');
    _load();
  }

  Future<void> _removeHoliday(Map<String, dynamic> h) async {
    final ok = await d4Confirm(
      context,
      title: 'Remove ${h.str('reason', 'this holiday')}?',
      body: 'The clinic opens for bookings again on these dates.',
      confirm: 'Remove holiday',
    );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => Api.I.delete('/api/locations/${h.str('locationId')}/closures/${h.str('id')}'), busy: _busy);
    if (r == null || !mounted) return;
    toast(context, 'Holiday removed');
    _load();
  }

  Widget _row(String title, String detail, {Widget? pill, VoidCallback? onRemove, String? removeLabel}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(child: D4TitleSub(title, detail)),
        if (pill != null) ...[const SizedBox(width: 12), pill],
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          MpIconButton(I.close, label: removeLabel ?? 'Remove', color: MP.ink2, iconSize: 18, size: 40, onTap: onRemove),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final live = isLive;
    final leaves = live ? _data?.list('leaves') ?? const <Map<String, dynamic>>[] : const <Map<String, dynamic>>[];
    final holidays = live ? _data?.list('holidays') ?? const <Map<String, dynamic>>[] : const <Map<String, dynamic>>[];
    final Widget body;
    if (live && _data == null) {
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
    } else {
      body = VGap(
        gap: 20,
        children: [
          D11Group('Your leave', [
            if (live)
              for (final l in leaves)
                _row(
                  l.str('reason', 'Leave'),
                  [_dates(l), _where(l), timeOffPatients(l.numOr('affectedPatients').toInt())].join(' · '),
                  pill: l['status'] == 'active' ? const D4Pill.green('On leave') : const D4Pill.blue('Planned'),
                  onRemove: () => _cancelLeave(l),
                  removeLabel: 'Cancel leave',
                )
            else
              for (final (n, d) in _sampleLeave) _row(n, d, pill: const D4Pill.blue('Planned')),
            if (live && leaves.isEmpty) _row('No leave planned', 'Add the days you’re away. Patients who booked are told.'),
            D11Row('Add leave', trailing: const Ico(I.plus, size: 18, color: MP.primary, stroke: 2), onTap: _addLeave),
          ]),
          D11Group('Clinic holidays', [
            if (live)
              for (final h in holidays)
                _row(
                  h.str('reason', 'Closed all day'),
                  [_dates(h), _where(h), timeOffPatients(h.numOr('affectedPatients').toInt())].join(' · '),
                  pill: h['status'] == 'active' ? const D4Pill.amber('Closed') : null,
                  onRemove: _canAddHoliday ? () => _removeHoliday(h) : null,
                  removeLabel: 'Remove holiday',
                )
            else
              for (final (n, d) in _sampleHolidays) _row(n, d),
            if (live && holidays.isEmpty) _row('No clinic holidays coming up', 'The whole clinic is closed on a holiday, for every doctor.'),
            if (_canAddHoliday)
              D11Row('Add clinic holiday', trailing: const Ico(I.plus, size: 18, color: MP.primary, stroke: 2), onTap: _addHoliday)
            else
              _row('Clinic holidays are set by the owner', 'Ask them to add a day the clinic is closed.'),
          ]),
          const D4Note('Online booking closes on these days. Patients already booked are told on WhatsApp and in the app, and your front desk sees the visits to move.'),
        ],
      );
    }
    return MpSheet(title: 'Leave and holidays', showClose: true, child: body);
  }
}

/// Reason, first and last day, and where (all locations / one location).
class _TimeOffForm extends StatefulWidget {
  final bool holiday;
  final List<(String, String)> locations;
  final String? locationId;
  const _TimeOffForm({required this.holiday, required this.locations, this.locationId});

  @override
  State<_TimeOffForm> createState() => _TimeOffFormState();
}

class _TimeOffFormState extends State<_TimeOffForm> {
  final _reason = TextEditingController();
  late DateTime _from = _today;
  late DateTime _to = _today;
  late String? _where = widget.locationId ?? (widget.holiday && widget.locations.isNotEmpty ? widget.locations.first.$1 : null);

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool first) async {
    final d = await showDatePicker(
      context: context,
      initialDate: first ? _from : (_to.isBefore(_from) ? _from : _to),
      firstDate: first ? _today : _from,
      lastDate: DateTime(_today.year + 2, 12, 31),
      helpText: first ? (widget.holiday ? 'Closed from' : 'Leave from') : (widget.holiday ? 'Closed until' : 'Leave until'),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (first) {
        _from = d;
        if (_to.isBefore(d)) _to = d;
      } else {
        _to = d;
      }
    });
  }

  void _done() {
    final reason = _reason.text.trim();
    if (!widget.holiday && reason.isEmpty) return toast(context, 'Enter a reason');
    if (widget.holiday && (_where ?? '').isEmpty && widget.locations.isNotEmpty) return toast(context, 'Choose the location');
    Navigator.pop(context, <String, String?>{
      'reason': reason.isEmpty ? 'Closed all day' : reason,
      'startDate': _ymd(_from),
      'endDate': _ymd(_to),
      'locationId': (_where ?? '').isEmpty ? null : _where,
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _to.difference(_from).inDays + 1;
    return MpSheet(
      title: widget.holiday ? 'Add clinic holiday' : 'Add leave',
      subtitle: widget.holiday ? 'The clinic is closed for every doctor' : 'Online booking closes for these days',
      showClose: true,
      child: VGap(
        gap: 16,
        children: [
          MpInput(
            label: 'Reason',
            hint: widget.holiday ? 'e.g. Durga Puja' : 'e.g. Medical conference',
            controller: _reason,
            autofocus: true,
          ),
          D11Group('Dates', [
            D11Row('From', value: F.dayMonth(_from), onTap: () => _pick(true)),
            D11Row('Until', value: F.dayMonth(_to), sub: days == 1 ? '1 day' : '$days days', onTap: () => _pick(false)),
          ]),
          if (widget.locations.length > 1 || !widget.holiday)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Where', style: tx(13, w: w600, c: MP.ink2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!widget.holiday)
                      D4OptionCard(
                        title: 'All locations',
                        sub: 'Every clinic you practise at',
                        selected: _where == null,
                        titleSize: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        onTap: () => setState(() => _where = null),
                      ),
                    for (final (id, name) in widget.locations)
                      D4OptionCard(
                        title: name,
                        sub: widget.holiday ? 'Closed all day' : 'Only here',
                        selected: _where == id && id.isNotEmpty,
                        titleSize: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        onTap: () => setState(() => _where = id),
                      ),
                  ],
                ),
              ],
            ),
          MpButton(widget.holiday ? 'Add clinic holiday' : 'Add leave', onTap: _done),
        ],
      ),
    );
  }
}

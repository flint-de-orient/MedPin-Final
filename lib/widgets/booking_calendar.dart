import 'package:flutter/material.dart' hide Text;

import '../data/api.dart';
import '../data/live.dart';
import 'i18n.dart';
import 'mp.dart';

/// "YYYY-MM-DD" for a local day.
String bookingDayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One day of a doctor's diary at a place: open or why not, and free / all times.
class BookingDay {
  final DateTime date;
  final bool open;
  final String? reason; // no_session · doctor_on_leave · closed · clinic_closed · full · …
  final String? note; // the leave / closure reason ("Durga Puja")
  final int free;
  final int total;
  const BookingDay(this.date, {required this.open, this.reason, this.note, this.free = 0, this.total = 0});

  bool get bookable => open && free > 0;

  static BookingDay fromJson(Map<String, dynamic> j) {
    final d = DateTime.tryParse(j.str('date')) ?? DateTime.now();
    return BookingDay(
      DateTime(d.year, d.month, d.day),
      open: j['open'] == true,
      reason: j['reason'] as String?,
      note: j['note'] as String?,
      free: j.numOr('free').toInt(),
      total: j.numOr('total').toInt(),
    );
  }

  /// "Doctor on leave · Durga Puja", "Clinic closed", "Full", "No session".
  String why(BuildContext context) {
    final base = switch (reason) {
      'doctor_on_leave' => 'Doctor on leave',
      'closed' || 'clinic_closed' || 'location_inactive' => 'Clinic closed',
      'full' => 'Fully booked',
      'beyond_booking_window' => 'Not open for booking yet',
      _ => 'No session',
    };
    final n = note ?? '';
    return n.isEmpty ? tr(context, base) : '${tr(context, base)} · $n';
  }
}

/// The days a doctor sees patients at a place from [from] for [days] days
/// (GET /api/appointments/booking/days; an older server: each day's slots).
/// Returns the days and the last day open for booking.
Future<(List<BookingDay>, DateTime?)> loadBookingDays({
  required String doctorId,
  required String locationId,
  required DateTime from,
  int days = 14,
  DateTime? until,
}) async {
  try {
    final r = (await Api.I.get('/api/appointments/booking/days', query: {
      'doctorId': doctorId,
      'locationId': locationId,
      'from': bookingDayKey(from),
      'days': '$days',
      if (until != null) 'until': bookingDayKey(until),
    }) as Map).cast<String, dynamic>();
    final last = DateTime.tryParse(r.str('lastDate'));
    return ([for (final d in r.list('days')) BookingDay.fromJson(d)], last == null ? null : DateTime(last.year, last.month, last.day));
  } on ApiException catch (e) {
    if (e.status != 404) rethrow;
  }
  // Older server: ask each day.
  final list = [for (var i = 0; i < days; i++) DateTime(from.year, from.month, from.day + i)];
  final res = await Future.wait([
    for (final d in list) Api.I.get('/api/doctors/$doctorId/slots', query: {'locationId': locationId, 'date': bookingDayKey(d)}),
  ]);
  return (
    [
      for (var i = 0; i < list.length; i++)
        () {
          final s = (res[i] as Map).cast<String, dynamic>();
          final slots = s.list('slots');
          final free = slots.where((x) => x['available'] == true).length;
          return BookingDay(list[i], open: s['open'] == true, reason: s['open'] == true ? (free > 0 ? null : 'full') : s['reason'] as String?, note: s['note'] as String?, free: free, total: slots.length);
        }(),
    ],
    null,
  );
}

/// "More dates": a month calendar of the days the doctor sees patients at this
/// place, up to the last day open for booking. Greyed: no session, leave, clinic
/// closed or fully booked (tap one to see why). [mark] is a day to point out
/// (the follow-up due date). Returns the chosen day.
Future<DateTime?> pickBookingDay(
  BuildContext context, {
  required String doctorId,
  required String locationId,
  DateTime? selected,
  DateTime? until,
  DateTime? mark,
  String? markLabel,
}) {
  return openSheet<DateTime>(
    context,
    (_) => _BookingCalendar(doctorId: doctorId, locationId: locationId, selected: selected, until: until, mark: mark, markLabel: markLabel),
  );
}

class _BookingCalendar extends StatefulWidget {
  final String doctorId;
  final String locationId;
  final DateTime? selected;
  final DateTime? until;
  final DateTime? mark;
  final String? markLabel;
  const _BookingCalendar({required this.doctorId, required this.locationId, this.selected, this.until, this.mark, this.markLabel});

  @override
  State<_BookingCalendar> createState() => _BookingCalendarState();
}

class _BookingCalendarState extends State<_BookingCalendar> {
  late final DateTime _today = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();
  late DateTime _month = DateTime((widget.selected ?? _today).year, (widget.selected ?? _today).month);
  final Map<String, BookingDay> _days = {};
  DateTime? _last;
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final first = _month.isBefore(DateTime(_today.year, _today.month)) ? _today : (_month.month == _today.month && _month.year == _today.year ? _today : _month);
    final end = DateTime(_month.year, _month.month + 1, 0);
    final n = end.difference(first).inDays + 1;
    if (n <= 0) return;
    if (!isLive) {
      setState(() {
        for (var i = 0; i < n; i++) {
          final d = DateTime(first.year, first.month, first.day + i);
          final open = d.weekday != DateTime.sunday;
          _days[bookingDayKey(d)] = BookingDay(d, open: open, reason: open ? (d.day % 9 == 0 ? 'full' : null) : 'no_session', free: open && d.day % 9 != 0 ? 6 : 0, total: 12);
        }
        _last = DateTime(_today.year, _today.month, _today.day + 30);
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (days, last) = await loadBookingDays(doctorId: widget.doctorId, locationId: widget.locationId, from: first, days: n.clamp(1, 42), until: widget.until);
      if (!mounted) return;
      setState(() {
        for (final d in days) {
          _days[bookingDayKey(d.date)] = d;
        }
        _last = last ?? _last ?? (days.isEmpty ? null : days.last.date);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canBack => DateTime(_month.year, _month.month).isAfter(DateTime(_today.year, _today.month));
  bool get _canNext => _last == null || DateTime(_month.year, _month.month + 1).isBefore(DateTime(_last!.year, _last!.month + 1));

  void _shift(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _info = null;
    });
    _load();
  }

  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month);
    final lead = first.weekday - 1;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= count; d++) _cell(DateTime(_month.year, _month.month, d)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    return MpSheet(
      title: 'Choose a date',
      subtitle: 'Days the doctor sees patients here',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MpIconButton(I.chevronLeft, label: 'Previous month', color: _canBack ? MP.ink : MP.lineStrong, onTap: _canBack ? () => _shift(-1) : null),
                Expanded(
                  child: Text('${tr(context, _months[_month.month - 1])} ${_month.year}', textAlign: TextAlign.center, style: tx(16, w: w700)),
                ),
                MpIconButton(I.chevronRight, label: 'Next month', color: _canNext ? MP.ink : MP.lineStrong, onTap: _canNext ? () => _shift(1) : null),
              ],
            ),
            const Gap(8),
            Row(
              children: [
                for (final w in _wd)
                  Expanded(child: Text(w, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: tx(12, w: w600, c: MP.ink3))),
              ],
            ),
            const Gap(6),
            for (var r = 0; r < cells.length; r += 7)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [for (final c in cells.sublist(r, r + 7)) Expanded(child: c)]),
              ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator(minHeight: 2, color: MP.primary, backgroundColor: MP.fill)),
            if (_error != null) ...[const Gap(8), Text(_error!, style: tx(13, c: MP.red))],
            const Gap(10),
            Text(_info ?? 'Grey days: no session, doctor on leave, clinic closed or fully booked.', style: tx(13, c: _info == null ? MP.ink3 : MP.ink2, h: 1.4)),
            if (widget.mark != null && widget.markLabel != null) ...[
              const Gap(6),
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: MP.amber, shape: BoxShape.circle)),
                  const Gap(8),
                  Expanded(child: Text(widget.markLabel!, style: tx(13, c: MP.ink2))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(DateTime d) {
    final key = bookingDayKey(d);
    final day = _days[key];
    final past = d.isBefore(_today);
    final beyond = _last != null && d.isAfter(_last!);
    final on = widget.selected != null && bookingDayKey(widget.selected!) == key;
    final ok = !past && !beyond && (day?.bookable ?? false);
    final marked = widget.mark != null && bookingDayKey(widget.mark!) == key;
    final fg = on ? MP.white : ok ? MP.ink : MP.lineStrong;
    final label = '${d.day}';
    return Semantics(
      button: true,
      enabled: ok,
      selected: on,
      label: ok ? label : '$label, ${day == null ? tr(context, 'not open') : day.why(context)}',
      excludeSemantics: true,
      child: Tap(
        onTap: past || beyond || day == null
            ? null
            : ok
                ? () => Navigator.pop(context, d)
                : () => setState(() => _info = '${d.day} ${tr(context, _months[d.month - 1])}: ${day.why(context)}'),
        radius: 10,
        color: on ? MP.primary : (ok ? MP.white : Colors.transparent),
        border: on ? MP.primary : (ok ? MP.line : null),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                style: tx(15, w: ok || on ? w600 : w500, c: fg, tab: true, deco: day?.reason == 'full' && !past ? TextDecoration.lineThrough : null),
              ),
              if (marked)
                Positioned(
                  bottom: 5,
                  child: Container(width: 5, height: 5, decoration: BoxDecoration(color: on ? MP.white : MP.amber, shape: BoxShape.circle)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

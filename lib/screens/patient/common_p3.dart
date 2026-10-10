import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/downloads.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch P3 (patient app live data: records, medicines, cart,
// pharmacy). Visuals reuse the P2 components so the design stays the same.

// ─────────────────────────────────────────────────────────────────────────────
// Change signals
// ─────────────────────────────────────────────────────────────────────────────

/// Bumped when a record is added, split, shared or deleted, so Patient-Records
/// refreshes even when the upload started from another screen.
final p3RecordsChanged = ValueNotifier<int>(0);

/// Bumped when the cart or an order changes (Med-AddToCart, Med-Cart,
/// Med-Pharmacy), so Patient-Medicines refreshes its cart badge and buttons.
final p3CartChanged = ValueNotifier<int>(0);

/// Runs [onChange] whenever [signal] fires while the screen is live.
mixin P3Listen<W extends StatefulWidget> on State<W> {
  final _subs = <(Listenable, VoidCallback)>[];

  void p3Listen(Listenable signal, VoidCallback onChange) {
    if (!isLive) return;
    signal.addListener(onChange);
    _subs.add((signal, onChange));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.$1.removeListener(s.$2);
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formatting
// ─────────────────────────────────────────────────────────────────────────────

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "September 2026"
String p3Month(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year}';

/// "30 Sep 2026"
String p3Date(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';

/// "Friday"
String p3Weekday(DateTime d) => _weekdaysLong[d.weekday - 1];

/// API weekday key ('sun') → "Sunday".
String p3WeekdayKey(String? k) {
  const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final i = keys.indexOf(k ?? '');
  return i < 0 ? '' : _weekdaysLong[i];
}

/// Reads "30 Sep 2026", "30/09/2026" or "2026-09-30". Null when it isn't a date.
DateTime? p3ParseDate(String text) {
  final t = text.trim();
  final iso = DateTime.tryParse(t);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final m = RegExp(r'^(\d{1,2})[\s/.-]+([A-Za-z]+|\d{1,2})[\s/.-]+(\d{4})$').firstMatch(t);
  if (m == null) return null;
  final day = int.parse(m[1]!);
  final mon = m[2]!;
  final month = int.tryParse(mon) ?? (_monthsShort.indexWhere((x) => mon.toLowerCase().startsWith(x.toLowerCase())) + 1);
  final year = int.parse(m[3]!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// "2026-09-30" for the API.
String p3Iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// ₹1,380
String p3Rupees(num v) => '₹${F.count(v)}';

/// "after food", "at bedtime" (null when unknown).
String? p3Food(String? relation) => const {
      'before_food': 'before food',
      'after_food': 'after food',
      'with_food': 'with food',
      'empty_stomach': 'empty stomach',
      'bedtime': 'at bedtime',
    }[relation];

/// Meal words for a dose slot: "Before breakfast", "after dinner".
String? p3SlotFood(String slot, String? relation) {
  final meal = const {'morning': 'breakfast', 'afternoon': 'lunch', 'night': 'dinner'}[slot] ?? 'food';
  return switch (relation) {
    'before_food' => 'before $meal',
    'after_food' => 'after $meal',
    'with_food' => 'with $meal',
    'empty_stomach' => 'empty stomach',
    'bedtime' => 'at bedtime',
    _ => null,
  };
}

String p3Cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "07:30" → "7:30 AM"
String p3Clock(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first) ?? 0;
  final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return F.time(DateTime(2026, 1, 1, h, m));
}

/// "Metformin 500 mg"
String p3MedName(Map<String, dynamic> m) => [m.str('name'), m.str('strength')].where((s) => s.isNotEmpty).join(' ');

/// Opens a file the API signed (report, prescription, PDF).
Future<void> p3Open(BuildContext context, String? url, {String what = 'the file'}) async {
  if (url == null || url.isEmpty) {
    toast(context, 'There is no file to open');
    return;
  }
  if (Downloads.isFile(url)) {
    await Downloads.open(context, url);
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) toast(context, "Couldn't open $what");
}

// ─────────────────────────────────────────────────────────────────────────────
// "Share with" doctors (Records-Add, Records-Review, record sheet)
// ─────────────────────────────────────────────────────────────────────────────

class P3Doctor {
  final String id;
  final String name;
  final String sub;
  final bool suggested;
  const P3Doctor(this.id, this.name, this.sub, {this.suggested = false});
}

/// The patient's care team for the picker (GET /api/patient/my-doctors). A
/// doctor with a visit in the next week is suggested.
List<P3Doctor> p3DoctorsFrom(List<Map<String, dynamic>> rows, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final out = <P3Doctor>[];
  for (final d in rows) {
    final next = F.date(d.obj('nextVisit')['startAt']);
    final soon = next != null && next.isAfter(n.subtract(const Duration(hours: 2))) && next.difference(n).inDays < 7;
    final role = d.str('role');
    final about = [d.str('headline', role == 'doctor' ? '' : p3Cap(role)), d.str('clinic')].where((s) => s.isNotEmpty).join(' · ');
    out.add(P3Doctor(
      d.str('doctorId'),
      d.str('name'),
      soon ? 'Suggested · visit ${F.when(next, now: n).replaceFirst('Today', 'today').replaceFirst('Tomorrow', 'tomorrow')}' : about,
      suggested: soon,
    ));
  }
  out.sort((a, b) => (b.suggested ? 1 : 0) - (a.suggested ? 1 : 0));
  return out;
}

Future<List<P3Doctor>> p3LoadDoctors() async {
  final res = await Api.I.get('/api/patient/my-doctors');
  return p3DoctorsFrom([for (final x in (res as List? ?? const [])) (x as Map).cast<String, dynamic>()]);
}

/// [P2ShareDoctors] with the selection held by the caller, and a working
/// "Share with another doctor" search.
class P3ShareDoctors extends StatelessWidget {
  final String title;
  final List<P3Doctor> doctors;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// A doctor found with "Share with another doctor" (added to [doctors] by the caller).
  final ValueChanged<P3Doctor> onAdd;
  const P3ShareDoctors({
    super.key,
    required this.title,
    required this.doctors,
    required this.selected,
    required this.onChanged,
    required this.onAdd,
  });

  void _toggle(String id) => onChanged(selected.contains(id) ? ({...selected}..remove(id)) : {...selected, id});

  Future<void> _another(BuildContext context) async {
    final d = await openSheet<P3Doctor>(context, (_) => const _FindDoctorSheet());
    if (d != null) onAdd(d);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: tx(14, w: w600))),
              Text('Pick any doctors', style: tx(13, c: MP.ink3)),
            ],
          ),
        ),
        for (var i = 0; i < doctors.length; i++)
          P2Box(
            onTap: () => _toggle(doctors[i].id),
            label: doctors[i].name,
            topBorder: i == 0 ? null : const BorderSide(color: MP.line),
            minHeight: i == 0 ? 56 : 57,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                MpCheck(value: selected.contains(doctors[i].id), onChanged: (_) => _toggle(doctors[i].id)),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(doctors[i].name, style: tx(15, w: w600)),
                      if (doctors[i].sub.isNotEmpty) ...[
                        const Gap(1),
                        Text(doctors[i].sub, style: tx(13, c: doctors[i].suggested ? MP.primary : MP.ink2)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        P2Box(
          onTap: () => _another(context),
          topBorder: doctors.isEmpty ? null : const BorderSide(color: MP.line),
          minHeight: 53,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Ico(I.search, size: 20, color: MP.primary),
              const Gap(12),
              Flexible(child: Text('Share with another doctor', style: tx(15, w: w600, c: MP.primary))),
            ],
          ),
        ),
      ],
    );
  }
}

/// Search any MedPin doctor (GET /api/patient/doctors/search) and pick one.
class _FindDoctorSheet extends StatefulWidget {
  const _FindDoctorSheet();

  @override
  State<_FindDoctorSheet> createState() => _FindDoctorSheetState();
}

class _FindDoctorSheetState extends State<_FindDoctorSheet> {
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    final res = await runAction(context, () => Api.I.get('/api/patient/doctors/search', query: {'q': q.trim()}));
    if (!mounted || res is! Map) return;
    setState(() {
      _searched = true;
      _results = res.cast<String, dynamic>().list('items');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Share with another doctor',
      subtitle: 'Search by name or speciality',
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          P2Field(hint: 'Doctor name or speciality', icon: I.search, padLeft: 46, action: TextInputAction.search, onChanged: _onChanged, onSubmitted: _search),
          const Gap(8),
          if (_searched && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No doctors found', textAlign: TextAlign.center, style: tx(14, c: MP.ink2)),
            ),
          for (var i = 0; i < _results.length; i++)
            P2Box(
              onTap: () {
                final d = _results[i];
                final about = [d.str('headline'), d.str('clinic')].where((s) => s.isNotEmpty).join(' · ');
                Navigator.of(context).pop(P3Doctor(d.str('doctorId'), d.str('name'), about));
              },
              label: _results[i].str('name'),
              topBorder: i == 0 ? null : const BorderSide(color: MP.line),
              minHeight: 57,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_results[i].str('name'), style: tx(15, w: w600)),
                  const Gap(1),
                  Text(
                    [_results[i].str('headline'), _results[i].str('clinic')].where((s) => s.isNotEmpty).join(' · '),
                    style: tx(13, c: MP.ink2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small sheet rows
// ─────────────────────────────────────────────────────────────────────────────

/// A label / value line inside a sheet (hairline above all but the first).
class P3Row extends StatelessWidget {
  final String title;
  final String sub;
  final Widget? trailing;
  final bool first;
  final VoidCallback? onTap;
  const P3Row(this.title, this.sub, {super.key, this.trailing, this.first = false, this.onTap});

  @override
  Widget build(BuildContext context) => P2Box(
        onTap: onTap,
        label: title,
        topBorder: first ? null : const BorderSide(color: MP.line),
        minHeight: first ? 60 : 61,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: tx(15, w: w600)),
                  if (sub.isNotEmpty) ...[const Gap(2), Text(sub, style: tx(13, c: MP.ink2))],
                ],
              ),
            ),
            if (trailing != null) ...[const Gap(12), trailing!],
          ],
        ),
      );
}

/// "Delete this record?" confirmation sheet. True when confirmed.
Future<bool> p3Confirm(BuildContext context, {required String title, required String body, required String confirm}) async {
  final ok = await openSheet<bool>(
    context,
    (c) => MpSheet(
      title: title,
      subtitle: body,
      child: VGap(
        gap: 8,
        children: [
          MpButton(confirm, kind: MpBtn.danger, onTap: () => Navigator.pop(c, true)),
          MpButton('Cancel', kind: MpBtn.secondary, onTap: () => Navigator.pop(c, false)),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Small grey note line used for empty sheets.
class P3Empty extends StatelessWidget {
  final String text;
  const P3Empty(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text, textAlign: TextAlign.center, style: tx(14, c: MP.ink2)),
      );
}

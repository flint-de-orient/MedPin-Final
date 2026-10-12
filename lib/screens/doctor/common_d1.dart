import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D1: AI Assistant composer, status pill, option
// picker sheet and the doctor's consulting locations.

/// Status pill: 22px high, padding 0 8, radius 999, 12px / 700.
class D1Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double height;
  final double fontSize;
  final double padding;
  final double em;
  const D1Pill(
    this.text, {
    super.key,
    required this.bg,
    required this.fg,
    this.height = 22,
    this.fontSize = 12,
    this.padding = 8,
    this.em = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: padding),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(text, maxLines: 1, softWrap: false, style: tx(fontSize, w: w700, c: fg, em: em))],
      ),
    );
  }
}

/// Bottom sheet with a list of options (52px rows, check on the current one).
/// Resolves to the picked option, or null when dismissed.
class D1Picker {
  D1Picker._();

  static Future<String?> show(
    BuildContext context, {
    String? title,
    required List<String> options,
    required String value,
  }) {
    return openSheet<String>(
      context,
      (c) => MpSheet(
        title: title,
        child: Column(
          children: [
            for (final o in options)
              Tap(
                onTap: () => Navigator.pop(c, o),
                radius: 12,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          o,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(16, w: o == value ? w600 : w400),
                        ),
                      ),
                      if (o == value) const Ico(I.check, size: 20, color: MP.primary, stroke: 2.25),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A place the doctor consults at (Queue-Select options, Queue-List header).
class D1Location {
  final String name;

  /// Spoken form of [name] (commas instead of the middle dot).
  final String a11y;

  /// Second line in the location picker, e.g. 'Clinic · 9:00 AM – 1:00 PM'.
  final String kind;

  /// Second line in the queue header, e.g. 'Today 9:00 AM – 1:00 PM'.
  final String hours;
  final String? badge;
  final Color badgeBg;
  final Color badgeFg;
  final String? booked;
  final String? waiting;

  /// Set when the location is closed today (option is disabled).
  final String? note;

  /// API id of the location (live data only).
  final String? id;

  const D1Location({
    this.id,
    required this.name,
    required this.a11y,
    required this.kind,
    required this.hours,
    this.badge,
    this.badgeBg = MP.fill,
    this.badgeFg = MP.ink2,
    this.booked,
    this.waiting,
    this.note,
  });

  bool get closed => note != null;

  /// A Queue-Select card from GET /api/queue/locations.
  factory D1Location.fromApi(Map<String, dynamic> m) {
    final name = m.str('name');
    final type = d1LocationType(m.str('type'));
    final hours = d1Hours(m.list('sessions'));
    final booked = m.numOr('booked').toInt();
    final waiting = m.numOr('waiting').toInt();
    final open = m['closedReason'] == null;
    String badge;
    var bg = MP.fill;
    var fg = MP.ink2;
    if (m['openNow'] == true) {
      badge = 'Open now';
      bg = MP.greenSoft;
      fg = MP.green;
    } else if (m['opensAt'] is num) {
      badge = 'Opens ${d1Minutes((m['opensAt'] as num).toInt())}';
    } else {
      badge = 'Closed now';
    }
    String? note;
    if (!open) {
      final next = F.date(m['nextSession']);
      final why = switch (m.str('closedReason')) {
        'doctor_on_leave' => 'On leave today',
        'location_inactive' => 'Not open',
        _ => 'Closed today',
      };
      note = next == null ? why : '$why · next session ${d1Day(next)}';
    }
    return D1Location(
      id: m.str('locationId'),
      name: name,
      a11y: name.replaceAll(' · ', ', ').replaceAll(' — ', ', '),
      kind: hours.isEmpty ? type : '$type · $hours',
      hours: hours.isEmpty ? 'Closed today' : 'Today $hours',
      badge: badge,
      badgeBg: bg,
      badgeFg: fg,
      booked: '$booked booked',
      waiting: waiting > 0 ? '$waiting waiting' : null,
      note: note,
    );
  }

  static const all = [
    D1Location(
      name: 'City Care Clinic · Salt Lake',
      a11y: 'City Care Clinic, Salt Lake',
      kind: 'Clinic · 9:00 AM – 1:00 PM',
      hours: 'Today 9:00 AM – 1:00 PM',
      badge: 'Open now',
      badgeBg: MP.greenSoft,
      badgeFg: MP.green,
      booked: '12 booked',
      waiting: '3 waiting',
    ),
    D1Location(
      name: 'City Care · New Town',
      a11y: 'City Care, New Town',
      kind: 'Clinic · 5:00 PM – 8:00 PM',
      hours: 'Today 5:00 PM – 8:00 PM',
      badge: 'Opens 5:00 PM',
      booked: '6 booked',
    ),
    D1Location(
      name: 'Sen Diabetes Chamber · Gariahat',
      a11y: 'Sen Diabetes Chamber, Gariahat',
      kind: 'Chamber · Thu and Sat only',
      hours: 'Thu and Sat only',
      note: 'Closed today · next session Thu, 1 Oct',
    ),
  ];
}

/// AI Assistant composer bar (Doctor-AI, Doctor-AI-Chat): white bar with a
/// top border, a 56px pill input (1px #D5DBE5; 1.5px #003399 while focused or
/// filled) with a 40px send button, a 56px mic button and an optional caption.
class D1Composer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hint;
  final String? caption;

  /// Screen-reader label of the input.
  final String label;

  /// Filled blue mic (landing) instead of the white outlined one (chat).
  final bool micPrimary;
  final ValueChanged<String> onSend;
  final VoidCallback onMic;
  const D1Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onMic,
    this.hint,
    this.caption,
    this.label = 'Ask the AI Assistant',
    this.micPrimary = true,
  });

  @override
  State<D1Composer> createState() => _D1ComposerState();
}

class _D1ComposerState extends State<D1Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(D1Composer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _send() {
    final t = widget.controller.text.trim();
    if (t.isNotEmpty) widget.onSend(t);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final canSend = text.trim().isNotEmpty;
    final active = canSend || widget.focusNode.hasFocus;
    final mic = widget.micPrimary;
    return MpBottomBar(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  // The field inside is what screen readers focus.
                  excludeFromSemantics: true,
                  onTap: widget.focusNode.requestFocus,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
                    decoration: BoxDecoration(
                      color: MP.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: active ? MP.primary : MP.lineStrong, width: active ? 1.5 : 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              // Placeholder, clipped like a browser input (no ellipsis).
                              if (widget.hint != null && text.isEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        widget.hint!,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.clip,
                                        style: tx(15, c: MP.ink3),
                                      ),
                                    ),
                                  ),
                                ),
                              Semantics(
                                label: widget.label,
                                child: MpFieldArea(child: TextField(
                                  textAlignVertical: TextAlignVertical.center,
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  style: tx(15),
                                  cursorColor: MP.primary,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                                )),
                              ),
                            ],
                          ),
                        ),
                        const Gap(8),
                        MpHitSlop(child: Semantics(
                          button: true,
                          enabled: canSend,
                          label: 'Send',
                          child: GestureDetector(
                            onTap: canSend ? _send : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: canSend ? MP.primary : MP.fill, shape: BoxShape.circle),
                              child: Ico(I.arrowUp, size: 18, color: canSend ? MP.white : MP.ink3, stroke: 2),
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Semantics(
                button: true,
                label: 'Speak your question',
                // 56×56 border-box button: the size wraps the Tap.
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Tap(
                    onTap: widget.onMic,
                    radius: 999,
                    color: mic ? MP.primary : MP.white,
                    border: mic ? null : MP.lineStrong,
                    shadow: mic ? MPShadow.button : null,
                    child: Center(child: Ico(I.mic, size: 22, color: mic ? MP.white : MP.primary)),
                  ),
                ),
              ),
            ],
          ),
          if (widget.caption != null) ...[
            const Gap(10),
            Text(widget.caption!, textAlign: TextAlign.center, style: tx(12, c: MP.ink3)),
          ],
        ],
      ),
    );
  }
}

// ── Live helpers (batch D1) ──

/// 540 → "9:00 AM" (minutes after midnight).
String d1Minutes(int min) => F.time(DateTime(2000, 1, 1, min ~/ 60, min % 60));

/// Sessions [{startMin, endMin}] → "9:00 AM – 1:00 PM, 5:00 PM – 8:00 PM".
String d1Hours(List<Map<String, dynamic>> sessions) => sessions
    .map((s) => '${d1Minutes(s.numOr('startMin').toInt())} – ${d1Minutes(s.numOr('endMin').toInt())}')
    .join(', ');

/// "Thu, 1 Oct"
String d1Day(DateTime d) {
  final s = F.dateLong(d);
  return s.substring(0, s.lastIndexOf(' '));
}

/// "Today, 8:42 AM", "Yesterday", "28 Sep" — recent-list times.
String d1Recent(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (F.sameDay(d, n)) return 'Today, ${F.time(d)}';
  if (F.sameDay(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return F.dayMonth(d);
}

String d1LocationType(String t) => switch (t) {
  'clinic' => 'Clinic',
  'chamber' => 'Chamber',
  'hospital' => 'Hospital',
  'nursing_home' => 'Nursing home',
  'diagnostic_centre' => 'Diagnostic centre',
  'video' => 'Video',
  _ => t.isEmpty ? 'Clinic' : '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}',
};

/// "45 M", "29 F" (empty when unknown).
String d1AgeSex(Map<String, dynamic> p) {
  final age = p['age'] is num ? '${(p['age'] as num).toInt()}' : '';
  final g = switch (p.str('gender')) {
    'male' => 'M',
    'female' => 'F',
    'other' => 'O',
    _ => '',
  };
  return [age, g].where((x) => x.isNotEmpty).join(' ');
}

/// "9876543210" → "+91 98765 43210"; other numbers unchanged.
String d1Phone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  final ten = d.length == 12 && d.startsWith('91') ? d.substring(2) : d;
  if (ten.length != 10) return phone;
  return '+91 ${ten.substring(0, 5)} ${ten.substring(5)}';
}

/// The signed-in user's id.
String get d1MyId => Session.I.user.str('id');

/// The AI's Markdown answer as plain text: no ** / __ / # markers, bullets as •.
String d1PlainText(String md) {
  final lines = <String>[];
  for (var line in md.replaceAll('\r', '').split('\n')) {
    line = line.trimRight();
    if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) continue;
    line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '');
    line = line.replaceFirstMapped(RegExp(r'^(\s*)[*\-+]\s+'), (m) => '${m[1]}• ');
    line = line.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*|__(.+?)__'), (m) => m[1] ?? m[2] ?? '');
    line = line.replaceAllMapped(RegExp(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])'), (m) => m[1] ?? '');
    line = line.replaceAll('`', '');
    lines.add(line);
  }
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Queue-Select cards: GET /api/queue/locations. If that endpoint fails on
/// the server, the same cards are built from the doctor's weekly schedule
/// (GET /api/doctor/locations) and each location's queue (GET /api/queue).
Future<Map<String, dynamic>> d1QueueLocations() async {
  try {
    return ((await Api.I.get('/api/queue/locations')) as Map).cast<String, dynamic>();
  } on ApiException catch (e) {
    if (e.status < 500) rethrow;
  }
  const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  List<Map<String, dynamic>> sessionsOn(Map<String, dynamic> dl, DateTime d) {
    for (final w in dl.obj('schedule').list('week')) {
      if (w['weekday'] == days[d.weekday - 1]) return w.list('sessions');
    }
    return const [];
  }

  final dls = <Map<String, dynamic>>[
    for (final x in (await Api.I.get('/api/doctor/locations')) as List? ?? const [])
      if ((x as Map)['status'] == 'active' && x['locationId'] is Map) x.cast<String, dynamic>(),
  ];
  final queues = await Future.wait([
    for (final dl in dls) Api.I.get('/api/queue', query: {'locationId': dl.obj('locationId').str('id')}),
  ]);
  final now = DateTime.now();
  final nowMin = now.hour * 60 + now.minute;
  final items = <Map<String, dynamic>>[];
  for (var i = 0; i < dls.length; i++) {
    final dl = dls[i];
    final loc = dl.obj('locationId');
    final sessions = sessionsOn(dl, now);
    final open = sessions.isNotEmpty;
    String? next;
    if (!open) {
      for (var k = 1; k <= 14 && next == null; k++) {
        final day = DateTime(now.year, now.month, now.day + k);
        final s = sessionsOn(dl, day);
        if (s.isNotEmpty) {
          final m = s.first.numOr('startMin').toInt();
          next = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60).toUtc().toIso8601String();
        }
      }
    }
    final stats = ((queues[i] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{}).obj('stats');
    final starts = [for (final s in sessions) s.numOr('startMin').toInt()];
    items.add({
      'locationId': loc.str('id'),
      'name': loc.str('name'),
      'type': loc.str('type'),
      'sessions': sessions,
      'openNow': sessions.any((s) => nowMin >= s.numOr('startMin') && nowMin < s.numOr('endMin')),
      'opensAt': open ? starts.where((m) => m > nowMin).firstOrNull : null,
      'closedReason': open ? null : 'no_session',
      'nextSession': next,
      'booked': stats.numOr('all').toInt(),
      'waiting': stats.numOr('waiting').toInt(),
    });
  }
  return {'defaultLocationId': null, 'items': items};
}

/// The screen's [Nav.args] map. Safe to call first thing in
/// `LiveData.fetch()` (which starts during initState): it reads the route
/// once the State is set up.
Future<Map<String, dynamic>> d1Args(State s) async {
  await Future<void>.value();
  if (!s.mounted) return const {};
  final a = Nav.args<Map>(s.context);
  return a == null ? const {} : a.cast<String, dynamic>();
}

/// Opens the phone dialer for [phone] (toast when there is no number).
Future<void> d1Call(BuildContext context, String phone, String name) async {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) {
    toast(context, 'No phone number for $name');
    return;
  }
  bool ok;
  try {
    ok = await launchUrl(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) toast(context, "Couldn't start a call to $name");
}

/// "1 patient", "3 patients"
String d1Count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

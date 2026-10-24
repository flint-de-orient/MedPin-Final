/// Formatting used by live screens, matching the design's text
/// ("Thu, 1 Oct 2026", "8:30 AM", "Dr. Sen", "2 min ago").
class F {
  F._();

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// API timestamps (UTC ISO) → local time.
  static DateTime? date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  /// "Thu, 1 Oct 2026"
  static String dateLong(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "29 Sep"
  /// A dose count as printed on a prescription: 1, ½, 1½ (halves kept, never rounded away).
  static String dose(num n) {
    final whole = n.floor();
    final half = (n - whole) >= 0.5;
    if (!half) return '$whole';
    return whole == 0 ? '½' : '$whole½';
  }

  static String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// "8:30 AM"
  static String time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "8:30" (12-hour, no AM/PM — the front desk list)
  static String timeShort(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')}';
  }

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// "Today, 5:00 PM", "Tomorrow, 10:30 AM", "Sat, 10 Oct · 11:00 AM"
  static String when(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (sameDay(d, n)) return 'Today, ${time(d)}';
    if (sameDay(d, n.add(const Duration(days: 1)))) return 'Tomorrow, ${time(d)}';
    return '${_days[d.weekday - 1]}, ${dayMonth(d)} · ${time(d)}';
  }

  /// "8:20 AM", "yesterday", "28 Sep" — for "Asked …" lines.
  static String askedAt(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (sameDay(d, n)) return time(d);
    if (sameDay(d, n.subtract(const Duration(days: 1)))) return 'yesterday';
    return dayMonth(d);
  }

  /// "Just now", "2 min ago", "3 h ago", "Yesterday", "28 Sep"
  static String ago(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final s = n.difference(d).inSeconds;
    if (s < 60) return 'Just now';
    if (s < 3600) return '${s ~/ 60} min ago';
    if (sameDay(d, n)) return '${s ~/ 3600} h ago';
    if (sameDay(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
    return dayMonth(d);
  }

  /// "Good morning" / "Good afternoon" / "Good evening"
  static String greeting([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _stripTitle(String name) => name.replaceFirst(RegExp(r'^(Dr\.?)\s+', caseSensitive: false), '').trim();

  /// "Dr. Arjun Sen" → "AS"
  static String initials(String name) {
    final parts = _stripTitle(name).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  /// "Priya Sharma" → "Priya"; "Dr. Arjun Sen" → "Arjun"
  static String firstName(String name) {
    final parts = _stripTitle(name).split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.first;
  }

  /// "Dr. Arjun Sen" → "Dr. Sen" (others unchanged)
  static String doctorShort(String name) {
    if (!RegExp(r'^Dr\.?\s', caseSensitive: false).hasMatch(name)) return name;
    final parts = _stripTitle(name).split(RegExp(r'\s+'));
    return 'Dr. ${parts.last}';
  }

  /// 4820 → "4,820"
  static String count(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// "A and B", "A, B and C"
  static String joinAnd(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }
}

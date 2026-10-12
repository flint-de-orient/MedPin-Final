import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/photo.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../../widgets/i18n.dart';

// Shared pieces for batch D8: the clinician tabs (Doctor-Home, Care,
// Nutrition, Profile), Home-States and Practice.

/// Clinician-tab top bar (`padding: 12px 20px 0`): logo, 44px bell with a red
/// dot, 40px "AS" avatar that opens the Profile tab.
///
/// Live: the dot shows while GET /api/notifications?unread=true has unread
/// items ([unread] overrides it when the screen already knows the count) and
/// the avatar shows the signed-in user's initials.
class D8TabHeader extends StatefulWidget {
  final int? unread;
  const D8TabHeader({super.key, this.unread});

  @override
  State<D8TabHeader> createState() => _D8TabHeaderState();
}

class _D8TabHeaderState extends State<D8TabHeader> with LiveData {
  @override
  Future<Object?> fetch() =>
      // Always fetched: the urgent count decides the dot's colour.
      Api.I.get('/api/notifications', query: {'unread': true, 'limit': 1, if (Session.I.practiceId != null) 'practiceId': Session.I.practiceId});

  @override
  Widget build(BuildContext context) {
    final unread = !isLive ? 2 : (widget.unread ?? data?.numOr('unread').toInt() ?? 0);
    // Red only for an unread emergency (emergency alert, urgent chat); blue otherwise.
    final urgent = !isLive ? 1 : (data?.numOr('urgent').toInt() ?? 0);
    final initials = !isLive || Session.I.name.isEmpty ? 'AS' : F.initials(Session.I.name);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          const MpLogo(),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              MpIconButton(
                I.bell,
                label: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
                onTap: () async {
                  await Nav.go(context, 'Notifications');
                  if (mounted && isLive) reload(quiet: true);
                },
              ),
              if (unread > 0) Positioned(
                top: 10,
                right: 11,
                child: IgnorePointer(
                  // 8px dot + 2px #F7F9FC ring (CSS content-box → 12px outer).
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: urgent > 0 ? MP.red : MP.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: MP.bg, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Gap(4),
          MpHitSlop(child: Semantics(
            button: true,
            label: 'Profile',
            excludeSemantics: true,
            child: Tap(
              onTap: () => Nav.tab(context, 'Profile'),
              radius: 999,
              // The profile photo once there is one (it updates as soon as it changes).
              child: ListenableBuilder(
                listenable: Session.I,
                builder: (_, _) => MpAvatar(initials, size: 40, fontSize: 15, photo: isLive ? myPhotoUrl : null),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

/// 56px search input: 1px #D5DBE5 border, radius 16, magnifier at `left: 16px`,
/// text after `padding-left: 48px` (focus → #003399 border with the #EBF1FB
/// ring, like MpInput, whose leading icon sits 1px right and text 2px left).
class D8SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  const D8SearchField({super.key, required this.hint, this.onChanged});

  @override
  State<D8SearchField> createState() => _D8SearchFieldState();
}

class _D8SearchFieldState extends State<D8SearchField> {
  final _c = TextEditingController();
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _f.hasFocus;
    return GestureDetector(
      // The field inside is what screen readers focus.
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: _f.requestFocus,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? MP.primary : MP.lineStrong),
          boxShadow: focused ? MPShadow.focusRing : null,
        ),
        // The decoration's 1px border already insets this Row by 1px, so:
        // icon at 1 + 15 = 16px, text at 1 + 15 + 20 + 13 = 1 + 48px.
        child: Row(
          children: [
            const SizedBox(width: 15),
            const Ico(I.search, size: 20, color: MP.ink3),
            const SizedBox(width: 13),
            Expanded(
              child: MpFieldArea(child: TextField(
                textAlignVertical: TextAlignVertical.center,
                controller: _c,
                focusNode: _f,
                onChanged: widget.onChanged,
                textInputAction: TextInputAction.search,
                style: tx(16),
                cursorColor: MP.primary,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: tx(16, c: MP.ink3),
                ),
              )),
            ),
            const SizedBox(width: 16), // `padding-right: 16px`
          ],
        ),
      ),
    );
  }
}

/// Inline text link (14/600 #003399) with no forced height, as `<a>` renders
/// inside a flex row (MpLink is always a fixed-height box). Pass [height] for
/// links that are 44/48px tall boxes.
class D8Link extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double? height;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  const D8Link(
    this.label, {
    super.key,
    this.onTap,
    this.size = 14,
    this.height,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget t = Text(label, style: tx(size, w: w600, c: MP.primary), maxLines: 1);
    if (height != null) t = SizedBox(height: height, child: Center(widthFactor: 1, child: t));
    return Semantics(
      link: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Tap(onTap: onTap ?? () {}, radius: 8, child: Padding(padding: padding, child: t)),
    );
  }
}

/// First two lines of a conversation row (Care, Nutrition): name + time, then
/// "Who: preview" + unread count.
class D8ConvHead extends StatelessWidget {
  final String name;
  final String time;
  final String who;
  final String text;
  final int unread;
  const D8ConvHead({
    super.key,
    required this.name,
    required this.time,
    required this.who,
    required this.text,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = unread > 0;
    final previewColor = isUnread ? MP.ink : MP.ink2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: tx(16, w: w600, h: 1.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Gap(8),
            Text(
              time,
              style: tx(13, w: isUnread ? w600 : w400, c: isUnread ? MP.primary : MP.ink3, h: 24 / 13, tab: true),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$who:', style: const TextStyle(fontWeight: w600)),
                    TextSpan(text: ' $text'),
                  ],
                ),
                style: tx(14, c: previewColor, h: 20 / 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isUnread) ...[
              const Gap(8),
              Container(
                height: 20,
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: MP.primary, borderRadius: BorderRadius.circular(999)),
                child: Text('$unread', style: tx(12, w: w700, c: MP.white, h: 1, tab: true)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 16px dashed circle ("not done yet"), drawn from the design's SVG verbatim
/// (no round caps, `stroke-dasharray="3 3"`).
class D8PendingIcon extends StatelessWidget {
  const D8PendingIcon({super.key});

  @override
  Widget build(BuildContext context) => const Svg(
    '<svg viewBox="0 0 24 24" fill="none" stroke="#69738A" stroke-width="2" stroke-dasharray="3 3">'
    '<circle cx="12" cy="12" r="9"/></svg>',
    width: 16,
    height: 16,
  );
}

/// Box with a CSS-style dashed border (`border: Npx dashed`). The border takes
/// layout space like CSS; [fill] paints under it (background-clip: border-box).
class D8DashedBox extends StatelessWidget {
  final Widget? child;
  final double radius;
  final double strokeWidth;
  final Color color;
  final Color? fill;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  const D8DashedBox({
    super.key,
    this.child,
    required this.radius,
    this.strokeWidth = 1,
    this.color = MP.lineStrong,
    this.fill,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(radius: radius, strokeWidth: strokeWidth, color: color),
      child: Container(
        width: width,
        height: height,
        padding: padding.add(EdgeInsets.all(strokeWidth)),
        decoration: fill == null ? null : BoxDecoration(color: fill, borderRadius: BorderRadius.circular(radius)),
        child: child,
      ),
    );
  }
}

/// Dashes like Chromium's borders: measured on the integer thickness (so a
/// 1.5px border dashes like 1px), dash = 3× and gap = 2× it below 3px (2× / 1×
/// from 3px), with the gap evened out so the pattern closes around corners.
class _DashedRRectPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final Color color;
  const _DashedRRectPainter({required this.radius, required this.strokeWidth, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = (Offset.zero & size).deflate(half);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - half))));
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    final unit = math.max(1.0, strokeWidth.floorToDouble());
    final dash = unit * (unit >= 3 ? 2 : 3);
    final gap = unit * (unit >= 3 ? 1 : 2);
    for (final metric in path.computeMetrics()) {
      final count = math.max(1, (metric.length / (dash + gap)).round());
      final step = metric.length / count;
      for (var i = 0; i < count; i++) {
        final start = i * step;
        canvas.drawPath(metric.extractPath(start, start + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.radius != radius || old.strokeWidth != strokeWidth || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Live-data helpers
// ─────────────────────────────────────────────────────────────────────────────

/// List times as in the design: "9:12 AM" today, "Yesterday", "Sun" within
/// the week, otherwise "28 Sep".
String d8ListTime(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (F.sameDay(d, n)) return F.time(d);
  if (F.sameDay(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days > 0 && days < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  return F.dayMonth(d);
}

/// "Who:" of a conversation preview from the inbox row's `lastMessage`.
String d8Who(Map<String, dynamic> row) {
  final m = row.obj('lastMessage');
  final label = m.str('senderLabel');
  return switch (m.str('senderType')) {
    'patient' => F.firstName(row.obj('patient').str('name', label)),
    'ai' => 'AI',
    'dietician' => label.isEmpty ? 'Dietician' : label,
    // The label is the sender's first word, so doctors come through as "Dr.".
    'doctor' => label.isEmpty || label.startsWith('Dr') ? 'Doctor' : label,
    _ => label.isEmpty ? 'Clinic' : label,
  };
}

/// Triage chip text for an inbox row (empty = no chip).
String d8Triage(Object? key) => switch (key) {
  'needs_attention' => 'Needs attention',
  'check_in_due' => 'Check-in due',
  'review_due' => 'Review due',
  _ => '',
};

/// "Updated 4s ago", "Updated 3 min ago".
String d8Updated(DateTime at, {DateTime? now}) {
  final s = (now ?? DateTime.now()).difference(at).inSeconds;
  if (s < 60) return 'Updated ${s < 0 ? 0 : s}s ago';
  if (s < 3600) return 'Updated ${s ~/ 60} min ago';
  return 'Updated ${F.ago(at).toLowerCase()}';
}

/// `Api.I.get` for one card's data: resolves null instead of throwing, so
/// that card can show its own error while the rest of the screen loads.
Future<Object?> d8Optional(String path, {Map<String, Object?>? query}) =>
    Api.I.get(path, query: query).then<Object?>((v) => v, onError: (Object _) => null);

/// "1 item", "4 items".
String d8Plural(num n, String one, [String? many]) => '${n.round()} ${n == 1 ? one : (many ?? '${one}s')}';

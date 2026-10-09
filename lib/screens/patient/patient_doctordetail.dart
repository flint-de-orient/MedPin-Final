import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p2.dart';

/// Design: Patient-DoctorDetail.dc.html — "Patient · doctor page (Dr. Sen)".
class PatientDoctordetailScreen extends StatefulWidget {
  const PatientDoctordetailScreen({super.key});

  @override
  State<PatientDoctordetailScreen> createState() => _PatientDoctordetailScreenState();
}

typedef _Tone = (Color, Color);

const _Tone _high = (MP.amberSoft, MP.amber);
const _Tone _new = (MP.primarySoft, MP.primary);

const _todos = ['Upload HbA1c report', "Log today's fasting sugar", 'Note down questions for Dr. Sen'];

const _plan = [
  ('Metformin 500 mg', '1-0-1 · after food', '78%', MP.amber),
  ('Glimepiride 1 mg', '1-0-0 · before breakfast', 'New', MP.ink3),
  ('Vitamin D3 60,000 IU', 'Once a week · Sunday', '100%', MP.green),
];

const List<(String, String, String, String, _Tone?)> _docs = [
  ('Test result · shared by you', 'HbA1c', '30 Sep · Suraksha Diagnostics', 'High', _high),
  ('Prescription', 'Diabetes follow-up', '29 Sep · Dr. Sen', 'Latest', _new),
  ('Test result · shared by you', 'Lipid profile', '30 Sep · Suraksha Diagnostics', 'High', _high),
  ('Prescription', 'Sugar and cholesterol', '12 Mar · Dr. Sen', '', null),
];

/// (date, title, dot fill, dot ring)
const _visits = [
  ('Today · 5:00 PM', 'Follow-up · review HbA1c', MP.primary, MP.primary),
  ('29 Sep 2026', 'Glimepiride added', MP.white, MP.ink3),
  ('12 Mar 2026', 'Lipid test ordered', MP.white, MP.ink3),
  ('12 Jan 2026', 'HbA1c improved to 6.8%', MP.white, MP.ink3),
];

const _filters = ['All', 'From Dr. Sen · 3', 'Shared by you · 4'];

/// To-do circle: dashed 2px #69738A ring (no round caps, so not [Ico]).
const _dashedCircle =
    '<svg viewBox="0 0 24 24" fill="none" stroke="#69738A" stroke-width="2" stroke-dasharray="3 3"><circle cx="12" cy="12" r="9"/></svg>';

const _cardDeco = BoxDecoration(
  color: MP.white,
  borderRadius: BorderRadius.all(Radius.circular(24)),
  border: Border.fromBorderSide(BorderSide(color: MP.line)),
  boxShadow: MPShadow.card,
);

class _PatientDoctordetailScreenState extends State<PatientDoctordetailScreen> {
  final _done = [true, false, false];
  int _filter = 0;

  bool _inFilter((String, String, String, String, _Tone?) d) => switch (_filter) {
    1 => d.$1 == 'Prescription',
    2 => d.$1.endsWith('shared by you'),
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    void chat() => Nav.go(context, 'Patient-DoctorChat');

    return MpPage(
        // 64px bar: back + more (white, joins the white profile header below).
        header: Container(
          height: 64,
          color: MP.white,
          padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
          child: Row(
            children: [
              MpIconButton(I.back, label: 'Back to My doctors', onTap: () => Nav.back(context)),
              const Spacer(),
              MpIconButton(
                I.moreV,
                label: 'More options',
                filled: true,
                onTap: () => p2Missing(context, 'The options menu'),
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profile(chat),
            VGap(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
              gap: 16,
              children: [
                _nextVisit(),
                _latestMessage(chat),
                _yourPlan(),
                _lastVisit(),
                _documents(),
                _visitHistory(),
                _sharing(),
              ],
            ),
          ],
        ),
      );
  }

  // Avatar, name, availability + Chat / Book / Share.
  Widget _profile(VoidCallback chat) {
    Widget tile(String icon, String label, VoidCallback onTap) => P2Box(
      onTap: onTap,
      label: label,
      height: 58, // <a> 56px + 1px border (content-box)
      radius: 16,
      color: MP.white,
      border: MP.lineStrong,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Ico(icon, size: 18, color: MP.primary), const Gap(2), Text(label, style: tx(13, w: w700))],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 14px dot + 3px ring (content-box) at right 2 / bottom 2.
              const P2AvatarDot('AS', size: 72, fontSize: 24, dot: MP.green, dotSize: 20, dotBorder: 3, inset: 2),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dr. Arjun Sen', style: tx(26, w: w800, h: 1.15, em: -0.02)),
                    const Gap(2),
                    Text('MBBS, MD · Diabetes & hormones', style: tx(14, c: MP.ink2)),
                    const Gap(2),
                    Text('Available now · replies in ~10 min', style: tx(13, w: w600, c: MP.green)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: P2Box(
                  onTap: chat,
                  label: 'Chat, 2 unread',
                  height: 56,
                  radius: 16,
                  color: MP.primary,
                  shadow: MPShadow.button,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.message, size: 20, color: MP.white),
                      const Gap(8),
                      Text('Chat', style: tx(16, w: w700, c: MP.white)),
                      const Gap(8),
                      const P2Pill('2', bg: MP.white, fg: MP.primary, height: 20, padX: 6, weight: w800, minWidth: 20),
                    ],
                  ),
                ),
              ),
              const Gap(8),
              Expanded(child: tile(I.calendar, 'Book', () => p2Missing(context, 'Booking'))),
              const Gap(8),
              Expanded(child: tile(I.upload, 'Share', () => Nav.go(context, 'Records-Add'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nextVisit() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MP.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MP.primary, width: 1.5),
        boxShadow: MPShadow.float,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT VISIT', style: tx(12, w: w700, c: MP.primary, em: 0.06)),
                    const Gap(4),
                    Text('Today, 5:00 PM', style: tx(20, w: w700, h: 1.25)),
                    const Gap(4),
                    Text('City Care Clinic, Salt Lake · Token 04', style: tx(14, c: MP.ink2)),
                  ],
                ),
              ),
              const Gap(12),
              const P2Pill('Follow-up', bg: MP.primarySoft, fg: MP.primary, height: 26, padX: 10),
            ],
          ),
          const Gap(14),

          // Before you go (tap an item to tick it off)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('BEFORE YOU GO', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                for (var i = 0; i < _todos.length; i++) ...[
                  const Gap(8),
                  Semantics(
                    checked: _done[i],
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _done[i] = !_done[i]),
                      child: Row(
                        children: [
                          _done[i]
                              ? const Ico(I.check, size: 16, color: MP.green, stroke: 2.5)
                              : const Svg(_dashedCircle, width: 16, height: 16),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              _todos[i],
                              style: _done[i] ? tx(14, c: MP.ink2, deco: TextDecoration.lineThrough) : tx(14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: P2Box(
                  onTap: () => p2Missing(context, 'The map'),
                  height: 48,
                  radius: 12,
                  color: MP.primarySoft,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Ico(I.pin, size: 16, color: MP.primary),
                      const Gap(6),
                      Text('Directions', style: tx(14, w: w700, c: MP.primary)),
                    ],
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: P2Box(
                  onTap: () => p2Missing(context, 'Rescheduling'),
                  height: 50, // <a> 48px + 1px border (content-box)
                  radius: 12,
                  border: MP.lineStrong,
                  alignment: Alignment.center,
                  child: Text('Reschedule', style: tx(14, w: w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _latestMessage(VoidCallback chat) {
    return P2Box(
      onTap: chat,
      label: 'Open chat with Dr. Sen',
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      radius: 20,
      color: MP.white,
      border: MP.line,
      shadow: MPShadow.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('LATEST MESSAGE', style: tx(12, w: w700, c: MP.ink3, em: 0.06))),
              Text('9:14 AM', style: tx(13, c: MP.ink3)),
              const Gap(6),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
              ),
            ],
          ),
          const Gap(8),
          Text.rich(
            TextSpan(
              style: tx(15, h: 1.5),
              children: [
                TextSpan(text: 'Dr. Sen:', style: tx(15, w: w700, h: 1.5)),
                const TextSpan(text: " Got your HbA1c report, thanks. We'll adjust the dose when you come in at 5."),
              ],
            ),
          ),
          const Gap(8),
          Text('Reply', style: tx(14, w: w700, c: MP.primary)),
        ],
      ),
    );
  }

  Widget _yourPlan() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Your plan', style: tx(20, w: w700, h: 1.25))),
                Text('82% taken', style: tx(14, w: w700, c: MP.amber)),
              ],
            ),
          ),
          for (final m in _plan)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.$1, style: tx(15, w: w600)),
                        const Gap(2),
                        Text(m.$2, style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                  const Gap(12),
                  Text(m.$3, style: tx(14, w: w700, c: m.$4)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADVICE', style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                const Gap(6),
                Text(
                  'Walk 30 minutes, 5 days a week. Avoid sweets and refined flour. Check fasting sugar 3 times a week.',
                  style: tx(14, h: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lastVisit() {
    Widget vital(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(12, c: MP.ink2)),
          const Gap(2),
          Text(value, maxLines: 1, style: tx(16, w: w800, c: color, tab: true)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Last visit', style: tx(20, w: w700, h: 1.25))),
              Text('29 Sep 2026', style: tx(14, c: MP.ink2)),
            ],
          ),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Ico(I.sparkle, size: 16, color: MP.primary, stroke: 2),
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  'Sugar was higher than target, so Glimepiride was added. You were asked to get an HbA1c test and come back today.',
                  style: tx(15, h: 1.5),
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(child: vital('BP', '128/82', MP.ink)),
              const Gap(8),
              Expanded(child: vital('Sugar (F)', '142', MP.amber)),
              const Gap(8),
              Expanded(child: vital('Weight', '68.5', MP.ink)),
            ],
          ),
          const Gap(12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => p2Missing(context, 'The prescription view'),
            child: Text('View prescription', style: tx(14, w: w700, c: MP.primary)),
          ),
        ],
      ),
    );
  }

  Widget _documents() {
    final docs = [
      for (final d in _docs)
        if (_inFilter(d)) d,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Prescriptions & reports', style: tx(20, w: w700, h: 1.25))),
                const Gap(8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Nav.go(context, 'Patient-Records'),
                  child: Text('All 7', style: tx(14, w: w600, c: MP.primary)),
                ),
              ],
            ),
          ),
          // Filter chips (wider than the card in the design, so they scroll).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0) const Gap(8),
                  P2Box(
                    onTap: () => setState(() => _filter = i),
                    label: _filters[i],
                    height: 36,
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    color: _filter == i ? MP.primary : MP.white,
                    border: _filter == i ? null : MP.lineStrong,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(_filters[i], style: tx(13, w: w600, c: _filter == i ? MP.white : MP.ink2))],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in docs)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.$1.toUpperCase(), style: tx(12, w: w700, c: MP.ink3, em: 0.06)),
                              const Gap(3),
                              Text(d.$2, style: tx(15, w: w600)),
                              const Gap(3),
                              Text(d.$3, style: tx(13, c: MP.ink2)),
                            ],
                          ),
                        ),
                        if (d.$5 != null) ...[const Gap(12), P2Pill(d.$4, bg: d.$5!.$1, fg: d.$5!.$2)],
                        const Gap(12),
                        P2Box(
                          onTap: () => toast(context, 'Downloading ${d.$2}'),
                          label: 'Download ${d.$2}',
                          width: 44,
                          height: 44,
                          radius: 12,
                          color: MP.white,
                          border: MP.lineStrong,
                          alignment: Alignment.center,
                          child: const Ico(I.download, size: 18, color: MP.primary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _visitHistory() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Visits with Dr. Sen', style: tx(20, w: w700, h: 1.25)),
          const Gap(12),
          for (var i = 0; i < _visits.length; i++) ...[
            const Gap(4),
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_visits[i].$1, style: tx(13, c: MP.ink3)),
                      const Gap(2),
                      Text(_visits[i].$2, style: tx(15, w: w600)),
                    ],
                  ),
                ),
                // Timeline: 10px dot (2px ring) + 1px line to the row's end.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: Column(
                    children: [
                      const Gap(5),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _visits[i].$3,
                          shape: BoxShape.circle,
                          border: Border.all(color: _visits[i].$4, width: 2),
                        ),
                      ),
                      // Last row: transparent line.
                      Expanded(
                        child:
                            i == _visits.length - 1
                                ? const SizedBox(width: 1)
                                : const ColoredBox(color: MP.line, child: SizedBox(width: 1)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sharing() {
    return P2Box(
      onTap: () => p2Missing(context, 'Managing access'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      radius: 20,
      color: MP.white,
      border: MP.line,
      child: Row(
        children: [
          const Ico(I.shield, size: 20, color: MP.ink2),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What Dr. Sen can see', style: tx(15, w: w700)),
                const Gap(2),
                Text('Full record, daily log and tracked vitals', style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const Gap(12),
          Text('Manage', style: tx(14, w: w600, c: MP.primary)),
        ],
      ),
    );
  }
}

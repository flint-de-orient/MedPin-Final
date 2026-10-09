import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_p1.dart';

/// Design: Patient-Log.dc.html — "Patient · log meal, exercise, steps" (sheet over 'Main').
class PatientLogSheet extends StatefulWidget {
  /// 0 = Meal (the design's state), 1 = Exercise, 2 = Steps.
  final int initialTab;
  const PatientLogSheet({super.key, this.initialTab = 0});

  @override
  State<PatientLogSheet> createState() => _PatientLogSheetState();
}

class _PatientLogSheetState extends State<PatientLogSheet> {
  static const _tabs = ['Meal', 'Exercise', 'Steps'];
  static const _meals = ['Breakfast', 'Lunch', 'Snack', 'Dinner'];
  static const _exercises = ['Walk', 'Yoga', 'Cycling', 'Other'];
  static const _people = [
    (name: 'Mou Banerjee', role: 'Dietician · reviews every 3 days'),
    (name: 'Dr. Arjun Sen', role: 'Diabetes'),
    (name: 'Dr. Rina Mitra', role: 'Heart'),
  ];

  late int _tab = widget.initialTab.clamp(0, _tabs.length - 1);
  int _meal = 1;
  int _exercise = 0;
  final List<bool> _share = [true, true, false];
  bool _photo = false;
  bool _listening = false;
  final _mealNote = TextEditingController();
  final _exerciseNote = TextEditingController();
  final _steps = TextEditingController();

  @override
  void dispose() {
    _mealNote.dispose();
    _exerciseNote.dispose();
    _steps.dispose();
    super.dispose();
  }

  String get _saveLabel => switch (_tab) {
        0 => 'Save ${_meals[_meal].toLowerCase()}',
        1 => 'Save exercise',
        _ => 'Save steps',
      };

  void _save() {
    final what = switch (_tab) {
      0 => _meals[_meal],
      1 => _exercises[_exercise],
      _ => 'Steps',
    };
    P1.closeWithToast(context, '$what saved to your log');
  }

  @override
  Widget build(BuildContext context) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
    final sections = <Widget>[
      pad(_Segmented(options: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i))),
      if (_tab == 0) ...[
        pad(_chips(_meals, _meal, (i) => setState(() => _meal = i))),
        pad(
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PhotoTile(added: _photo, onTap: () => setState(() => _photo = !_photo)),
                const Gap(10),
                Expanded(child: _noteBox(_mealNote, 'What did you eat? E.g. 2 rotis, dal, salad')),
              ],
            ),
          ),
        ),
      ] else if (_tab == 1) ...[
        pad(_chips(_exercises, _exercise, (i) => setState(() => _exercise = i))),
        pad(_noteBox(_exerciseNote, 'How long and how hard? E.g. 30 min brisk walk')),
      ] else
        pad(
          MpInput(
            label: 'Steps today',
            controller: _steps,
            hint: 'E.g. 6,000',
            keyboard: TextInputType.number,
            unit: 'steps',
            help: 'Goal 8,000 · 4,820 so far today',
          ),
        ),
      pad(_shareWith()),
      pad(MpButton(_saveLabel, onTap: _save)),
    ];
    return MpSheet(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            P1SheetHeader(title: Text('Add to your log', style: tx(20, w: w700, h: 1.25)), center: true),
            for (final s in sections) ...[const Gap(18), s],
          ],
        ),
      ),
    );
  }

  Widget _chips(List<String> items, int selected, ValueChanged<int> onTap) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < items.length; i++) _ChoiceChip(items[i], on: i == selected, onTap: () => onTap(i)),
      ],
    );
  }

  /// Textarea (96px, radius 16, 1px #D5DBE5, 15/1.45) with the mic button in
  /// its corner. The wrapper is 100px tall like the browser's (the textarea is
  /// inline-block and leaves a 4px line gap under it).
  Widget _noteBox(TextEditingController controller, String hint) {
    return SizedBox(
      height: 100,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 96,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 52, 12),
              decoration: BoxDecoration(
                color: MP.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MP.lineStrong),
              ),
              child: TextField(
                controller: controller,
                expands: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: tx(15, h: 1.45),
                cursorColor: MP.primary,
                decoration: InputDecoration.collapsed(hintText: hint, hintStyle: tx(15, h: 1.45, c: P1.placeholder)),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Semantics(
              button: true,
              toggled: _listening,
              label: 'Speak instead',
              child: Tap(
                onTap: () => setState(() => _listening = !_listening),
                radius: 12,
                color: _listening ? MP.primary : MP.primarySoft,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: Ico(I.mic, size: 18, color: _listening ? MP.white : MP.primary)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareWith() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Share with', style: tx(14, w: w600))),
        for (var i = 0; i < _people.length; i++)
          Tap(
            onTap: () => setState(() => _share[i] = !_share[i]),
            radius: 0,
            child: Container(
              constraints: BoxConstraints(minHeight: i == 0 ? 52 : 53),
              decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
              child: Row(
                children: [
                  MpCheck(value: _share[i], onChanged: (v) => setState(() => _share[i] = v)),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_people[i].name, style: tx(15, w: w600)),
                        const Gap(1),
                        Text(_people[i].role, style: tx(13, c: MP.ink2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tabs: #F1F4F9 track (padding 4, radius 16), white selected tab
/// (radius 12, 0 1 2 rgba(0,51,153,.08)), no gap between tabs.
class _Segmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const _Segmented({required this.options, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? MP.white : const Color(0x00FFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: i == index ? MPShadow.hairline : null,
                    ),
                    child: Text(
                      options[i],
                      style: tx(15, w: i == index ? w600 : w500, c: i == index ? MP.ink : MP.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Choice pill: 40px, padding 0 16, radius 999, 14/600; on = #003399 / white.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ChoiceChip(this.label, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Border-box button: 40px tall including the 1px border.
    return Semantics(
      selected: on,
      button: true,
      child: SizedBox(
        height: 40,
        child: Tap(
          onTap: onTap,
          radius: 999,
          color: on ? MP.primary : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: tx(14, w: w600, c: on ? MP.white : MP.ink2)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 88×96 "Photo" tile: #F7F9FC, 1.5px dashed #D5DBE5 border, radius 16.
class _PhotoTile extends StatelessWidget {
  final bool added;
  final VoidCallback onTap;
  const _PhotoTile({required this.added, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: added ? 'Photo added' : 'Add a photo of your meal',
      child: Tap(
        onTap: onTap,
        radius: 16,
        color: MP.bg,
        child: CustomPaint(
          foregroundPainter: const _DashedBorder(),
          child: SizedBox(
            width: 88,
            height: 96,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Ico(added ? I.check : I.camera, size: 22, color: MP.primary, stroke: added ? 2 : 1.75),
                const Gap(6),
                Text(added ? 'Added' : 'Photo', style: tx(13, w: w700, c: MP.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed 1.5px rounded outline (about 3px dashes and 2px gaps, as Chrome draws it).
class _DashedBorder extends CustomPainter {
  const _DashedBorder();

  @override
  void paint(Canvas canvas, Size size) {
    const w = 1.5;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(w / 2), const Radius.circular(16 - w / 2)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = MP.lineStrong;
    for (final metric in outline.computeMetrics()) {
      final count = (metric.length / 5).floor();
      if (count == 0) continue;
      final step = metric.length / count;
      for (var i = 0; i < count; i++) {
        final start = i * step;
        canvas.drawPath(metric.extractPath(start, start + step * 0.6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => false;
}

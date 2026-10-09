import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/mp.dart';
import 'common_d10.dart';

/// Design: Knowledge-Editor.dc.html — "Knowledge · edit".
class KnowledgeEditorScreen extends StatefulWidget {
  const KnowledgeEditorScreen({super.key});

  @override
  State<KnowledgeEditorScreen> createState() => _KnowledgeEditorScreenState();
}

const _content =
    'Metformin is best taken with meals to reduce stomach upset. If it is prescribed twice a day (1-0-1), '
    'take one tablet with breakfast and one with dinner. If you forget a dose, take it with your next meal '
    'only if that meal is more than 4 hours away; never take two doses together to catch up. '
    'Extended-release (XR) tablets are usually taken once a day with the evening meal. '
    'Do not change your timing or dose without checking with your doctor.';

const _languages = ['English', 'Bengali', 'Hindi'];
const _categories = ['Medicines', 'Diabetes', 'Hypertension', 'Diet'];
const _maxChars = 2000;

class _KnowledgeEditorScreenState extends State<KnowledgeEditorScreen> {
  final _title = TextEditingController(text: 'Metformin timing');
  final _body = TextEditingController(text: _content);
  final _source = TextEditingController(text: 'ADA Standards of Care 2026, Section 9');
  final _tags = <String>['metformin', 'diabetes', 'dosage timing'];
  String _language = 'English';
  String _category = 'Medicines';
  String _saved = 'Last saved 2 min ago';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    final tag = await openSheet<String>(context, (_) => const _AddTagSheet());
    if (!mounted || tag == null) return;
    if (!_tags.contains(tag)) setState(() => _tags.add(tag));
  }

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: MpHeader(
        'Edit entry',
        actions: [
          Semantics(
            button: true,
            label: 'More options',
            child: Tap(
              onTap: () => toast(context, 'More options are not in the design yet'),
              radius: 12,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Ico(I.moreV, size: 22, color: MP.ink, filled: true)),
              ),
            ),
          ),
        ],
      ),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        gap: 20,
        children: [
          // Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const MpBadge('Draft', weight: w600),
                  const Gap(8),
                  Expanded(child: Text(_saved, style: tx(14, c: MP.ink2, h: 20 / 14))),
                ],
              ),
              const Gap(4),
              Text(
                'The AI assistant only uses this entry once Dr. Sen approves it.',
                style: tx(13, c: MP.ink3, h: 18 / 13),
              ),
            ],
          ),

          // Title
          VGap(gap: 8, children: [const _FieldLabel('Title'), MpInput(controller: _title)]),

          // Content
          VGap(
            gap: 8,
            children: [
              const _FieldLabel('Content'),
              _TextArea(controller: _body, height: 316),
              Row(
                children: [
                  Expanded(child: Text('Written for patients, in plain words', style: tx(13, c: MP.ink3, h: 18 / 13))),
                  const Gap(8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _body,
                    builder:
                        (_, v, __) =>
                            Text('${v.text.length} / $_maxChars', style: tx(13, c: MP.ink3, h: 18 / 13, tab: true)),
                  ),
                ],
              ),
            ],
          ),

          // Language + category
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: VGap(
                  gap: 8,
                  children: [
                    const _FieldLabel('Language'),
                    D10Select(
                      title: 'Language',
                      value: _language,
                      options: _languages,
                      onChanged: (v) => setState(() => _language = v),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Expanded(
                child: VGap(
                  gap: 8,
                  children: [
                    const _FieldLabel('Category'),
                    D10Select(
                      title: 'Category',
                      value: _category,
                      options: _categories,
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Source citation
          VGap(
            gap: 8,
            children: [
              const _FieldLabel('Source citation'),
              MpInput(controller: _source),
              Text('Shown to you in chat review when the AI cites this entry.', style: tx(13, c: MP.ink3, h: 18 / 13)),
            ],
          ),

          // Tags
          VGap(
            gap: 8,
            children: [
              const _FieldLabel('Tags'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _tags) _TagChip(t, onRemove: () => setState(() => _tags.remove(t))),
                  _AddTagButton(onTap: _addTag),
                ],
              ),
            ],
          ),
        ],
      ),
      bottom: MpBottomBar(
        child: Row(
          children: [
            SizedBox(
              width: 124,
              child: MpButton(
                'Save draft',
                kind: MpBtn.secondary,
                onTap: () {
                  setState(() => _saved = 'Last saved just now');
                  toast(context, 'Draft saved');
                },
              ),
            ),
            const Gap(12),
            Expanded(
              child: MpButton(
                'Submit for approval',
                onTap: () {
                  toast(context, 'Submitted for approval');
                  Nav.back(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Field label: 14/20, 600.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text, style: tx(14, w: w600, h: 20 / 14));
}

/// Fixed-height textarea (316px border-box, padding 14/16, 16/1.5) that
/// scrolls inside, with the MedPin focus style.
class _TextArea extends StatefulWidget {
  final TextEditingController controller;
  final double height;
  const _TextArea({required this.controller, required this.height});

  @override
  State<_TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<_TextArea> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: MP.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? MP.primary : MP.lineStrong),
          boxShadow: focused ? MPShadow.focusRing : null,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          inputFormatters: [LengthLimitingTextInputFormatter(_maxChars)],
          style: tx(16, h: 1.5),
          cursorColor: MP.primary,
          decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
        ),
      ),
    );
  }
}

/// 40px #F1F4F9 tag pill (padding 0 4 0 14) with a 32px remove button.
class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _TagChip(this.label, {required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
    decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: tx(14, w: w600)),
        const Gap(2),
        Semantics(
          button: true,
          label: 'Remove tag $label',
          child: Tap(
            onTap: onRemove,
            radius: 999,
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Center(child: Ico(I.close, size: 16, color: MP.ink2, stroke: 2)),
            ),
          ),
        ),
      ],
    ),
  );
}

/// "Add tag": 40px white pill, 1px dashed #D5DBE5 border, #003399 text.
class _AddTagButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTagButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: CustomPaint(
      foregroundPainter: const _DashedPillPainter(MP.lineStrong),
      child: Tap(
        onTap: onTap,
        radius: 999,
        color: MP.white,
        child: SizedBox(
          height: 40,
          child: Padding(
            // 14px padding + the 1px border (painted on top).
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Ico(I.plus, size: 16, color: MP.primary, stroke: 2),
                const Gap(6),
                Text('Add tag', style: tx(14, w: w600, c: MP.primary)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 1px dashed pill outline, Chrome-style 3px dashes with ~2px gaps.
class _DashedPillPainter extends CustomPainter {
  final Color color;
  const _DashedPillPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)));
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      final n = (m.length / 5).floor();
      if (n < 1) continue;
      final step = m.length / n;
      for (var i = 0; i < n; i++) {
        final start = i * step;
        canvas.drawPath(m.extractPath(start, start + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPillPainter oldDelegate) => oldDelegate.color != color;
}

/// Small sheet to type a new tag.
class _AddTagSheet extends StatefulWidget {
  const _AddTagSheet();

  @override
  State<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<_AddTagSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final v = _c.text.trim().toLowerCase();
    Navigator.pop(context, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Add tag',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MpInput(controller: _c, hint: 'Tag name', autofocus: true),
          const Gap(16),
          MpButton('Add tag', onTap: _done),
        ],
      ),
    );
  }
}

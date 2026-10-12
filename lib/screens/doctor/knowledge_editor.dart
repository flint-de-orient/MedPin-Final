import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'common_d10.dart';
import '../../widgets/i18n.dart';

/// Design: Knowledge-Editor.dc.html — "Knowledge · edit".
/// Live (args {'knowledgeId'}; none = new entry): GET /api/knowledge/:id;
/// Save draft POST /api/knowledge or PATCH /api/knowledge/:id; Submit
/// POST /api/knowledge/:id/submit; ⋮ Approve / Retire (doctors).
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

class _KnowledgeEditorScreenState extends State<KnowledgeEditorScreen> with LiveData {
  final _title = TextEditingController(text: 'Metformin timing');
  final _body = TextEditingController(text: _content);
  final _source = TextEditingController(text: 'ADA Standards of Care 2026, Section 9');
  final _tags = <String>['metformin', 'diabetes', 'dosage timing'];
  String _language = 'English';
  String _category = 'Medicines';
  String _saved = 'Last saved 2 min ago';

  /// Live: the entry being edited (null = new).
  bool _argsRead = false;
  String? _id;
  bool _filled = false;
  final _busy = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    if (!isLive) return;
    _title.text = '';
    _body.text = '';
    _source.text = '';
    _tags.clear();
    _saved = 'Not saved yet';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _source.dispose();
    _busy.dispose();
    super.dispose();
  }

  @override
  Future<Object?> fetch() async {
    if (!_argsRead) {
      _id = (await d1Args(this))['knowledgeId'] as String?;
      _argsRead = true;
    }
    final id = _id;
    return {'entry': id == null ? null : await Api.I.get('/api/knowledge/$id')};
  }

  @override
  Future<void> reload({bool quiet = false}) async {
    await super.reload(quiet: quiet);
    if (!mounted || data == null) return;
    final e = _entry;
    setState(() {
      if (e != null && !_filled) {
        _filled = true;
        _title.text = e.str('title');
        _body.text = e.str('content');
        _source.text = e.str('sourceCitation');
        _tags
          ..clear()
          ..addAll([for (final t in (e['tags'] as List? ?? const [])) '$t']);
        _language = d10Languages[e.str('language')] ?? 'English';
        _category = d10Categories[e.str('category')] ?? 'Other';
      }
      final at = F.date(e?['updatedAt']);
      if (at != null) {
        final ago = F.ago(at);
        _saved = 'Last saved ${ago[0].toLowerCase()}${ago.substring(1)}';
      }
    });
  }

  Map<String, dynamic>? get _entry => data?['entry'] is Map ? data!.obj('entry') : null;

  String get _statusKey => _entry?.str('status', 'draft') ?? 'draft';

  static String _codeOf(Map<String, String> m, String label, String fallback) {
    for (final e in m.entries) {
      if (e.value == label) return e.key;
    }
    return fallback;
  }

  Map<String, Object?> get _body$ => {
    'title': _title.text.trim(),
    'content': _body.text.trim(),
    'summary': _summaryOf(_body.text.trim()),
    'language': _codeOf(d10Languages, _language, 'en'),
    'category': _codeOf(d10Categories, _category, 'other'),
    'sourceCitation': _source.text.trim(),
    'tags': _tags,
  };

  /// First sentence of the content, for list previews.
  static String _summaryOf(String content) {
    final m = RegExp(r'^.+?[.!?](\s|$)', dotAll: true).firstMatch(content);
    final s = (m?.group(0) ?? content).trim();
    return s.length > 160 ? '${s.substring(0, 157)}…' : s;
  }

  /// Creates or updates the entry; returns its id (null on failure).
  Future<String?> _saveLive() async {
    final res = await runAction(context, () async {
      final id = _id;
      final r = id == null ? await Api.I.post('/api/knowledge', _body$) : await Api.I.patch('/api/knowledge/$id', _body$);
      return (r as Map)['id'] as String?;
    }, busy: _busy);
    if (res != null) _id = res;
    return res;
  }

  Future<void> _saveDraft() async {
    if (!isLive) {
      setState(() => _saved = 'Last saved just now');
      toast(context, 'Draft saved');
      return;
    }
    final id = await _saveLive();
    if (id == null || !mounted) return;
    toast(context, 'Draft saved');
    reload(quiet: true);
  }

  Future<void> _submit() async {
    if (!isLive) {
      toast(context, 'Submitted for approval');
      Nav.back(context);
      return;
    }
    final id = await _saveLive();
    if (id == null || !mounted) return;
    final ok = await runAction(context, () => Api.I.post('/api/knowledge/$id/submit'), busy: _busy);
    if (ok == null || !mounted) return;
    toast(context, 'Submitted for approval');
    Nav.back(context);
  }

  /// ⋮ Entry options: approve (doctors), duplicate, retire, delete a draft.
  Future<void> _more() async {
    if (isLive && _id == null) {
      toast(context, 'Save the entry first');
      return;
    }
    final r = await Nav.go<String>(context, 'Knowledge-Options', args: {
      'knowledgeId': _id,
      'status': isLive ? _statusKey : 'approved',
      'canApprove': Session.I.role == 'doctor',
    });
    if (r == null || !mounted) return;
    if (r == 'deleted') {
      Nav.back(context);
    } else if (r.startsWith('duplicated:') && r.length > 11) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: Nav.spec('Knowledge-Editor')!.builder,
        settings: RouteSettings(name: 'Knowledge-Editor', arguments: {'knowledgeId': r.substring(11)}),
      ));
    } else if (isLive) {
      reload(quiet: true);
    }
  }

  (String, Color, Color) get _badge => switch (_statusKey) {
    'approved' => ('Approved', MP.greenSoft, MP.green),
    'pending' => ('Pending', MP.amberSoft, MP.amber),
    'retired' => ('Retired', MP.fill, MP.ink3),
    _ => ('Draft', MP.fill, MP.ink2),
  };

  String get _note {
    if (!isLive) return 'The AI assistant only uses this entry once Dr. Sen approves it.';
    return switch (_statusKey) {
      'approved' => 'The AI assistant uses this entry in its answers.',
      'retired' => 'Retired: the AI assistant no longer uses this entry.',
      _ => 'The AI assistant only uses this entry once a doctor approves it.',
    };
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
        isLive && _id == null ? 'New entry' : 'Edit entry',
        actions: [
          Semantics(
            button: true,
            label: 'More options',
            child: Tap(
              onTap: _more,
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
      body: livePlaceholder() ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        gap: 20,
        children: [
          // Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MpBadge(_badge.$1, bg: _badge.$2, fg: _badge.$3, weight: w600),
                  const Gap(8),
                  Expanded(child: Text(_saved, style: tx(14, c: MP.ink2, h: 20 / 14))),
                ],
              ),
              const Gap(4),
              Text(
                _note,
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
                      options: isLive ? d10Languages.values.toList() : _languages,
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
                      options: isLive ? d10Categories.values.toList() : _categories,
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
                onTap: _saveDraft,
              ),
            ),
            const Gap(12),
            Expanded(
              child: MpButton(
                'Submit for approval',
                onTap: _submit,
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
      // The field inside is what screen readers focus.
      excludeFromSemantics: true,
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
        child: MpFieldArea(child: TextField(
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
        )),
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

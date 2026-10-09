import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d1.dart';
import 'common_d10.dart';

/// Design: Knowledge-Shared.dc.html — "Knowledge · shared".
/// Live (args {'knowledgeId'}): GET /api/knowledge/:id; adopt / stop using
/// POST / DELETE /api/knowledge/:id/adopt.
class KnowledgeSharedScreen extends StatefulWidget {
  const KnowledgeSharedScreen({super.key});

  @override
  State<KnowledgeSharedScreen> createState() => _KnowledgeSharedScreenState();
}

class _KnowledgeSharedScreenState extends State<KnowledgeSharedScreen> with LiveData {
  static const _tags = ['levothyroxine', 'thyroid', 'dosage timing'];
  String? _id;
  final _busy = ValueNotifier(false);

  @override
  Future<Object?> fetch() async {
    _id ??= (await d1Args(this))['knowledgeId'] as String?;
    if (_id == null) throw const ApiException(404, 'NOT_FOUND', 'Choose an entry first');
    return Api.I.get('/api/knowledge/$_id');
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  bool get _adopted => data?['adopted'] == true;

  Future<void> _adopt() async {
    if (!isLive) {
      toast(context, 'Adopted for your practice');
      Nav.back(context);
      return;
    }
    if (data == null) return;
    final adopted = _adopted;
    final ok = await runAction(
      context,
      () => adopted ? Api.I.delete('/api/knowledge/$_id/adopt') : Api.I.post('/api/knowledge/$_id/adopt'),
      busy: _busy,
    );
    if (ok == null || !mounted) return;
    toast(context, adopted ? 'Removed from your practice' : 'Adopted for your practice');
    Nav.back(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final title = d?.str('title') ?? 'Thyroid tablet on an empty stomach';
    final content = d?.str('content') ??
        'Levothyroxine works best on an empty stomach. Take it with a glass of water as soon as you wake up, '
            '30 to 60 minutes before breakfast or tea. Keep calcium, iron and antacid tablets at least 4 hours '
            'apart from it. If you miss a dose, take it the same day when you remember; do not take two doses '
            'the next morning.';
    final language = d == null ? 'English' : (d10Languages[d.str('language')] ?? 'English');
    final category = d == null ? 'Medicines' : (d10Categories[d.str('category')] ?? d10Cap(d.str('category')));
    final source = d?.str('sourceCitation') ?? 'American Thyroid Association, Hypothyroidism guidelines';
    final tags = d == null ? _tags : [for (final t in (d['tags'] as List? ?? const [])) '$t'];
    final updated = F.date(d?['updatedAt']);
    final lastUpdated = d == null
        ? 'MedPin clinical team · 1 Sep 2026'
        : [d.str('authorLabel', 'MedPin'), if (updated != null) '${F.dayMonth(updated)} ${updated.year}'].join(' · ');
    final status = d == null ? 'approved' : d.str('status', 'approved');
    final adoptedLine = d == null || !_adopted ? 'Not yet adopted by your practice' : 'Adopted by your practice';
    final placeholder = livePlaceholder();
    return MpPage(
      header: const MpHeader('Knowledge entry'),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        gap: 20,
        children: [
          // Read-only note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: Ico(I.lock, size: 20, color: MP.primary)),
                const Gap(12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Shared by MedPin.', style: tx(14, w: w600, h: 20 / 14)),
                        const TextSpan(text: " Your practice can adopt this entry but can't edit it."),
                      ],
                    ),
                    style: tx(14, h: 20 / 14),
                  ),
                ),
              ],
            ),
          ),

          // Status + title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (status == 'approved')
                    const MpBadge.green('Approved', weight: w600)
                  else
                    MpBadge(d10Cap(status), weight: w600),
                  const Gap(8),
                  Flexible(child: Text(adoptedLine, style: tx(13, c: MP.ink3))),
                ],
              ),
              const Gap(8),
              Text(title, style: tx(28, w: w800, h: 1.15, em: -0.02)),
            ],
          ),

          // Entry details
          Semantics(
            container: true,
            label: 'Entry details',
            child: MpCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Item(
                    label: 'Content',
                    gap: 8,
                    divider: false,
                    child: Text(content, style: tx(16, h: 1.5)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Pair('Language', language)),
                        const Gap(12),
                        Expanded(child: _Pair('Category', category)),
                      ],
                    ),
                  ),
                  if (source.isNotEmpty)
                    _Item(
                      label: 'Source citation',
                      child: Text(source, style: tx(16, h: 1.5)),
                    ),
                  if (tags.isNotEmpty)
                    _Item(
                      label: 'Tags',
                      gap: 8,
                      child: Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tags) MpBadge(t, weight: w600)]),
                    ),
                  _Item(
                    label: 'Last updated',
                    child: Text(lastUpdated, style: tx(16, h: 24 / 16)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottom: MpBottomBar(
        child: MpButton(
          _adopted ? 'Stop using in my practice' : 'Adopt for my practice',
          kind: _adopted ? MpBtn.secondary : MpBtn.primary,
          onTap: _adopt,
        ),
      ),
    );
  }
}

/// One `<dt>/<dd>` block: 16px vertical padding, optional top divider.
class _Item extends StatelessWidget {
  final String label;
  final Widget child;
  final double gap;
  final bool divider;
  const _Item({required this.label, required this.child, this.gap = 4, this.divider = true});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: divider ? const BoxDecoration(border: Border(top: BorderSide(color: MP.line))) : null,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [D10Caps(label), Gap(gap), child]),
  );
}

/// Label over a single-line value (16/24).
class _Pair extends StatelessWidget {
  final String label;
  final String value;
  const _Pair(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [D10Caps(label), const Gap(4), Text(value, style: tx(16, h: 24 / 16))],
  );
}

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Knowledge editor · "More options" sheet: duplicate as a new draft, retire
/// an approved entry, or delete a draft. Opened with
/// {'knowledgeId', 'status': draft|pending|approved|retired}; pops
/// `duplicated:ID`, `retired` or `deleted`.
/// Live data: POST /api/knowledge/:id/duplicate, POST /api/knowledge/:id/retire,
/// DELETE /api/knowledge/:id.
class KnowledgeOptionsSheet extends StatelessWidget {
  const KnowledgeOptionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Nav.args<Map>(context) ?? const {};
    final id = a['knowledgeId'] as String?;
    final status = (a['status'] as String?) ?? 'draft';
    final canRetire = status == 'approved';
    final canDelete = status == 'draft' || status == 'pending';

    Future<void> run(String what) async {
      final nav = Navigator.of(context);
      if (!isLive || id == null) {
        toast(context, what == 'duplicate' ? 'Copied as a new draft' : what == 'retire' ? 'Entry retired' : 'Draft deleted');
        nav.pop(what == 'duplicate' ? 'duplicated:' : what == 'retire' ? 'retired' : 'deleted');
        return;
      }
      switch (what) {
        case 'duplicate':
          final r = await runAction(context, () => Api.I.post('/api/knowledge/$id/duplicate'));
          if (r == null || !context.mounted) return;
          toast(context, 'Copied as a new draft');
          nav.pop('duplicated:${(r as Map)['id']}');
        case 'retire':
          final note = await d4FormSheet(
            context,
            title: 'Retire this entry?',
            subtitle: 'MedPin AI stops using it. Patients who were told about it are not affected.',
            fields: const [D4FormField('Why (optional)', hint: 'e.g. Superseded by the 2026 protocol')],
            confirm: 'Retire entry',
          );
          if (note == null || note.isEmpty || !context.mounted) return;
          final r = await runAction(context, () => Api.I.post('/api/knowledge/$id/retire', {if (note.first.isNotEmpty) 'note': note.first}));
          if (r == null || !context.mounted) return;
          toast(context, 'Entry retired');
          nav.pop('retired');
        case 'delete':
          final yes = await d4Confirm(context, title: 'Delete this draft?', body: 'It is removed for everyone in your practice.', confirm: 'Delete draft');
          if (!yes || !context.mounted) return;
          final r = await runAction(context, () => Api.I.delete('/api/knowledge/$id'));
          if (r == null || !context.mounted) return;
          toast(context, 'Draft deleted');
          nav.pop('deleted');
      }
    }

    Widget option(String icon, String label, String sub, VoidCallback onTap, {Color color = MP.ink}) => Tap(
      onTap: onTap,
      radius: 12,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            MpIconTile(icon, size: 40, iconSize: 20, radius: 12, bg: color == MP.red ? MP.redSoft : MP.primarySoft, fg: color == MP.red ? MP.red : MP.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: tx(16, w: w600, c: color)),
                  const SizedBox(height: 2),
                  Text(sub, style: tx(13, c: MP.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return MpSheet(
      title: 'Entry options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          option(I.fileText, 'Duplicate as a new draft', 'Start a new entry from this one', () => run('duplicate')),
          if (canRetire) option(I.clock, 'Retire entry', 'MedPin AI stops using it; history is kept', () => run('retire'), color: MP.red),
          if (canDelete) option(I.close, 'Delete draft', 'Remove it for everyone', () => run('delete'), color: MP.red),
        ],
      ),
    );
  }
}

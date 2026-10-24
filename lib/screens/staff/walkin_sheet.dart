import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/i18n.dart';
import '../../widgets/mp.dart';
import '../doctor/add_patient.dart' show addWalkIn;

/// Today → "Register walk-in": find a patient the clinic already has (name or mobile) and
/// put them in today's queue, with what brings them in; or register a new one.
/// Live data: GET /api/patients?q=, POST /api/appointments/walk-in. Pops true when added.
class WalkInSheet extends StatefulWidget {
  const WalkInSheet({super.key});

  @override
  State<WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends State<WalkInSheet> {
  final _q = TextEditingController();
  final _reason = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = const [];
  bool _searching = false;
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() => _rows = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = (await Api.I.get('/api/patients', query: {'q': q, 'limit': '15', 'sort': 'recent'}) as Map).cast<String, dynamic>();
      if (!mounted || _q.text.trim() != q) return;
      setState(() => _rows = r.list('items'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(Map<String, dynamic> p) async {
    if (_busy) return;
    setState(() => _busy = true);
    final token = await addWalkIn(context, p.str('id'), reason: _reason.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (token == null) return;
    toast(context, trf(context, "{name} added to today's queue · token {token}", {'name': p.str('name'), 'token': '$token'.padLeft(2, '0')}));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    return MpSheet(
      title: 'Register walk-in',
      subtitle: 'Find the patient, or register someone new.',
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MpInput(controller: _q, hint: 'Name or mobile number', leadingIcon: I.search, height: 48, autofocus: true, onChanged: _onSearch, autofillHints: const []),
          const SizedBox(height: 10),
          MpInput(controller: _reason, hint: 'What brings them in (optional)', height: 48),
          const SizedBox(height: 12),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))),
            )
          else if (q.length >= 2 && _rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No patient found. Register them as new.', style: tx(14, c: MP.ink2)),
            ),
          for (final p in _rows)
            Tap(
              onTap: _busy ? null : () => _add(p),
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  MpAvatar(F.initials(p.str('name')), size: 40, fontSize: 14, photo: p['photo'] as String?),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserText(p.str('name'), style: tx(15, w: w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            if (p['age'] != null) '${p['age']} ${tr(context, 'yrs')}',
                            if (p.str('phone').length >= 4) '••${p.str('phone').substring(p.str('phone').length - 4)}',
                            ...[for (final c in (p['conditions'] as List? ?? const []).take(2)) '$c'],
                          ].join(' · '),
                          style: tx(13, c: MP.ink2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Add to queue', style: tx(14, w: w700, c: MP.primary)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          MpButton(
            'New patient',
            kind: MpBtn.secondary,
            icon: I.userPlus,
            height: 48,
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              Nav.go(nav.context, 'Add-Patient', args: const {'walkIn': true});
            },
          ),
        ],
      ),
    );
  }
}

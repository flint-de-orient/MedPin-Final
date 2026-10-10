import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';
import '../../widgets/i18n.dart';

/// Design: Consult-NotFound.dc.html — "Consultation · patient not found".
/// Live: args {'query'} from Consult-Pick. Close matches are patients whose
/// number starts like the typed one (or whose name starts like it), from
/// GET /api/consultations/pick?q=.
class ConsultNotfoundScreen extends StatefulWidget {
  const ConsultNotfoundScreen({super.key});

  @override
  State<ConsultNotfoundScreen> createState() => _ConsultNotfoundScreenState();
}

class _ConsultNotfoundScreenState extends State<ConsultNotfoundScreen> with LiveData {
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  String get _query => isLive ? '${(Nav.args<Map>(context) ?? const {})['query'] ?? ''}'.trim() : '98300 71245';
  String get _digits => D5Live.digits(_query);
  bool get _byNumber => RegExp(r'\d').hasMatch(_query);

  @override
  Future<Object?> fetch() async {
    await Future<void>.value(); // the route args are read after initState
    if (!mounted) return const {};
    final q = _query;
    final digits = _digits;
    final probe = _byNumber ? (digits.length >= 6 ? digits.substring(0, 6) : '') : (q.length >= 3 ? q.substring(0, 3) : '');
    if (probe.isEmpty) return const {'matches': []};
    final r = await Api.I.get('/api/consultations/pick', query: {'q': probe});
    final matches = [
      for (final p in D5Live.list(r is Map ? r['matches'] : null))
        if (!_byNumber || '${p['phone']}' != digits) p,
    ];
    return {'matches': matches.take(3).toList()};
  }

  /// '31 F · +91 98300 7' + bold '1254': the digits after the shared prefix.
  InlineSpan _phoneMeta(Map<String, dynamic> p) {
    final lead = D5Live.ageSex(p);
    final phone = D5Live.phone(p['phone']);
    var cut = phone.length;
    if (_byNumber) {
      final q = _digits;
      var seen = 0;
      for (var i = 4; i < phone.length; i++) {
        if (!RegExp(r'\d').hasMatch(phone[i])) continue;
        if (seen >= q.length || q[seen] != phone[i]) {
          cut = i;
          break;
        }
        seen++;
      }
    }
    return TextSpan(
      children: [
        TextSpan(text: lead.isEmpty ? phone.substring(0, cut) : '$lead · ${phone.substring(0, cut)}'),
        if (cut < phone.length) TextSpan(text: phone.substring(cut), style: tx(13, w: w700, c: MP.ink, tab: true)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Clearing the search returns to the empty search state (Consult-Pick).
    void clear() => Nav.tab(context, 'Consult-Pick');
    final placeholder = livePlaceholder();
    final matches = isLive ? (data?.list('matches') ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
    final query = _query;

    return MpPage(
      header: const D5Header('Consultation', subtitle: 'No patient selected'),
      bottom: const MpBottomBar(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: D5Button.disabled('Generate prescription'),
      ),
      body: VGap(
        // 136px in the design, less the 97px bar that covers it.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 39),
        gap: 16,
        children: [
          MpCard(
            radius: 20,
            shadow: MPShadow.float,
            child: VGap(
              gap: 16,
              children: [
                Text('Who are you consulting?', style: tx(20, w: w700, h: 1.25)),
                D5SearchField(
                  value: query,
                  tab: true,
                  onClear: clear,
                  onSubmitted: (v) {
                    if (v.trim().isEmpty) clear();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_byNumber ? 'No patient with this number' : 'No patient with this name', style: tx(16, w: w700)),
                      const Gap(4),
                      Text(
                        'Check the ${_byNumber ? 'number' : 'spelling'}, or add them as a new patient and start right away.',
                        style: tx(14, c: MP.ink2, h: 1.45),
                      ),
                    ],
                  ),
                ),
                if (!isLive)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const D5Label('Close match · check before adding', bottom: 4),
                      D5PersonRow(
                        leading: const MpAvatar('AG', size: 40, fontSize: 14),
                        name: 'Ankita Ghosh',
                        meta: TextSpan(
                          children: [
                            const TextSpan(text: '31 F · +91 98300 7'),
                            TextSpan(text: '1254', style: tx(13, w: w700, c: MP.ink, tab: true)),
                            const TextSpan(text: ' · last visit Jun'),
                          ],
                        ),
                        tab: true,
                        first: true,
                        onTap: () => Nav.go(context, 'Consult-Page'),
                      ),
                    ],
                  )
                else if (placeholder == null && matches.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      D5Label(matches.length == 1 ? 'Close match · check before adding' : 'Close matches · check before adding', bottom: 4),
                      for (var i = 0; i < matches.length; i++)
                        D5PersonRow(
                          leading: MpAvatar(F.initials(matches[i].str('name')), size: 40, fontSize: 14),
                          name: matches[i].str('name'),
                          meta: _phoneMeta(matches[i]),
                          tab: true,
                          first: i == 0,
                          onTap: () => D5Live.start(context, patientId: matches[i].str('id'), busy: _busy),
                        ),
                    ],
                  ),
                D5Button(
                  'Add as new patient',
                  icon: I.userPlus,
                  onTap: () => Nav.go(context, 'Consult-QuickAdd', args: isLive ? {'query': query} : null),
                ),
              ],
            ),
          ),
          MpCard(
            shadow: null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: D5IconText(
              icon: I.lock,
              text: 'Vitals, complaint, diagnosis and prescription open once a patient is selected.',
              style: tx(13, c: MP.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

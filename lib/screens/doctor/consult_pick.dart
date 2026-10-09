import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d5.dart';

/// Design: Consult-Pick.dc.html — "Consultation · not from a patient: search".
class ConsultPickScreen extends StatefulWidget {
  const ConsultPickScreen({super.key});

  @override
  State<ConsultPickScreen> createState() => _ConsultPickScreenState();
}

typedef _Person = (String, String, String, String, String);

class _ConsultPickScreenState extends State<ConsultPickScreen> with LiveData {
  // (token, name, age · sex, phone, waiting)
  static const _queue = <_Person>[
    ('05', 'Rahul Das', '45 M', '+91 98311 20764', 'waiting 22 min'),
    ('06', 'Aisha Khan', '52 F', '+91 90070 41288', 'waiting 15 min'),
    ('07', 'Sujit Mondal', '37 M', '+91 83360 15902', 'waiting 6 min'),
  ];

  // (initials, name, age · sex, phone, last visit)
  static const _recent = <_Person>[
    ('DB', 'Debasish Bose', '62 M', '+91 98740 33126', 'today'),
    ('MR', 'Moumita Roy', '41 F', '+91 97480 62215', '02 Sep'),
  ];

  static const _steps = [
    ('·', 'Vitals'),
    ('1', 'Chief complaint'),
    ('2', 'Diagnosis'),
    ('3', 'Medications'),
    ('4', 'Lab tests'),
    ('5', 'Advice & instructions'),
    ('6', 'Validity & follow-up'),
  ];

  String _query = '';

  // Live: GET /api/consultations/pick (waiting now + recent); typing searches
  // with ?q= and the matches replace the recent list.
  @override
  Future<Object?> fetch() => Api.I.get('/api/consultations/pick');

  List<Map<String, dynamic>>? _found;
  String _foundFor = '';
  Timer? _debounce;
  int _seq = 0;
  final _busy = ValueNotifier(false);

  @override
  void dispose() {
    _debounce?.cancel();
    _busy.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() => _query = v);
    if (!isLive) return;
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _found = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    try {
      final r = await Api.I.get('/api/consultations/pick', query: {'q': q});
      if (!mounted || seq != _seq) return;
      setState(() {
        _found = D5Live.list(r is Map ? r['matches'] : null);
        _foundFor = q;
      });
    } on ApiException catch (e) {
      if (mounted && seq == _seq) toast(context, e.message);
    }
  }

  static _Person _row(Map<String, dynamic> p, String lead, String extra) =>
      (lead, p.str('name'), D5Live.ageSex(p), D5Live.phone(p['phone']), extra);

  /// Live waiting rows with their appointment and patient ids.
  List<(_Person, String, String)> get _liveQueue => [
    for (final w in data!.list('waiting'))
      (
        _row(w.obj('patient'), w.str('token'), D5Live.waiting(w['waitingMin'])),
        w.str('appointmentId'),
        w.obj('patient').str('id'),
      ),
  ];

  /// Live recent patients (or the search matches) with their ids.
  List<(_Person, String)> get _liveRecent {
    final waiting = {for (final w in data!.list('waiting')) w.obj('patient').str('id')};
    final source = _query.trim().isEmpty ? data!.list('recent') : (_found ?? const <Map<String, dynamic>>[]);
    return [
      for (final p in source)
        if (_query.trim().isEmpty || !waiting.contains(p.str('id'))) (_row(p, F.initials(p.str('name')), ''), p.str('id')),
    ];
  }

  bool _matches(_Person p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (p.$2.toLowerCase().contains(q)) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty && p.$4.replaceAll(RegExp(r'\D'), '').contains(digits);
  }

  String _meta(_Person p) => [p.$3, p.$4, p.$5].where((s) => s.isNotEmpty).join(' · ');

  void _startAppointment(String appointmentId, String patientId) =>
      D5Live.start(context, appointmentId: appointmentId, patientId: patientId, busy: _busy);

  void _startPatient(String patientId) => D5Live.start(context, patientId: patientId, busy: _busy);

  Future<void> _submit(String _) async {
    final q = _query.trim();
    if (q.isEmpty) return;
    if (!isLive) {
      final hits = _queue.where(_matches).length + _recent.where(_matches).length;
      if (hits == 0) {
        // Same search screen, "patient not found" state.
        Nav.tab(context, 'Consult-NotFound');
      } else if (hits == 1) {
        Nav.go(context, 'Consult-Page');
      }
      return;
    }
    if (data == null) return;
    if (_foundFor != q) {
      _debounce?.cancel();
      await _search(q);
      if (!mounted || _foundFor != q) return;
    }
    final queue = _liveQueue.where((r) => _matches(r.$1)).toList();
    final recent = _liveRecent;
    if (queue.isEmpty && recent.isEmpty) {
      // Same search screen, "patient not found" state.
      D5Live.replace(context, 'Consult-NotFound', {'query': q});
    } else if (queue.length + recent.length == 1) {
      if (queue.isNotEmpty) {
        _startAppointment(queue.first.$2, queue.first.$3);
      } else {
        _startPatient(recent.first.$2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = isLive && data != null;
    final liveQueue = live ? _liveQueue.where((r) => _matches(r.$1)).toList() : const <(_Person, String, String)>[];
    final liveRecent = live ? _liveRecent : const <(_Person, String)>[];
    final queue = live ? [for (final r in liveQueue) r.$1] : _queue.where(_matches).toList();
    final recent = live ? [for (final r in liveRecent) r.$1] : _recent.where(_matches).toList();
    final searched = !isLive || _query.trim().isEmpty || _foundFor == _query.trim();
    final none = queue.isEmpty && recent.isEmpty && (!isLive || (_query.trim().isNotEmpty && searched));
    final byNumber = RegExp(r'\d').hasMatch(_query);

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
                  hint: 'Name or phone number',
                  autofocus: true,
                  onChanged: _changed,
                  onSubmitted: _submit,
                ),
                if (placeholder != null) placeholder,
                if (queue.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The pick list has no location name, so live it is just "Waiting now".
                      D5Label(isLive ? 'Waiting now' : 'Waiting now · Salt Lake', bottom: 4),
                      for (var i = 0; i < queue.length; i++)
                        D5PersonRow(
                          leading: _Token(queue[i].$1),
                          name: queue[i].$2,
                          meta: TextSpan(text: isLive ? _meta(queue[i]) : '${queue[i].$3} · ${queue[i].$4} · ${queue[i].$5}'),
                          first: i == 0,
                          onTap:
                              live
                                  ? () => _startAppointment(liveQueue[i].$2, liveQueue[i].$3)
                                  : () => Nav.go(context, 'Consult-Page'),
                        ),
                    ],
                  ),
                if (recent.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      D5Label(isLive && _query.trim().isNotEmpty ? 'Patients' : 'Recent', bottom: 4),
                      for (var i = 0; i < recent.length; i++)
                        D5PersonRow(
                          leading: MpAvatar(recent[i].$1, size: 40, fontSize: 14),
                          name: recent[i].$2,
                          meta: TextSpan(text: isLive ? _meta(recent[i]) : '${recent[i].$3} · ${recent[i].$4} · ${recent[i].$5}'),
                          first: i == 0,
                          onTap: live ? () => _startPatient(liveRecent[i].$2) : () => Nav.go(context, 'Consult-Page'),
                        ),
                    ],
                  ),
                if (none)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          byNumber ? 'No patient with this number' : 'No patient with this name',
                          style: tx(16, w: w700),
                        ),
                        const Gap(4),
                        Text(
                          'Check the ${byNumber ? 'number' : 'spelling'}, or add them as a new patient and start right away.',
                          style: tx(14, c: MP.ink2, h: 1.45),
                        ),
                      ],
                    ),
                  ),
                D5Button.outline(
                  'Add new patient',
                  icon: I.userPlus,
                  iconSize: 18,
                  height: 48,
                  radius: 12,
                  fontSize: 15,
                  onTap: () => Nav.go(context, 'Consult-QuickAdd', args: isLive ? {'query': _query.trim()} : null),
                ),
              ],
            ),
          ),

          // Consultation steps, available after selecting a patient.
          MpCard(
            shadow: null,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Container(
                    // 52px rows; the 1px top border sits outside (content-box).
                    height: i == 0 ? 52 : 53,
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: MP.line))),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: MP.fill, shape: BoxShape.circle),
                          child: Text(_steps[i].$1, style: tx(13, w: w700, c: MP.ink3)),
                        ),
                        const Gap(10),
                        Expanded(child: Text(_steps[i].$2, style: tx(16, w: w600, c: MP.ink3))),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: D5IconText(icon: I.lock, text: 'Select or add a patient to start.', style: tx(13, c: MP.ink3)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Queue token tile: 40×40, radius 12, #F1F4F9, 15 / 800 tabular.
class _Token extends StatelessWidget {
  final String token;
  const _Token(this.token);

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(12)),
    child: Text(token, style: tx(15, w: w800, tab: true)),
  );
}

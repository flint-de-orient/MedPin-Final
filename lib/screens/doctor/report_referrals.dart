import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../widgets/mp.dart';
import 'common_d3.dart';
import 'patient_picker.dart';
import '../../widgets/i18n.dart';

/// Design: Report-Referrals.dc.html — "Report · Referrals".
/// Live data: GET /api/referrals?direction=sent|received (period applied
/// to `referredAt` on the device). "Add a referral" posts /api/referrals;
/// a row's sheet marks it seen (POST /api/referrals/:id/seen).
class ReportReferralsScreen extends StatefulWidget {
  const ReportReferralsScreen({super.key});

  @override
  State<ReportReferralsScreen> createState() => _ReportReferralsScreenState();
}

class _Ref {
  final String name;
  final String status;
  final String detail;
  final String date;
  final bool seen;
  final bool cancelled;
  const _Ref(this.name, this.status, this.detail, this.date, {this.seen = false, this.cancelled = false});
}

/// One direction of the Sent / Received tabs.
class _Dir {
  final String tab;
  final List<(String, String, Color)> stats;
  final String barTitle;
  final List<D3BarRow> bars;
  final String listTitle;
  final List<_Ref> rows;
  final List<_Ref> more;
  const _Dir({
    required this.tab,
    required this.stats,
    required this.barTitle,
    required this.bars,
    required this.listTitle,
    required this.rows,
    required this.more,
  });
}

const _dirs = [
  _Dir(
    tab: 'Sent · 9',
    stats: [('9', 'Sent', MP.ink), ('6', 'Seen by them', MP.green), ('3', 'Awaiting', MP.amber)],
    barTitle: 'Sent to',
    bars: [
      D3BarRow('Cardiology', '4', 0.44),
      D3BarRow('Nephrology', '2', 0.22),
      D3BarRow('Ophthalmology', '2', 0.22),
      D3BarRow('Gynaecology', '1', 0.11),
    ],
    listTitle: 'All sent',
    rows: [
      _Ref('Amit Pal', 'Awaiting', 'To Dr. Sourav Lahiri · Nephrology · Rising creatinine', '24 Sep'),
      _Ref('Priya Sharma', 'Awaiting', 'To Dr. Rina Mitra · Cardiology · LDL still high', '29 Sep'),
      _Ref('Tapas Kar', 'Seen 25 Sep', 'To Eye clinic · Ophthalmology · Diabetic eye check', '18 Sep', seen: true),
      _Ref('Moumita Roy', 'Seen 8 Sep', 'To Dr. Rina Mitra · Cardiology · Palpitations', '2 Sep', seen: true),
    ],
    // Revealed by "Show 5 more".
    more: [
      _Ref('Debasish Bose', 'Awaiting', 'To Dr. Sourav Lahiri · Nephrology · Protein in urine', '27 Sep'),
      _Ref(
        'Partha Ghosh',
        'Seen 22 Sep',
        'To Dr. Rina Mitra · Cardiology · Breathless on stairs',
        '16 Sep',
        seen: true,
      ),
      _Ref('Ritam Sarkar', 'Seen 19 Sep', 'To Eye clinic · Ophthalmology · Blurred vision', '11 Sep', seen: true),
      _Ref('Sohini Bose', 'Seen 15 Sep', 'To Dr. Mitali Sen · Gynaecology · Irregular periods', '9 Sep', seen: true),
      _Ref('Subhash Dey', 'Seen 10 Sep', 'To Dr. Rina Mitra · Cardiology · ECG changes', '4 Sep', seen: true),
    ],
  ),
  _Dir(
    tab: 'Received · 6',
    stats: [('6', 'Received', MP.ink), ('4', 'Seen by you', MP.green), ('2', 'Awaiting', MP.amber)],
    barTitle: 'Received from',
    bars: [
      D3BarRow('General medicine', '3', 0.50),
      D3BarRow('Gynaecology', '2', 0.33),
      D3BarRow('Cardiology', '1', 0.17),
    ],
    listTitle: 'All received',
    rows: [
      _Ref('Rahul Das', 'Awaiting', 'From Dr. Rina Mitra · Cardiology · BP and sugar review', '29 Sep'),
      _Ref(
        'Payel Mukherjee',
        'Seen 30 Sep',
        'From Dr. Mitali Sen · Gynaecology · Thyroid before pregnancy',
        '27 Sep',
        seen: true,
      ),
      _Ref('Aisha Khan', 'Awaiting', 'From Dr. Anjan Basu · General medicine · TSH high on screening', '26 Sep'),
      _Ref('Farhana Islam', 'Seen 25 Sep', 'From Dr. Mitali Sen · Gynaecology · Low haemoglobin', '22 Sep', seen: true),
    ],
    more: [
      _Ref(
        'Kakoli Das',
        'Seen 18 Sep',
        'From Dr. Anjan Basu · General medicine · Newly found diabetes',
        '15 Sep',
        seen: true,
      ),
      _Ref(
        'Haripada Saha',
        'Seen 5 Sep',
        'From Dr. Anjan Basu · General medicine · BP not controlled',
        '3 Sep',
        seen: true,
      ),
    ],
  ),
];

class _ReportReferralsScreenState extends State<ReportReferralsScreen> with LiveData, D3FilterState {
  int _tab = 0;
  final _more = [false, false];
  static const _shown = 4;

  /// Both directions at once, so switching tabs needs no fetch.
  @override
  Future<Object?> fetch() async {
    final f = await loadFilters();
    // Period and locations are applied by the server too.
    final r = await Future.wait([
      Api.I.get('/api/referrals', query: {...f.query, 'direction': 'sent'}),
      Api.I.get('/api/referrals', query: {...f.query, 'direction': 'received'}),
    ]);
    return {'sent': r[0], 'received': r[1]};
  }

  /// Referrals of one direction made in the chosen period, newest first.
  /// (GET /api/referrals has no date range, so the period is applied here.)
  List<Map<String, dynamic>> _items(String dir) {
    final (from, to) = filters.days;
    final out = [
      for (final r in data!.obj(dir).list('items'))
        if (d3Day(r['referredAt']) case final d? when !d.isBefore(from) && !d.isAfter(to)) r,
    ];
    out.sort((a, b) => b.str('referredAt').compareTo(a.str('referredAt')));
    return out;
  }

  _Ref _refOf(Map<String, dynamic> r, String dir) {
    final p = r['patientId'] is Map ? (r['patientId'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final seen = r['status'] == 'seen';
    final seenAt = d3Day(r['seenAt']);
    final at = d3Day(r['referredAt']);
    final detail = [
      '${dir == 'sent' ? 'To' : 'From'} ${r.str('counterpartName')}',
      r.str('specialty'),
      r.str('reason'),
    ].where((s) => s.trim().isNotEmpty && s.trim() != 'To' && s.trim() != 'From').join(' · ');
    return _Ref(
      p.str('name', 'Patient'),
      r['status'] == 'cancelled' ? 'Cancelled' : (seen ? (seenAt == null ? 'Seen' : 'Seen ${F.dayMonth(seenAt)}') : 'Awaiting'),
      detail,
      at == null ? '' : F.dayMonth(at),
      seen: seen,
      cancelled: r['status'] == 'cancelled',
    );
  }

  /// The design's direction view, built from live referrals.
  _Dir _liveDir(int i) {
    final dir = i == 0 ? 'sent' : 'received';
    final items = _items(dir);
    // Cancelled ones stay in the list but don't count.
    final live = items.where((r) => r['status'] != 'cancelled').toList();
    final seen = live.where((r) => r['status'] == 'seen').length;
    final awaiting = live.where((r) => r['status'] == 'awaiting').length;
    final by = <String, int>{};
    for (final r in live) {
      final s = r.str('specialty', 'Other');
      by[s.isEmpty ? 'Other' : s] = (by[s.isEmpty ? 'Other' : s] ?? 0) + 1;
    }
    final bars = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final refs = [for (final r in items) _refOf(r, dir)];
    return _Dir(
      tab: '${i == 0 ? 'Sent' : 'Received'} · ${live.length}',
      stats: [
        (F.count(live.length), i == 0 ? 'Sent' : 'Received', MP.ink),
        (F.count(seen), i == 0 ? 'Seen by them' : 'Seen by you', MP.green),
        (F.count(awaiting), 'Awaiting', MP.amber),
      ],
      barTitle: i == 0 ? 'Sent to' : 'Received from',
      bars: [for (final b in bars) D3BarRow(b.key, F.count(b.value), live.isEmpty ? 0 : b.value / live.length)],
      listTitle: i == 0 ? 'All sent' : 'All received',
      rows: refs.take(_shown).toList(),
      more: refs.skip(_shown).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    final live = isLive;
    final dirs = data == null ? _dirs : [_liveDir(0), _liveDir(1)];
    final d = dirs[_tab];
    final rows = [...d.rows, if (_more[_tab]) ...d.more];
    final rawRows = data == null ? null : _items(_tab == 0 ? 'sent' : 'received');
    final total = data == null ? 0 : [..._items('sent'), ..._items('received')].where((r) => r['status'] != 'cancelled').length;
    return MpPage(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          live
              ? D3ReportHeader(
                title: 'Referrals',
                subtitle: data == null ? filters.label : '${d3Plural(total, 'referral')} · ${filters.label}',
                rangeLabel: filters.label,
                locationLabel: filters.locationLabel,
                onFilters: pickFilters,
              )
              : const D3ReportHeader(title: 'Referrals', subtitle: '15 referrals · 1 – 30 Sep'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: D3Tabs(
              options: [for (final x in dirs) x.tab],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
        ],
      ),
      bottom: live
          ? D3DownloadBar('Download report', reportType: 'referrals', filters: filters)
          : const D3DownloadBar('Download report'),
      body: placeholder ?? VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          D3StatTiles(d.stats),
          if (d.bars.isNotEmpty) D3BarCard(title: d.barTitle, note: 'Referrals', rows: d.bars),
          if (live) MpButton('Add a referral', kind: MpBtn.secondary, icon: I.plus, onTap: _add),
          D3SectionHead(d.listTitle, trailing: 'Newest first'),
          if (rows.isNotEmpty)
            D3ListCard(children: [for (var i = 0; i < rows.length; i++) _row(rows[i], rawRows?[i])])
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                _tab == 0 ? 'No referrals sent in this period.' : 'No referrals received in this period.',
                style: tx(14, c: MP.ink3, h: 1.45),
              ),
            ),
          if (!_more[_tab] && d.more.isNotEmpty)
            D3ShowMore('Show ${d.more.length} more', onTap: () => setState(() => _more[_tab] = true)),
        ],
      ),
    );
  }

  Widget _row(_Ref r, [Map<String, dynamic>? raw]) {
    final p = raw?['patientId'];
    return D3RegisterRow(
      name: r.name,
      trailing: D3Badge(r.status, tone: r.cancelled ? D3Tone.grey : r.seen ? D3Tone.green : D3Tone.amber),
      detail: r.detail,
      footer: Text(r.date, style: tx(13, c: MP.ink3)),
      onTap: raw == null ? () => Nav.go(context, 'PP-Summary') : () => _open(r, raw, p is Map ? '${p['id']}' : null),
    );
  }

  Future<void> _add() async {
    final ok = await openSheet<bool>(context, (_) => _AddReferralSheet(direction: _tab == 0 ? 'sent' : 'received'));
    if (ok == true && mounted) {
      toast(context, 'Referral added');
      reload(quiet: true);
    }
  }

  /// A referral: mark it seen, or open the patient.
  Future<void> _open(_Ref r, Map<String, dynamic> raw, String? patientId) async {
    final action = await openSheet<String>(
      context,
      (_) => MpSheet(
        title: r.name,
        subtitle: [r.detail, r.date].where((x) => x.isNotEmpty).join(' · '),
        showClose: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: VGap(
            gap: 12,
            children: [
              if (raw['status'] == 'awaiting')
                MpButton(_tab == 0 ? 'They have seen the patient' : 'I have seen the patient', icon: I.check, onTap: () => Navigator.pop(context, 'seen')),
              if (patientId != null) MpButton('Open patient record', kind: MpBtn.secondary, onTap: () => Navigator.pop(context, 'patient')),
              if (raw['status'] == 'awaiting') MpButton('Cancel referral', kind: MpBtn.danger, onTap: () => Navigator.pop(context, 'cancel')),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'patient') {
      Nav.go(context, 'PP-Summary', args: {'patientId': patientId, 'referralId': raw['id']});
      return;
    }
    final cancel = action == 'cancel';
    final done = await runAction(context, () => Api.I.post('/api/referrals/${raw['id']}/${cancel ? 'cancel' : 'seen'}', {}));
    if (done != null && mounted) {
      toast(context, cancel ? 'Referral cancelled' : 'Marked as seen');
      reload(quiet: true);
    }
  }
}

/// Add a referral: sent to another doctor, or received from one.
/// "Referred to / by" finds doctors on MedPin at any clinic as you type
/// (GET /api/reports/referral-doctors); Specialty and Reason offer tap-chips
/// from GET /api/reports/referral-suggestions (the chosen patient's abnormal
/// labs, out-of-range readings, diagnoses and conditions). All stay typeable.
class _AddReferralSheet extends StatefulWidget {
  final String direction;
  const _AddReferralSheet({required this.direction});
  @override
  State<_AddReferralSheet> createState() => _AddReferralSheetState();
}

class _AddReferralSheetState extends State<_AddReferralSheet> {
  late String _dir = widget.direction;
  String? _patientId;
  // The Patient field shows the chosen name (a controller, so it updates when picked).
  final _patient = TextEditingController();
  final _who = TextEditingController();
  final _specialty = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;

  // Doctors on MedPin matching "Referred to / by"; the one picked and the text it filled
  // (typing over it makes it a free-text name again).
  Timer? _whoTimer;
  List<Map<String, dynamic>> _doctors = const [];
  String? _doctorId;
  String? _doctorLabel;

  // Suggestions: specialties (always) and reasons from the chosen patient's record.
  List<String> _specialties = const [];
  List<Map<String, dynamic>> _reasons = const [];
  static const _specialtyChips = 10;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _whoTimer?.cancel();
    for (final c in [_patient, _who, _specialty, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final id = await pickPatient(context, title: 'Who is referred?');
    if (id == null || !mounted) return;
    setState(() {
      _patientId = id;
      _patient.text = 'Patient chosen';
      _reasons = const [];
    });
    _loadSuggestions();
    try {
      final p = await Api.I.get('/api/patients/$id');
      final name = p is Map ? ((p['patient'] is Map ? p['patient']['name'] : null) ?? p['name']) : null;
      if (mounted && name != null) setState(() => _patient.text = '$name');
    } on ApiException {
      // The id is enough to save.
    }
  }

  Future<void> _loadSuggestions() async {
    final id = _patientId;
    try {
      final r = await Api.I.get('/api/reports/referral-suggestions', query: {if (id != null) 'patientId': id});
      // A reply for a patient no longer chosen is dropped.
      if (!mounted || id != _patientId || r is! Map) return;
      setState(() {
        _specialties = [for (final s in (r['specialties'] as List? ?? const [])) '$s'];
        _reasons = [
          for (final x in (r['reasons'] as List? ?? const []))
            if (x is Map && '${x['text'] ?? ''}'.trim().isNotEmpty) x.cast<String, dynamic>(),
        ];
      });
    } catch (_) {
      // Offline: no chips, the fields are still typeable.
    }
  }

  void _onWho(String text) {
    _whoTimer?.cancel();
    final q = text.trim();
    setState(() {
      if (_doctorId != null && q != _doctorLabel) {
        _doctorId = null;
        _doctorLabel = null;
      }
      if (q.length < 2) _doctors = const [];
    });
    if (q.length < 2 || _doctorId != null) return;
    _whoTimer = Timer(const Duration(milliseconds: 300), () => _searchDoctors(q));
  }

  Future<void> _searchDoctors(String q) async {
    try {
      final r = await Api.I.get('/api/reports/referral-doctors', query: {'q': q});
      // A reply for older text (they kept typing) is dropped.
      if (!mounted || _who.text.trim() != q || r is! Map) return;
      setState(() => _doctors = [
        for (final x in (r['items'] as List? ?? const []))
          if (x is Map && '${x['name'] ?? ''}'.trim().isNotEmpty) x.cast<String, dynamic>(),
      ].take(5).toList());
    } catch (_) {
      // Offline: just no suggestions; any name can still be typed.
      if (mounted && _doctors.isNotEmpty) setState(() => _doctors = const []);
    }
  }

  /// A MedPin doctor: their name and clinic, and their specialty.
  void _pickDoctor(Map<String, dynamic> d) {
    _whoTimer?.cancel();
    final label = [d.str('name'), d.str('clinic')].where((s) => s.trim().isNotEmpty).join(' · ');
    final spec = d.str('specialty');
    setState(() {
      _who.text = label;
      _who.selection = TextSelection.collapsed(offset: label.length);
      _doctorId = d.str('id');
      _doctorLabel = label;
      _doctors = const [];
      if (spec.isNotEmpty) _specialty.text = spec;
    });
    FocusScope.of(context).unfocus();
  }

  List<String> get _reasonParts => [for (final p in _reason.text.split(',')) if (p.trim().isNotEmpty) p.trim()];
  bool _hasReason(String text) => _reasonParts.any((p) => p.toLowerCase() == text.toLowerCase());

  /// A reason chip adds its text to Reason (tap again to take it out); its
  /// specialty fills Specialty when that is still empty.
  void _toggleReason(Map<String, dynamic> x) {
    final text = x.str('text').trim();
    final had = _hasReason(text);
    final parts = had ? _reasonParts.where((p) => p.toLowerCase() != text.toLowerCase()).toList() : [..._reasonParts, text];
    setState(() {
      _reason.text = parts.join(', ');
      _reason.selection = TextSelection.collapsed(offset: _reason.text.length);
      final spec = x.str('specialty');
      if (!had && spec.isNotEmpty && _specialty.text.trim().isEmpty) _specialty.text = spec;
    });
  }

  void _pickSpecialty(String s) => setState(() {
    _specialty.text = s;
    _specialty.selection = TextSelection.collapsed(offset: s.length);
  });

  Future<void> _speakReason() async {
    final said = await dictateInto(context, _reason, title: 'Reason for referral');
    if (said != null && mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_patientId == null) return toast(context, 'Choose the patient');
    if (_who.text.trim().isEmpty) return toast(context, _dir == 'sent' ? 'Enter who you referred to' : 'Enter who referred them');
    setState(() => _saving = true);
    final r = await runAction(
      context,
      () => Api.I.post('/api/referrals', {
        'patientId': _patientId,
        'direction': _dir,
        'counterpartName': _who.text.trim(),
        // The other doctor is on MedPin.
        if (_doctorId != null) 'counterpartUserId': _doctorId,
        if (_specialty.text.trim().isNotEmpty) 'specialty': _specialty.text.trim(),
        if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
      }),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) Navigator.pop(context, true);
  }

  /// Tap-chips under a field (long suggestions are shortened to fit a line).
  Widget _chips(List<(String, bool, VoidCallback)> items) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (label, selected, onTap) in items)
        MpChip(
          label.length > 38 ? '${label.substring(0, 37)}…' : label,
          selected: selected,
          tonal: true,
          height: 34,
          fontSize: 13,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onTap: onTap,
        ),
    ],
  );

  Widget _doctorHits() => Container(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: MP.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in _doctors)
          Tap(
            onTap: () => _pickDoctor(d),
            radius: 10,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Ico(I.stethoscope, size: 16, color: MP.ink3)),
                const Gap(8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: w600, h: 1.35)),
                      if ([d.str('specialty'), d.str('clinic')].any((s) => s.isNotEmpty))
                        Text(
                          [d.str('specialty'), d.str('clinic')].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tx(13, c: MP.ink2, h: 1.35),
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

  @override
  Widget build(BuildContext context) {
    final sent = _dir == 'sent';
    final spec = _specialty.text.trim().toLowerCase();
    return MpSheet(
      title: 'Add a referral',
      subtitle: 'It shows here and in the downloaded report.',
      showClose: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: VGap(
          gap: 16,
          children: [
            MpSegmented(
              options: const ['Sent', 'Received'],
              index: sent ? 0 : 1,
              height: 40,
              fontSize: 14,
              onChanged: (i) => setState(() => _dir = i == 0 ? 'sent' : 'received'),
            ),
            MpInput(
              label: 'Patient',
              controller: _patient,
              hint: 'Choose a patient',
              readOnly: true,
              onTap: _pick,
              trailing: const Padding(padding: EdgeInsets.only(right: 12), child: Ico(I.chevronRight, size: 18, color: MP.ink3)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MpInput(
                  label: sent ? 'Referred to' : 'Referred by',
                  controller: _who,
                  hint: 'Search doctors on MedPin, or type a name',
                  onChanged: _onWho,
                ),
                if (_doctors.isNotEmpty) ...[const Gap(8), _doctorHits()],
                if (_doctorId != null) ...[
                  const Gap(8),
                  Row(
                    children: [
                      const Ico(I.check, size: 16, color: MP.green, stroke: 2.25),
                      const Gap(6),
                      Expanded(child: Text('On MedPin', style: tx(13, c: MP.ink3))),
                    ],
                  ),
                ],
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MpInput(label: 'Specialty', controller: _specialty, hint: 'e.g. Cardiology', onChanged: (_) => setState(() {})),
                if (_specialties.isNotEmpty) ...[
                  const Gap(10),
                  _chips([
                    for (final s in _specialties.take(_specialtyChips)) (s, s.toLowerCase() == spec, () => _pickSpecialty(s)),
                  ]),
                ],
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MpInput(
                  label: 'Reason',
                  controller: _reason,
                  hint: 'e.g. Rising creatinine',
                  maxLines: 2,
                  height: 80,
                  onChanged: (_) => setState(() {}),
                  trailing: _MicButton(label: 'Speak the reason', onTap: _speakReason),
                ),
                if (_reasons.isNotEmpty) ...[
                  const Gap(10),
                  Text("From the patient's record", style: tx(13, c: MP.ink3)),
                  const Gap(8),
                  _chips([
                    for (final x in _reasons) (x.str('text'), _hasReason(x.str('text').trim()), () => _toggleReason(x)),
                  ]),
                ],
              ],
            ),
            MpButton(_saving ? 'Saving…' : 'Save', onTap: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}

/// Mic in the top-right of the Reason field (as on Add patient's address).
class _MicButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MicButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
    child: MpIconButton(I.mic, label: label, iconSize: 20, color: MP.primary, background: MP.primarySoft, onTap: onTap),
  );
}

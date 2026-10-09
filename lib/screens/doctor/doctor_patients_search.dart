import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d2.dart';

/// Design: Doctor-Patients-Search.dc.html — "Doctor · Patients · search by name or mobile".
class DoctorPatientsSearchScreen extends StatefulWidget {
  const DoctorPatientsSearchScreen({super.key});

  @override
  State<DoctorPatientsSearchScreen> createState() => _DoctorPatientsSearchScreenState();
}

class _P {
  final String name;
  final String phone;
  final String meta;

  /// Live: the patient's id.
  final String? id;
  const _P(this.name, this.phone, this.meta, [this.id]);

  String get initials {
    final s = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).join();
    return s.length > 2 ? s.substring(0, 2) : s;
  }
}

/// Recent searches typed on this device this session (live).
final _liveRecent = <String>[];

/// Searchable patients. The first two are the design's results for "98765".
const _all = [
  _P('Priya Sharma', '98765 43210', '29 F · Type 2 diabetes · seen today'),
  _P('Sneha Ghosh', '98765 07731', '47 F · Hypertension · seen 12 Jun'),
  _P('Rahul Das', '98311 20764', '45 M · High BP · seen today'),
  _P('Aisha Khan', '90070 41288', '52 F · Hypothyroidism · seen today'),
  _P('Debasish Bose', '98740 33126', '62 M · Type 2 diabetes · seen today'),
  _P('Farhana Islam', '90511 72830', '34 F · Anaemia · seen today'),
  _P('Amit Pal', '98303 11942', '55 M · Type 2 diabetes, CKD · seen 24 Sep'),
  _P('Moumita Roy', '97480 62215', '41 F · Cardiology review · seen 02 Sep'),
  _P('Sujit Mondal', '98362 50417', '37 M · Fever, cough · seen today'),
];

const _recent = ['Amit Pal', 'Moumita', '97480 62215'];

/// Match range of [q] inside [name] (case-insensitive).
(int, int)? _nameHit(String name, String q) {
  final i = name.toLowerCase().indexOf(q.toLowerCase());
  return i < 0 ? null : (i, i + q.length);
}

/// Match range of a digits-only query inside a spaced phone number.
(int, int)? _phoneHit(String phone, String q) {
  var digits = q.replaceAll(RegExp(r'[\s-]'), '');
  if (digits.startsWith('+91')) digits = digits.substring(3);
  if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;
  final at = <int>[];
  final buf = StringBuffer();
  for (var i = 0; i < phone.length; i++) {
    final c = phone.codeUnitAt(i);
    if (c >= 48 && c <= 57) {
      at.add(i);
      buf.writeCharCode(c);
    }
  }
  final k = buf.toString().indexOf(digits);
  if (k < 0) return null;
  return (at[k], at[k + digits.length - 1] + 1);
}

class _DoctorPatientsSearchScreenState extends State<DoctorPatientsSearchScreen> with LiveData {
  final _q = TextEditingController(text: isLive ? '' : '98765');
  final _focus = FocusNode();
  Timer? _debounce;
  String _lastQ = '';

  /// The query the current [data] answers.
  String _answered = '';

  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      setState(() {});
      final q = _q.text.trim();
      if (!isLive || q == _lastQ) return;
      _lastQ = q;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) reload(quiet: true);
      });
    });
  }

  @override
  Future<Object?> fetch() async {
    final q = _q.text.trim();
    if (q.isEmpty) return {'items': const [], 'q': ''};
    final res = await Api.I.get('/api/patients', query: {'q': q, 'limit': 30});
    return {...(res as Map).cast<String, dynamic>(), 'q': q};
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setQuery(String v) {
    _q.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
  }

  void _remember(String q) {
    if (!isLive || q.isEmpty) return;
    _liveRecent
      ..remove(q)
      ..insert(0, q);
    if (_liveRecent.length > 5) _liveRecent.removeLast();
  }

  List<_P> get _pool {
    final d = data;
    if (d == null) return _all;
    _answered = d.str('q');
    return [
      for (final p in d.list('items'))
        _P(
          p.str('name'),
          d2Phone(p.str('phone')),
          [
            d2AgeSex(p),
            [for (final c in (p['conditions'] as List? ?? const [])) '$c'].join(', '),
            if (p['lastVisitAt'] != null) 'seen ${d2LastSeen(p['lastVisitAt']).toLowerCase()}',
          ].where((s) => s.isNotEmpty).join(' · '),
          p.str('id'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final pool = _pool;
    final searching = isLive && q != _answered;
    final recent = isLive ? _liveRecent : _recent;
    final hits = <(_P, (int, int)?, (int, int)?)>[
      if (q.isNotEmpty && !searching)
        for (final p in pool)
          if (isLive || _nameHit(p.name, q) != null || _phoneHit(p.phone, q) != null)
            (p, _nameHit(p.name, q), _phoneHit(p.phone, q)),
    ];
    return MpPage(
      header: _header(context),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        gap: 16,
        children: [
          if (isLive && loadError != null && q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(loadError!.message, style: tx(14, c: MP.ink2)),
            )
          else if (q.isNotEmpty && !searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: D2Caps('${hits.length} ${hits.length == 1 ? 'match' : 'matches'} for “$q”'),
            ),
          if (hits.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: MPDeco.card(),
              child: Column(children: [for (var i = 0; i < hits.length; i++) _result(context, hits[i], first: i == 0)]),
            ),
          if (q.isNotEmpty && !searching) _notFoundCard(context),
          if (recent.isNotEmpty) Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: D2Caps('Recent searches')),
              const Gap(10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final r in recent) D2Chip(r, weight: w500, onTap: () => _setQuery(r))],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
      decoration: const BoxDecoration(color: MP.white, border: Border(bottom: BorderSide(color: MP.line))),
      child: Row(
        children: [
          MpIconButton(I.back, label: 'Back', onTap: () => Nav.back(context)),
          const Gap(4),
          Expanded(
            child: Container(
              height: 52,
              padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
              decoration: BoxDecoration(
                color: MP.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MP.primary, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _q,
                      focusNode: _focus,
                      style: tx(16, w: w500, tab: true),
                      cursorColor: MP.primary,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) => setState(() => _remember(v.trim())),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search by name or mobile number',
                        hintStyle: tx(16, c: MP.ink3),
                      ),
                    ),
                  ),
                  if (_q.text.isNotEmpty) ...[
                    const Gap(10),
                    MpIconButton(
                      I.close,
                      label: 'Clear search',
                      size: 40,
                      iconSize: 18,
                      stroke: 2,
                      color: MP.ink2,
                      onTap: () {
                        _q.clear();
                        _focus.requestFocus();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, (_P, (int, int)?, (int, int)?) hit, {required bool first}) {
    final (p, nameHit, phoneHit) = hit;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MpAvatar(p.initials, size: 44, fontSize: 15),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Marked(p.name, nameHit, tx(16, w: w700)),
                    const Gap(2),
                    _Marked(p.phone, phoneHit, tx(14, c: MP.ink2, tab: true), prefix: '+91 '),
                    const Gap(2),
                    Text(p.meta, style: tx(13, c: MP.ink3)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          D2ViewConsult(
            onView: () {
              _remember(_q.text.trim());
              Nav.go(context, 'PP-Summary', args: p.id == null ? null : {'patientId': p.id});
            },
            onConsult: () {
              _remember(_q.text.trim());
              Nav.go(context, 'Consult-Page', args: p.id == null ? null : {'patientId': p.id});
            },
          ),
        ],
      ),
    );
  }

  Widget _notFoundCard(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _DashedBorder(color: MP.lineStrong, radius: 20),
      child: Container(
        // padding 18 + the 1px dashed border
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(color: MP.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not the patient you’re looking for?', style: tx(15, w: w700)),
            const Gap(4),
            Text(
              'Add them with this number and start a consultation straight away.',
              style: tx(14, c: MP.ink2, h: 1.45),
            ),
            const Gap(12),
            D2PillButton(
              'Add new patient',
              icon: I.plus,
              fontSize: 15,
              onTap: () => Nav.go(context, 'Consult-QuickAdd'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text with the matched part drawn like the design's <mark>:
/// #EBF1FB background, #003399 / 700 text, radius 4, padding 0 2.
class _Marked extends StatelessWidget {
  final String text;
  final (int, int)? hit;
  final TextStyle style;
  final String prefix;
  const _Marked(this.text, this.hit, this.style, {this.prefix = ''});

  @override
  Widget build(BuildContext context) {
    final h = hit;
    if (h == null) return Text('$prefix$text', style: style);
    final (s, e) = h;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '$prefix${text.substring(0, s)}'),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: MP.primarySoft, borderRadius: BorderRadius.circular(4)),
              child: Text(text.substring(s, e), style: style.copyWith(color: MP.primary, fontWeight: w700)),
            ),
          ),
          TextSpan(text: text.substring(e)),
        ],
      ),
    );
  }
}

/// 1px dashed rounded border (Chrome draws 1px dashes as 3px on, 2px off).
class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorder({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
        d += 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

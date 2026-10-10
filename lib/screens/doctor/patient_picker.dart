import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';

/// "Choose a patient" sheet for screens opened without one (quick actions
/// such as Prescriptions, Test results, Record vitals, Follow-ups).
/// Search by name or mobile; recent patients first. Returns the patient id.
Future<String?> pickPatient(BuildContext context, {String title = 'Choose a patient'}) {
  return openSheet<String>(context, (_) => _PatientPicker(title: title));
}

/// For a screen's fetch(): [id] if it was passed, else asks with the picker.
/// When the user cancels, the screen closes.
Future<String> patientOrPick(BuildContext context, String? id, {String title = 'Choose a patient'}) async {
  if (id != null && id.isNotEmpty) return id;
  final picked = context.mounted ? await pickPatient(context, title: title) : null;
  if (picked != null) return picked;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) Navigator.of(context).maybePop();
  });
  throw const ApiException(400, 'NO_PATIENT', 'Choose a patient');
}

class _PatientPicker extends StatefulWidget {
  final String title;
  const _PatientPicker({required this.title});

  @override
  State<_PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends State<_PatientPicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = _q.text.trim();
      final r = await Api.I.get('/api/patients', query: {'limit': '20', 'sort': 'recent', if (q.isNotEmpty) 'q': q});
      if (!mounted) return;
      setState(() {
        _items = (r is Map ? r : const {}).cast<String, dynamic>().list('items');
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false));
    }
  }

  static String _meta(Map<String, dynamic> p) {
    final g = p.str('gender');
    final phone = p.str('phone');
    return [
      [if (p['age'] != null) '${p['age']}', if (g.isNotEmpty) g[0].toUpperCase()].join(' '),
      if (phone.length == 10) '+91 ${phone.substring(0, 5)} ${phone.substring(5)}',
    ].where((x) => x.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MpInput(controller: _q, hint: 'Search by name or mobile number', leadingIcon: I.search, autofocus: false),
          const Gap(12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: _loading && _items.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary)))
                : _error != null
                    ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center, style: tx(14, c: MP.ink2)))
                    : _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_q.text.trim().isEmpty ? 'No patients yet' : 'No patient matches "${_q.text.trim()}"', textAlign: TextAlign.center, style: tx(14, c: MP.ink2)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: MP.line),
                            itemBuilder: (_, i) {
                              final p = _items[i];
                              return Tap(
                                onTap: () => Navigator.of(context).pop(p.str('id')),
                                radius: 12,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                child: Row(
                                  children: [
                                    MpAvatar(_initials(p.str('name')), size: 40, fontSize: 14),
                                    const Gap(12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(p.str('name', 'Patient'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: w600)),
                                          if (_meta(p).isNotEmpty) Text(_meta(p), style: tx(13, c: MP.ink3)),
                                        ],
                                      ),
                                    ),
                                    const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

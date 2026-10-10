import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/session.dart';
import '../../widgets/mp.dart';
import '../doctor/common_d11.dart';
import 'common_a1.dart';

/// "I'm a doctor" — start a clinic: about you, the clinic, hours and fee.
/// Creates the practice, its first location and the doctor's schedule there
/// (POST /api/me/practices), so patients can book straight away.
class AuthClinicSetupScreen extends StatefulWidget {
  const AuthClinicSetupScreen({super.key});

  @override
  State<AuthClinicSetupScreen> createState() => _AuthClinicSetupScreenState();
}

const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _AuthClinicSetupScreenState extends State<AuthClinicSetupScreen> {
  final _name = TextEditingController(text: Session.I.name);
  final _quals = TextEditingController();
  final _reg = TextEditingController();
  final _clinic = TextEditingController();
  final _area = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController(text: 'Kolkata');
  final _pincode = TextEditingController();
  final _clinicPhone = TextEditingController();
  final _fee = TextEditingController(text: '500');

  /// (key, label) from the specialty catalog.
  List<(String, String)> _specialties = const [('general', 'General physician')];
  String? _specialty;
  final Set<String> _open = {'mon', 'tue', 'wed', 'thu', 'fri', 'sat'};
  String _opens = '09:00';
  String _closes = '20:00';
  bool _agree = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!AppMode.preview) _loadSpecialties();
  }

  Future<void> _loadSpecialties() async {
    try {
      final list = await Api.I.get('/api/catalog/specialties') as List;
      if (!mounted || list.isEmpty) return;
      setState(() => _specialties = [for (final s in list) ('${(s as Map)['key']}', '${s['label']}')]);
    } on ApiException {
      // Keep the default; the specialty can be set later in Professional details.
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _quals, _reg, _clinic, _area, _address, _city, _pincode, _clinicPhone, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  static int _minutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String? _problem() {
    if (_name.text.trim().length < 3) return 'Enter your full name';
    if (_clinic.text.trim().length < 2) return 'Enter the clinic name';
    if (_area.text.trim().isEmpty) return 'Enter the area, e.g. Salt Lake';
    if (_pincode.text.trim().isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(_pincode.text.trim())) return 'Pincode must be 6 digits';
    if (_clinicPhone.text.trim().isNotEmpty && _clinicPhone.text.replaceAll(RegExp(r'\D'), '').length != 10) return 'Clinic phone must be 10 digits';
    if (_open.isEmpty) return 'Choose at least one open day';
    if (_minutes(_closes) - _minutes(_opens) < 30) return 'Closing time must be after opening time';
    final fee = num.tryParse(_fee.text.trim());
    if (fee == null || fee < 0 || fee > 100000) return 'Enter the consultation fee in rupees';
    if (!_agree) return 'Please agree to the Terms of Use and Privacy Policy';
    return null;
  }

  Future<void> _create() async {
    final problem = _problem();
    if (problem != null) {
      toast(context, problem);
      return;
    }
    if (AppMode.preview) {
      Nav.reset(context, 'Doctor-Dashboard');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Api.I.post('/api/me/practices', {
        'doctorName': _name.text.trim(),
        'specialtyKey': _specialty ?? _specialties.first.$1,
        if (_quals.text.trim().isNotEmpty) 'qualifications': _quals.text.trim(),
        if (_reg.text.trim().isNotEmpty) 'registrationNo': _reg.text.trim(),
        'name': _clinic.text.trim(),
        'area': _area.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
        if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        if (_pincode.text.trim().isNotEmpty) 'pincode': _pincode.text.trim(),
        if (_clinicPhone.text.trim().isNotEmpty) 'clinicPhone': _clinicPhone.text.trim(),
        'openDays': [for (final d in _days) if (_open.contains(d)) d],
        'opensAt': _minutes(_opens),
        'closesAt': _minutes(_closes),
        'fee': num.parse(_fee.text.trim()),
        'termsAccepted': true,
      });
      await Session.I.reloadAccount();
      if (!mounted) return;
      toast(context, 'Your clinic is ready');
      Nav.reset(context, Session.I.landing);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Opens at 9:00 AM" — tap to pick from half-hour times.
  Widget _time(String label, String value, void Function(String) set) {
    final labels = [for (final t in d11Times) d11Clock(t)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        A1Label(label),
        const Gap(8),
        MpSelect(
          value: d11Clock(value),
          options: labels,
          leadingIcon: I.clock,
          onChanged: (v) => setState(() => set(d11Times[labels.indexOf(v)])),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? keyboard, bool optional = false, String? prefix}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          A1Label(label, optional: optional),
          const Gap(8),
          MpInput(controller: c, hint: hint, keyboard: keyboard, prefixText: prefix),
          const Gap(16),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final specLabels = [for (final s in _specialties) s.$2];
    final specLabel = _specialties.firstWhere((s) => s.$1 == _specialty, orElse: () => _specialties.first).$2;
    return MpPage(
      header: const MpHeader('Start your clinic'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Takes about 2 minutes. You can change everything later in My profile.', style: tx(14, c: MP.ink2, h: 1.45)),
            const Gap(20),
            const A1Step('1 · About you'),
            const Gap(12),
            _field('Full name', _name, hint: 'Dr. Ananya Sen', keyboard: TextInputType.name),
            const A1Label('Specialty'),
            const Gap(8),
            MpSelect(
              value: specLabel,
              options: specLabels,
              onChanged: (v) => setState(() => _specialty = _specialties.firstWhere((s) => s.$2 == v).$1),
            ),
            const Gap(16),
            _field('Qualifications', _quals, hint: 'MBBS, MD (Medicine)', optional: true),
            _field('Medical registration number', _reg, hint: 'WBMC 12345', optional: true),
            const Gap(8),
            const A1Step('2 · Your clinic'),
            const Gap(12),
            _field('Clinic name', _clinic, hint: 'Sen Diabetes Clinic'),
            _field('Area', _area, hint: 'Salt Lake'),
            _field('Address', _address, hint: 'House no, street, landmark', optional: true),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field('City', _city)),
                const Gap(12),
                Expanded(child: _field('Pincode', _pincode, keyboard: TextInputType.number, optional: true)),
              ],
            ),
            _field('Clinic phone', _clinicPhone, keyboard: TextInputType.phone, optional: true, prefix: '+91'),
            const Gap(8),
            const A1Step('3 · Hours and fee'),
            const Gap(12),
            const A1Label('Open days'),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _days.length; i++)
                  MpChip(
                    _dayLabels[i],
                    selected: _open.contains(_days[i]),
                    onTap: () => setState(() => _open.contains(_days[i]) ? _open.remove(_days[i]) : _open.add(_days[i])),
                  ),
              ],
            ),
            const Gap(16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _time('Opens at', _opens, (v) => _opens = v)),
                const Gap(12),
                Expanded(child: _time('Closes at', _closes, (v) => _closes = v)),
              ],
            ),
            const Gap(16),
            _field('Consultation fee', _fee, keyboard: TextInputType.number, prefix: '₹'),
            const Gap(8),
            A1Terms(value: _agree, onChanged: (v) => setState(() => _agree = v)),
            const Gap(24),
            MpButton(_busy ? 'Creating…' : 'Create my clinic', onTap: _busy ? null : _create),
          ],
        ),
      ),
    );
  }
}

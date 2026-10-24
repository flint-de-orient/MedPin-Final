import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/config.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';
import '../../widgets/i18n.dart';

/// Doctor · Payouts and bank account — where online consultation fees are paid.
/// Live data: GET/PATCH /api/doctor/profile (payout). Only the last 4 digits of
/// the account number are kept on MedPin.
///
/// Details are checked as they are typed: the IFSC is looked up
/// (GET /api/banks/ifsc/:code, RBI directory) and fills in the bank and
/// branch; the UPI ID's handle names its app and bank (GET /api/banks/upi);
/// a new account number is typed twice.
class ProfilePayoutsScreen extends StatefulWidget {
  const ProfilePayoutsScreen({super.key});

  @override
  State<ProfilePayoutsScreen> createState() => _ProfilePayoutsScreenState();
}

class _ProfilePayoutsScreenState extends State<ProfilePayoutsScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  String _preferred = 'upi';
  final _upi = TextEditingController(text: 'arjunsen@okhdfcbank');
  final _holder = TextEditingController(text: 'Arjun Sen');
  final _bank = TextEditingController(text: 'HDFC Bank');
  final _account = TextEditingController();
  final _ifsc = TextEditingController(text: 'HDFC0001234');
  final _account2 = TextEditingController();
  String? _last4 = '6789';

  // What the IFSC and UPI ID were found to be (null: not checked yet).
  Map<String, dynamic>? _ifscInfo =
      AppMode.preview ? {'valid': true, 'found': true, 'bank': 'HDFC Bank', 'branch': 'Salt Lake', 'city': 'Kolkata'} : null;
  bool _ifscChecking = false;
  Map<String, dynamic>? _upiInfo = AppMode.preview ? {'valid': true, 'known': true, 'app': 'Google Pay'} : null;
  Timer? _ifscTimer;
  Timer? _upiTimer;
  String _ifscAsked = AppMode.preview ? 'HDFC0001234' : '';

  @override
  void initState() {
    super.initState();
    _ifsc.addListener(_onIfsc);
    _upi.addListener(_onUpi);
    _account.addListener(_onAccount);
    _account2.addListener(_onAccount);
  }

  void _onAccount() => setState(() {});

  /// Looks the IFSC up once all 11 characters are typed.
  void _onIfsc() {
    final code = _ifsc.text.trim().toUpperCase();
    if (code == _ifscAsked) return;
    _ifscAsked = code;
    _ifscTimer?.cancel();
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(code)) {
      setState(() {
        _ifscInfo = code.length >= 11 ? const {'valid': false} : null;
        _ifscChecking = false;
      });
      return;
    }
    if (!isLive) return;
    setState(() => _ifscChecking = true);
    _ifscTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = (await Api.I.get('/api/banks/ifsc/$code') as Map).cast<String, dynamic>();
        if (!mounted || _ifsc.text.trim().toUpperCase() != code) return;
        setState(() {
          _ifscInfo = r;
          // The IFSC decides the bank.
          if (r['bank'] is String) _bank.text = r['bank'] as String;
        });
      } catch (_) {
        if (mounted) setState(() => _ifscInfo = const {'valid': true, 'found': null});
      } finally {
        if (mounted) setState(() => _ifscChecking = false);
      }
    });
  }

  void _onUpi() {
    final vpa = _upi.text.trim();
    _upiTimer?.cancel();
    if (!vpa.contains('@') || vpa.endsWith('@')) {
      if (_upiInfo != null) setState(() => _upiInfo = null);
      return;
    }
    if (!isLive) return;
    _upiTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = (await Api.I.get('/api/banks/upi', query: {'vpa': vpa}) as Map).cast<String, dynamic>();
        if (!mounted || _upi.text.trim() != vpa) return;
        setState(() {
          _upiInfo = r;
          // The name on the UPI ID (Razorpay check) fills an empty account holder.
          final name = r['name'];
          if (name is String && name.isNotEmpty && _holder.text.trim().isEmpty) _holder.text = _titleCase(name);
        });
      } catch (_) {}
    });
  }
  DateTime? _updated;
  bool _filled = false;
  bool _busy = false;

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([Api.I.get('/api/doctor/profile'), Api.I.get('/api/doctor/payouts').catchError((_) => null)]);
    _payouts = (r[1] as Map?)?.cast<String, dynamic>();
    return r[0];
  }

  /// GET /api/doctor/payouts: online fees waiting, next payout day, past payouts.
  Map<String, dynamic>? _payouts;

  static const _statusLabel = {
    'pending': ('Waiting', MP.amber),
    'on_hold': ('On hold', MP.amber),
    'processing': ('On its way', MP.primary),
    'paid': ('Paid', MP.green),
    'failed': ('Not sent', MP.red),
  };

  Widget _onlineFees() {
    final p = _payouts;
    final waiting = data == null ? 2400 : (p?.obj('waiting').numOr('amount') ?? 0);
    final count = data == null ? (isLive ? 0 : 4) : (p?.obj('waiting').numOr('count') ?? 0).toInt();
    final next = data == null ? null : F.date(p?['nextPayoutOn']);
    final items = data == null ? const <Map<String, dynamic>>[] : (p?.list('items') ?? const <Map<String, dynamic>>[]);
    return D4Card(
      children: [
        const D4CardTitle('Online fees'),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹${F.count(waiting)}', style: tx(28, w: w800, tab: true)),
          const Gap(8),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(count == 1 ? 'from 1 visit' : 'from $count visits', style: tx(14, c: MP.ink2))),
        ]),
        D4Note([
          'Paid to you every Monday',
          if (next != null) 'next on ${F.dayMonth(next)}',
          'fees wait ${p?.numOr('holdDays', 2).toInt() ?? 2} days in case of a refund',
        ].join(' · ')),
        if (data != null && p?['live'] == false)
          const D4Note('Automatic payouts are being set up by MedPin. Your balance is kept safely until then.'),
        for (final it in items.take(6))
          Builder(builder: (_) {
            final (label, color) = _statusLabel[it.str('status')] ?? ('Waiting', MP.amber);
            final at = F.date(it['paidAt'] ?? it['createdAt']);
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('₹${F.count(it.numOr('amount'))} · ${it.numOr('count').toInt()} fees', style: tx(15, w: w600, tab: true)),
                    Text([if (at != null) F.dayMonth(at), if (it.str('destination').isNotEmpty) it.str('destination')].join(' · '), style: tx(13, c: MP.ink2)),
                    if (it.str('note').isNotEmpty) Text(it.str('note'), style: tx(13, c: color, h: 1.4)),
                  ]),
                ),
                const Gap(8),
                Text(label, style: tx(13, w: w600, c: color)),
              ]),
            );
          }),
      ],
    );
  }

  @override
  void dispose() {
    _ifscTimer?.cancel();
    _upiTimer?.cancel();
    for (final c in [_upi, _holder, _bank, _account, _account2, _ifsc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill() {
    final p = data!.obj('payout');
    _preferred = p.str('preferred', p['upiId'] != null ? 'upi' : 'bank');
    _upi.text = p.str('upiId');
    _holder.text = p.str('accountHolder', data!.str('displayName').replaceFirst(RegExp(r'^Dr\.?\s*'), ''));
    _bank.text = p.str('bankName');
    // What was saved was checked then; show it without asking again.
    _ifscAsked = p.str('ifsc');
    _ifsc.text = p.str('ifsc');
    if (p.str('ifsc').isNotEmpty && p.str('bankName').isNotEmpty) {
      final branch = p.str('bankBranch').split(', ');
      _ifscInfo = {
        'valid': true,
        'found': true,
        'bank': p.str('bankName'),
        'branch': branch.first,
        if (branch.length > 1) 'city': branch.sublist(1).join(', '),
      };
    }
    if (_upi.text.isNotEmpty) _onUpi();
    _last4 = p['bankAccountLast4'] as String?;
    _updated = F.date(p['updatedAt']);
  }

  String? _check() {
    final upi = _upi.text.trim();
    final acc = _account.text.replaceAll(' ', '');
    final ifsc = _ifsc.text.trim().toUpperCase();
    if (_preferred == 'upi' && upi.isEmpty) return 'Enter your UPI ID';
    if (upi.isNotEmpty && !RegExp(r'^[\w.-]{2,}@[a-zA-Z]{2,}$').hasMatch(upi)) return 'Enter a UPI ID like name@bank';
    if (_preferred == 'bank') {
      if (_holder.text.trim().isEmpty) return 'Enter the account holder’s name';
      if (acc.isEmpty && _last4 == null) return 'Enter the account number';
    }
    if (acc.isNotEmpty && !RegExp(r'^\d{9,18}$').hasMatch(acc)) return 'Enter the bank account number (9–18 digits)';
    if (acc.isNotEmpty && _account2.text.replaceAll(' ', '') != acc) return 'The two account numbers don’t match';
    if (ifsc.isNotEmpty && _ifscInfo?['found'] == false) return 'This IFSC doesn’t exist. Check it on your cheque book or bank app.';
    if (upi.isNotEmpty && _upiInfo?['checked'] == true && _upiInfo?['exists'] == false) return 'This UPI ID doesn’t exist. Check it in your UPI app.';
    if (_ifscChecking) return 'Checking the IFSC…';
    if ((_preferred == 'bank' || ifsc.isNotEmpty) && !RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) {
      return 'Enter an 11-character IFSC like HDFC0001234';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _check();
    if (problem != null) {
      toast(context, problem);
      return;
    }
    if (!isLive) {
      d4Save(context);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final acc = _account.text.replaceAll(' ', '');
    final ok = await runAction(
      context,
      () => Api.I.patch('/api/doctor/profile', {
        'payout': {
          'preferred': _preferred,
          if (_upi.text.trim().isNotEmpty) 'upiId': _upi.text.trim(),
          'accountHolder': _holder.text.trim(),
          'bankName': _bank.text.trim(),
          if (_ifsc.text.trim().isNotEmpty) 'ifsc': _ifsc.text.trim().toUpperCase(),
          if (acc.isNotEmpty) 'accountNumber': acc,
        },
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) d4Save(context, 'Payout details saved');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (data != null && !_filled) {
      _filled = true;
      _fill();
    }
    return MpPage(
      header: D4Header('Payouts and bank account', subtitle: 'For fees patients pay online', onSave: placeholder == null ? _save : null),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              _onlineFees(),
              D4Card(
                children: [
                  const D4CardTitle('Pay me by'),
                  Row(
                    children: [
                      Expanded(child: D4OptionCard(title: 'UPI', sub: 'Usually the same day', selected: _preferred == 'upi', onTap: () => setState(() => _preferred = 'upi'))),
                      const SizedBox(width: 8),
                      Expanded(child: D4OptionCard(title: 'Bank account', sub: '1–2 working days', selected: _preferred == 'bank', onTap: () => setState(() => _preferred = 'bank'))),
                    ],
                  ),
                ],
              ),
              // Only the chosen way's details show; the other's saved details are kept.
              if (_preferred == 'upi')
              D4Card(
                children: [
                  const D4CardTitle('UPI'),
                  D11Field('UPI ID', _upi, hint: 'name@bank', keyboard: TextInputType.emailAddress),
                  ..._upiNotes(),
                ],
              ),
              if (_preferred == 'bank')
              D4Card(
                children: [
                  const D4CardTitle('Bank account'),
                  D11Field('Account holder', _holder, caps: TextCapitalization.words),
                  D11Field(
                    'Account number',
                    _account,
                    hint: _last4 == null ? '9–18 digits' : 'Saved ••••$_last4 · type to replace',
                    keyboard: TextInputType.number,
                  ),
                  if (_account.text.trim().isNotEmpty) ...[
                    D11Field('Re-enter account number', _account2, hint: 'Type it again to be sure', keyboard: TextInputType.number),
                    if (_account2.text.isNotEmpty && _account2.text.replaceAll(' ', '') != _account.text.replaceAll(' ', ''))
                      const _Note('The two numbers don’t match', tone: _Tone.bad),
                  ],
                  D11Field('IFSC', _ifsc, hint: 'HDFC0001234', caps: TextCapitalization.characters),
                  if (_ifscNote() case final n?) n,
                  // The bank comes from the IFSC; typed only when it couldn't be looked up.
                  if (_ifscInfo != null && _ifscInfo!['found'] == null)
                    D11Field('Bank', _bank, hint: 'e.g. HDFC Bank', caps: TextCapitalization.words),
                ],
              ),
              D4Note(
                'Payouts are sent through Razorpay once your clinic’s payment account is active. '
                'MedPin keeps only the last 4 digits of your account number.'
                '${_updated == null ? '' : ' Last updated ${F.dayMonth(_updated!)}.'}',
              ),
            ],
          ),
    );
  }
}

extension on _ProfilePayoutsScreenState {
  /// Under the IFSC: the bank and branch it belongs to, or what's wrong.
  Widget? _ifscNote() {
    if (_ifscChecking) return const _Note('Checking the IFSC…', tone: _Tone.wait);
    final i = _ifscInfo;
    if (i == null) {
      return _ifsc.text.trim().isEmpty ? const _Note('The bank and branch fill in from the IFSC (on your cheque book or bank app)', tone: _Tone.wait) : null;
    }
    if (i['valid'] == false) return const _Note('An IFSC has 11 characters: 4 letters, 0, then 6 letters or digits', tone: _Tone.bad);
    if (i['found'] == false) return const _Note('This IFSC doesn’t exist. Check it on your cheque book or bank app.', tone: _Tone.bad);
    if (i['found'] == null) {
      final bank = i['bank'];
      return _Note(
        bank is String ? '$bank · couldn’t check the branch right now' : 'Couldn’t check the IFSC right now. Type the bank name below.',
        tone: _Tone.wait,
      );
    }
    final place = [i['branch'], i['city']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    return _Note([i['bank'], if (place.isNotEmpty) place].join(' · '), tone: _Tone.ok);
  }

  /// Under the UPI ID: which app it is from, and (with Razorpay set up)
  /// whether it exists and whose name is on it.
  List<Widget> _upiNotes() {
    final u = _upiInfo;
    if (u == null) return const [];
    if (u['valid'] != true) return const [_Note('Enter a UPI ID like name@bank', tone: _Tone.bad)];
    if (u['checked'] == true && u['exists'] == false) {
      return const [_Note('This UPI ID doesn’t exist. Check it in your UPI app.', tone: _Tone.bad)];
    }
    final app = u['app'] as String?;
    final bank = u['bank'] as String?;
    final out = <Widget>[
      if (u['known'] != true)
        _Note('@${u['handle']} isn’t a UPI app we know. Check it in your UPI app.', tone: _Tone.wait)
      else if (bank != null)
        _Note('$app · $bank', tone: _Tone.ok)
      else
        // A payment app's handle doesn't say which bank the money is in.
        _Note('$app UPI ID · paid into the bank you linked in $app', tone: _Tone.ok),
    ];
    final name = u['name'];
    if (name is String && name.isNotEmpty) {
      final holder = _holder.text.trim().toLowerCase();
      final same = holder.isEmpty || _sameName(holder, name.toLowerCase());
      out.add(_Note('Name on this UPI ID: ${_titleCase(name)}', tone: same ? _Tone.ok : _Tone.wait));
      if (!same) out.add(const _Note('This isn’t the account holder’s name below. Payouts go to the name on the UPI ID.', tone: _Tone.wait));
    }
    return out;
  }
}

/// "TANMOY DAS" → "Tanmoy Das".
String _titleCase(String s) => s.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

/// Same person: every word of the shorter name appears in the longer one.
bool _sameName(String a, String b) {
  final wa = a.split(RegExp(r'[^a-z]+')).where((w) => w.length > 1).toSet();
  final wb = b.split(RegExp(r'[^a-z]+')).where((w) => w.length > 1).toSet();
  if (wa.isEmpty || wb.isEmpty) return true;
  final (small, big) = wa.length <= wb.length ? (wa, wb) : (wb, wa);
  return small.every(big.contains);
}

enum _Tone { ok, bad, wait }

/// One line under a field: a green tick when found, red when wrong, grey otherwise.
class _Note extends StatelessWidget {
  final String text;
  final _Tone tone;
  const _Note(this.text, {required this.tone});

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) { _Tone.ok => MP.green, _Tone.bad => MP.red, _Tone.wait => MP.ink2 };
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Ico(tone == _Tone.ok ? I.check : (tone == _Tone.bad ? I.alert : I.clock), size: 15, color: color, stroke: 2.2),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: tx(13, w: tone == _Tone.ok ? w600 : w500, c: color, h: 1.4))),
        ],
      ),
    );
  }
}

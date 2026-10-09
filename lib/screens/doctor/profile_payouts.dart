import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';

/// Doctor · Payouts and bank account — where online consultation fees are paid.
/// Live data: GET/PATCH /api/doctor/profile (payout). Only the last 4 digits of
/// the account number are kept on MedPin.
class ProfilePayoutsScreen extends StatefulWidget {
  const ProfilePayoutsScreen({super.key});

  @override
  State<ProfilePayoutsScreen> createState() => _ProfilePayoutsScreenState();
}

class _ProfilePayoutsScreenState extends State<ProfilePayoutsScreen> with LiveData {
  String _preferred = 'upi';
  final _upi = TextEditingController(text: 'arjunsen@okhdfcbank');
  final _holder = TextEditingController(text: 'Arjun Sen');
  final _bank = TextEditingController(text: 'HDFC Bank');
  final _account = TextEditingController();
  final _ifsc = TextEditingController(text: 'HDFC0001234');
  String? _last4 = '6789';
  DateTime? _updated;
  bool _filled = false;
  bool _busy = false;

  @override
  Future<Object?> fetch() => Api.I.get('/api/doctor/profile');

  @override
  void dispose() {
    for (final c in [_upi, _holder, _bank, _account, _ifsc]) {
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
    _ifsc.text = p.str('ifsc');
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
              D4Card(
                children: [
                  const D4CardTitle('UPI'),
                  D11Field('UPI ID', _upi, hint: 'name@bank', keyboard: TextInputType.emailAddress),
                ],
              ),
              D4Card(
                children: [
                  const D4CardTitle('Bank account'),
                  D11Field('Account holder', _holder, caps: TextCapitalization.words),
                  D11Field('Bank', _bank, hint: 'e.g. HDFC Bank', caps: TextCapitalization.words),
                  D11Field(
                    'Account number',
                    _account,
                    hint: _last4 == null ? '9–18 digits' : 'Saved ••••$_last4 · type to replace',
                    keyboard: TextInputType.number,
                  ),
                  D11Field('IFSC', _ifsc, hint: 'HDFC0001234', caps: TextCapitalization.characters),
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

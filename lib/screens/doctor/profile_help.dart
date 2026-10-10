import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';
import '../../widgets/i18n.dart';

/// Doctor · Help and support — contact MedPin, common questions, and
/// "Report a problem".
/// Live data: GET /api/me/support (contact), POST /api/me/support.
class ProfileHelpScreen extends StatefulWidget {
  const ProfileHelpScreen({super.key});

  @override
  State<ProfileHelpScreen> createState() => _ProfileHelpScreenState();
}

class _ProfileHelpScreenState extends State<ProfileHelpScreen> with LiveData {
  static const _appVersion = '3.8.2';

  static const _faqs = [
    (
      'How do patients link their records to my clinic?',
      'Register them with their mobile number from New patient. If they already use MedPin, ask for the 6-digit consent code shown in their app under Profile.',
    ),
    (
      'Why can’t I send a prescription?',
      'A digital signature is needed before prescriptions can be sent. Add it in Prescription letterhead and signature.',
    ),
    (
      'What does MedPin AI say to my patients?',
      'It answers from your approved knowledge-base entries, never diagnoses or changes doses, and flags anything clinical to you in Chat review.',
    ),
    (
      'How do I stop bookings on a holiday?',
      'Add the dates in Leave and holidays. Patients who already booked are told, and those days close for online booking.',
    ),
    (
      'Can my front desk see clinical notes?',
      'Front desk can see patients and chats and record vitals, but cannot prescribe or edit clinical records. Roles are set in Staff and assistants.',
    ),
  ];

  static const _topics = [('problem', 'Something isn’t working'), ('question', 'A question'), ('billing', 'Billing'), ('feature', 'An idea')];

  final _message = TextEditingController();
  String _topic = 'problem';
  int? _open;
  bool _busy = false;

  @override
  Future<Object?> fetch() => Api.I.get('/api/me/support');

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  // Contacts come from the backend (SUPPORT_EMAIL / SUPPORT_PHONE / SUPPORT_WHATSAPP).
  String? get _email => data == null ? 'support@example.com' : data!['email'] as String?;
  String? get _phone => data == null ? '+91 33 4000 0000' : data!['phone'] as String?;
  String? get _whatsapp => data == null ? '+91 98300 00000' : data!['whatsapp'] as String?;

  Future<void> _launch(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Couldn't open that");
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 10) {
      toast(context, 'Tell us a little more (at least 10 characters)');
      return;
    }
    if (!isLive) {
      _message.clear();
      toast(context, 'Thanks — we’ll get back to you');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => Api.I.post('/api/me/support', {
        'topic': _topic,
        'message': text,
        'appVersion': _appVersion,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == null) return;
    _message.clear();
    toast(context, 'Thanks — we’ll get back to you');
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    final phone = _phone;
    final whatsapp = _whatsapp;
    final anyContact = [email, phone, whatsapp].any((c) => c != null && c.isNotEmpty);
    return MpPage(
      header: const D4Header('Help and support'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        gap: 16,
        children: [
          if (anyContact) D11Group('Contact MedPin', [
            if (email != null && email.isNotEmpty) D11Row('Email us', sub: email, onTap: () => _launch('mailto:$email?subject=MedPin%20help')),
            if (phone != null && phone.isNotEmpty) D11Row('Call us', sub: '$phone · 9 AM – 7 PM, Mon–Sat', onTap: () => _launch('tel:${_digits(phone)}')),
            if (whatsapp != null && whatsapp.isNotEmpty)
              D11Row('WhatsApp', sub: whatsapp, onTap: () => _launch('https://wa.me/${_digits(whatsapp).replaceAll('+', '')}')),
          ]),
          D11Group('Common questions', [
            for (var i = 0; i < _faqs.length; i++)
              Tap(
                onTap: () => setState(() => _open = _open == i ? null : i),
                radius: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(_faqs[i].$1, style: tx(15, w: w600))),
                          const SizedBox(width: 12),
                          Ico(_open == i ? I.chevronUp : I.chevronDown, size: 18, color: MP.ink3, stroke: 2),
                        ],
                      ),
                      if (_open == i) ...[const SizedBox(height: 8), Text(_faqs[i].$2, style: tx(14, c: MP.ink2, h: 1.5))],
                    ],
                  ),
                ),
              ),
          ]),
          D4Card(
            children: [
              const D4CardTitle('Report a problem'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _topics)
                    MpChip(t.$2, selected: _topic == t.$1, onTap: () => setState(() => _topic = t.$1)),
                ],
              ),
              D11Field('What happened?', _message, hint: 'What you tapped, what you expected, what you saw', maxLines: null, maxLength: 4000, caps: TextCapitalization.sentences),
              MpButton(_busy ? 'Sending…' : 'Send', onTap: _busy ? null : _send),
              const D4Note('We reply by email or phone, usually within a working day.'),
            ],
          ),
          Text('MedPin $_appVersion', textAlign: TextAlign.center, style: tx(12, c: MP.ink3)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';

/// Doctor · Chat and urgent messages — who can message, MedPin AI replies,
/// urgent alerts, reply hours and availability.
/// Live data: GET/PATCH /api/doctor/profile (chatSettings, presence, avgReplyMinutes).
class ProfileChatScreen extends StatefulWidget {
  const ProfileChatScreen({super.key});

  @override
  State<ProfileChatScreen> createState() => _ProfileChatScreenState();
}

class _ProfileChatScreenState extends State<ProfileChatScreen> with LiveData {
  // A form: don't refresh by itself while it's being filled in.
  @override
  bool get autoRefresh => false;

  static const _who = [
    ('booked', 'Patients with a booked visit', 'They can message you from 1 day before their visit'),
    ('anyone', 'All patients of your practice', 'Anyone linked to your clinic can start a chat'),
    ('nobody', 'Nobody', 'Patients are asked to call the clinic instead'),
  ];
  // What patients see is worked out live: "In clinic now" during your clinic
  // hours, "Available now" when you're in the app within reply hours, else
  // "Back at …". Away keeps you from showing as available.
  static const _presence = [
    ('auto', 'Automatic', 'From your clinic hours and when you use the app'),
    ('away', 'Away', 'Never shown as available · your clinic team sees new messages'),
  ];

  String _whoCan = 'booked';
  String _status = 'auto';
  bool _aiReplies = true;
  bool _urgent = true;
  String _from = '09:00';
  String _to = '20:00';
  int _replyMin = 15;
  final _away = TextEditingController(text: "I'm with patients. Your message is with the clinic team, and I'll reply by evening.");
  bool _filled = false;
  bool _busy = false;

  @override
  Future<Object?> fetch() => Api.I.get('/api/doctor/profile');

  @override
  void dispose() {
    _away.dispose();
    super.dispose();
  }

  void _fill() {
    final c = data!.obj('chatSettings');
    _whoCan = c.str('whoCanMessage', 'booked');
    _aiReplies = c['aiReplies'] != false;
    _urgent = c['urgentAlerts'] != false;
    _from = c.obj('replyHours').str('from', '09:00');
    _to = c.obj('replyHours').str('to', '20:00');
    _away.text = c.str('awayMessage');
    _status = data!.str('presence') == 'away' ? 'away' : 'auto';
    _replyMin = data!.numOr('avgReplyMinutes', 15).toInt();
  }

  Future<void> _save() async {
    if (!isLive) {
      d4Save(context);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => Api.I.patch('/api/doctor/profile', {
        'presence': _status,
        'avgReplyMinutes': _replyMin,
        'chatSettings': {
          'whoCanMessage': _whoCan,
          'aiReplies': _aiReplies,
          'urgentAlerts': _urgent,
          'replyHours': {'from': _from, 'to': _to},
          'awayMessage': _away.text.trim(),
        },
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) d4Save(context);
  }

  Future<void> _pick(bool from) async {
    final r = await d11PickTime(context, from ? 'Replies from' : 'Replies until', from ? _from : _to);
    if (r != null && mounted) setState(() => from ? _from = r : _to = r);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (data != null && !_filled) {
      _filled = true;
      _fill();
    }
    return MpPage(
      header: D4Header('Chat and urgent messages', onSave: placeholder == null ? _save : null),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              D4Card(
                children: [
                  const D4CardTitle('Who can message you'),
                  for (final w in _who)
                    D4OptionCard(title: w.$2, sub: w.$3, selected: _whoCan == w.$1, onTap: () => setState(() => _whoCan = w.$1)),
                ],
              ),
              D4Card(
                children: [
                  const D4CardTitle('Your status'),
                  for (final p in _presence)
                    D4OptionCard(title: p.$2, sub: p.$3, selected: _status == p.$1, onTap: () => setState(() => _status = p.$1)),
                  D4StepperRow(
                    title: 'Usual reply time',
                    sub: 'Used until MedPin has measured your replies to patients',
                    value: '$_replyMin min',
                    onMinus: _replyMin > 5 ? () => setState(() => _replyMin -= 5) : null,
                    onPlus: _replyMin < 240 ? () => setState(() => _replyMin += 5) : null,
                  ),
                ],
              ),
              D11Group('Replies', [
                D11Switch(
                  'MedPin AI replies',
                  'Answers common questions from your approved knowledge base and flags anything clinical for you',
                  value: _aiReplies,
                  onChanged: (v) => setState(() => _aiReplies = v),
                ),
                D11Switch(
                  'Alert me for urgent messages',
                  'Urgent chats ring through even in quiet hours, and your front desk is told too',
                  value: _urgent,
                  onChanged: (v) => setState(() => _urgent = v),
                ),
                D11Row('Replies from', value: d11Clock(_from), onTap: () => _pick(true)),
                D11Row('Replies until', value: d11Clock(_to), onTap: () => _pick(false)),
              ]),
              D4Card(
                children: [
                  const D4CardTitle('Away message'),
                  D11Field('Sent when a patient writes outside reply hours', _away, maxLines: null, maxLength: 300, caps: TextCapitalization.sentences),
                ],
              ),
            ],
          ),
    );
  }
}

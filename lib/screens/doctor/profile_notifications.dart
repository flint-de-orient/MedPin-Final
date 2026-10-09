import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';
import 'common_d11.dart';

/// Doctor · Notifications — channels, what to be told about, quiet hours and
/// the follow-up reminders patients get.
/// Live data: GET/PATCH /api/doctor/profile (notificationPrefs, followUpReminder), GET /api/me (email).
class ProfileNotificationsScreen extends StatefulWidget {
  const ProfileNotificationsScreen({super.key});

  @override
  State<ProfileNotificationsScreen> createState() => _ProfileNotificationsScreenState();
}

class _ProfileNotificationsScreenState extends State<ProfileNotificationsScreen> with LiveData {
  bool _push = true, _whatsapp = true, _email = false, _digest = true;
  bool _appointments = true, _messages = true, _labs = true, _followUps = true;
  bool _quiet = false;
  String _quietFrom = '22:00', _quietTo = '07:00';
  int _remindDays = 3;
  bool _remindWhatsapp = true, _remindApp = true;
  bool _filled = false;
  bool _busy = false;

  @override
  Future<Object?> fetch() async {
    final r = await Future.wait([Api.I.get('/api/doctor/profile'), Api.I.get('/api/me')]);
    return {'profile': r[0], 'me': r[1]};
  }

  String? get _accountEmail => (data?.obj('me').obj('user')['email']) as String?;

  void _fill() {
    final p = data!.obj('profile');
    final n = p.obj('notificationPrefs');
    _push = n['push'] != false;
    _whatsapp = n['whatsapp'] != false;
    _email = n['email'] == true;
    _digest = n['dailyDigest'] != false;
    final t = n.obj('types');
    _appointments = t['appointments'] != false;
    _messages = t['messages'] != false;
    _labs = t['labResults'] != false;
    _followUps = t['followUps'] != false;
    final q = n.obj('quietHours');
    _quiet = q['enabled'] == true;
    _quietFrom = q.str('from', '22:00');
    _quietTo = q.str('to', '07:00');
    final f = p.obj('followUpReminder');
    _remindDays = f.numOr('daysBefore', 3).toInt();
    final ch = [for (final c in (f['channels'] as List? ?? const ['whatsapp', 'app'])) '$c'];
    _remindWhatsapp = ch.contains('whatsapp');
    _remindApp = ch.contains('app');
  }

  Future<void> _save() async {
    if (!isLive) {
      d4Save(context);
      return;
    }
    if (_email && (_accountEmail ?? '').isEmpty) {
      toast(context, 'Add an email to your account first (Profile → name and email)');
      return;
    }
    if (!_remindWhatsapp && !_remindApp) {
      toast(context, 'Choose at least one way to remind patients');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => Api.I.patch('/api/doctor/profile', {
        'notificationPrefs': {
          'push': _push,
          'whatsapp': _whatsapp,
          'email': _email,
          'dailyDigest': _digest,
          'quietHours': {'enabled': _quiet, 'from': _quietFrom, 'to': _quietTo},
          'types': {'appointments': _appointments, 'messages': _messages, 'labResults': _labs, 'followUps': _followUps},
        },
        'followUpReminder': {
          'daysBefore': _remindDays,
          'channels': [if (_remindWhatsapp) 'whatsapp', if (_remindApp) 'app'],
        },
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) d4Save(context);
  }

  Future<void> _pick(bool from) async {
    final r = await d11PickTime(context, from ? 'Quiet from' : 'Quiet until', from ? _quietFrom : _quietTo);
    if (r != null && mounted) setState(() => from ? _quietFrom = r : _quietTo = r);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = livePlaceholder();
    if (data != null && !_filled) {
      _filled = true;
      _fill();
    }
    final email = _accountEmail;
    return MpPage(
      header: D4Header('Notifications', onSave: placeholder == null ? _save : null),
      body: placeholder ??
          VGap(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            gap: 16,
            children: [
              D11Group('How we reach you', [
                D11Switch('App notifications', 'On this phone', value: _push, onChanged: (v) => setState(() => _push = v)),
                D11Switch('WhatsApp', 'To your registered mobile number', value: _whatsapp, onChanged: (v) => setState(() => _whatsapp = v)),
                D11Switch(
                  'Email',
                  data == null ? 'arjun.sen@citycare.in' : (email == null || email.isEmpty ? 'No email on your account yet' : email),
                  value: _email,
                  onChanged: (v) => setState(() => _email = v),
                ),
              ]),
              D11Group('Tell me about', [
                D11Switch('Appointments', 'New bookings, requests, cancellations', value: _appointments, onChanged: (v) => setState(() => _appointments = v)),
                D11Switch('Patient messages', 'New chats and replies', value: _messages, onChanged: (v) => setState(() => _messages = v)),
                D11Switch('Test results', 'New and abnormal reports', value: _labs, onChanged: (v) => setState(() => _labs = v)),
                D11Switch('Follow-ups', 'Patients due or overdue', value: _followUps, onChanged: (v) => setState(() => _followUps = v)),
                D11Switch('Daily summary', 'Your day at 8 PM: visits, open alerts, chats', value: _digest, onChanged: (v) => setState(() => _digest = v)),
              ]),
              D11Group('Quiet hours', [
                D11Switch(
                  'Quiet hours',
                  'No sounds or WhatsApp. Emergencies and urgent chats still come through.',
                  value: _quiet,
                  onChanged: (v) => setState(() => _quiet = v),
                ),
                if (_quiet) ...[
                  D11Row('From', value: d11Clock(_quietFrom), onTap: () => _pick(true)),
                  D11Row('Until', value: d11Clock(_quietTo), onTap: () => _pick(false)),
                ],
              ]),
              D4Card(
                children: [
                  const D4CardTitle('Follow-up reminders to patients'),
                  D4StepperRow(
                    title: 'Remind',
                    sub: 'Days before the follow-up is due',
                    value: '$_remindDays ${_remindDays == 1 ? 'day' : 'days'}',
                    onMinus: _remindDays > 1 ? () => setState(() => _remindDays -= 1) : null,
                    onPlus: _remindDays < 14 ? () => setState(() => _remindDays += 1) : null,
                  ),
                  D4SwitchRow(title: 'WhatsApp', sub: 'A message to the patient’s number', value: _remindWhatsapp, onChanged: (v) => setState(() => _remindWhatsapp = v)),
                  D4SwitchRow(title: 'MedPin app', sub: 'A notification in the patient app', value: _remindApp, onChanged: (v) => setState(() => _remindApp = v)),
                ],
              ),
            ],
          ),
    );
  }
}

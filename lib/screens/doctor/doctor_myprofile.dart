import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/live.dart';
import '../../widgets/mp.dart';
import 'common_d4.dart';

/// Design: Doctor-MyProfile.dc.html — "Doctor · My profile (settings hub)".
class DoctorMyprofileScreen extends StatefulWidget {
  const DoctorMyprofileScreen({super.key});

  @override
  State<DoctorMyprofileScreen> createState() => _DoctorMyprofileScreenState();
}

class _DoctorMyprofileScreenState extends State<DoctorMyprofileScreen> {
  static const _spoken = ['English', 'Bengali', 'Hindi', 'Urdu', 'Odia', 'Assamese'];
  static const _appLanguages = ['English', 'Bengali', 'Hindi'];

  List<String> _languages = const ['English', 'Bengali'];
  String _appLanguage = 'English';

  void _go(String stem) => Nav.go(context, stem);

  /// Rows whose editor is not part of the design yet.
  void _soon(String what) => toast(context, '$what — coming soon');

  Future<void> _editLanguages() async {
    final r = await openSheet<List<String>>(context, (_) => _LanguagesSheet(options: _spoken, selected: _languages));
    if (r != null && mounted) setState(() => _languages = r);
  }

  void _addHindi() {
    setState(() => _languages = [..._languages, 'Hindi']);
    toast(context, 'Hindi added');
  }

  Future<void> _pickAppLanguage() async {
    final r = await d4PickOne(context, title: 'App language', options: _appLanguages, value: _appLanguage);
    if (r != null && mounted) setState(() => _appLanguage = r);
  }

  void _share() {
    Clipboard.setData(
      const ClipboardData(
        text: 'Dr. Arjun Sen · Diabetologist · Internal medicine · MBBS, MD · WBMC 64213 — book on MedPin',
      ),
    );
    toast(context, 'Profile copied to share');
  }

  @override
  Widget build(BuildContext context) {
    final languages = _languages.isEmpty ? 'Add the languages you speak' : _languages.join(', ');
    return MpPage(
      header: const D4Header('My profile'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        gap: 16,
        children: [
          _profileCard(),
          _bookingCard(),
          _Group('About you', [
            _SettingRow(
              'Professional details',
              sub: 'Profession, qualifications, registration, specialisations',
              emptyValue: true,
              onTap: () => _go('Profile-Professional'),
            ),
            _SettingRow(
              'ABDM · HPR ID',
              sub: 'Ayushman Bharat Digital Mission',
              value: 'Link',
              valueColor: MP.primary,
              onTap: () => _go('Profile-Professional'),
            ),
            _SettingRow(
              'About and photo',
              sub: 'Bio patients read before booking',
              onTap: () => _soon('About and photo'),
            ),
            _SettingRow(
              'Languages',
              sub: languages,
              value: _languages.contains('Hindi') ? null : 'Add Hindi?',
              valueColor: MP.primary,
              onValue: _addHindi,
              onTap: _editLanguages,
            ),
          ]),
          _Group('Practice', [
            _SettingRow(
              'Locations',
              sub: '3 locations · map, address, contact',
              value: '3',
              onTap: () => _go('Clinics'),
            ),
            _SettingRow(
              'Schedules and slots',
              sub: 'Hours and slot rules for each location',
              onTap: () => _go('Profile-Schedule'),
            ),
            _SettingRow(
              'Services and fees',
              sub: '5 services · in clinic and video',
              onTap: () => _go('Profile-Location'),
            ),
            _SettingRow('Leave and holidays', sub: 'Durga Puja · 19 – 23 Oct', onTap: () => _go('Profile-Schedule')),
          ]),
          _Group('Patients and care', [
            _SettingRow(
              'Booking rules',
              sub: 'How far ahead, cancellations, walk-ins',
              onTap: () => _go('Profile-Schedule'),
            ),
            _SettingRow(
              'Follow-up reminders',
              sub: 'Sent 3 days before · WhatsApp and app',
              onTap: () => _go('Doctor-FollowUps'),
            ),
            _SettingRow(
              'Chat and urgent messages',
              sub: 'When patients can message you',
              onTap: () => _soon('Chat and urgent messages'),
            ),
            _SettingRow(
              'Prescription letterhead and signature',
              sub: 'Printed on every prescription',
              value: 'Signature missing',
              valueColor: MP.amber,
              onTap: () => _go('Clinic-Editor'),
            ),
          ]),
          _Group('Team', [
            _SettingRow('Staff and assistants', sub: 'Front desk at City Care · 2 people', onTap: () => _go('People')),
            _SettingRow(
              'Colleagues you work with',
              sub: 'Dietician, cardiologist and 4 more',
              onTap: () => _go('People'),
            ),
          ]),
          _Group('Account', [
            _SettingRow('Notifications', onTap: () => _soon('Notifications')),
            _SettingRow(
              'Payouts and bank account',
              sub: 'UPI and bank for online fees',
              onTap: () => _soon('Payouts and bank account'),
            ),
            _SettingRow('Plan and billing', sub: 'MedPin Pro · renews 12 Jan', onTap: () => _go('Billing')),
            _SettingRow('Privacy and data', onTap: () => _soon('Privacy and data')),
            _SettingRow('App language', sub: _appLanguage, onTap: _pickAppLanguage),
            _SettingRow('Help and support', onTap: () => _soon('Help and support')),
          ]),
          D4OutlineButton('Log out', border: MP.redLine, onTap: () => signOut(context)),
          Text('MedPin 3.8.2', textAlign: TextAlign.center, style: tx(12, c: MP.ink3)),
        ],
      ),
    );
  }

  Widget _profileCard() {
    return MpCard(
      child: VGap(
        gap: 16,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: MP.primarySoft, shape: BoxShape.circle),
                      child: Text('AS', style: tx(24, w: w800, c: MP.primary)),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Semantics(
                        button: true,
                        label: 'Change photo',
                        // <button> is border-box: 28×28 including the 2px border.
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Tap(
                            onTap: () => _soon('Change photo'),
                            radius: 999,
                            color: MP.primary,
                            border: MP.white,
                            borderWidth: 2,
                            child: const Center(child: Ico(I.cameraAlt, size: 14, color: MP.white, stroke: 2)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Dr. Arjun Sen',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx(20, w: w800, em: -0.01),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Semantics(label: 'Verified', child: const Svg(I.verifiedSvg, width: 18, height: 18)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('Diabetologist · Internal medicine', style: tx(14, c: MP.ink2)),
                    const SizedBox(height: 3),
                    Text('MBBS, MD · WBMC 64213 · 14 yrs', style: tx(13, c: MP.ink3)),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('Profile 85% complete', style: tx(14, w: w600))),
                  D4TextLink('Finish', onTap: _editLanguages),
                ],
              ),
              const SizedBox(height: 8),
              const MpProgress(0.85, height: 6),
              const SizedBox(height: 8),
              Text(
                'Add your languages and a clinic photo to appear higher in patient search.',
                style: tx(13, c: MP.ink2),
              ),
            ],
          ),
          // Grid 1fr 1fr: the bordered link is 44 + 2px tall, the tonal one 44px.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: Tap(
                    onTap: () => _go('Patient-DoctorDetail'),
                    radius: 12,
                    border: MP.lineStrong,
                    child: Center(child: Text('See as a patient', style: tx(14, w: w600))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Tap(
                    onTap: _share,
                    radius: 12,
                    color: MP.primarySoft,
                    child: Center(child: Text('Share profile', style: tx(14, w: w600, c: MP.primary))),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bookingCard() {
    return MpCard(
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: MP.green, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Taking bookings', style: tx(15, w: w700)),
                const SizedBox(height: 2),
                Text('Next free slot: today, 12:15 PM · Salt Lake', style: tx(13, c: MP.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          D4TextLink('Take leave', onTap: () => _go('Profile-Schedule')),
        ],
      ),
    );
  }
}

/// Uppercase group label (13/700, .06em, #69738A, padding 0 4) over a white
/// list card (padding 0 16, radius 24) of rows separated by 1px lines.
class _Group extends StatelessWidget {
  final String label;
  final List<Widget> rows;
  const _Group(this.label, this.rows);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(label.toUpperCase(), style: tx(13, w: w700, c: MP.ink3, em: 0.06)),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: MPDeco.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) const MpDivider(), rows[i]],
          ],
        ),
      ),
    ],
  );
}

/// Settings row: 15/600 title, optional 13px / 1.4 #545E72 line, optional
/// 14/600 value, #69738A chevron. Padding 14 0, gap 12.
class _SettingRow extends StatelessWidget {
  final String title;
  final String? sub;
  final String? value;
  final Color valueColor;

  /// Makes [value] a link of its own (e.g. "Add Hindi?").
  final VoidCallback? onValue;

  /// The design keeps an empty value slot on this row (one more 12px gap).
  final bool emptyValue;
  final VoidCallback onTap;
  const _SettingRow(
    this.title, {
    this.sub,
    this.value,
    this.valueColor = MP.ink2,
    this.onValue,
    this.emptyValue = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Tap(
      onTap: onTap,
      radius: 0,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(15, w: w600)),
                if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: tx(13, c: MP.ink2, h: 1.4))],
              ],
            ),
          ),
          if (emptyValue) const SizedBox(width: 12),
          if (v != null) ...[
            const SizedBox(width: 12),
            onValue == null
                ? Text(v, style: tx(14, w: w600, c: valueColor))
                : D4TextLink(v, color: valueColor, onTap: onValue),
          ],
          const SizedBox(width: 12),
          const Ico(I.chevronRight, size: 18, color: MP.ink3, stroke: 2),
        ],
      ),
    );
  }
}

/// Spoken-languages picker opened from the Languages row and "Finish".
class _LanguagesSheet extends StatefulWidget {
  final List<String> options;
  final List<String> selected;
  const _LanguagesSheet({required this.options, required this.selected});

  @override
  State<_LanguagesSheet> createState() => _LanguagesSheetState();
}

class _LanguagesSheetState extends State<_LanguagesSheet> {
  late final Set<String> _on = {...widget.selected};

  void _toggle(String l) => setState(() {
    if (!_on.remove(l)) _on.add(l);
  });

  @override
  Widget build(BuildContext context) {
    return MpSheet(
      title: 'Languages',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in widget.options)
            Tap(
              onTap: () => _toggle(l),
              radius: 12,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(l, style: tx(16, w: _on.contains(l) ? w600 : w400))),
                    MpCheck(value: _on.contains(l), onChanged: (_) => _toggle(l)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          MpButton(
            'Save',
            onTap:
                () => Navigator.pop(context, [
                  for (final l in widget.options)
                    if (_on.contains(l)) l,
                ]),
          ),
        ],
      ),
    );
  }
}

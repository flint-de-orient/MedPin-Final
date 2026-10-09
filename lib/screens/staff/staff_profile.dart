import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import '../doctor/common_d10.dart';

/// Design: Staff-Profile.dc.html — "Profile" (front desk).
class StaffProfileScreen extends StatefulWidget {
  const StaffProfileScreen({super.key});

  @override
  State<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

/// The canvas sets `line-height: 1.4` on the page.
const _lh = 1.4;

const _globe = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>';
const _building =
    '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4M9 6h.01M15 6h.01M9 10h.01M15 10h.01M9 14h.01M15 14h.01"/>';

const _languages = ['English', 'Bengali', 'Hindi'];

class _StaffProfileScreenState extends State<StaffProfileScreen> {
  String _language = 'English';
  bool _appLock = true;

  Future<void> _pickLanguage() async {
    final v = await D10Picker.show(context, title: 'Language', options: _languages, value: _language);
    if (v != null && mounted) setState(() => _language = v);
  }

  @override
  Widget build(BuildContext context) {
    final title = tx(16, w: w600, h: _lh);
    final sub = tx(14, c: MP.ink2, h: _lh);
    return MpPage(
      nav: const StaffNav(current: 2),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const D10StaffHeader(bellLabel: 'Notifications, 3 new', dot: MP.primary, showAvatar: false),
          VGap(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            gap: 24,
            children: [
              // Identity
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const ExcludeSemantics(child: MpAvatar('TG', size: 72, fontSize: 24)),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tania Ghosh', style: tx(28, w: w800, h: 1.15, em: -0.02)),
                          const Gap(4),
                          Text('+91 98765 18210', style: tx(14, c: MP.ink2, h: _lh, tab: true)),
                          const Gap(6),
                          const MpBadge('Front desk', weight: w600),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // General
              _Section(
                title: 'General',
                rows: [
                  D10ListRow(
                    vPad: 0,
                    onTap: _pickLanguage,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(
                        children: [
                          const Ico(_globe, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(child: Text('Language', style: title)),
                          const Gap(12),
                          Text(_language, style: sub),
                          const Gap(12),
                          const Ico(I.chevronRight, size: 18, color: MP.ink3),
                        ],
                      ),
                    ),
                  ),
                  D10ListRow(
                    divider: true,
                    vPad: 12,
                    onTap: () => Nav.go(context, 'Clinic-Editor'),
                    child: Row(
                      children: [
                        const Ico(_building, size: 22, color: MP.ink2),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Clinic details', style: title),
                              const Gap(2),
                              Text(
                                'City Care Clinic · Salt Lake',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sub,
                              ),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.edit, size: 16, color: MP.primary),
                        const Gap(4),
                        Text('Edit', style: tx(14, w: w600, c: MP.primary, h: _lh)),
                      ],
                    ),
                  ),
                  D10ListRow(
                    divider: true,
                    vPad: 12,
                    // No account editor for front-desk staff in the design yet.
                    onTap: () => toast(context, 'Account settings are not in the design yet'),
                    child: Row(
                      children: [
                        const Ico(I.user, size: 22, color: MP.ink2),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Account', style: title),
                              const Gap(2),
                              Text('Name, phone and email', maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
                            ],
                          ),
                        ),
                        const Gap(12),
                        const Ico(I.chevronRight, size: 18, color: MP.ink3),
                      ],
                    ),
                  ),
                ],
              ),

              // Security
              _Section(
                title: 'Security',
                rows: [
                  D10ListRow(
                    vPad: 12,
                    child: Row(
                      children: [
                        const Ico(I.lock, size: 22, color: MP.ink2),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('App lock', style: title),
                              const Gap(2),
                              Text('Fingerprint or PIN to open MedPin', style: sub),
                            ],
                          ),
                        ),
                        const Gap(12),
                        _Switch(
                          value: _appLock,
                          label: 'App lock',
                          onChanged: (v) => setState(() => _appLock = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Log out
              D10ListCard(
                children: [
                  D10ListRow(
                    vPad: 0,
                    onTap: () => Nav.reset(context, 'Auth-Login'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(
                        children: [
                          const Ico(I.logout, size: 22, color: MP.ink2),
                          const Gap(12),
                          Expanded(child: Text('Log out', style: title)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Uppercase heading (12 / 1.35, 4px inset) over a list card, 8px apart.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => VGap(
        gap: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(header: true, child: D10Caps(title, lineHeight: 12 * 1.35)),
          ),
          D10ListCard(children: rows),
        ],
      );
}

/// 52×32 switch; knob 28px with this design's 0 1px 3px rgba(0,51,153,.24).
class _Switch extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  const _Switch({required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? MP.primary : MP.lineStrong,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: MP.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x3D003399), offset: Offset(0, 1), blurRadius: 3)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

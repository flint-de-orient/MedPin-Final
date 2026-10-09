import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d8.dart';

/// Design: Practice.dc.html — "Practice" (Clinic operations): masthead,
/// readiness checklist, summary tiles and the food-log review cadence.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

const _minor = ['Add a map link', 'Set holiday closures'];
const _done = ['Clinic hours', 'Letterhead', 'Team'];

/// (count, label, stem).
const _tiles = [('2', 'Locations', 'Clinics'), ('7', 'People', 'People'), ('2', 'Departments', 'Departments')];

const _cadence = ['Daily', 'Every 3 days', 'Weekly'];
const _cadenceCopy = ['every day', 'every 3 days', 'every week'];

class _PracticeScreenState extends State<PracticeScreen> {
  /// "Every 3 days" is selected in the design.
  int _cadenceIndex = 1;

  @override
  Widget build(BuildContext context) {
    return MpPage(
      header: const MpHeader('Practice'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gap: 16,
        children: [_masthead(context), _readiness(context), _summaryTiles(context), _cadenceCard()],
      ),
    );
  }

  // ── Masthead (hero) ───────────────────────────────────────────────────────

  Widget _masthead(BuildContext context) {
    return MpCard(
      radius: 20,
      shadow: MPShadow.float,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                image: true,
                label: 'No logo uploaded yet',
                child: const D8DashedBox(
                  width: 64,
                  height: 64,
                  radius: 12,
                  fill: MP.fill,
                  child: Center(child: Ico(I.image, size: 22, color: MP.ink3)),
                ),
              ),
              const Spacer(),
              D8Link(
                'Edit',
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () => Nav.go(context, 'Clinic-Editor'),
              ),
            ],
          ),
          const Gap(16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('City Care Clinic', style: tx(28, w: w800, h: 1.15, em: -0.02)),
              const Gap(4),
              Text('Diabetes and heart care since 2011', style: tx(16, c: MP.ink2, h: 1.5)),
              const Gap(4),
              Text('Reg. no. WB/CE/2011/0412', style: tx(14, c: MP.ink3, h: 1.45, tab: true)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Readiness checklist ───────────────────────────────────────────────────

  Widget _readiness(BuildContext context) {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Readiness', style: tx(20, w: w700, h: 1.25)),
              const Gap(2),
              Text('1 blocking · 2 optional · 3 done', style: tx(14, c: MP.ink2, h: 1.45)),
            ],
          ),
          const Gap(20),
          // Blocking
          const SectionLabel('Blocking', h: 1.35),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: MP.amberSoft, borderRadius: BorderRadius.circular(12)),
            child: Stack(
              children: [
                Row(
                  children: [
                    // Space for the warning icon (`align-self: flex-start`), drawn below.
                    const SizedBox(width: 20),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add your digital signature', style: tx(15, w: w600, h: 1.45)),
                          const Gap(2),
                          Text("Prescriptions can't be sent without it", style: tx(14, c: MP.amber, h: 1.45)),
                        ],
                      ),
                    ),
                    const Gap(12),
                    MpButton.small('Add', expand: false, onTap: () => Nav.go(context, 'Doctor-MyProfile')),
                  ],
                ),
                const Positioned(left: 0, top: 2, child: Ico(I.alert, size: 20, color: MP.amber)),
              ],
            ),
          ),
          const Gap(20),
          // Optional
          const Padding(padding: EdgeInsets.only(bottom: 4), child: SectionLabel('Optional', h: 1.35)),
          for (final m in _minor)
            Tap(
              onTap: () => Nav.go(context, 'Clinic-Editor'),
              radius: 0,
              child: _ChecklistRow(
                leading: const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: D8PendingIcon()),
                label: m,
                labelColor: MP.ink,
                trailing: const Ico(I.chevronRight, size: 18, color: MP.ink3),
              ),
            ),
          const Gap(20),
          // Done
          const Padding(padding: EdgeInsets.only(bottom: 4), child: SectionLabel('Done', h: 1.35)),
          for (final d in _done)
            _ChecklistRow(
              leading: const Ico(I.check, size: 20, color: MP.green, stroke: 2.25),
              label: d,
              labelColor: MP.ink2,
            ),
        ],
      ),
    );
  }

  // ── Summary tiles ─────────────────────────────────────────────────────────

  Widget _summaryTiles(BuildContext context) {
    return MpGrid(
      columns: 3,
      gap: 8,
      children: [
        for (final t in _tiles)
          Tap(
            onTap: () => Nav.go(context, t.$3),
            radius: 12,
            color: MP.white,
            border: MP.line,
            shadow: MPShadow.card,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$1, style: tx(30, w: w800, h: 1, em: -0.02, tab: true)),
                const Gap(6),
                Text(
                  t.$2,
                  style: tx(14, c: MP.ink2, h: 1.45),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Food-log review cadence ───────────────────────────────────────────────

  Widget _cadenceCard() {
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Food-log review cadence', style: tx(20, w: w700, h: 1.25)),
          const Gap(16),
          Semantics(
            container: true,
            label: 'Food-log review cadence',
            child: MpSegmented(
              options: _cadence,
              index: _cadenceIndex,
              onChanged: (i) => setState(() => _cadenceIndex = i),
            ),
          ),
          const Gap(16),
          Text(
            "Dieticians get each patient's food log for review ${_cadenceCopy[_cadenceIndex]}. "
            'Patients see when their next review is due.',
            style: tx(14, c: MP.ink2, h: 1.45),
          ),
        ],
      ),
    );
  }
}

/// 48px checklist row under a 1px top border (`box-sizing: content-box`).
class _ChecklistRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final Color labelColor;
  final Widget? trailing;
  const _ChecklistRow({required this.leading, required this.label, required this.labelColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 49,
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: MP.line))),
      child: Row(
        children: [
          leading,
          const Gap(12),
          Expanded(
            child: Text(label, style: tx(15, w: w500, c: labelColor), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) ...[const Gap(12), trailing!],
        ],
      ),
    );
  }
}

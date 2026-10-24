import 'package:flutter/material.dart' hide Text;

import '../../data/format.dart';
import '../../data/live.dart';
import '../../widgets/mp.dart';
import '../../widgets/payment_history.dart';
import 'common_d6.dart';
import '../../widgets/i18n.dart';

/// Design: Patient-Profile-Desk.dc.html — "Patient profile · front desk".
/// Live data: GET /api/patients/:id, /vitals and /prescriptions.
class PatientProfileDeskScreen extends StatefulWidget {
  const PatientProfileDeskScreen({super.key});

  @override
  State<PatientProfileDeskScreen> createState() => _PatientProfileDeskScreenState();
}

class _PatientProfileDeskScreenState extends State<PatientProfileDeskScreen> with LiveData {
  /// Desk care rows: icon, title, detail, target screen.
  static const _care = [
    (I.activity, 'Record vitals', 'Last recorded today, 8:52 AM', 'Staff-Vitals'),
    (I.upload, "Upload report for today's visit", 'Nothing uploaded for this visit yet', 'Records-Add'),
    (I.calendar, 'Book follow-up', 'City Care Clinic, Salt Lake', 'Appointments'),
    (I.message, 'Message patient', "Opens Priya's conversation", 'Patient-Thread'),
    (I.eye, 'Prescriptions (view only)', 'Latest 12 Mar 2026 · Dr. Arjun Sen', 'Prescriptions'),
  ];

  @override
  Future<Object?> fetch() => d6Load(context, {'vitals': '/vitals', 'rx': '/prescriptions'});

  /// The visit today (or the next one), for the card subtitle and row args.
  Map<String, dynamic>? _visit(D6Rec r) => r.nextVisit.isEmpty ? null : r.nextVisit;

  String? _visitLine(D6Rec r) {
    final v = _visit(r);
    final at = F.date(v?['startAt']);
    if (v == null || at == null) return null;
    final doctor = r.personName(v['doctorId']);
    final today = F.sameDay(at, DateTime.now());
    return [today ? "Today's visit · ${F.time(at)}" : 'Next visit · ${F.when(at)}', if (doctor != null) 'with $doctor'].join(' ');
  }

  List<(String, String, String, String)> _liveCare(D6Rec r) {
    final last = r.clinicVitals;
    final lastAt = F.date(last?['recordedAt']);
    final rx = r.m.obj('rx').list('items');
    final latest = rx.isEmpty ? null : rx.first;
    final rxAt = F.date(latest?['issuedAt']);
    return [
      (I.activity, 'Record vitals', lastAt == null ? 'No vitals recorded yet' : 'Last recorded ${d6When(lastAt)}', 'Staff-Vitals'),
      (I.upload, "Upload report for today's visit", 'Add a test report or prescription', 'Records-Add'),
      (I.calendar, 'Book follow-up', D6Rec.practiceName.isEmpty ? 'Choose a date and time' : D6Rec.practiceName, 'Appointments-Manage'),
      (I.message, 'Message patient', "Opens ${r.first}'s conversation", 'Patient-Thread'),
      (I.wallet, 'Payments', 'Fees paid and due, with receipts', 'Payments'),
      (
        I.eye,
        'Prescriptions (view only)',
        latest == null ? 'No prescriptions yet' : ['Latest ${rxAt == null ? '' : d6Date(rxAt)}', latest.str('doctorName')].where((s) => s.trim().isNotEmpty).join(' · '),
        'Prescriptions',
      ),
    ];
  }

  void _openLive(BuildContext context, D6Rec r, String stem) {
    final v = _visit(r);
    if (stem == 'Patient-Thread') {
      d6MessagePatient(context, r.id);
      return;
    }
    if (stem == 'Payments') {
      showPatientPayments(context, patientId: r.id, name: r.name);
      return;
    }
    d6Go(context, stem, {if (v != null && v['id'] != null) 'appointmentId': '${v['id']}'});
  }

  @override
  Widget build(BuildContext context) {
    final rec = data == null ? null : D6Rec(data!);
    final placeholder = livePlaceholder();
    final care = rec == null ? _care : _liveCare(rec);
    final sub = rec == null ? "Today's visit · 9:00 AM with Dr. Arjun Sen" : _visitLine(rec);
    return D6Scope(
      rec: rec,
      onChanged: () => reload(quiet: true),
      child: Builder(
        builder: (context) => MpPage(
          header: MpHeader(
            'Patient profile',
            actions: [
              MpIconButton(I.moreVSmall, label: 'More options', filled: true, onTap: rec == null ? null : () => d6MoreOptions(context)),
            ],
          ),
          body: placeholder ?? VGap(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            gap: 16,
            children: [
              const D6ProfileHero(),
              if (D6ConsentNote.shown(context)) const D6ConsentNote(),
              const D6RecordCaption(),
              const D6OverviewCard(),
              if (D6MeasurementsCard.shown(context)) const D6MeasurementsCard(),

              // Desk care (replaces prescribing for the front desk)
              MpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: D6Title('Desk care', sub: sub),
                    ),
                    for (var i = 0; i < care.length; i++)
                      D6Row(
                        padding: i == care.length - 1
                            ? const EdgeInsets.only(top: 14)
                            : const EdgeInsets.symmetric(vertical: 14),
                        onTap: () => rec == null ? Nav.go(context, care[i].$4) : _openLive(context, rec, care[i].$4),
                        child: Row(
                          children: [
                            Ico(care[i].$1, size: 22, color: MP.primary),
                            const Gap(14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(care[i].$2, style: tx(16, w: w600)),
                                  const Gap(2),
                                  Text(care[i].$3, style: tx(14, c: MP.ink2, h: 1.45)),
                                ],
                              ),
                            ),
                            const Gap(14),
                            const Ico(I.chevronRight, size: 18, color: MP.ink3),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/mp.dart';
import 'common_d3.dart';

/// Design: Report-Prescriptions.dc.html — "Report · Prescription register".
class ReportPrescriptionsScreen extends StatefulWidget {
  const ReportPrescriptionsScreen({super.key});

  @override
  State<ReportPrescriptionsScreen> createState() => _ReportPrescriptionsScreenState();
}

class _Rx {
  final String name;
  final String date;
  final String meds;
  final String ref;
  const _Rx(this.name, this.date, this.meds, this.ref);
}

const _medicines = [
  D3BarRow('Metformin 500 mg', '88', 1.00),
  D3BarRow('Glimepiride', '41', 0.47),
  D3BarRow('Telmisartan 40 mg', '36', 0.41),
  D3BarRow('Levothyroxine 50 mcg', '29', 0.33),
  D3BarRow('Atorvastatin 10 mg', '24', 0.27),
];

const _tests = [
  D3BarRow('HbA1c', '64', 1.00),
  D3BarRow('Lipid profile', '38', 0.59),
  D3BarRow('TSH', '27', 0.42),
  D3BarRow('Kidney function (KFT)', '19', 0.30),
];

const _rx = [
  _Rx('Sanjay Ghosh', '30 Sep', 'Metformin 500 mg · Glimepiride 1 mg', 'Rx 0286 · HbA1c'),
  _Rx('Rina Dutta', '30 Sep', 'Telmisartan 40 mg', 'Rx 0285 · Lipid profile, KFT'),
  _Rx('Tapas Kar', '30 Sep', 'Telmisartan 40 mg · Metformin 500 mg', 'Rx 0284 · No tests'),
  _Rx('Priya Sharma', '29 Sep', 'Metformin 500 mg · Vitamin D3 60,000 IU', 'Rx 0279 · HbA1c'),
  _Rx('Nasreen Begum', '29 Sep', 'Levothyroxine 50 mcg', 'Rx 0278 · TSH'),
];

/// Revealed by "Show more prescriptions".
const _rxMore = [
  _Rx('Subrata Pal', '29 Sep', 'Atorvastatin 10 mg · Telmisartan 40 mg', 'Rx 0277 · Lipid profile'),
  _Rx('Mousumi Dey', '29 Sep', 'Metformin 500 mg', 'Rx 0276 · HbA1c'),
  _Rx('Sudipta Roy', '29 Sep', 'Levothyroxine 50 mcg', 'Rx 0275 · TSH'),
  _Rx('Ashok Banerjee', '28 Sep', 'Glimepiride 1 mg · Atorvastatin 10 mg', 'Rx 0274 · KFT'),
  _Rx('Lipika Saha', '28 Sep', 'Ferrous sulphate 200 mg · Folic acid 5 mg', 'Rx 0273 · No tests'),
];

class _ReportPrescriptionsScreenState extends State<ReportPrescriptionsScreen> {
  String _q = '';
  bool _more = false;

  bool _hit(_Rx r, String q) =>
      q.isEmpty ||
      r.name.toLowerCase().contains(q) ||
      r.meds.toLowerCase().contains(q) ||
      r.ref.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = [..._rx, if (_more || q.isNotEmpty) ..._rxMore].where((r) => _hit(r, q)).toList();
    return MpPage(
      header: D3ReportHeader(
        title: 'Prescription register',
        subtitle: '271 prescriptions · 1 – 30 Sep',
        searchHint: 'Search patient, medicine or Rx number',
        onSearch: (s) => setState(() => _q = s),
      ),
      bottom: const D3DownloadBar('Download register'),
      body: VGap(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 23),
        gap: 12,
        children: [
          const D3StatTiles([
            ('271', 'Prescriptions', MP.ink),
            ('612', 'Medicines', MP.ink),
            ('148', 'Lab tests', MP.ink),
          ]),
          const D3BarCard(title: 'Most prescribed medicines', note: 'Prescriptions', rows: _medicines),
          const D3BarCard(title: 'Most ordered tests', note: 'Orders', rows: _tests),
          const D3SectionHead('All prescriptions', trailing: 'Newest first'),
          if (rows.isNotEmpty)
            D3ListCard(children: [for (final r in rows) _row(r)])
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No prescriptions match “${_q.trim()}”',
                textAlign: TextAlign.center,
                style: tx(15, c: MP.ink2),
              ),
            ),
          if (!_more && q.isEmpty) D3ShowMore('Show more prescriptions', onTap: () => setState(() => _more = true)),
        ],
      ),
    );
  }

  Widget _row(_Rx r) => D3RegisterRow(
    name: r.name,
    trailing: Text(r.date, style: tx(13, w: w500, c: MP.ink3)),
    detail: r.meds,
    footer: Row(
      children: [
        Expanded(child: Text(r.ref, style: tx(13, c: MP.ink3))),
        const SizedBox(width: 8),
        D3TextLink('View', onTap: () => Nav.go(context, 'PP-Prescriptions')),
      ],
    ),
    onTap: () => Nav.go(context, 'PP-Summary'),
  );
}

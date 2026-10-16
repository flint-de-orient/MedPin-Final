import '../../data/live.dart';
import 'common_d9.dart';

/// What the People-Add / People-Member forms offer, from GET /api/members/options:
/// the practice's active locations, the doctors who practise at each (with the
/// departments they practise in) and every department name. Null [raw] = the
/// design sample.
class TeamOptions {
  TeamOptions(this.raw);
  final Map<String, dynamic>? raw;

  /// Roles whose form asks for a department; the rest (front desk, lab roles,
  /// practice manager) work across departments.
  static const departmentRoles = {'Doctor', "Doctor's assistant", 'Dietician'};
  static const noDepartment = 'None';

  static const _sampleDoctors = [
    (id: 'as', name: 'Dr. Arjun Sen', locationIds: {'0', '1'}, departments: ['Diabetology']),
    (id: 'rm', name: 'Dr. Rina Mitra', locationIds: {'0'}, departments: ['Cardiology']),
  ];
  static const _sampleDepartments = ['Cardiology', 'Diabetology', 'Endocrinology', 'General medicine', 'Gynaecology', 'Nephrology'];

  /// (id, name) of the active locations.
  List<(String, String)> get locations => raw == null
      ? [for (var i = 0; i < D9Locations.names.length; i++) ('$i', D9Locations.names[i])]
      : [for (final l in raw!.list('locations')) (l.str('id'), l.str('name'))];

  List<({String id, String name, Set<String> locationIds, List<String> departments})> get doctors => raw == null
      ? _sampleDoctors
      : [
          for (final d in raw!.list('doctors'))
            (
              id: d.str('userId'),
              name: d.str('name'),
              locationIds: {for (final x in (d['locationIds'] as List? ?? const [])) '$x'},
              departments: [for (final x in (d['departments'] as List? ?? const [])) '$x'],
            ),
        ];

  /// Doctors who practise at any of [locationIds] (every doctor when none is chosen).
  List<({String id, String name, Set<String> locationIds, List<String> departments})> doctorsAt(Set<String> locationIds) {
    final all = doctors;
    if (locationIds.isEmpty) return all;
    return [for (final d in all) if (d.locationIds.any(locationIds.contains)) d];
  }

  /// Department choices for [role]: a doctor picks their own specialty from all
  /// departments; an assistant gets the departments of the doctor(s) they
  /// assist; a dietician those of the doctors at their locations. Empty = no
  /// department field for this role.
  List<String> departmentsFor(String role, Set<String> locationIds, {Set<String> assists = const {}}) {
    if (!departmentRoles.contains(role)) return const [];
    if (role == 'Doctor') {
      final all = raw == null ? _sampleDepartments : [for (final x in (raw!['departments'] as List? ?? const [])) '$x'];
      return [noDepartment, ...all];
    }
    final from = role == "Doctor's assistant" && assists.isNotEmpty
        ? [for (final d in doctors) if (assists.contains(d.id)) d]
        : doctorsAt(locationIds);
    final out = <String>[];
    for (final d in from) {
      for (final dep in d.departments) {
        if (!out.contains(dep)) out.add(dep);
      }
    }
    return out;
  }
}

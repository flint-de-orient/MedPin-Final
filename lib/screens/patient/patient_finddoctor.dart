import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../data/api.dart';
import '../../data/format.dart';
import '../../data/live.dart';
import '../../data/voice.dart';
import '../../data/where.dart';
import '../../widgets/mp.dart';
import 'common_p2.dart';
import '../../data/checkout.dart';
import '../../widgets/i18n.dart';

/// Patient app · Find a doctor. Not an artboard in the design canvas: opened
/// from the "Find a new doctor" banner on the Doctor tab. Lists every doctor
/// on MedPin and lets the patient describe what they need to MedPin AI.
///
/// Live data: GET /api/patient/doctors/search (every doctor taking bookings,
/// nearest first). MedPin AI matching runs on the device over that list. The
/// booking sheet reads GET /api/patient/doctors/:id/slots?next=3 and sends
/// POST /api/patient/visit-requests (booked at once when the doctor allows it).
class PatientFinddoctorScreen extends StatefulWidget {
  const PatientFinddoctorScreen({super.key});

  @override
  State<PatientFinddoctorScreen> createState() => _PatientFinddoctorScreenState();
}

// ── Directory ────────────────────────────────────────────────────────────────

class _Spec {
  final String key;
  final String label;

  /// How the AI names it in a sentence ("a Heart specialist").
  final String role;
  final String icon;
  const _Spec(this.key, this.label, this.role, this.icon);
}

const _icWomen = '<circle cx="12" cy="9" r="5"/><path d="M12 14v8M9 19h6"/>';
const _icChild =
    '<path d="M9 12h.01M15 12h.01M10 16c.5.3 1.2.5 2 .5s1.5-.2 2-.5"/><path d="M19 6.3a9 9 0 0 1 1.8 3.9 2 2 0 0 1 0 3.6 9 9 0 0 1-17.6 0 2 2 0 0 1 0-3.6A9 9 0 0 1 12 3c2 0 3.5 1.1 3.5 2.5s-.9 2.5-2 2.5c-.8 0-1.5-.4-1.5-1"/>';
const _icSkin =
    '<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/><path d="M8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01"/>';
const _icBone =
    '<path d="M17 10c.7-.7 1.69 0 2.5 0a2.5 2.5 0 1 0 0-5 .5.5 0 0 1-.5-.5 2.5 2.5 0 1 0-5 0c0 .81.7 1.8 0 2.5l-7 7c-.7.7-1.69 0-2.5 0a2.5 2.5 0 0 0 0 5c.28 0 .5.22.5.5a2.5 2.5 0 1 0 5 0c0-.81-.7-1.8 0-2.5Z"/>';
const _icMind = '<circle cx="12" cy="12" r="9"/><path d="M8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01"/>';
const _icStomach =
    '<path d="M12 21a9 9 0 0 0 9-9H3a9 9 0 0 0 9 9Z"/><path d="M7 21h10M19.5 12 22 6"/><path d="M8 3c.3.1.8.5.8 1.4S7.9 5.6 7.9 6.4 8.3 7.6 8.7 8M12 3c.3.1.8.5.8 1.4s-.9 1.2-.9 2 .4 1.2.8 1.6"/>';
const _icTooth =
    '<path d="M7 3c-2.5 0-4 2-4 4.5 0 3 1.5 4.5 2 7 .5 2.5 1 6.5 2.5 6.5S9 18 10 16c.5-1 1.5-1 2-1s1.5 0 2 1c1 2 1 5 2.5 5s2-4 2.5-6.5c.5-2.5 2-4 2-7C21 5 19.5 3 17 3c-2 0-3 1-5 1S9 3 7 3Z"/>';
const _icEar =
    '<path d="M6 8.5a6.5 6.5 0 1 1 13 0c0 6-6 6-6 10a3.5 3.5 0 1 1-7 0"/><path d="M15 8.5a2.5 2.5 0 0 0-5 0v1a2 2 0 1 1 0 4"/>';
const _icVideo =
    '<path d="m16 13 5.2 3.5a.5.5 0 0 0 .8-.4V7.9a.5.5 0 0 0-.8-.4L16 11"/><rect x="2" y="6" width="14" height="12" rx="2"/>';
const _icGlobe = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>';

const _specs = [
  _Spec('gp', 'General', 'General physician', I.stethoscope),
  _Spec('diabetes', 'Diabetes & thyroid', 'Diabetes and thyroid specialist', I.drop),
  _Spec('heart', 'Heart', 'Heart specialist (cardiologist)', I.heart),
  _Spec('women', "Women's health", 'Gynaecologist', _icWomen),
  _Spec('child', 'Child', 'Child specialist (paediatrician)', _icChild),
  _Spec('skin', 'Skin & hair', 'Skin specialist (dermatologist)', _icSkin),
  _Spec('bones', 'Bones & joints', 'Bone and joint specialist (orthopaedic)', _icBone),
  _Spec('mind', 'Mind', 'Mental health specialist (psychiatrist)', _icMind),
  _Spec('stomach', 'Stomach', 'Stomach specialist (gastroenterologist)', _icStomach),
  _Spec('eye', 'Eye', 'Eye specialist (ophthalmologist)', I.eye),
  _Spec('teeth', 'Teeth', 'Dentist', _icTooth),
  _Spec('ent', 'Ear, nose & throat', 'ENT specialist', _icEar),
];

_Spec _spec(String key) => _specs.firstWhere((s) => s.key == key, orElse: () => _specs.first);

class _Doc {
  final String initials;
  final String name;
  final String spec;
  final String title;
  final String clinic;
  final String area;
  final double? km;
  final int? years;
  final List<String> langs;
  final bool female;
  final bool video;
  final bool today;
  final String next;
  final int? fee;
  final bool mine;
  final String about;

  /// Live only: the doctor's user id and the clinic location to book at.
  final String? id;
  final String? locationId;
  const _Doc({
    required this.initials,
    required this.name,
    required this.spec,
    required this.title,
    required this.clinic,
    required this.area,
    required this.km,
    required this.years,
    required this.langs,
    required this.next,
    required this.fee,
    required this.about,
    this.female = false,
    this.video = false,
    this.today = false,
    this.mine = false,
    this.id,
    this.locationId,
  });

  /// A doctor card from the API (search results and the doctor page).
  factory _Doc.fromJson(Map<String, dynamic> j) {
    final name = j.str('name', 'Doctor');
    final keys = [for (final k in (j['specialtyKeys'] as List? ?? const [])) '$k'];
    final spec = keys.isEmpty ? 'gp' : keys.first;
    final loc = j.obj('location');
    final next = F.date(j.obj('nextSlot')['startAt']);
    return _Doc(
      initials: j.str('initials', F.initials(name)),
      name: name,
      spec: spec,
      title: j.str('headline', j.str('specialty', _spec(spec).label)),
      clinic: j.str('clinic', loc.str('name')),
      area: loc.str('area'),
      km: (j['km'] as num?)?.toDouble(),
      years: (j['years'] as num?)?.toInt(),
      langs: [for (final l in (j['languages'] as List? ?? const [])) '$l'],
      next: next == null ? 'No online times this week' : F.when(next),
      fee: (j['fee'] as num?)?.toInt(),
      about: j.str('bio', j.str('headline')),
      female: j['gender'] == 'female',
      video: j['video'] == true,
      today: j['availableToday'] == true,
      mine: j['mine'] == true,
      id: j.str('doctorId'),
      locationId: loc.str('id').isEmpty ? null : loc.str('id'),
    );
  }

  String get feeText => fee == null ? '—' : '₹$fee';
}

/// Opens the booking sheet for one doctor (Doctor tab "Book a visit",
/// doctor page "Book"). Returns true when a visit was booked or requested.
Future<bool> openDoctorBooking(BuildContext context, String doctorId) async {
  // Distance from where the phone is now, like the list (cached; no prompt here).
  final here = await Where.here(ask: false).timeout(const Duration(seconds: 3), onTimeout: () => null);
  if (!context.mounted) return false;
  final card = await runAction(
    context,
    () => Api.I.get('/api/patient/doctors/$doctorId', query: here == null ? null : {'lat': '${here.lat}', 'lng': '${here.lng}'}),
  );
  if (card is! Map || !context.mounted) return false;
  final doc = _Doc.fromJson(card.cast<String, dynamic>());
  final res = await openSheet<String>(context, (_) => _DoctorSheet(doc: doc, showPage: false));
  if (res == null || res == '__page' || !context.mounted) return false;
  toast(context, res);
  return true;
}

const _doctors = [
  _Doc(
    initials: 'AS',
    name: 'Dr. Arjun Sen',
    spec: 'diabetes',
    title: 'Diabetes & hormones',
    clinic: 'City Care Clinic',
    area: 'Salt Lake',
    km: 1.2,
    years: 14,
    langs: ['Bengali', 'Hindi', 'English'],
    video: true,
    today: true,
    next: 'Today, 5:00 PM',
    fee: 700,
    mine: true,
    about: 'Treats diabetes, thyroid and PCOS. Your doctor since June 2025.',
  ),
  _Doc(
    initials: 'RM',
    name: 'Dr. Rina Mitra',
    spec: 'heart',
    title: 'Heart',
    clinic: 'City Care Clinic',
    area: 'Salt Lake',
    km: 1.2,
    years: 18,
    langs: ['Bengali', 'English'],
    female: true,
    next: 'Thu, 8 Oct · 11:00 AM',
    fee: 900,
    mine: true,
    about: 'Heart rhythm, blood pressure and cholesterol care.',
  ),
  _Doc(
    initials: 'NG',
    name: 'Dr. Nandita Gupta',
    spec: 'women',
    title: 'Gynaecology',
    clinic: 'Apollo Clinic',
    area: 'Park Street',
    km: 6.4,
    years: 16,
    langs: ['Hindi', 'English'],
    female: true,
    video: true,
    next: 'Fri, 9 Oct · 4:30 PM',
    fee: 1000,
    mine: true,
    about: 'Periods, PCOS, pregnancy and menopause care.',
  ),
  _Doc(
    initials: 'AG',
    name: 'Dr. Ananya Ghosh',
    spec: 'diabetes',
    title: 'Diabetes & thyroid',
    clinic: 'Thyroid & Diabetes Centre',
    area: 'Salt Lake',
    km: 1.8,
    years: 11,
    langs: ['Bengali', 'English'],
    female: true,
    video: true,
    today: true,
    next: 'Today, 7:15 PM',
    fee: 800,
    about: 'Diabetes, thyroid and weight care, with diet plans from the clinic dietician.',
  ),
  _Doc(
    initials: 'SB',
    name: 'Dr. Suchitra Bose',
    spec: 'gp',
    title: 'General physician',
    clinic: 'Family Health Clinic',
    area: 'Bidhannagar',
    km: 0.9,
    years: 20,
    langs: ['Bengali', 'Hindi', 'English'],
    female: true,
    video: true,
    today: true,
    next: 'Today, 6:30 PM',
    fee: 500,
    about: 'Fever, infections, check-ups and everyday health problems for the whole family.',
  ),
  _Doc(
    initials: 'SN',
    name: 'Dr. Sourav Banerjee',
    spec: 'gp',
    title: 'General physician',
    clinic: 'City Care Clinic',
    area: 'New Town',
    km: 6.8,
    years: 9,
    langs: ['Bengali', 'English'],
    video: true,
    today: true,
    next: 'Today, 8:00 PM',
    fee: 450,
    about: 'First visit for most problems. Evening clinic on weekdays.',
  ),
  _Doc(
    initials: 'VM',
    name: 'Dr. Vikram Mehta',
    spec: 'heart',
    title: 'Heart',
    clinic: 'Heart Point',
    area: 'New Town',
    km: 7.2,
    years: 22,
    langs: ['Hindi', 'English'],
    next: 'Tomorrow, 10:00 AM',
    fee: 1200,
    about: 'Chest pain, breathlessness, ECG and echo reviews.',
  ),
  _Doc(
    initials: 'SD',
    name: 'Dr. Sreya Dutta',
    spec: 'women',
    title: 'Gynaecology',
    clinic: 'Mother & Child Clinic',
    area: 'Salt Lake',
    km: 2.4,
    years: 12,
    langs: ['Bengali', 'Hindi', 'English'],
    female: true,
    today: true,
    next: 'Today, 5:45 PM',
    fee: 900,
    about: 'Period problems, PCOS, fertility and pregnancy care.',
  ),
  _Doc(
    initials: 'KH',
    name: 'Dr. Kabir Hussain',
    spec: 'child',
    title: 'Child specialist',
    clinic: 'Little Steps Clinic',
    area: 'Kankurgachi',
    km: 3.4,
    years: 15,
    langs: ['Bengali', 'Hindi', 'English'],
    video: true,
    today: true,
    next: 'Today, 7:00 PM',
    fee: 700,
    about: 'Newborn to teens: fever, growth, vaccines and nutrition.',
  ),
  _Doc(
    initials: 'IB',
    name: 'Dr. Ishita Basu',
    spec: 'skin',
    title: 'Skin & hair',
    clinic: 'Skin & Hair Studio',
    area: 'Sector V',
    km: 2.1,
    years: 8,
    langs: ['Bengali', 'English'],
    female: true,
    video: true,
    next: 'Tomorrow, 12:30 PM',
    fee: 800,
    about: 'Rashes, acne, allergies, hair fall and dandruff.',
  ),
  _Doc(
    initials: 'AD',
    name: 'Dr. Anirban Das',
    spec: 'bones',
    title: 'Bones & joints',
    clinic: 'Bone & Joint Centre',
    area: 'Ultadanga',
    km: 4.2,
    years: 17,
    langs: ['Bengali', 'Hindi', 'English'],
    next: 'Tomorrow, 9:30 AM',
    fee: 900,
    about: 'Knee, back, neck and shoulder pain; sports injuries and arthritis.',
  ),
  _Doc(
    initials: 'MI',
    name: 'Dr. Meera Iyer',
    spec: 'mind',
    title: 'Mental health',
    clinic: 'Mindful Care',
    area: 'Ballygunge',
    km: 7.9,
    years: 13,
    langs: ['Hindi', 'English'],
    female: true,
    video: true,
    today: true,
    next: 'Today, 9:00 PM · video',
    fee: 1100,
    about: 'Stress, anxiety, low mood and sleep problems. Video visits available.',
  ),
  _Doc(
    initials: 'TA',
    name: 'Dr. Tanvir Ahmed',
    spec: 'stomach',
    title: 'Stomach & liver',
    clinic: 'City Care Clinic',
    area: 'Salt Lake',
    km: 1.2,
    years: 10,
    langs: ['Bengali', 'Hindi', 'English'],
    next: 'Tomorrow, 5:00 PM',
    fee: 850,
    about: 'Acidity, gas, constipation, loose motions and liver care.',
  ),
  _Doc(
    initials: 'PC',
    name: 'Dr. Priyanka Chatterjee',
    spec: 'eye',
    title: 'Eye',
    clinic: 'Eye Care Centre',
    area: 'Lake Town',
    km: 3.0,
    years: 9,
    langs: ['Bengali', 'English'],
    female: true,
    today: true,
    next: 'Today, 6:00 PM',
    fee: 600,
    about: 'Blurry vision, glasses, eye checks for diabetes.',
  ),
  _Doc(
    initials: 'NA',
    name: 'Dr. Nikhil Agarwal',
    spec: 'teeth',
    title: 'Dentist',
    clinic: 'Smile Dental',
    area: 'Salt Lake',
    km: 1.6,
    years: 7,
    langs: ['Hindi', 'English'],
    next: 'Tomorrow, 11:00 AM',
    fee: 500,
    about: 'Tooth pain, cleaning, fillings and root canal.',
  ),
  _Doc(
    initials: 'AR',
    name: 'Dr. Arnab Sinha',
    spec: 'ent',
    title: 'Ear, nose & throat',
    clinic: 'City Care Clinic',
    area: 'New Town',
    km: 6.8,
    years: 12,
    langs: ['Bengali', 'English'],
    video: true,
    next: 'Sat, 10 Oct · 10:30 AM',
    fee: 700,
    about: 'Ear pain, sinus, sore throat, tonsils and hearing checks.',
  ),
];

// ── MedPin AI (on-device intent matching) ────────────────────────────────────

class _Intent {
  final String query;
  final List<String> specs;
  final List<String> heard;
  final String? lang;
  final bool female;
  final bool video;
  final bool today;
  final String? area;
  final bool emergency;
  const _Intent({
    required this.query,
    required this.specs,
    required this.heard,
    this.lang,
    this.female = false,
    this.video = false,
    this.today = false,
    this.area,
    this.emergency = false,
  });
}

/// Symptom and need words → specialty. Longer phrases first so "chest pain"
/// wins over "pain".
const _symptoms = <String, String>{
  'high sugar': 'diabetes',
  'blood sugar': 'diabetes',
  'sugar': 'diabetes',
  'diabetes': 'diabetes',
  'diabetic': 'diabetes',
  'thyroid': 'diabetes',
  'hba1c': 'diabetes',
  'insulin': 'diabetes',
  'burning feet': 'diabetes',
  'numb': 'diabetes',
  'thirsty': 'diabetes',
  'weight gain': 'diabetes',
  'hormone': 'diabetes',
  'chest pain': 'heart',
  'chest': 'heart',
  'heart': 'heart',
  'palpitation': 'heart',
  'blood pressure': 'heart',
  'bp': 'heart',
  'breathless': 'heart',
  'short of breath': 'heart',
  'cholesterol': 'heart',
  'period': 'women',
  'pregnan': 'women',
  'pcos': 'women',
  'pcod': 'women',
  'gynae': 'women',
  'gyneco': 'women',
  'menopause': 'women',
  'white discharge': 'women',
  'child': 'child',
  'baby': 'child',
  'kid': 'child',
  'kids': 'child',
  'son': 'child',
  'daughter': 'child',
  'infant': 'child',
  'vaccin': 'child',
  'rash': 'skin',
  'skin': 'skin',
  'itch': 'skin',
  'acne': 'skin',
  'pimple': 'skin',
  'hair fall': 'skin',
  'dandruff': 'skin',
  'eczema': 'skin',
  'knee': 'bones',
  'joint': 'bones',
  'back pain': 'bones',
  'backache': 'bones',
  'bone': 'bones',
  'fracture': 'bones',
  'shoulder': 'bones',
  'neck pain': 'bones',
  'arthritis': 'bones',
  'stress': 'mind',
  'anxiety': 'mind',
  'anxious': 'mind',
  'sleep': 'mind',
  'insomnia': 'mind',
  'depress': 'mind',
  'panic': 'mind',
  'low mood': 'mind',
  'stomach': 'stomach',
  'acidity': 'stomach',
  'gas': 'stomach',
  'constipation': 'stomach',
  'loose motion': 'stomach',
  'diarrh': 'stomach',
  'liver': 'stomach',
  'indigestion': 'stomach',
  'vomit': 'stomach',
  'eye': 'eye',
  'eyes': 'eye',
  'vision': 'eye',
  'blurry': 'eye',
  'spectacle': 'eye',
  'glasses': 'eye',
  'tooth': 'teeth',
  'teeth': 'teeth',
  'dental': 'teeth',
  'gum': 'teeth',
  'gums': 'teeth',
  'ear': 'ent',
  'ears': 'ent',
  'throat': 'ent',
  'sinus': 'ent',
  'tonsil': 'ent',
  'nose': 'ent',
  'fever': 'gp',
  'cold': 'gp',
  'cough': 'gp',
  'flu': 'gp',
  'headache': 'gp',
  'body ache': 'gp',
  'check-up': 'gp',
  'checkup': 'gp',
  'infection': 'gp',
  'tired': 'gp',
  'weak': 'gp',
};

const _emergencyWords = [
  'chest pain',
  "can't breathe",
  'cannot breathe',
  'not breathing',
  'faint',
  'unconscious',
  'stroke',
  'severe bleeding',
  'heart attack',
  'seizure',
];

const _areas = [
  'salt lake',
  'new town',
  'park street',
  'bidhannagar',
  'kankurgachi',
  'sector v',
  'ultadanga',
  'ballygunge',
  'lake town',
];

String _title(String s) => s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// Matches [key] at a word start; short keys must be whole words, so "ear"
/// doesn't fire on "near" or "years".
RegExp _wordRe(String key) =>
    RegExp(key.length <= 4 ? '(?<![a-z])${RegExp.escape(key)}(?![a-z])' : '(?<![a-z])${RegExp.escape(key)}');

_Intent _understand(String raw, {String nearArea = 'Salt Lake'}) {
  final q = ' ${raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  final specs = <String>[];
  final heard = <String>[];
  var rest = q;
  final keys = _symptoms.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    final re = _wordRe(k);
    if (re.hasMatch(rest)) {
      final s = _symptoms[k]!;
      if (!specs.contains(s)) specs.add(s);
      heard.add(k);
      rest = rest.replaceAll(re, ' ');
    }
  }
  // "Tired" alone points to a GP, but next to sugar words it's the diabetes doctor.
  if (specs.contains('diabetes') &&
      specs.contains('gp') &&
      !heard.any((h) => ['fever', 'cold', 'cough', 'flu'].contains(h))) {
    specs.remove('gp');
  }
  // A specialist first, the general physician as the fallback.
  if (specs.length > 1 && specs.remove('gp')) specs.add('gp');
  String? lang;
  if (RegExp(r'bengali|bangla|বাংলা').hasMatch(q)) lang = 'Bengali';
  if (RegExp(r'hindi|हिन्दी|हिंदी').hasMatch(q)) lang = 'Hindi';
  final female = RegExp(r'female|(?<![a-z])wom[ae]n(?![a-z])|(?<![a-z])lady(?![a-z])|mahila').hasMatch(q);
  final video = RegExp(r'(?<![a-z])(video|online|call)(?![a-z])|from home').hasMatch(q);
  final today = RegExp(r'(?<![a-z])(today|now|tonight|urgent)(?![a-z])').hasMatch(q);
  String? area;
  for (final a in _areas) {
    if (q.contains(a)) area = _title(a);
  }
  if (area == null && nearArea.isNotEmpty && RegExp(r'near me|nearby|close to me').hasMatch(q)) area = nearArea;
  final emergency = _emergencyWords.any(q.contains) || (q.contains('chest') && RegExp(r'breath|sweat').hasMatch(q));
  return _Intent(
    query: raw.trim(),
    specs: specs,
    heard: heard,
    lang: lang,
    female: female,
    video: video,
    today: today,
    area: area,
    emergency: emergency,
  );
}

String _joinAnd(List<String> xs) {
  if (xs.isEmpty) return '';
  if (xs.length == 1) return xs.first;
  return '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
}

/// "350 m", "2.4 km"; "Nearby" within 50 m (GPS isn't more exact than that).
String distanceLabel(double km) {
  if (km < 0.05) return 'Nearby';
  if (km < 1) return '${((km * 1000) / 10).round() * 10} m';
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

// ── Screen ───────────────────────────────────────────────────────────────────

class _PatientFinddoctorScreenState extends State<PatientFinddoctorScreen>
    with SingleTickerProviderStateMixin, LiveData {
  @override
  Future<Object?> fetch() async {
    final here = await Where.here().timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (here != null && !_savedHere) {
      _savedHere = true;
      Api.I.patch('/api/patient/me', {'lat': here.lat, 'lng': here.lng}).catchError((_) => null);
    }
    return Api.I.get('/api/patient/doctors/search', query: here == null ? null : {'lat': '${here.lat}', 'lng': '${here.lng}'});
  }

  static bool _savedHere = false;

  bool _argsRead = false;

  /// `args: {'specialty': 'heart'}` (Ask AI, home) starts on that specialty.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final a = Nav.args<Object>(context);
    final key = a is Map ? a['specialty'] : (a is String ? a : null);
    if (key is String && _specs.any((s) => s.key == key)) _specKey = key;
  }

  /// Every doctor: the live directory, or the design sample.
  List<_Doc> get _all => data == null
      ? (isLive ? const [] : _doctors)
      : [for (final d in data!.list('items')) _Doc.fromJson(d)];

  /// The patient's area ("near Salt Lake").
  String get _area => data == null ? (isLive ? '' : 'Salt Lake') : data!.str('area');

  final _ask = TextEditingController();
  final _askFocus = FocusNode();
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  // Created up front: a lazy controller would first be built inside dispose().
  late final AnimationController _dots;
  Timer? _thinkTimer;

  _Intent? _intent;
  bool _thinking = false;
  String? _specKey;
  bool _fToday = false, _fVideo = false, _fFemale = false, _fBengali = false, _fNear = false;
  bool _soonest = false;

  static const _examples = [
    'High sugar and always tired',
    'Itchy rash on my arms',
    'My child has fever since 2 days',
    'Irregular periods, female doctor',
    'Knee pain when climbing stairs',
    'Stress and poor sleep, video call',
  ];

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _askFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _thinkTimer?.cancel();
    _dots.dispose();
    _ask.dispose();
    _askFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search([String? text]) {
    if (text != null) _ask.text = text;
    final q = _ask.text.trim();
    if (q.isEmpty) {
      _askFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    _thinkTimer?.cancel();
    setState(() {
      _thinking = true;
      _specKey = null;
    });
    _dots.repeat();
    // A short pause so the answer reads as considered, not instant.
    _thinkTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      _dots.stop();
      setState(() {
        _thinking = false;
        _intent = _understand(q, nearArea: _area);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _resultsKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            alignment: 0.02,
          );
        }
      });
    });
  }

  void _clearAi() {
    _thinkTimer?.cancel();
    _dots.stop();
    setState(() {
      _intent = null;
      _thinking = false;
      _ask.clear();
    });
  }

  void _clearAll() {
    _clearAi();
    setState(() {
      _specKey = null;
      _fToday = _fVideo = _fFemale = _fBengali = _fNear = false;
    });
  }

  int _score(_Doc d, _Intent i) {
    var s = 0;
    if (i.specs.isNotEmpty) {
      final at = i.specs.indexOf(d.spec);
      if (at >= 0) s += 40 - at * 6;
    }
    if (i.lang != null && d.langs.contains(i.lang)) s += 8;
    if (i.female && d.female) s += 8;
    if (i.video && d.video) s += 6;
    if (i.today && d.today) s += 6;
    if (i.area != null && d.area == i.area) s += 6;
    if (d.mine) s += 2;
    return s;
  }

  /// The list after AI matching, specialty and filter chips. `relaxed` is set
  /// when the AI's extra wishes (language, gender…) matched nobody and only
  /// the specialty was kept.
  ({List<_Doc> docs, bool relaxed}) _results() {
    var docs = List<_Doc>.of(_all);
    var relaxed = false;
    final i = _intent;
    if (i != null) {
      final specs = i.specs.isEmpty ? ['gp'] : i.specs;
      docs = docs.where((d) => specs.contains(d.spec)).toList();
      final strict =
          docs.where((d) {
            if (i.lang != null && !d.langs.contains(i.lang)) return false;
            if (i.female && !d.female) return false;
            if (i.video && !d.video) return false;
            if (i.today && !d.today) return false;
            return true;
          }).toList();
      if (strict.isNotEmpty) {
        docs = strict;
      } else if (i.lang != null || i.female || i.video || i.today) {
        relaxed = true;
      }
    }
    if (_specKey != null) docs = docs.where((d) => d.spec == _specKey).toList();
    if (_fToday) docs = docs.where((d) => d.today).toList();
    if (_fVideo) docs = docs.where((d) => d.video).toList();
    if (_fFemale) docs = docs.where((d) => d.female).toList();
    if (_fBengali) docs = docs.where((d) => d.langs.contains('Bengali')).toList();
    if (_fNear) docs = docs.where((d) => d.km != null && d.km! <= 3).toList();

    // Unknown distance sorts last; live, the server's order (nearest, then
    // your doctors first) breaks ties.
    int byKm(_Doc a, _Doc b) => (a.km ?? 1e9).compareTo(b.km ?? 1e9);
    int byTime(_Doc a, _Doc b) => (a.today == b.today) ? byKm(a, b) : (a.today ? -1 : 1);
    final order = {for (var k = 0; k < docs.length; k++) docs[k]: k};
    docs.sort((a, b) {
      if (i != null) {
        final c = _score(b, i).compareTo(_score(a, i));
        if (c != 0) return c;
      }
      final c = _soonest ? byTime(a, b) : byKm(a, b);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
    return (docs: docs, relaxed: relaxed);
  }

  Future<void> _open(_Doc d) async {
    final slot = await openSheet<String>(context, (_) => _DoctorSheet(doc: d, showPage: d.id != null ? d.mine : null));
    if (slot == null || !mounted) return;
    if (slot == '__page') {
      Nav.go(context, 'Patient-DoctorDetail', args: d.id == null ? null : {'doctorId': d.id});
      return;
    }
    if (d.id != null) {
      // Live: the sheet already sent the request; [slot] is what happened.
      toast(context, slot);
      reload(quiet: true);
      return;
    }
    toast(context, 'Request sent to ${d.name} for $slot. The clinic will confirm.');
  }

  @override
  Widget build(BuildContext context) {
    final r = _results();
    final aiActive = _intent != null || _thinking;
    final total = _all.length;
    final placeholder = livePlaceholder();
    return MpPage(
      header: MpHeader(
        'Find a doctor',
        subtitle: placeholder != null
            ? 'Doctors on MedPin'
            : data != null && data!.containsKey('from') && data!['from'] == null
                // No location: distances can't be shown.
                ? '$total doctor${total == 1 ? '' : 's'} on MedPin · turn on location to see how far'
                : '$total doctor${total == 1 ? '' : 's'} on MedPin${_area.isEmpty ? '' : ' near $_area'}',
      ),
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: _askCard()),
            if (aiActive)
              Padding(key: _resultsKey, padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: _aiAnswer(r.relaxed)),
            if (!aiActive) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 20, 10),
                child: SectionLabel('Browse by specialty', h: 1.35),
              ),
              _specialtyRow(),
            ],
            const Gap(16),
            MpChipRow(
              gap: 8,
              children: [
                _filter('Available today', _fToday, (v) => _fToday = v),
                _filter('Video visit', _fVideo, (v) => _fVideo = v),
                _filter('Female doctor', _fFemale, (v) => _fFemale = v),
                _filter('Speaks Bengali', _fBengali, (v) => _fBengali = v),
                _filter('Within 3 km', _fNear, (v) => _fNear = v),
              ],
            ),
            Padding(
              key: aiActive ? null : _resultsKey,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text:
                            _intent != null
                                ? 'Best matches'
                                : (_specKey == null ? 'All doctors' : _spec(_specKey!).label),
                        style: tx(18, w: w700, h: 1.25),
                        children: [TextSpan(text: '  ${r.docs.length}', style: tx(15, w: w600, c: MP.ink3))],
                      ),
                    ),
                  ),
                  MpHitSlop(child: Tap(
                    onTap: () => setState(() => _soonest = !_soonest),
                    radius: 8,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Ico(I.filter, size: 16, color: MP.primary, stroke: 2),
                        const Gap(6),
                        Text(_soonest ? 'Soonest first' : 'Nearest first', style: tx(14, w: w600, c: MP.primary)),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            if (_thinking)
              const SizedBox.shrink()
            else if (placeholder != null)
              placeholder
            else if (r.docs.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _empty())
            else
              VGap(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gap: 12,
                children: [for (final d in r.docs) _DoctorCard(doc: d, onTap: () => _open(d))],
              ),
          ],
        ),
      ),
      scroll: false,
    );
  }

  // ── AI search card ────────────────────────────────────────────────────────

  Widget _askCard() {
    final focused = _askFocus.hasFocus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MPDeco.card(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const MpIconTile(I.sparkles, size: 40, radius: 12, iconSize: 20),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ask MedPin AI', style: tx(16, w: w700)),
                    const Gap(2),
                    Text('Describe your symptoms or the doctor you need', style: tx(13, c: MP.ink2, h: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: focused ? MP.white : MP.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: focused ? MP.primary : MP.lineStrong),
              boxShadow: focused ? MPShadow.focusRing : null,
            ),
            child: TextField(
              controller: _ask,
              focusNode: _askFocus,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: tx(16, h: 1.45),
              cursorColor: MP.primary,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: tr(context, 'e.g. High sugar and always tired, Bengali-speaking doctor near Salt Lake'),
                hintMaxLines: 3,
                hintStyle: tx(16, c: MP.ink3, h: 1.45),
              ),
            ),
          ),
          const Gap(10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (var i = 0; i < _examples.length; i++) ...[
                  if (i > 0) const Gap(6),
                  SizedBox(
                    height: 34,
                    child: Tap(
                      onTap: () => _search(_examples[i]),
                      radius: 999,
                      color: MP.white,
                      border: MP.lineStrong,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(widthFactor: 1, child: Text(_examples[i], style: tx(13, w: w600, c: MP.ink2))),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(14),
          Row(
            children: [
              MpIconButton(
                I.mic,
                label: 'Speak',
                size: 52,
                radius: 16,
                background: MP.primarySoft,
                color: MP.primary,
                onTap: () async {
                  final said = await Voice.dictate(context, title: 'Describe what you need', hint: 'e.g. “Skin doctor near me for an itchy rash”', purpose: 'symptoms');
                  if (said != null && mounted) _search(said);
                },
              ),
              const Gap(8),
              Expanded(child: MpButton('Find doctors', icon: I.sparkles, height: 52, onTap: _search)),
            ],
          ),
          const Gap(10),
          Text("MedPin AI suggests doctors. It doesn't diagnose.", style: tx(12, c: MP.ink3, h: 1.4)),
        ],
      ),
    );
  }

  // ── AI answer ─────────────────────────────────────────────────────────────

  Widget _aiAnswer(bool relaxed) {
    if (_thinking) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MP.primarySoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MP.primaryLine),
        ),
        child: Row(
          children: [
            const Ico(I.sparkles, size: 18, color: MP.primary),
            const Gap(10),
            Expanded(child: Text('MedPin AI is finding the right doctor…', style: tx(15, w: w600, c: MP.primary))),
            _ThinkingDots(animation: _dots),
          ],
        ),
      );
    }
    final i = _intent!;
    final specs = i.specs.isEmpty ? ['gp'] : i.specs;
    final first = _spec(specs.first);
    final also = specs.length > 1 ? _spec(specs[1]) : null;
    final wishes = <String>[
      if (i.lang != null) 'Speaks ${i.lang}',
      if (i.female) 'Female doctor',
      if (i.video) 'Video visit',
      if (i.today) 'Available today',
      if (i.area != null) 'Near ${i.area}',
    ];
    final because =
        i.heard.isEmpty
            ? "I couldn't tell the problem from that. A general physician is a good first visit."
            : 'Because you mentioned ${_joinAnd(i.heard.take(3).map((h) => '“$h”').toList())}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (i.emergency) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MP.redSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: MP.redLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MpIconTile(
                      I.emergency,
                      size: 40,
                      radius: 12,
                      iconSize: 20,
                      bg: MP.red,
                      fg: MP.white,
                      stroke: 2.25,
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('This may be an emergency', style: tx(16, w: w700)),
                          const Gap(2),
                          Text(
                            "Don't wait for a visit. Call 108 or go to the nearest hospital now.",
                            style: tx(14, c: MP.ink2, h: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                MpButton(
                  'Call 108',
                  kind: MpBtn.danger,
                  icon: I.phone,
                  height: 48,
                  radius: 12,
                  fontSize: 15,
                  onTap: () => isLive ? p2Open(context, 'tel:108', failed: 'Dial 108 from your phone') : toast(context, 'Dial 108 from your phone'),
                ),
              ],
            ),
          ),
          const Gap(12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MP.primarySoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MP.primaryLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Ico(I.sparkles, size: 16, color: MP.primary),
                  const Gap(6),
                  Expanded(child: Text('MEDPIN AI', style: tx(12, w: w800, c: MP.primary, em: 0.06))),
                  Tap(
                    onTap: _clearAi,
                    radius: 8,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text('Clear', style: tx(14, w: w600, c: MP.primary)),
                  ),
                ],
              ),
              const Gap(8),
              Text.rich(
                TextSpan(
                  text: 'You may need a ',
                  style: tx(17, w: w600, h: 1.4),
                  children: [
                    TextSpan(text: first.role, style: tx(17, w: w800, c: MP.primary, h: 1.4)),
                    if (also != null) ...[
                      const TextSpan(text: ' or a '),
                      TextSpan(text: also.role, style: tx(17, w: w800, c: MP.primary, h: 1.4)),
                    ],
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const Gap(4),
              Text(because, style: tx(14, c: MP.ink2, h: 1.45)),
              if (wishes.isNotEmpty) ...[
                const Gap(10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in wishes)
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: MP.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: MP.primaryLine),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Ico(I.check, size: 14, color: MP.primary, stroke: 2.5),
                            const Gap(4),
                            Text(w, style: tx(12, w: w600, c: MP.primary)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              if (relaxed) ...[
                const Gap(10),
                Text(
                  'No exact match for everything you asked, so these are the closest.',
                  style: tx(13, c: MP.ink2, h: 1.4),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Specialties, filters, empty state ─────────────────────────────────────

  Widget _specialtyRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < _specs.length; i++) ...[if (i > 0) const Gap(8), _specTile(_specs[i])],
        ],
      ),
    );
  }

  Widget _specTile(_Spec s) {
    final on = _specKey == s.key;
    return SizedBox(
      width: 84,
      height: MediaQuery.textScalerOf(context).scale(100).clamp(100, 140).toDouble(),
      child: Tap(
        onTap: () => setState(() => _specKey = on ? null : s.key),
        radius: 16,
        color: on ? MP.primarySoft : MP.white,
        border: on ? MP.primary : MP.line,
        shadow: MPShadow.card,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MpIconTile(s.icon, size: 40, radius: 12, iconSize: 20, bg: on ? MP.white : MP.primarySoft),
            const Gap(8),
            Text(
              s.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tx(12, w: w600, h: 1.25, c: on ? MP.primary : MP.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filter(String label, bool on, void Function(bool) set) =>
      MpChip(label, selected: on, tonal: true, icon: on ? I.check : null, onTap: () => setState(() => set(!on)));

  Widget _empty() => Container(
    padding: const EdgeInsets.all(24),
    decoration: MPDeco.card(),
    child: Column(
      children: [
        const MpIconTile(I.search, size: 52, radius: 16),
        const Gap(12),
        Text('No doctors match these filters', style: tx(16, w: w700)),
        const Gap(4),
        Text(
          'Try removing a filter or describe it differently.',
          textAlign: TextAlign.center,
          style: tx(14, c: MP.ink2, h: 1.45),
        ),
        const Gap(16),
        MpButton(
          'Clear filters',
          kind: MpBtn.secondary,
          height: 48,
          radius: 12,
          fontSize: 15,
          expand: false,
          onTap: _clearAll,
        ),
      ],
    ),
  );
}

// ── Pieces ───────────────────────────────────────────────────────────────────

class _ThinkingDots extends StatelessWidget {
  final Animation<double> animation;
  const _ThinkingDots({required this.animation});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder:
        (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const Gap(4),
              Opacity(
                opacity: 0.3 + 0.7 * (1 - ((animation.value * 3 - i) % 3).clamp(0.0, 1.0)),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: MP.primary, shape: BoxShape.circle),
                ),
              ),
            ],
          ],
        ),
  );
}

class _DocAvatar extends StatelessWidget {
  final _Doc doc;
  final double size;
  const _DocAvatar(this.doc, {this.size = 52});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        MpAvatar(doc.initials, size: size, fontSize: size * 0.33),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: doc.today ? MP.green : MP.lineStrong,
              shape: BoxShape.circle,
              border: Border.all(color: MP.white, width: 2),
            ),
          ),
        ),
      ],
    ),
  );
}

class _InfoPill extends StatelessWidget {
  final String icon;
  final String text;
  const _InfoPill(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: MP.fill, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Ico(icon, size: 14, color: MP.ink2, stroke: 2),
        const Gap(4),
        Text(text, style: tx(12, w: w600, c: MP.ink2)),
      ],
    ),
  );
}

class _DoctorCard extends StatelessWidget {
  final _Doc doc;
  final VoidCallback onTap;
  const _DoctorCard({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = doc;
    return MpCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocAvatar(d),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx(16, w: w700, h: 1.3),
                          ),
                        ),
                        const Gap(4),
                        const Svg(I.verifiedSvg, width: 16, height: 16),
                      ],
                    ),
                    Text(d.title, style: tx(14, c: MP.ink2, h: 1.4)),
                    Text(
                      [
                        if (d.years != null) '${d.years} yrs',
                        [d.clinic, d.area].where((x) => x.isNotEmpty).join(', '),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tx(13, c: MP.ink3, h: 1.4),
                    ),
                  ],
                ),
              ),
              if (d.mine) ...[const Gap(8), const MpBadge.green('Your doctor', height: 22, fontSize: 11, padX: 8)],
            ],
          ),
          const Gap(12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (d.km != null) _InfoPill(I.pin, distanceLabel(d.km!)),
              if (d.video) const _InfoPill(_icVideo, 'Video visit'),
              if (d.langs.isNotEmpty) _InfoPill(_icGlobe, d.langs.join(' · ')),
            ],
          ),
          const Gap(12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next available', style: tx(12, c: MP.ink3)),
                      const Gap(2),
                      Text(
                        d.next,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(14, w: w700, c: d.today ? MP.green : MP.ink),
                      ),
                    ],
                  ),
                ),
                const Gap(8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Fee', style: tx(12, c: MP.ink3)),
                    const Gap(2),
                    Text(d.feeText, style: tx(14, w: w700, tab: true)),
                  ],
                ),
                const Gap(12),
                SizedBox(
                  height: 40,
                  child: MpButton(
                    'Book',
                    kind: MpBtn.primary,
                    height: 40,
                    radius: 12,
                    fontSize: 14,
                    expand: false,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onTap: onTap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Doctor details with the next free times; pops the picked time, or
/// '__page' to open the patient's own doctor page (Dr. Sen).
///
/// Live (the doctor has an id) it loads the next three free times, sends the
/// visit request itself and pops the confirmation to show.
class _DoctorSheet extends StatefulWidget {
  final _Doc doc;

  /// Show "Open doctor page"; null → the design's rule (Dr. Sen only).
  final bool? showPage;
  const _DoctorSheet({required this.doc, this.showPage});
  @override
  State<_DoctorSheet> createState() => _DoctorSheetState();
}

class _DoctorSheetState extends State<_DoctorSheet> {
  bool get _live => widget.doc.id != null;
  late List<String> _slots = _live ? const [] : _slotsFor(widget.doc);
  late String? _slot = _slots.isEmpty ? null : _slots.first;

  /// Live: label → startAt (ISO) of each offered time.
  final _startAt = <String, String>{};
  bool _loadingSlots = false;
  final _busy = ValueNotifier(false);

  /// Live (GET /doctors/:id/booking): where the doctor sees patients, the coming
  /// days there with how many times are free, and the chosen day's free times.
  List<Map<String, dynamic>> _places = const [];
  List<Map<String, dynamic>> _days = const [];
  String? _locId;
  String? _date;
  bool _online = true;
  bool _loadingTimes = false;

  Map<String, dynamic> get _place => _places.firstWhere((p) => p.str('locationId') == _locId, orElse: () => const {});

  static List<String> _slotsFor(_Doc d) {
    final first = d.next.replaceAll(' · video', '');
    if (d.today) return [first, 'Tomorrow, 10:30 AM', 'Tomorrow, 6:00 PM'];
    return [first, 'Sat, 10 Oct · 11:00 AM', 'Mon, 12 Oct · 5:30 PM'];
  }

  @override
  void initState() {
    super.initState();
    if (_live) _load(locationId: widget.doc.locationId);
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  /// Loads the places, days and times; [locationId] / [date] pick what to show.
  Future<void> _load({String? locationId, String? date}) async {
    setState(() => date == null ? _loadingSlots = true : _loadingTimes = true);
    final here = await Where.here(ask: false).timeout(const Duration(seconds: 2), onTimeout: () => null);
    try {
      final res = (await Api.I.get('/api/patient/doctors/${widget.doc.id}/booking', query: {
        if (locationId != null) 'locationId': locationId,
        if (date != null) 'date': date,
        if (here != null) 'lat': '${here.lat}',
        if (here != null) 'lng': '${here.lng}',
      }) as Map)
          .cast<String, dynamic>();
      if (!mounted) return;
      final labels = <String>[];
      _startAt.clear();
      for (final s in res.list('slots')) {
        final at = F.date(s['startAt']);
        if (at == null) continue;
        final label = F.when(at);
        _startAt[label] = s.str('startAt');
        labels.add(label);
      }
      setState(() {
        _places = res.list('places');
        _days = res.list('days');
        _locId = res.str('locationId');
        _date = res['date'] as String?;
        _online = res['online'] != false;
        _slots = labels;
        _slot = labels.isEmpty ? null : labels.first;
        _loadingSlots = false;
        _loadingTimes = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSlots = false;
        _loadingTimes = false;
      });
      // An older server without the booking call: the next three times, as before.
      if (e.status == 404 && _places.isEmpty && widget.doc.locationId != null) return _loadSlots();
      toast(context, e.message);
    }
  }

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// A day picked from the calendar beyond the online-booking window (or not open
  /// online): sent as a request for that day; the clinic confirms a time.
  DateTime? _laterDate;

  /// "More dates": any day in the next 3 months.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      initialDate: _laterDate ?? DateTime.tryParse(_date ?? '') ?? today,
      helpText: tr(context, 'Pick a day'),
    );
    if (picked == null || !mounted) return;
    final key = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    final inStrip = _days.where((x) => x.str('date') == key).firstOrNull;
    if (inStrip != null && inStrip.numOr('free') > 0) {
      setState(() => _laterDate = null);
      await _load(locationId: _locId, date: key);
      return;
    }
    // Full / closed, or beyond what's open online: a request for that day.
    setState(() {
      _laterDate = picked;
      _slot = null;
    });
  }

  Widget _moreDates() => Semantics(
        button: true,
        label: 'More dates',
        child: P2Box(
          onTap: _pickDate,
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          radius: 14,
          color: _laterDate != null ? MP.primarySoft : MP.white,
          border: _laterDate != null ? MP.primary : MP.lineStrong,
          borderWidth: _laterDate != null ? 1.5 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Ico(I.calendar, size: 22, color: MP.primary),
              const Gap(6),
              Text(_laterDate == null ? 'More' : '${_laterDate!.day} ${_monthShort(_laterDate!)}', style: tx(12, w: w700, c: MP.primary)),
              Text(_laterDate == null ? 'dates' : 'request', style: tx(11, c: MP.ink3)),
            ],
          ),
        ),
      );

  Widget _dayTile(Map<String, dynamic> d) {
    final at = DateTime.tryParse(d.str('date'));
    if (at == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final free = d.numOr('free').toInt();
    final on = d.str('date') == _date && _laterDate == null;
    final top = F.sameDay(at, now) ? 'Today' : F.sameDay(at, now.add(const Duration(days: 1))) ? 'Tmrw' : _wd[at.weekday - 1];
    final sub = free > 0 ? '$free free' : d.str('reason') == 'full' ? 'Full' : 'Closed';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: free > 0 ? 1 : 0.5,
        child: P2Box(
          onTap: free > 0 && !on
              ? () {
                  setState(() => _laterDate = null);
                  _load(locationId: _locId, date: d.str('date'));
                }
              : null,
          label: '${F.dateLong(at)} · $sub',
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          radius: 14,
          color: on ? MP.primarySoft : MP.white,
          border: on ? MP.primary : MP.lineStrong,
          borderWidth: on ? 1.5 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(top, style: tx(12, w: w600, c: on ? MP.primary : MP.ink2)),
              const Gap(2),
              Text('${at.day}', style: tx(20, w: w700, c: on ? MP.primary : MP.ink, tab: true)),
              Text(_monthShort(at), style: tx(11, c: on ? MP.primary : MP.ink3)),
              const Gap(4),
              Text(sub, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: tx(11, w: w600, c: free > 0 ? MP.green : MP.ink3)),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthShort(DateTime d) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1];

  /// The chosen day's free times, by part of the day.
  Widget _times() {
    if (_loadingTimes) {
      return const SizedBox(height: 44, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary))));
    }
    if (_slots.isEmpty) {
      return Text('No free times on this day. Pick another day, or send a request and the clinic will suggest a time.', style: tx(14, c: MP.ink2, h: 1.45));
    }
    final groups = <String, List<String>>{};
    for (final s in _slots) {
      final h = F.date(_startAt[s])?.hour ?? 12;
      groups.putIfAbsent(h < 12 ? 'Morning' : h < 17 ? 'Afternoon' : 'Evening', () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups.entries) ...[
          if (groups.length > 1) Padding(padding: const EdgeInsets.only(bottom: 6, top: 4), child: Text(g.key, style: tx(13, c: MP.ink3))),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in g.value)
                MpChip(F.time(F.date(_startAt[s])!), selected: _slot == s, tonal: true, onTap: () => setState(() => _slot = s)),
            ],
          ),
          const Gap(8),
        ],
      ],
    );
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    try {
      final res = await Api.I.get(
        '/api/patient/doctors/${widget.doc.id}/slots',
        query: {'locationId': widget.doc.locationId, 'next': 3},
      );
      if (!mounted) return;
      final labels = <String>[];
      for (final s in (res as Map).cast<String, dynamic>().list('slots')) {
        final at = F.date(s['startAt']);
        if (at == null) continue;
        final label = F.when(at);
        _startAt[label] = s.str('startAt');
        labels.add(label);
      }
      setState(() {
        _slots = labels;
        _slot = labels.isEmpty ? null : labels.first;
        _loadingSlots = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingSlots = false);
      toast(context, e.message);
    }
  }

  Future<void> _request() async {
    final d = widget.doc;
    if (!_live) {
      Navigator.pop(context, _slot);
      return;
    }
    final slot = _slot;
    final res = await runAction(
      context,
      () => Api.I.post('/api/patient/visit-requests', {
        'doctorId': d.id,
        if ((_locId ?? d.locationId) != null) 'locationId': _locId ?? d.locationId,
        'visitType': d.mine ? 'follow_up' : 'new',
        'mode': 'in_clinic',
        if (slot != null && _laterDate == null) 'slot': _startAt[slot],
        if (_laterDate != null) 'preferredTime': '${F.dateLong(_laterDate!)} · any time',
        if (slot == null && _laterDate == null) 'preferredTime': 'Any time the clinic suggests',
      }),
      busy: _busy,
    );
    if (res is! Map || !mounted) return;
    final appt = (res['appointment'] as Map?)?.cast<String, dynamic>();
    final token = appt?['tokenNo'];
    // Booked with a fee: pay now in the app, or at the clinic (kept, so the desk knows to collect it).
    var payNote = '';
    if (appt != null && (appt['fee'] as num? ?? 0) > 0 && appt['feeStatus'] == 'pending') {
      final id = '${appt['id'] ?? appt['_id']}';
      final paid = await Checkout.pay(context, kind: 'fee', id: id, laterLabel: 'Pay at the clinic', optional: true);
      if (!mounted) return;
      if (paid) {
        payNote = ' · Paid';
      } else {
        await Api.I.post('/api/patient/appointments/$id/pay-at-clinic', const {}).catchError((_) => null);
        if (!mounted) return;
        payNote = ' · Pay ₹${(appt['fee'] as num).round()} at the clinic';
      }
    }
    Navigator.pop(
      context,
      appt != null
          ? 'Visit booked with ${d.name} for $slot${token == null ? '' : ' · Token ${'$token'.padLeft(2, '0')}'}$payNote'
          : 'Request sent to ${d.name}${_laterDate != null ? ' for ${F.dateLong(_laterDate!)}' : slot == null ? '' : ' for $slot'}. The clinic will confirm.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final showPage = widget.showPage ?? d.name == 'Dr. Arjun Sen';
    final where = [d.clinic, d.area].where((x) => x.isNotEmpty).join(', ');
    return MpSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocAvatar(d, size: 64),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(d.name, style: tx(20, w: w700, h: 1.25))),
                        const Gap(6),
                        const Svg(I.verifiedSvg, width: 18, height: 18),
                      ],
                    ),
                    const Gap(2),
                    Text(d.title, style: tx(15, c: MP.ink2, h: 1.4)),
                    if (d.years != null) Text('${d.years} years of practice', style: tx(13, c: MP.ink3, h: 1.4)),
                  ],
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: OverflowBox(
                  alignment: Alignment.bottomLeft,
                  minWidth: 44,
                  maxWidth: 44,
                  minHeight: 44,
                  maxHeight: 44,
                  child: MpIconButton(I.close, label: 'Close', color: MP.ink2, onTap: () => Navigator.pop(context)),
                ),
              ),
            ],
          ),
          if (d.about.isNotEmpty && d.about.trim() != d.title.trim()) ...[
            const Gap(14),
            Text(d.about, style: tx(15, h: 1.5)),
          ],
          const Gap(14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: MP.bg, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                MpKV(
                  'Clinic',
                  _place.isEmpty
                      ? where
                      : [_place.str('name'), if (!_place.str('name').toLowerCase().contains(_place.str('area').toLowerCase())) _place.str('area')]
                          .where((x) => x.isNotEmpty)
                          .join(', '),
                ),
                if ((_place.isEmpty ? d.km : (_place['km'] as num?)?.toDouble()) case final km?) ...[
                  const MpDivider(),
                  MpKV('Distance', km < 0.05 ? 'Right here' : '${distanceLabel(km)} from you'),
                ],
                if (d.langs.isNotEmpty) ...[
                  const MpDivider(),
                  MpKV('Speaks', d.langs.join(', ')),
                ],
                const MpDivider(),
                MpKV('Consult fee', _place['fee'] is num ? ((_place['fee'] as num) == 0 ? 'Free' : '₹${(_place['fee'] as num).toInt()}') : d.feeText),
              ],
            ),
          ),
          if (_places.length > 1) ...[
            const Gap(18),
            Text('Where', style: tx(14, w: w600)),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _places)
                  MpChip(
                    [p.str('name'), if (p['km'] is num) distanceLabel((p['km'] as num).toDouble())].join(' · '),
                    selected: p.str('locationId') == _locId,
                    tonal: true,
                    onTap: p.str('locationId') == _locId || _loadingSlots ? null : () => _load(locationId: p.str('locationId')),
                  ),
              ],
            ),
          ],
          if (_live && _days.isNotEmpty && !_loadingSlots) ...[
            const Gap(18),
            Text('Pick a day', style: tx(14, w: w600)),
            const Gap(8),
            SizedBox(
              height: 96,
              child: ListView(scrollDirection: Axis.horizontal, children: [for (final d in _days) _dayTile(d), _moreDates()]),
            ),
          ],
          const Gap(18),
          Text('Pick a time', style: tx(14, w: w600)),
          const Gap(8),
          if (_live && !_online && !_loadingSlots)
            Text('This clinic takes bookings by phone or at the desk. Send a request and they will suggest a time.', style: tx(14, c: MP.ink2, h: 1.45))
          else if (_live && _laterDate != null)
            Text(
              tr(context, 'Online booking is open for the next #1 days. Send a request for #2 and the clinic will confirm a time.')
                  .replaceFirst('#1', '${_days.length}')
                  .replaceFirst('#2', F.dateLong(_laterDate!)),
              style: tx(14, c: MP.ink2, h: 1.45),
            )
          else if (_live && _days.isNotEmpty && !_loadingSlots)
            _times()
          else if (_loadingSlots)
            const SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MP.primary)),
              ),
            )
          else if (_slots.isEmpty)
            Text(
              'No online times in the next two weeks. Send a request and the clinic will suggest a time.',
              style: tx(14, c: MP.ink2, h: 1.45),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _slots)
                  MpChip(s, selected: _slot == s, tonal: true, onTap: () => setState(() => _slot = s)),
              ],
            ),
          const Gap(20),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, __) => MpButton(
              busy ? 'Sending…' : 'Request visit',
              onTap: busy || _loadingSlots ? null : _request,
            ),
          ),
          if (showPage) ...[
            const Gap(10),
            MpButton('Open doctor page', kind: MpBtn.secondary, onTap: () => Navigator.pop(context, '__page')),
          ],
          const Gap(10),
          Text(
            'The clinic confirms the time. You can chat with the doctor once the visit is booked.',
            textAlign: TextAlign.center,
            style: tx(12, c: MP.ink3, h: 1.4),
          ),
        ],
      ),
    );
  }
}
